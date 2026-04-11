#!/bin/bash
# track.sh — Event recorder + working set tracking + prediction cache
# Usage: track.sh <write|read|failure|instructions>
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$KG_DATA/graph-events.jsonl"
TS=$(date +%s)
PREFIX="$CLAUDE_PROJECT_DIR/"
CMD="${1:-write}"

# Guard: skip files outside current project (cross-project edits)
is_project_file() {
  case "$1" in
    "$PREFIX"*) return 0 ;;
    *) return 1 ;;
  esac
}

case "$CMD" in

  write)
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    is_project_file "$FILE_PATH" || exit 0

    REL="${FILE_PATH#$PREFIX}"
    TARGET_DIR=$(dirname "$REL")

    # Record event
    TOOL=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
    case "$TOOL" in
      Write) echo "{\"e\":\"w:new\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS" 2>/dev/null ;;
      Edit)  echo "{\"e\":\"w:edit\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS" 2>/dev/null ;;
    esac

    # Update working set
    ws_touch "$TS" "$TARGET_DIR" "w"
    ;;

  pre-write)
    # PreToolUse: Write|Edit — block if module needs CLAUDE.md
    # Must be PreToolUse (not PostToolUse) for decision:block to work
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    is_project_file "$FILE_PATH" || exit 0

    TARGET_DIR=$(dirname "${FILE_PATH#$PREFIX}")
    UPDATE_MARKER="$KG_DATA/.update-triggered"

    # One-time per session: block if writing to module without CLAUDE.md
    if [ ! -f "$UPDATE_MARKER" ] && [ -f "$KG_DATA/.initialized" ]; then
      if [ "$TARGET_DIR" != "." ] && [ ! -f "$CLAUDE_PROJECT_DIR/$TARGET_DIR/CLAUDE.md" ]; then
        touch "$UPDATE_MARKER" 2>/dev/null

        # Assess module complexity from event history
        DIR_WRITES=0; DIR_FAILS=0
        if [ -f "$EVENTS" ]; then
          DIR_WRITES=$(jq -r --arg d "$TARGET_DIR" 'select((.e | startswith("w")) and (.p | startswith($d+"/")))' "$EVENTS" 2>/dev/null | wc -l | tr -d ' ')
          DIR_FAILS=$(jq -r --arg d "$TARGET_DIR" 'select(.e == "f" and ((.p // "") | startswith($d+"/")))' "$EVENTS" 2>/dev/null | wc -l | tr -d ' ')
        fi

        if [ "$DIR_WRITES" -ge 5 ] || [ "$DIR_FAILS" -ge 1 ]; then
          # Complex module: has significant history or failures → use skill for deep analysis
          printf '{"decision":"block","reason":"Write paused. Module %s/ has significant activity (%s writes, %s failures) but no CLAUDE.md. Call Skill(skill=\\\"knowledge-graph\\\", args=\\\"update\\\") for code+history analysis. Then retry."}\n' "$TARGET_DIR" "$DIR_WRITES" "$DIR_FAILS"
        else
          # Simple module: new/minimal history → direct write with format template
          printf '{"decision":"block","reason":"Write paused. Module %s/ needs CLAUDE.md (max 20 lines). Create it now:\\n# %s\\n## Prohibitions\\n- {behavior} → {consequence}\\n## When Changing\\n- {condition} → @{path}/CLAUDE.md\\n## Conventions\\n- {rule}\\nEvidence-only, no guesses. Also add one-line entry to .knowledge-graph/knowledge-index.md. Then retry."}\n' "$TARGET_DIR" "$(basename "$TARGET_DIR")"
        fi
        exit 0
      fi
    fi
    ;;

  read)
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    is_project_file "$FILE_PATH" || exit 0

    REL="${FILE_PATH#$PREFIX}"
    TARGET_DIR=$(dirname "$REL")

    # Record event
    echo "{\"e\":\"r\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS" 2>/dev/null

    # Skip prediction if module already accessed this session
    FIRST_ACCESS=true
    ws_is_paged_in "$TARGET_DIR" && FIRST_ACCESS=false
    ws_touch "$TS" "$TARGET_DIR" "r"
    [ "$FIRST_ACCESS" = false ] && exit 0

    # Check prediction cache (single call — capture output and test exit code)
    PRED_DIRS=$(tlb_get "$TARGET_DIR" "$TS") || {
      # Cache miss → run prediction + cache result
      PREDICTED=$(echo "{\"file_path\":\"$FILE_PATH\"}" | bash "$SCRIPT_DIR/infer.sh" predict 2>/dev/null)
      PRED_DIRS=$(echo "$PREDICTED" | jq -r '.[0:3][] | .dir' 2>/dev/null)
      if [ -n "$PRED_DIRS" ]; then
        PRED_CSV=$(echo "$PRED_DIRS" | tr '\n' ',' | sed 's/,$//')
        tlb_set "$TS" "$TARGET_DIR" "$PRED_CSV"
      fi
    }
    [ -z "$PRED_DIRS" ] && exit 0

    # Prefetch: inject predicted module prohibitions
    CONTEXT=""
    while IFS= read -r pdir; do
      [ -z "$pdir" ] && continue
      RULES=$(get_prohibitions "$CLAUDE_PROJECT_DIR/$pdir/CLAUDE.md" 3)
      [ -n "$RULES" ] && CONTEXT="${CONTEXT}[${pdir}] ${RULES}\n"
    done <<< "$PRED_DIRS"

    if [ -n "$CONTEXT" ]; then
      ESCAPED=$(printf '%s' "$CONTEXT" | sed 's/"/\\"/g' | tr '\n' ' ')
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"[Related] %s"}}\n' "$ESCAPED"
    fi
    ;;

  failure)
    cat | jq -c --argjson t "$TS" '
      {e:"f", tool:(.tool_name // ""), err:((.error // "")[0:100] | gsub("\n"; " ")), t:$t}
    ' >> "$EVENTS" 2>/dev/null
    ;;

  instructions)
    # Only record module-level CLAUDE.md loads (skip root, .claude/, .knowledge-graph/)
    cat | jq -c --argjson t "$TS" --arg prefix "$PREFIX" '
      [(.loaded_files // [])[], (.file_path // empty)] | unique | .[] |
      select(. != null and . != "") |
      select(startswith($prefix)) |
      sub($prefix; "") |
      select(endswith("CLAUDE.md")) |
      select(. != "CLAUDE.md" and (startswith(".claude/") | not) and (startswith(".knowledge-graph/") | not)) |
      {e:"i", p:., t:$t}
    ' >> "$EVENTS" 2>/dev/null
    ;;

esac

exit 0
