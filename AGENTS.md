# Project Instructions

This repository builds Knowledge Graph, a bash + jq memory layer for AI coding agents. Treat `standalone/` as the packaged installer/runtime surface and keep `skills/knowledge-graph/` in sync when changing shared skill or script behavior.

## Knowledge Graph

- Source of truth for runtime behavior: `standalone/skills/knowledge-graph/scripts/`.
- Main validation command: `bash tests/test-pipeline.sh`.
- Installer validation: `bash -n standalone/install.sh standalone/skills/knowledge-graph/scripts/*.sh` and, when available, `shellcheck standalone/install.sh standalone/skills/knowledge-graph/scripts/*.sh`.
- Durable knowledge nodes are canonical `CLAUDE.md` and `SKILL.md` files. `AGENTS.md` is only a Codex adapter and must not duplicate module knowledge.
- Codex/MCP runtime should prefer `KG_PROJECT_DIR` for non-Claude scripts. Claude Code may still set `CLAUDE_PROJECT_DIR`.
- Do not commit `.knowledge-graph/` runtime data.
