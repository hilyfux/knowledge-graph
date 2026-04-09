# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning where practical.

## [Unreleased]

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
