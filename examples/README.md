# Examples

This directory shows what Knowledge Graph looks like in practice.

The goal is not to provide a fake full repository, but to make the expected file layout and workflow easier to understand before installation.

## Example structure after install

```text
.your-project/
  .claude/
    settings.json
    CLAUDE.md
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
          graph-cache.json
          work-snapshot.json
  src/
    auth/
      CLAUDE.md
    api/
      CLAUDE.md
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
- Module-level `CLAUDE.md` files to see how rules are synthesized

## Example 1: what a module node looks like

```markdown
# auth

## Prohibitions
- Raw token in localStorage -> XSS risk
- Refresh mock skipped in tests -> flaky CI

## When Changing
- Token flow -> @api/CLAUDE.md
- Session invalidation -> @middleware/CLAUDE.md
```

This is the core pattern: short, evidence-backed local rules that Claude can load lazily when it touches a directory.

## Example 2: what survives after `/clear`

A typical restored work snapshot looks like:

```json
{
  "activeModules": ["src/auth", "src/api"],
  "recentErrors": ["auth.test.ts: refresh token race condition"],
  "recentCommits": ["fix: dedupe refresh requests"]
}
```

Instead of starting from zero, Claude gets the exact working set back at session start.

## Example 3: prediction in practice

If Claude opens `src/api/routes.ts`, Knowledge Graph can pre-load rules from related modules such as `src/auth/` or `src/config/` based on recent co-change history. That means fewer exploratory reads and fewer repeated mistakes.

## Suggested real-world use cases

- Long-running feature work across multiple Claude Code sessions
- Repositories with recurring architectural patterns or local conventions
- Solo developer projects where context loss creates repeated re-explanation
- Teams experimenting with persistent memory without adding databases or hosted services
- OSS repos where contributors want inspectable memory instead of another service layer
