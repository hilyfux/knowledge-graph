#!/bin/bash
# test-pipeline.sh — P0 performance verification
# Generates a synthetic event file and verifies predict/decay stay within timeout
# Usage: bash tests/test-pipeline.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/../standalone/skills/knowledge-graph/scripts" && pwd)"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export CLAUDE_PROJECT_DIR="$TMPDIR"
mkdir -p "$TMPDIR/.knowledge-graph"

EVENTS="$TMPDIR/.knowledge-graph/graph-events.jsonl"
PASS=0
FAIL=0
TOTAL=0

# macOS date doesn't support %N; use python3 for ms-precision timestamps
now_ms() {
  python3 -c 'import time; print(int(time.time()*1000))'
}

assert_under_ms() {
  local label="$1" max_ms="$2" actual_ms="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$actual_ms" -le "$max_ms" ]; then
    echo "  PASS: $label — ${actual_ms}ms (<= ${max_ms}ms)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — ${actual_ms}ms (> ${max_ms}ms)"
    FAIL=$((FAIL + 1))
  fi
}

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_true() {
  local label="$1" command="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$command"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    FAIL=$((FAIL + 1))
  fi
}

# ── Generate 1000-line synthetic event file ──────────────────────────────────
echo "Generating 1000-line event file..."
NOW=$(date +%s)
DIRS=("src/auth" "src/api" "src/db" "src/ui" "src/utils" "src/config" "lib/core" "lib/helpers")
for i in $(seq 1 1000); do
  DIR="${DIRS[$((RANDOM % ${#DIRS[@]}))]}"
  TYPES=("r" "w:new" "w:edit" "f")
  TYPE="${TYPES[$((RANDOM % ${#TYPES[@]}))]}"
  TS=$((NOW - RANDOM % 86400))
  if [ "$TYPE" = "f" ]; then
    echo "{\"e\":\"f\",\"tool\":\"Bash\",\"err\":\"test error $i\",\"t\":$TS}" >> "$EVENTS"
  else
    echo "{\"e\":\"$TYPE\",\"p\":\"$DIR/file$((RANDOM % 10)).ts\",\"t\":$TS}" >> "$EVENTS"
  fi
done

LINE_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
echo "Generated $LINE_COUNT events"
echo ""

# ── Test 1: predict performance ──────────────────────────────────────────────
echo "Test 1: infer.sh predict (1000 events)"
START=$(now_ms)
RESULT=$(echo '{"file_path":"src/auth/login.ts"}' | bash "$SCRIPT_DIR/infer.sh" predict 2>/dev/null)
END=$(now_ms)
ELAPSED=$((END - START))
assert_under_ms "predict < 500ms" 500 "$ELAPSED"

# Verify output is valid JSON array
VALID=$(echo "$RESULT" | jq 'type' 2>/dev/null || echo "error")
assert_eq "predict returns JSON array" '"array"' "$VALID"

# ── Test 2: cochange performance ─────────────────────────────────────────────
echo ""
echo "Test 2: infer.sh cochange (1000 events)"
START=$(now_ms)
RESULT=$(bash "$SCRIPT_DIR/infer.sh" cochange 2>/dev/null)
END=$(now_ms)
ELAPSED=$((END - START))
assert_under_ms "cochange < 1000ms" 1000 "$ELAPSED"

VALID=$(echo "$RESULT" | jq 'type' 2>/dev/null || echo "error")
assert_eq "cochange returns JSON array" '"array"' "$VALID"

# ── Test 3: decay performance ────────────────────────────────────────────────
echo ""
echo "Test 3: infer.sh decay (1000 events, no CLAUDE.md files)"
START=$(now_ms)
RESULT=$(bash "$SCRIPT_DIR/infer.sh" decay 2>/dev/null)
END=$(now_ms)
ELAPSED=$((END - START))
assert_under_ms "decay < 1000ms" 1000 "$ELAPSED"

VALID=$(echo "$RESULT" | jq 'type' 2>/dev/null || echo "error")
assert_eq "decay returns JSON array" '"array"' "$VALID"

# ── Test 4: corrupt line resilience ──────────────────────────────────────────
echo ""
echo "Test 4: corrupt line resilience"
echo "THIS IS NOT JSON" >> "$EVENTS"
echo '{"e":"r","p":"src/auth/x.ts","t":'$NOW'}' >> "$EVENTS"

RESULT=$(echo '{"file_path":"src/auth/login.ts"}' | bash "$SCRIPT_DIR/infer.sh" predict 2>/dev/null)
VALID=$(echo "$RESULT" | jq 'type' 2>/dev/null || echo "error")
assert_eq "predict survives corrupt line" '"array"' "$VALID"

RESULT=$(bash "$SCRIPT_DIR/infer.sh" cochange 2>/dev/null)
VALID=$(echo "$RESULT" | jq 'type' 2>/dev/null || echo "error")
assert_eq "cochange survives corrupt line" '"array"' "$VALID"

# ── Test 5: event rotation ───────────────────────────────────────────────────
echo ""
echo "Test 5: event rotation (>500 lines)"
# File should have 1002 lines now (1000 + corrupt + valid)
PRE_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
bash "$SCRIPT_DIR/analyze.sh" stop 2>/dev/null
POST_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
assert_eq "rotation triggered (pre > 500)" "true" "$([ "$PRE_COUNT" -gt 500 ] && echo true || echo false)"
assert_eq "post-rotation <= 300 lines" "true" "$([ "$POST_COUNT" -le 300 ] && echo true || echo false)"

ARCHIVE="$TMPDIR/.knowledge-graph/graph-events-archive.jsonl"
assert_eq "archive file created" "true" "$([ -f "$ARCHIVE" ] && echo true || echo false)"

# ── Test 6: get_prohibitions multilingual ────────────────────────────────────
echo ""
echo "Test 6: get_prohibitions multilingual"
source "$SCRIPT_DIR/guard.sh"

mkdir -p "$TMPDIR/mod_cn" "$TMPDIR/mod_en"
printf '## 禁忌\n- 禁止 eval\n- 禁止 SQL 注入\n## 约定\n' > "$TMPDIR/mod_cn/CLAUDE.md"
printf '## Prohibitions\n- No eval\n- No SQL injection\n## Conventions\n' > "$TMPDIR/mod_en/CLAUDE.md"

CN=$(get_prohibitions "$TMPDIR/mod_cn/CLAUDE.md" 3)
EN=$(get_prohibitions "$TMPDIR/mod_en/CLAUDE.md" 3)
assert_eq "Chinese heading extracted" "true" "$([ -n "$CN" ] && echo true || echo false)"
assert_eq "English heading extracted" "true" "$([ -n "$EN" ] && echo true || echo false)"

# ── Test 7: initialized marker ───────────────────────────────────────────────
echo ""
echo "Test 7: initialized marker check"
# Without marker, context.sh should emit init message
TMPDIR2=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2"' EXIT
export CLAUDE_PROJECT_DIR="$TMPDIR2"
mkdir -p "$TMPDIR2/.knowledge-graph"
OUTPUT=$(bash "$SCRIPT_DIR/context.sh" startup 2>/dev/null || true)
assert_eq "uninit project emits init message" "true" "$(echo "$OUTPUT" | grep -q '初始化' && echo true || echo false)"

# With marker, should not emit init message
date +%s > "$TMPDIR2/.knowledge-graph/.initialized"
OUTPUT=$(bash "$SCRIPT_DIR/context.sh" startup 2>/dev/null || true)
assert_eq "init'd project skips init message" "true" "$(echo "$OUTPUT" | grep -q '初始化' && echo false || echo true)"

# ── Test 8: standalone/source script parity ──────────────────────────────────
echo ""
echo "Test 8: standalone/source script parity"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for script in analyze.sh context.sh guard.sh infer.sh mcp-server.sh prompt-trigger.sh track.sh; do
  assert_true "standalone matches $script" "cmp -s \"$REPO_ROOT/skills/knowledge-graph/scripts/$script\" \"$REPO_ROOT/standalone/skills/knowledge-graph/scripts/$script\""
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
