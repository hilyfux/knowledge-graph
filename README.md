# :brain: Knowledge Graph for Claude Code

**Persistent memory that makes Claude Code smarter with every session.**

[![GitHub stars](https://img.shields.io/github/stars/hilyfux/knowledge-graph?style=social)](https://github.com/hilyfux/knowledge-graph)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/hilyfux/knowledge-graph)](https://github.com/hilyfux/knowledge-graph/commits/main)

Claude Code forgets everything between sessions. Knowledge Graph fixes that. It silently tracks every file operation via hooks, builds distributed `CLAUDE.md` knowledge nodes across your project, and injects the right context when Claude needs it -- automatically.

**Zero dependencies beyond `jq`. No databases. No vector stores. No external services. Just bash scripts and git.**

---

## What's New in v1.1.0

### Inference Engine (pure bash + jq, zero LLM cost)

Three capabilities that no other Claude Code memory tool offers:

**1. Predictive Context Loading** — When Claude reads a file, the system checks co-change history and *pre-loads* related modules' prohibitions before Claude even visits them. Claude knows the pitfalls of `src/middleware/` while still reading `src/auth/`.

**2. Sequence Pattern Mining** — Discovers implicit dependencies from event streams: "every time someone writes to `src/api/`, they first read `src/auth/` and `src/types/`" → automatically adds cross-references to CLAUDE.md.

**3. Knowledge Decay Detection** — Monitors whether prohibitions in CLAUDE.md are actually working:
- **effective** (prohibition + zero failures) → keep
- **ineffective** (prohibition + continued failures) → rewrite more specifically
- **stale** (30+ days no activity) → mark for review

### Context Survival (verified against Claude Code source)

Built on deep study of [Claude Code internals](docs/architecture-notes.md):

- **`@include` directive** — Knowledge index lives in the system prompt via `.claude/CLAUDE.md` → survives `clear` and `compact` natively
- **PreCompact hook** — Guides the compactor to preserve prohibitions and error patterns
- **PostCompact hook** — Re-injects dynamic state (pending events count)
- **Nested traversal** — Subdirectory CLAUDE.md files auto-load when Claude accesses files in that directory (O(1) lookup, zero upfront cost)

### Token Efficiency

- CLAUDE.md capped at ≤20 lines with compression rules (no articles, symbols over words, commit hash only)
- Knowledge index in single-line format (~40% fewer tokens than table format)
- Hook output uses `additionalContext` (correct API, verified from source)

---

## Background & Methodology

This project was built on four pillars:

1. **Anthropic Internal Engineering Practices** — Workflow patterns that informed the evidence-based rule system and modular CLAUDE.md architecture.

2. **Karpathy's LLM Wiki + AutoResearch** — Three-layer architecture (Raw Sources → Wiki → Schema) and autonomous knowledge building: observe → collect evidence → synthesize.

3. **Michael Polanyi's Tacit Knowledge Theory** — "We know more than we can tell." The externalization prompt (P5) asks developers to articulate experience that code alone can't capture.

4. **Claude Code Source Code Analysis** — Every hook, every loading mechanism, every compaction behavior verified against the actual implementation. Not guesses — [architecture notes with line references](docs/architecture-notes.md).

> *"The best memory system is one that's invisible, auditable, and shareable."*

---

## Why This Exists

Claude Code is powerful, but stateless. Every new session starts from zero. Knowledge Graph gives Claude a persistent, evidence-based memory layer that grows with your project.

### vs Competitors

| | **Knowledge Graph** | [mcp-knowledge-graph](https://github.com/shaneholloman/mcp-knowledge-graph) | [Memento](https://github.com/skydeckai/mcp-server-memento) | [Caveman](https://github.com/JuliusBrussee/caveman) |
|---|---|---|---|---|
| **Purpose** | Persistent memory + inference | Graph storage | Vector memory | Token compression |
| **Storage** | Plain files in your repo | Neo4j database | Vector database | N/A (stateless) |
| **Dependencies** | `jq` only | Neo4j + Node.js + Docker | Python + ChromaDB | Python (optional) |
| **Learns over time** | Yes (inference engine) | No | No | No |
| **Predicts context** | Yes (co-change analysis) | No | No | No |
| **Survives compact** | Yes (verified from source) | N/A | N/A | N/A |
| **LLM cost** | Near zero (bash does analysis) | Every query | Embedding costs | Zero |
| **Team sharing** | `git push` | Manual DB export | Manual DB export | N/A |

---

## Quick Start

```bash
# 1. Install
bash <(curl -fsSL https://raw.githubusercontent.com/hilyfux/knowledge-graph/v1.1.0/standalone/install.sh) /path/to/your-project

# 2. Restart Claude Code to activate hooks

# 3. Initialize the knowledge graph
/knowledge-graph init
```

That's it. From now on, Claude Code will:
- Track every file read, write, and edit automatically
- Predict related modules and pre-load their prohibitions
- Build knowledge nodes (`CLAUDE.md`) in each module
- Auto-discover implicit dependencies from co-change patterns
- Detect and fix stale or ineffective knowledge rules
- Survive `clear` and `compact` without losing context

---

## How It Works

```
  You code normally with Claude Code
              |
              v
  +-----------------------+
  | Hooks fire silently   |  PreToolUse(Read), PostToolUse(Write/Edit),
  | on every operation    |  PostToolUseFailure, UserPromptSubmit,
  |                       |  SessionStart, PreCompact, PostCompact, Stop
  +-----------+-----------+
              |
    +---------+---------+
    |                   |
    v                   v
  +-------------+  +------------------+
  | track.sh    |  | infer.sh predict |  PreToolUse: predicts related
  | records     |  | co-change lookup |  modules from history, injects
  | events      |  +--------+---------+  prohibitions BEFORE errors happen
  +------+------+           |
         |                  v
         |           additionalContext
         |           → Claude sees related
         |             module pitfalls
         |
         |  Every 15 writes (auto)
         |  or /knowledge-graph update (manual)
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
| `PreToolUse` (Read) | `track.sh` | Records reads + **predicts related modules and injects their prohibitions** |
| `PostToolUse` (Write/Edit) | `track.sh` | Records file changes; auto-triggers update every 15 writes |
| `PostToolUseFailure` | `track.sh` | Records failures + error messages as learning opportunities |
| `InstructionsLoaded` | `track.sh` | Records which `CLAUDE.md` files Claude loaded |
| `UserPromptSubmit` | `prompt-trigger.sh` | Detects completion/failure signals, auto-triggers update |
| `SessionStart` | `context.sh` | Injects active zones + pending event count |
| `PreCompact` | `context.sh` | Guides compactor to preserve prohibitions and error patterns |
| `PostCompact` | `context.sh` | Re-injects dynamic state after compaction |
| `SubagentStart` | `context.sh` | Injects prohibitions into sub-agents |
| `Stop` | `analyze.sh` | Runs background pre-analysis when 20+ events accumulated |

### The Inference Engine (`infer.sh`)

Pure bash + jq. Zero LLM tokens. Runs during `update`.

| Command | What it discovers |
|---------|-------------------|
| `infer.sh cochange` | Files modified together within 10-min windows → implicit dependencies |
| `infer.sh sequences` | Repeated read→write patterns → "always check X before changing Y" |
| `infer.sh decay` | Rule effectiveness: effective / ineffective / stale |
| `infer.sh predict` | Given a file, predicts which modules will be needed next |

---

## Commands

| Command | Purpose |
|---------|---------|
| `/knowledge-graph init` | Full project scan. Generates `CLAUDE.md` for every module. |
| `/knowledge-graph update` | Incremental refresh + inference engine. Auto-triggered every 15 writes. |
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

## Context Survival

| Content | `clear` | `compact` | Mechanism |
|---------|---------|-----------|-----------|
| Knowledge index | Survives | Survives | `@include` in system prompt |
| Module CLAUDE.md | Re-loaded on access | Cache cleared, re-loaded | Native nested traversal |
| Active zones | Re-injected | Re-injected | SessionStart + PostCompact hooks |
| Prohibitions | Always available | Guided preservation | PreCompact hook |
| Event data | On disk | On disk | Never enters context window |

---

## Design Principles

1. **Bash computes, LLM decides.** Data collection, pattern mining, and inference are pure bash (~3ms per event). The LLM only steps in when judgment is needed.

2. **Evidence-based only.** Every rule must trace back to a commit, error, or code analysis. No evidence, no rule.

3. **Predict, don't react.** Pre-load related knowledge before errors happen, based on historical co-change patterns.

4. **Survive everything.** `clear`, `compact`, long sessions — knowledge persists through `@include` directives and native Claude Code mechanisms.

5. **Minimal token footprint.** ≤20 line CLAUDE.md, single-line index, lazy loading. Maximum information per token.

6. **Self-healing.** Stale rules get marked, ineffective prohibitions get rewritten, missing cross-references get discovered automatically.

---

## Project Structure

```
knowledge-graph/
├── standalone/
│   ├── install.sh
│   └── skills/
│       └── knowledge-graph/
│           ├── SKILL.md
│           └── scripts/
│               ├── track.sh          <- Event recording + predictive injection
│               ├── infer.sh          <- Inference engine (co-change, sequences, decay)
│               ├── context.sh        <- Context injection (startup, compact, subagent)
│               ├── analyze.sh        <- Pre-analysis engine
│               ├── prompt-trigger.sh <- User prompt signal detection
│               └── guard.sh          <- Shared utilities
├── docs/
│   ├── architecture-notes.md         <- Source code research findings
│   ├── configuration.md
│   ├── installation.md
│   └── faq.md
└── examples/
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
- Cross-project knowledge transfer
- Integration testing

---

## License

[MIT](LICENSE)
