#!/bin/bash
# inject-resume-context.sh — SessionStart(resume)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
REPORTED="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl.reported"

if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  SRC="$CHANGELOG"
elif [ -f "$REPORTED" ] && [ -s "$REPORTED" ]; then
  SRC="$REPORTED"
else
  exit 0
fi

UPDATES=$(tail -5 "$SRC" | jq -r '"- " + .action + ": " + .path' 2>/dev/null)
[ -z "$UPDATES" ] && exit 0

emit_hook_context "$(json_escape "[知识图谱] 对话恢复。更新的节点：
$UPDATES")"
exit 0
