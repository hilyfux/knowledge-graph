# Knowledge Graph Network Plugin Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin that automatically creates and maintains a distributed knowledge graph network using CLAUDE.md files, hooks, and skills.

**Architecture:** Plugin uses hooks for event tracking (PostToolUse, InstructionsLoaded, PostToolUseFailure), context injection (SessionStart, SubagentStart), and self-evolution (Stop agent hook). Two skills provide init scan and diagnostics. All data stored as JSONL files in `.claude/`.

**Tech Stack:** Bash scripts, jq, Claude Code plugin system (hooks.json, SKILL.md, plugin.json, settings.json)

**Spec:** `docs/superpowers/specs/2026-03-17-knowledge-graph-network-design.md`

---

## File Map

| File | Responsibility |
|------|---------------|
| `.claude-plugin/plugin.json` | Plugin manifest |
| `hooks/hooks.json` | All hook event registrations |
| `settings.json` | Plugin permissions |
| `scripts/track-activity.sh` | Record file changes/reads to JSONL |
| `scripts/track-instructions.sh` | Record CLAUDE.md loads to JSONL |
| `scripts/track-failure.sh` | Record tool failures to JSONL |
| `scripts/inject-graph-context.sh` | SessionStart: inject graph summary + changelog report |
| `scripts/on-compact.sh` | SessionStart(compact): restore context after compaction |
| `scripts/inject-resume-context.sh` | SessionStart(resume): inject delta since last session |
| `scripts/inject-subagent-context.sh` | SubagentStart: inject graph awareness |
| `skills/init-knowledge-graph/SKILL.md` | Full-scan init skill |
| `skills/graph-status/SKILL.md` | Diagnostic status skill |

---

### Task 1: Plugin Scaffold

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `settings.json`
- Create: `hooks/hooks.json` (empty hooks object, filled in later tasks)

- [ ] **Step 1: Create plugin manifest**

```json
{
  "name": "knowledge-graph-network",
  "description": "Automated knowledge graph network that builds and maintains distributed CLAUDE.md files, tracks activity via hooks, and self-evolves to eliminate blind spots.",
  "version": "1.0.0"
}
```

Write to `.claude-plugin/plugin.json`.

- [ ] **Step 2: Create settings.json**

```json
{
  "permissions": {
    "allow": [
      "Bash(jq *)",
      "Bash(date *)",
      "Bash(wc *)",
      "Bash(tail *)",
      "Bash(cat *)",
      "Bash(mkdir *)",
      "Bash(find *)",
      "Bash(rm */.claude/.evolving)",
      "Bash(mv *)"
    ]
  }
}
```

Write to `settings.json`.

- [ ] **Step 3: Create empty hooks.json skeleton**

```json
{
  "hooks": {}
}
```

Write to `hooks/hooks.json`.

- [ ] **Step 4: Verify directory structure**

Run: `find . -type f | sort`
Expected: `.claude-plugin/plugin.json`, `hooks/hooks.json`, `settings.json`, plus docs files.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/plugin.json settings.json hooks/hooks.json
git commit -m "feat: scaffold plugin with manifest, settings, and hooks skeleton"
```

---

### Task 2: Activity Tracking Script (track-activity.sh)

**Files:**
- Create: `scripts/track-activity.sh`

- [ ] **Step 1: Write track-activity.sh**

```bash
#!/bin/bash
# track-activity.sh - Records file change/read events to JSONL
# Must complete in < 50ms. No heavy processes.
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"

# Skip sub-agent tool calls (prevents evolution engine recursion)
[ "$(echo "$INPUT" | jq -r '.agent_id // empty')" != "" ] && exit 0

# Fallback anti-loop: skip if evolution engine is running
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

Write to `scripts/track-activity.sh`.

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/track-activity.sh`

- [ ] **Step 3: Test with mock Write input**

Run: `echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test/src/auth/login.ts"}}' | CLAUDE_PROJECT_DIR=/tmp/test bash scripts/track-activity.sh && cat /tmp/test/.claude/graph-events.jsonl`

Prerequisite: `mkdir -p /tmp/test/.claude`

Expected: A JSONL line with `"e":"w","p":"src/auth/login.ts"`.

- [ ] **Step 4: Test with agent_id (should skip)**

Run: `echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/test/x.ts"},"agent_id":"agent-123"}' | CLAUDE_PROJECT_DIR=/tmp/test bash scripts/track-activity.sh && wc -l /tmp/test/.claude/graph-events.jsonl`

Expected: Same line count as before (no new line added).

- [ ] **Step 5: Commit**

```bash
git add scripts/track-activity.sh
git commit -m "feat: add activity tracking script for PostToolUse events"
```

---

### Task 3: Instructions & Failure Tracking Scripts

**Files:**
- Create: `scripts/track-instructions.sh`
- Create: `scripts/track-failure.sh`

- [ ] **Step 1: Write track-instructions.sh**

```bash
#!/bin/bash
# track-instructions.sh - Records CLAUDE.md load events
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
TS=$(date +%s)

# Support both payload formats: loaded_files array or single file_path
FILES=$(echo "$INPUT" | jq -r '(.loaded_files // [])[], (.file_path // empty)' 2>/dev/null | sort -u)
for f in $FILES; do
  [ -z "$f" ] && continue
  REL="${f#$CLAUDE_PROJECT_DIR/}"
  echo "{\"e\":\"i\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS"
done
exit 0
```

Write to `scripts/track-instructions.sh`.

- [ ] **Step 2: Write track-failure.sh**

```bash
#!/bin/bash
# track-failure.sh - Records tool failure events
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
TS=$(date +%s)
echo "{\"e\":\"f\",\"tool\":\"$TOOL\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
exit 0
```

Write to `scripts/track-failure.sh`.

- [ ] **Step 3: Make both executable**

Run: `chmod +x scripts/track-instructions.sh scripts/track-failure.sh`

- [ ] **Step 4: Test track-instructions.sh with loaded_files format**

Run: `echo '{"loaded_files":["/tmp/test/src/auth/CLAUDE.md","/tmp/test/CLAUDE.md"]}' | CLAUDE_PROJECT_DIR=/tmp/test bash scripts/track-instructions.sh && tail -2 /tmp/test/.claude/graph-events.jsonl`

Expected: Two lines with `"e":"i"`.

- [ ] **Step 5: Test track-failure.sh**

Run: `echo '{"tool_name":"Bash"}' | CLAUDE_PROJECT_DIR=/tmp/test bash scripts/track-failure.sh && tail -1 /tmp/test/.claude/graph-events.jsonl`

Expected: Line with `"e":"f","tool":"Bash"`.

- [ ] **Step 6: Commit**

```bash
git add scripts/track-instructions.sh scripts/track-failure.sh
git commit -m "feat: add instructions loaded and failure tracking scripts"
```

---

### Task 4: SessionStart Context Injection Scripts

**Files:**
- Create: `scripts/inject-graph-context.sh`
- Create: `scripts/on-compact.sh`
- Create: `scripts/inject-resume-context.sh`

- [ ] **Step 1: Write inject-graph-context.sh**

```bash
#!/bin/bash
# inject-graph-context.sh - SessionStart(startup|clear)
# Injects changelog report + hot area summary into Claude context
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

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
    # Atomic clear: move then delete to avoid concurrent read/write
    mv "$CHANGELOG" "${CHANGELOG}.reported" 2>/dev/null
    rm -f "${CHANGELOG}.reported" 2>/dev/null
  fi
fi

# Report hot areas (limit to last 500 lines to prevent timeout)
if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(tail -500 "$EVENTS" | jq -r 'select(.e=="w") | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  if [ -n "$HOT" ]; then
    CONTEXT="$CONTEXT\n[活跃区域] 近期高频变更目录：\n$HOT"
  fi
fi

if [ -n "$CONTEXT" ]; then
  ESCAPED=$(echo -e "$CONTEXT" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
fi

exit 0
```

Write to `scripts/inject-graph-context.sh`.

- [ ] **Step 2: Write on-compact.sh**

```bash
#!/bin/bash
# on-compact.sh - SessionStart(compact)
# Re-inject minimal context after conversation compaction
CONTEXT="[知识图谱] 上下文已压缩。项目知识图谱仍在工作中，子目录的 CLAUDE.md 会在你进入对应目录时自动加载。"
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$CONTEXT\"}}"
exit 0
```

Write to `scripts/on-compact.sh`.

- [ ] **Step 3: Write inject-resume-context.sh**

```bash
#!/bin/bash
# inject-resume-context.sh - SessionStart(resume)
# Report graph changes since last interaction
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
[ ! -f "$CHANGELOG" ] || [ ! -s "$CHANGELOG" ] && exit 0

UPDATES=$(tail -5 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path' 2>/dev/null)
[ -z "$UPDATES" ] && exit 0

ESCAPED=$(echo "[知识图谱] 对话恢复。自上次以来更新的节点：\n$UPDATES" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
exit 0
```

Write to `scripts/inject-resume-context.sh`.

- [ ] **Step 4: Make all executable**

Run: `chmod +x scripts/inject-graph-context.sh scripts/on-compact.sh scripts/inject-resume-context.sh`

- [ ] **Step 5: Test on-compact.sh (simplest, no deps)**

Run: `bash scripts/on-compact.sh`

Expected: JSON with `hookSpecificOutput` containing `additionalContext` about compaction.

- [ ] **Step 6: Commit**

```bash
git add scripts/inject-graph-context.sh scripts/on-compact.sh scripts/inject-resume-context.sh
git commit -m "feat: add SessionStart context injection scripts (startup, compact, resume)"
```

---

### Task 5: SubagentStart Script

**Files:**
- Create: `scripts/inject-subagent-context.sh`

- [ ] **Step 1: Write inject-subagent-context.sh**

```bash
#!/bin/bash
# inject-subagent-context.sh - SubagentStart
# Tell sub-agents about the knowledge graph
CWD_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
if [ -f "$CWD_CLAUDE" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"项目有知识图谱网络，子目录的 CLAUDE.md 包含模块级指导，进入目录时会自动加载。\"}}"
fi
exit 0
```

Write to `scripts/inject-subagent-context.sh`.

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/inject-subagent-context.sh`

- [ ] **Step 3: Commit**

```bash
git add scripts/inject-subagent-context.sh
git commit -m "feat: add SubagentStart context injection script"
```

---

### Task 6: Complete Hooks Configuration

**Files:**
- Modify: `hooks/hooks.json`

- [ ] **Step 1: Write the full hooks.json**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Read|Glob|Grep",
        "hooks": [{
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/track-activity.sh",
          "timeout": 2
        }]
      }
    ],
    "InstructionsLoaded": [
      {
        "hooks": [{
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/track-instructions.sh",
          "timeout": 2
        }]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/track-failure.sh",
          "timeout": 2
        }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|clear",
        "hooks": [{
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/inject-graph-context.sh",
          "timeout": 5
        }]
      },
      {
        "matcher": "compact",
        "hooks": [{
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/on-compact.sh",
          "timeout": 5
        }]
      },
      {
        "matcher": "resume",
        "hooks": [{
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/inject-resume-context.sh",
          "timeout": 5
        }]
      }
    ],
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/inject-subagent-context.sh",
          "timeout": 3
        }]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "agent",
          "prompt": "你是知识图谱进化引擎。\n\n第零步：创建锁文件 .claude/.evolving 防止递归。所有工作完成后删除此锁文件。\n\n第一步：读取 .claude/graph-events.jsonl。如果文件不存在或少于5行，删除锁文件后直接结束。\n\n第二步：三维盲区分析\n- 统计每个目录的：写入次数(e=w)、读取次数(e=r)、知识加载次数(e=i)、失败次数(e=f)\n- 高写入+高读取+零知识加载 = 关键盲区（优先处理）\n- 高失败 = 问题区域（CLAUDE.md 需增强约束）\n\n第三步：执行进化（每次最多处理3个文件）\n1) 为关键盲区目录生成 CLAUDE.md，结构必须是：\n   ## 禁忌\\n## 改动时\\n## 约定\n2) 检查已有 CLAUDE.md 是否因文件变更而过时，用 Edit 工具最小化更新\n3) 确保 @ 引用反映真实依赖关系\n\n第四步：记录变更\n1) 每个创建或更新的 CLAUDE.md，追加一条到 .claude/graph-changelog.jsonl：\n   {\"action\":\"created|updated\",\"path\":\"相对路径\",\"reason\":\"原因\",\"ts\":时间戳}\n2) 将已处理事件追加到 .claude/graph-events-archive.jsonl\n3) 清空 graph-events.jsonl\n4) 归档文件超过 5000 行时只保留最后 2000 行\n5) 删除锁文件 .claude/.evolving",
          "timeout": 120
        }]
      }
    ]
  }
}
```

Write to `hooks/hooks.json` (overwrite existing skeleton).

- [ ] **Step 2: Validate JSON syntax**

Run: `cat hooks/hooks.json | jq . > /dev/null && echo "Valid JSON"`

Expected: "Valid JSON"

- [ ] **Step 3: Commit**

```bash
git add hooks/hooks.json
git commit -m "feat: complete hooks configuration with all event handlers"
```

---

### Task 7: Init Knowledge Graph Skill

**Files:**
- Create: `skills/init-knowledge-graph/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

````yaml
---
name: init-knowledge-graph
description: 初始化项目知识图谱网络。扫描项目结构，在每个有意义的子目录生成 CLAUDE.md，建立全局索引和条件规则。安装插件后执行一次。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(find *), Bash(wc *), Bash(date *), Bash(cat *), Bash(mkdir *)
---

你是知识图谱初始化引擎。对当前项目执行全量扫描并建立知识网络。

## 步骤

### 1. 项目感知
- 用 Glob 扫描项目结构（`**/*`），识别所有有实质内容的目录
- 跳过：.git、node_modules、dist、build、.next、__pycache__、.venv、vendor、target、.claude
- 跳过 .gitignore 中列出的路径
- 读取项目元文件（README.md、package.json、Cargo.toml、pyproject.toml、go.mod 等）
- 识别项目类型：代码/文档/混合
- 识别模块边界：每个有 3+ 文件且有独立职责的目录视为一个模块

### 2. 生成根 CLAUDE.md
如果项目根已有 CLAUDE.md：
- 读取现有内容，在末尾追加知识图谱相关段落
- 不修改已有内容

如果没有 CLAUDE.md：
```markdown
# {从 README 或 package.json 提取的项目名}

@README.md

## 全局约定
- {从项目配置和代码风格推断的约定}

## 禁忌
- {从项目结构推断的禁忌，如不要手动修改生成文件}
```

### 3. 生成子模块 CLAUDE.md
对每个识别出的模块目录，生成 CLAUDE.md：

```markdown
# {模块名}

## 禁忌
- {分析代码/文件后提取的禁忌}

## 改动时
- {触发条件} → 看 @{关联模块的 CLAUDE.md 相对路径}

## 约定
- {本模块特有的工作方式}
```

约束：
- 每个 CLAUDE.md 控制在 30 行以内
- @ 引用使用相对路径
- 只建立确实存在依赖关系的 @ 引用（通过 import/require/use 语句或目录结构推断）
- 已有 CLAUDE.md 的目录不覆盖，只追加缺失段落

### 4. 生成 .claude/rules/
识别跨模块的共性规则，生成带 paths: frontmatter 的条件规则文件：

```markdown
---
paths:
  - "{匹配路径 glob}"
---
- {规则内容}
```

常见 rules 示例：
- 代码风格规则（匹配源代码路径）
- 测试规则（匹配测试文件路径）
- 文档规则（匹配文档路径）

### 5. 初始化数据文件
```bash
mkdir -p .claude
touch .claude/graph-events.jsonl
touch .claude/graph-changelog.jsonl
touch .claude/graph-events-archive.jsonl
```

将初始化事件写入 changelog：
```jsonl
{"action":"initialized","path":".","reason":"知识图谱首次初始化","ts":{当前时间戳}}
```

### 6. 输出初始化报告
完成后输出摘要：
- 识别了 X 个模块
- 创建了 Y 个 CLAUDE.md（列出路径）
- 建立了 Z 条 @ 关联
- 生成了 W 条 rules
- 跳过了 N 个已有 CLAUDE.md 的目录

提醒用户：
- 知识图谱将在后续对话中自动进化
- 每次对话结束时会自动检测盲区并补充
- 建议将 CLAUDE.md 和 .claude/rules/ 提交到 Git
- 建议在 .gitignore 中添加运行时数据文件
````

Write to `skills/init-knowledge-graph/SKILL.md`.

- [ ] **Step 2: Verify file exists and frontmatter is valid**

Run: `head -5 skills/init-knowledge-graph/SKILL.md`

Expected: YAML frontmatter with `name: init-knowledge-graph`.

- [ ] **Step 3: Commit**

```bash
git add skills/init-knowledge-graph/SKILL.md
git commit -m "feat: add /init-knowledge-graph skill for first-time graph setup"
```

---

### Task 8: Graph Status Diagnostic Skill

**Files:**
- Create: `skills/graph-status/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

```yaml
---
name: graph-status
description: 查看知识图谱网络的当前状态：覆盖率、热力图、盲区、最近更新。
allowed-tools: Read, Glob, Grep, Bash(wc *), Bash(cat *), Bash(find *), Bash(tail *)
---

分析当前项目的知识图谱状态并输出报告。

## 步骤

1. 用 Glob 统计所有 CLAUDE.md 文件数量和位置（`**/CLAUDE.md`）
2. 用 Glob 统计所有 `.claude/rules/*.md` 文件数量
3. 用 Glob 统计有 3+ 文件的目录，排除 .git/node_modules/dist/build/.claude，与已有 CLAUDE.md 对比找出盲区
4. 读取 `.claude/graph-events.jsonl`（最近 500 行），统计各目录的写入/读取/搜索/加载/失败次数
5. 读取 `.claude/graph-changelog.jsonl`，列出最近 10 条更新记录
6. 计算覆盖率 = 有 CLAUDE.md 的模块目录数 / 总模块目录数

## 输出格式

```
## 知识图谱状态报告

### 覆盖率
X/Y 个模块已覆盖 (Z%)

### 知识节点
- path/to/CLAUDE.md
- ...

### 条件规则
- .claude/rules/xxx.md (paths: ...)
- ...

### 盲区（无 CLAUDE.md 的活跃目录）
- path/to/uncovered/dir/ (写入: N, 读取: M)
- ...

### 热力图 Top 5
| 目录 | 写入 | 读取 | 加载 | 失败 |
|------|------|------|------|------|
| ... | ... | ... | ... | ... |

### 最近进化记录
- [时间] action: path (reason)
- ...
```
```

Write to `skills/graph-status/SKILL.md`.

- [ ] **Step 2: Verify frontmatter**

Run: `head -5 skills/graph-status/SKILL.md`

Expected: YAML frontmatter with `name: graph-status`.

- [ ] **Step 3: Commit**

```bash
git add skills/graph-status/SKILL.md
git commit -m "feat: add /graph-status diagnostic skill"
```

---

### Task 9: Final Validation & Integration Test

**Files:**
- No new files

- [ ] **Step 1: Verify complete plugin structure**

Run: `find . -not -path './.git/*' -not -path './docs/*' -type f | sort`

Expected:
```
./.claude-plugin/plugin.json
./hooks/hooks.json
./scripts/inject-graph-context.sh
./scripts/inject-resume-context.sh
./scripts/inject-subagent-context.sh
./scripts/on-compact.sh
./scripts/track-activity.sh
./scripts/track-failure.sh
./scripts/track-instructions.sh
./settings.json
./skills/graph-status/SKILL.md
./skills/init-knowledge-graph/SKILL.md
```

- [ ] **Step 2: Verify all scripts are executable**

Run: `ls -la scripts/*.sh | awk '{print $1, $NF}'`

Expected: All scripts show `-rwxr-xr-x`.

- [ ] **Step 3: Validate hooks.json references match actual scripts**

Run: `grep -oP 'scripts/[^"]+' hooks/hooks.json | sort -u`

Expected: All 7 script names, each matching an existing file in `scripts/`.

- [ ] **Step 4: Validate plugin.json is valid**

Run: `cat .claude-plugin/plugin.json | jq .`

Expected: Valid JSON with name, description, version.

- [ ] **Step 5: Run end-to-end smoke test**

```bash
# Setup temp project
rm -rf /tmp/kg-test && mkdir -p /tmp/kg-test/.claude
# Test tracking
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/kg-test/src/main.ts"}}' | CLAUDE_PROJECT_DIR=/tmp/kg-test bash scripts/track-activity.sh
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/kg-test/src/main.ts"}}' | CLAUDE_PROJECT_DIR=/tmp/kg-test bash scripts/track-activity.sh
echo '{"tool_name":"Bash"}' | CLAUDE_PROJECT_DIR=/tmp/kg-test bash scripts/track-failure.sh
echo '{"loaded_files":["/tmp/kg-test/CLAUDE.md"]}' | CLAUDE_PROJECT_DIR=/tmp/kg-test bash scripts/track-instructions.sh
# Verify events
cat /tmp/kg-test/.claude/graph-events.jsonl
```

Expected: 4 JSONL lines with events `w`, `r`, `f`, `i`.

- [ ] **Step 6: Test SessionStart with changelog**

```bash
echo '{"action":"created","path":"src/auth/CLAUDE.md","reason":"盲区检测","ts":1742212800}' > /tmp/kg-test/.claude/graph-changelog.jsonl
CLAUDE_PROJECT_DIR=/tmp/kg-test bash scripts/inject-graph-context.sh
```

Expected: JSON output with `hookSpecificOutput` containing the changelog report.

- [ ] **Step 7: Cleanup and final commit**

```bash
rm -rf /tmp/kg-test
git add -A
git status
```

If there are any uncommitted changes, commit them:
```bash
git commit -m "chore: final validation pass"
```

---

### Task 10: Documentation Commit

**Files:**
- No new code files; commit existing docs and plan

- [ ] **Step 1: Commit plan document**

```bash
git add docs/superpowers/plans/2026-03-17-knowledge-graph-network.md
git commit -m "docs: add implementation plan for knowledge graph network plugin"
```

- [ ] **Step 2: Verify git log**

Run: `git log --oneline`

Expected: Sequential commits from Task 1 through Task 10.
