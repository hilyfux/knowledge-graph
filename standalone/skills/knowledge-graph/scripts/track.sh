#!/bin/bash
# track.sh — Event recorder + working set tracking + prediction cache
# Usage: track.sh <write|read|failure|instructions>
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$KG_DATA/graph-events.jsonl"
TS=$(date +%s)
PREFIX="$CLAUDE_PROJECT_DIR/"
CMD="${1:-write}"

# Guard: skip files outside current project, plus kg/claude infra.
# Tracking writes to .knowledge-graph/ creates self-referential pollution
# (runtime data showing up as "active module"). Tracking .claude/ is noise
# — infra, not user code.
is_project_file() {
  case "$1" in
    "$PREFIX.knowledge-graph/"*) return 1 ;;
    "$PREFIX.claude/"*) return 1 ;;
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

    # Recurring auto-trigger: every WRITE_TRIGGER_THRESHOLD writes since last
    # successful update, drop a `.update-pending` marker so the next user
    # prompt re-injects the [kg auto-trigger] context. Counter resets when
    # the skill's update step 5 calls `analyze.sh unlock`. Threshold can be
    # overridden via KG_UPDATE_THRESHOLD (default 15).
    THRESHOLD=${KG_UPDATE_THRESHOLD:-15}
    COUNTER_FILE="$KG_DATA/.writes-since-update"
    UPDATE_PENDING="$KG_DATA/.update-pending"
    UPDATE_LOCK="$KG_DATA/.kg-updating"
    if [ ! -f "$UPDATE_LOCK" ] && [ ! -f "$UPDATE_PENDING" ]; then
      WROTE=0
      [ -f "$COUNTER_FILE" ] && WROTE=$(cat "$COUNTER_FILE" 2>/dev/null | tr -d ' \n' || echo 0)
      case "$WROTE" in ''|*[!0-9]*) WROTE=0 ;; esac
      WROTE=$((WROTE + 1))
      printf '%s\n' "$WROTE" > "$COUNTER_FILE" 2>/dev/null
      if [ "$WROTE" -ge "$THRESHOLD" ]; then
        touch "$UPDATE_PENDING" 2>/dev/null
      fi
    fi

    # Mid-session analysis trigger: long sessions may never hit Stop, so keep
    # graph-analysis.json reasonably fresh once event backlog grows. Fire in the
    # background, throttled by age + lock to stay within hook timeout budget.
    LINE_COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
    LAST_ANALYZE=0
    [ -f "$ANALYZE_STAMP" ] && LAST_ANALYZE=$(cat "$ANALYZE_STAMP" 2>/dev/null | tr -d ' ')
    [ -z "$LAST_ANALYZE" ] && LAST_ANALYZE=0
    ANALYZE_AGE=$((TS - LAST_ANALYZE))
    if [ "$LINE_COUNT" -ge 50 ] && [ "$ANALYZE_AGE" -ge 300 ] && [ ! -f "$ANALYZE_LOCK" ]; then
      printf '%s\n' "$TS" > "$ANALYZE_STAMP" 2>/dev/null
      touch "$ANALYZE_LOCK" 2>/dev/null
      (
        trap 'rm -f "$ANALYZE_LOCK" 2>/dev/null' EXIT
        env CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" run_with_timeout 15 bash "$SCRIPT_DIR/analyze.sh" analyze > /dev/null 2>&1
      ) &
      disown
    fi
    ;;

  pre-write)
    # PreToolUse: Write|Edit — block if module needs a knowledge node
    # Must be PreToolUse (not PostToolUse) for decision:block to work
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    is_project_file "$FILE_PATH" || exit 0

    TARGET_DIR=$(dirname "${FILE_PATH#$PREFIX}")
    UPDATE_MARKER="$KG_DATA/.update-triggered"

    # Never block writes that themselves create the knowledge node — otherwise
    # the skill's own update-mode write gets blocked by the very condition it
    # is trying to resolve (paradox loop).
    BASENAME=$(basename "$FILE_PATH")
    if [ "$BASENAME" = "CLAUDE.md" ] || [ "$BASENAME" = "SKILL.md" ] || [ "$BASENAME" = "AGENTS.md" ]; then
      exit 0
    fi

    # One-time per session: block if writing to module without a knowledge node
    if [ ! -f "$UPDATE_MARKER" ] && [ -f "$KG_DATA/.initialized" ]; then
      if [ "$TARGET_DIR" != "." ] && ! has_knowledge_node "$TARGET_DIR"; then
        touch "$UPDATE_MARKER" 2>/dev/null

        # Assess module complexity from event history
        DIR_WRITES=0; DIR_FAILS=0
        if [ -f "$EVENTS" ]; then
          DIR_WRITES=$(jq -r --arg d "$TARGET_DIR" 'select((.e | startswith("w")) and (.p | startswith($d+"/")))' "$EVENTS" 2>/dev/null | wc -l | tr -d ' ')
          DIR_FAILS=$(jq -r --arg d "$TARGET_DIR" 'select(.e == "f" and ((.p // "") | startswith($d+"/")))' "$EVENTS" 2>/dev/null | wc -l | tr -d ' ')
        fi

        if [ "$DIR_WRITES" -ge 5 ] || [ "$DIR_FAILS" -ge 1 ]; then
          # Complex module: has significant history or failures → use skill for deep analysis
          printf '{"decision":"block","reason":"Write paused. Module %s/ has significant activity (%s writes, %s failures) but no knowledge node. Call Skill(skill=\\\"knowledge-graph\\\", args=\\\"update\\\") for code+history analysis. Then retry."}\n' "$TARGET_DIR" "$DIR_WRITES" "$DIR_FAILS"
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

    # Large-file guard: warn before the Read tool hits its 25K-token ceiling
    # and burns a round-trip. Override via env KG_READ_SIZE_WARN_KB (default 40).
    SIZE_WARN=""
    if [ -f "$FILE_PATH" ]; then
      FILE_BYTES=$(stat -f %z "$FILE_PATH" 2>/dev/null || stat -c %s "$FILE_PATH" 2>/dev/null || echo 0)
      THRESHOLD_KB=${KG_READ_SIZE_WARN_KB:-40}
      THRESHOLD_BYTES=$((THRESHOLD_KB * 1024))
      if [ "$FILE_BYTES" -gt "$THRESHOLD_BYTES" ] 2>/dev/null; then
        FILE_KB=$((FILE_BYTES / 1024))
        SIZE_WARN="[kg:size-guard] $REL is ~${FILE_KB}KB — Read will likely hit the token ceiling. Prefer Grep to locate, then Read with offset/limit, or split the read. "
      fi
    fi

    # Skip prediction if module already accessed this session
    FIRST_ACCESS=true
    ws_is_paged_in "$TARGET_DIR" && FIRST_ACCESS=false
    ws_touch "$TS" "$TARGET_DIR" "r"

    # On repeat access, skip prediction but still surface the size warning.
    if [ "$FIRST_ACCESS" = false ]; then
      if [ -n "$SIZE_WARN" ]; then
        ESCAPED=$(printf '%s' "$SIZE_WARN" | sed 's/"/\\"/g' | tr '\n' ' ')
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$ESCAPED"
      fi
      exit 0
    fi

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

    # Prefetch: inject predicted module prohibitions (may be empty)
    CONTEXT=""
    if [ -n "$PRED_DIRS" ]; then
      while IFS= read -r pdir; do
        [ -z "$pdir" ] && continue
        NODE=$(knowledge_node_path "$pdir" 2>/dev/null || true)
        RULES=$(get_prohibitions "$NODE" 3)
        [ -n "$RULES" ] && CONTEXT="${CONTEXT}[${pdir}] ${RULES}\n"
      done <<< "$PRED_DIRS"
    fi

    # Combine size warning + related-module prohibitions into one hook output
    COMBINED=""
    [ -n "$SIZE_WARN" ]   && COMBINED="$SIZE_WARN"
    [ -n "$CONTEXT" ]     && COMBINED="${COMBINED}[Related] ${CONTEXT}"
    if [ -n "$COMBINED" ]; then
      ESCAPED=$(printf '%s' "$COMBINED" | sed 's/"/\\"/g' | tr '\n' ' ')
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' "$ESCAPED"
    fi
    ;;

  failure)
    INPUT=$(cat)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    REL=""
    if [ -n "$FILE_PATH" ] && is_project_file "$FILE_PATH"; then
      REL="${FILE_PATH#$PREFIX}"
    fi

    # Ignore infra / host-leak failures without a project-local file path.
    [ -z "$REL" ] && exit 0

    echo "$INPUT" | jq -c --argjson t "$TS" --arg p "$REL" '
      {e:"f", p:$p, tool:(.tool_name // ""), err:((.error // "")[0:100] | gsub("\n"; " ")), t:$t}
    ' >> "$EVENTS" 2>/dev/null
    ;;

  instructions)
    # Only record module-level knowledge node loads (skip root, .claude/, .knowledge-graph/)
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
