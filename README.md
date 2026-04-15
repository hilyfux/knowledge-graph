# Knowledge Graph for Claude Code

**Persistent, git-native memory that makes your AI coding agent actually remember. Zero databases, zero services — just bash, `jq`, and your own commits.**

[![GitHub stars](https://img.shields.io/github/stars/hilyfux/knowledge-graph?style=social)](https://github.com/hilyfux/knowledge-graph)
[![CI](https://img.shields.io/github/actions/workflow/status/hilyfux/knowledge-graph/test.yml?branch=main&label=tests)](https://github.com/hilyfux/knowledge-graph/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/hilyfux/knowledge-graph)](https://github.com/hilyfux/knowledge-graph/commits/main)

Claude Code and other AI coding agents forget everything between sessions — you end up re-explaining the same project context every time. Knowledge Graph fixes that by turning your file operations and git history into a lightweight, evidence-based memory layer that lives inside your repo.

**First-class support for:**

- **Claude Code** — auto-tracks reads and writes via hooks, injects a work snapshot on every session start, rebuilds context after `/clear` and `/compact`
- **Codex / Cursor / Windsurf / any MCP client** — 7 tools and 20+ resources exposed by the bundled MCP stdio server (`kg_read_node`, `kg_query`, `kg_recent_work`, `kg_blind_spots`, …)

No embeddings. No vector stores. No external services. Works on macOS, Linux, and Windows.

---

## Who this is for

- **Vibecoders** — you describe intent, the agent writes code. Knowledge Graph gives the agent the project context you never had to learn, so one-line requests turn into working changes instead of destructive rewrites. *From the maintainer (a vibecoder himself): goal completion and "actually what I wanted" rate jumped at least 10× after installing it — "10× is the floor."*
- **Senior developers** — you want structured, auditable context that your AI agent respects. Every rule traces back to a commit hash or a recorded error event. No hallucinated conventions.
- **Teams** — rules live in `CLAUDE.md` right next to the code they govern. Share via `git push`.

---

## Quick Start

### macOS / Linux / WSL

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hilyfux/knowledge-graph/main/standalone/install.sh) /path/to/your-project
```

### Windows (PowerShell + Git Bash)

```powershell
git clone https://github.com/hilyfux/knowledge-graph.git
cd knowledge-graph
.\standalone\install.ps1 C:\path\to\your-project
```

Then:

1. Restart Claude Code (so hooks activate) — or your MCP-aware agent
2. Run `/knowledge-graph init`

From that point on: silent tracking, distributed `CLAUDE.md` knowledge nodes per module, and cross-session memory readable by any MCP-aware agent.

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
| **Multi-agent (Codex / MCP)** | ✅ 7 tools + resources | Partial | Partial | ❌ |
| **Windows (PowerShell installer)** | ✅ | ❌ | ❌ | ❌ |

---

## What You Get

- **Cross-agent memory** — works natively in Claude Code (hooks); works in Codex / Cursor / Windsurf / any MCP client through the bundled server (7 tools + 22 resources auto-exposed)
- **Session-to-session continuity** — snapshot survives `clear` and `compact`; includes `git status` uncommitted changes so the agent knows what's still in progress, not just what was committed
- **Auto-discovered dependencies** from real co-change patterns — observe work, infer patterns, promote only evidence-backed rules
- **Zero-interrupt workflow** — heavy analysis runs at session boundaries, not during coding
- **Zero dependencies beyond `jq`** — no Docker, no Neo4j, no Python, no services, no daemon. Inspectable. Versionable. No lock-in.

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
- **SessionStart / PostCompact** → injects the last work snapshot so the agent picks up where it left off
- **Stop** → saves the snapshot, rotates the event log, runs background analysis

**Pure bash + jq** mines patterns from the event log and git history; the LLM is only involved when a `CLAUDE.md` actually needs to be (re)written. Everything else is zero-token.

Deep dive with full hook table, pipeline diagram, and context-survival matrix: [docs/architecture-notes.md](docs/architecture-notes.md).

For non-Claude agents: the same data (CLAUDE.md nodes, work snapshot, co-change pairs) is accessible via the MCP server.

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

**7 tools** and a **resources channel** exposed via MCP, usable from any MCP-aware agent (Codex, Cursor, Windsurf, Claude Desktop, custom clients):

| Tool | Description |
|------|-------------|
| `kg_status` | Coverage, pending events, blind-spot count, hot zones, recent failures |
| `kg_query` | Full-text search across every `CLAUDE.md` / `SKILL.md` body — returns `path:line:excerpt` |
| `kg_read_node` | Fetch the full knowledge node for a specific module |
| `kg_recent_work` | Current work snapshot — active modules, uncommitted changes, recent commits |
| `kg_predict` | Predict related modules for a file path (co-change history) |
| `kg_cochange` | Top co-change directory pairs — implicit dependencies |
| `kg_blind_spots` | Modules with activity but no knowledge node |

Plus **Resources**: every `CLAUDE.md` / `SKILL.md` is exposed at `kg://node/<path>` (or `kg://skill/<path>`); the knowledge index at `kg://index`; the work snapshot at `kg://snapshot`. Agents that speak the `resources/list` + `resources/read` protocol can discover and read knowledge files without knowing filesystem paths.

Auto-registered in `.mcp.json` during installation.

---

## Design Principles

1. **Zero interrupts.** Never blocks your coding. Analysis runs at session boundaries.
2. **Bash computes, LLM decides.** Pattern mining is pure bash (~3ms/event); LLM only writes prose.
3. **Evidence-based only.** Every rule traces back to a commit, error, or analysis. No evidence, no rule.
4. **Predict, don't react.** Pre-load related knowledge before errors, based on co-change history.
5. **Survive everything.** `clear`, `compact`, long sessions — working state persists through snapshots.
6. **Minimal token footprint.** ≤20 line `CLAUDE.md`, pointer-style index, lazy loading.
7. **Agent-agnostic outputs.** Hooks are Claude Code-specific; outputs (CLAUDE.md nodes, MCP tools, resources) are consumable by any agent.

---

## Requirements

- **`bash`** — macOS / Linux: native. Windows: [Git Bash](https://gitforwindows.org/) (`winget install Git.Git`) or WSL.
- **`jq`** — `brew install jq` / `apt install jq` / `winget install jqlang.jq`
- **`git`** (optional, recommended) — enhances dependency analysis and evidence tracing
- An MCP-aware AI agent: **Claude Code** natively, or **Codex / Cursor / Windsurf / Claude Desktop** via the bundled MCP server

---

## Learn More

- [Installation](docs/installation.md) — platform-specific setup (macOS / Linux / Windows / WSL)
- [Configuration](docs/configuration.md) — env vars and tuning
- [Architecture](docs/architecture-notes.md) — hook flow, prediction engine, pipeline diagram, installed layout
- [FAQ](docs/faq.md) — common questions
- [Changelog](CHANGELOG.md) — release history

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

High-impact areas:
- New pattern types in `infer.sh`
- Large-monorepo performance (1000+ modules)
- Prediction accuracy measurement and feedback loops
- Integration tests for non-Claude MCP clients
- Additional agent integrations beyond MCP

---

## License

[MIT](LICENSE)
