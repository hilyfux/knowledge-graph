# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning where practical.

## [Unreleased]

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
