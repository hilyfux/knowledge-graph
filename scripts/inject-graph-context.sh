#!/bin/bash
# inject-graph-context.sh — SessionStart(startup|clear)
# Injects changelog report + hot area summary into Claude context
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
CONTEXT=""

# Clean up stale lockfile from failed evolution
rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

# Report evolution updates since last session
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  UPDATES=$(tail -10 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path + " (" + .reason + ")"' 2>/dev/null)
  if [ -n "$UPDATES" ]; then
    CONTEXT="[知识图谱更新报告] 上次会话后自动更新了以下知识节点：\n$UPDATES"
    mv "$CHANGELOG" "${CHANGELOG}.reported" 2>/dev/null
    rm -f "${CHANGELOG}.reported" 2>/dev/null
  fi
fi

# Report hot areas
if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e=="w") | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  if [ -n "$HOT" ]; then
    CONTEXT="$CONTEXT\n[活跃区域] 近期高频变更目录：\n$HOT"
  fi
fi

if [ -n "$CONTEXT" ]; then
  ESCAPED=$(printf '%s' "$(echo -e "$CONTEXT")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
fi

exit 0
