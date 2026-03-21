#!/bin/bash
# guard.sh — 共享 workspace 守卫，所有 hook 脚本 source 此文件
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

json_escape() { printf '%s' "$1" | jq -Rs .; }
emit_hook_context() {
  local event="${2:-SessionStart}"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":$1}}"
}
