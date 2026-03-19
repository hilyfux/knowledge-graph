#!/bin/bash
# track-activity.sh — PostToolUse: records file change/read events to JSONL
# Performance budget: < 30ms. Single jq call.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

[ -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" ] && exit 0

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
PREFIX="$CLAUDE_PROJECT_DIR/"
TS=$(date +%s)

# Single jq call: parse input + produce output event
cat | jq -c --argjson t "$TS" --arg prefix "$PREFIX" '
  .tool_name as $tool |
  if $tool == "Write" then
    (.tool_input.file_path // empty) | sub($prefix; "") |
    if . != "" then {e:"w:new",p:.,t:$t} else empty end
  elif $tool == "Edit" then
    (.tool_input.file_path // empty) | sub($prefix; "") |
    if . != "" then {e:"w:edit",p:.,t:$t} else empty end
  elif $tool == "Read" then
    (.tool_input.file_path // empty) | sub($prefix; "") |
    if . != "" then {e:"r",p:.,t:$t} else empty end
  elif ($tool == "Glob" or $tool == "Grep") then
    {e:"s", p:((.tool_input.path // "") | sub($prefix; "") | if . == "" then "." else . end), q:(.tool_input.pattern // ""), t:$t}
  else empty end
' >> "$EVENTS" 2>/dev/null

exit 0
