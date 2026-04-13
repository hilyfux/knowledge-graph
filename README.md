# Knowledge Graph for Claude Code

**Persistent memory for Claude Code, built from real coding history instead of another database.**

[![GitHub stars](https://img.shields.io/github/stars/hilyfux/knowledge-graph?style=social)](https://github.com/hilyfux/knowledge-graph)
[![CI](https://img.shields.io/github/actions/workflow/status/hilyfux/knowledge-graph/test.yml?branch=main&label=tests)](https://github.com/hilyfux/knowledge-graph/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/hilyfux/knowledge-graph)](https://github.com/hilyfux/knowledge-graph/commits/main)

Claude Code forgets everything between sessions. Knowledge Graph fixes that by turning your existing file operations into a lightweight, git-native memory layer. It silently records reads and edits via hooks, builds distributed `CLAUDE.md` knowledge nodes across your project, and injects the right context exactly when Claude needs it.

**Inspired by Anthropic's Claude Code practices and Karpathy-style AutoResearch loops, but implemented as a zero-dependency, git-native layer you can drop into a real repo today.**

**Zero dependencies beyond `jq`. No databases. No vector stores. No external services. Just bash, git, and evidence from your own repo.**

## Why people try it

- **Session-to-session memory** without a hosted service or vector database
- **Git-native knowledge graph** built from real co-change and read/write patterns
- **Zero-interrupt workflow** that stays out of the way while you code
- **Privacy-first local architecture** with everything stored in your project
- **Contributor-friendly architecture** with plain bash hooks, readable runtime files, and no lock-in

---

## What's New in v1.2.0

### Zero-Interrupt Architecture

Previous versions interrupted your coding every 15 writes to force a knowledge update. v1.2 eliminates all mid-coding interrupts. The system now works exclusively at session boundaries:

- **During coding**: only records events and predicts on first module access (~5ms). No blocking, no forced updates, no popups.
- **On session end** (Stop hook): saves a structured work snapshot — which modules you touched, what you modified, errors you hit, commits you made.
- **On next session / clear** (SessionStart): injects the snapshot so Claude immediately knows what you were doing, even after `clear`.
- **On compact** (PreCompact): saves snapshot before compaction, rebuilds context from snapshot + working set afterward.

### Session Recovery That Actually Works

| Scenario | Before v1.2 | After v1.2 |
|----------|-------------|------------|
| After `clear` | Claude only knows project rules. Forgets what you were doing. | Claude knows which modules you touched, what you modified, errors you hit, and recent commits. |
| After `compact` | Loses working state. Generic event summaries re-injected. | Working set prohibitions pinned. Snapshot restored with specific modules and error context. |
| Same-directory re-reads | Prediction engine runs on every read (~200ms each) | First access triggers prediction; subsequent reads: ~5ms (working set hit) |

### Pipeline Resilience

- **Event rotation**: files automatically truncated to 300 lines on session end. No more unbounded growth.
- **Corrupt line tolerance**: a single malformed JSON line no longer crashes the inference engine.
- **Bounded prediction**: `predict` reads only the most recent 300 events, regardless of total file size.
- **N+1 elimination**: `decay` analysis reduced from N full-file scans to 1 pre-computation pass.

### MCP Server + Plugin Packaging

- 4 structured tools via MCP: `kg_status`, `kg_query`, `kg_predict`, `kg_cochange`
- Standard `plugin.json` manifest for Claude Code plugin ecosystem
- Multilingual support: `## Prohibitions` / `## Rules` / `## Constraints` headings work alongside `## 禁忌`

---

## Quick Start

```bash
# 1. Install
bash <(curl -fsSL https://raw.githubusercontent.com/hilyfux/knowledge-graph/main/standalone/install.sh) /path/to/your-project

# 2. Restart Claude Code to activate hooks

# 3. Initialize the knowledge graph
/knowledge-graph init
```

That's it. From now on, Claude Code will:
- Track every file read, write, and edit automatically
- Predict related modules and pre-load their prohibitions on first access
- Save your working state on session end; restore it on next session or after `clear`
- Build knowledge nodes (`CLAUDE.md`) in each module with ≤20 lines of evidence-based rules
- Auto-discover implicit dependencies from co-change patterns
- Detect and fix stale or ineffective knowledge rules
- Survive `clear` and `compact` without losing working context

---

## How It Works

```
  You code normally with Claude Code
              |
              v
  +-----------------------+
  | Hooks fire silently   |  PreToolUse(Read), PostToolUse(Write/Edit),
  | on every operation    |  SessionStart, PreCompact, PostCompact, Stop
  +-----------+-----------+
              |
    +---------+---------+
    |                   |
    v                   v
  +-------------+  +------------------+
  | track.sh    |  | Prediction Cache |  First access → predict related
  | records     |  | (300s TTL)       |  modules from co-change history.
  | events      |  +--------+---------+  Repeat access → cache hit, skip.
  +------+------+           |
         |                  v
         |           additionalContext
         |           → Claude sees related
         |             module pitfalls
         |
         |  Session end (Stop hook):
         |  → save work snapshot
         |  → rotate events (>500 → keep 300)
         |  → background analysis
         |
         |  /knowledge-graph update (manual):
         v
  +-----------------------+
  | analyze.sh            |  Pure bash: stats, blind spots
  | infer.sh              |  Pure bash: co-change, sequences, decay
  | (zero LLM tokens)     |
  +-----------+-----------+
              |
              v
  +-----------------------+
  | LLM reads analysis,   |  Only step using LLM tokens
  | writes CLAUDE.md       |  Evidence-based: no proof = no rule
  +-----------+-----------+
              |
              v
  +-----------------------+
  | knowledge-index.md    |  @include in .claude/CLAUDE.md
  | (system prompt level) |  Survives clear + compact natively
  +-----------------------+
```

### The Hook System

| Hook | Script | What it does |
|------|--------|-------------|
| `PreToolUse` (Read) | `track.sh` | Records reads. On first access to a module: predicts related modules, injects their prohibitions. On repeat access: ~5ms no-op. |
| `PostToolUse` (Write/Edit) | `track.sh` | Records changes. Updates working set. Invalidates prediction cache for changed module. |
| `PostToolUseFailure` | `track.sh` | Records failures + error messages as learning opportunities. |
| `InstructionsLoaded` | `track.sh` | Records which `CLAUDE.md` files Claude loaded. |
| `UserPromptSubmit` | `prompt-trigger.sh` | Only responds when user explicitly mentions knowledge graph. |
| `SessionStart` | `context.sh` | Resets working set. Injects previous work snapshot + update suggestion (if stale). |
| `PreCompact` | `context.sh` | Saves work snapshot. Tells compactor which specific modules to preserve. |
| `PostCompact` | `context.sh` | Restores snapshot + working set prohibitions after compaction. |
| `SubagentStart` | `context.sh` | Injects project prohibitions + main session's active modules into sub-agents. |
| `Stop` | `analyze.sh` | Saves work snapshot. Rotates events. Runs background analysis. |

### The Inference Engine (`infer.sh`)

Pure bash + jq. Zero LLM tokens. Runs during `update`.

| Command | What it discovers |
|---------|-------------------|
| `infer.sh cochange` | Files modified together within 10-min windows — implicit dependencies |
| `infer.sh sequences` | Repeated read→write patterns — "always check X before changing Y" |
| `infer.sh decay` | Rule effectiveness: effective / ineffective / stale |
| `infer.sh predict` | Given a file, predicts which modules will be needed next (bounded to 300 recent events) |

---

## Context Survival

| Content | `clear` | `compact` | Mechanism |
|---------|---------|-----------|-----------|
| Knowledge index | Survives | Survives | `@include` in system prompt |
| Module CLAUDE.md | Re-loaded on access | Re-loaded on access | Native nested traversal |
| **Working state** | **Restored from snapshot** | **Restored from snapshot** | **Stop/PreCompact save + SessionStart inject** |
| **Active module prohibitions** | **Re-loaded on access** | **Pinned by working set** | **Working set tracking** |
| Event data | On disk | On disk | `.knowledge-graph/` — never enters context window |

### Token Budget

| Component | Tokens | When loaded |
|-----------|--------|-------------|
| Knowledge index (pointer tags) | ~300-500 | Always (`@include`) |
| Work snapshot | ~200-400 | SessionStart / PostCompact |
| Predicted prohibitions | ~100/module | First access to new module |
| Module CLAUDE.md | ~200/module | On file access (lazy) |
| **Total baseline** | **~500-900** | **<0.5% of 200K context** |

---

## Commands

| Command | Purpose |
|---------|---------|
| `/knowledge-graph init` | Full project scan. Generates `CLAUDE.md` for every module. |
| `/knowledge-graph update` | Incremental refresh + inference engine. Run when suggested or manually. |
| `/knowledge-graph status` | Coverage, health, blind spots, and activity heatmap. |
| `/knowledge-graph query <question>` | Search the knowledge graph and get sourced answers. |

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

The `@` references create a dependency graph. The inference engine automatically discovers and adds these references from co-change patterns.

---

## MCP Server

Knowledge Graph exposes 4 tools via MCP for programmatic access:

| Tool | Description |
|------|-------------|
| `kg_status` | Health report: event count, node count, last analysis time |
| `kg_query` | Search knowledge index by keyword |
| `kg_predict` | Predict related modules for a file path |
| `kg_cochange` | List top co-change directory pairs |

The MCP server is automatically registered in `.mcp.json` during installation.

---

## Why This Exists

Claude Code is powerful, but stateless. Every new session starts from zero. Knowledge Graph gives Claude a persistent, evidence-based memory layer that grows with your project.

### vs Alternatives

| | **Knowledge Graph** | [mcp-knowledge-graph](https://github.com/shaneholloman/mcp-knowledge-graph) | [Memento](https://github.com/skydeckai/mcp-server-memento) | [Caveman](https://github.com/JuliusBrussee/caveman) |
|---|---|---|---|---|
| **Purpose** | Persistent memory + inference | Graph storage | Vector memory | Token compression |
| **Storage** | Plain files in your repo | Neo4j database | Vector database | N/A (stateless) |
| **Dependencies** | `jq` only | Neo4j + Node.js + Docker | Python + ChromaDB | Python (optional) |
| **Learns over time** | Yes (inference engine) | No | No | No |
| **Predicts context** | Yes (co-change analysis) | No | No | No |
| **Survives clear/compact** | Yes (snapshot + @include) | N/A | N/A | N/A |
| **Zero-interrupt** | Yes (v1.2+) | N/A | N/A | N/A |
| **LLM cost** | Near zero (bash does analysis) | Every query | Embedding costs | Zero |
| **Team sharing** | `git push` | Manual DB export | Manual DB export | N/A |

---

## Design Principles

1. **Zero interrupts.** The system never blocks your coding. Events accumulate silently; analysis runs at session boundaries.

2. **Bash computes, LLM decides.** Data collection, pattern mining, and inference are pure bash (~3ms per event). The LLM only steps in when judgment is needed.

3. **Evidence-based only.** Every rule must trace back to a commit, error, or code analysis. No evidence, no rule.

4. **Predict, don't react.** Pre-load related knowledge before errors happen, based on historical co-change patterns.

5. **Survive everything.** `clear`, `compact`, long sessions — working state persists through snapshots, knowledge through `@include` + lazy loading.

6. **Minimal token footprint.** ≤20 line CLAUDE.md, pointer-style index, lazy loading. Total baseline <0.5% of context window.

---

## Project Structure

```
knowledge-graph/                       <- Source repo
├── standalone/
│   ├── install.sh                     <- Installer + migration + hook merge
│   └── skills/
│       └── knowledge-graph/
│           ├── SKILL.md               <- Skill interface (4 modes)
│           ├── plugin.json            <- Plugin manifest
│           └── scripts/
│               ├── guard.sh           <- Shared infrastructure + working set + cache
│               ├── track.sh           <- Event recording + prediction
│               ├── context.sh         <- Session lifecycle (startup/compact/resume)
│               ├── analyze.sh         <- Project scan + analysis + stop snapshot
│               ├── infer.sh           <- Inference engine (co-change/sequences/decay/predict)
│               ├── mcp-server.sh      <- MCP stdio server (4 tools)
│               └── prompt-trigger.sh  <- Explicit KG mention detection
├── tests/
│   └── test-pipeline.sh              <- 15 automated tests
├── docs/
│   ├── architecture-notes.md
│   ├── configuration.md
│   ├── installation.md
│   └── faq.md
└── examples/
```

**After installation in your project:**

```
your-project/
├── .knowledge-graph/                  <- Runtime data (gitignored)
│   ├── graph-events.jsonl             <- Event log (auto-rotated at 500 lines)
│   ├── graph-events-archive.jsonl     <- Archived events
│   ├── graph-analysis.json            <- Analysis cache
│   ├── knowledge-index.md             <- Global knowledge index
│   ├── work-snapshot.md               <- Last session's working state
│   ├── working-set.dat                <- Current session's active modules
│   ├── pred-cache.dat                 <- Prediction cache (300s TTL)
│   └── .initialized                   <- Init marker
├── .claude/
│   ├── CLAUDE.md                      <- @include → knowledge-index.md
│   ├── settings.json                  <- Hooks auto-merged
│   ├── rules/                         <- Cross-module rules
│   └── skills/knowledge-graph/        <- Scripts only
├── .mcp.json                          <- MCP server registered
├── src/
│   ├── auth/CLAUDE.md                 <- Module knowledge (committed)
│   ├── api/CLAUDE.md
│   └── ...
└── CLAUDE.md                          <- Root project knowledge
```

---

## Requirements

- **`jq`** (required) — `brew install jq` / `apt install jq`
- **`git`** (optional) — enhances dependency analysis and evidence tracing
- **Claude Code** with hooks support

---

## Contributing

Contributions welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

**High-impact areas:**
- Inference engine improvements (new pattern types in `infer.sh`)
- Performance for large monorepos (1000+ modules)
- Prediction accuracy measurement and feedback loops
- Integration testing and CI pipeline

---

## License

[MIT](LICENSE)
