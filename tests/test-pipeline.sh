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

# macOS date doesn't support %N; prefer lightweight Perl for ms timestamps.
now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
  else
    python3 -c 'import time; print(int(time.time()*1000))'
  fi
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
assert_eq "uninit project emits init message" "true" "$(echo "$OUTPUT" | grep -q 'not initialized' && echo true || echo false)"

# With marker, should not emit init message
date +%s > "$TMPDIR2/.knowledge-graph/.initialized"
OUTPUT=$(bash "$SCRIPT_DIR/context.sh" startup 2>/dev/null || true)
assert_eq "init'd project skips init message" "true" "$(echo "$OUTPUT" | grep -q 'not initialized' && echo false || echo true)"

# ── Test 8: track.sh excludes .knowledge-graph/ and .claude/ (bug C fix) ─────
echo ""
echo "Test 8: track.sh excludes runtime/infra paths"
TMPDIR3=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3"' EXIT
export CLAUDE_PROJECT_DIR="$TMPDIR3"
mkdir -p "$TMPDIR3/.knowledge-graph" "$TMPDIR3/.claude" "$TMPDIR3/src"
EV3="$TMPDIR3/.knowledge-graph/graph-events.jsonl"
: > "$EV3"

feed() {
  printf '%s' "$1" | bash "$SCRIPT_DIR/track.sh" write >/dev/null 2>&1 || true
}
# tool_name must be Write/Edit for track.sh to append an event
feed '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMPDIR3"'/.knowledge-graph/foo.jsonl"}}'
feed '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMPDIR3"'/.claude/settings.json"}}'
feed '{"tool_name":"Edit","tool_input":{"file_path":"'"$TMPDIR3"'/src/real.js"}}'

# Count matches robustly (grep -c prints "0" and exits 1 on no-match,
# which || echo 0 would double-emit — use awk+wc instead)
count_lines() {
  awk -v pat="$1" '$0 ~ pat' "$2" 2>/dev/null | wc -l | tr -d ' '
}
KG_COUNT=$(count_lines '"p":"\.knowledge-graph' "$EV3")
CL_COUNT=$(count_lines '"p":"\.claude'          "$EV3")
SRC_COUNT=$(count_lines '"p":"src/'             "$EV3")
assert_eq ".knowledge-graph/ writes not recorded"  "0" "$KG_COUNT"
assert_eq ".claude/ writes not recorded"           "0" "$CL_COUNT"
assert_eq "src/ writes ARE recorded"               "1" "$SRC_COUNT"

# ── Test 9: context.sh startup does NOT early-exit on trigger (bug A fix) ────
echo ""
echo "Test 9: context.sh startup preserves snapshot alongside trigger notice"
TMPDIR4=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4"' EXIT
export CLAUDE_PROJECT_DIR="$TMPDIR4"
mkdir -p "$TMPDIR4/.knowledge-graph" "$TMPDIR4/src/undocumented"
date +%s > "$TMPDIR4/.knowledge-graph/.initialized"
# Snapshot must exist to test preservation
printf '# 工作快照 (test)\n## 活跃模块\n- src/undocumented (r:0 w:5)\n' > "$TMPDIR4/.knowledge-graph/work-snapshot.md"
# Feed 6 write events into a dir lacking CLAUDE.md to trigger MISSING_NODES > 0
EV4="$TMPDIR4/.knowledge-graph/graph-events.jsonl"
for i in 1 2 3 4 5 6; do
  printf '{"e":"w:edit","p":"src/undocumented/file%d.js","t":%d}\n' "$i" "$(date +%s)" >> "$EV4"
done
OUT9=$(bash "$SCRIPT_DIR/context.sh" startup 2>/dev/null || true)
assert_eq "snapshot injected alongside trigger" "true" \
  "$(echo "$OUT9" | grep -q '工作快照' && echo true || echo false)"
assert_eq "trigger notice also appended"        "true" \
  "$(echo "$OUT9" | grep -q 'kg auto-trigger' && echo true || echo false)"

# ── Test 10: analyze.sh auto-detect skips runtime/ghost dirs (bug B+C fix) ───
echo ""
echo "Test 10: auto-detect ignores runtime and ghost dirs"
TMPDIR5=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5"' EXIT
export CLAUDE_PROJECT_DIR="$TMPDIR5"
mkdir -p "$TMPDIR5/.knowledge-graph"
date +%s > "$TMPDIR5/.knowledge-graph/.initialized"
EV5="$TMPDIR5/.knowledge-graph/graph-events.jsonl"
for i in 1 2 3 4 5 6; do
  printf '{"e":"w:edit","p":".knowledge-graph/x.jsonl","t":%d}\n' "$(date +%s)" >> "$EV5"
done
for i in 1 2 3; do
  printf '{"e":"w:edit","p":"ghost-dir/x.js","t":%d}\n' "$(date +%s)" >> "$EV5"
done
OUT10=$(bash "$SCRIPT_DIR/analyze.sh" auto-detect 2>/dev/null || true)
assert_eq "auto-detect says Status: OK (no fake missing)" "true" \
  "$(echo "$OUT10" | grep -q 'Status: OK' && echo true || echo false)"
assert_eq "auto-detect does NOT emit '[AUTO] Execute update'" "true" \
  "$(echo "$OUT10" | grep -q 'Execute update' && echo false || echo true)"

# ── Test 11: blind_spots filter + SKILL.md recognition (analyze) ─────────────
echo ""
echo "Test 11: blind_spots excludes SKILL.md dirs and ghost paths"
mkdir -p "$TMPDIR5/skill-mod" "$TMPDIR5/code-mod"
printf '# skill-mod\n' > "$TMPDIR5/skill-mod/SKILL.md"
printf '# code-mod\n' > "$TMPDIR5/code-mod/CLAUDE.md"
# Generate events that would naively flag all three as blind spots
: > "$EV5"
for i in 1 2 3 4 5 6; do
  printf '{"e":"w:edit","p":"skill-mod/a.sh","t":%d}\n' "$(date +%s)" >> "$EV5"
  printf '{"e":"r","p":"skill-mod/a.sh","t":%d}\n' "$(date +%s)" >> "$EV5"
  printf '{"e":"w:edit","p":"code-mod/a.js","t":%d}\n' "$(date +%s)" >> "$EV5"
  printf '{"e":"r","p":"code-mod/a.js","t":%d}\n' "$(date +%s)" >> "$EV5"
  printf '{"e":"w:edit","p":"ghost-dir/a.js","t":%d}\n' "$(date +%s)" >> "$EV5"
  printf '{"e":"r","p":"ghost-dir/a.js","t":%d}\n' "$(date +%s)" >> "$EV5"
done
bash "$SCRIPT_DIR/analyze.sh" analyze 2>/dev/null || true
BLIND=$(jq -r '.blind_spots | join(",")' "$TMPDIR5/.knowledge-graph/graph-analysis.json" 2>/dev/null)
assert_eq "SKILL.md dir not in blind_spots"  "true" \
  "$([ "${BLIND/skill-mod/}" = "$BLIND" ] && echo true || echo false)"
assert_eq "CLAUDE.md dir not in blind_spots" "true" \
  "$([ "${BLIND/code-mod/}" = "$BLIND" ] && echo true || echo false)"
assert_eq "ghost dir not in blind_spots"     "true" \
  "$([ "${BLIND/ghost-dir/}" = "$BLIND" ] && echo true || echo false)"

# ── Test 12: broken_refs dual-resolve + placeholder skip (analyze) ───────────
echo ""
echo "Test 12: broken_refs resolves both relative and project-root paths"
mkdir -p "$TMPDIR5/src/foo"
printf '# root\n' > "$TMPDIR5/CLAUDE.md"
printf '# foo\n' > "$TMPDIR5/src/foo/CLAUDE.md"
printf '# leaf\n- When Changing → @src/foo/CLAUDE.md\n- Placeholder → @{path}/CLAUDE.md\n' \
  > "$TMPDIR5/code-mod/CLAUDE.md"
bash "$SCRIPT_DIR/analyze.sh" analyze 2>/dev/null || true
BROKEN=$(jq -r '.broken_refs | length' "$TMPDIR5/.knowledge-graph/graph-analysis.json" 2>/dev/null)
assert_eq "cross-module @ref resolves (not broken)" "0" "$BROKEN"

# ── Test 13: non-Claude env fallback (Codex / MCP) ───────────────────────────
echo ""
echo "Test 13: scripts resolve KG_PROJECT_DIR without CLAUDE_PROJECT_DIR"
TMPDIR6=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5" "$TMPDIR6"' EXIT
unset CLAUDE_PROJECT_DIR
export KG_PROJECT_DIR="$TMPDIR6"
mkdir -p "$TMPDIR6/.knowledge-graph"
OUT13=$(bash "$SCRIPT_DIR/analyze.sh" quick-status 2>/dev/null || true)
assert_eq "analyze status works with KG_PROJECT_DIR" "true" \
  "$(echo "$OUT13" | grep -q 'Pending events:' && echo true || echo false)"
assert_eq "guard exports CLAUDE_PROJECT_DIR fallback" "true" \
  "$(bash -c 'source "$1/guard.sh"; [ "$CLAUDE_PROJECT_DIR" = "$KG_PROJECT_DIR" ] && echo true || echo false' _ "$SCRIPT_DIR")"
unset KG_PROJECT_DIR
export CLAUDE_PROJECT_DIR="$TMPDIR5"

# ── Test 14: AGENTS.md is adapter-only; CLAUDE.md remains canonical ──────────
echo ""
echo "Test 14: AGENTS.md does not satisfy canonical module knowledge"
TMPDIR7=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5" "$TMPDIR6" "$TMPDIR7"' EXIT
export CLAUDE_PROJECT_DIR="$TMPDIR7"
mkdir -p "$TMPDIR7/.knowledge-graph" "$TMPDIR7/codex-mod"
printf '# codex adapter\n## Prohibitions\n- Adapter-only rule\n' > "$TMPDIR7/codex-mod/AGENTS.md"
EV7="$TMPDIR7/.knowledge-graph/graph-events.jsonl"
for i in 1 2 3 4; do
  printf '{"e":"w:edit","p":"codex-mod/file%d.ts","t":%d}\n' "$i" "$(date +%s)" >> "$EV7"
  printf '{"e":"r","p":"codex-mod/file%d.ts","t":%d}\n' "$i" "$(date +%s)" >> "$EV7"
done
bash "$SCRIPT_DIR/analyze.sh" analyze 2>/dev/null || true
BLIND7=$(jq -r '.blind_spots | join(",")' "$TMPDIR7/.knowledge-graph/graph-analysis.json" 2>/dev/null)
assert_eq "AGENTS.md-only dir remains blind_spot" "true" \
  "$([ "${BLIND7/codex-mod/}" != "$BLIND7" ] && echo true || echo false)"
printf '# codex-mod\n## Prohibitions\n- Canonical rule\n' > "$TMPDIR7/codex-mod/CLAUDE.md"
bash "$SCRIPT_DIR/analyze.sh" analyze 2>/dev/null || true
BLIND7B=$(jq -r '.blind_spots | join(",")' "$TMPDIR7/.knowledge-graph/graph-analysis.json" 2>/dev/null)
assert_eq "CLAUDE.md dir not in blind_spots" "true" \
  "$([ "${BLIND7B/codex-mod/}" = "$BLIND7B" ] && echo true || echo false)"
MCP7=$(printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"kg_read_node","arguments":{"module_path":"codex-mod"}}}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
assert_eq "kg_read_node reads canonical CLAUDE.md" "true" \
  "$(echo "$MCP7" | grep -q 'Canonical rule' && echo true || echo false)"
assert_eq "kg_read_node ignores adapter AGENTS.md" "true" \
  "$(echo "$MCP7" | grep -q 'Adapter-only rule' && echo false || echo true)"

# ── Test 15: MCP resource scan prunes runtime/dependency/build dirs ──────────
echo ""
echo "Test 15: MCP resource scan prunes runtime/dependency/build dirs"
TMPDIR8=$(mktemp -d)
OUTSIDE8=$(mktemp -d "$(dirname "$TMPDIR8")/kg-outside.XXXXXX")
OUTSIDE8_REL="../$(basename "$OUTSIDE8")"
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5" "$TMPDIR6" "$TMPDIR7" "$TMPDIR8" "$OUTSIDE8"' EXIT
export CLAUDE_PROJECT_DIR="$TMPDIR8"
mkdir -p \
  "$TMPDIR8/.knowledge-graph" \
  "$TMPDIR8/src/real" \
  "$TMPDIR8/.claude/skills/knowledge-graph" \
  "$TMPDIR8/node_modules/pkg" \
  "$TMPDIR8/dist" \
  "$TMPDIR8/.worktrees/feature"
printf '# root node\n' > "$TMPDIR8/CLAUDE.md"
printf '# real module\n' > "$TMPDIR8/src/real/CLAUDE.md"
printf '# runtime skill copy\n' > "$TMPDIR8/.claude/skills/knowledge-graph/SKILL.md"
printf '# dependency node\n' > "$TMPDIR8/node_modules/pkg/CLAUDE.md"
printf '# build node\n' > "$TMPDIR8/dist/CLAUDE.md"
printf '# worktree node\n' > "$TMPDIR8/.worktrees/feature/CLAUDE.md"
printf '# outside node\n' > "$OUTSIDE8/CLAUDE.md"
MCP15=$(printf '{"jsonrpc":"2.0","id":1,"method":"resources/list","params":{}}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
GUARD15=$(bash -c 'source "$1/guard.sh"; find_knowledge_nodes' _ "$SCRIPT_DIR" 2>/dev/null || true)
GUARD15_TRAVERSAL=$(bash -c 'source "$1/guard.sh"; knowledge_node_path "$2"' _ "$SCRIPT_DIR" "$OUTSIDE8_REL" 2>/dev/null || true)
assert_eq "resources/list includes root node" "true" \
  "$(echo "$MCP15" | grep -q 'CLAUDE.md' && echo true || echo false)"
assert_eq "resources/list includes source module" "true" \
  "$(echo "$MCP15" | grep -q 'src/real/CLAUDE.md' && echo true || echo false)"
assert_eq "resources/list excludes .claude runtime copy" "true" \
  "$(echo "$MCP15" | grep -q '.claude/skills/knowledge-graph/SKILL.md' && echo false || echo true)"
assert_eq "resources/list excludes node_modules" "true" \
  "$(echo "$MCP15" | grep -q 'node_modules/pkg/CLAUDE.md' && echo false || echo true)"
assert_eq "resources/list excludes build output" "true" \
  "$(echo "$MCP15" | grep -q 'dist/CLAUDE.md' && echo false || echo true)"
assert_eq "resources/list excludes worktrees" "true" \
  "$(echo "$MCP15" | grep -q '.worktrees/feature/CLAUDE.md' && echo false || echo true)"
assert_eq "shared scan includes source module" "true" \
  "$(echo "$GUARD15" | grep -q 'src/real/CLAUDE.md' && echo true || echo false)"
assert_eq "shared scan excludes .claude runtime copy" "true" \
  "$(echo "$GUARD15" | grep -q '.claude/skills/knowledge-graph/SKILL.md' && echo false || echo true)"
assert_eq "shared scan excludes node_modules" "true" \
  "$(echo "$GUARD15" | grep -q 'node_modules/pkg/CLAUDE.md' && echo false || echo true)"
assert_eq "shared scan excludes build output" "true" \
  "$(echo "$GUARD15" | grep -q 'dist/CLAUDE.md' && echo false || echo true)"
assert_eq "shared scan excludes worktrees" "true" \
  "$(echo "$GUARD15" | grep -q '.worktrees/feature/CLAUDE.md' && echo false || echo true)"
assert_eq "shared lookup rejects path traversal" "" "$GUARD15_TRAVERSAL"

# ── Test 16: MCP preserves string JSON-RPC ids ───────────────────────────────
echo ""
echo "Test 16: MCP preserves string JSON-RPC ids"
MCP16_INIT=$(printf '{"jsonrpc":"2.0","id":"req-init","method":"initialize","params":{}}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP16_TOOL=$(printf '{"jsonrpc":"2.0","id":"req-status","method":"tools/call","params":{"name":"kg_status","arguments":{}}}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
assert_eq "initialize with string id returns valid JSON" "true" \
  "$(echo "$MCP16_INIT" | jq -e '.jsonrpc == "2.0"' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "initialize preserves string id" "true" \
  "$(echo "$MCP16_INIT" | jq -e '.id == "req-init"' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "initialize includes concise server instructions" "true" \
  "$(echo "$MCP16_INIT" | jq -e '(.result.instructions | type == "string") and (.result.instructions | length <= 512) and (.result.instructions | contains("kg_status")) and (.result.instructions | contains("kg_query")) and (.result.instructions | contains("kg_read_node")) and (.result.instructions | contains(".knowledge-graph/"))' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "tool call with string id returns valid JSON" "true" \
  "$(echo "$MCP16_TOOL" | jq -e '.jsonrpc == "2.0"' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "tool call preserves string id" "true" \
  "$(echo "$MCP16_TOOL" | jq -e '.id == "req-status"' >/dev/null 2>&1 && echo true || echo false)"

# ── Test 17: MCP returns JSON-RPC errors for invalid input ───────────────────
echo ""
echo "Test 17: MCP returns JSON-RPC errors for invalid input"
MCP17_PARSE=$(printf 'not-json\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP17_INVALID=$(printf '[1,2,3]\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP17_EMPTY_OBJECT=$(printf '{}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP17_MISSING_METHOD=$(printf '{"jsonrpc":"2.0","id":50}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP17_BAD_METHOD=$(printf '{"jsonrpc":"2.0","id":51,"method":123}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP17_BAD_VERSION=$(printf '{"jsonrpc":"1.0","id":52,"method":"tools/list"}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
assert_eq "malformed JSON returns parse error" "true" \
  "$(echo "$MCP17_PARSE" | jq -e '.jsonrpc == "2.0" and .id == null and .error.code == -32700' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "non-object JSON returns invalid request" "true" \
  "$(echo "$MCP17_INVALID" | jq -e '.jsonrpc == "2.0" and .id == null and .error.code == -32600' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "empty object returns invalid request" "true" \
  "$(echo "$MCP17_EMPTY_OBJECT" | jq -e '.jsonrpc == "2.0" and .id == null and .error.code == -32600' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "missing method returns invalid request" "true" \
  "$(echo "$MCP17_MISSING_METHOD" | jq -e '.jsonrpc == "2.0" and .id == 50 and .error.code == -32600' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "non-string method returns invalid request" "true" \
  "$(echo "$MCP17_BAD_METHOD" | jq -e '.jsonrpc == "2.0" and .id == 51 and .error.code == -32600' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "wrong jsonrpc version returns invalid request" "true" \
  "$(echo "$MCP17_BAD_VERSION" | jq -e '.jsonrpc == "2.0" and .id == 52 and .error.code == -32600' >/dev/null 2>&1 && echo true || echo false)"

# ── Test 18: MCP does not respond to JSON-RPC notifications ──────────────────
echo ""
echo "Test 18: MCP does not respond to JSON-RPC notifications"
MCP18_NOTIFY=$(printf '%s\n%s\n%s\n' \
  '{"jsonrpc":"2.0","method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","method":"resources/list","params":{}}' \
  '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"kg_status","arguments":{}}}' \
  | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
assert_eq "known-method notifications produce no stdout" "" "$MCP18_NOTIFY"

# ── Test 19: MCP validates tools/call params shape ───────────────────────────
echo ""
echo "Test 19: MCP validates tools/call params shape"
MCP18_ARRAY=$(printf '{"jsonrpc":"2.0","id":18,"method":"tools/call","params":[]}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP18_MISSING=$(printf '{"jsonrpc":"2.0","id":19,"method":"tools/call"}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
assert_eq "tools/call array params returns invalid params" "true" \
  "$(echo "$MCP18_ARRAY" | jq -e '.jsonrpc == "2.0" and .id == 18 and .error.code == -32602' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "tools/call missing params returns invalid params" "true" \
  "$(echo "$MCP18_MISSING" | jq -e '.jsonrpc == "2.0" and .id == 19 and .error.code == -32602' >/dev/null 2>&1 && echo true || echo false)"

# ── Test 20: MCP validates resources/read params shape ───────────────────────
echo ""
echo "Test 20: MCP validates resources/read params shape"
MCP19_ARRAY=$(printf '{"jsonrpc":"2.0","id":20,"method":"resources/read","params":[]}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP19_MISSING=$(printf '{"jsonrpc":"2.0","id":21,"method":"resources/read"}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP19_BAD_URI=$(printf '{"jsonrpc":"2.0","id":22,"method":"resources/read","params":{"uri":123}}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
assert_eq "resources/read array params returns invalid params" "true" \
  "$(echo "$MCP19_ARRAY" | jq -e '.jsonrpc == "2.0" and .id == 20 and .error.code == -32602' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "resources/read missing params returns invalid params" "true" \
  "$(echo "$MCP19_MISSING" | jq -e '.jsonrpc == "2.0" and .id == 21 and .error.code == -32602' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "resources/read non-string uri returns invalid params" "true" \
  "$(echo "$MCP19_BAD_URI" | jq -e '.jsonrpc == "2.0" and .id == 22 and .error.code == -32602' >/dev/null 2>&1 && echo true || echo false)"

# ── Test 21: MCP confines resource paths to project root ─────────────────────
echo ""
echo "Test 21: MCP confines resource paths to project root"
TMPDIR9=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5" "$TMPDIR6" "$TMPDIR7" "$TMPDIR8" "$TMPDIR9"' EXIT
PROJECT9="$TMPDIR9/project"
OUTSIDE9="$TMPDIR9/outside"
export CLAUDE_PROJECT_DIR="$PROJECT9"
mkdir -p "$PROJECT9/.knowledge-graph" "$PROJECT9/src" "$OUTSIDE9"
printf '# project root\n' > "$PROJECT9/CLAUDE.md"
printf '# source node\n' > "$PROJECT9/src/CLAUDE.md"
printf '# outside leak\n' > "$OUTSIDE9/CLAUDE.md"
MCP20_TOOL=$(printf '{"jsonrpc":"2.0","id":23,"method":"tools/call","params":{"name":"kg_read_node","arguments":{"module_path":"../outside"}}}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
MCP20_RESOURCE=$(printf '{"jsonrpc":"2.0","id":24,"method":"resources/read","params":{"uri":"kg://claude/../outside"}}\n' | bash "$SCRIPT_DIR/mcp-server.sh" 2>/dev/null || true)
assert_eq "kg_read_node rejects path traversal" "true" \
  "$(echo "$MCP20_TOOL" | jq -e '.jsonrpc == "2.0" and .id == 23 and .error.code == -32602' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "resources/read rejects path traversal" "true" \
  "$(echo "$MCP20_RESOURCE" | jq -e '.jsonrpc == "2.0" and .id == 24 and .error.code == -32602' >/dev/null 2>&1 && echo true || echo false)"
assert_eq "path traversal does not leak outside node content" "true" \
  "$(printf '%s\n%s\n' "$MCP20_TOOL" "$MCP20_RESOURCE" | grep -q 'outside leak' && echo false || echo true)"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── Test 22: installer stays project-level only for Codex/MCP ────────────────
echo ""
echo "Test 22: installer stays project-level only for Codex/MCP"
TMPDIR10=$(mktemp -d)
trap 'rm -rf "$TMPDIR" "$TMPDIR2" "$TMPDIR3" "$TMPDIR4" "$TMPDIR5" "$TMPDIR6" "$TMPDIR7" "$TMPDIR8" "$TMPDIR9" "$TMPDIR10"' EXIT
TARGET8="$TMPDIR10/project"
HOME8="$TMPDIR10/home"
FAKEBIN8="$TMPDIR10/bin"
CODEX_LOG8="$TMPDIR10/codex.log"
CODEX_CONFIG8="$HOME8/.codex/config.toml"
mkdir -p "$TARGET8" "$FAKEBIN8" "$(dirname "$CODEX_CONFIG8")"
cat > "$CODEX_CONFIG8" <<EOF
[mcp_servers.knowledge-graph]
command = "bash"
args = ["/old/project/.claude/skills/knowledge-graph/scripts/mcp-server.sh"]

[mcp_servers.knowledge-graph.env]
KG_PROJECT_DIR = "/old/project"
EOF
cat > "$FAKEBIN8/codex" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CODEX_TEST_LOG"
case "$*" in
  "mcp get knowledge-graph") exit 1 ;;
  "mcp remove knowledge-graph") exit 0 ;;
  mcp\ add\ knowledge-graph*) exit 0 ;;
  mcp*) exit 0 ;;
esac
exit 0
SH
chmod +x "$FAKEBIN8/codex"
CODEX_TEST_LOG="$CODEX_LOG8" HOME="$HOME8" PATH="$FAKEBIN8:$PATH" bash "$REPO_ROOT/standalone/install.sh" "$TARGET8" >/dev/null 2>&1
assert_eq "installer does NOT call user-level codex mcp" "true" \
  "$([ ! -s "$CODEX_LOG8" ] && echo true || echo false)"
assert_eq "codex user config stays unchanged" "true" \
  "$(grep -q '/old/project/.claude/skills/knowledge-graph/scripts/mcp-server.sh' "$CODEX_CONFIG8" 2>/dev/null && echo true || echo false)"
assert_eq "codex user config does NOT point at installed server" "true" \
  "$(grep -q "$TARGET8/.claude/skills/knowledge-graph/scripts/mcp-server.sh" "$CODEX_CONFIG8" 2>/dev/null && echo false || echo true)"
assert_eq "project .mcp.json has startup timeout" "true" \
  "$(jq -e '.mcpServers["knowledge-graph"].startup_timeout_sec == 60' "$TARGET8/.mcp.json" >/dev/null 2>&1 && echo true || echo false)"
assert_eq "project .mcp.json points at installed server" "true" \
  "$(jq -e --arg p "$TARGET8/.claude/skills/knowledge-graph/scripts/mcp-server.sh" '.mcpServers["knowledge-graph"].args == [$p]' "$TARGET8/.mcp.json" >/dev/null 2>&1 && echo true || echo false)"
assert_eq "project .codex config has managed MCP block" "true" \
  "$(grep -qF '# knowledge-graph:codex-mcp begin' "$TARGET8/.codex/config.toml" 2>/dev/null && echo true || echo false)"
assert_eq "project .codex config has startup timeout" "true" \
  "$(grep -qF 'startup_timeout_sec = 60' "$TARGET8/.codex/config.toml" 2>/dev/null && echo true || echo false)"
assert_eq "project .codex config points at installed server" "true" \
  "$(grep -qF "args = [\"$TARGET8/.claude/skills/knowledge-graph/scripts/mcp-server.sh\"]" "$TARGET8/.codex/config.toml" 2>/dev/null && echo true || echo false)"
assert_eq "project .codex config sets KG_PROJECT_DIR" "true" \
  "$(grep -qF "KG_PROJECT_DIR = \"$TARGET8\"" "$TARGET8/.codex/config.toml" 2>/dev/null && echo true || echo false)"
assert_eq "gitignore excludes generated project codex config" "true" \
  "$(grep -qxF '.codex/config.toml' "$TARGET8/.gitignore" 2>/dev/null && echo true || echo false)"
TARGET8_CODEX_EXISTING="$TMPDIR10/project-codex-existing"
mkdir -p "$TARGET8_CODEX_EXISTING/.codex"
printf 'model = "gpt-5.4"\n' > "$TARGET8_CODEX_EXISTING/.codex/config.toml"
HOME="$HOME8" PATH="$FAKEBIN8:$PATH" bash "$REPO_ROOT/standalone/install.sh" "$TARGET8_CODEX_EXISTING" >/dev/null 2>&1
assert_eq "installer preserves existing project codex config" "true" \
  "$(grep -qF 'model = "gpt-5.4"' "$TARGET8_CODEX_EXISTING/.codex/config.toml" 2>/dev/null && echo true || echo false)"
CODEX_MCP_STARTUP_TIMEOUT_SEC=75 HOME="$HOME8" PATH="$FAKEBIN8:$PATH" bash "$REPO_ROOT/standalone/install.sh" "$TARGET8_CODEX_EXISTING" >/dev/null 2>&1
assert_eq "installer replaces managed project codex block" "1" \
  "$(grep -cF '# knowledge-graph:codex-mcp begin' "$TARGET8_CODEX_EXISTING/.codex/config.toml" 2>/dev/null || echo 0)"
assert_eq "installer updates project codex startup timeout" "true" \
  "$(grep -qF 'startup_timeout_sec = 75' "$TARGET8_CODEX_EXISTING/.codex/config.toml" 2>/dev/null && echo true || echo false)"
TARGET8_EXISTING="$TMPDIR10/project-existing"
mkdir -p "$TARGET8_EXISTING"
printf '{"mcpServers": null, "preserve": "yes"}\n' > "$TARGET8_EXISTING/.mcp.json"
HOME="$HOME8" PATH="$FAKEBIN8:$PATH" bash "$REPO_ROOT/standalone/install.sh" "$TARGET8_EXISTING" >/dev/null 2>&1
assert_eq "installer normalizes missing mcpServers object" "true" \
  "$(jq -e --arg p "$TARGET8_EXISTING/.claude/skills/knowledge-graph/scripts/mcp-server.sh" '.preserve == "yes" and .mcpServers["knowledge-graph"].args == [$p] and .mcpServers["knowledge-graph"].startup_timeout_sec == 60' "$TARGET8_EXISTING/.mcp.json" >/dev/null 2>&1 && echo true || echo false)"
TARGET8_BAD_SHAPE="$TMPDIR10/project-bad-shape"
mkdir -p "$TARGET8_BAD_SHAPE"
printf '{"mcpServers":[]}\n' > "$TARGET8_BAD_SHAPE/.mcp.json"
BAD_SHAPE_OUT=$(HOME="$HOME8" PATH="$FAKEBIN8:$PATH" bash "$REPO_ROOT/standalone/install.sh" "$TARGET8_BAD_SHAPE" 2>&1 || true)
assert_eq "installer rejects non-object mcpServers clearly" "true" \
  "$(echo "$BAD_SHAPE_OUT" | grep -q 'mcpServers 必须是 object' && echo true || echo false)"
assert_eq "installer preserves invalid-shaped .mcp.json" '{"mcpServers":[]}' \
  "$(tr -d '\n' < "$TARGET8_BAD_SHAPE/.mcp.json")"
TARGET8_BAD_JSON="$TMPDIR10/project-bad-json"
mkdir -p "$TARGET8_BAD_JSON"
printf '{"mcpServers":\n' > "$TARGET8_BAD_JSON/.mcp.json"
BAD_JSON_OUT=$(HOME="$HOME8" PATH="$FAKEBIN8:$PATH" bash "$REPO_ROOT/standalone/install.sh" "$TARGET8_BAD_JSON" 2>&1 || true)
assert_eq "installer rejects malformed .mcp.json clearly" "true" \
  "$(echo "$BAD_JSON_OUT" | grep -q '.mcp.json 必须是 JSON object' && echo true || echo false)"
assert_eq "installer preserves malformed .mcp.json" '{"mcpServers":' \
  "$(tr -d '\n' < "$TARGET8_BAD_JSON/.mcp.json")"
HOME_INSTALL_OUT=$(HOME="$HOME8" PATH="$FAKEBIN8:$PATH" bash "$REPO_ROOT/standalone/install.sh" "$HOME8" 2>&1 || true)
assert_eq "installer rejects HOME as target" "true" \
  "$(echo "$HOME_INSTALL_OUT" | grep -q '不能安装到 HOME 目录' && echo true || echo false)"

# ── Test 23: standalone/source script parity ─────────────────────────────────
echo ""
echo "Test 23: standalone/source script parity"
for script in analyze.sh context.sh guard.sh infer.sh mcp-server.sh prompt-trigger.sh track.sh; do
  assert_true "standalone matches $script" "cmp -s \"$REPO_ROOT/skills/knowledge-graph/scripts/$script\" \"$REPO_ROOT/standalone/skills/knowledge-graph/scripts/$script\""
done

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════"
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
