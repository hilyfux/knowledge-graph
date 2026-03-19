#!/bin/bash
# run-evolution.sh — Spawns claude with the evolution prompt in BACKGROUND
# Returns immediately so the Stop hook doesn't block session exit.
# The .evolving lock file prevents conflicts with the next session.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

PROMPT_FILE="$SCRIPT_DIR/evolution-prompt.md"
[ ! -f "$PROMPT_FILE" ] && exit 0

# Background: don't block session exit
nohup claude -p "$(cat "$PROMPT_FILE")" --allowedTools 'Read,Write,Edit,Glob,Grep,Bash(*)' >/dev/null 2>&1 &

exit 0
