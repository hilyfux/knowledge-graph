#!/bin/bash
# track-failure.sh — PostToolUseFailure: records tool failure events
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
# Truncate error to 100 chars for compact events
ERR=$(echo "$INPUT" | jq -r '.error // empty' | tr '\n' ' ' | head -c 100)
TS=$(date +%s)
jq -n --arg e "f" --arg tool "$TOOL" --arg err "$ERR" --argjson t "$TS" '{e:$e,tool:$tool,err:$err,t:$t}' >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
exit 0
