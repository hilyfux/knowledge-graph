#!/bin/bash
# on-compact.sh — SessionStart(compact)：上下文压缩后注入工作摘要
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
CONTEXT="[上下文已压缩] 工作摘要："

if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  SUMMARY=$(tail -200 "$EVENTS" | jq -sr '
    [.[] | select(.e | startswith("w")) | .p | split("/") | if length > 1 then .[:-1] | join("/") else "." end] | group_by(.) | map({dir: .[0], n: length}) | sort_by(-.n) | .[0:5][] | "- \(.dir) (\(.n)次写入)"
  ' 2>/dev/null)
  [ -n "$SUMMARY" ] && CONTEXT="$CONTEXT\n\n活跃目录：\n$SUMMARY"

  FAILS=$(tail -200 "$EVENTS" | jq -r 'select(.e == "f") | "- \(.tool): \(.err)"' 2>/dev/null | sort -u | head -3)
  [ -n "$FAILS" ] && CONTEXT="$CONTEXT\n\n近期失败：\n$FAILS"

  ACTIVE_DIRS=$(tail -200 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p | split("/") | if length > 1 then .[:-1] | join("/") else "." end' 2>/dev/null | sort -u)
fi

if [ -n "$ACTIVE_DIRS" ]; then
  for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -10); do
    REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
    DIR=$(dirname "$REL")
    if echo "$ACTIVE_DIRS" | grep -q "^$DIR$"; then
      RULES=$(sed -n '/^## 禁忌/,/^## /{ /^## /d; /^$/d; p; }' "$cmd_file" 2>/dev/null | head -5)
      [ -n "$RULES" ] && CONTEXT="$CONTEXT\n\n$DIR 禁忌：\n$RULES"
    fi
  done
fi

if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  COMMITS=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -3 --since="2 hours ago" 2>/dev/null)
  [ -n "$COMMITS" ] && CONTEXT="$CONTEXT\n\n会话提交：\n$COMMITS"
fi

emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")"
exit 0
