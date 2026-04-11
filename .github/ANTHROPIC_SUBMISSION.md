# Plugin Submission: knowledge-graph — Persistent memory layer for Claude Code

## One-liner

Pure bash+jq persistent memory that makes Claude Code remember across sessions — zero dependencies, zero interrupts, zero LLM cost for analysis.

## Repository

https://github.com/hilyfux/knowledge-graph

## What problem does this solve?

Claude Code is stateless. Every `clear`, every `compact`, every new session starts from zero. Users repeatedly re-explain what they're working on, which modules matter, and what pitfalls to avoid.

Knowledge Graph solves this by building an automatic, persistent memory layer:
- **Tracks** every file operation via hooks (read, write, edit, failure)
- **Learns** implicit module dependencies from co-change patterns (pure bash, no LLM tokens)
- **Predicts** which modules Claude will need next and pre-loads their rules
- **Saves** working state on session end; **restores** it after `clear` or `compact`
- **Generates** distributed `CLAUDE.md` knowledge nodes (≤20 lines each) with evidence-based rules

## What makes it different?

| Aspect | Knowledge Graph | Typical approaches |
|--------|----------------|-------------------|
| Dependencies | `jq` only | Vector DB, embeddings, Python, Docker |
| Runtime cost | ~5ms per hook, 0 LLM tokens for analysis | Embedding costs, API calls per query |
| Learns over time | Yes (inference engine mines patterns) | Static indexing |
| Predicts context | Yes (co-change history) | No |
| Survives clear/compact | Yes (snapshot + @include, verified against Claude Code source) | No |
| Interrupts coding | Never (v1.2 zero-interrupt architecture) | Often |
| Team sharing | `git push` (plain files) | Manual DB export |

## Technical highlights

**Zero-Interrupt Architecture (v1.2)**
- No mid-coding interrupts. Events accumulate silently; analysis runs at session boundaries (Stop hook).
- Working Set tracking: knows which modules are "paged in" this session; skips redundant predictions.
- Prediction Cache: 300s TTL per-directory. First access ~200ms (prediction), subsequent ~5ms (cache hit).
- Work Snapshot: saved on session end + before compact. Injected on next session start. Makes `clear` non-destructive.

**Inference Engine (pure bash + jq)**
- `cochange`: discovers files modified together within 10-min windows
- `sequences`: mines read→write patterns to discover implicit prerequisites  
- `decay`: monitors rule effectiveness (effective / ineffective / stale)
- `predict`: predicts related modules from co-change history (bounded to 300 recent events)

**Pipeline Resilience**
- Event rotation: auto-truncate to 300 lines on session end
- Corrupt line tolerance: malformed JSON lines filtered, not fatal
- N+1 elimination: decay analysis from N full-file scans to 1 pre-computation pass

**Context Survival (verified against Claude Code source)**
- `@include` directive: knowledge index in system prompt, survives `clear` + `compact` natively
- PreCompact hook: saves snapshot + guides compactor to preserve working set
- PostCompact hook: restores snapshot + working set prohibitions
- Total baseline token cost: <0.5% of context window (~500-900 tokens)

## Plugin compatibility

- `plugin.json` manifest included
- MCP Server (`mcp-server.sh`): 4 tools — `kg_status`, `kg_query`, `kg_predict`, `kg_cochange`
- 9 hooks: PreToolUse, PostToolUse, PostToolUseFailure, InstructionsLoaded, SessionStart, PreCompact, PostCompact, SubagentStart, Stop
- Automated test suite: 15 tests covering performance, resilience, i18n

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hilyfux/knowledge-graph/main/standalone/install.sh) /path/to/project
# Restart Claude Code, then:
/knowledge-graph init
```

## Stats

- **1599 lines** of bash (total runtime)
- **0 external dependencies** beyond `jq`
- **15 automated tests**, all passing
- **MIT license**

## Author

[@hilyfux](https://github.com/hilyfux)
