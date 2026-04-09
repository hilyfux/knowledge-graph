# Sample Session Walkthrough

This example illustrates the intended usage pattern at a high level.

## Before

You start a Claude Code session in an existing repository.

Without persistent memory, useful context often stays trapped in the current conversation window:

- local coding conventions
- naming patterns
- architectural constraints
- lessons learned during debugging
- files that are tightly coupled

## During the session

Knowledge Graph hooks observe relevant workflow events and keep a lightweight local event trail.

Examples of useful signals include:

- file writes and edits
- failed tool actions
- session starts and resumes
- prompt-driven context loading

## After repeated sessions

Instead of rebuilding the same context from scratch, the project can keep a structured memory trail inside the repository.

That means future Claude Code sessions can benefit from:

- better continuity
- lower repeated prompting cost
- more stable project conventions
- less context loss between sessions

## Why this example matters

The point of Knowledge Graph is not to replace coding workflow with a heavy memory platform.

It is to give Claude Code a practical, local, git-native memory layer that feels like part of the project itself.
