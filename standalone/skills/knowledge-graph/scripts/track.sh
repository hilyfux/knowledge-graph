#!/bin/bash
# track.sh — PostToolUse/Failure/Instructions event recorder
# Usage: track.sh <write|failure|instructions>
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$KG_DATA/graph-events.jsonl"
TS=$(date +%s)
PREFIX="$CLAUDE_PROJECT_DIR/"
CMD="${1:-write}"

case "$CMD" in

  write)
    # PostToolUse: Write|Edit — record file change event
    cat | jq -c --argjson t "$TS" --arg prefix "$PREFIX" '
      .tool_name as $tool |
      if $tool == "Write" then
        (.tool_input.file_path // empty) | sub($prefix; "") |
        if . != "" then {e:"w:new",p:.,t:$t} else empty end
      elif $tool == "Edit" then
        (.tool_input.file_path // empty) | sub($prefix; "") |
        if . != "" then {e:"w:edit",p:.,t:$t} else empty end
      else empty end
    ' >> "$EVENTS" 2>/dev/null

    # Milestone: every 15 writes → inject auto-update instruction
    COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
    if [ "$COUNT" -gt 0 ] && [ "$((COUNT % 15))" -eq 0 ]; then
      HOT=$(tail -60 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
        | xargs dirname 2>/dev/null | sort | uniq -c | sort -rn | head -3 \
        | awk '{print $2 "(" $1 "次)"}' | paste -sd '、' -)
      MSG="[kg] 已积累 ${COUNT} 条变更记录"
      [ -n "$HOT" ] && MSG="${MSG}，活跃区域：${HOT}"
      MSG="${MSG}。【kg 自动指令】请立即在当前对话中执行知识图谱增量更新：调用 Skill tool（skill: knowledge-graph, args: update），无需等待用户确认，更新完成后继续原任务。"
      printf '{"decision":"block","reason":"%s"}\n' "$MSG"
    fi
    ;;

  failure)
    # PostToolUseFailure — record tool error
    cat | jq -c --argjson t "$TS" '
      {e:"f", tool:(.tool_name // ""), err:((.error // "")[0:100] | gsub("\n"; " ")), t:$t}
    ' >> "$EVENTS" 2>/dev/null
    ;;

  read)
    # PreToolUse: Read — record file read + predictive context injection
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    REL=$(echo "$FILE_PATH" | sed "s|^$PREFIX||")
    # 记录 read 事件
    echo "{\"e\":\"r\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS" 2>/dev/null

    # 预测性上下文注入：基于 co-change 历史，预加载关联模块的 CLAUDE.md
    TARGET_DIR=$(dirname "$REL")
    PREDICTED=$(echo "{\"file_path\":\"$FILE_PATH\"}" | bash "$SCRIPT_DIR/infer.sh" predict 2>/dev/null)
    PRED_DIRS=$(echo "$PREDICTED" | jq -r '.[0:3][] | .dir' 2>/dev/null)
    [ -z "$PRED_DIRS" ] && exit 0

    # 读取关联模块的禁忌，注入为 additionalContext
    CONTEXT=""
    while IFS= read -r pdir; do
      [ -z "$pdir" ] && continue
      CMD_FILE="$CLAUDE_PROJECT_DIR/$pdir/CLAUDE.md"
      [ ! -f "$CMD_FILE" ] && continue
      RULES=$(sed -n '/^## 禁忌/,/^## /{ /^## /d; /^$/d; p; }' "$CMD_FILE" 2>/dev/null | head -3)
      [ -n "$RULES" ] && CONTEXT="${CONTEXT}[${pdir}] ${RULES}\n"
    done <<< "$PRED_DIRS"

    if [ -n "$CONTEXT" ]; then
      ESCAPED=$(printf '%s' "$CONTEXT" | sed 's/"/\\"/g' | tr '\n' ' ')
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[预测关联] %s"}}\n' "$ESCAPED"
    fi
    ;;

  instructions)
    # InstructionsLoaded — record which CLAUDE.md was loaded
    cat | jq -c --argjson t "$TS" --arg prefix "$PREFIX" '
      [(.loaded_files // [])[], (.file_path // empty)] | unique | .[] |
      select(. != null and . != "") |
      sub($prefix; "") |
      {e:"i", p:., t:$t}
    ' >> "$EVENTS" 2>/dev/null
    ;;

esac

exit 0
