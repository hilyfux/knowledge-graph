#!/bin/bash
# prompt-trigger.sh — UserPromptSubmit hook
# Minimal: only inject context when user explicitly mentions knowledge graph
# All automatic triggers moved to Stop hook (session end) and SessionStart (session begin)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

# Skip system messages
echo "$PROMPT" | grep -qE '<task-notification>|<system-reminder>|<command-name>' && exit 0

# Only react to explicit knowledge graph mentions
echo "$PROMPT" | grep -qiE '(知识图谱|knowledge.?graph|/knowledge-graph|kg update|kg status)' || exit 0

# Provide quick status as context
EVENTS="$KG_DATA/graph-events.jsonl"
[ ! -f "$EVENTS" ] && exit 0
PENDING=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
[ "$PENDING" -lt 1 ] && exit 0

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"[知识图谱] 当前 %s 条待分析事件"}}\n' "$PENDING"
exit 0
