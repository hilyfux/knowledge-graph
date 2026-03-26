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
