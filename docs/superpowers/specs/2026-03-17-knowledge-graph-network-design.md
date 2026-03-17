# 知识图谱网络插件设计文档

## 概述

一个 Claude Code 项目级插件，安装后通过 hooks 和 skills 自动为项目搭建分布式知识图谱网络。知识图谱以 CLAUDE.md 文件网络为载体，利用 Claude Code 原生的层级加载、`@` 引用、条件规则等机制，形成类神经网络的项目认知系统，帮助 Claude 快速精准定位上下文、解决问题。

## 目标

- 团队内部使用，通过 `.claude/` 目录提交到仓库，零安装成本
- 适用于任何项目类型（代码、文档、设计等）
- 全自动运行，无需人工维护
- 自我进化，识别并修复知识盲区

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
          "prompt": "你是知识图谱进化引擎。\n\n第一步：读取 .claude/graph-events.jsonl。如果文件不存在或少于5行，直接结束不做任何事。\n\n第二步：分析事件，执行进化：\n1) 找出高频变更但无 CLAUDE.md 的目录，生成 CLAUDE.md（禁忌/改动时/约定三段式）\n2) 检查已有 CLAUDE.md 是否因文件变更而过时，更新之\n3) 确保 @ 引用反映真实依赖关系\n每次最多处理3个文件。\n\n第三步：记录变更\n1) 每个创建或更新的 CLAUDE.md，追加一条到 .claude/graph-changelog.jsonl：\n   {\"action\":\"created|updated\",\"path\":\"相对路径\",\"reason\":\"原因\",\"ts\":时间戳}\n2) 将已处理事件移入 .claude/graph-events-archive.jsonl\n3) 清空 graph-events.jsonl",
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
INPUT=$(cat)

# 跳过子 agent 的工具调用
[ "$(echo "$INPUT" | jq -r '.agent_id // empty')" != "" ] && exit 0

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
TS=$(date +%s)

case "$TOOL" in
  Write|Edit)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"w\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
    ;;
  Read)
    PATH_VAL=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    [ -n "$PATH_VAL" ] && echo "{\"e\":\"r\",\"p\":\"$PATH_VAL\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
    ;;
  Glob|Grep)
    echo "{\"e\":\"s\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
    ;;
esac

exit 0
```

#### InstructionsLoaded — 知识节点加载追踪

```bash
#!/bin/bash
# track-instructions.sh
INPUT=$(cat)
FILES=$(echo "$INPUT" | jq -r '.loaded_files[]' 2>/dev/null)
TS=$(date +%s)
for f in $FILES; do
  echo "{\"e\":\"i\",\"p\":\"$f\",\"t\":$TS}" >> "$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
done
exit 0
```

#### PostToolUseFailure — 失败模式追踪

```bash
#!/bin/bash
# track-failure.sh
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
CHANGELOG="$CLAUDE_PROJECT_DIR/.claude/graph-changelog.jsonl"
EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
CONTEXT=""

# 报告上次进化更新
if [ -f "$CHANGELOG" ] && [ -s "$CHANGELOG" ]; then
  UPDATES=$(tail -10 "$CHANGELOG" | jq -r '"- " + .action + ": " + .path + " (" + .reason + ")"' 2>/dev/null)
  if [ -n "$UPDATES" ]; then
    CONTEXT="[知识图谱更新报告] 上次会话后自动更新了以下知识节点：\n$UPDATES"
    # 清空已报告的 changelog
    > "$CHANGELOG"
  fi
fi

# 报告热区摘要
if [ -f "$EVENTS" ] && [ -s "$EVENTS" ]; then
  HOT=$(cat "$EVENTS" | jq -r 'select(.e=="w") | .p' 2>/dev/null | xargs -I{} dirname {} 2>/dev/null | sort | uniq -c | sort -rn | head -3)
  if [ -n "$HOT" ]; then
    CONTEXT="$CONTEXT\n[活跃区域] 近期高频变更目录：\n$HOT"
  fi
fi

if [ -n "$CONTEXT" ]; then
  # 转义换行符为 \\n
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

防循环机制：
- agent hook 的 prompt 内嵌条件检查（事件不足 5 条则退出）
- agent 的工具调用被 PostToolUse 的 agent_id 过滤跳过

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

### 执行步骤

1. **项目感知** — 扫描项目结构，识别模块边界和项目类型
2. **生成根 CLAUDE.md** — 已有则追加，没有则新建
3. **生成子模块 CLAUDE.md** — 三段式模板，每个控制在 30 行以内
4. **生成 .claude/rules/** — 跨模块共性规则，带 paths: frontmatter
5. **初始化数据文件** — 创建 graph-events.jsonl、graph-changelog.jsonl、graph-events-archive.jsonl
6. **输出初始化报告** — 创建了多少节点、多少条关联、多少条规则

### 约束

- 已有的 CLAUDE.md 不覆盖，只追加
- .gitignore 列出的目录跳过
- node_modules、.git、dist、build 等构建产物跳过
- `@` 引用只建立确实存在依赖的关联

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
