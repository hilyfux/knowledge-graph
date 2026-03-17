#!/bin/bash
# on-compact.sh - SessionStart(compact)
# Re-inject minimal context after conversation compaction
CONTEXT="[知识图谱] 上下文已压缩。项目知识图谱仍在工作中，子目录的 CLAUDE.md 会在你进入对应目录时自动加载。"
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$CONTEXT\"}}"
exit 0
