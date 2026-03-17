#!/bin/bash
# inject-resume-context.sh - SessionStart(resume)
# Report graph changes since last interaction
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
[ ! -f "$CHANGELOG" ] || [ ! -s "$CHANGELOG" ] && exit 0

UPDATES=$(tail -5 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path' 2>/dev/null)
[ -z "$UPDATES" ] && exit 0

ESCAPED=$(echo "[知识图谱] 对话恢复。自上次以来更新的节点：\n$UPDATES" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
exit 0
