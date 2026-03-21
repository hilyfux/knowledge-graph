#!/bin/bash
# track-activity.sh — PostToolUse: 记录文件变更/读取事件到 JSONL
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
PREFIX="$CLAUDE_PROJECT_DIR/"
TS=$(date +%s)

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
