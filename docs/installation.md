# Installation Guide

Knowledge Graph is designed to be easy to adopt in an existing Claude Code workflow.

## Requirements

- `bash` (macOS/Linux: native; Windows: Git Bash or WSL)
- `jq`
- Claude Code project with a writable `.claude/` directory

Install `jq` if needed:

```bash
# macOS
brew install jq

# Linux
sudo apt install jq      # Debian/Ubuntu
sudo dnf install jq      # Fedora

# Windows (PowerShell)
winget install jqlang.jq
# or: scoop install jq / choco install jq
```

Windows users also need `bash`. The easiest path is Git for Windows (ships with Git Bash):

```powershell
winget install Git.Git
```

After installing, restart your shell so `bash.exe` is on `PATH`.

## Quick install (macOS / Linux / WSL)

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

## Quick install (Windows PowerShell)

```powershell
git clone https://github.com/hilyfux/knowledge-graph.git
cd knowledge-graph
.\standalone\install.ps1 C:\path\to\project
```

The PowerShell installer mirrors the bash one: copies the skill to
`.claude\skills\knowledge-graph\`, merges hooks into `.claude\settings.json`,
registers the MCP server in `.mcp.json`, and adds `.knowledge-graph/` to
`.gitignore`. Runtime still uses the `.sh` scripts — Claude Code's hooks run
them via the bash on your PATH.

> If you see `bash not found` or `jq not found` from `install.ps1`, install the
> missing tool using the commands in the Requirements section above, restart
> your shell, and re-run.

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
