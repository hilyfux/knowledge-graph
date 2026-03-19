#!/bin/bash
# run-evolution.sh — Spawns claude with the evolution prompt
# Called by Stop hook after on-stop.sh guard passes.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

PROMPT_FILE="$SCRIPT_DIR/evolution-prompt.md"
[ ! -f "$PROMPT_FILE" ] && exit 1

# Run claude in non-interactive mode with the evolution prompt
claude -p "$(cat "$PROMPT_FILE")" --allowedTools 'Read,Write,Edit,Glob,Grep,Bash(*)' 2>/dev/null

exit 0
