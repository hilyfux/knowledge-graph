# Installation Guide

Knowledge Graph is designed to be easy to adopt in an existing Claude Code workflow.

## Requirements

- macOS or Linux shell environment
- `bash`
- `jq`
- Claude Code project with a writable `.claude/` directory

Install `jq` if needed:

```bash
brew install jq
```

## Quick install

Clone the repository and run the installer against your project:

```bash
git clone https://github.com/hilyfux/knowledge-graph.git
cd knowledge-graph
bash standalone/install.sh /path/to/project
```

If you run the installer from inside your target project, you can also do:

```bash
bash /path/to/knowledge-graph/standalone/install.sh .
```

## What gets installed

The installer copies the skill into:

```text
.claude/skills/knowledge-graph/
```

It also wires the required hooks into:

```text
.claude/settings.json
```

And creates the local event log:

```text
.claude/skills/knowledge-graph/data/graph-events.jsonl
```

## After install

1. Restart Claude Code so hooks reload.
2. Run `/knowledge-graph init`.
3. Start using Claude Code normally.

## Reinstalling

You can rerun the installer safely after updates:

```bash
bash standalone/install.sh /path/to/project
```

The installer can migrate older `.claude/scripts/`-based installs to the current layout.

## Troubleshooting

### `jq` not found

Install `jq` and rerun the installer.

### Hooks are not firing

- Confirm `.claude/settings.json` contains the knowledge-graph hook entries.
- Restart the Claude Code session.
- Confirm the target project is not read-only.

### Installed into the wrong directory

If you accidentally target `.claude/`, the installer automatically corrects to the project root.
