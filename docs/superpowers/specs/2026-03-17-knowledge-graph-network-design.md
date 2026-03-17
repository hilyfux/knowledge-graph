# 知识图谱网络插件设计文档

## 概述

一个 Claude Code 项目级插件，安装后通过 hooks 和 skills 自动为项目搭建分布式知识图谱网络。知识图谱以 CLAUDE.md 文件网络为载体，利用 Claude Code 原生的层级加载、`@` 引用、条件规则等机制，形成类神经网络的项目认知系统，帮助 Claude 快速精准定位上下文、解决问题。

## 目标

- 团队内部使用，通过 `.claude/` 目录提交到仓库，零安装成本
- 适用于任何项目类型（代码、文档、设计等）
- 全自动运行，无需人工维护
- 自我进化，识别并修复知识盲区

## 前置依赖

### 环境变量（Claude Code 原生提供）

| 变量 | 说明 | 提供时机 |
|------|------|---------|
| `$CLAUDE_PLUGIN_ROOT` | 插件安装目录的绝对路径 | 所有 hook |
| `$CLAUDE_PROJECT_DIR` | 项目根目录的绝对路径 | 所有 hook |
| `$CLAUDE_ENV_FILE` | 持久化环境变量的文件路径 | 仅 SessionStart |

所有脚本必须在首行加环境变量守卫：
```bash
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
```

### Hook 事件 Matcher 值（Claude Code 官方定义）

| 事件 | Matcher 值 | 说明 |
|------|-----------|------|
| SessionStart | `startup` | 新会话 |
| SessionStart | `resume` | `--resume`/`--continue`/`/resume` |
| SessionStart | `clear` | `/clear` |
| SessionStart | `compact` | 自动或手动压缩 |
| PostToolUse | 工具名正则 | `Write\|Edit` 等 |
| Stop | `*` | 通配所有 |

### InstructionsLoaded 事件 payload

根据官方文档，InstructionsLoaded 的 input 包含 `loaded_files` 数组（文件路径列表）和 `file_path`（单文件路径）+ `load_reason`。脚本同时兼容两种格式。

## 架构：方案 B（Hooks + Skills 引擎）

hooks 作为触发器，skill 作为首次执行引擎，agent hook 作为进化引擎。

### 三层结构

```
项目/
├── CLAUDE.md                          ← 根指令（立即加载，极短）
├── .claude/
│   ├── rules/
│   │   ├── code-style.md              ← paths: src/**  代码风格规则
│   │   ├── doc-conventions.md         ← paths: docs/**  文档规范
│   │   └── test-policy.md             ← paths: **/*.test.*  测试策略
│   ├── graph-events.jsonl             ← 活动事件流
│   ├── graph-changelog.jsonl          ← 进化变更记录
│   └── graph-events-archive.jsonl     ← 已归档事件
├── src/
│   ├── auth/
│   │   └── CLAUDE.md                  ← 懒加载：auth 模块指令
│   └── api/
│       └── CLAUDE.md                  ← 懒加载：api 模块指令
└── docs/
    └── CLAUDE.md                      ← 懒加载：文档区指令
```

**三层分工**：
- **根 CLAUDE.md** = 全局指令（每次都加载，必须极短）
- **`.claude/rules/`** = 条件规则（按路径匹配，跨模块共性）
- **子目录 CLAUDE.md** = 模块指令（懒加载，进入时才激活）

### 图谱连接机制

- **纵向连接**：目录层级天然形成树结构
- **横向连接**：`@` 引用语法，内嵌在指令的触发条件中
- **条件连接**：`.claude/rules/` 的 `paths:` frontmatter

不需要单独的索引文件。`@` 引用即图谱的边，目录层级即图谱的树。

---

## CLAUDE.md 内容规范

### 设计原则

1. **指令不是文档** — 只写代码里读不到的东西（决策原因、禁忌、团队约定）
2. **`@` 引用即图谱边** — 关联不是静态列表，是触发条件
3. **极致压缩** — 短指令比长句子好，每个字都消耗 token
4. **行级粒度** — 每条指令独占一行，Git 冲突最小化
5. **三个核心意图** — 禁忌/改动时/约定，适配一切项目类型
6. **固定锚点** — 固定三个语义段落，进化引擎可精确更新

### 根 CLAUDE.md 模板

```markdown
# {项目名}

@README.md

## 全局约定
- {项目级约定1}
- {项目级约定2}

## 禁忌
- {全局禁忌1}
- {全局禁忌2}
```

### 子模块 CLAUDE.md 模板

```markdown
# {模块名}

## 禁忌
- {不要做的事}

## 改动时
- {触发条件} → 看 @{关联模块路径}
- {触发条件} → 同步更新 @{关联文件}

## 约定
- {本模块特有的工作方式}
```

### `.claude/rules/` 条件规则模板

```markdown
---
paths:
  - "{匹配路径}"
---
- {当操作匹配路径的文件时应遵守的规则}
```

---

## Hooks 设计

### 设计原则

| 原则 | 说明 |
|------|------|
| 类型最轻 | command 记录、prompt 判断、agent 行动 — 永远用最轻的够用类型 |
| 速度红线 | PostToolUse < 50ms，用 jq 一行追加 JSONL |
| 防循环 | stop_hook_active + agent_id 过滤双重保险 |
| 数据格式 | JSONL 并发安全、追加友好 |
| 条件执行 | 事件不足 5 条不进化，避免空转 |
| 渐进限制 | 每次进化最多改 3 个文件 |

### 完整 hooks 配置

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

### 各 Hook 详解

#### PostToolUse — 极速活动记录

```bash
#!/bin/bash
# track-activity.sh - 必须 < 50ms
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"

# 跳过子 agent 的工具调用（防进化引擎递归）
[ "$(echo "$INPUT" | jq -r '.agent_id // empty')" != "" ] && exit 0

# 备用防循环：进化引擎运行时跳过
[ -f "$CLAUDE_PROJECT_DIR/.claude/.evolving" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
TS=$(date +%s)

case "$TOOL" in
  Write|Edit)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    # 转为相对路径
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

#### InstructionsLoaded — 知识节点加载追踪

```bash
#!/bin/bash
# track-instructions.sh
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
TS=$(date +%s)

# 兼容两种 payload 格式：loaded_files 数组或单个 file_path
FILES=$(echo "$INPUT" | jq -r '(.loaded_files // [])[], (.file_path // empty)' 2>/dev/null | sort -u)
for f in $FILES; do
  [ -z "$f" ] && continue
  REL="${f#$CLAUDE_PROJECT_DIR/}"
  echo "{\"e\":\"i\",\"p\":\"$REL\",\"t\":$TS}" >> "$EVENTS"
done
exit 0
```

#### PostToolUseFailure — 失败模式追踪

```bash
#!/bin/bash
# track-failure.sh
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
TS=$(date +%s)
echo "{\"e\":\"f\",\"tool\":\"$TOOL\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
exit 0
```

#### SessionStart(startup|clear) — 图谱摘要 + 更新报告注入

```bash
#!/bin/bash
# inject-graph-context.sh
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0

CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
CONTEXT=""

# 报告上次进化更新
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  UPDATES=$(tail -10 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path + " (" + .reason + ")"' 2>/dev/null)
  if [ -n "$UPDATES" ]; then
    CONTEXT="[知识图谱更新报告] 上次会话后自动更新了以下知识节点：\n$UPDATES"
    # 原子化清空：移动后删除，避免并发读写冲突
    mv "$CHANGELOG" "${CHANGELOG}.reported" 2>/dev/null
    rm -f "${CHANGELOG}.reported" 2>/dev/null
  fi
fi

# 报告热区摘要（限制读取最近 500 行，防止大文件超时）
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

#### SessionStart(compact) — 压缩恢复

```bash
#!/bin/bash
# on-compact.sh
CONTEXT="[知识图谱] 上下文已压缩。项目知识图谱仍在工作中，子目录的 CLAUDE.md 会在你进入对应目录时自动加载。"
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$CONTEXT\"}}"
exit 0
```

#### SessionStart(resume) — 恢复上下文

```bash
#!/bin/bash
# inject-resume-context.sh
CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
[ ! -f "$CHANGELOG" ] || [ ! -s "$CHANGELOG" ] && exit 0

UPDATES=$(tail -5 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path' 2>/dev/null)
[ -z "$UPDATES" ] && exit 0

ESCAPED=$(echo "[知识图谱] 对话恢复。自上次以来更新的节点：\n$UPDATES" | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/"/\\"/g')
echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$ESCAPED\"}}"
exit 0
```

#### SubagentStart — 子 agent 上下文注入

```bash
#!/bin/bash
# inject-subagent-context.sh
CWD_CLAUDE="$CLAUDE_PROJECT_DIR/CLAUDE.md"
if [ -f "$CWD_CLAUDE" ]; then
  echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SubagentStart\",\"additionalContext\":\"项目有知识图谱网络，子目录的 CLAUDE.md 包含模块级指导，进入目录时会自动加载。\"}}"
fi
exit 0
```

#### Stop — 进化引擎

使用 `type: "agent"`，原生获得工具访问和会话上下文。

防循环机制（三重保险）：
1. agent hook 的 prompt 内嵌条件检查（事件不足 5 条则退出）
2. agent 的工具调用被 PostToolUse 的 `agent_id` 字段过滤跳过
3. 备用锁文件 `.claude/.evolving`：进化引擎创建，完成后删除；PostToolUse 检测到锁文件则跳过记录

### 三维盲区检测模型

```
维度1: 变更频率（event.e == "w" 计数）
维度2: 访问频率（event.e == "r" 计数）
维度3: 知识加载频率（event.e == "i" 计数）

交叉分析：
- 高变更 + 高访问 + 低知识加载 = 关键盲区（急需 CLAUDE.md）
- 高变更 + 低访问 + 低知识加载 = 孤岛（需关注）
- 低变更 + 高访问 + 高知识加载 = 稳定核心（健康）
- 高失败 + 任意              = 问题区域（CLAUDE.md 需增强约束）
```

### JSONL 事件格式

```jsonl
{"e":"w","p":"src/auth/login.ts","t":1742212800}
{"e":"r","p":"src/api/routes.ts","t":1742212801}
{"e":"i","p":"src/auth/CLAUDE.md","t":1742212802}
{"e":"f","tool":"Bash","t":1742212803}
{"e":"s","t":1742212804}
```

| 字段 | 含义 |
|------|------|
| e | 事件类型：w=写, r=读, s=搜索, i=知识加载, f=失败 |
| p | 文件路径（搜索事件无路径） |
| t | Unix 时间戳 |
| tool | 失败的工具名（仅失败事件） |

---

## `/init-knowledge-graph` Skill

首次全量扫描建图的 skill，用户安装插件后手动执行一次。

### SKILL.md 完整内容

```yaml
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
```

### 约束

- 已有的 CLAUDE.md 不覆盖，只追加
- .gitignore 列出的目录跳过
- node_modules、.git、dist、build 等构建产物跳过
- `@` 引用只建立确实存在依赖的关联
- 每个 CLAUDE.md 控制在 30 行以内

---

## `/graph-status` 诊断 Skill

查看知识图谱当前状态的诊断工具。

```yaml
---
name: graph-status
description: 查看知识图谱网络的当前状态：覆盖率、热力图、盲区、最近更新。
allowed-tools: Read, Glob, Grep, Bash(wc *), Bash(cat *), Bash(find *)
---

分析当前项目的知识图谱状态并输出报告。

## 步骤

1. 统计所有 CLAUDE.md 文件数量和位置
2. 统计所有 .claude/rules/*.md 文件数量
3. 统计有实质内容但无 CLAUDE.md 的目录（盲区）
4. 读取 .claude/graph-events.jsonl，统计近期活动热力图
5. 读取 .claude/graph-changelog.jsonl，列出最近更新
6. 计算覆盖率 = 有CLAUDE.md的模块目录 / 总模块目录

输出格式：
- 覆盖率：X/Y (Z%)
- 知识节点：列出所有 CLAUDE.md 路径
- 条件规则：列出所有 rules 文件
- 盲区：列出无 CLAUDE.md 的活跃目录
- 热力图：最近高频变更/访问的 Top 5 目录
- 最近更新：最近 10 条进化记录
```

---

## 数据维护

### 归档轮转策略

`graph-events-archive.jsonl` 是追加式文件，需要定期轮转防止无限增长。

轮转由 Stop hook 的进化引擎执行：
- 每次进化结束时检查归档文件行数
- 超过 5000 行时只保留最后 2000 行
- 使用 `tail -2000` + 临时文件 + `mv` 实现原子轮转

### 并发安全

- JSONL 追加（`>>`）在 POSIX 系统上对小写入是原子的
- changelog 清空使用 `mv` + `rm` 而非 `>` 截断，避免读写冲突
- 进化引擎使用锁文件 `.claude/.evolving` 防止并发执行

---

## 团队协作

### 冲突最小化策略

- CLAUDE.md 采用行级粒度，每条指令独占一行
- 分小节用标题锚定，不同人修改不同段落几乎不冲突
- `.claude/graph-events.jsonl` 是 JSONL 追加式，不冲突
- `.claude/graph-changelog.jsonl` 同上
- 真冲突走 Git 合并流程

### .gitignore 建议

```
# 知识图谱运行时数据（不提交）
.claude/graph-events.jsonl
.claude/graph-events-archive.jsonl

# 知识图谱变更日志（不提交）
.claude/graph-changelog.jsonl
```

知识节点（CLAUDE.md 和 rules/）提交到仓库，共享团队知识。运行时数据各自本地维护。

---

## 自我进化机制

### 触发条件

每次对话结束（Stop hook），且 graph-events.jsonl 中有 >= 5 条新事件。

### 进化行为

1. 覆盖率检测 — 有文件但没 CLAUDE.md 的活跃目录
2. 热力图分析 — 高频变更/访问但无知识覆盖的区域
3. 质量评估 — 文件已变更但 CLAUDE.md 未更新的过时节点
4. 关联完整性 — 新增依赖是否反映在 `@` 引用中

### 限制

- 每次最多创建/更新 3 个 CLAUDE.md
- 所有变更记录到 changelog
- 下次 SessionStart 向用户报告更新内容

---

## 通知流程

```
对话结束 → Stop agent hook 执行进化
         → 创建/更新 CLAUDE.md
         → 写入 graph-changelog.jsonl

下次对话 → SessionStart 读取 changelog
         → additionalContext 注入更新报告
         → Claude 开场告知用户更新了哪些知识节点
         → 清空已报告的 changelog
```

---

## 插件目录结构

```
knowledge-graph-network/
├── .claude-plugin/
│   └── plugin.json
├── hooks/
│   └── hooks.json
├── skills/
│   └── init-knowledge-graph/
│       └── SKILL.md
├── scripts/
│   ├── track-activity.sh
│   ├── track-instructions.sh
│   ├── track-failure.sh
│   ├── inject-graph-context.sh
│   ├── on-compact.sh
│   ├── inject-resume-context.sh
│   └── inject-subagent-context.sh
└── settings.json
```
