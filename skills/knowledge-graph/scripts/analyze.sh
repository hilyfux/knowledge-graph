#!/bin/bash
# analyze.sh — Stop hook + project scan + pre-analysis + quick-status
# Usage: analyze.sh <stop|scan|analyze|quick-status>
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$KG_DATA/graph-events.jsonl"
ANALYSIS="$KG_DATA/graph-analysis.json"
SCAN="$KG_DATA/graph-scan.json"
CMD="${1:-quick-status}"

case "$CMD" in

  stop)
    # Stop hook: save working state + background analysis
    [ ! -f "$EVENTS" ] && exit 0
    LINE_COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
    [ "$LINE_COUNT" -lt 3 ] && exit 0

    # Save snapshot (shared function from guard.sh)
    save_snapshot

    # Event rotation: keep recent 300 lines, archive the rest
    if [ "$LINE_COUNT" -gt 500 ]; then
      ARCHIVE="$KG_DATA/graph-events-archive.jsonl"
      head -$((LINE_COUNT - 300)) "$EVENTS" >> "$ARCHIVE" 2>/dev/null
      tail -300 "$EVENTS" > "$EVENTS.tmp" 2>/dev/null && mv "$EVENTS.tmp" "$EVENTS"
    fi

    # Background analysis if enough events
    if [ "$LINE_COUNT" -ge 10 ]; then
      env CLAUDE_PROJECT_DIR="$CLAUDE_PROJECT_DIR" \
        timeout 15 bash "$SCRIPT_DIR/analyze.sh" analyze > /dev/null 2>&1 &
      disown
    fi
    ;;

  quick-status)
    # Lightweight status for SKILL.md !`command` pre-injection
    COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' 2>/dev/null || echo 0)
    CLAUDE_MD_COUNT=$(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" \
      -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
    LAST=$([ -f "$ANALYSIS" ] && date -r "$ANALYSIS" "+%m/%d %H:%M" 2>/dev/null || echo "未生成")
    echo "待处理事件: ${COUNT} | CLAUDE.md: ${CLAUDE_MD_COUNT} | 上次分析: ${LAST}"
    ;;

  scan)
    # Full project scan → graph-scan.json (used by init mode)
    cd "$CLAUDE_PROJECT_DIR" || exit 1

    MODULES=$(find . -type f \
      -not -path './.git/*' -not -path '*/node_modules/*' \
      -not -path '*/dist/*' -not -path '*/build/*' \
      -not -path '*/.next/*' -not -path '*/__pycache__/*' \
      -not -path '*/.venv/*' -not -path '*/vendor/*' \
      -not -path '*/target/*' -not -path '*/.claude/*' \
      2>/dev/null | sed 's|^\./||' | xargs -I{} dirname {} | sort | uniq -c | sort -rn | awk '$1 >= 3 {print $2}' | head -30)

    EXISTING=$(find . -name "CLAUDE.md" -not -path '*/.git/*' \
      -not -path '*/node_modules/*' 2>/dev/null | sed 's|^\./||' | sort)

    DEPS=""
    for mod in $MODULES; do
      IMPORTS=$(grep -rhoE "(from\s+['\"]\.\.?/[^'\"]+|require\(['\"]\.\.?/[^'\"]+)" \
        "$mod" 2>/dev/null | grep -oE '\.\.?/[^"'"'"')+]+' | sort -u)
      for imp in $IMPORTS; do
        TARGET=$(cd "$CLAUDE_PROJECT_DIR/$mod" 2>/dev/null && cd "$imp" 2>/dev/null && pwd) || continue
        TARGET="${TARGET#$CLAUDE_PROJECT_DIR/}"
        [ -d "$CLAUDE_PROJECT_DIR/$TARGET" ] || TARGET=$(dirname "$TARGET")
        [ "$TARGET" = "$mod" ] && continue
        echo "$MODULES" | grep -q "^$TARGET$" && DEPS="$DEPS{\"from\":\"$mod\",\"to\":\"$TARGET\"},"
      done
    done
    DEPS_JSON=$(echo "[${DEPS%,}]" | jq -c 'unique' 2>/dev/null || echo "[]")

    COCHANGE_JSON="[]"
    FIXES=""
    CONVENTIONS=""
    if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null; then
      COCHANGE_JSON=$(git log --pretty=format: --name-only -50 2>/dev/null | grep -v '^$' \
        | sort | uniq -c | sort -rn | head -10 | awk '{print $2}' | jq -R . | jq -s . 2>/dev/null || echo "[]")
      FIXES=$(git log --oneline --all --grep='fix\|bug\|revert\|broken' -10 2>/dev/null | head -10)
      RECENT_MSGS=$(git log --pretty=format:'%s' -20 2>/dev/null)
      if echo "$RECENT_MSGS" | grep -qE '^(feat|fix|chore|docs|refactor|test|perf)(\(.+\))?:'; then
        CONVENTIONS="conventional-commits"
      fi
    fi

    PROJECT_TYPE="unknown"
    if [ -f "package.json" ] || [ -f "tsconfig.json" ]; then
      PROJECT_TYPE="js/ts"
    elif [ -f "Cargo.toml" ]; then PROJECT_TYPE="rust"
    elif [ -f "go.mod" ]; then PROJECT_TYPE="go"
    elif [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ]; then PROJECT_TYPE="python"
    elif [ -f "pom.xml" ] || [ -f "build.gradle" ]; then PROJECT_TYPE="java"
    fi

    TOTAL_FILES=$(find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \
      -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.claude/*' 2>/dev/null | wc -l | tr -d ' ')
    TOTAL_DIRS=$(echo "$MODULES" | wc -l | tr -d ' ')

    jq -n \
      --arg type "$PROJECT_TYPE" \
      --argjson files "$TOTAL_FILES" \
      --argjson dirs "$TOTAL_DIRS" \
      --argjson deps "$DEPS_JSON" \
      --argjson cochange "$COCHANGE_JSON" \
      --arg fixes "${FIXES:-}" \
      --arg conventions "${CONVENTIONS:-}" \
      --arg modules "$(echo "$MODULES" | tr '\n' '|')" \
      --arg existing "$(echo "$EXISTING" | tr '\n' '|')" \
      '{
        project_type: $type, total_files: $files, total_dirs: $dirs,
        modules: ($modules | split("|") | map(select(. != ""))),
        existing_claude_md: ($existing | split("|") | map(select(. != ""))),
        dependencies: $deps, cochange_files: $cochange,
        recent_fixes: $fixes, conventions: $conventions
      }' > "$SCAN"

    echo "$TOTAL_FILES files, $TOTAL_DIRS modules scanned"
    ;;

  analyze)
    # Pre-analysis → graph-analysis.json (used by update mode + stop hook)
    [ ! -f "$EVENTS" ] && exit 1

    CORE=$(jq -c '.' "$EVENTS" 2>/dev/null | jq -s '
      . as $all |
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

    STALE_LIST=""
    for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" \
      -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
      REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
      DIR=$(dirname "$REL")
      NEW_COUNT=$(echo "$CORE" | jq --arg d "$DIR" '[.dirs[] | select(.dir == $d) | .w_new] | add // 0')
      [ "$NEW_COUNT" -ge 3 ] && STALE_LIST="$STALE_LIST\"$REL\","
    done
    STALE_JSON="[${STALE_LIST%,}]"
    [ -z "$STALE_LIST" ] && STALE_JSON="[]"

    BROKEN_LIST=""
    for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" \
      -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
      for ref in $(grep -oE '@[^[:space:]]+CLAUDE\.md' "$cmd_file" 2>/dev/null); do
        FULL="$(dirname "$cmd_file")/${ref#@}"
        if [ ! -f "$FULL" ]; then
          REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
          BROKEN_LIST="$BROKEN_LIST\"$REL: $ref\","
        fi
      done
    done
    BROKEN_JSON="[${BROKEN_LIST%,}]"
    [ -z "$BROKEN_LIST" ] && BROKEN_JSON="[]"

    COCHANGE_JSON="[]"
    FIXES=""
    if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
      COCHANGE_JSON=$(git -C "$CLAUDE_PROJECT_DIR" log --pretty=format: --name-only -30 2>/dev/null \
        | grep -v '^$' | sort | uniq -c | sort -rn | head -8 | awk '{print $2}' | jq -R . | jq -s .)
      FIXES=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline --all \
        --grep='fix\|bug\|revert\|broken' -5 2>/dev/null | head -5)
    fi

    echo "$CORE" | jq \
      --argjson stale "$STALE_JSON" \
      --argjson broken "$BROKEN_JSON" \
      --argjson cochange "$COCHANGE_JSON" \
      --arg fixes "${FIXES:-}" \
      '. + {stale: $stale, broken_refs: $broken, cochange_files: $cochange, recent_fixes: $fixes}' \
      > "$ANALYSIS"
    ;;

esac

exit 0
