#!/bin/bash
# pre-analyze.sh — Pre-compute analysis data for the evolution engine
# Outputs .claude/graph-analysis.json so the agent reads ONE file instead of 10+ tool calls.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
OUTPUT="$CLAUDE_PROJECT_DIR/.claude/graph-analysis.json"

[ ! -f "$EVENTS" ] && exit 1

# --- Core analysis: single jq call for events → dirs + blind_spots + loaded ---
# Filter valid JSON lines first (skip malformed events)
CORE=$(jq -c '.' "$EVENTS" 2>/dev/null | jq -s '
  . as $all |
  # Directory stats
  [.[] | select(.p != null and .p != "")] |
  group_by(.p | split("/") | if length > 1 then .[:-1] | join("/") else "." end) |
  map({
    dir: .[0].p | split("/") | (if length > 1 then .[:-1] | join("/") else "." end),
    w: [.[] | select(.e | startswith("w"))] | length,
    w_new: [.[] | select(.e == "w:new")] | length,
    r: [.[] | select(.e == "r")] | length,
    i: [.[] | select(.e == "i")] | length,
    f: [.[] | select(.e == "f")] | length,
    top_err: ([.[] | select(.e == "f") | .err // ""] | group_by(.) | sort_by(-length) | .[0][0] // "")
  }) | sort_by(-.w) | .[0:15] |
  . as $dirs |
  {
    event_count: ($all | length),
    dirs: $dirs,
    blind_spots: [$dirs[] | select(.w > 2 and .r > 0 and .i == 0) | .dir],
    loaded_knowledge: [$all[] | select(.e == "i") | .p] | unique
  }
')

# --- Stale CLAUDE.md detection ---
STALE_JSON="[]"
STALE_LIST=""
for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
  REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
  DIR=$(dirname "$REL")
  NEW_COUNT=$(echo "$CORE" | jq --arg d "$DIR" '[.dirs[] | select(.dir == $d) | .w_new] | add // 0')
  [ "$NEW_COUNT" -ge 3 ] && STALE_LIST="$STALE_LIST\"$REL\","
done
[ -n "$STALE_LIST" ] && STALE_JSON="[${STALE_LIST%,}]"

# --- Broken @ references ---
BROKEN_JSON="[]"
BROKEN_LIST=""
for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
  for ref in $(grep -oP '@[^\s]+CLAUDE\.md' "$cmd_file" 2>/dev/null); do
    FULL="$(dirname "$cmd_file")/${ref#@}"
    if [ ! -f "$FULL" ]; then
      REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
      BROKEN_LIST="$BROKEN_LIST\"$REL: $ref\","
    fi
  done
done
[ -n "$BROKEN_LIST" ] && BROKEN_JSON="[${BROKEN_LIST%,}]"

# --- Git data (single check, two commands) ---
COCHANGE_JSON="[]"
FIXES=""
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  COCHANGE_JSON=$(git -C "$CLAUDE_PROJECT_DIR" log --pretty=format: --name-only -30 2>/dev/null | grep -v '^$' | sort | uniq -c | sort -rn | head -8 | awk '{print $2}' | jq -R . | jq -s .)
  FIXES=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline --all --grep='fix\|bug\|revert\|broken' -5 2>/dev/null | head -5)
fi

# --- Assemble final output (merge core + extras) ---
echo "$CORE" | jq \
  --argjson stale "$STALE_JSON" \
  --argjson broken "$BROKEN_JSON" \
  --argjson cochange "$COCHANGE_JSON" \
  --arg fixes "${FIXES:-}" \
  '. + {stale: $stale, broken_refs: $broken, cochange_files: $cochange, recent_fixes: $fixes}' \
  > "$OUTPUT"

exit 0
