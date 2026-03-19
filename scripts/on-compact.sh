#!/bin/bash
# on-compact.sh — SessionStart(compact)
# Critical moment: AI just lost all accumulated context.
# Inject a working summary so it can resume without re-reading everything.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
CONTEXT="[上下文已压缩] 以下是压缩前的工作摘要："

# 1. What was being worked on (recent write targets)
if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  # Active directories (where writes happened)
  ACTIVE=$(tail -200 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -5 | awk '{print "- " $2 " (" $1 "次写入)"}')
  [ -n "$ACTIVE" ] && CONTEXT="$CONTEXT\n\n活跃目录：\n$ACTIVE"

  # Recent failures (things to avoid)
  FAILS=$(tail -200 "$EVENTS" | jq -r 'select(.e == "f") | "- \(.tool): \(.err)"' 2>/dev/null | sort -u | head -3)
  [ -n "$FAILS" ] && CONTEXT="$CONTEXT\n\n近期失败（避免重复）：\n$FAILS"
fi

# 2. Inject prohibitions for active directories
for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -10); do
  REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
  DIR=$(dirname "$REL")
  # Only inject if this directory was active
  if [ -f "$EVENTS" ] && tail -200 "$EVENTS" | jq -e --arg d "$DIR" 'select(.p != null) | select(.p | startswith($d))' &>/dev/null; then
    RULES=$(sed -n '/^## 禁忌/,/^## /{ /^## /d; /^$/d; p; }' "$cmd_file" 2>/dev/null | head -5)
    [ -n "$RULES" ] && CONTEXT="$CONTEXT\n\n$DIR 禁忌：\n$RULES"
  fi
done

# 3. Recent git commits (what was accomplished)
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  COMMITS=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -3 --since="2 hours ago" 2>/dev/null)
  [ -n "$COMMITS" ] && CONTEXT="$CONTEXT\n\n本次会话提交：\n$COMMITS"
fi

ESCAPED=$(printf '%s' "$(echo -e "$CONTEXT")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
exit 0
