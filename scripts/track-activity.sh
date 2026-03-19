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
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"w:new\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Edit)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"w:edit\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Read)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"r\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Glob)
    SPATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty')
    SPATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty')
    SPATH="${SPATH#$CLAUDE_PROJECT_DIR/}"
    echo "{\"e\":\"s\",\"p\":\"$SPATH\",\"q\":\"$SPATTERN\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Grep)
    SPATH=$(echo "$INPUT" | jq -r '.tool_input.path // empty')
    SPATTERN=$(echo "$INPUT" | jq -r '.tool_input.pattern // empty')
    SPATH="${SPATH#$CLAUDE_PROJECT_DIR/}"
    echo "{\"e\":\"s\",\"p\":\"$SPATH\",\"q\":\"$SPATTERN\",\"t\":$TS}" >> "$EVENTS"
    ;;
esac

exit 0
