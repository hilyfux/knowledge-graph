#!/bin/bash
# context.sh — SessionStart + SubagentStart context injection
# Usage: context.sh <startup|resume|compact|subagent>
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$KG_DATA/graph-events.jsonl"
ANALYSIS="$KG_DATA/graph-analysis.json"
CMD="${1:-startup}"

case "$CMD" in

  startup)
    CONTEXT=""
    # Clean up stale lock files
    rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

    # Knowledge index: inject if available (Karpathy-style index.md)
    INDEX="$CLAUDE_PROJECT_DIR/.claude/knowledge-index.md"
    if [ -f "$INDEX" ]; then
      INDEX_CONTENT=$(cat "$INDEX" 2>/dev/null | head -50)
      [ -n "$INDEX_CONTENT" ] && CONTEXT="$CONTEXT\n[知识索引]\n$INDEX_CONTENT"
    fi

    # Not initialized: no events + no CLAUDE.md anywhere
    if [ ! -f "$EVENTS" ]; then
      if ! find "$CLAUDE_PROJECT_DIR" -maxdepth 3 -name "CLAUDE.md" \
           -not -path "*/.git/*" 2>/dev/null | grep -q .; then
        emit_hook_context "$(json_escape '[知识图谱] 此项目尚未初始化。执行 /knowledge-graph init 开始。')"
        exit 0
      fi
    fi

    # Pending events reminder
    if [ -f "$EVENTS" ]; then
      PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
      [ "$PENDING" -ge 10 ] && CONTEXT="$CONTEXT\n[知识图谱] 已积累 ${PENDING} 条未同步变更，建议运行 /knowledge-graph update"
    fi

    # Hot zones + broken refs from cached analysis
    if [ -f "$ANALYSIS" ]; then
      HOT=$(jq -r '.dirs[:3][] | "  \(.w)次写入 \(.dir)"' "$ANALYSIS" 2>/dev/null)
      BROKEN=$(jq -r '.broken_refs[]' "$ANALYSIS" 2>/dev/null)
      [ -n "$HOT" ]    && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
      [ -n "$BROKEN" ] && CONTEXT="$CONTEXT\n[断裂引用]\n$BROKEN"
    elif [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
      HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
        | xargs dirname 2>/dev/null | sort | uniq -c | sort -rn | head -3)
      [ -n "$HOT" ] && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
    fi

    # Git summary
    if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
      GIT=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -5 2>/dev/null)
      [ -n "$GIT" ] && CONTEXT="$CONTEXT\n[最近提交]\n$GIT"
    fi

    [ -n "$CONTEXT" ] && emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")"
    ;;

  resume)
    [ ! -f "$EVENTS" ] && exit 0
    LINE_COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
    [ "$LINE_COUNT" -lt 1 ] && exit 0
    emit_hook_context "$(json_escape "[知识图谱] 对话恢复。待分析活动：${LINE_COUNT} 条（可运行 /knowledge-graph update 刷新）")"
    ;;

  compact)
    CONTEXT="[上下文已压缩] 工作摘要："
    if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
      SUMMARY=$(tail -200 "$EVENTS" | jq -sr '
        [.[] | select(.e | startswith("w")) | .p |
          split("/") | if length > 1 then .[:-1] | join("/") else "." end] |
        group_by(.) | map({dir: .[0], n: length}) | sort_by(-.n) | .[0:5][] |
        "- \(.dir) (\(.n)次写入)"
      ' 2>/dev/null)
      [ -n "$SUMMARY" ] && CONTEXT="$CONTEXT\n\n活跃目录：\n$SUMMARY"

      FAILS=$(tail -200 "$EVENTS" | jq -r 'select(.e == "f") | "- \(.tool): \(.err)"' \
        2>/dev/null | sort -u | head -3)
      [ -n "$FAILS" ] && CONTEXT="$CONTEXT\n\n近期失败：\n$FAILS"

      ACTIVE_DIRS=$(tail -200 "$EVENTS" | jq -r \
        'select(.e | startswith("w")) | .p | split("/") | if length > 1 then .[:-1] | join("/") else "." end' \
        2>/dev/null | sort -u)
    fi

    if [ -n "$ACTIVE_DIRS" ]; then
      while IFS= read -r cmd_file; do
        REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
        DIR=$(dirname "$REL")
        if echo "$ACTIVE_DIRS" | grep -q "^$DIR$"; then
          RULES=$(sed -n '/^## 禁忌/,/^## /{ /^## /d; /^$/d; p; }' "$cmd_file" 2>/dev/null | head -5)
          [ -n "$RULES" ] && CONTEXT="$CONTEXT\n\n$DIR 禁忌：\n$RULES"
        fi
      done < <(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" \
        -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -10)
    fi

    if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
      COMMITS=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -3 --since="2 hours ago" 2>/dev/null)
      [ -n "$COMMITS" ] && CONTEXT="$CONTEXT\n\n会话提交：\n$COMMITS"
    fi

    emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")"
    ;;

  subagent)
    CONTEXT=""
    ROOT_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
    if [ -f "$ROOT_CLAUDE" ]; then
      PROHIBITIONS=$(sed -n '/^## 禁忌/,/^## /{ /^## 禁忌/d; /^## /d; p; }' \
        "$ROOT_CLAUDE" 2>/dev/null | head -10)
      [ -n "$PROHIBITIONS" ] && CONTEXT="[项目禁忌]\n$PROHIBITIONS"
    fi

    if [ -f "$ANALYSIS" ]; then
      ERRORS=$(jq -r '[.dirs[] | select(.f > 0)] | sort_by(-.f) | .[0:3][] |
        "- \(.dir): \(.top_err)"' "$ANALYSIS" 2>/dev/null)
      [ -n "$ERRORS" ] && CONTEXT="$CONTEXT\n[常见失败]\n$ERRORS"
    fi

    [ -n "$CONTEXT" ] && emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")" "SubagentStart"
    ;;

esac

exit 0
