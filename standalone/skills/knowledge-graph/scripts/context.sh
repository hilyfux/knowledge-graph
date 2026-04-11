#!/bin/bash
# context.sh — Context injection for session lifecycle events
# Usage: context.sh <startup|resume|compact|subagent|precompact|postcompact>
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$KG_DATA/graph-events.jsonl"
ANALYSIS="$KG_DATA/graph-analysis.json"
CMD="${1:-startup}"

case "$CMD" in

  startup)
    CONTEXT=""
    rm -f "$KG_DATA/.kg-updating" 2>/dev/null
    rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

    # Reset working set + prediction cache for new session
    > "$WS" 2>/dev/null
    > "$PRED_CACHE" 2>/dev/null

    # Knowledge index loaded via @include in .claude/CLAUDE.md (always resident)

    # Auto-trigger: if not initialized or active modules missing CLAUDE.md
    if [ ! -f "$KG_DATA/.initialized" ]; then
      emit_hook_context "$(json_escape '[kg auto-trigger] Project not initialized. Invoke Skill tool (skill: knowledge-graph) to auto-detect and run init.')"
      exit 0
    fi

    # Restore previous session state
    SNAPSHOT="$KG_DATA/work-snapshot.md"
    if [ -f "$SNAPSHOT" ]; then
      SNAP_CONTENT=$(cat "$SNAPSHOT" 2>/dev/null)
      [ -n "$SNAP_CONTENT" ] && CONTEXT="$CONTEXT\n$SNAP_CONTENT"
    fi

    # Auto-update: trigger when active modules lack CLAUDE.md
    if [ -f "$EVENTS" ]; then
      PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)

      # Check if any recently active directories are missing CLAUDE.md
      MISSING_NODES=0
      if [ "$PENDING" -ge 5 ]; then
        ACTIVE_DIRS=$(tail -200 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
          | xargs -I{} dirname {} 2>/dev/null | sort -u | head -10)
        for d in $ACTIVE_DIRS; do
          [ "$d" = "." ] && continue
          [ ! -f "$CLAUDE_PROJECT_DIR/$d/CLAUDE.md" ] && MISSING_NODES=$((MISSING_NODES + 1))
        done
      fi

      if [ "$MISSING_NODES" -gt 0 ]; then
        emit_hook_context "$(json_escape "[kg auto-trigger] $MISSING_NODES active modules lack CLAUDE.md. Invoke Skill tool (skill: knowledge-graph) to auto-detect and run update.")"
        exit 0
      fi
    fi

    # Hot zones from cached analysis
    if [ -f "$ANALYSIS" ]; then
      HOT=$(jq -r '.dirs[:3][] | "  \(.w)次写入 \(.dir)"' "$ANALYSIS" 2>/dev/null)
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
    emit_hook_context "$(json_escape "[知识图谱] 对话恢复。待分析活动：${LINE_COUNT} 条")"
    ;;

  precompact)
    # Save working state before compaction (dirty writeback)
    save_snapshot

    # Tell compactor what to preserve
    WS_SUMMARY=""
    if [ -f "$WS" ] && [ -s "$WS" ]; then
      WS_DIRS=$(ws_top 3)
      [ -n "$WS_DIRS" ] && WS_SUMMARY="活跃模块: $(echo "$WS_DIRS" | tr '\n' '、' | sed 's/、$//')"
    fi
    GUIDE="保留：${WS_SUMMARY:+$WS_SUMMARY; }模块禁忌(## 禁忌)、进行中任务、错误修复"
    emit_hook_context "$(json_escape "$GUIDE")" "PreCompact"
    ;;

  compact)
    # Post-compact context rebuild: inject snapshot + working set rules
    CONTEXT="[上下文已压缩] 工作状态恢复："

    SNAPSHOT="$KG_DATA/work-snapshot.md"
    if [ -f "$SNAPSHOT" ]; then
      SNAP=$(cat "$SNAPSHOT" 2>/dev/null)
      [ -n "$SNAP" ] && CONTEXT="$CONTEXT\n\n$SNAP"
    fi

    WS_RULES=$(inject_working_set_rules 5)
    [ -n "$WS_RULES" ] && CONTEXT="$CONTEXT\n\n[工作集禁忌]$WS_RULES"

    if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
      FAILS=$(tail -100 "$EVENTS" | jq -r 'select(.e == "f") | "- \(.tool): \(.err)"' \
        2>/dev/null | sort -u | head -3)
      [ -n "$FAILS" ] && CONTEXT="$CONTEXT\n\n[近期失败]\n$FAILS"
    fi

    if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
      COMMITS=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -3 --since="2 hours ago" 2>/dev/null)
      [ -n "$COMMITS" ] && CONTEXT="$CONTEXT\n\n[会话提交]\n$COMMITS"
    fi

    emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")"
    ;;

  postcompact)
    if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
      PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
      [ "$PENDING" -ge 5 ] && emit_hook_context "$(json_escape "[知识图谱] 待分析：${PENDING} 条")" "PostCompact"
    fi
    ;;

  subagent)
    CONTEXT=""
    ROOT_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
    if [ -f "$ROOT_CLAUDE" ]; then
      PROHIBITIONS=$(get_prohibitions "$ROOT_CLAUDE" 10)
      [ -n "$PROHIBITIONS" ] && CONTEXT="[项目禁忌]\n$PROHIBITIONS"
    fi

    if [ -f "$WS" ] && [ -s "$WS" ]; then
      WS_DIRS=$(ws_top 3)
      [ -n "$WS_DIRS" ] && CONTEXT="$CONTEXT\n[主会话活跃模块] $(echo "$WS_DIRS" | tr '\n' '、' | sed 's/、$//')"
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
