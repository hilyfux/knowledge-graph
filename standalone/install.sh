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

# ── Clean up scattered legacy files ───────────────────────────────────────────
LEGACY_FILES=(
  "$TARGET/.claude/graph-changelog.jsonl"
  "$TARGET/.claude/graph-changelog.jsonl.reported"
  "$TARGET/.claude/graph-events-archive.jsonl"
  "$TARGET/.claude/knowledge-graph.md"
  "$TARGET/.claude/knowledge-index.md"
)
for f in "${LEGACY_FILES[@]}"; do
  [ -f "$f" ] && rm -f "$f" && info "已清理散落文件：$(basename "$f")"
done
# Migrate graph-events.jsonl from .claude/ root to data/ (if still there)
if [ -f "$TARGET/.claude/graph-events.jsonl" ]; then
  mkdir -p "$SKILL_DST/data"
  mv "$TARGET/.claude/graph-events.jsonl" "$SKILL_DST/data/graph-events.jsonl"
  info "已迁移 graph-events.jsonl → data/"
fi
if [ -f "$TARGET/.claude/graph-analysis.json" ]; then
  rm -f "$TARGET/.claude/graph-analysis.json"
  info "已清理散落的 graph-analysis.json"
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
  "PreToolUse": [
    {
      "matcher": "Read",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" read", "timeout": 3}]
    },
    {
      "matcher": "Write|Edit",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/track.sh\" pre-write", "timeout": 3}]
    }
  ],
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
  "PreCompact": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" precompact", "timeout": 3}]
    }
  ],
  "PostCompact": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/context.sh\" postcompact", "timeout": 5}]
    }
  ],
  "Stop": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/analyze.sh\" stop", "timeout": 3}]
    }
  ],
  "UserPromptSubmit": [
    {
      "matcher": "*",
      "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/prompt-trigger.sh\"", "timeout": 2}]
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
        .hooks.PreToolUse         = ((.hooks.PreToolUse // [])         + $h.PreToolUse) |
        .hooks.PostToolUse        = ((.hooks.PostToolUse // [])        | map(select(.hooks[]?.command | contains("track-activity.sh") | not)) + $h.PostToolUse) |
        .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) | map(select(.hooks[]?.command | contains("track-failure.sh") | not))  + $h.PostToolUseFailure) |
        .hooks.InstructionsLoaded = ((.hooks.InstructionsLoaded // []) | map(select(.hooks[]?.command | contains("track-instructions.sh") | not)) + $h.InstructionsLoaded) |
        .hooks.SessionStart       = ((.hooks.SessionStart // [])       | map(select(.hooks[]?.command | contains("inject-") | not) | select(.hooks[]?.command | contains("on-compact") | not)) + $h.SessionStart) |
        .hooks.SubagentStart      = ((.hooks.SubagentStart // [])      | map(select(.hooks[]?.command | contains("inject-subagent") | not)) + $h.SubagentStart) |
        .hooks.Stop               = ((.hooks.Stop // [])               | map(select(.hooks[]?.command | contains("on-stop") | not)) + $h.Stop) |
        .hooks.PreCompact         = ((.hooks.PreCompact // [])         + $h.PreCompact) |
        .hooks.PostCompact        = ((.hooks.PostCompact // [])        | map(select(.hooks[]?.command | contains("context.sh") | not)) + $h.PostCompact) |
        .hooks.UserPromptSubmit   = ((.hooks.UserPromptSubmit // [])   | map(select(.hooks[]?.command | contains("prompt-trigger") | not)) + $h.UserPromptSubmit)
      ' > "$SETTINGS"
  elif echo "$EXISTING" | jq -e '.hooks.PostToolUse[]? | select(.hooks[]?.command | contains("knowledge-graph/scripts/track.sh"))' >/dev/null 2>&1; then
    # Already installed — patch missing hooks
    PATCHED=false
    for HOOK_TYPE in PreToolUse PreCompact UserPromptSubmit PostCompact; do
      HOOK_CMD=""
      case "$HOOK_TYPE" in
        PreToolUse)    HOOK_CMD="pre-write" ;;
        PreCompact)    HOOK_CMD="precompact" ;;
        UserPromptSubmit) HOOK_CMD="prompt-trigger" ;;
        PostCompact)   HOOK_CMD="postcompact" ;;
      esac
      if ! echo "$EXISTING" | jq -e ".hooks.${HOOK_TYPE}[]?" >/dev/null 2>&1; then
        info "补充 ${HOOK_TYPE} hook..."
        EXISTING=$(echo "$EXISTING" | jq --argjson h "$HOOKS_JSON" ".hooks.${HOOK_TYPE} = ((.hooks.${HOOK_TYPE} // []) + \$h.${HOOK_TYPE})")
        PATCHED=true
      fi
    done
    if [ "$PATCHED" = true ]; then
      echo "$EXISTING" > "$SETTINGS"
    else
      warn "检测到已安装的 hooks，跳过合并（如需重装请先删除 settings.json 中的 kg hooks）"
    fi
  else
    echo "$EXISTING" | jq \
      --argjson h "$HOOKS_JSON" \
      '
        .hooks //= {} |
        .hooks.PreToolUse         = ((.hooks.PreToolUse // [])         + $h.PreToolUse) |
        .hooks.PostToolUse        = ((.hooks.PostToolUse // [])        + $h.PostToolUse) |
        .hooks.PostToolUseFailure = ((.hooks.PostToolUseFailure // []) + $h.PostToolUseFailure) |
        .hooks.InstructionsLoaded = ((.hooks.InstructionsLoaded // []) + $h.InstructionsLoaded) |
        .hooks.SessionStart       = ((.hooks.SessionStart // [])       + $h.SessionStart) |
        .hooks.SubagentStart      = ((.hooks.SubagentStart // [])      + $h.SubagentStart) |
        .hooks.Stop               = ((.hooks.Stop // [])               + $h.Stop) |
        .hooks.PreCompact         = ((.hooks.PreCompact // [])         + $h.PreCompact) |
        .hooks.PostCompact        = ((.hooks.PostCompact // [])        + $h.PostCompact) |
        .hooks.UserPromptSubmit   = ((.hooks.UserPromptSubmit // [])   + $h.UserPromptSubmit)
      ' > "$SETTINGS"
  fi
fi

# ── Init data directory ────────────────────────────────────────────────────────
KG_DATA_DIR="$TARGET/.knowledge-graph"
mkdir -p "$KG_DATA_DIR"
touch "$KG_DATA_DIR/graph-events.jsonl"

# Migrate data from old location (.claude/skills/knowledge-graph/data/)
OLD_DATA="$SKILL_DST/data"
if [ -d "$OLD_DATA" ] && [ -f "$OLD_DATA/graph-events.jsonl" ]; then
  info "迁移数据从 .claude/.../data/ → .knowledge-graph/"
  for f in "$OLD_DATA"/*; do
    [ -f "$f" ] && mv "$f" "$KG_DATA_DIR/" 2>/dev/null
  done
  rmdir "$OLD_DATA" 2>/dev/null
fi

# ── Setup @include in .claude/CLAUDE.md ───────────────────────────────────────
INCLUDE_LINE="@.knowledge-graph/knowledge-index.md"
OLD_INCLUDE="@.claude/skills/knowledge-graph/data/knowledge-index.md"
DOT_CLAUDE_MD="$TARGET/.claude/CLAUDE.md"
if [ -f "$DOT_CLAUDE_MD" ]; then
  # 清理旧的 @include
  grep -qF "$OLD_INCLUDE" "$DOT_CLAUDE_MD" && \
    sed -i '' "s|$OLD_INCLUDE|$INCLUDE_LINE|g" "$DOT_CLAUDE_MD" 2>/dev/null
  if ! grep -qF "$INCLUDE_LINE" "$DOT_CLAUDE_MD"; then
    echo "" >> "$DOT_CLAUDE_MD"
    echo "$INCLUDE_LINE" >> "$DOT_CLAUDE_MD"
    info "已在 .claude/CLAUDE.md 中添加知识索引 @include"
  fi
else
  echo "$INCLUDE_LINE" > "$DOT_CLAUDE_MD"
  info "已创建 .claude/CLAUDE.md 并添加知识索引 @include"
fi

# ── Register MCP server in .mcp.json ─────────────────────────────────────────
MCP_JSON="$TARGET/.mcp.json"
MCP_CMD="bash"
MCP_ARGS="[\"$SKILL_DST/scripts/mcp-server.sh\"]"
if [ -f "$MCP_JSON" ]; then
  if ! jq -e '.mcpServers["knowledge-graph"]' "$MCP_JSON" >/dev/null 2>&1; then
    jq --arg cmd "$MCP_CMD" --argjson args "$MCP_ARGS" \
      '.mcpServers["knowledge-graph"] = {"type": "stdio", "command": $cmd, "args": $args}' \
      "$MCP_JSON" > "$MCP_JSON.tmp" && mv "$MCP_JSON.tmp" "$MCP_JSON"
    info "已在 .mcp.json 中注册 knowledge-graph MCP server"
  fi
else
  jq -n --arg cmd "$MCP_CMD" --argjson args "$MCP_ARGS" \
    '{"mcpServers": {"knowledge-graph": {"type": "stdio", "command": $cmd, "args": $args}}}' > "$MCP_JSON"
  info "已创建 .mcp.json 并注册 knowledge-graph MCP server"
fi

# ── Update .gitignore ──────────────────────────────────────────────────────────
GITIGNORE="$TARGET/.gitignore"
if [ -f "$GITIGNORE" ]; then
  # 添加新路径
  grep -q "^\.knowledge-graph/" "$GITIGNORE" || echo ".knowledge-graph/" >> "$GITIGNORE"
  # 清理旧路径
  grep -q "knowledge-graph/data" "$GITIGNORE" || true
  info "已更新 .gitignore"
else
  echo ".knowledge-graph/" > "$GITIGNORE"
  info "已创建 .gitignore"
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
