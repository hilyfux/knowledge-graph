# Contributing to Knowledge Graph

Thanks for your interest in improving Knowledge Graph.

## What this project values

- Zero-dependency by default
- Git-native workflows
- Privacy-first local operation
- Small, understandable shell scripts
- Low runtime overhead

## Before opening a change

Please keep the project philosophy in mind:

1. Prefer simple bash over adding new infrastructure.
2. Avoid introducing databases, background services, or heavy runtime dependencies.
3. Keep installation friction low.
4. Preserve compatibility with Claude Code workflows.
5. Document user-facing behavior changes in `README.md` or `CHANGELOG.md` when relevant.

## Development setup

Clone the repo and inspect the standalone package:

```bash
git clone https://github.com/hilyfux/knowledge-graph.git
cd knowledge-graph
```

Main files:

- `standalone/install.sh` - installer and hook wiring
- `standalone/skills/knowledge-graph/SKILL.md` - skill entrypoint and usage guidance
- `standalone/skills/knowledge-graph/scripts/*.sh` - runtime scripts

## Local checks

Run basic shell validation before submitting:

```bash
bash -n standalone/install.sh
bash -n standalone/skills/knowledge-graph/scripts/*.sh
```

If you have `shellcheck` installed, run:

```bash
shellcheck standalone/install.sh standalone/skills/knowledge-graph/scripts/*.sh
```

## Pull request guidelines

Please aim for focused PRs.

- One logical change per PR
- Include a clear title and summary
- Explain why the change helps Claude Code memory or developer workflow
- Add migration notes if installation or hooks change
- Update `CHANGELOG.md` for notable changes

## Good first contributions

- Documentation improvements
- Installation clarifications
- Safer hook behavior
- Better migration handling
- Small performance or reliability fixes

## What to avoid

- Large dependency additions
- Breaking installer behavior without migration support
- Replacing local-first behavior with cloud-only services
- Adding complexity without a measurable benefit

If a proposal changes the core philosophy, open an issue or discussion first so the tradeoff is explicit.
