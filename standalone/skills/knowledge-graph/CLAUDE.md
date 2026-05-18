# knowledge-graph — skill package (SKILL.md + scripts/)
## Prohibitions
- Referencing `$CLAUDE_PROJECT_DIR` raw in SKILL.md bash blocks → unset in Bash tool shell, expands to `/...` (e173219)
- Editing SKILL.md without syncing installed copies via `version.sh sync-installed` → host drift (77b49b8)
- Adding new hook commands here without updating `standalone/install.sh` all 3 merge branches → installs miss the hook (77b49b8)
## When Changing
- Any script change → @standalone/skills/knowledge-graph/scripts/CLAUDE.md
- Hook wiring change → also patch `standalone/install.sh` HOOKS_JSON
- Skill body bash → call `analyze.sh` subcommands (lock/unlock/reset-trigger) instead of raw `$CLAUDE_PROJECT_DIR`
## Conventions
- Skill body uses `${CLAUDE_SKILL_DIR}` (set by harness) — safe; project dir resolved inside scripts via `guard.sh`
- Auto-trigger surfaces only through SessionStart, UserPromptSubmit, and pre-write — never PostToolUse
