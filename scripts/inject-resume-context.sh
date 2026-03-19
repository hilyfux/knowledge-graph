#!/bin/bash
# inject-resume-context.sh — SessionStart(resume)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
REPORTED="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl.reported"

# Check both current and reported changelog (startup hook moves it to .reported)
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  SRC="$CHANGELOG"
elif [ -f "$REPORTED" ] && [ -s "$REPORTED" ]; then
  SRC="$REPORTED"
else
  exit 0
fi

UPDATES=$(tail -5 "$SRC" | jq -r '"- " + .action + ": " + .path' 2>/dev/null)
[ -z "$UPDATES" ] && exit 0

ESCAPED=$(printf '%s' "$(echo -e "[知识图谱] 对话恢复。自上次以来更新的节点：\n$UPDATES")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
exit 0
