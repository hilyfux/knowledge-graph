#!/bin/bash
# inject-subagent-context.sh — SubagentStart
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CONTEXT=""

ROOT_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
if [ -f "$ROOT_CLAUDE" ]; then
  PROHIBITIONS=$(sed -n '/^## 禁忌/,/^## /{ /^## 禁忌/d; /^## /d; p; }' "$ROOT_CLAUDE" 2>/dev/null | head -10)
  [ -n "$PROHIBITIONS" ] && CONTEXT="[项目禁忌]\n$PROHIBITIONS"
fi

ANALYSIS="$CLAUDE_PROJECT_DIR/.claude/graph-analysis.json"
if [ -f "$ANALYSIS" ]; then
  ERRORS=$(jq -r '[.dirs[] | select(.f > 0)] | sort_by(-.f) | .[0:3][] | "- \(.dir): \(.top_err)"' "$ANALYSIS" 2>/dev/null)
  [ -n "$ERRORS" ] && CONTEXT="$CONTEXT\n[常见失败]\n$ERRORS"
fi

[ -n "$CONTEXT" ] && emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")" "SubagentStart"
exit 0
