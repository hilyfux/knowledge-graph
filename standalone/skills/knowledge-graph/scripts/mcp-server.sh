#!/bin/bash
# mcp-server.sh — MCP stdio server for knowledge graph (v2)
# Exposes tools + resources over JSON-RPC 2.0 so any MCP-aware agent
# (Claude Code, Codex, Cursor, …) can consume the knowledge graph.
#
# Usage: registered in .mcp.json as
#   {"command":"bash","args":["path/to/mcp-server.sh"]}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="1.2.2"

# ── Project-dir resolution ────────────────────────────────────────────────────
# Priority: CLAUDE_PROJECT_DIR env > walk up from script dir > $PWD (warn).
# Codex / non-Claude agents may not set CLAUDE_PROJECT_DIR, so the fallback
# has to be reliable.
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  d="$SCRIPT_DIR"
  while [ "$d" != "/" ]; do
    if [ -d "$d/.knowledge-graph" ]; then PROJECT_DIR="$d"; break; fi
    d="$(dirname "$d")"
  done
fi
if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(pwd)"
  echo "[mcp-server] warning: CLAUDE_PROJECT_DIR unset and no .knowledge-graph/ found up-tree; falling back to PWD=$PROJECT_DIR" >&2
fi
export CLAUDE_PROJECT_DIR="$PROJECT_DIR"

KG_DATA="$PROJECT_DIR/.knowledge-graph"
EVENTS="$KG_DATA/graph-events.jsonl"
ANALYSIS="$KG_DATA/graph-analysis.json"
INDEX="$KG_DATA/knowledge-index.md"
SNAPSHOT="$KG_DATA/work-snapshot.md"

# ── JSON-RPC helpers ──────────────────────────────────────────────────────────
send_response() {
  local id="$1" result="$2"
  printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$id" "$result"
}

send_error() {
  local id="$1" code="$2" msg="$3"
  jq -nc --argjson id "$id" --argjson code "$code" --arg msg "$msg" \
    '{"jsonrpc":"2.0","id":$id,"error":{"code":$code,"message":$msg}}'
}

send_text_response() {
  local id="$1" text="$2"
  jq -nc --argjson id "$id" --arg text "$text" \
    '{"jsonrpc":"2.0","id":$id,"result":{"content":[{"type":"text","text":$text}]}}'
}

# ── Domain error codes (reserved range -32100 to -32199 per MCP convention) ───
# -32100 missing required argument, -32101 empty argument, -32102 not found,
# -32103 not initialized, -32104 invalid input shape
err_missing_arg()    { send_error "$1" -32100 "Missing required argument: $2"; }
err_empty_arg()      { send_error "$1" -32101 "Argument must not be empty: $2"; }
err_not_found()      { send_error "$1" -32102 "$2"; }
err_not_initialized(){ send_error "$1" -32103 "Knowledge graph not initialized. Run /knowledge-graph init first."; }

# ── Resource URI helpers ──────────────────────────────────────────────────────
# kg://node/<rel-path>   → <rel-path>/CLAUDE.md  (e.g. kg://node/bin → bin/CLAUDE.md)
# kg://node/root         → CLAUDE.md (project root)
# kg://index             → .knowledge-graph/knowledge-index.md
# kg://snapshot          → .knowledge-graph/work-snapshot.md
uri_to_path() {
  case "$1" in
    kg://node/root)    echo "$PROJECT_DIR/CLAUDE.md" ;;
    kg://node/*)       echo "$PROJECT_DIR/${1#kg://node/}/CLAUDE.md" ;;
    kg://skill/*)      echo "$PROJECT_DIR/${1#kg://skill/}/SKILL.md" ;;
    kg://index)        echo "$INDEX" ;;
    kg://snapshot)     echo "$SNAPSHOT" ;;
    *)                 echo "" ;;
  esac
}

# ── Handlers ──────────────────────────────────────────────────────────────────
handle_initialize() {
  local id="$1"
  send_response "$id" "{
    \"protocolVersion\":\"2024-11-05\",
    \"capabilities\":{\"tools\":{},\"resources\":{\"listChanged\":false}},
    \"serverInfo\":{\"name\":\"knowledge-graph\",\"version\":\"$VERSION\"}
  }"
}

handle_tools_list() {
  local id="$1"
  send_response "$id" '{
    "tools":[
      {
        "name":"kg_status",
        "description":"Project health report: coverage (CLAUDE.md count), pending events, last analysis time, top hot zones, blind-spot count, recent failures. Use this as the first call to check whether the knowledge graph is healthy and worth querying.",
        "inputSchema":{"type":"object","properties":{},"required":[]}
      },
      {
        "name":"kg_query",
        "description":"Full-text search across all knowledge nodes (CLAUDE.md bodies, not just the tag index). Returns ranked matches with file paths and snippet excerpts. Use this to find prohibitions, conventions, or references for a topic.",
        "inputSchema":{"type":"object","properties":{"question":{"type":"string","description":"Search query (keywords or short phrase)"},"limit":{"type":"integer","description":"Max results to return (default 8)","default":8}},"required":["question"]}
      },
      {
        "name":"kg_read_node",
        "description":"Fetch the full CLAUDE.md (or SKILL.md) of a specific module. Use after kg_query or kg_predict points you at a module path. Accepts a directory path relative to project root (e.g. \"bin\", \"pipeline/patches\"), or \".\" for the root knowledge node.",
        "inputSchema":{"type":"object","properties":{"module_path":{"type":"string","description":"Module directory relative to project root. Use \".\" for the root."}},"required":["module_path"]}
      },
      {
        "name":"kg_predict",
        "description":"Predict related modules for a file path based on co-change history. Returns modules that have historically been modified together with the given file. Use before editing to preload cross-cutting concerns.",
        "inputSchema":{"type":"object","properties":{"file_path":{"type":"string","description":"File path (relative or absolute) to predict relations for"}},"required":["file_path"]}
      },
      {
        "name":"kg_cochange",
        "description":"Top co-change directory pairs from event history. Surfaces implicit dependencies — directories that change together indicate coupling worth knowing about.",
        "inputSchema":{"type":"object","properties":{"limit":{"type":"integer","description":"Max pairs (default 10)","default":10}},"required":[]}
      },
      {
        "name":"kg_recent_work",
        "description":"Return the current work snapshot (active modules, modified files, uncommitted changes, recent failures, recent commits). Use at session start to pick up where the previous session left off.",
        "inputSchema":{"type":"object","properties":{},"required":[]}
      },
      {
        "name":"kg_blind_spots",
        "description":"List modules with significant activity but no CLAUDE.md (needing documentation). Use to identify which parts of the codebase lack knowledge coverage.",
        "inputSchema":{"type":"object","properties":{},"required":[]}
      }
    ]
  }'
}

handle_resources_list() {
  local id="$1"

  # Build resources array: each CLAUDE.md / SKILL.md + index + snapshot
  local resources
  resources=$(
    {
      # Special resources
      [ -f "$INDEX" ] && jq -nc \
        '{uri:"kg://index", name:"Knowledge Index", description:"Pointer index of all knowledge nodes in the project", mimeType:"text/markdown"}'
      [ -f "$SNAPSHOT" ] && jq -nc \
        '{uri:"kg://snapshot", name:"Work Snapshot", description:"Recent work: active modules, uncommitted changes, recent commits", mimeType:"text/markdown"}'

      # Every CLAUDE.md and SKILL.md in the project
      find "$PROJECT_DIR" \( -name "CLAUDE.md" -o -name "SKILL.md" \) \
        -not -path "*/.git/*" -not -path "*/node_modules/*" \
        -not -path "*/.knowledge-graph/*" 2>/dev/null | \
      while IFS= read -r f; do
        local rel dir uri name fname
        rel="${f#$PROJECT_DIR/}"
        dir="$(dirname "$rel")"
        fname="$(basename "$f")"
        if [ "$fname" = "SKILL.md" ]; then
          uri="kg://skill/$dir"
        elif [ "$dir" = "." ]; then
          uri="kg://node/root"
        else
          uri="kg://node/$dir"
        fi
        name="$dir"
        [ "$name" = "." ] && name="(project root)"
        jq -nc --arg uri "$uri" --arg name "$name" --arg rel "$rel" \
          '{uri:$uri, name:$name, description:("Knowledge node: "+$rel), mimeType:"text/markdown"}'
      done
    } | jq -sc '.'
  )
  [ -z "$resources" ] && resources='[]'

  send_response "$id" "{\"resources\":$resources}"
}

handle_resources_read() {
  local id="$1" uri="$2"
  local path
  path=$(uri_to_path "$uri")
  if [ -z "$path" ]; then
    send_error "$id" -32602 "Unsupported URI scheme: $uri"
    return
  fi
  if [ ! -f "$path" ]; then
    err_not_found "$id" "Resource not found: $uri"
    return
  fi
  local content
  content=$(cat "$path" 2>/dev/null || echo "")
  jq -nc --argjson id "$id" --arg uri "$uri" --arg text "$content" \
    '{jsonrpc:"2.0", id:$id, result:{contents:[{uri:$uri, mimeType:"text/markdown", text:$text}]}}'
}

# ── Tool implementations ──────────────────────────────────────────────────────
tool_kg_status() {
  local id="$1"
  local coverage events last hot blind fails
  coverage=$(find "$PROJECT_DIR" \( -name "CLAUDE.md" -o -name "SKILL.md" \) \
    -not -path "*/.git/*" -not -path "*/node_modules/*" \
    -not -path "*/.knowledge-graph/*" 2>/dev/null | wc -l | tr -d ' ')
  events=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
  last="never"
  [ -f "$ANALYSIS" ] && last=$(date -r "$ANALYSIS" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "unknown")

  if [ -f "$ANALYSIS" ]; then
    hot=$(jq -r '.dirs[:3] | map("\(.dir) (w:\(.w) r:\(.r))") | join(", ")' "$ANALYSIS" 2>/dev/null)
    blind=$(jq -r '.blind_spots | length' "$ANALYSIS" 2>/dev/null)
  else
    hot="(no analysis cache)"
    blind="?"
  fi

  if [ -f "$EVENTS" ]; then
    fails=$(tail -200 "$EVENTS" | jq -r 'select(.e=="f") | .err // ""' 2>/dev/null | sort -u | head -3 | sed 's/^/  - /')
  fi

  local text
  text=$(printf "Knowledge Graph Status\n  nodes: %s\n  pending events: %s\n  last analysis: %s\n  blind spots: %s\n  hot zones: %s\n" \
    "$coverage" "$events" "$last" "$blind" "$hot")
  [ -n "${fails:-}" ] && text="$text"$'\n'"recent failures:"$'\n'"$fails"

  send_text_response "$id" "$text"
}

tool_kg_query() {
  local id="$1" args="$2"
  local question limit
  question=$(echo "$args" | jq -r '.question // ""')
  limit=$(echo "$args" | jq -r '.limit // 8')

  if [ -z "$question" ]; then err_empty_arg "$id" "question"; return; fi
  case "$limit" in ''|*[!0-9]*) limit=8 ;; esac

  # Search all CLAUDE.md / SKILL.md bodies, not just the index.
  # Locally disable pipefail: head -n closes the pipe early, which SIGPIPEs
  # upstream grep/find and would otherwise kill the whole server under
  # `set -euo pipefail`.
  local hits
  set +o pipefail
  hits=$(
    find "$PROJECT_DIR" \( -name "CLAUDE.md" -o -name "SKILL.md" \) \
      -not -path "*/.git/*" -not -path "*/node_modules/*" \
      -not -path "*/.knowledge-graph/*" 2>/dev/null | \
    while IFS= read -r f; do
      local rel
      rel="${f#$PROJECT_DIR/}"
      grep -in --color=never -- "$question" "$f" 2>/dev/null | head -3 | \
        while IFS=: read -r lineno excerpt; do
          printf "%s\t%s\t%s\n" "$rel" "$lineno" "$excerpt"
        done
    done | head -n "$limit"
  ) || true
  set -o pipefail

  if [ -z "$hits" ]; then
    send_text_response "$id" "No matches for '$question'. Try /knowledge-graph query for deeper search, or /knowledge-graph update to rebuild."
    return
  fi

  local formatted
  formatted=$(echo "$hits" | awk -F'\t' '{printf "- %s:%s  %s\n", $1, $2, $3}')
  send_text_response "$id" "Matches for '$question':"$'\n'"$formatted"
}

tool_kg_read_node() {
  local id="$1" args="$2"
  local module_path
  module_path=$(echo "$args" | jq -r '.module_path // ""')
  if [ -z "$module_path" ]; then err_empty_arg "$id" "module_path"; return; fi

  local candidate_c candidate_s
  if [ "$module_path" = "." ] || [ "$module_path" = "" ] || [ "$module_path" = "root" ]; then
    candidate_c="$PROJECT_DIR/CLAUDE.md"
    candidate_s="$PROJECT_DIR/SKILL.md"
  else
    candidate_c="$PROJECT_DIR/$module_path/CLAUDE.md"
    candidate_s="$PROJECT_DIR/$module_path/SKILL.md"
  fi

  local path="" which=""
  if [ -f "$candidate_c" ]; then path="$candidate_c"; which="CLAUDE.md"; fi
  [ -z "$path" ] && [ -f "$candidate_s" ] && { path="$candidate_s"; which="SKILL.md"; }

  if [ -z "$path" ]; then
    err_not_found "$id" "No CLAUDE.md or SKILL.md at module: $module_path"
    return
  fi

  local content header
  content=$(cat "$path" 2>/dev/null || echo "")
  header="# Source: $which at $module_path/"
  send_text_response "$id" "$header"$'\n\n'"$content"
}

tool_kg_predict() {
  local id="$1" args="$2"
  local fp predicted
  fp=$(echo "$args" | jq -r '.file_path // ""')
  if [ -z "$fp" ]; then err_empty_arg "$id" "file_path"; return; fi

  predicted=$(jq -nc --arg fp "$fp" '{"file_path":$fp}' | \
    bash "$SCRIPT_DIR/infer.sh" predict 2>/dev/null || echo "[]")

  local formatted
  formatted=$(echo "$predicted" | jq -r '
    if length == 0 then "No predictions (insufficient co-change history or new file)."
    else (map("- \(.dir) (score:\(.score // "?"))") | join("\n"))
    end' 2>/dev/null)
  [ -z "$formatted" ] && formatted="$predicted"
  send_text_response "$id" "Predicted related modules for $fp:"$'\n'"$formatted"
}

tool_kg_cochange() {
  local id="$1" args="$2"
  local limit cochange
  limit=$(echo "$args" | jq -r '.limit // 10')
  case "$limit" in ''|*[!0-9]*) limit=10 ;; esac

  cochange=$(bash "$SCRIPT_DIR/infer.sh" cochange 2>/dev/null || echo "[]")
  local formatted
  formatted=$(echo "$cochange" | jq -r --argjson lim "$limit" '
    if length == 0 then "No co-change pairs yet (need more event history)."
    else (.[:$lim] | map("- \(.a) ↔ \(.b) (\(.count // "?")×)") | join("\n"))
    end' 2>/dev/null)
  [ -z "$formatted" ] && formatted="$cochange"
  send_text_response "$id" "Top co-change pairs:"$'\n'"$formatted"
}

tool_kg_recent_work() {
  local id="$1"
  if [ ! -f "$SNAPSHOT" ]; then
    send_text_response "$id" "No work snapshot yet. Snapshots are written by the Stop hook at the end of a session — run at least one coding turn under Claude Code first."
    return
  fi
  local content
  content=$(cat "$SNAPSHOT" 2>/dev/null || echo "")
  send_text_response "$id" "$content"
}

tool_kg_blind_spots() {
  local id="$1"
  if [ ! -f "$ANALYSIS" ]; then
    send_text_response "$id" "No analysis cache. Run /knowledge-graph update to regenerate, or trigger analyze.sh manually."
    return
  fi
  local list
  list=$(jq -r '.blind_spots | if length == 0 then "(none — all active modules documented)" else (map("- "+.) | join("\n")) end' "$ANALYSIS" 2>/dev/null)
  [ -z "$list" ] && list="(unreadable analysis cache)"
  send_text_response "$id" "Blind spots (active modules lacking CLAUDE.md/SKILL.md):"$'\n'"$list"
}

handle_tool_call() {
  local id="$1" name="$2" args="$3"
  case "$name" in
    kg_status)       tool_kg_status "$id" ;;
    kg_query)        tool_kg_query "$id" "$args" ;;
    kg_read_node)    tool_kg_read_node "$id" "$args" ;;
    kg_predict)      tool_kg_predict "$id" "$args" ;;
    kg_cochange)     tool_kg_cochange "$id" "$args" ;;
    kg_recent_work)  tool_kg_recent_work "$id" ;;
    kg_blind_spots)  tool_kg_blind_spots "$id" ;;
    *)               send_error "$id" -32601 "Unknown tool: $name" ;;
  esac
}

# ── Main loop: dispatch JSON-RPC from stdin ──────────────────────────────────
while IFS= read -r line; do
  [ -z "$line" ] && continue

  PARSED=$(echo "$line" | jq -r '[.method // "", (.id // "null" | tostring)] | join("\t")' 2>/dev/null)
  method=$(printf '%s' "$PARSED" | cut -f1)
  id=$(printf '%s' "$PARSED" | cut -f2)

  case "$method" in
    initialize)
      handle_initialize "$id"
      ;;
    notifications/initialized)
      ;;
    tools/list)
      handle_tools_list "$id"
      ;;
    tools/call)
      tool_name=$(echo "$line" | jq -r '.params.name // ""')
      tool_args=$(echo "$line" | jq -c '.params.arguments // {}')
      handle_tool_call "$id" "$tool_name" "$tool_args"
      ;;
    resources/list)
      handle_resources_list "$id"
      ;;
    resources/read)
      uri=$(echo "$line" | jq -r '.params.uri // ""')
      handle_resources_read "$id" "$uri"
      ;;
    *)
      [ "$id" != "null" ] && send_error "$id" -32601 "Method not found: $method"
      ;;
  esac
done
