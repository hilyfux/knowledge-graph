#!/bin/bash
# run-evolution.sh — Spawns claude with the evolution prompt in BACKGROUND
# Returns immediately so the Stop hook doesn't block session exit.
# The .evolving lock file prevents conflicts with the next session.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

LOCK="$CLAUDE_PROJECT_DIR/.claude/.evolving"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"

# Remove stale lock (older than 30 minutes — means a previous evolution crashed)
if [ -f "$LOCK" ]; then
  find "$CLAUDE_PROJECT_DIR/.claude" -name ".evolving" -mmin +30 -delete 2>/dev/null || true
fi

# Lock guard: evolution already running (or just finished and cleared events)
[ -f "$LOCK" ] && exit 0

# Event count guard: not enough activity to justify evolution
[ ! -f "$EVENTS" ] && exit 0
LINE_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
[ "$LINE_COUNT" -lt 5 ] && exit 0

PROMPT_FILE="$SCRIPT_DIR/evolution-prompt.md"
[ ! -f "$PROMPT_FILE" ] && exit 0

# Create lock BEFORE spawning — prevents track-activity.sh from writing events
# during evolution, and prevents Stop hook re-entry on the evolution process itself
touch "$LOCK"

# Background: don't block session exit
nohup claude -p "$(cat "$PROMPT_FILE")" --allowedTools 'Read,Write,Edit,Glob,Grep,Bash(*)' >/dev/null 2>&1 &

exit 0
