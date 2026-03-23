#!/bin/bash
# inject-resume-context.sh — SessionStart(resume)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"

[ ! -f "$EVENTS" ] && exit 0

LINE_COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
[ "$LINE_COUNT" -lt 1 ] && exit 0

emit_hook_context "$(json_escape "[知识图谱] 对话恢复。待分析活动：${LINE_COUNT} 条（可运行 /knowledge-graph update 刷新）")"
exit 0
