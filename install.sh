#!/bin/bash
# 知识图谱 - 一键安装到当前项目
# 用法: bash install.sh [目标项目路径]
#   不传参数则安装到当前目录

set -euo pipefail

TARGET="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE="$SCRIPT_DIR/.claude"

if [ ! -d "$SOURCE" ]; then
  echo "错误: 找不到 .claude 目录" >&2
  exit 1
fi

# 检查目标目录
if [ ! -d "$TARGET" ]; then
  echo "错误: 目标目录 $TARGET 不存在" >&2
  exit 1
fi

TARGET_CLAUDE="$TARGET/.claude"

# 如果目标已有 .claude，合并而不是覆盖
if [ -d "$TARGET_CLAUDE" ]; then
  echo "检测到目标项目已有 .claude/ 目录，将进行合并安装..."

  # 复制 scripts（不覆盖已有的）
  mkdir -p "$TARGET_CLAUDE/scripts"
  for f in "$SOURCE/scripts/"*.sh; do
    BASENAME=$(basename "$f")
    if [ -f "$TARGET_CLAUDE/scripts/$BASENAME" ]; then
      echo "  跳过: scripts/$BASENAME（已存在）"
    else
      cp "$f" "$TARGET_CLAUDE/scripts/$BASENAME"
      chmod +x "$TARGET_CLAUDE/scripts/$BASENAME"
      echo "  安装: scripts/$BASENAME"
    fi
  done

  # 复制 commands（不覆盖已有的）
  mkdir -p "$TARGET_CLAUDE/commands"
  for f in "$SOURCE/commands/"*.md; do
    BASENAME=$(basename "$f")
    if [ -f "$TARGET_CLAUDE/commands/$BASENAME" ]; then
      echo "  跳过: commands/$BASENAME（已存在）"
    else
      cp "$f" "$TARGET_CLAUDE/commands/$BASENAME"
      echo "  安装: commands/$BASENAME"
    fi
  done

  # 合并 settings.json（hooks 部分）
  if [ -f "$TARGET_CLAUDE/settings.json" ]; then
    echo "  注意: settings.json 已存在，需要手动合并 hooks 配置"
    echo "  知识图谱的 hooks 配置在: $SOURCE/settings.json"
  else
    cp "$SOURCE/settings.json" "$TARGET_CLAUDE/settings.json"
    echo "  安装: settings.json"
  fi

else
  # 全新安装
  echo "全新安装知识图谱到 $TARGET/.claude/ ..."
  cp -r "$SOURCE" "$TARGET_CLAUDE"
  chmod +x "$TARGET_CLAUDE/scripts/"*.sh
fi

# 创建运行时数据文件
touch "$TARGET_CLAUDE/graph-events.jsonl" 2>/dev/null || true
touch "$TARGET_CLAUDE/graph-changelog.jsonl" 2>/dev/null || true
touch "$TARGET_CLAUDE/graph-events-archive.jsonl" 2>/dev/null || true

echo ""
echo "安装完成！"
echo ""
echo "下一步："
echo "  1. cd $TARGET"
echo "  2. 启动 claude"
echo "  3. 执行 /init-knowledge-graph 完成首次全量扫描"
echo ""
echo "建议添加到 .gitignore："
echo "  .claude/graph-events.jsonl"
echo "  .claude/graph-events-archive.jsonl"
echo "  .claude/graph-changelog.jsonl"
echo "  .claude/.evolving"
