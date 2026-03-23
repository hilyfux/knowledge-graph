#!/bin/bash
# inject-graph-context.sh — SessionStart(startup|clear)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
ANALYSIS="$CLAUDE_PROJECT_DIR/.claude/graph-analysis.json"
CONTEXT=""

# 清理残留锁文件
rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

# 未初始化提示：events 文件不存在且无任何 CLAUDE.md
if [ ! -f "$EVENTS" ]; then
  if ! find "$CLAUDE_PROJECT_DIR" -maxdepth 3 -name "CLAUDE.md" -not -path "*/.git/*" 2>/dev/null | grep -q .; then
    emit_hook_context "$(json_escape '[知识图谱] 此项目尚未初始化。执行 /knowledge-graph init 开始。')"
    exit 0
  fi
fi

# 1. 热区 + 健康状态
if [ -f "$ANALYSIS" ]; then
  HOT=$(jq -r '.dirs[:3][] | "  \(.w)次写入 \(.dir)"' "$ANALYSIS" 2>/dev/null)
  BROKEN=$(jq -r '.broken_refs[]' "$ANALYSIS" 2>/dev/null)
  [ -n "$HOT" ] && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
  [ -n "$BROKEN" ] && CONTEXT="$CONTEXT\n[断裂引用]\n$BROKEN"
elif [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  [ -n "$HOT" ] && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
fi

# 3. Git 摘要
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  GIT=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -5 2>/dev/null)
  [ -n "$GIT" ] && CONTEXT="$CONTEXT\n[最近提交]\n$GIT"
fi

[ -n "$CONTEXT" ] && emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")"
exit 0
