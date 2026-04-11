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

    # Update working set (no cache invalidation — editing current dir
    # doesn't change its relationship to other dirs)
    ws_touch "$TS" "$TARGET_DIR" "w"
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
    cat | jq -c --argjson t "$TS" --arg prefix "$PREFIX" '
      [(.loaded_files // [])[], (.file_path // empty)] | unique | .[] |
      select(. != null and . != "") |
      select(startswith($prefix)) |
      sub($prefix; "") |
      {e:"i", p:., t:$t}
    ' >> "$EVENTS" 2>/dev/null
    ;;

esac

exit 0
