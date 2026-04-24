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
KG_VERSION_FILE="$SKILL_SRC/VERSION"
KG_VERSION="$(tr -d ' \t\r\n' < "$KG_VERSION_FILE" 2>/dev/null || true)"
[ -n "$KG_VERSION" ] || KG_VERSION="v0.0.0-dev"
KG_COMMIT="$(git -C "$INSTALL_DIR/.." rev-parse --short HEAD 2>/dev/null || echo unknown)"
KG_INSTALLED_AT="$(date '+%Y-%m-%dT%H:%M:%S%z')"
KG_VERSION_STATUS="$TARGET/.knowledge-graph/version.json"
KG_VERSION_TEXT="$SKILL_DST/VERSION"
KG_VERSION_LINE="$KG_VERSION+$KG_COMMIT"
KG_STATUS_CMD='bash "$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/version.sh" status'
KG_SYNC_CMD='bash "$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/version.sh" sync-installed'
KG_PRINT_CMD='bash "$CLAUDE_PROJECT_DIR/.claude/skills/knowledge-graph/scripts/version.sh" print'
KG_VERSION_JSON=$(jq -nc --arg version "$KG_VERSION" --arg commit "$KG_COMMIT" --arg installed_at "$KG_INSTALLED_AT" --arg source_repo "knowledge-graph" '{version:$version, commit:$commit, installed_at:$installed_at, source_repo:$source_repo}')
KG_ROOT_CLAUDE="$TARGET/CLAUDE.md"
KG_ROOT_AGENTS="$TARGET/AGENTS.md"
KG_ROOT_VERSION_PREFIX="Installed Knowledge Graph: "
KG_ROOT_VERSION_LINE="Installed Knowledge Graph: $KG_VERSION_LINE"
KG_ROOT_VERSION_HINT="Use version+commit to compare source repo, installed copy, and host project state"
KG_AGENTS_BEGIN="<!-- knowledge-graph:codex begin -->"
KG_AGENTS_END="<!-- knowledge-graph:codex end -->"

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
mkdir -p "$TARGET/.knowledge-graph"

# ── Copy skill files ───────────────────────────────────────────────────────────
info "复制 skill 到 .claude/skills/knowledge-graph/ ..."
cp "$SKILL_SRC/SKILL.md" "$SKILL_DST/"
cp "$SKILL_SRC/VERSION" "$SKILL_DST/"
cp "$SKILL_SRC/scripts/"*.sh "$SKILL_DST/scripts/"
chmod +x "$SKILL_DST/scripts/"*.sh
printf 'version=%s\ncommit=%s\ninstalled_at=%s\nsource_repo=knowledge-graph\n' "$KG_VERSION" "$KG_COMMIT" "$KG_INSTALLED_AT" > "$KG_VERSION_TEXT"
printf '%s\n' "$KG_VERSION_JSON" > "$KG_VERSION_STATUS"
info "已写入版本元数据：$KG_VERSION_LINE"
info "版本检查：! $KG_STATUS_CMD"
info "版本同步：! $KG_SYNC_CMD"
info "版本打印：! $KG_PRINT_CMD"

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
    PATCHED=false
    for HOOK_TYPE in PreToolUse PreCompact UserPromptSubmit PostCompact; do
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

if [ -f "$KG_ROOT_CLAUDE" ]; then
  python3 - "$KG_ROOT_CLAUDE" "$KG_ROOT_VERSION_PREFIX" "$KG_ROOT_VERSION_LINE" "$KG_ROOT_VERSION_HINT" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
prefix = sys.argv[2]
line = sys.argv[3]
hint = sys.argv[4]
text = path.read_text()
lines = text.splitlines()
out = []
replaced = False
for item in lines:
    if item.startswith(prefix):
        out.append(line)
        replaced = True
    else:
        out.append(item)
if not replaced:
    if out and out[-1] != "":
        out.append("")
    out.append(line)
    out.append("")
    out.append(hint)
path.write_text("\n".join(out) + "\n")
PY
else
  printf '%s\n\n%s\n' "$KG_ROOT_VERSION_LINE" "$KG_ROOT_VERSION_HINT" > "$KG_ROOT_CLAUDE"
fi

# ── Add Codex operating notes to AGENTS.md ───────────────────────────────────
AGENTS_BLOCK=$(cat <<EOF
$KG_AGENTS_BEGIN
## Knowledge Graph

- Use the bundled MCP server in .mcp.json when available: start with kg_status, then kg_query or kg_read_node before editing unfamiliar modules.
- Durable module knowledge lives in canonical CLAUDE.md and SKILL.md files. AGENTS.md is only the Codex adapter that tells Codex to read those canonical nodes through MCP.
- Runtime data lives under .knowledge-graph/ and should stay uncommitted.
- If running scripts outside Claude Code, set KG_PROJECT_DIR to this project root; Claude Code may set CLAUDE_PROJECT_DIR instead.
- Before reporting success, include concrete evidence: tests run, files checked, or MCP resources consulted.
$KG_AGENTS_END
EOF
)

if [ -f "$KG_ROOT_AGENTS" ]; then
  python3 - "$KG_ROOT_AGENTS" "$KG_AGENTS_BEGIN" "$KG_AGENTS_END" "$AGENTS_BLOCK" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
begin, end, block = sys.argv[2], sys.argv[3], sys.argv[4]
text = path.read_text()
if begin in text and end in text:
    before = text.split(begin, 1)[0].rstrip()
    after = text.split(end, 1)[1].lstrip()
    text = before + "\n\n" + block + "\n\n" + after
else:
    text = text.rstrip() + "\n\n" + block + "\n"
path.write_text(text)
PY
else
  printf '# Project Instructions\n\n%s\n' "$AGENTS_BLOCK" > "$KG_ROOT_AGENTS"
fi
info "已更新 AGENTS.md，Codex 可读取 Knowledge Graph 操作说明"

# ── Register MCP server in .mcp.json ─────────────────────────────────────────
MCP_JSON="$TARGET/.mcp.json"
MCP_CMD="bash"
MCP_ARGS="[\"$SKILL_DST/scripts/mcp-server.sh\"]"
MCP_ENV=$(jq -nc --arg project "$TARGET" '{KG_PROJECT_DIR:$project}')
if [ -f "$MCP_JSON" ]; then
  if ! jq -e '.mcpServers["knowledge-graph"]' "$MCP_JSON" >/dev/null 2>&1; then
    jq --arg cmd "$MCP_CMD" --argjson args "$MCP_ARGS" --argjson env "$MCP_ENV" \
      '.mcpServers["knowledge-graph"] = {"type": "stdio", "command": $cmd, "args": $args, "env": $env}' \
      "$MCP_JSON" > "$MCP_JSON.tmp" && mv "$MCP_JSON.tmp" "$MCP_JSON"
    info "已在 .mcp.json 中注册 knowledge-graph MCP server"
  else
    jq --arg project "$TARGET" \
      '.mcpServers["knowledge-graph"].env = ((.mcpServers["knowledge-graph"].env // {}) + {KG_PROJECT_DIR: $project}) | del(.mcpServers["knowledge-graph"].env.KG_PRIMARY_NODE_FILE)' \
      "$MCP_JSON" > "$MCP_JSON.tmp" && mv "$MCP_JSON.tmp" "$MCP_JSON"
    info "已更新 .mcp.json 中的 KG_PROJECT_DIR"
  fi
else
  jq -n --arg cmd "$MCP_CMD" --argjson args "$MCP_ARGS" --argjson env "$MCP_ENV" \
    '{"mcpServers": {"knowledge-graph": {"type": "stdio", "command": $cmd, "args": $args, "env": $env}}}' > "$MCP_JSON"
  info "已创建 .mcp.json 并注册 knowledge-graph MCP server"
fi

# ── Update .gitignore ──────────────────────────────────────────────────────────
GITIGNORE="$TARGET/.gitignore"
if [ -f "$GITIGNORE" ]; then
  grep -q '^\.knowledge-graph/' "$GITIGNORE" || echo '.knowledge-graph/' >> "$GITIGNORE"
  info "已更新 .gitignore"
else
  echo '.knowledge-graph/' > "$GITIGNORE"
  info "已创建 .gitignore"
fi

echo ""
info "✅ 安装完成！"
echo ""
echo "  已安装到: $TARGET/.claude/skills/knowledge-graph/"
echo "  版本: $KG_VERSION_LINE"
echo "  安装副本元数据: $KG_VERSION_TEXT"
echo "  宿主状态元数据: $KG_VERSION_STATUS"
echo ""
echo "  下一步："
echo "  1. 重启 Claude Code session（让 hooks 生效）"
echo "  2. Codex/MCP 客户端读取 AGENTS.md，并通过 .mcp.json 连接 knowledge-graph"
echo "  3. 运行 /knowledge-graph init 初始化知识图谱"
echo "  4. 运行 ! $KG_STATUS_CMD 检查版本一致性"
echo ""
