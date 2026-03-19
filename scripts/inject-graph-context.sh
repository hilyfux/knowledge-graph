#!/bin/bash
# inject-graph-context.sh — SessionStart(startup|clear)
# Injects rich context: changelog + hot areas + git summary + health warnings
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
CONTEXT=""

# Clean up stale lockfile from failed evolution
rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

# 1. Report evolution updates since last session
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  UPDATES=$(tail -10 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path + " (" + .reason + ")"' 2>/dev/null)
  if [ -n "$UPDATES" ]; then
    CONTEXT="[知识图谱更新报告] 上次会话后自动更新了以下知识节点：\n$UPDATES"
    mv "$CHANGELOG" "${CHANGELOG}.reported" 2>/dev/null
  fi
fi

# 2. Report hot areas from events
if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  if [ -n "$HOT" ]; then
    CONTEXT="$CONTEXT\n[活跃区域] 近期高频变更目录：\n$HOT"
  fi
fi

# 3. Git recent activity summary (last 5 commits, quick context)
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  GIT_SUMMARY=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -5 2>/dev/null)
  if [ -n "$GIT_SUMMARY" ]; then
    CONTEXT="$CONTEXT\n[最近提交]\n$GIT_SUMMARY"
  fi

  # Co-change hint: files that changed together in last 10 commits
  COCHANGE=$(git -C "$CLAUDE_PROJECT_DIR" log --pretty=format: --name-only -10 2>/dev/null | sort | uniq -c | sort -rn | head -5 | grep -v '^\s*$')
  if [ -n "$COCHANGE" ]; then
    CONTEXT="$CONTEXT\n[高频变更文件]\n$COCHANGE"
  fi
fi

# 4. Knowledge health warnings
WARNINGS=""
# Check for broken @ references in CLAUDE.md files
for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
  REFS=$(grep -oP '@\S+CLAUDE\.md' "$cmd_file" 2>/dev/null)
  for ref in $REFS; do
    REF_PATH="${ref#@}"
    FULL_PATH="$(dirname "$cmd_file")/$REF_PATH"
    if [ ! -f "$FULL_PATH" ]; then
      REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
      WARNINGS="$WARNINGS\n- 断裂引用: $REL 中 $ref 指向不存在的文件"
    fi
  done
done

if [ -n "$WARNINGS" ]; then
  CONTEXT="$CONTEXT\n[知识健康警告]$WARNINGS"
fi

if [ -n "$CONTEXT" ]; then
  ESCAPED=$(printf '%s' "$(echo -e "$CONTEXT")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
fi

exit 0
