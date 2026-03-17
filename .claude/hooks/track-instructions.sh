#!/bin/bash
# track-instructions.sh - Records CLAUDE.md load events
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
TS=$(date +%s)

# Support both payload formats: loaded_files array or single file_path
FILES=$(echo "$INPUT" | jq -r '(.loaded_files // [])[], (.file_path // empty)' 2>/dev/null | sort -u)
for f in $FILES; do
  [ -z "$f" ] && continue
  REL="${f#$CLAUDE_PROJECT_DIR/}"
  echo "{\"e\":\"i\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS"
done
exit 0
