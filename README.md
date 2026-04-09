# :brain: Knowledge Graph for Claude Code

**Persistent memory that makes Claude Code smarter with every session.**

[![GitHub stars](https://img.shields.io/github/stars/hilyfux/knowledge-graph?style=social)](https://github.com/hilyfux/knowledge-graph)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/hilyfux/knowledge-graph)](https://github.com/hilyfux/knowledge-graph/commits/main)

Claude Code forgets everything between sessions. Knowledge Graph fixes that. It silently tracks every file operation via hooks, builds distributed `CLAUDE.md` knowledge nodes across your project, and injects the right context when Claude needs it -- automatically.

**Zero dependencies beyond `jq`. No databases. No vector stores. No external services. Just bash scripts and git.**

---

## Background & Methodology

This project was built on three pillars:

1. **Anthropic Internal Engineering Practices** — Inspired by how Anthropic engineers maintain project context when working with Claude Code in production. Their workflow patterns informed the evidence-based rule system and modular CLAUDE.md architecture.

2. **Karpathy's AutoResearch Methodology** — Applies Andrej Karpathy's autonomous research pattern to knowledge building: let the system observe, collect evidence, and synthesize insights without human prompting. The bash hooks + auto-analysis pipeline is a direct implementation of this philosophy.

3. **Latest LLM Knowledge Graph Research** — Addresses the fundamental limitation of all AI coding assistants: context window amnesia. Rather than using heavyweight solutions (Neo4j, vector databases), this takes a minimalist approach: structured text files committed to git.

> *"The best memory system is one that's invisible, auditable, and shareable."*



## Why This Exists

Claude Code is powerful, but stateless. Every new session starts from zero -- it re-discovers the same pitfalls, re-learns the same conventions, and repeats the same mistakes. Knowledge Graph gives Claude a persistent, evidence-based memory layer that grows with your project.

### vs Competitors

| | **Knowledge Graph** | [mcp-knowledge-graph](https://github.com/shaneholloman/mcp-knowledge-graph) (838+ stars) | [Memento](https://github.com/skydeckai/mcp-server-memento) |
|---|---|---|---|
| **Storage** | Plain files (`CLAUDE.md`) in your repo | Neo4j graph database | Vector database |
| **Dependencies** | `jq` only | Neo4j + Node.js + Docker | Python + ChromaDB |
| **Privacy** | 100% local, everything in `.claude/` | Requires running database | Requires running database |
| **Version control** | Knowledge committed to git, shared with team | External DB, not in repo | External DB, not in repo |
| **Setup time** | 30 seconds, one bash command | Database provisioning required | Database provisioning required |
| **LLM cost** | Near zero -- bash does data collection, LLM only decides what to write | Every query hits LLM | Embedding costs per operation |
| **How it works** | Hooks track activity; bash scripts analyze; LLM writes knowledge | MCP server with CRUD operations | MCP server with semantic search |
| **Team sharing** | `git push` -- knowledge travels with code | Manual DB export/import | Manual DB export/import |
| **Runs without internet** | Yes | Yes (local Neo4j) | Yes (local ChromaDB) |
| **Works with Claude Code hooks** | Native -- built specifically for it | Generic MCP server | Generic MCP server |

**TL;DR:** Other tools bolt a database onto Claude. Knowledge Graph embeds knowledge directly into your repository, where it belongs.

---

## Quick Start

```bash
# 1. Install (copies scripts to your project's .claude/ directory)
bash <(curl -fsSL https://raw.githubusercontent.com/hilyfux/knowledge-graph/main/standalone/install.sh) /path/to/your-project

# 2. Restart Claude Code to activate hooks

# 3. Initialize the knowledge graph
/knowledge-graph init
```

That's it. From now on, Claude Code will:
- Track every file write and edit automatically
- Build knowledge nodes (`CLAUDE.md`) in each module
- Inject relevant context at session start
- Auto-trigger updates every 15 file writes

## Demo

> Demo GIF / terminal walkthrough coming soon. The intended flow is: install, restart Claude Code, run `/knowledge-graph init`, then watch `CLAUDE.md` knowledge nodes accumulate as hooks record real work across sessions.

---

## How It Works

```
  You code normally with Claude Code
              |
              v
  +-----------------------+
  | Hooks fire silently   |  PostToolUse, PostToolUseFailure,
  | on every operation    |  InstructionsLoaded, SessionStart,
  |                       |  SubagentStart, Stop
  +-----------+-----------+
              |
              v
  +-----------------------+
  | track.sh records      |  Pure bash + jq
  | events to JSONL       |  ~3ms per event
  +-----------+-----------+
              |
              |  Every 15 writes (auto)
              |  or /knowledge-graph update (manual)
              v
  +-----------------------+
  | analyze.sh            |  Pure bash: aggregates stats,
  | pre-analyzes data     |  finds blind spots, detects staleness
  +-----------+-----------+
              |
              v
  +-----------------------+
  | LLM reads analysis,   |  Only step that uses LLM tokens
  | writes CLAUDE.md       |  Evidence-based: no proof = no rule
  +-----------+-----------+
              |
              v
  +-----------------------+
  | context.sh injects    |  Next session starts with
  | knowledge at startup  |  full project awareness
  +-----------------------+
```

### The Hook System

| Hook | Script | What it does |
|------|--------|-------------|
| `PostToolUse` (Write/Edit) | `track.sh` | Records file changes; auto-triggers update every 15 writes |
| `PostToolUseFailure` | `track.sh` | Records failures + error messages as learning opportunities |
| `InstructionsLoaded` | `track.sh` | Records which `CLAUDE.md` files Claude loaded |
| `SessionStart` | `context.sh` | Injects knowledge summary + warns if events are piling up |
| `SubagentStart` | `context.sh` | Injects prohibitions into sub-agents |
| `Stop` | `analyze.sh` | Runs background pre-analysis when 20+ events accumulated |

---

## Commands

| Command | Purpose |
|---------|---------|
| `/knowledge-graph init` | Full project scan. Generates `CLAUDE.md` for every module. |
| `/knowledge-graph update` | Incremental refresh from accumulated activity. Also auto-triggered every 15 writes. |
| `/knowledge-graph status` | Coverage, health, blind spots, and activity heatmap. |
| `/knowledge-graph query <question>` | Search the knowledge graph and get sourced answers. |

---

## What Gets Generated

Each module directory gets a `CLAUDE.md` that Claude loads automatically:

```markdown
# auth-middleware

## Prohibitions
- Don't bypass token refresh in tests -> causes flaky CI (source: commit a1b2c3d)

## When Changing
- Modifying token logic -> also check @../session/CLAUDE.md

## Conventions
- All auth errors return 401 with { code, message } shape
```

The `@` references create a dependency graph -- when Claude follows a reference, it loads the linked knowledge too.

---

## Design Principles

1. **Bash computes, LLM decides.** Data collection and aggregation are pure bash (~3ms per event). The LLM only steps in when judgment is needed -- reading analysis and deciding what knowledge to write.

2. **Evidence-based only.** Every rule in `CLAUDE.md` must trace back to a git commit, a recorded error, or direct code analysis. No evidence, no rule. An unverified rule is worse than no rule.

3. **Idempotent.** `init` and `update` are safe to re-run anytime. They append missing content and skip what's already complete -- they never overwrite.

4. **No background processes.** No `claude -p`. No automatic LLM calls. You stay in control.

5. **Git-native.** Knowledge files are committed to your repo and shared with your team via `git push`. Runtime data stays local in `.gitignore`.

---

## Project Structure

```
knowledge-graph/
├── standalone/
│   ├── install.sh              <- Entry point: copies scripts, merges hooks
│   └── skills/
│       └── knowledge-graph/
│           ├── SKILL.md        <- Skill definition (init/update/status/query)
│           └── scripts/
│               ├── track.sh    <- Event recording (PostToolUse hooks)
│               ├── context.sh  <- Context injection (SessionStart hooks)
│               ├── analyze.sh  <- Pre-analysis engine (Stop hook)
│               ├── guard.sh    <- Shared utilities and validation
│               └── prompt-trigger.sh  <- User prompt detection
└── docs/
```

**After installation in your project:**

```
your-project/
├── .claude/
│   ├── settings.json           <- Hooks auto-merged here
│   ├── knowledge-index.md      <- Auto-generated module index
│   ├── rules/                  <- Cross-module rules
│   └── skills/
│       └── knowledge-graph/
│           ├── SKILL.md
│           ├── scripts/
│           └── data/           <- Runtime data (gitignored)
├── src/
│   ├── auth/
│   │   └── CLAUDE.md           <- Module knowledge (committed)
│   ├── api/
│   │   └── CLAUDE.md
│   └── ...
└── CLAUDE.md                   <- Root project knowledge
```

---

## Team Usage

Knowledge files are project knowledge -- commit them. Runtime data is local -- gitignore it.

```bash
# Share knowledge with your team
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# Runtime data stays local (auto-added by installer)
# .claude/skills/knowledge-graph/data/
```

When a teammate pulls your repo, their Claude Code sessions immediately benefit from the accumulated knowledge -- no setup needed beyond the initial install.

---

## Requirements

- **`jq`** (required) -- install via `brew install jq` / `apt install jq`
- **`git`** (optional) -- enhances dependency analysis and evidence tracing
- **Claude Code** with hooks support

---

## Contributing

Contributions are welcome! Here's how:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-improvement`)
3. Make your changes
4. Test by running `install.sh` against a sample project
5. Submit a pull request

**Areas where help is appreciated:**
- Support for additional hook types
- Performance improvements for large monorepos
- Documentation and examples
- Integration testing

---

## License

[MIT](LICENSE) -- use it however you want.
