#!/usr/bin/env bash
# Stop hook: trigger knowledge graph evolution via claude subagent
# This script acts as a guard — only spawns the agent if conditions are met.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
LOCK_FILE="$PROJECT_DIR/.claude/.evolving"
EVENTS_FILE="$PROJECT_DIR/.claude/graph-events.jsonl"

# Prevent recursive evolution
if [ -f "$LOCK_FILE" ]; then
  exit 0
fi

# Skip if no events or fewer than 5 lines
if [ ! -f "$EVENTS_FILE" ]; then
  exit 0
fi

LINE_COUNT=$(wc -l < "$EVENTS_FILE" | tr -d ' ')
if [ "$LINE_COUNT" -lt 5 ]; then
  exit 0
fi

# All conditions met — the agent hook prompt will handle the rest
# Output a message so the agent hook knows to proceed
echo "graph-events has $LINE_COUNT entries, evolution conditions met"
