#!/bin/bash
# pre-analyze.sh — Pre-compute analysis data for the evolution engine
# Outputs structured JSON to .claude/graph-analysis.json
# This saves the agent 10+ tool calls by doing all computation in bash.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
OUTPUT="$CLAUDE_PROJECT_DIR/.claude/graph-analysis.json"

[ ! -f "$EVENTS" ] && exit 1

# --- Directory-level event aggregation ---
# Count events per directory, output as JSON object
DIR_STATS=$(cat "$EVENTS" | jq -r '
  select(.p != null and .p != "") |
  {dir: (.p | split("/") | if length > 1 then .[:-1] | join("/") else "." end), e: .e, err: (.err // "")}
' | jq -s '
  group_by(.dir) | map({
    dir: .[0].dir,
    w: [.[] | select(.e | startswith("w"))] | length,
    w_new: [.[] | select(.e == "w:new")] | length,
    r: [.[] | select(.e == "r")] | length,
    i: [.[] | select(.e == "i")] | length,
    f: [.[] | select(.e == "f")] | length,
    top_err: ([.[] | select(.e == "f") | .err] | group_by(.) | sort_by(-length) | .[0][0] // "")
  }) | sort_by(-.w) | .[0:15]
')

# --- Blind spots: high activity + zero knowledge loading ---
BLIND_SPOTS=$(echo "$DIR_STATS" | jq '[.[] | select(.w > 2 and .r > 0 and .i == 0) | .dir]')

# --- Stale CLAUDE.md detection ---
STALE="[]"
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  STALE_LIST=""
  for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
    REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
    DIR=$(dirname "$REL")
    # Check if directory has w:new events
    NEW_COUNT=$(echo "$DIR_STATS" | jq --arg d "$DIR" '[.[] | select(.dir == $d) | .w_new] | add // 0')
    if [ "$NEW_COUNT" -ge 3 ]; then
      STALE_LIST="$STALE_LIST\"$REL\","
    fi
  done
  if [ -n "$STALE_LIST" ]; then
    STALE="[${STALE_LIST%,}]"
  fi
fi

# --- Broken @ references ---
BROKEN="[]"
BROKEN_LIST=""
for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
  REFS=$(grep -oP '@[^\s]+CLAUDE\.md' "$cmd_file" 2>/dev/null)
  for ref in $REFS; do
    REF_PATH="${ref#@}"
    FULL="$(dirname "$cmd_file")/$REF_PATH"
    if [ ! -f "$FULL" ]; then
      REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
      BROKEN_LIST="$BROKEN_LIST\"$REL: $ref\","
    fi
  done
done
if [ -n "$BROKEN_LIST" ]; then
  BROKEN="[${BROKEN_LIST%,}]"
fi

# --- Git co-change files (top 8) ---
COCHANGE="[]"
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  COCHANGE=$(git -C "$CLAUDE_PROJECT_DIR" log --pretty=format: --name-only -30 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -8 | awk '{print $2}' | jq -R . | jq -s .)

  # Recent fix/revert commits
  FIXES=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline --all --grep='fix\|bug\|revert\|broken' -5 2>/dev/null | head -5)
fi

# --- Feedback: loaded CLAUDE.md files ---
LOADED=$(cat "$EVENTS" | jq -r 'select(.e == "i") | .p' 2>/dev/null | sort -u | jq -R . | jq -s .)

# --- Event count for tiering ---
EVENT_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')

# --- Assemble output ---
jq -n \
  --argjson dirs "$DIR_STATS" \
  --argjson blind "$BLIND_SPOTS" \
  --argjson stale "$STALE" \
  --argjson broken "$BROKEN" \
  --argjson cochange "$COCHANGE" \
  --argjson loaded "$LOADED" \
  --argjson count "$EVENT_COUNT" \
  --arg fixes "${FIXES:-}" \
  '{
    event_count: $count,
    dirs: $dirs,
    blind_spots: $blind,
    stale: $stale,
    broken_refs: $broken,
    cochange_files: $cochange,
    loaded_knowledge: $loaded,
    recent_fixes: $fixes
  }' > "$OUTPUT"

exit 0
