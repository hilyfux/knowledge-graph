#!/bin/bash
# on-stop.sh — Stop hook: prints reminder when enough events accumulated.
# No background processes, no LLM calls. User triggers /knowledge-graph update manually.

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
[ ! -f "$EVENTS" ] && exit 0

LINE_COUNT=$(wc -l < "$EVENTS")
[ "$LINE_COUNT" -lt 20 ] && exit 0

echo "[kg] 💡 已积累 $LINE_COUNT 条活动记录，可运行 /knowledge-graph update 更新知识图谱"
exit 0
