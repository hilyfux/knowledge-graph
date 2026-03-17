#!/bin/bash
# track-failure.sh - Records tool failure events
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
TS=$(date +%s)
echo "{\"e\":\"f\",\"tool\":\"$TOOL\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
exit 0
