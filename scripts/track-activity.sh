#!/bin/bash
# track-activity.sh — PostToolUse: records file change/read events to JSONL
# Must complete in < 50ms. No heavy processes.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"

# Skip if evolution engine is running
[ -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
TS=$(date +%s)

case "$TOOL" in
  Write)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && jq -n --arg e "w:new" --arg p "$PATH_VAL" --argjson t "$TS" '{e:$e,p:$p,t:$t}' >> "$EVENTS"
    ;;
  Edit)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && jq -n --arg e "w:edit" --arg p "$PATH_VAL" --argjson t "$TS" '{e:$e,p:$p,t:$t}' >> "$EVENTS"
    ;;
  Read)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && jq -n --arg e "r" --arg p "$PATH_VAL" --argjson t "$TS" '{e:$e,p:$p,t:$t}' >> "$EVENTS"
    ;;
  Glob|Grep)
    SPATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty')
    SPATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty')
    SPATH="${SPATH#$CLAUDE_PROJECT_DIR/}"
    [ -z "$SPATH" ] && SPATH="."
    jq -n --arg e "s" --arg p "$SPATH" --arg q "$SPATTERN" --argjson t "$TS" '{e:$e,p:$p,q:$q,t:$t}' >> "$EVENTS"
    ;;
esac

exit 0
