# Configuration Guide

Knowledge Graph keeps configuration intentionally small. Most behavior is driven by the installed skill, hook wiring, and the structure of your repository.

## Installed layout

After installation, the relevant files live under:

```text
.claude/
├── settings.json
└── skills/
    └── knowledge-graph/
        ├── SKILL.md
        ├── scripts/
        └── data/
```

## Hook wiring

The installer merges Knowledge Graph into `.claude/settings.json`.

The system relies on these hook moments:

- `PostToolUse` for write and edit tracking
- `PostToolUseFailure` for learning from failed operations
- `InstructionsLoaded` for tracking which knowledge files were loaded
- `SessionStart` for injecting relevant context
- `SubagentStart` for propagating constraints into sub-agents
- `Stop` for pre-analysis when enough events have accumulated

If hooks appear missing, rerun the installer and restart Claude Code.

## Runtime data

Runtime data is local and should stay out of git:

```text
.claude/skills/knowledge-graph/data/
```

Typical contents include:

- event logs
- lightweight analysis artifacts
- temporary state used to decide when to refresh knowledge

The durable knowledge itself is written to `CLAUDE.md` files in your project and can be committed normally.

## Update cadence

By default, the workflow is designed around these thresholds:

- track every relevant file write or edit
- auto-trigger a knowledge refresh roughly every 15 writes
- run background pre-analysis when enough events accumulate

These defaults aim to keep overhead low while still capturing evolving project context.

## Team workflow

Recommended setup for teams:

1. Commit generated `CLAUDE.md` knowledge files.
2. Ignore runtime data under `.claude/skills/knowledge-graph/data/`.
3. Review important knowledge changes like any other documentation diff.
4. Let each contributor keep their local runtime event history private.

## Safe reinstallation

You can rerun the installer after pulling a new version of Knowledge Graph:

```bash
bash standalone/install.sh /path/to/project
```

This is the easiest way to refresh scripts and hook wiring without manually editing settings.

## Troubleshooting checklist

- `jq` is installed and available in `PATH`
- `.claude/settings.json` includes Knowledge Graph hooks
- Claude Code has been restarted after install or reinstall
- the target project is writable
- generated `CLAUDE.md` files are not being accidentally deleted by cleanup scripts
