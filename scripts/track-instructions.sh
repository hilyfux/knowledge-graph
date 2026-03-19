#!/bin/bash
# track-instructions.sh — InstructionsLoaded: records CLAUDE.md load events
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
TS=$(date +%s)

FILES=$(echo "$INPUT" | jq -r '(.loaded_files // [])[], (.file_path // empty)' 2>/dev/null | sort -u)
for f in $FILES; do
  [ -z "$f" ] && continue
  REL="${f#$CLAUDE_PROJECT_DIR/}"
  jq -n --arg e "i" --arg p "$REL" --argjson t "$TS" '{e:$e,p:$p,t:$t}' >> "$EVENTS"
done
exit 0
