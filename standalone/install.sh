#!/bin/bash
# knowledge-graph install.sh
# 用法：在任意项目根目录运行 bash /path/to/install.sh
# 会将 scripts、skill 复制到 .claude/，并将 hooks 合并到 .claude/settings.json

set -euo pipefail

# ── 颜色 ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[kg]${NC} $*"; }
warn()    { echo -e "${YELLOW}[kg]${NC} $*"; }
error()   { echo -e "${RED}[kg]${NC} $*" >&2; exit 1; }

# ── 前置检查 ──────────────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 || error "需要 jq，请先安装：brew install jq"

TARGET="${1:-$(pwd)}"
[ "$TARGET" = "$HOME" ] && error "不能安装到 HOME 目录"
[ "$TARGET" = "/" ]     && error "不能安装到根目录"
[ ! -d "$TARGET" ]      && error "目标目录不存在：$TARGET"

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"  # standalone/ 所在目录

# ── 创建目录 ──────────────────────────────────────────────────────────────────
mkdir -p "$TARGET/.claude/scripts" "$TARGET/.claude/commands"

# ── 复制脚本 ──────────────────────────────────────────────────────────────────
info "复制脚本到 .claude/scripts/ ..."
cp "$INSTALL_DIR/scripts/"*.sh  "$TARGET/.claude/scripts/"
chmod +x "$TARGET/.claude/scripts/"*.sh

# ── 复制 skill ────────────────────────────────────────────────────────────────
info "复制 skill 到 .claude/commands/ ..."
cp "$INSTALL_DIR/commands/knowledge-graph.md" "$TARGET/.claude/commands/"

# ── 合并 hooks 到 settings.json ───────────────────────────────────────────────
SETTINGS="$TARGET/.claude/settings.json"

# 新增的 hooks 片段（用 heredoc 避免单引号冲突）
HOOKS_JSON=$(cat << 'ENDJSON'
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit|Read|Glob|Grep",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/track-activity.sh\"", "timeout": 2}]
    }
  ],
  "PostToolUseFailure": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/track-failure.sh\"", "timeout": 2}]
    }
  ],
  "InstructionsLoaded": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/track-instructions.sh\"", "timeout": 2}]
    }
  ],
  "SessionStart": [
    {
      "matcher": "startup|clear",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/inject-graph-context.sh\"", "timeout": 5}]
    },
    {
      "matcher": "compact",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/on-compact.sh\"", "timeout": 5}]
    },
    {
      "matcher": "resume",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/inject-resume-context.sh\"", "timeout": 5}]
    }
  ],
  "SubagentStart": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/scripts/inject-subagent-context.sh\"", "timeout": 3}]
    }
  ]
}
ENDJSON
)

info "合并 hooks 到 .claude/settings.json ..."

if [ ! -f "$SETTINGS" ]; then
  # 文件不存在：直接创建
  echo "{}" | jq --argjson h "$HOOKS_JSON" '. + {hooks: $h}' > "$SETTINGS"
else
  # 文件已存在：逐事件合并（追加，不覆盖已有条目）
  EXISTING=$(cat "$SETTINGS")

  # 检查是否已安装（避免重复）
  if echo "$EXISTING" | jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command | contains("track-activity.sh"))' >/dev/null 2>&1; then
    warn "检测到已安装的 hooks，跳过合并（如需重新安装请先删除 .claude/settings.json 中的 kg hooks）"
  else
    # 逐事件合并：已有的 hooks 数组 + 新的追加
    echo "$EXISTING" | jq \
      --argjson h "$HOOKS_JSON" \
      '
        .hooks //= {} |
        .hooks.PostToolUse        = ((.hooks.PostToolUse // [])        + $h.PostToolUse) |
        .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) + $h.PostToolUseFailure) |
        .hooks.InstructionsLoaded = ((.hooks.InstructionsLoaded // []) + $h.InstructionsLoaded) |
        .hooks.SessionStart       = ((.hooks.SessionStart // [])       + $h.SessionStart) |
        .hooks.SubagentStart      = ((.hooks.SubagentStart // [])      + $h.SubagentStart)
      ' > "$SETTINGS"
  fi
fi

# ── 初始化数据文件 ─────────────────────────────────────────────────────────────
touch "$TARGET/.claude/graph-events.jsonl" \
      "$TARGET/.claude/graph-changelog.jsonl" \
      "$TARGET/.claude/graph-events-archive.jsonl"

# ── 完成 ──────────────────────────────────────────────────────────────────────
echo ""
info "✅ 安装完成！"
echo ""
echo "  下一步："
echo "  1. 重启 Claude Code session（让 hooks 生效）"
echo "  2. 运行 /knowledge-graph init 初始化知识图谱"
echo ""
