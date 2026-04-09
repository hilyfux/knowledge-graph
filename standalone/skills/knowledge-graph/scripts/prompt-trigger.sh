#!/bin/bash
# prompt-trigger.sh — UserPromptSubmit hook
# 检测用户消息中的完成/失败信号，通过 additionalContext 注入更新指令
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

# 读取用户消息
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# 过滤非用户消息
echo "$PROMPT" | grep -qE '<task-notification>|<system-reminder>|<command-name>|【kg 自动指令】' && exit 0

# 过滤太短的消息
CLEAN=$(echo "$PROMPT" | sed 's/<[^>]*>//g' | tr -d '[:space:]')
[ ${#CLEAN} -lt 4 ] && exit 0

# 知识图谱未初始化则跳过
EVENTS="$KG_DATA/graph-events.jsonl"
[ ! -f "$EVENTS" ] && exit 0

INJECT=""

# 完成信号（任务阶段性结束）
if echo "$PROMPT" | grep -qiE '(整理(一下|完了?)?|清理(一下|完了?)?|确认(一下|完了?)?|ok了|可以了|搞定了?|行了|没问题了|done了?|完成了)'; then
  PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
  [ "$PENDING" -lt 3 ] && exit 0
  INJECT="【kg 自动指令】检测到阶段性完成信号（${PENDING}条待分析）。请先完成当前所有进行中的任务，全部完成后再调用 Skill tool（skill: knowledge-graph, args: update）固化知识图谱。不要打断正在进行的工作。"
fi

# 失败信号（遇到问题，记录教训）
if [ -z "$INJECT" ] && echo "$PROMPT" | grep -qiE '(还不行|还是不行|不对(啊|呀)?|又(错|报错|失败)了|还是错|仍然不行|没解决)'; then
  INJECT="【kg 自动指令】检测到失败信号。请先完成当前所有进行中的任务，全部完成后再调用 Skill tool（skill: knowledge-graph, args: update）记录教训。不要打断正在进行的工作。"
fi

[ -z "$INJECT" ] && exit 0

# 使用 hookSpecificOutput.additionalContext 注入（Claude Code 原生支持的方式）
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' \
  "$(echo "$INJECT" | sed 's/"/\\"/g')"
exit 0
