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

Run `/knowledge-graph query <your question>` to search the knowledge graph. It reads the `knowledge-index.md` to locate relevant modules, then reads their `CLAUDE.md` files and synthesizes an answer with sources. Useful for questions like "which module handles authentication?" or "what are the known pitfalls in the API layer?".

## What triggers an automatic update?

Two mechanisms:
1. **Write threshold**: every 15 file writes, `track.sh` injects an auto-update instruction.
2. **Prompt detection**: `prompt-trigger.sh` watches for completion signals ("搞定了", "ok了", "可以了", "整理一下") and failure signals ("还不行", "不对", "又错了") in your messages. When detected, it appends an instruction for Claude to run an update after finishing current work.

## What makes it different?

The project combines:

- Anthropic internal engineering workflow inspiration
- Karpathy's AutoResearch-style knowledge building
- Persistent memory beyond the context window
- Zero-dependency shell-based implementation
- Git-native, privacy-first local storage
