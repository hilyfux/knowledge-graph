#!/bin/bash
# guard.sh — shared env guard + helpers for all kg hook scripts
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

KG_DATA="$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/data"
mkdir -p "$KG_DATA"

json_escape() { printf '%s' "$1" | jq -Rs .; }

emit_hook_context() {
  local event="${2:-SessionStart}"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":$1}}"
}
