#!/bin/bash
# guard.sh — shared env guard + helpers for all kg hook scripts
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

KG_DATA="$CLAUDE_PROJECT_DIR/.knowledge-graph"
[ -d "$KG_DATA" ] || mkdir -p "$KG_DATA"

# Working set: tracks which module directories are accessed this session
# Format: {timestamp}\t{dir}\t{r|w}   (append-only, reset per session)
WS="$KG_DATA/working-set.dat"

# Prediction cache: avoids re-running infer.sh predict for known dirs
# Format: {timestamp}\t{dir}\t{pred1,pred2,...}   (one entry per dir, 300s TTL)
PRED_CACHE="$KG_DATA/pred-cache.dat"

# ── JSON / Hook helpers ───────────────────────────────────────────────────────
json_escape() { printf '%s' "$1" | jq -Rs .; }

emit_hook_context() {
  local event="${2:-SessionStart}"
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"$event\",\"additionalContext\":$1}}"
}

# ── Working Set ───────────────────────────────────────────────────────────────

ws_touch() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-r}" >> "$WS" 2>/dev/null
}

# Returns 0 if module was accessed before in this session
ws_is_paged_in() {
  [ ! -f "$WS" ] && return 1
  awk -F'\t' -v d="$1" '$2 == d {found=1; exit} END {exit !found}' "$WS" 2>/dev/null
}

ws_top() {
  local n="${1:-5}"
  [ ! -f "$WS" ] && return
  awk -F'\t' '{print $2}' "$WS" 2>/dev/null | sort | uniq -c | sort -rn | head -"$n" | awk '{print $2}'
}

ws_dirty() {
  [ ! -f "$WS" ] && return
  awk -F'\t' '$3 == "w" {print $2}' "$WS" 2>/dev/null | sort -u
}

# ── Prediction Cache ──────────────────────────────────────────────────────────

# Outputs predicted dirs (one per line). Returns 1 on miss or expired.
tlb_get() {
  local dir="$1" now="$2"
  [ ! -f "$PRED_CACHE" ] && return 1
  local line
  line=$(awk -F'\t' -v d="$dir" '$2 == d {print; exit}' "$PRED_CACHE" 2>/dev/null)
  [ -z "$line" ] && return 1
  local cached_ts
  cached_ts=$(printf '%s' "$line" | cut -f1)
  [ $((now - cached_ts)) -ge 300 ] && return 1
  printf '%s' "$line" | cut -f3 | tr ',' '\n'
  return 0
}

tlb_set() {
  local ts="$1" dir="$2" preds_csv="$3"
  if [ -f "$PRED_CACHE" ]; then
    awk -F'\t' -v d="$dir" '$2 != d' "$PRED_CACHE" > "$PRED_CACHE.tmp" 2>/dev/null
    mv "$PRED_CACHE.tmp" "$PRED_CACHE" 2>/dev/null
  fi
  printf '%s\t%s\t%s\n' "$ts" "$dir" "$preds_csv" >> "$PRED_CACHE" 2>/dev/null
}

tlb_invalidate() {
  local dir="$1"
  # Skip if file missing or empty
  [ ! -s "$PRED_CACHE" ] && return
  awk -F'\t' -v d="$dir" '$2 != d' "$PRED_CACHE" > "$PRED_CACHE.tmp" 2>/dev/null
  mv "$PRED_CACHE.tmp" "$PRED_CACHE" 2>/dev/null
}

# ── Shared: extract prohibitions from a module CLAUDE.md ──────────────────────
get_prohibitions() {
  local cmd_file="$1" max="${2:-3}"
  [ ! -f "$cmd_file" ] && return
  # macOS sed BRE does not support \|, use -E for extended regex
  sed -nE '/^## (禁忌|Prohibitions|Rules|Constraints)/,/^## /{ /^## /d; /^$/d; p; }' "$cmd_file" 2>/dev/null | head -"$max"
}

# ── Shared: save working state snapshot ───────────────────────────────────────
# Called from Stop hook and PreCompact hook. Single awk pass for module stats.
save_snapshot() {
  local snapshot="$KG_DATA/work-snapshot.md"
  local events="$KG_DATA/graph-events.jsonl"
  {
    echo "# 工作快照 ($(date '+%m/%d %H:%M'))"

    if [ -f "$WS" ] && [ -s "$WS" ]; then
      # Single awk pass: compute r/w counts for all modules at once
      printf '\n## 活跃模块\n'
      awk -F'\t' '
        {r[$2]+=($3=="r"); w[$2]+=($3=="w"); total[$2]++}
        END {for(d in total) printf "%d\t%s\t%d\t%d\n",total[d],d,r[d],w[d]}
      ' "$WS" 2>/dev/null | sort -rn | head -8 | awk -F'\t' '{printf "- %s (r:%s w:%s)\n",$2,$3,$4}'

      # Dirty modules
      local dirty
      dirty=$(ws_dirty)
      if [ -n "$dirty" ]; then
        printf '\n## 修改的模块\n'
        echo "$dirty" | sed 's/^/- /'
      fi
    elif [ -f "$events" ] && [ -s "$events" ]; then
      # Fallback: derive from events
      local edited
      edited=$(tail -200 "$events" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null \
        | sort | uniq -c | sort -rn | head -8 | awk '{printf "- %s (%d次)\n", $2, $1}')
      [ -n "$edited" ] && printf '\n## 编辑文件\n%s\n' "$edited"
    fi

    # Recent failures
    if [ -f "$events" ] && [ -s "$events" ]; then
      local fails
      fails=$(tail -200 "$events" | jq -r 'select(.e == "f") | "\(.tool): \(.err)"' 2>/dev/null \
        | sort -u | head -3)
      [ -n "$fails" ] && printf '\n## 遇到的问题\n%s\n' "$(echo "$fails" | sed 's/^/- /')"
    fi

    # Recent commits
    if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
      local commits
      commits=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -5 --since="2 hours ago" 2>/dev/null)
      [ -n "$commits" ] && printf '\n## 本次提交\n%s\n' "$(echo "$commits" | sed 's/^/- /')"
    fi
  } > "$snapshot"
}

# ── Shared: inject working set module prohibitions ────────────────────────────
inject_working_set_rules() {
  local max="${1:-5}"
  local ctx=""
  local dirs
  dirs=$(ws_top "$max")
  [ -z "$dirs" ] && return

  while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    local rules
    rules=$(get_prohibitions "$CLAUDE_PROJECT_DIR/$dir/CLAUDE.md" 3)
    [ -n "$rules" ] && ctx="$ctx\n[$dir 禁忌] $rules"
  done <<< "$dirs"

  [ -n "$ctx" ] && printf '%s' "$ctx"
}
