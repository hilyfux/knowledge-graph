#!/bin/bash
# guard.sh — Shared workspace guard for all hook scripts
# Usage: source this file at the top of every script.
# If the workspace is invalid, `exit` terminates the caller (intentional).

# Three-layer guard: unset / HOME / root
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

# Ensure project data space exists (auto-create on first use)
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
