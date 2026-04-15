# Knowledge Graph for Claude Code

**Git-native memory for Claude Code. Zero databases, zero services — just bash, `jq`, and your own commits.**

[![GitHub stars](https://img.shields.io/github/stars/hilyfux/knowledge-graph?style=social)](https://github.com/hilyfux/knowledge-graph)
[![CI](https://img.shields.io/github/actions/workflow/status/hilyfux/knowledge-graph/test.yml?branch=main&label=tests)](https://github.com/hilyfux/knowledge-graph/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/hilyfux/knowledge-graph)](https://github.com/hilyfux/knowledge-graph/commits/main)

Claude Code forgets everything between sessions. Knowledge Graph fixes that by turning your file operations and git history into a lightweight, evidence-based memory layer that lives inside your repo. No embeddings, no vector stores, no external services.

---

## Quick Start

```bash
# 1. Install into your project
bash <(curl -fsSL https://raw.githubusercontent.com/hilyfux/knowledge-graph/main/standalone/install.sh) /path/to/your-project

# 2. Restart Claude Code (so hooks activate)

# 3. Initialize the graph
/knowledge-graph init
```

Three commands. From now on Claude Code silently tracks every read/write, builds distributed `CLAUDE.md` knowledge nodes per module, and injects the right context when needed.

---

## vs Alternatives

| | **Knowledge Graph** | [mcp-knowledge-graph](https://github.com/shaneholloman/mcp-knowledge-graph) | [Memento](https://github.com/skydeckai/mcp-server-memento) | [Caveman](https://github.com/JuliusBrussee/caveman) |
|---|---|---|---|---|
| **Storage** | Plain files in your repo | Neo4j database | Vector database | N/A (stateless) |
| **Dependencies** | `jq` only | Neo4j + Node.js + Docker | Python + ChromaDB | Python (optional) |
| **Learns over time** | ✅ Inference engine | ❌ | ❌ | ❌ |
| **Predicts context** | ✅ Co-change analysis | ❌ | ❌ | ❌ |
| **Survives `clear` / `compact`** | ✅ Snapshot + `@include` | N/A | N/A | N/A |
| **LLM cost** | Near zero (bash computes) | Every query | Embedding costs | Zero |
| **Team sharing** | `git push` | Manual DB export | Manual DB export | N/A |

---

## What You Get

- **Session-to-session memory** without a hosted service or vector DB
- **Auto-discovered dependencies** from real co-change patterns — observe work, infer, promote only evidence-backed rules
- **Zero-interrupt workflow** — heavy analysis runs at session boundaries, not during coding
- **Survives `clear` and `compact`** — working state restored from snapshot on next session
- **Everything local + git-committed** — inspectable, versionable, no lock-in

---

## Token Budget

| Component | Tokens | When loaded |
|-----------|--------|-------------|
| Knowledge index (pointer tags) | ~300-500 | Always (`@include`) |
| Work snapshot | ~200-400 | SessionStart / PostCompact |
| Predicted prohibitions | ~100/module | First access to new module |
| Module CLAUDE.md | ~200/module | On file access (lazy) |
| **Total baseline** | **~500-900** | **<0.5% of 200K context** |

---

## How It Works (briefly)

Hooks fire silently during your normal Claude Code workflow:

- **Read / Write** → events recorded in ~3ms; first access to a module triggers a co-change prediction that pre-loads related module prohibitions
- **SessionStart / PostCompact** → injects the last work snapshot so Claude picks up where it left off
- **Stop** → saves the snapshot, rotates the event log, runs background analysis
- **Pure bash + jq** mines patterns from the event log and git history; LLM is only used to write the final `CLAUDE.md` prose

Deep dive with full hook table and pipeline diagram: [docs/architecture-notes.md](docs/architecture-notes.md).

---

## Commands

| Command | Purpose |
|---------|---------|
| `/knowledge-graph init` | Full project scan. Generates `CLAUDE.md` for every module. |
| `/knowledge-graph update` | Incremental refresh + inference engine. |
| `/knowledge-graph status` | Coverage, health, blind spots, activity heatmap. |
| `/knowledge-graph query <question>` | Search the graph; get sourced answers. |

---

## What Gets Generated

Each module directory gets a `CLAUDE.md` (≤20 lines, maximum information density):

```markdown
# auth

## Prohibitions
- Raw token in localStorage → XSS (a3f21b)
- Skip refresh in test mock → flaky CI (8c4e01)

## When Changing
- Token flow → @middleware/CLAUDE.md
- User model → @api/users/CLAUDE.md

## Conventions
- Auth errors: 401 + {code, message}
- Refresh tokens: httpOnly cookies only
```

`@` references form the dependency graph. The inference engine discovers and adds them from co-change patterns automatically.

---

## MCP Server

Four tools exposed via MCP for programmatic access:

| Tool | Description |
|------|-------------|
| `kg_status` | Health report: event count, node count, last analysis time |
| `kg_query` | Search knowledge index by keyword |
| `kg_predict` | Predict related modules for a file path |
| `kg_cochange` | List top co-change directory pairs |

Auto-registered in `.mcp.json` during installation.

---

## Design Principles

1. **Zero interrupts.** Never blocks your coding. Analysis runs at session boundaries.
2. **Bash computes, LLM decides.** Pattern mining is pure bash (~3ms/event); LLM only writes prose.
3. **Evidence-based only.** Every rule traces back to a commit, error, or analysis. No evidence, no rule.
4. **Predict, don't react.** Pre-load related knowledge before errors, based on co-change history.
5. **Survive everything.** `clear`, `compact`, long sessions — working state persists through snapshots.
6. **Minimal token footprint.** ≤20 line `CLAUDE.md`, pointer-style index, lazy loading.

---

## Requirements

- **`jq`** (required) — `brew install jq` / `apt install jq`
- **`git`** (optional, recommended) — enhances dependency analysis and evidence tracing
- **Claude Code** with hooks support

---

## Learn More

- [Installation](docs/installation.md) — platform-specific setup
- [Configuration](docs/configuration.md) — env vars and tuning
- [Architecture](docs/architecture-notes.md) — deep dive: hook flow, prediction engine, pipeline diagram, installed layout
- [FAQ](docs/faq.md) — common questions
- [Changelog](CHANGELOG.md) — release history

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

High-impact areas:
- New pattern types in `infer.sh`
- Large-monorepo performance (1000+ modules)
- Prediction accuracy measurement and feedback loops
- Integration testing and CI pipeline

---

## License

[MIT](LICENSE)
