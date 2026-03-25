#!/bin/bash
# track-activity.sh — PostToolUse: 记录文件变更/读取事件到 JSONL
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
PREFIX="$CLAUDE_PROJECT_DIR/"
TS=$(date +%s)

cat | jq -c --argjson t "$TS" --arg prefix "$PREFIX" '
  .tool_name as $tool |
  if $tool == "Write" then
    (.tool_input.file_path // empty) | sub($prefix; "") |
    if . != "" then {e:"w:new",p:.,t:$t} else empty end
  elif $tool == "Edit" then
    (.tool_input.file_path // empty) | sub($prefix; "") |
    if . != "" then {e:"w:edit",p:.,t:$t} else empty end
  elif $tool == "Read" then
    (.tool_input.file_path // empty) | sub($prefix; "") |
    if . != "" then {e:"r",p:.,t:$t} else empty end
  elif ($tool == "Glob" or $tool == "Grep") then
    {e:"s", p:((.tool_input.path // "") | sub($prefix; "") | if . == "" then "." else . end), q:(.tool_input.pattern // ""), t:$t}
  else empty end
' >> "$EVENTS" 2>/dev/null

# 里程碑检查：每 15 次写入，block 注入一次更新提醒
COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
if [ "$COUNT" -gt 0 ] && [ "$((COUNT % 15))" -eq 0 ]; then
  # 找出最活跃的目录（最多3个）
  HOT=$(tail -60 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
    | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3 \
    | awk '{print "  " $2 "(" $1 "次)"}' | paste -sd '、' -)
  MSG="[kg] 已积累 ${COUNT} 条变更记录"
  [ -n "$HOT" ] && MSG="${MSG}，活跃区域：${HOT}"
  MSG="${MSG}。建议运行 /knowledge-graph update 同步知识节点。"
  printf '{"decision":"block","reason":"%s"}\n' "$MSG"
fi

exit 0
