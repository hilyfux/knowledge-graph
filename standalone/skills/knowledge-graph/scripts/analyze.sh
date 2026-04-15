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
    LAST=$([ -f "$ANALYSIS" ] && date -r "$ANALYSIS" "+%m/%d %H:%M" 2>/dev/null || echo "never")
    echo "Pending events: ${COUNT} | CLAUDE.md nodes: ${CLAUDE_MD_COUNT} | Last analysis: ${LAST}"
    ;;

  auto-detect)
    # Called by SKILL.md !` preprocessor — detect if init or update is needed
    # and output a directive that tells Claude which mode to run

    # Case 1: never initialized → need init
    if [ ! -f "$KG_DATA/.initialized" ]; then
      echo "[AUTO] Project not initialized. Execute init mode now."
      exit 0
    fi

    # Case 2: active modules missing CLAUDE.md → need update
    MISSING=0
    if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
      for d in $(tail -200 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
        | xargs -I{} dirname {} 2>/dev/null | sort -u | head -10); do
        [ "$d" = "." ] && continue
        [ "${d#.knowledge-graph}" != "$d" ] && continue
        [ "${d#.claude}" != "$d" ] && continue
        [ ! -d "$CLAUDE_PROJECT_DIR/$d" ] && continue
        [ -f "$CLAUDE_PROJECT_DIR/$d/CLAUDE.md" ] && continue
        [ -f "$CLAUDE_PROJECT_DIR/$d/SKILL.md" ] && continue
        MISSING=$((MISSING + 1))
      done
    fi
    if [ "$MISSING" -gt 0 ]; then
      COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' || echo 0)
      echo "[AUTO] $MISSING active modules lack CLAUDE.md ($COUNT events pending). Execute update mode now."
      exit 0
    fi

    # Case 3: normal status
    COUNT=$(wc -l < "$EVENTS" 2>/dev/null | tr -d ' ' 2>/dev/null || echo 0)
    CLAUDE_MD_COUNT=$(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" \
      -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
    echo "Pending events: ${COUNT} | CLAUDE.md nodes: ${CLAUDE_MD_COUNT} | Status: OK"
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
    for cmd_file in $(find "$CLAUDE_PROJECT_DIR" \( -name "CLAUDE.md" -o -name "SKILL.md" \) \
      -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
      REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
      DIR=$(dirname "$REL")
      NEW_COUNT=$(echo "$CORE" | jq --arg d "$DIR" '[.dirs[] | select(.dir == $d) | .w_new] | add // 0')
      [ "$NEW_COUNT" -ge 3 ] && STALE_LIST="$STALE_LIST\"$REL\","
    done
    STALE_JSON="[${STALE_LIST%,}]"
    [ -z "$STALE_LIST" ] && STALE_JSON="[]"

    BROKEN_LIST=""
    for cmd_file in $(find "$CLAUDE_PROJECT_DIR" \( -name "CLAUDE.md" -o -name "SKILL.md" \) \
      -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
      for ref in $(grep -oE '@[^[:space:]]+(CLAUDE|SKILL)\.md' "$cmd_file" 2>/dev/null \
        | grep -v '{'); do
        # Skip template placeholders like `@{path}/CLAUDE.md` — those are docstring
        # format examples, not real references.
        REF_PATH="${ref#@}"
        # Resolve both ways: relative to the node's directory, and from project root.
        # Cross-module refs like `@src/foo/CLAUDE.md` use project-root form.
        if [ ! -f "$(dirname "$cmd_file")/$REF_PATH" ] && \
           [ ! -f "$CLAUDE_PROJECT_DIR/$REF_PATH" ]; then
          REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
          BROKEN_LIST="$BROKEN_LIST\"$REL: $ref\","
        fi
      done
    done
    BROKEN_JSON="[${BROKEN_LIST%,}]"
    [ -z "$BROKEN_LIST" ] && BROKEN_JSON="[]"

    # Filter blind_spots by filesystem — jq only knows about `i` events,
    # which miss dirs whose CLAUDE.md/SKILL.md exists but wasn't read this session.
    # Also drop ghost paths from stale events where the directory no longer exists.
    BLIND_FILTERED=""
    for d in $(echo "$CORE" | jq -r '.blind_spots[]?'); do
      [ ! -d "$CLAUDE_PROJECT_DIR/$d" ] && continue
      [ -f "$CLAUDE_PROJECT_DIR/$d/CLAUDE.md" ] && continue
      [ -f "$CLAUDE_PROJECT_DIR/$d/SKILL.md" ] && continue
      BLIND_FILTERED="$BLIND_FILTERED\"$d\","
    done
    BLIND_JSON="[${BLIND_FILTERED%,}]"
    [ -z "$BLIND_FILTERED" ] && BLIND_JSON="[]"
    CORE=$(echo "$CORE" | jq --argjson b "$BLIND_JSON" '.blind_spots = $b')

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

  save-channel-snapshot)
    # Usage: analyze.sh save-channel-snapshot <channel>
    # Writes .knowledge-graph/{channel}-snapshot.md from {channel}-events.jsonl.
    # For the default (work) channel, use `analyze.sh stop` instead — this
    # command is for named channels only (e.g. "upgrade").
    CH=${2:-}
    if [ -z "$CH" ] || [ "$CH" = "default" ] || [ "$CH" = "work" ]; then
      echo "usage: analyze.sh save-channel-snapshot <channel> (non-default)" >&2
      exit 1
    fi

    CH_EVENTS=$(channel_events_path "$CH")
    CH_SNAP=$(channel_snapshot_path "$CH")

    if [ ! -f "$CH_EVENTS" ] || [ ! -s "$CH_EVENTS" ]; then
      echo "no events in channel '$CH' ($CH_EVENTS)"
      exit 0
    fi

    TOTAL_LINES=$(wc -l < "$CH_EVENTS" | tr -d ' ')
    VALID_LINES=$(filter_valid_events < "$CH_EVENTS" | wc -l | tr -d ' ')
    BAD_LINES=$((TOTAL_LINES - VALID_LINES))

    {
      echo "# $CH 快照 ($(date '+%Y-%m-%d %H:%M'))"
      echo ""
      echo "## 事件统计"
      echo "- 有效事件: $VALID_LINES"
      [ "$BAD_LINES" -gt 0 ] && echo "- 忽略的损坏/旧 schema 行: $BAD_LINES"
      echo ""
      echo "## 活跃文件（最常编辑，前 8）"
      filter_valid_events < "$CH_EVENTS" | \
        jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null | \
        sort | uniq -c | sort -rn | head -8 | awk '{printf "- %s (%d×)\n", $2, $1}'
      echo ""
      echo "## 最近 10 条事件"
      filter_valid_events < "$CH_EVENTS" | tail -10 | \
        jq -r '"- [\(.t | todateiso8601)] \(.e) \(.p)" + (if .err then "  — \(.err)" else "" end)' 2>/dev/null
      echo ""
      echo "## 错误事件（最近 5 条）"
      FAILS=$(filter_valid_events < "$CH_EVENTS" | \
        jq -r 'select(.e == "f") | "- [\(.t | todateiso8601)] \(.p): \(.err // "")"' 2>/dev/null | tail -5)
      if [ -n "$FAILS" ]; then
        echo "$FAILS"
      else
        echo "(无)"
      fi
    } > "$CH_SNAP"

    echo "wrote $CH_SNAP ($VALID_LINES valid / $BAD_LINES ignored)"
    ;;

  validate-events)
    # Usage: analyze.sh validate-events [channel]
    # Reports schema conformance for a channel's events file.
    CH=${2:-}
    CH_EVENTS=$(channel_events_path "$CH")
    if [ ! -f "$CH_EVENTS" ]; then
      echo "no events file: $CH_EVENTS"
      exit 0
    fi
    TOTAL=$(wc -l < "$CH_EVENTS" | tr -d ' ')
    VALID=$(filter_valid_events < "$CH_EVENTS" | wc -l | tr -d ' ')
    INVALID=$((TOTAL - VALID))
    echo "channel: ${CH:-work}"
    echo "file:    $CH_EVENTS"
    echo "total:   $TOTAL"
    echo "valid:   $VALID"
    echo "invalid: $INVALID"
    if [ "$INVALID" -gt 0 ]; then
      echo ""
      echo "first 3 invalid lines:"
      awk -v script="$SCRIPT_DIR/guard.sh" 'NR<=200' "$CH_EVENTS" | \
      while IFS= read -r line; do
        if ! is_valid_event_line "$line"; then
          printf '  %s\n' "$(printf '%.200s' "$line")"
        fi
      done | head -3
    fi
    ;;

  build-index)
    # Pure-bash knowledge-index.md generator. Replaces the LLM-driven
    # regeneration in init step 6 / update step 5.4 — LLMs tend to
    # shortcut to path echoes ("bin/: bin/") which gives Claude zero
    # discovery signal. Bash extracts real topic keywords from each
    # node's title and first prohibition, producing deterministic
    # ≤15-char semantic tags every time.
    INDEX_FILE="$KG_DATA/knowledge-index.md"
    DATE=$(date +%Y-%m-%d)

    mkdir -p "$KG_DATA"
    TMP=$(mktemp -t kg-index.XXXXXX)
    echo "# KG Index ($DATE)" > "$TMP"

    COUNT=0
    find "$CLAUDE_PROJECT_DIR" \( -name "CLAUDE.md" -o -name "SKILL.md" \) \
      -not -path "*/.git/*" -not -path "*/node_modules/*" \
      -not -path "*/.knowledge-graph/*" 2>/dev/null | sort | \
    while IFS= read -r f; do
      REL="${f#$CLAUDE_PROJECT_DIR/}"
      DIR=$(dirname "$REL")
      BASE=$(basename "$DIR")
      [ "$DIR" = "." ] && BASE="root"

      # Prefer the portion after " — " in the title line (convention for kg nodes)
      TITLE=$(head -1 "$f" 2>/dev/null | sed -E 's/^#[[:space:]]*//')
      if printf '%s' "$TITLE" | grep -q '—'; then
        KW=$(printf '%s' "$TITLE" | sed -E 's/.*—[[:space:]]*//' | \
             awk '{for(i=1;i<=NF;i++){ w=tolower($i); gsub(/[^a-z0-9]/,"",w); if(length(w)>=3){print w; exit}}}')
      else
        # Fallback: first meaningful word of the first prohibition bullet
        KW=$(awk 'NR>1 && /^## Prohibitions/{flag=1; next} flag && /^- /{
          line=$0; sub(/^- */,"",line);
          for(i=1;i<=split(line, a, / /);i++){w=tolower(a[i]); gsub(/[^a-z0-9]/,"",w); if(length(w)>=4){print w; exit}}
          exit
        }' "$f" 2>/dev/null)
      fi
      [ -z "$KW" ] && KW="node"

      TAG="$BASE/$KW"
      # Trim to 15 chars
      TAG=$(printf '%s' "$TAG" | cut -c1-15)

      echo "$REL: $TAG" >> "$TMP"
      COUNT=$((COUNT + 1))
    done

    # File-line count: subtract header
    ENTRIES=$(( $(wc -l < "$TMP") - 1 ))
    mv "$TMP" "$INDEX_FILE"
    echo "knowledge-index.md built: $ENTRIES entries"
    ;;

esac

exit 0
