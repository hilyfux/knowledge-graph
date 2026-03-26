#!/bin/bash
# knowledge-graph install.sh
# Usage: bash /path/to/install.sh [/path/to/project]
# Copies skill + scripts to .claude/skills/knowledge-graph/, merges hooks into settings.json

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[kg]${NC} $*"; }
warn()  { echo -e "${YELLOW}[kg]${NC} $*"; }
error() { echo -e "${RED}[kg]${NC} $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || error "需要 jq，请先安装：brew install jq"

TARGET="${1:-$(pwd)}"
if [ "$(basename "$TARGET")" = ".claude" ]; then
  TARGET="$(dirname "$TARGET")"
  warn "检测到目标为 .claude 目录，已自动修正为项目根目录：$TARGET"
fi
[ "$TARGET" = "$HOME" ] && error "不能安装到 HOME 目录"
[ "$TARGET" = "/" ]     && error "不能安装到根目录"
[ ! -d "$TARGET" ]      && error "目标目录不存在：$TARGET"

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$INSTALL_DIR/skills/knowledge-graph"
SKILL_DST="$TARGET/.claude/skills/knowledge-graph"
SETTINGS="$TARGET/.claude/settings.json"

# ── Migration: detect old installation ────────────────────────────────────────
if [ -f "$TARGET/.claude/scripts/track-activity.sh" ]; then
  warn "检测到旧版安装（.claude/scripts/），开始迁移..."
  OLD_EVENTS="$TARGET/.claude/graph-events.jsonl"
  NEW_DATA="$SKILL_DST/data"
  mkdir -p "$NEW_DATA"
  if [ -f "$OLD_EVENTS" ]; then
    mv "$OLD_EVENTS" "$NEW_DATA/graph-events.jsonl"
    info "已迁移 graph-events.jsonl → skills/knowledge-graph/data/"
  fi
  rm -rf "$TARGET/.claude/scripts"
  rm -rf "$TARGET/.claude/commands"
  rm -f "$TARGET/.claude/graph-analysis.json" "$TARGET/.claude/graph-scan.json"
  info "已清理旧版脚本"
fi

# ── Create directories ─────────────────────────────────────────────────────────
mkdir -p "$SKILL_DST/scripts" "$SKILL_DST/data"

# ── Copy skill files ───────────────────────────────────────────────────────────
info "复制 skill 到 .claude/skills/knowledge-graph/ ..."
cp "$SKILL_SRC/SKILL.md" "$SKILL_DST/"
cp "$SKILL_SRC/scripts/"*.sh "$SKILL_DST/scripts/"
chmod +x "$SKILL_DST/scripts/"*.sh

# ── Merge hooks into settings.json ────────────────────────────────────────────
HOOKS_JSON=$(cat << 'ENDJSON'
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" write", "timeout": 3}]
    }
  ],
  "PostToolUseFailure": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" failure", "timeout": 2}]
    }
  ],
  "InstructionsLoaded": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" instructions", "timeout": 2}]
    }
  ],
  "SessionStart": [
    {
      "matcher": "startup|clear",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" startup", "timeout": 5}]
    },
    {
      "matcher": "compact",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" compact", "timeout": 5}]
    },
    {
      "matcher": "resume",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" resume", "timeout": 5}]
    }
  ],
  "SubagentStart": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" subagent", "timeout": 3}]
    }
  ],
  "Stop": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/analyze.sh\" stop", "timeout": 3}]
    }
  ]
}
ENDJSON
)

info "合并 hooks 到 .claude/settings.json ..."
if [ ! -f "$SETTINGS" ]; then
  echo "{}" | jq --argjson h "$HOOKS_JSON" '. + {hooks: $h}' > "$SETTINGS"
else
  EXISTING=$(cat "$SETTINGS")
  # Detect old hooks (track-activity.sh path) and replace them
  if echo "$EXISTING" | jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command | contains("track-activity.sh"))' >/dev/null 2>&1; then
    warn "检测到旧版 hooks，替换为新路径..."
    echo "$EXISTING" | jq \
      --argjson h "$HOOKS_JSON" \
      '
        .hooks //= {} |
        .hooks.PostToolUse        = ((.hooks.PostToolUse // [])        | map(select(.hooks[]?.command | contains("track-activity.sh") | not)) + $h.PostToolUse) |
        .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) | map(select(.hooks[]?.command | contains("track-failure.sh") | not))  + $h.PostToolUseFailure) |
        .hooks.InstructionsLoaded = ((.hooks.InstructionsLoaded // []) | map(select(.hooks[]?.command | contains("track-instructions.sh") | not)) + $h.InstructionsLoaded) |
        .hooks.SessionStart       = ((.hooks.SessionStart // [])       | map(select(.hooks[]?.command | contains("inject-") | not) | select(.hooks[]?.command | contains("on-compact") | not)) + $h.SessionStart) |
        .hooks.SubagentStart      = ((.hooks.SubagentStart // [])      | map(select(.hooks[]?.command | contains("inject-subagent") | not)) + $h.SubagentStart) |
        .hooks.Stop               = ((.hooks.Stop // [])               | map(select(.hooks[]?.command | contains("on-stop") | not)) + $h.Stop)
      ' > "$SETTINGS"
  elif echo "$EXISTING" | jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command | contains("knowledge-graph/scripts/track.sh"))' >/dev/null 2>&1; then
    warn "检测到已安装的 hooks，跳过合并（如需重装请先删除 settings.json 中的 kg hooks）"
  else
    echo "$EXISTING" | jq \
      --argjson h "$HOOKS_JSON" \
      '
        .hooks //= {} |
        .hooks.PostToolUse        = ((.hooks.PostToolUse // [])        + $h.PostToolUse) |
        .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) + $h.PostToolUseFailure) |
        .hooks.InstructionsLoaded = ((.hooks.InstructionsLoaded // []) + $h.InstructionsLoaded) |
        .hooks.SessionStart       = ((.hooks.SessionStart // [])       + $h.SessionStart) |
        .hooks.SubagentStart      = ((.hooks.SubagentStart // [])      + $h.SubagentStart) |
        .hooks.Stop               = ((.hooks.Stop // [])               + $h.Stop)
      ' > "$SETTINGS"
  fi
fi

# ── Init data file ─────────────────────────────────────────────────────────────
touch "$SKILL_DST/data/graph-events.jsonl"

# ── Update .gitignore ──────────────────────────────────────────────────────────
GITIGNORE="$TARGET/.gitignore"
if [ -f "$GITIGNORE" ] && ! grep -q "knowledge-graph/data" "$GITIGNORE"; then
  echo ".claude/skills/knowledge-graph/data/" >> "$GITIGNORE"
  info "已添加 data/ 到 .gitignore"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
echo ""
info "✅ 安装完成！"
echo ""
echo "  已安装到: $TARGET/.claude/skills/knowledge-graph/"
echo ""
echo "  下一步："
echo "  1. 重启 Claude Code session（让 hooks 生效）"
echo "  2. 运行 /knowledge-graph init 初始化知识图谱"
echo ""
