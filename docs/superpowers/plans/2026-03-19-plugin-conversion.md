# Knowledge Graph Plugin Conversion Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert knowledge-graph from a copy-based install to a standard Claude Code plugin with three-space isolation and misoperation protection.

**Architecture:** Plugin code lives under plugin root (read-only at runtime). All project data writes to `${CLAUDE_PROJECT_DIR}/.claude/`. Every entry point (script, skill, agent prompt) validates workspace before executing. Stop hook uses command+agent chaining where the command guards and the agent evolves.

**Tech Stack:** Bash scripts, Claude Code plugin system (plugin.json, hooks.json, SKILL.md)

**Spec:** `docs/superpowers/specs/2026-03-19-plugin-conversion-design.md`

---

### Task 1: Create plugin scaffold — manifest and directory structure

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `hooks/hooks.json` (empty placeholder for now)
- Create: `scripts/` directory

- [ ] **Step 1: Create `.claude-plugin/plugin.json`**

```json
{
  "name": "knowledge-graph",
  "version": "1.0.0",
  "description": "自动化知识图谱：追踪活动、检测盲区、生成和进化分布式 CLAUDE.md",
  "author": {
    "name": "hilyfux"
  },
  "repository": "https://github.com/hilyfux/knowledge-graph",
  "license": "MIT",
  "keywords": ["knowledge-graph", "claude-md", "auto-evolution"]
}
```

- [ ] **Step 2: Create empty directory structure**

```bash
mkdir -p scripts skills/init-knowledge-graph skills/graph-status
```

- [ ] **Step 3: Commit scaffold**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add plugin manifest and directory scaffold"
```

---

### Task 2: Create guard.sh — the shared workspace guard

**Files:**
- Create: `scripts/guard.sh`

- [ ] **Step 1: Write guard.sh**

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/guard.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/guard.sh
git commit -m "feat: add shared workspace guard script"
```

---

### Task 3: Migrate tracking scripts (track-activity, track-instructions, track-failure)

**Files:**
- Create: `scripts/track-activity.sh` (from `.claude/hooks/track-activity.sh`)
- Create: `scripts/track-instructions.sh` (from `.claude/hooks/track-instructions.sh`)
- Create: `scripts/track-failure.sh` (from `.claude/hooks/track-failure.sh`)

- [ ] **Step 1: Write `scripts/track-activity.sh`**

Take the existing `.claude/hooks/track-activity.sh`, replace the old guard lines (`[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0`) with:

```bash
#!/bin/bash
# track-activity.sh — PostToolUse: records file change/read events to JSONL
# Must complete in < 50ms. No heavy processes.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"

# Skip if evolution engine is running
[ -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
TS=$(date +%s)

case "$TOOL" in
  Write|Edit)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"w\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Read)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    PATH_VAL="${PATH_VAL#$CLAUDE_PROJECT_DIR/}"
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"r\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$EVENTS"
    ;;
  Glob|Grep)
    echo "{\"e\":\"s\",\"t\":$TS}" >> "$EVENTS"
    ;;
esac

exit 0
```

- [ ] **Step 2: Write `scripts/track-instructions.sh`**

```bash
#!/bin/bash
# track-instructions.sh — InstructionsLoaded: records CLAUDE.md load events
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
TS=$(date +%s)

FILES=$(echo "$INPUT" | jq -r '(.loaded_files // [])[], (.file_path // empty)' 2>/dev/null | sort -u)
for f in $FILES; do
  [ -z "$f" ] && continue
  REL="${f#$CLAUDE_PROJECT_DIR/}"
  echo "{\"e\":\"i\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS"
done
exit 0
```

- [ ] **Step 3: Write `scripts/track-failure.sh`**

```bash
#!/bin/bash
# track-failure.sh — PostToolUseFailure: records tool failure events
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
TS=$(date +%s)
echo "{\"e\":\"f\",\"tool\":\"$TOOL\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
exit 0
```

- [ ] **Step 4: Make all executable**

```bash
chmod +x scripts/track-activity.sh scripts/track-instructions.sh scripts/track-failure.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/track-activity.sh scripts/track-instructions.sh scripts/track-failure.sh
git commit -m "feat: migrate tracking scripts with workspace guard"
```

---

### Task 4: Migrate context injection scripts (inject-graph-context, inject-resume-context, on-compact, inject-subagent-context)

**Files:**
- Create: `scripts/inject-graph-context.sh` (from `.claude/hooks/inject-graph-context.sh`)
- Create: `scripts/inject-resume-context.sh` (from `.claude/hooks/inject-resume-context.sh`)
- Create: `scripts/on-compact.sh` (from `.claude/hooks/on-compact.sh`)
- Create: `scripts/inject-subagent-context.sh` (from `.claude/hooks/inject-subagent-context.sh`)

- [ ] **Step 1: Write `scripts/inject-graph-context.sh`**

```bash
#!/bin/bash
# inject-graph-context.sh — SessionStart(startup|clear)
# Injects changelog report + hot area summary into Claude context
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
CONTEXT=""

# Clean up stale lockfile from failed evolution
rm -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" 2>/dev/null

# Report evolution updates since last session
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  UPDATES=$(tail -10 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path + " (" + .reason + ")"' 2>/dev/null)
  if [ -n "$UPDATES" ]; then
    CONTEXT="[知识图谱更新报告] 上次会话后自动更新了以下知识节点：\n$UPDATES"
    mv "$CHANGELOG" "${CHANGELOG}.reported" 2>/dev/null
    rm -f "${CHANGELOG}.reported" 2>/dev/null
  fi
fi

# Report hot areas
if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e=="w") | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  if [ -n "$HOT" ]; then
    CONTEXT="$CONTEXT\n[活跃区域] 近期高频变更目录：\n$HOT"
  fi
fi

if [ -n "$CONTEXT" ]; then
  ESCAPED=$(printf '%s' "$(echo -e "$CONTEXT")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
fi

exit 0
```

- [ ] **Step 2: Write `scripts/inject-resume-context.sh`**

```bash
#!/bin/bash
# inject-resume-context.sh — SessionStart(resume)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
[ ! -f "$CHANGELOG" ] || [ ! -s "$CHANGELOG" ] && exit 0

UPDATES=$(tail -5 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path' 2>/dev/null)
[ -z "$UPDATES" ] && exit 0

ESCAPED=$(printf '%s' "$(echo -e "[知识图谱] 对话恢复。自上次以来更新的节点：\n$UPDATES")" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read())[1:-1])")
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
exit 0
```

- [ ] **Step 3: Write `scripts/on-compact.sh`**

```bash
#!/bin/bash
# on-compact.sh — SessionStart(compact)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CONTEXT="[知识图谱] 上下文已压缩。项目知识图谱仍在工作中，子目录的 CLAUDE.md 会在你进入对应目录时自动加载。"
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$CONTEXT\"}}"
exit 0
```

- [ ] **Step 4: Write `scripts/inject-subagent-context.sh`**

```bash
#!/bin/bash
# inject-subagent-context.sh — SubagentStart
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

CWD_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
if [ -f "$CWD_CLAUDE" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"项目有知识图谱，子目录的 CLAUDE.md 包含模块级指导，进入目录时会自动加载。\"}}"
fi
exit 0
```

- [ ] **Step 5: Make all executable**

```bash
chmod +x scripts/inject-graph-context.sh scripts/inject-resume-context.sh scripts/on-compact.sh scripts/inject-subagent-context.sh
```

- [ ] **Step 6: Commit**

```bash
git add scripts/inject-graph-context.sh scripts/inject-resume-context.sh scripts/on-compact.sh scripts/inject-subagent-context.sh
git commit -m "feat: migrate context injection scripts with workspace guard"
```

---

### Task 5: Create on-stop.sh — the Stop hook guard

**Files:**
- Create: `scripts/on-stop.sh`

- [ ] **Step 1: Write `scripts/on-stop.sh`**

This script is special: `exit 1` = block agent, `exit 0` = allow agent to proceed. It does NOT source guard.sh because its exit codes have inverted semantics.

```bash
#!/bin/bash
# on-stop.sh — Stop hook guard (exit 1 = block agent, exit 0 = allow)
set -euo pipefail

# Workspace guard (fail = block evolution)
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 1
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 1
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 1

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
LOCK="$CLAUDE_PROJECT_DIR/.claude/.evolving"

# Lock file guard (evolution already running)
[ -f "$LOCK" ] && exit 1

# Event count guard (not enough to justify evolution)
[ ! -f "$EVENTS" ] && exit 1
LINE_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
[ "$LINE_COUNT" -lt 5 ] && exit 1

exit 0
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/on-stop.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/on-stop.sh
git commit -m "feat: add Stop hook guard with inverted exit codes"
```

---

### Task 6: Create hooks.json — full hook definitions

**Files:**
- Create: `hooks/hooks.json`

- [ ] **Step 1: Write `hooks/hooks.json`**

Copy the complete hooks.json from the spec (`docs/superpowers/specs/2026-03-19-plugin-conversion-design.md`, lines 136-221). This is the exact content — all paths use `${CLAUDE_PLUGIN_ROOT}/scripts/`, all timeouts and matchers are defined, and the Stop hook has both command and agent types.

- [ ] **Step 2: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: add hooks.json with all event definitions"
```

---

### Task 7: Create skills — init-knowledge-graph and graph-status

**Files:**
- Create: `skills/init-knowledge-graph/SKILL.md` (from `.claude/commands/init-knowledge-graph.md`)
- Create: `skills/graph-status/SKILL.md` (from `.claude/commands/graph-status.md`)

- [ ] **Step 1: Write `skills/init-knowledge-graph/SKILL.md`**

Take the body from `.claude/commands/init-knowledge-graph.md` and restructure:

```markdown
---
name: init-knowledge-graph
description: 初始化项目知识图谱。扫描项目结构，在每个有意义的子目录生成 CLAUDE.md，建立全局索引和条件规则。安装后执行一次。
---

你是知识图谱初始化引擎。对当前项目执行全量扫描并建立知识图谱。

## 前置检查（必须按顺序执行，任一失败则停止）

### 0. 工作空间守卫
- 检查当前工作目录：不能是用户主目录（$HOME）、不能是根目录（/）
- 如果不满足 → 告知用户「请在项目目录中执行此命令，不能在用户主目录或根目录执行」，结束
- 如果当前目录看起来不像项目（例如 ~/Desktop、~/Downloads 等常见非项目路径）→ 在下一步确认中特别提醒

### 1. 扫描前确认
- 用 Glob 快速统计项目根目录下的文件总数（排除 .git、node_modules、dist、build、.next、__pycache__、.venv、vendor、target、.claude）
- 输出摘要：「当前目录：{path}，共 {N} 个文件，{M} 个子目录」
- 明确询问用户「确认要在此目录初始化知识图谱吗？」
- 用户确认后才继续。用户拒绝则结束。

## 步骤

### 2. 项目感知
（以下内容保留原 .claude/commands/init-knowledge-graph.md 中的步骤 1 内容）
- 用 Glob 扫描项目结构（`**/*`），识别所有有实质内容的目录
- 跳过：.git、node_modules、dist、build、.next、__pycache__、.venv、vendor、target、.claude
- 跳过 .gitignore 中列出的路径
- 读取项目元文件（README.md、package.json、Cargo.toml、pyproject.toml、go.mod 等）
- 识别项目类型：代码/文档/混合
- 识别模块边界：每个有 3+ 文件且有独立职责的目录视为一个模块

### 3. 生成根 CLAUDE.md（幂等）
如果项目根已有 CLAUDE.md：
- 读取现有内容，仅追加缺失的段落（全局约定/禁忌），不覆盖已有内容
- 不修改用户自己写的内容

如果没有 CLAUDE.md：
```（保留原模板内容）```

### 4. 生成子模块 CLAUDE.md（幂等）
对每个识别出的模块目录：
- 如果已有 CLAUDE.md → 读取现有内容，仅追加缺失的段落（禁忌/改动时/约定），不覆盖
- 如果没有 → 生成新的 CLAUDE.md

（保留原模板和约束内容）

### 5. 生成 .claude/rules/（幂等）
- 检查已有规则文件，只补充新发现的规则，不覆盖已有规则

（保留原规则生成逻辑）

### 6. 初始化数据文件
```bash
mkdir -p .claude
touch .claude/graph-events.jsonl
touch .claude/graph-changelog.jsonl
touch .claude/graph-events-archive.jsonl
```

写入 changelog：
- 首次初始化：`{"action":"initialized","path":".","reason":"知识图谱首次初始化","ts":{当前时间戳}}`
- 重复初始化：`{"action":"re-initialized","path":".","reason":"知识图谱重新初始化","ts":{当前时间戳}}`

### 7. 输出初始化报告
（保留原报告格式内容）
```

Note: The full skill body is long. The key changes from the original are: (1) add sections 0 and 1 as shown above, (2) add "（幂等）" annotations to sections 3/4/5, (3) add re-initialized changelog entry in section 6. The rest of the content from `.claude/commands/init-knowledge-graph.md` is preserved verbatim.

- [ ] **Step 2: Write `skills/graph-status/SKILL.md`**

Take the body from `.claude/commands/graph-status.md` and restructure:

```markdown
---
name: graph-status
description: 查看知识图谱的当前状态：覆盖率、热力图、盲区、最近更新。
---

分析当前项目的知识图谱状态并输出报告。

## 前置检查

### 工作空间守卫
- 检查当前工作目录：不能是用户主目录（$HOME）、不能是根目录（/）
- 如果不满足 → 告知用户「请在项目目录中执行此命令」，结束

### 初始化检查
- 用 Glob 检查是否存在任何 CLAUDE.md 文件（`**/CLAUDE.md`）
- 如果一个都没有 → 告知用户「当前项目尚未初始化知识图谱，请先执行 /knowledge-graph:init-knowledge-graph」，结束

## 步骤
（保留原 .claude/commands/graph-status.md 的全部步骤和输出格式内容）
```

- [ ] **Step 3: Commit**

```bash
git add skills/init-knowledge-graph/SKILL.md skills/graph-status/SKILL.md
git commit -m "feat: add skills with workspace guard and scan confirmation"
```

---

### Task 8: Delete old files

**Files:**
- Delete: `install.sh`
- Delete: `.claude/settings.json`
- Delete: `.claude/commands/init-knowledge-graph.md`
- Delete: `.claude/commands/graph-status.md`
- Delete: `.claude/hooks/track-activity.sh`
- Delete: `.claude/hooks/track-instructions.sh`
- Delete: `.claude/hooks/track-failure.sh`
- Delete: `.claude/hooks/inject-graph-context.sh`
- Delete: `.claude/hooks/inject-resume-context.sh`
- Delete: `.claude/hooks/on-compact.sh`
- Delete: `.claude/hooks/inject-subagent-context.sh`
- Delete: `.claude/hooks/on-stop.sh`
- Delete: `.claude/graph-events.jsonl` (runtime data, should not be in repo)

- [ ] **Step 1: Remove old files via git**

```bash
git rm install.sh
git rm .claude/settings.json
git rm -r .claude/commands/
git rm -r .claude/hooks/
git rm --cached .claude/graph-events.jsonl 2>/dev/null || true
```

- [ ] **Step 2: Remove empty .claude/ directory if nothing left**

Check if `.claude/` has any remaining tracked files. If empty, remove it. If it still has other files (like the spec docs), leave it.

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: remove old install-based files, replaced by plugin structure"
```

---

### Task 9: Update README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README to reflect plugin installation**

Key changes:
- Installation section: replace `install.sh` instructions with `claude plugin install` / `--plugin-dir`
- Usage section: update skill names to namespaced format (`/knowledge-graph:init-knowledge-graph`, `/knowledge-graph:graph-status`)
- File structure section: show plugin structure instead of `.claude/` copy structure
- Remove `scripts/` references (now internal to plugin)
- Keep the "工作原理" and "CLAUDE.md 结构" sections as-is
- Update "团队使用" section: only need to commit CLAUDE.md and .claude/rules/, not plugin files

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README for plugin-based installation"
```

---

### Task 10: Verify plugin structure

- [ ] **Step 1: Verify directory structure**

```bash
# Expected structure:
# .claude-plugin/plugin.json
# hooks/hooks.json
# scripts/guard.sh
# scripts/track-activity.sh
# scripts/track-instructions.sh
# scripts/track-failure.sh
# scripts/inject-graph-context.sh
# scripts/inject-resume-context.sh
# scripts/on-compact.sh
# scripts/inject-subagent-context.sh
# scripts/on-stop.sh
# skills/init-knowledge-graph/SKILL.md
# skills/graph-status/SKILL.md
# README.md
# docs/...

find . -not -path './.git/*' -not -path './docs/*' -type f | sort
```

Verify: No files under `.claude/commands/`, `.claude/hooks/`, or `.claude/settings.json`. No `install.sh`.

- [ ] **Step 2: Verify all scripts are executable**

```bash
ls -la scripts/*.sh
```

All should show `rwxr-xr-x`.

- [ ] **Step 3: Verify hooks.json references valid script paths**

```bash
grep -o 'scripts/[a-z-]*.sh' hooks/hooks.json | sort -u
ls scripts/*.sh | sed 's|scripts/||' | sort -u
```

Both lists should match.

- [ ] **Step 4: Smoke test with --plugin-dir**

```bash
cd /tmp && mkdir test-project && cd test-project && git init
claude --plugin-dir /path/to/knowledge-graph
# In Claude: type /knowledge-graph:init-knowledge-graph
# Expected: shows file count and asks for confirmation
# Type: no (to cancel)
# Exit
rm -rf /tmp/test-project
```

- [ ] **Step 5: Final commit and push**

```bash
git push origin main
```
