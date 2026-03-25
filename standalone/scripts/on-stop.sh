#!/bin/bash
# on-stop.sh — Stop hook: auto-run pre-analyze.sh when events >= threshold.
# No LLM calls. Produces graph-analysis.json for next session's inject-graph-context.

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
[ ! -f "$EVENTS" ] && exit 0

LINE_COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
[ "$LINE_COUNT" -lt 20 ] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Run analysis in background so the hook returns immediately.
# timeout 15s: hard kill if pre-analyze hangs (git/find on large repos).
# disown: detach from shell so it doesn't become a zombie when parent exits.
env CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" timeout 15 bash "$SCRIPT_DIR/pre-analyze.sh" > /dev/null 2>&1 &
disown

exit 0
