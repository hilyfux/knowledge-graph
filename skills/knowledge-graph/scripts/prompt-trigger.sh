#!/bin/bash
# prompt-trigger.sh — UserPromptSubmit hook
# Two triggers:
# 1. First user message in session: if active modules lack knowledge nodes → auto-trigger update
# 2. User explicitly mentions knowledge graph → inject status
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Skip system messages
echo "$PROMPT" | grep -qE '<task-notification>|<system-reminder>|<command-name>' && exit 0

EVENTS="$KG_DATA/graph-events.jsonl"

# Trigger 1: auto-update on first user message if modules need knowledge nodes
# Use a session-scoped marker to fire only once per session
TRIGGER_MARKER="$KG_DATA/.trigger-checked"
if [ ! -f "$TRIGGER_MARKER" ] && [ -f "$KG_DATA/.initialized" ] && [ -f "$EVENTS" ]; then
  touch "$TRIGGER_MARKER" 2>/dev/null
  PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
  if [ "$PENDING" -ge 5 ]; then
    MISSING=0
    for d in $(tail -200 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
      | xargs -I{} dirname {} 2>/dev/null | sort -u | head -10); do
      [ "$d" = "." ] && continue
      has_knowledge_node "$d" || MISSING=$((MISSING + 1))
    done
    if [ "$MISSING" -gt 0 ]; then
      printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[kg auto-trigger] %d active modules lack knowledge nodes (%d events pending). Before starting user task, invoke Skill tool (skill: knowledge-graph) to run auto-update. This takes ~30 seconds and will improve code quality for this session."}}\n' "$MISSING" "$PENDING"
      exit 0
    fi
  fi
fi

# Trigger 2: explicit knowledge graph mention
echo "$PROMPT" | grep -qiE '(知识图谱|knowledge.?graph|/knowledge-graph|kg update|kg status)' || exit 0
[ ! -f "$EVENTS" ] && exit 0
PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
[ "$PENDING" -lt 1 ] && exit 0
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[knowledge-graph] %s events pending"}}\n' "$PENDING"
exit 0
