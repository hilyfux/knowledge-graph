# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning where practical.

## [Unreleased]

### Added
- Placeholder for upcoming improvements, fixes, and documentation updates.

## [1.0.0] - 2026-04-08

### Added
- Initial public release of Knowledge Graph as a zero-dependency, git-native memory layer for Claude Code.
- Bash-based install flow under `standalone/install.sh`.
- Core tracking, context injection, prompt trigger, and analysis scripts under `standalone/skills/knowledge-graph/scripts/`.
- Skill packaging via `standalone/skills/knowledge-graph/SKILL.md`.
- Migration support for older `.claude/scripts/`-based installs.
- Automatic hook wiring for write, failure, instructions, session start, subagent start, stop, and prompt submit events.
- Privacy-first local storage with `.claude/skills/knowledge-graph/data/graph-events.jsonl`.
