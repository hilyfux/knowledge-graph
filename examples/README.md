# Examples

This directory shows what Knowledge Graph looks like in practice.

The goal is not to provide a fake full repository, but to make the expected file layout and workflow easier to understand before installation.

## Example structure after install

```text
.your-project/
  .claude/
    settings.json
    skills/
      knowledge-graph/
        SKILL.md
        scripts/
          analyze.sh
          context.sh
          guard.sh
          prompt-trigger.sh
          track.sh
        data/
          graph-events.jsonl
```

## Typical lifecycle

1. Install Knowledge Graph into a Claude Code project.
2. Restart the Claude Code session.
3. Run `/knowledge-graph init`.
4. Let normal file operations and prompts accumulate event history.
5. Reuse the synthesized project context across future sessions.

## What to inspect first

- `.claude/settings.json` for installed hooks
- `.claude/skills/knowledge-graph/scripts/` for runtime behavior
- `.claude/skills/knowledge-graph/data/graph-events.jsonl` for captured local events

## Suggested real-world use cases

- Long-running feature work across multiple Claude Code sessions
- Repositories with recurring architectural patterns or local conventions
- Solo developer projects where context loss creates repeated re-explanation
- Teams experimenting with persistent memory without adding databases or hosted services
