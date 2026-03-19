#!/bin/bash
# track-instructions.sh — InstructionsLoaded: records CLAUDE.md load events
# Single jq call for all files.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

TS=$(date +%s)
cat | jq -c --argjson t "$TS" --arg prefix "$CLAUDE_PROJECT_DIR/" '
  [(.loaded_files // [])[], (.file_path // empty)] | unique | .[] |
  select(. != null and . != "") |
  sub($prefix; "") |
  {e:"i", p:., t:$t}
' >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl" 2>/dev/null

exit 0
