# Skill-Centric Knowledge Graph Design

**Date**: 2026-03-26
**Status**: Approved

---

## Problem

Current installation puts 11+ scripts into `.claude/scripts/` of user projects — polluting their namespace, hard to manage, and conceptually wrong. The scripts are implementation internals, not user-facing artifacts.

Additionally, the current skill file (`commands/knowledge-graph.md`) is a flat markdown file with no access to its own directory, making it impossible to co-locate scripts with the skill that uses them.

---

## Goal

Restructure knowledge-graph as a proper Claude Code skill with its own directory. All files live under `.claude/skills/knowledge-graph/`. User sees one coherent unit they can understand and modify. Hooks stay fast (pure bash). Skill is the only LLM layer.

---

## Architecture

### Directory Structure (installed in target project)

```
.claude/
├── settings.json                              ← hooks only, no kg logic
└── skills/
    └── knowledge-graph/
        ├── SKILL.md                           ← main entry, all LLM intelligence
        ├── scripts/
        │   ├── guard.sh                       ← shared: validate env, helpers
        │   ├── track.sh                       ← PostToolUse/Failure/Instructions
        │   ├── context.sh                     ← SessionStart (all) + SubagentStart
        │   └── analyze.sh                     ← Stop + scan-project + pre-analyze
        └── data/                              ← runtime data (gitignored)
            ├── graph-events.jsonl
            ├── graph-analysis.json
            └── graph-scan.json
```

### Source Repo Structure

```
knowledge-graph/
├── standalone/
│   ├── install.sh
│   ├── skills/
│   │   └── knowledge-graph/
│   │       ├── SKILL.md
│   │       └── scripts/
│   │           ├── guard.sh
│   │           ├── track.sh
│   │           ├── context.sh
│   │           └── analyze.sh
│   └── (no commands/ or scripts/ at top level)
├── README.md
└── .gitignore
```

---

## Script Consolidation: 11 → 3 + guard

| Old (11 files) | New | Responsibility |
|---|---|---|
| track-activity.sh | track.sh | PostToolUse (Write/Edit): record event + milestone block |
| track-failure.sh | track.sh | PostToolUseFailure: record error |
| track-instructions.sh | track.sh | InstructionsLoaded: record CLAUDE.md load |
| inject-graph-context.sh | context.sh | SessionStart startup/clear |
| inject-resume-context.sh | context.sh | SessionStart resume |
| on-compact.sh | context.sh | SessionStart compact |
| inject-subagent-context.sh | context.sh | SubagentStart |
| on-stop.sh | analyze.sh | Stop: background pre-analysis |
| scan-project.sh | analyze.sh | init helper |
| pre-analyze.sh | analyze.sh | update helper |
| guard.sh | guard.sh | unchanged |

Each consolidated script dispatches on `$KG_EVENT` or `$1` argument to handle multiple hook events.

---

## SKILL.md Design

```yaml
---
name: knowledge-graph
description: |
  Manages project knowledge graph (CLAUDE.md nodes). Auto-invoke when:
  - A kg auto-instruction block is received
  - Project has no CLAUDE.md files and user asks about structure
  - User asks about project modules or knowledge graph state
  Arguments: init (first time) / update (incremental refresh) / status (health)
argument-hint: [init|update|status]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---
```

### Shell Pre-injection

The skill uses `` !`command` `` to inject live data before Claude sees the content:

```markdown
Project state: !`bash ${CLAUDE_SKILL_DIR}/scripts/analyze.sh --quick-status`
Pending events: !`wc -l < ${CLAUDE_PROJECT_DIR}/.claude/skills/knowledge-graph/data/graph-events.jsonl 2>/dev/null || echo 0`
```

This means Claude receives pre-computed context without needing to run Bash tool calls for basic state checks. Faster, cleaner.

### Auto-dispatch Logic

The skill reads `$ARGUMENTS` and dispatches:
- `init` → full project scan + CLAUDE.md generation
- `update` → incremental refresh from events
- `status` → health report
- (empty) → skill auto-detects: no events file → suggest init; events ≥ threshold → run update

---

## Hook Configuration (settings.json)

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Write|Edit",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" write", "timeout": 3}]
    }],
    "PostToolUseFailure": [{
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" failure", "timeout": 2}]
    }],
    "InstructionsLoaded": [{
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" instructions", "timeout": 2}]
    }],
    "SessionStart": [
      {"matcher": "startup|clear", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" startup", "timeout": 5}]},
      {"matcher": "compact",       "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" compact", "timeout": 5}]},
      {"matcher": "resume",        "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" resume",  "timeout": 5}]}
    ],
    "SubagentStart": [{
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" subagent", "timeout": 3}]
    }],
    "Stop": [{
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/analyze.sh\" stop", "timeout": 3}]
    }]
  }
}
```

---

## Auto-trigger Chain

```
Write/Edit file
  → track.sh write
    → append to graph-events.jsonl
    → if count % 15 == 0:
        output {"decision":"block","reason":"[kg] N events. 【自动指令】调用 knowledge-graph skill (args: update)"}
          → Claude reads description, recognizes kg instruction
          → invokes SKILL.md with args: update
            → !`analyze.sh --quick-status` pre-injects current state
            → Claude executes incremental update
            → continues original task

Session start
  → context.sh startup
    → reads graph-analysis.json
    → if pending events ≥ 10: appends reminder to context
    → injects hot zones + recent commits

Session stop
  → analyze.sh stop
    → if events ≥ 20: background pre-analyze (no LLM, < 1s)
```

---

## install.sh Changes

- Source path: `standalone/skills/knowledge-graph/` instead of `standalone/scripts/` + `standalone/commands/`
- Target: `.claude/skills/knowledge-graph/`
- Creates `data/` directory inside skill dir
- Hook paths updated to reference new location
- `.claude` guard (already exists)

---

## Data Flow

```
graph-events.jsonl    ← written by track.sh (append-only, fast)
graph-analysis.json   ← written by analyze.sh (background, on stop)
graph-scan.json       ← written by analyze.sh --scan (on init/update, temp)
CLAUDE.md files       ← written by SKILL.md via Claude (LLM decision)
```

Runtime data stays in `data/`. Knowledge artifacts (CLAUDE.md) go in project dirs. Both patterns unchanged.

---

## Migration

For projects already using the old structure:
1. Run updated `install.sh` — it detects old installation and migrates
2. Old `.claude/scripts/*.sh` removed, new `.claude/skills/knowledge-graph/` created
3. `settings.json` hooks updated to new paths
4. `graph-events.jsonl` moved to `data/`

---

## What Doesn't Change

- Three commands: `init`, `update`, `status`
- Evidence-based CLAUDE.md rules (quality_check logic)
- Milestone block trigger (every 15 writes)
- No `claude -p`, no background LLM
- Idempotent operations
