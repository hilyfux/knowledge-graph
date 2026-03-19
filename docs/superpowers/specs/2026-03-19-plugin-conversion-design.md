# Knowledge Graph — 标准 Claude Code 插件转换设计

## 目标

将 knowledge-graph 从「复制 .claude/ 目录到项目」的安装模式，转换为标准 Claude Code 插件格式。用户通过 `claude plugin install` 安装，无需手动复制文件。

## 核心原则

1. **安装范围不限** — user / project / local 均可
2. **运行时必须在项目中** — 所有脚本和 skill 检测 `CLAUDE_PROJECT_DIR` 存在且不等于 `$HOME`，否则静默退出
3. **数据跟项目走** — events、changelog、CLAUDE.md 全部写入 `${CLAUDE_PROJECT_DIR}`

## 三空间隔离模型

插件运行涉及三个完全隔离的空间，任何操作不得越界：

```
┌─────────────────────────────────────────────────────┐
│ 安装空间（Install Space）                            │
│ ${CLAUDE_PLUGIN_ROOT}                                │
│ 只读。脚本代码、skill 定义、hooks.json               │
│ 位置取决于安装 scope：                                │
│   user  → ~/.claude/plugins/cache/knowledge-graph/   │
│   project → .claude/plugins/...                      │
│   local → .claude/plugins/...                        │
│ 插件代码永远不写入此空间                              │
├─────────────────────────────────────────────────────┤
│ 工作空间（Workspace）                                │
│ ${CLAUDE_PROJECT_DIR}                                │
│ 当前项目根目录。skill（init/status）在此空间执行扫描  │
│ CLAUDE.md、.claude/rules/ 生成在此空间               │
│ 守卫条件：必须存在、不等于 $HOME、不等于 /           │
├─────────────────────────────────────────────────────┤
│ 数据空间（Data Space）                               │
│ ${CLAUDE_PROJECT_DIR}/.claude/                       │
│ graph-events.jsonl、graph-changelog.jsonl 等         │
│ 属于项目，由 hooks 自动读写                          │
│ 不存在时由 guard.sh 自动 mkdir -p 创建               │
└─────────────────────────────────────────────────────┘
```

**关键约束**：
- 安装空间对运行时只读 — 脚本不得写入 `${CLAUDE_PLUGIN_ROOT}`
- 数据空间与安装空间完全分离 — 插件卸载/升级不影响项目数据
- 工作空间守卫 — 每个入口点（脚本、skill、agent prompt）都必须验证工作空间有效性

## 状态机与防误操作

### 项目生命周期状态

```
[未初始化] ──/init──→ [已初始化] ──自动进化──→ [持续运行]
     ↑                    │                        │
     │                    ├── /init（重复执行）──→ 安全跳过已有内容
     │                    │
     │                    └── 插件卸载 ──→ 数据保留在项目中
     │
     └── hooks 静默跳过（无 .claude/graph-events.jsonl）
```

### 防误操作矩阵

| 场景 | 行为 | 实现方式 |
|------|------|----------|
| 用户在 $HOME 执行 /init | skill 提示「请在项目目录中执行」，不执行任何操作 | skill 开头守卫检查 |
| 用户在 $HOME 下 hooks 触发 | 所有 hook 脚本静默 exit 0 | guard.sh |
| 用户在非项目目录执行 /init | 扫描前显示文件数量并要求确认，用户可中止 | skill 扫描前确认步骤 |
| 用户对已初始化项目再次 /init | 不覆盖已有 CLAUDE.md，只追加缺失段落 | skill 内逻辑：已有 CLAUDE.md 的目录跳过或追加 |
| 进化引擎正在运行时 hooks 触发 | 检测 .evolving 锁文件，静默跳过 | track-activity.sh 锁文件检查 |
| 进化引擎崩溃留下锁文件 | 下次 SessionStart 清理过期锁文件 | inject-graph-context.sh 启动时 rm 锁文件 |
| events 文件不存在 | 追踪脚本 append 自动创建；进化引擎跳过 | `>>` 操作符 + 行数检查 |
| events 文件为空或行数 < 5 | 进化引擎不执行 | on-stop.sh 行数守卫 |
| CLAUDE_PROJECT_DIR 未设置 | 所有入口静默退出 | guard.sh 第一行 |
| CLAUDE_PROJECT_DIR = / | 阻止在根目录操作 | guard.sh 检查 |
| 项目目录没有 .claude/ | 首个 hook 触发时自动创建 | guard.sh 的 mkdir -p |
| 插件卸载后 | 项目中 .claude/ 数据、CLAUDE.md、rules/ 全部保留 | 数据不在安装空间 |
| 插件升级后 | 脚本代码更新，项目数据不受影响 | 三空间隔离 |

## 目标目录结构

```
knowledge-graph/
├── .claude-plugin/
│   └── plugin.json              ← 插件 manifest
├── hooks/
│   └── hooks.json               ← 所有 hook 定义
├── scripts/
│   ├── guard.sh                 ← 公共守卫函数（source 引用）
│   ├── track-activity.sh        ← PostToolUse: 记录文件变更/读取
│   ├── track-instructions.sh    ← InstructionsLoaded: 记录知识加载
│   ├── track-failure.sh         ← PostToolUseFailure: 记录失败
│   ├── inject-graph-context.sh  ← SessionStart(startup|clear): 注入上下文
│   ├── inject-resume-context.sh ← SessionStart(resume): 恢复上下文
│   ├── on-compact.sh            ← SessionStart(compact): 压缩提示
│   ├── inject-subagent-context.sh ← SubagentStart: 子 agent 提示
│   └── on-stop.sh               ← Stop: 进化条件守卫
├── skills/
│   ├── init-knowledge-graph/
│   │   └── SKILL.md             ← /knowledge-graph:init-knowledge-graph
│   └── graph-status/
│       └── SKILL.md             ← /knowledge-graph:graph-status
└── README.md
```

## 删除的文件

| 文件 | 原因 |
|------|------|
| `install.sh` | 插件系统取代手动安装 |
| `.claude/settings.json` | hooks 移到 `hooks/hooks.json` |
| `.claude/commands/*.md` | 迁移到 `skills/` |
| `.claude/hooks/*.sh` | 迁移到 `scripts/` |
| `.claude/graph-events.jsonl` | 运行时数据，不属于插件仓库 |

## 组件设计

### 1. plugin.json

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

### 2. hooks.json

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Read|Glob|Grep",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/track-activity.sh\"",
          "timeout": 2
        }]
      }
    ],
    "InstructionsLoaded": [
      {
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/track-instructions.sh\"",
          "timeout": 2
        }]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/track-failure.sh\"",
          "timeout": 2
        }]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|clear",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/inject-graph-context.sh\"",
          "timeout": 5
        }]
      },
      {
        "matcher": "compact",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/on-compact.sh\"",
          "timeout": 5
        }]
      },
      {
        "matcher": "resume",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/inject-resume-context.sh\"",
          "timeout": 5
        }]
      }
    ],
    "SubagentStart": [
      {
        "matcher": "*",
        "hooks": [{
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/inject-subagent-context.sh\"",
          "timeout": 3
        }]
      }
    ],
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/on-stop.sh\"",
            "timeout": 5
          },
          {
            "type": "agent",
            "prompt": "你是知识图谱进化引擎。\n\n第零步：检查 $CLAUDE_PROJECT_DIR 是否存在且不等于 $HOME 且不等于 /，不满足则直接结束。创建锁文件 .claude/.evolving 防止递归。所有工作完成后删除此锁文件。\n\n第一步：读取 .claude/graph-events.jsonl。如果文件不存在或少于5行，删除锁文件后直接结束。\n\n第二步：三维盲区分析\n- 统计每个目录的：写入次数(e=w)、读取次数(e=r)、知识加载次数(e=i)、失败次数(e=f)\n- 高写入+高读取+零知识加载 = 关键盲区（优先处理）\n- 高失败 = 问题区域（CLAUDE.md 需增强约束）\n\n第三步：执行进化（每次最多处理3个文件）\n1) 为关键盲区目录生成 CLAUDE.md，结构必须是：\n   ## 禁忌\\n## 改动时\\n## 约定\n2) 检查已有 CLAUDE.md 是否因文件变更而过时，用 Edit 工具最小化更新\n3) 确保 @ 引用反映真实依赖关系\n\n第四步：记录变更\n1) 每个创建或更新的 CLAUDE.md，追加一条到 .claude/graph-changelog.jsonl：\n   {\"action\":\"created|updated\",\"path\":\"相对路径\",\"reason\":\"原因\",\"ts\":时间戳}\n2) 将已处理事件追加到 .claude/graph-events-archive.jsonl\n3) 清空 graph-events.jsonl\n4) 归档文件超过 5000 行时只保留最后 2000 行\n5) 删除锁文件 .claude/.evolving",
            "timeout": 120
          }
        ]
      }
    ]
  }
}
```

Stop hook 设计：command 类型的 `on-stop.sh` 先做守卫检查（项目目录有效、锁文件不存在、事件数 >= 5）。守卫不通过时 `exit 1`（非零），阻止后续 agent hook 执行；通过时 `exit 0`，放行 agent 执行进化。

### 3. guard.sh（公共守卫）

```bash
#!/bin/bash
# 公共守卫：检查是否在有效项目目录中
# 用法：source guard.sh（exit 会直接终止调用者，这是期望行为）

# 三层守卫：未设置 / HOME / 根目录
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 0
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 0

# 确保项目数据空间存在（首次使用自动创建）
mkdir -p "$CLAUDE_PROJECT_DIR/.claude"
```

每个脚本开头 source 这个文件。exit 在 source 上下文中会直接终止调用者脚本，这正是我们要的行为。同时自动创建 `.claude/` 目录，解决首次使用时目录不存在的问题。

**on-stop.sh 特殊处理**：Stop hook 的守卫脚本不能用 `exit 0`（否则会放行 agent），守卫不通过时必须 `exit 1`：

```bash
#!/bin/bash
# on-stop.sh — Stop hook 守卫（exit 1 = 阻止 agent，exit 0 = 放行）
set -euo pipefail

# 工作空间守卫（不通过 = 阻止进化）
[ -z "$CLAUDE_PROJECT_DIR" ] && exit 1
[ "$CLAUDE_PROJECT_DIR" = "$HOME" ] && exit 1
[ "$CLAUDE_PROJECT_DIR" = "/" ] && exit 1

EVENTS="$CLAUDE_PROJECT_DIR/.claude/graph-events.jsonl"
LOCK="$CLAUDE_PROJECT_DIR/.claude/.evolving"

# 锁文件守卫（进化引擎正在运行）
[ -f "$LOCK" ] && exit 1

# 事件数守卫（不够则不值得进化）
[ ! -f "$EVENTS" ] && exit 1
LINE_COUNT=$(wc -l < "$EVENTS" | tr -d ' ')
[ "$LINE_COUNT" -lt 5 ] && exit 1

exit 0
```

### 4. Skills

**init-knowledge-graph/SKILL.md**

frontmatter 改为标准 skill 格式：
```yaml
---
name: init-knowledge-graph
description: 初始化项目知识图谱。扫描项目结构，在每个有意义的子目录生成 CLAUDE.md，建立全局索引和条件规则。安装后执行一次。
---
```

body 改动：

1. **开头守卫** — 第一步必须检查工作空间有效性：
   - `CLAUDE_PROJECT_DIR` 为空 → 告知用户「请在项目目录中执行此命令」，结束
   - `CLAUDE_PROJECT_DIR` = `$HOME` 或 `/` → 告知用户「不能在用户主目录或根目录执行」，结束

2. **扫描前确认** — 守卫通过后、扫描前必须：
   - 用 Glob 快速统计项目根目录下的文件总数（排除 .git/node_modules/dist 等）
   - 输出摘要：「当前目录：{path}，共 {N} 个文件，{M} 个子目录」
   - 明确询问用户「确认要在此目录初始化知识图谱吗？」
   - 用户确认后才开始实际扫描和生成

3. **幂等性保证** — 重复执行 /init 时的行为：
   - 已有 CLAUDE.md 的目录 → 读取现有内容，仅追加缺失的段落（禁忌/改动时/约定），不覆盖
   - 已有 .claude/rules/ → 检查现有规则，只补充新发现的规则
   - 已有 graph-events.jsonl → 不清空，保留历史数据
   - changelog 追加一条 `{"action":"re-initialized",...}` 记录

3. **其余内容不变** — 保留完整的扫描逻辑

**graph-status/SKILL.md**

同理迁移，开头加守卫提示。如果项目未初始化（无任何 CLAUDE.md），提示用户先执行 `/knowledge-graph:init-knowledge-graph`。

### 5. 脚本迁移清单

| 原路径 | 新路径 | 改动 |
|--------|--------|------|
| `.claude/hooks/track-activity.sh` | `scripts/track-activity.sh` | 加 guard.sh source |
| `.claude/hooks/track-instructions.sh` | `scripts/track-instructions.sh` | 加 guard.sh source |
| `.claude/hooks/track-failure.sh` | `scripts/track-failure.sh` | 加 guard.sh source |
| `.claude/hooks/inject-graph-context.sh` | `scripts/inject-graph-context.sh` | 加 guard.sh source |
| `.claude/hooks/inject-resume-context.sh` | `scripts/inject-resume-context.sh` | 加 guard.sh source |
| `.claude/hooks/on-compact.sh` | `scripts/on-compact.sh` | 加 guard.sh source |
| `.claude/hooks/inject-subagent-context.sh` | `scripts/inject-subagent-context.sh` | 加 guard.sh source |
| `.claude/hooks/on-stop.sh` | `scripts/on-stop.sh` | 加 guard.sh source |
| （无） | `scripts/guard.sh` | 新增公共守卫 |

## 测试方式

```bash
# 本地测试
claude --plugin-dir /path/to/knowledge-graph

# 在项目中验证
cd some-project
/knowledge-graph:init-knowledge-graph
/knowledge-graph:graph-status
```

## 注意事项

1. **首次使用自动引导** — guard.sh 自动 `mkdir -p` 创建 `.claude/` 目录。数据文件（events、changelog）由各脚本按需创建（append 操作会自动创建文件）。
2. **on-stop.sh 退出码** — 守卫不通过时必须 `exit 1`，通过时 `exit 0`。这是 command+agent 链式执行的关键。
3. **JSON 安全** — 追踪脚本中的 JSON 构造使用字符串拼接，文件路径中的特殊字符（`"`、`\`）可能导致无效 JSON。当前可接受（路径通常安全），后续可改用 `jq -n --arg` 加固。
4. **plugin.json 不需要显式引用 hooks** — `hooks/hooks.json` 是 Claude Code 插件的默认发现路径，无需在 plugin.json 中声明。

## 不在范围内

- Marketplace 发布（后续做）
- MCP server 集成
- 多语言 README
