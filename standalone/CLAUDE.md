# standalone — install surface
## Prohibitions
- Editing hook/script paths only in one place → installed copies drift and host projects run mixed behavior (77b49b8)
- Writing runtime data under `.claude/` → auth prompts and polluted repo state; keep it in `.knowledge-graph/` (v1.1.1)
- Changing installer flow without validating all merge branches → missing hooks survive in existing installs (77b49b8)
## When Changing
- Editing installer or packaged skill layout → @standalone/skills/knowledge-graph/CLAUDE.md
- Changing packaged script names or hook commands → @standalone/skills/knowledge-graph/scripts/CLAUDE.md
## Conventions
- `standalone/` is the canonical distribution tree copied into host projects
- Validate install changes with `bash -n standalone/install.sh` before sync
