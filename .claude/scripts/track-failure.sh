#!/bin/bash
# track-failure.sh — PostToolUseFailure: 记录工具失败事件
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

TS=$(date +%s)
cat | jq -c --argjson t "$TS" '
  {e:"f", tool:(.tool_name // ""), err:((.error // "")[0:100] | gsub("\n"; " ")), t:$t}
' >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl" 2>/dev/null

exit 0
