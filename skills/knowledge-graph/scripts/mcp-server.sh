#!/bin/bash
# mcp-server.sh — Minimal MCP stdio server for knowledge graph
# Exposes query/predict/status as structured tools over JSON-RPC 2.0
# Usage: Add to .mcp.json with {"command":"bash","args":["path/to/mcp-server.sh"]}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve project dir: walk up from script location to find .knowledge-graph/
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
  d="$SCRIPT_DIR"
  while [ "$d" != "/" ]; do
    [ -d "$d/.knowledge-graph" ] && { PROJECT_DIR="$d"; break; }
    d="$(dirname "$d")"
  done
fi
[ -z "$PROJECT_DIR" ] && PROJECT_DIR="$(pwd)"

export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
KG_DATA="$PROJECT_DIR/.knowledge-graph"
EVENTS="$KG_DATA/graph-events.jsonl"

send_response() {
  local id="$1" result="$2"
  printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$id" "$result"
}

send_error() {
  local id="$1" code="$2" msg="$3"
  jq -nc --argjson id "$id" --argjson code "$code" --arg msg "$msg" \
    '{"jsonrpc":"2.0","id":$id,"error":{"code":$code,"message":$msg}}'
}

# Build a text content response with proper JSON escaping
send_text_response() {
  local id="$1" text="$2"
  jq -nc --argjson id "$id" --arg text "$text" \
    '{"jsonrpc":"2.0","id":$id,"result":{"content":[{"type":"text","text":$text}]}}'
}

handle_initialize() {
  local id="$1"
  send_response "$id" '{
    "protocolVersion":"2024-11-05",
    "capabilities":{"tools":{}},
    "serverInfo":{"name":"knowledge-graph","version":"1.2.0"}
  }'
}

handle_tools_list() {
  local id="$1"
  send_response "$id" '{
    "tools":[
      {
        "name":"kg_status",
        "description":"Get knowledge graph health: coverage, blind spots, hot zones",
        "inputSchema":{"type":"object","properties":{},"required":[]}
      },
      {
        "name":"kg_query",
        "description":"Search knowledge graph for module rules, prohibitions, dependencies",
        "inputSchema":{"type":"object","properties":{"question":{"type":"string","description":"Search query"}},"required":["question"]}
      },
      {
        "name":"kg_predict",
        "description":"Predict related modules for a file path based on co-change history",
        "inputSchema":{"type":"object","properties":{"file_path":{"type":"string","description":"File path to predict relations for"}},"required":["file_path"]}
      },
      {
        "name":"kg_cochange",
        "description":"List top co-change file pairs from event history",
        "inputSchema":{"type":"object","properties":{},"required":[]}
      }
    ]
  }'
}

handle_tool_call() {
  local id="$1" name="$2" args="$3"

  case "$name" in
    kg_status)
      local result count events text
      result=$(bash "$SCRIPT_DIR/analyze.sh" quick-status 2>/dev/null || echo "status unavailable")
      count=$(find "$PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
      events=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
      text="$result | CLAUDE.md nodes: $count | pending events: $events"
      send_text_response "$id" "$text"
      ;;

    kg_query)
      local question text
      question=$(echo "$args" | jq -r '.question // ""')
      text="No knowledge index found. Run /knowledge-graph init first."
      if [ -f "$KG_DATA/knowledge-index.md" ]; then
        local matches
        matches=$(grep -iF "$question" "$KG_DATA/knowledge-index.md" 2>/dev/null | head -10 || echo "")
        if [ -n "$matches" ]; then
          text="Matching modules:"$'\n'"$matches"
        else
          text="No modules matching '$question' in index."
        fi
      fi
      send_text_response "$id" "$text"
      ;;

    kg_predict)
      local file_path predicted
      file_path=$(echo "$args" | jq -r '.file_path // ""')
      predicted=$(jq -nc --arg fp "$file_path" '{"file_path":$fp}' | bash "$SCRIPT_DIR/infer.sh" predict 2>/dev/null || echo "[]")
      send_text_response "$id" "$predicted"
      ;;

    kg_cochange)
      local cochange
      cochange=$(bash "$SCRIPT_DIR/infer.sh" cochange 2>/dev/null || echo "[]")
      send_text_response "$id" "$cochange"
      ;;

    *)
      send_error "$id" -32601 "Unknown tool: $name"
      ;;
  esac
}

# Main loop: read JSON-RPC from stdin, dispatch
while IFS= read -r line; do
  [ -z "$line" ] && continue

  # Single jq call to extract all routing fields
  PARSED=$(echo "$line" | jq -r '[.method // "", (.id // "null" | tostring), .params.name // "", (.params.arguments // {} | tostring)] | join("\t")' 2>/dev/null)
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
      tool_name=$(printf '%s' "$PARSED" | cut -f3)
      tool_args=$(echo "$line" | jq -c '.params.arguments // {}')
      handle_tool_call "$id" "$tool_name" "$tool_args"
      ;;
    *)
      [ "$id" != "null" ] && send_error "$id" -32601 "Method not found: $method"
      ;;
  esac
done
