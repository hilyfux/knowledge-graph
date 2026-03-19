#!/bin/bash
# guard.sh — Shared workspace guard for all hook scripts
# Usage: source this file at the top of every script.
# If the workspace is invalid, `exit` terminates the caller (intentional).

# Three-layer guard: unset / HOME / root
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

# Ensure project data space exists (auto-create on first use)
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"

# JSON escape helper — uses jq (already a dependency), no python3 needed
# Usage: json_escape "string with special chars"
json_escape() { printf '%s' "$1" | jq -Rs .; }

# Emit SessionStart hook output. Usage: emit_context "escaped JSON string content"
emit_hook_context() {
  local event="${2:-SessionStart}"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":$1}}"
}
