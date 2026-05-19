# docs — user-facing guides
## Prohibitions
- Documenting hook names/paths that diverge from `standalone/install.sh` HOOKS_JSON → users install and see stale instructions (77b49b8)
- Showing installed layout under `.claude/` for runtime data → contradicts v1.1.1 migration to `.knowledge-graph/`
- Adding version-pinned examples without bumping `standalone/skills/knowledge-graph/VERSION` + `version.json` → docs claim features the installed copy lacks
## When Changing
- Hook list or script names → cross-check @standalone/skills/knowledge-graph/scripts/CLAUDE.md
- Installer-flow descriptions → cross-check @standalone/CLAUDE.md
- Event schema docs (`events-schema.md`) → verify against `track.sh` producers
## Conventions
- Source-of-truth is code; docs mirror it, never the reverse
- Use the canonical names: `CLAUDE.md` for module nodes, `SKILL.md` for skill packages, `AGENTS.md` only as Codex adapter
