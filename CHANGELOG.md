# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning where practical.

## [Unreleased]

### Added
- `UserPromptSubmit` hook (`prompt-trigger.sh`): detects completion signals ("搞定了", "ok了", "可以了") and failure signals ("还不行", "不对", "又错了") in user messages, auto-triggers knowledge graph update.
- `knowledge-index.md`: Karpathy LLM Wiki-style global index generated after every init/update, injected at session start for O(1) knowledge node lookup.
- `query` mode: search the knowledge graph and get sourced answers (`/knowledge-graph query <question>`).
- P5 externalization prompting (Polanyi tacit knowledge): when a file is edited 3+ times, proactively asks the user for lessons learned and records them as prohibitions.

### Fixed
- `prompt-trigger.sh` no longer triggers on `<task-notification>`, `<system-reminder>`, or other system messages.
- Update instructions changed from "execute immediately" to "finish current tasks first", preventing interruption of in-progress work.

## [1.0.0] - 2026-04-08

### Added
- Initial public release of Knowledge Graph as a zero-dependency, git-native memory layer for Claude Code.
- Bash-based install flow under `standalone/install.sh`.
- Core tracking, context injection, prompt trigger, and analysis scripts under `standalone/skills/knowledge-graph/scripts/`.
- Skill packaging via `standalone/skills/knowledge-graph/SKILL.md`.
- Migration support for older `.claude/scripts/`-based installs.
- Automatic hook wiring for write, failure, instructions, session start, subagent start, stop, and prompt submit events.
- Privacy-first local storage with `.claude/skills/knowledge-graph/data/graph-events.jsonl`.
