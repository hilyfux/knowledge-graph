#!/bin/bash
# inject-graph-context.sh — SessionStart(startup|clear)
# Injects context: changelog + hot areas + git summary + health warnings
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# User-level installation: emit visible warning before guard silences everything
if [[ "$SCRIPT_DIR" == "$HOME/.claude/"* ]]; then
  MSG='⚠️ [knowledge-graph] 检测到 user 级别安装，插件已禁用。\n原因：user 级别会对所有项目生效，可能导致后台持续消耗 token。\n请卸载后改为项目级别安装：在项目根目录执行 claude plugin add knowledge-graph'
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":$(printf '%s' "$MSG" | jq -Rs .)}}"
  exit 0
fi

source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
ANALYSIS="$CLAUDE_PROJECT_DIR/.claude/graph-analysis.json"
CONTEXT=""

# Clean up stale lockfile
rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

# Auto-suggest init (fast check: no changelog = never initialized)
if [ ! -f "$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl" ] && [ ! -f "$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl.reported" ]; then
  if ! find "$CLAUDE_PROJECT_DIR" -maxdepth 3 -name "CLAUDE.md" -not -path "*/.git/*" 2>/dev/null | grep -q .; then
    emit_hook_context "$(json_escape '[知识图谱] 此项目尚未初始化。执行 /knowledge-graph:init-knowledge-graph 开始。')"
    exit 0
  fi
fi

# 1. Evolution updates
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  UPDATES=$(tail -10 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path + " (" + .reason + ")"' 2>/dev/null)
  if [ -n "$UPDATES" ]; then
    CONTEXT="[知识图谱更新]\n$UPDATES"
    mv "$CHANGELOG" "${CHANGELOG}.reported" 2>/dev/null
  fi
fi

# 2. Hot areas + health (from cache or events)
if [ -f "$ANALYSIS" ]; then
  HOT=$(jq -r '.dirs[:3][] | "  \(.w)次写入 \(.dir)"' "$ANALYSIS" 2>/dev/null)
  BROKEN=$(jq -r '.broken_refs[]' "$ANALYSIS" 2>/dev/null)
  [ -n "$HOT" ] && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
  [ -n "$BROKEN" ] && CONTEXT="$CONTEXT\n[断裂引用]\n$BROKEN"
elif [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e | startswith("w")) | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  [ -n "$HOT" ] && CONTEXT="$CONTEXT\n[活跃区域]\n$HOT"
fi

# 3. Git summary
if command -v git &>/dev/null && git -C "$CLAUDE_PROJECT_DIR" rev-parse --git-dir &>/dev/null; then
  GIT=$(git -C "$CLAUDE_PROJECT_DIR" log --oneline -5 2>/dev/null)
  [ -n "$GIT" ] && CONTEXT="$CONTEXT\n[最近提交]\n$GIT"
fi

[ -n "$CONTEXT" ] && emit_hook_context "$(json_escape "$(echo -e "$CONTEXT")")"
exit 0
