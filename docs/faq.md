# FAQ

## What problem does Knowledge Graph solve?

Claude Code sessions are powerful, but useful context can disappear between sessions when it only lives inside the context window. Knowledge Graph preserves learned patterns in a lightweight, project-native way.

## Is this a database-backed knowledge graph?

No. The project deliberately avoids Neo4j, vector databases, and extra infrastructure. It is a bash-first, git-native memory layer.

## Why not just use a vector memory tool?

Vector memory tools can be useful, but they add dependencies, extra services, or cloud coupling. Knowledge Graph is aimed at developers who want something local, transparent, and easy to version with git.

## How much overhead does it add?

The project target is extremely low overhead, roughly `~3ms/event` for tracked operations.

## Where is data stored?

Locally inside the project under:

```text
.claude/skills/knowledge-graph/data/
```

This keeps the workflow privacy-first and easy to inspect.

## Does it require Docker?

No.

## Does it require a running MCP server?

No.

## Can I use it across multiple projects?

Yes. Install it into each Claude Code project where you want persistent memory behavior.

## Is it only for Claude Code?

The current packaging and workflow are optimized for Claude Code, though the underlying ideas apply more broadly to AI coding agents.

## How does the query mode work?

Run `/knowledge-graph query <your question>` to search the knowledge graph. It reads the `knowledge-index.md` to locate relevant modules, then reads their canonical knowledge nodes (`CLAUDE.md` or `SKILL.md`) and synthesizes an answer with sources. Useful for questions like "which module handles authentication?" or "what are the known pitfalls in the API layer?".

## What triggers an automatic update?

Two mechanisms:
1. **Write threshold**: every 15 file writes, `track.sh` injects an auto-update instruction.
2. **Prompt detection**: `prompt-trigger.sh` watches for completion signals ("搞定了", "ok了", "可以了", "整理一下") and failure signals ("还不行", "不对", "又错了") in your messages. When detected, it appends an instruction for Claude to run an update after finishing current work.

## What is the inference engine?

A pure bash + jq pattern mining system (`infer.sh`) that discovers implicit knowledge from event streams — zero LLM tokens consumed. It finds:
- **Co-change patterns**: files modified together within 10-min windows
- **Read→write sequences**: "every time X is changed, A and B are read first"
- **Knowledge decay**: rules that are stale (30+ days inactive) or ineffective (failures continue despite prohibition)
- **Predictive context**: given a file being read, predicts what modules will be needed next

## Does it survive `clear` and `compact`?

Yes. In Claude Code, the knowledge index uses `@include` in `.claude/CLAUDE.md`, which is part of the system prompt and automatically rebuilt after clear/compact. Module `CLAUDE.md` files are lazily re-loaded when Claude accesses files in those directories. In Codex, root `AGENTS.md` points the agent to the MCP server, which exposes the same canonical `CLAUDE.md` nodes. A PreCompact hook guides Claude's compactor to preserve prohibitions and error patterns.

## What is predictive context loading?

When Claude reads a file, the `PreToolUse(Read)` hook checks co-change history and pre-loads related modules' prohibitions as `additionalContext`. Claude knows the pitfalls of `src/middleware/` while still reading `src/auth/` — before any error happens.

## What makes it different?

The project combines:

- **Inference engine** — discovers implicit dependencies from event streams (no other tool does this)
- **Predictive loading** — pre-loads related knowledge before errors happen
- **Knowledge self-healing** — stale rules detected, ineffective prohibitions rewritten automatically
- **Context survival** — verified against Claude Code source code, not guesses
- **Zero LLM cost for analysis** — bash does all data collection and pattern mining
- **Git-native** — knowledge travels with code via `git push`
