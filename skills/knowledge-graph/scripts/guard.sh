#!/bin/bash
# guard.sh — shared env guard + helpers for all kg hook scripts
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

KG_DATA="$CLAUDE_PROJECT_DIR/.knowledge-graph"
[ -d "$KG_DATA" ] || mkdir -p "$KG_DATA"

# Working set log: full access history (for ws_top, ws_dirty, save_snapshot)
WS="$KG_DATA/working-set.dat"
# Working set index: deduplicated dirs for O(1) paged-in check
WS_READ_SET="$KG_DATA/ws-reads.set"
WS_WRITE_SET="$KG_DATA/ws-writes.set"

# Prediction cache: avoids re-running infer.sh predict for known dirs
# Format: {timestamp}\t{dir}\t{pred1,pred2,...}   (one entry per dir, 300s TTL)
PRED_CACHE="$KG_DATA/pred-cache.dat"
# Mid-session analysis throttle: avoids stale graph-analysis.json during long
# sessions without relying solely on the Stop hook.
ANALYZE_LOCK="$KG_DATA/.analyzing"
ANALYZE_STAMP="$KG_DATA/.last-analyze-trigger"

# ── JSON / Hook helpers ───────────────────────────────────────────────────────
json_escape() { printf '%s' "$1" | jq -Rs .; }

emit_hook_context() {
  local event="${2:-SessionStart}"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":$1}}"
}

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$@"
  else
    "$@"
  fi
}

# ── Working Set ───────────────────────────────────────────────────────────────

ws_touch() {
  # Skip absolute paths (cross-project files that leaked past guards)
  case "$2" in /*) return ;; esac
  local type="${3:-r}"
  printf '%s\t%s\t%s\n' "$1" "$2" "$type" >> "$WS" 2>/dev/null
  # Maintain deduplicated set files for O(1) lookup
  if [ "$type" = "r" ]; then
    grep -qxF "$2" "$WS_READ_SET" 2>/dev/null || echo "$2" >> "$WS_READ_SET"
  else
    grep -qxF "$2" "$WS_WRITE_SET" 2>/dev/null || echo "$2" >> "$WS_WRITE_SET"
  fi
}

# O(1) check: was this dir READ before? (grep on small set file, not full log)
ws_is_paged_in() {
  [ ! -f "$WS_READ_SET" ] && return 1
  grep -qxF "$1" "$WS_READ_SET" 2>/dev/null
}

ws_top() {
  local n="${1:-5}"
  [ ! -f "$WS" ] && return
  awk -F'\t' '{print $2}' "$WS" 2>/dev/null | sort | uniq -c | sort -rn | head -"$n" | awk '{print $2}'
}

ws_dirty() {
  [ ! -f "$WS_WRITE_SET" ] && return
  cat "$WS_WRITE_SET" 2>/dev/null
}

# ── Prediction Cache ──────────────────────────────────────────────────────────

# Outputs predicted dirs (one per line). Returns 1 on miss or expired.
tlb_get() {
  local dir="$1" now="$2"
  [ ! -f "$PRED_CACHE" ] && return 1
  local line
  line=$(awk -F'\t' -v d="$dir" '$2 == d {print; exit}' "$PRED_CACHE" 2>/dev/null)
  [ -z "$line" ] && return 1
  local cached_ts
  cached_ts=$(printf '%s' "$line" | cut -f1)
  [ $((now - cached_ts)) -ge 300 ] && return 1
  printf '%s' "$line" | cut -f3 | tr ',' '\n'
  return 0
}

tlb_set() {
  local ts="$1" dir="$2" preds_csv="$3"
  if [ -f "$PRED_CACHE" ]; then
    awk -F'\t' -v d="$dir" '$2 != d' "$PRED_CACHE" > "$PRED_CACHE.tmp" 2>/dev/null
    mv "$PRED_CACHE.tmp" "$PRED_CACHE" 2>/dev/null
  fi
  printf '%s\t%s\t%s\n' "$ts" "$dir" "$preds_csv" >> "$PRED_CACHE" 2>/dev/null
}

tlb_invalidate() {
  local dir="$1"
  # Skip if file missing or empty
  [ ! -s "$PRED_CACHE" ] && return
  awk -F'\t' -v d="$dir" '$2 != d' "$PRED_CACHE" > "$PRED_CACHE.tmp" 2>/dev/null
  mv "$PRED_CACHE.tmp" "$PRED_CACHE" 2>/dev/null
}

# ── Shared: extract prohibitions from a module CLAUDE.md ──────────────────────
get_prohibitions() {
  local cmd_file="$1" max="${2:-3}"
  [ ! -f "$cmd_file" ] && return
  # macOS sed BRE does not support \|, use -E for extended regex
  sed -nE '/^## (禁忌|Prohibitions|Rules|Constraints)/,/^## /{ /^## /d; /^$/d; p; }' "$cmd_file" 2>/dev/null | head -"$max"
}

# ── Shared: save working state snapshot ───────────────────────────────────────
# Called from Stop hook and PreCompact hook. Single awk pass for module stats.
save_snapshot() {
  local snapshot="$KG_DATA/work-snapshot.md"
  local events="$KG_DATA/graph-events.jsonl"

  # Anti-overwrite: if WS is empty (e.g. a Stop fires right after /clear reset
  # WS, before the new session accumulated activity), don't stomp a richer
  # previous snapshot with a thin one. Keep the rich record until there's
  # real new activity to summarize.
  if [ ! -s "$WS" ] && [ -f "$snapshot" ] && grep -q "^## 活跃模块" "$snapshot" 2>/dev/null; then
    return 0
  fi

  {
    echo "# 工作快照 ($(date '+%m/%d %H:%M'))"

    if [ -f "$WS" ] && [ -s "$WS" ]; then
      # Single awk pass: compute r/w counts for all modules at once
      printf '\n## 活跃模块\n'
      awk -F'\t' '
        {r[$2]+=($3=="r"); w[$2]+=($3=="w"); total[$2]++}
        END {for(d in total) printf "%d\t%s\t%d\t%d\n",total[d],d,r[d],w[d]}
      ' "$WS" 2>/dev/null | sort -rn | head -8 | awk -F'\t' '{printf "- %s (r:%s w:%s)\n",$2,$3,$4}'

      # Dirty modules
      local dirty
      dirty=$(ws_dirty)
      if [ -n "$dirty" ]; then
        printf '\n## 修改的模块\n'
        echo "$dirty" | sed 's/^/- /'
      fi
    elif [ -f "$events" ] && [ -s "$events" ]; then
      # Fallback: derive from events
      local edited
      edited=$(tail -200 "$events" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
        | sort | uniq -c | sort -rn | head -8 | awk '{printf "- %s (%d次)\n", $2, $1}')
      [ -n "$edited" ] && printf '\n## 编辑文件\n%s\n' "$edited"
    fi

    # Uncommitted changes — strongest "work in progress" signal for Claude
    if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
      local dirty_git
      dirty_git=$(git -C "$CLAUDE_PROJECT_DIR" status --porcelain 2>/dev/null \
        | grep -vE '^[ MARCUD?!]{2} (\.knowledge-graph/|\.claude/|\.playwright/)' \
        | grep -vE '^[ MARCUD?!]{2} \.claude/worktrees/' \
        | head -15)
      [ -n "$dirty_git" ] && printf '\n## 未提交变更 (work in progress)\n%s\n' \
        "$(echo "$dirty_git" | sed 's/^/- /')"
    fi

    # Recent failures
    if [ -f "$events" ] && [ -s "$events" ]; then
      local fails active_dirs active_json
      active_dirs=$(ws_top 8)
      active_json=$(printf '%s\n' "$active_dirs" | jq -R . | jq -s . 2>/dev/null)
      [ -z "$active_json" ] && active_json='[]'

      fails=$(tail -200 "$events" | jq -r --argjson dirs "$active_json" '
        [select(.e == "f")
         | . as $f
         | ($f.p // "") as $p
         | ($p | split("/") | if length > 1 then .[:-1] | join("/") else if $p == "" then "" else "." end end) as $dir
         | select($p != "" and ($dirs | index($dir)))
         | "\($p): \($f.err)"
        ] | unique | .[:3][]
      ' 2>/dev/null)

      if [ -z "$fails" ]; then
        fails=$(tail -200 "$events" | jq -r 'select(.e == "f") | if (.p // "") != "" then "\(.p): \(.err)" else "\(.tool): \(.err)" end' 2>/dev/null \
          | sort -u | head -3)
      fi

      [ -n "$fails" ] && printf '\n## 遇到的问题\n%s\n' "$(echo "$fails" | sed 's/^/- /')"
    fi

    # Recent commits
    if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
      local commits
      commits=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -5 --since="2 hours ago" 2>/dev/null)
      [ -n "$commits" ] && printf '\n## 本次提交\n%s\n' "$(echo "$commits" | sed 's/^/- /')"
    fi
  } > "$snapshot"
}

# ── Channels + event schema (v1.3) ────────────────────────────────────────────
# A "channel" is a logical stream of events + snapshot. The default channel
# is the one the hooks use for general work tracking (graph-events.jsonl,
# work-snapshot.md). Named channels let callers (e.g. silly-code's upstream-
# upgrade tracker) maintain their own parallel stream without colliding
# with, or corrupting, the general work snapshot.
#
# Default channel            → graph-events.jsonl + work-snapshot.md
# Named channel "upgrade"    → upgrade-events.jsonl + upgrade-snapshot.md

channel_events_path() {
  local ch=${1:-}
  case "$ch" in
    ''|default|work) echo "$KG_DATA/graph-events.jsonl" ;;
    *)               echo "$KG_DATA/${ch}-events.jsonl" ;;
  esac
}

channel_snapshot_path() {
  local ch=${1:-}
  case "$ch" in
    ''|default|work) echo "$KG_DATA/work-snapshot.md" ;;
    *)               echo "$KG_DATA/${ch}-snapshot.md" ;;
  esac
}

# Event schema (v1):
#   required: e (enum: w:new|w:edit|r|f|i), p (non-empty string), t (number)
#   optional: tool (string), err (string)
# Readers that care about correctness should filter with is_valid_event_line
# or pipe through filter_valid_events. Writers should use log_channel_event
# which validates before appending.

is_valid_event_line() {
  local line=$1
  [ -z "$line" ] && return 1
  printf '%s' "$line" | jq -e '
    (type == "object") and
    has("e") and (.e | type == "string") and (.e | test("^(w:new|w:edit|r|f|i)$")) and
    has("p") and (.p | type == "string") and (.p | length > 0) and
    has("t") and (.t | type == "number")
  ' >/dev/null 2>&1
}

filter_valid_events() {
  # stdin: one JSON per line (possibly malformed)
  # stdout: only lines that pass schema validation
  while IFS= read -r line; do
    if is_valid_event_line "$line"; then
      printf '%s\n' "$line"
    fi
  done
}

log_channel_event() {
  # Usage: log_channel_event <channel> <event_type> <path> [tool] [err]
  # Builds a JSON event, validates, appends to the channel's events file.
  local ch=$1 et=$2 p=$3 tool=${4:-} err=${5:-}
  [ -z "$et" ] || [ -z "$p" ] && return 1
  local ts target event_json
  ts=$(date +%s)
  target=$(channel_events_path "$ch")
  [ -d "$(dirname "$target")" ] || mkdir -p "$(dirname "$target")"
  if [ -n "$tool" ] || [ -n "$err" ]; then
    event_json=$(jq -nc --arg e "$et" --arg p "$p" --argjson t "$ts" \
      --arg tool "$tool" --arg err "$err" \
      '{e:$e, p:$p, t:$t} + (if $tool != "" then {tool:$tool} else {} end) + (if $err != "" then {err:$err} else {} end)')
  else
    event_json=$(jq -nc --arg e "$et" --arg p "$p" --argjson t "$ts" \
      '{e:$e, p:$p, t:$t}')
  fi
  if is_valid_event_line "$event_json"; then
    printf '%s\n' "$event_json" >> "$target"
    return 0
  fi
  return 1
}

# ── Shared: inject working set module prohibitions ────────────────────────────
inject_working_set_rules() {
  local max="${1:-5}"
  local ctx=""
  local dirs
  dirs=$(ws_top "$max")
  [ -z "$dirs" ] && return

  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    local rules
    rules=$(get_prohibitions "$CLAUDE_PROJECT_DIR/$dir/CLAUDE.md" 3)
    [ -n "$rules" ] && ctx="$ctx\n[$dir 禁忌] $rules"
  done <<< "$dirs"

  [ -n "$ctx" ] && printf '%s' "$ctx"
}
