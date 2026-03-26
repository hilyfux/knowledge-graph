#!/bin/bash
# prompt-trigger.sh — UserPromptSubmit hook
# 检测用户消息中的完成/失败信号，触发知识图谱增量更新
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

# 读取用户消息
PROMPT=$(cat | jq -r '.prompt // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# 知识图谱未初始化则跳过
EVENTS="$KG_DATA/graph-events.jsonl"
[ ! -f "$EVENTS" ] && exit 0

# 完成信号（任务阶段性结束）
if echo "$PROMPT" | grep -qiE '(整理(一下|完了?)?|清理(一下|完了?)?|确认(一下|完了?)?|ok了|可以了|搞定了?|行了|没问题了|done了?|完成了)'; then
  PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
  [ "$PENDING" -lt 3 ] && exit 0  # 变更太少，不值得更新
  MSG="【kg 自动指令】检测到阶段性完成信号。请立即调用 Skill tool（skill: knowledge-graph, args: update）将本轮成果固化到知识图谱，完成后继续响应用户。"
  printf '{"decision":"block","reason":"%s"}\n' "$MSG"
  exit 0
fi

# 失败信号（遇到问题，记录教训）
if echo "$PROMPT" | grep -qiE '(还不行|还是不行|不对(啊|呀)?|又(错|报错|失败)了|还是错|仍然不行|没解决)'; then
  MSG="【kg 自动指令】检测到失败信号。请立即调用 Skill tool（skill: knowledge-graph, args: update）将本轮失败教训记录到知识图谱禁忌，完成后继续响应用户。"
  printf '{"decision":"block","reason":"%s"}\n' "$MSG"
  exit 0
fi

exit 0
