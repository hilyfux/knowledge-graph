# scripts
## Prohibitions
- Scripts must finish within 2–5s → hook timeout kills them silently (CLAUDE.md project rule)
- Introducing runtime deps beyond jq + git → breaks zero-dep promise
- Writing under `.claude/` → causes auth prompts; use `.knowledge-graph/` (v1.1.1 migration)
- Recording non-module-level CLAUDE.md reads as `i` events → event spam (4698fd2)
## When Changing
- Editing any script → source `guard.sh` for `$KG_DATA` / `$CLAUDE_PROJECT_DIR`
- Adding a hook trigger → also wire it in `standalone/install.sh` all 3 merge paths (77b49b8)
- Changing event schema → update both `track.sh` (producer) and `infer.sh` / `analyze.sh` (consumers)
## Conventions
- One script per role: track (record), infer (mine), analyze (scan), context (inject), guard (shared), prompt-trigger (signals), mcp-server (MCP)
- Always quote `$CLAUDE_PROJECT_DIR` — paths may contain spaces
- Pure jq streams, no temp DBs; dedup via set files for O(1) lookups (d6a5f03)
