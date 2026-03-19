#!/bin/bash
# track-failure.sh — PostToolUseFailure: records tool failure events
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
# Truncate error to 100 chars to keep events compact
ERR=$(echo "$INPUT" | jq -r '.error // empty' | head -c 100 | tr '"\\' '..')
TS=$(date +%s)
echo "{\"e\":\"f\",\"tool\":\"$TOOL\",\"err\":\"$ERR\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
exit 0
