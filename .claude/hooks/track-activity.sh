#!/bin/bash
# track-activity.sh - Records file change/read events to JSONL
# Must complete in < 50ms. No heavy processes.
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"

# Skip sub-agent tool calls (prevents evolution engine recursion)
[ "$(echo "$INPUT" | jq -r '.agent_id // empty')" != "" ] && exit 0

# Fallback anti-loop: skip if evolution engine is running
[ -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
TS=$(date +%s)

case "$TOOL" in
  Write|Edit)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"w\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Read)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"r\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Glob|Grep)
    echo "{\"e\":\"s\",\"t\":$TS}" >> "$EVENTS"
    ;;
esac

exit 0
