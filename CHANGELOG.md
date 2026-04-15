# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning where practical.

## [Unreleased]

## [1.2.2] - 2026-04-15

### Fixed — The "kg was running but invisible" pass

Live-debug session against a real project (silly-code) surfaced a class of
bugs where the pipeline was recording and predicting correctly, but the
main Claude session never saw the output. Sub-agents did, hiding the
problem. Five related issues, all in the same family:

- **`context.sh startup` early-exit wiped the snapshot.** When auto-update
  conditions triggered, the hook emitted a one-line trigger notice and
  exited — discarding the full work snapshot that was already prepared.
  Now appended to context instead; main session gets snapshot + notice.
- **`track.sh is_project_file` now excludes `.knowledge-graph/` and
  `.claude/`.** kg's own runtime writes were being tracked as "active
  module activity", so `.knowledge-graph/` always looked like a module
  lacking CLAUDE.md — perpetually triggering the early-exit above.
- **SKILL.md-based nodes and ghost paths weren't recognized** as
  knowledge nodes. Four mirror implementations (analyze.sh auto-detect,
  analyze.sh analyze blind_spots, context.sh startup, prompt-trigger.sh)
  now all skip `.knowledge-graph/`, `.claude/`, non-existent dirs, and
  accept `SKILL.md` alongside `CLAUDE.md`.
- **`broken_refs` now resolves both relative-to-node and project-root
  paths.** Cross-module references like `@src/foo/CLAUDE.md` (project-
  root form) were being flagged as broken. Also skips template
  placeholders containing `{` (e.g. `@{path}/CLAUDE.md` in docstring
  examples).
- **Test 7 language drift fixed.** Test expected Chinese `初始化`; code
  had been translated to English `not initialized`. Pre-existing.

### Added — Stronger "resume previous work" signal

- **`## 未提交变更 (work in progress)` section in snapshot.** When
  `save_snapshot` runs, it now includes `git status --porcelain` output.
  After `/clear`, Claude sees explicit `M file.js` entries and knows
  which files are still being edited — no longer concludes "everything
  committed, nothing to continue."
- **Anti-overwrite guard in `save_snapshot`.** If WS is empty (e.g. a
  Stop fires right after `/clear` wiped it) and an existing snapshot
  already has `## 活跃模块`, skip the save. Thin snapshots no longer
  stomp rich ones.

### Added — Integration tests for the above

- Tests 8-12 in `tests/test-pipeline.sh` cover track.sh runtime exclusion,
  context.sh non-early-exit, auto-detect ghost-skip, blind_spots
  filesystem filter, and broken_refs dual-resolve. **26/26 passing.**

### Changed — SKILL.md index-tag rules tightened

- LLM was emitting `bin/CLAUDE.md: bin/` (path echo) as knowledge-index
  tags. Step 6 now explicitly forbids path echoes and truncated @include
  lines, requires reading actual Prohibitions/Conventions before tagging,
  and specifies "would someone grep for this distinctively?" as the
  quality bar.

### Changed — README restructured

- README shrunk 358 → 172 lines. Deep architecture moved to
  `docs/architecture-notes.md` (pipeline ASCII, full hook table, infer.sh
  reference, context survival matrix, source + installed layout). v1.2
  release notes moved here. Tagline anchored to a single value prop.
  "vs Alternatives" table moved to second screen for faster decision.

## [1.2.1] - 2026-04-11

### Fixed — Live Monitoring Session (8 bugs found and fixed)

- **Cross-project path pollution**: files edited outside `$CLAUDE_PROJECT_DIR` (e.g. editing project-B while in project-A) leaked absolute paths into events, breaking all inference. Added `is_project_file()` guard.
- **InstructionsLoaded absolute paths**: global `~/.claude/CLAUDE.md` and plugin paths recorded as events. Added `startswith($prefix)` filter.
- **Write cleared prediction cache**: every Edit triggered `tlb_invalidate`, wiping the cache that was just populated by a preceding Read. Removed — editing current dir doesn't change its relationship to other dirs.
- **Write blocked Read prediction**: `ws_is_paged_in` checked both read and write records. A Write to a dir caused subsequent first-Read to skip prediction. Now only checks `r` records.
- **Cold start empty predictions**: `infer.sh predict` returned `[]` when event history was sparse. Added git log co-change fallback.
- **`decision:block` in PostToolUse**: block was placed in PostToolUse (after tool executed), making it ineffective. Moved to PreToolUse where it actually prevents the Write.
- **install.sh missing PreToolUse/PreCompact**: the jq merge filter in all 3 install paths omitted PreToolUse and PreCompact hook types. New hooks were defined but never installed.
- **InstructionsLoaded noise**: root and `.claude/` CLAUDE.md loads recorded on every session start/compact, filling 21% of events with data that inference never uses. Now only records module-level CLAUDE.md.

### Added — Auto-Trigger System

- **PreToolUse Write|Edit block**: when writing to a module directory without CLAUDE.md, the Write is blocked and Claude is prompted to create the knowledge node before proceeding.
- **Context-aware trigger**: simple modules (< 5 writes, 0 failures) get a format template for direct creation (~2s). Complex modules (≥ 5 writes or failures) are directed to use the Skill tool for deeper analysis (~30s).
- **Skill auto-detect preprocessor**: SKILL.md `!` preprocessor runs `analyze.sh auto-detect` to determine if init or update is needed, outputting `[AUTO] Execute init/update mode` directives.

### Improved — Performance

- **Working set deduplication**: `ws_touch` now maintains `ws-reads.set` and `ws-writes.set` alongside the full log. `ws_is_paged_in` checks the small set file (grep on ~20 lines) instead of scanning the full log (200+ lines).
- **`ws_dirty` optimized**: reads `ws-writes.set` directly instead of `awk|sort -u` on full log.
- **InstructionsLoaded filtered**: ~21% reduction in event file noise.

## [1.2.0] - 2026-04-10

### Added — Zero-Interrupt Architecture

Complete redesign of when and how the system interacts with your coding session:

- **Removed all mid-coding interrupts.** The old system blocked Claude every 15 writes to force a knowledge update. This is gone. You code uninterrupted; the system works at session boundaries.
- **Work Snapshot system.** On session end (Stop hook) and before compaction (PreCompact), the system saves a structured snapshot of your working state — which modules you touched, what you modified, errors you hit, commits you made. This snapshot is injected on next `SessionStart` or after `compact`, so Claude knows what you were doing even after `clear`.
- **Working Set tracking.** Every module directory you read or write is recorded in a session-scoped working set (`working-set.dat`). This is the authoritative record of "what's paged in" — used for prediction deduplication, compact recovery, and subagent context.
- **Prediction Cache (TLB).** Predicted module relations are cached per-directory with a 300-second TTL. Same-directory reads no longer re-run the prediction engine — first access triggers prediction, subsequent accesses cost ~5ms.

### Added — Pipeline Resilience

- **Event file rotation.** `graph-events.jsonl` is automatically truncated to 300 lines on session end (when exceeding 500 lines). Older events are archived to `graph-events-archive.jsonl`. The system no longer degrades as events accumulate.
- **Corrupt line tolerance.** All inference commands now filter malformed JSON lines before processing. A single corrupted event line no longer crashes the entire inference pipeline.
- **Bounded prediction input.** `infer.sh predict` reads only the most recent 300 events (`tail -300`), regardless of file size. Prediction latency is bounded.
- **N+1 query elimination.** `infer.sh decay` was rewritten from N separate full-file scans (one per module) to a single pre-computation pass + per-module lookup. 20 modules went from 20 full parses to 1.

### Added — MCP Server

- New `mcp-server.sh`: a bash-native MCP stdio server exposing 4 tools: `kg_status`, `kg_query`, `kg_predict`, `kg_cochange`. Registered automatically during install.

### Added — Plugin Packaging

- New `plugin.json`: standard Claude Code plugin manifest with hooks, skills, and MCP server definitions.

### Added — Multilingual Support

- `get_prohibitions()` now matches `## 禁忌`, `## Prohibitions`, `## Rules`, and `## Constraints` headings. English-language projects work out of the box.

### Added — Testing

- `tests/test-pipeline.sh`: 15 automated tests covering prediction performance, corrupt line resilience, event rotation, multilingual heading extraction, and initialization marker detection.
- Initialization detection changed from `find` scan (O(n) on large repos) to `.initialized` marker file (O(1)).

### Changed — Trigger Timing

- **`track.sh write`**: no longer outputs `"decision":"block"`. Events are silently accumulated; updates happen at session boundaries.
- **`prompt-trigger.sh`**: no longer scans every user message for completion/failure signals. Only responds when user explicitly mentions "知识图谱" or "knowledge-graph".
- **`context.sh startup`**: update suggestion only appears when knowledge index is >1 hour stale AND ≥15 events pending. Previously suggested at ≥10 events regardless of staleness.
- **`context.sh compact`**: now uses working set to inject only the active modules' prohibitions, instead of scanning event tails to guess which modules matter.

### Changed — Context Injection

- **SessionStart** now injects the previous session's work snapshot (modules, modifications, errors, commits) — the key to making `clear` non-destructive.
- **PreCompact** now saves a work snapshot before compaction and tells the compactor which specific modules to preserve (by name, not generic guidance).
- **PostCompact** rebuilds context from the saved snapshot + working set prohibitions, instead of generic event summaries.
- **SubagentStart** now includes the main session's active modules, so subagents know what the parent is working on.

### Fixed

- `guard.sh`: `mkdir -p` replaced with `[ -d ] || mkdir -p` to avoid unnecessary fork on every hook invocation.
- `tlb_invalidate`: added empty-file guard (`[ ! -s ]`) to skip awk+mv when prediction cache is empty.
- `mcp-server.sh`: all JSON construction uses `jq --arg` for proper escaping; removed unsafe `sed`/`tr` string interpolation.
- `install.sh`: MCP server registration added to `.mcp.json` during install.

## [1.1.1] - 2026-04-10

### Changed
- **Runtime data moved from `.claude/skills/knowledge-graph/data/` to `.knowledge-graph/`** at project root. Files under `.claude/` require user authorization on every modification — hooks writing event logs caused constant permission prompts. The new location is outside `.claude/` and operates silently.
- Install script auto-migrates existing data from old location to `.knowledge-graph/`.
- `@include` path in `.claude/CLAUDE.md` updated to `@.knowledge-graph/knowledge-index.md`.
- `.gitignore` updated to ignore `.knowledge-graph/` instead of old data path.

## [1.1.0] - 2026-04-09

### Added — Inference Engine (pure bash + jq, zero LLM cost)
- `infer.sh cochange`: discovers files modified together within 10-min windows as implicit dependencies.
- `infer.sh sequences`: mines repeated read→write patterns to discover "always check X before changing Y" relationships.
- `infer.sh decay`: monitors CLAUDE.md rule effectiveness — classifies as effective, ineffective, or stale.
- `infer.sh predict`: given a file being read, predicts which related modules will be needed next.
- P6 sequence pattern integration: auto-discovered read→write patterns written to `## When Changing` sections.
- P7 co-change dependency discovery: frequently co-changed directories get mutual cross-references.
- P8 knowledge decay detection: stale rules marked, ineffective prohibitions rewritten, effective rules preserved.

### Added — Predictive Context Loading
- `PreToolUse(Read)` hook: records read events and injects related module prohibitions via `additionalContext` BEFORE Claude visits those modules. Claude knows the pitfalls of related modules while still reading the current file.

### Added — Context Survival (verified against Claude Code source)
- `@include` directive in `.claude/CLAUDE.md`: knowledge index now lives in the system prompt, survives `clear` and `compact` natively without hook re-injection.
- `PreCompact` hook: guides compactor to preserve prohibitions, active tasks, and error patterns.
- `PostCompact` hook: re-injects dynamic state (pending event count) after compaction.
- Install script auto-creates `.claude/CLAUDE.md` with `@include` reference to knowledge index.

### Added — Token Efficiency
- CLAUDE.md capped at ≤20 lines (down from 30) with compression writing rules.
- Knowledge index uses single-line format (~40% fewer tokens than table format).
- `when_to_use` frontmatter field (separate from `description`) for precise auto-invocation.

### Added — Documentation
- `docs/architecture-notes.md`: Claude Code source analysis findings with verified mechanisms.
- Complete README rewrite with inference engine documentation, context survival table, and updated architecture diagram.

### Fixed
- `prompt-trigger.sh`: changed from broken prompt modification to correct `hookSpecificOutput.additionalContext` API (verified from Claude Code source — `UserPromptSubmit` does NOT support prompt rewriting).
- `prompt-trigger.sh`: filters `<task-notification>`, `<system-reminder>`, and other system messages.
- Update instructions changed to "finish current tasks first" to prevent interrupting in-progress work.
- Data files unified under `.claude/skills/knowledge-graph/data/` — no more scattered JSON/JSONL in `.claude/` root.
- Install script cleans up legacy files (`graph-changelog.jsonl`, `graph-events-archive.jsonl`, `knowledge-graph.md`).

### Changed
- `SessionStart` hook no longer injects knowledge index (handled by `@include` now).
- `PostCompact` hook simplified to only inject pending event count.
- Install script now patches missing hooks incrementally instead of skipping entirely.

## [1.0.0] - 2026-04-08

### Added
- Initial public release of Knowledge Graph as a zero-dependency, git-native memory layer for Claude Code.
- Bash-based install flow under `standalone/install.sh`.
- Core tracking, context injection, prompt trigger, and analysis scripts under `standalone/skills/knowledge-graph/scripts/`.
- Skill packaging via `standalone/skills/knowledge-graph/SKILL.md`.
- Migration support for older `.claude/scripts/`-based installs.
- Automatic hook wiring for write, failure, instructions, session start, subagent start, stop, and prompt submit events.
- Privacy-first local storage with `.claude/skills/knowledge-graph/data/graph-events.jsonl`.
