#!/bin/bash
# on-stop.sh — Stop hook guard + pre-analysis
set -euo pipefail

# Workspace guard (skip silently)
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
LOCK="$CLAUDE_PROJECT_DIR/.claude/.evolving"

# Lock file guard (evolution already running)
[ -f "$LOCK" ] && exit 0

# Event count guard (not enough to justify evolution)
[ ! -f "$EVENTS" ] && exit 0
LINE_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
[ "$LINE_COUNT" -lt 5 ] && exit 0

# Pre-compute analysis data so the agent doesn't waste tokens on tool calls
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/pre-analyze.sh" || true

exit 0
