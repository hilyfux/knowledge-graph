#!/bin/bash
# inject-subagent-context.sh - SubagentStart
# Tell sub-agents about the knowledge graph
CWD_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
if [ -f "$CWD_CLAUDE" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"项目有知识图谱网络，子目录的 CLAUDE.md 包含模块级指导，进入目录时会自动加载。\"}}"
fi
exit 0
