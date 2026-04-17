#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SKILL_DIR/../../.." 2>/dev/null && pwd)}"
VERSION_FILE="$SKILL_DIR/VERSION"
STATUS_FILE="$PROJECT_DIR/.knowledge-graph/version.json"

read_version() {
  tr -d ' \t\r\n' < "$VERSION_FILE" 2>/dev/null || printf 'v0.0.0-dev'
}

read_commit() {
  if git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$PROJECT_DIR" rev-parse --short HEAD 2>/dev/null || printf 'unknown'
  else
    printf 'unknown'
  fi
}

print_status() {
  local version commit installed_at
  version=$(read_version)
  commit=$(read_commit)
  installed_at=$(date '+%Y-%m-%dT%H:%M:%S%z')
  jq -nc --arg version "$version" --arg commit "$commit" --arg installed_at "$installed_at" --arg source_repo "knowledge-graph" '{version:$version, commit:$commit, installed_at:$installed_at, source_repo:$source_repo}'
}

case "${1:-print}" in
  print)
    printf '%s\n' "$(read_version)+$(read_commit)"
    ;;
  status)
    if [ -f "$STATUS_FILE" ]; then
      cat "$STATUS_FILE"
    else
      print_status
    fi
    ;;
  sync-installed)
    mkdir -p "$PROJECT_DIR/.knowledge-graph"
    print_status > "$STATUS_FILE"
    cat "$STATUS_FILE"
    ;;
  *)
    echo "usage: version.sh [print|status|sync-installed]" >&2
    exit 1
    ;;
esac
