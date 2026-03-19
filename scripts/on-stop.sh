#!/bin/bash
# on-stop.sh — Stop hook guard + pre-analysis (exit 1 = block agent, exit 0 = allow)
set -euo pipefail

# Workspace guard (fail = block evolution)
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 1
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 1
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 1

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
LOCK="$CLAUDE_PROJECT_DIR/.claude/.evolving"

# Lock file guard (evolution already running)
[ -f "$LOCK" ] && exit 1

# Event count guard (not enough to justify evolution)
[ ! -f "$EVENTS" ] && exit 1
LINE_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
[ "$LINE_COUNT" -lt 5 ] && exit 1

# Pre-compute analysis data so the agent doesn't waste tokens on tool calls
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/pre-analyze.sh" || true

exit 0
