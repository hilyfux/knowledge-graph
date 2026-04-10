# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

Knowledge Graph is a persistent memory layer for Claude Code. It tracks file operations via hooks, mines co-change patterns with a pure bash+jq inference engine, and generates distributed `CLAUDE.md` knowledge nodes across target projects — all with zero external dependencies beyond `jq` and git.

## Validation Commands

```bash
# Syntax check all scripts (required before any PR)
bash -n standalone/install.sh
bash -n standalone/skills/knowledge-graph/scripts/*.sh

# Optional deeper linting
shellcheck standalone/install.sh standalone/skills/knowledge-graph/scripts/*.sh
```

There is no test framework — validation is syntax checking and shellcheck.

## Architecture

**Pure bash project** — no package.json, no build step, no transpilation.

### Entry Points

- `standalone/install.sh` — Installer: copies skill, merges hooks into target project's `.claude/settings.json`, migrates old data
- `standalone/skills/knowledge-graph/SKILL.md` — Skill interface defining 4 modes: `init`, `update`, `status`, `query`

### Runtime Scripts (standalone/skills/knowledge-graph/scripts/)

| Script | Purpose |
|--------|---------|
| `track.sh` | Event recording + predictive module injection (called by hooks) |
| `infer.sh` | Inference engine: cochange, sequences, decay, predict (pure jq) |
| `analyze.sh` | Project scanning + pre-analysis |
| `context.sh` | Context injection at startup/compact/subagent events |
| `prompt-trigger.sh` | Detect completion/failure signals for auto-update |
| `guard.sh` | Environment guard + shared helpers |

### Hook Wiring

Hooks are configured in `.claude/settings.json` and fire automatically:

- `PreToolUse(Read)` → `track.sh read` — records reads, predicts related modules
- `PostToolUse(Write/Edit)` → `track.sh write` — records changes, auto-triggers update every 15 writes
- `PostToolUseFailure` → `track.sh failure` — records errors for learning
- `SessionStart` → `context.sh` — injects active zones + pending events

### Data Flow

1. Hooks append JSON lines to `.knowledge-graph/graph-events.jsonl`
2. `analyze.sh` scans project structure (pure bash)
3. `infer.sh` mines patterns from events (jq streams, zero LLM cost)
4. LLM is only invoked for final `CLAUDE.md` synthesis in the skill's update mode

### Installed Layout in Target Projects

```
target-project/
├── .claude/skills/knowledge-graph/   ← Skill + scripts (copied by installer)
├── .knowledge-graph/                 ← Runtime data (events, cache, index)
└── src/module/CLAUDE.md              ← Generated knowledge nodes (committed to git)
```

## Key Design Constraints

- **Zero dependencies** — only `jq` and git required; no databases, no cloud services
- **Hook timeouts** — scripts must complete within 2-5 seconds (enforced by Claude Code)
- **Knowledge nodes ≤ 20 lines** — maximum information density per module CLAUDE.md
- **Git-native** — knowledge files are committed like documentation
- **Data directory** — `.knowledge-graph/` (moved from `.claude/` in v1.1.1 to avoid auth prompts)

## Commit Conventions

Uses conventional commits: `feat:`, `fix:`, `docs:`, `refactor:`, `perf:`, `release:`
