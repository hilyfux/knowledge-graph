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

## What makes it different?

The project combines:

- Anthropic internal engineering workflow inspiration
- Karpathy's AutoResearch-style knowledge building
- Persistent memory beyond the context window
- Zero-dependency shell-based implementation
- Git-native, privacy-first local storage
