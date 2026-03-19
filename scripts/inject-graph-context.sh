#!/bin/bash
# inject-graph-context.sh — SessionStart(startup|clear)
# Injects context: changelog + hot areas + git summary + health warnings
# Uses cached analysis if available, avoids expensive scans.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
ANALYSIS="$CLAUDE_PROJECT_DIR/.claude/graph-analysis.json"
CONTEXT=""

# Clean up stale lockfile
rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

# 1. Evolution updates
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  UPDATES=$(tail -10 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path + " (" + .reason + ")"' 2>/dev/null)
  if [ -n "$UPDATES" ]; then
    CONTEXT="[知识图谱更新] \n$UPDATES"
    mv "$CHANGELOG" "${CHANGELOG}.reported" 2>/dev/null
  fi
fi

# 2. Hot areas (from cached analysis or events)
if [ -f "$ANALYSIS" ]; then
  HOT=$(jq -r '.dirs[:3][] | "  \(.w)次写入 \(.dir)"' "$ANALYSIS" 2>/dev/null)
  BROKEN=$(jq -r '.broken_refs[]' "$ANALYSIS" 2>/dev/null)
  [ -n "$HOT" ] && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
  [ -n "$BROKEN" ] && CONTEXT="$CONTEXT\n[断裂引用]\n$BROKEN"
elif [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  [ -n "$HOT" ] && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
fi

# 3. Git summary (fast: single git log call)
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  GIT=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -5 2>/dev/null)
  [ -n "$GIT" ] && CONTEXT="$CONTEXT\n[最近提交]\n$GIT"
fi

if [ -n "$CONTEXT" ]; then
  ESCAPED=$(printf '%s' "$(echo -e "$CONTEXT")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
fi

exit 0
