#!/bin/bash
# inject-subagent-context.sh — SubagentStart
# Injects project prohibitions + failure patterns so subagents avoid known mistakes.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CONTEXT=""

# Inject root CLAUDE.md prohibitions (highest value per token)
ROOT_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
if [ -f "$ROOT_CLAUDE" ]; then
  PROHIBITIONS=$(sed -n '/^## 禁忌/,/^## /{ /^## 禁忌/d; /^## /d; p; }' "$ROOT_CLAUDE" 2>/dev/null | head -10)
  [ -n "$PROHIBITIONS" ] && CONTEXT="[项目禁忌]\n$PROHIBITIONS"
fi

# Inject top failure patterns from cached analysis
ANALYSIS="$CLAUDE_PROJECT_DIR/.claude/graph-analysis.json"
if [ -f "$ANALYSIS" ]; then
  ERRORS=$(jq -r '[.dirs[] | select(.f > 0)] | sort_by(-.f) | .[0:3][] | "- \(.dir): \(.top_err)"' "$ANALYSIS" 2>/dev/null)
  [ -n "$ERRORS" ] && CONTEXT="$CONTEXT\n[常见失败]\n$ERRORS"
fi

if [ -n "$CONTEXT" ]; then
  ESCAPED=$(printf '%s' "$(echo -e "$CONTEXT")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"$ESCAPED\"}}"
fi

exit 0
