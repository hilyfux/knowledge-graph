# Knowledge Graph

[English](#english) | [中文](#中文)

---

<a id="english"></a>

A persistent memory layer for Claude Code. Automatically tracks what Claude touches each session, lets you run `/knowledge-graph update` when you want to refresh the distributed CLAUDE.md knowledge nodes.

**Requirements**: `jq` (required), `git` (optional, enhances dependency analysis)

## What It Does

1. **Init** — bash scans project structure & dependencies, LLM generates CLAUDE.md behavior instructions for each module
2. **Real-time tracking** — single `jq` call records file changes/reads/searches/failures (< 30ms, no LLM)
3. **On-demand update** — run `/knowledge-graph update` to detect new modules + refresh existing nodes based on accumulated activity
4. **Smart injection** — session start injects CLAUDE.md summary, post-compaction restores context, subagents inherit prohibitions

## Install (Standalone — Recommended)

No plugin system required. Works by copying scripts + skill into your project.

```bash
# Clone or download this repo, then run the install script:
bash /path/to/knowledge-graph/standalone/install.sh /path/to/your-project

# Then restart your Claude Code session and run:
/knowledge-graph init
```

## Install (Plugin)

```bash
# Step 1: Add marketplace
/plugin marketplace add hilyfux/knowledge-graph

# Step 2: Install plugin
/plugin install knowledge-graph@knowledge-graph
```

> ⚠️ **Project-level only.** Do not install at user level (`--scope user`). Installing globally causes hooks to run in every project, including non-project directories.

## Uninstall (Plugin)

```bash
/plugin uninstall knowledge-graph@knowledge-graph
/plugin marketplace remove knowledge-graph
```

## Usage

```bash
# Initialize (first time, or after adding new modules manually)
/knowledge-graph init

# Check graph status
/knowledge-graph status

# Update knowledge nodes (detect new modules + refresh based on recent activity)
/knowledge-graph update
```

When ≥20 activity events have accumulated, the Stop hook prints a reminder at session end:
```
[kg] 💡 已积累 37 条活动记录，可运行 /knowledge-graph update 更新知识图谱
```

## Design Principles

### Bash Computes, LLM Decides

| Phase | Bash does | LLM does |
|-------|-----------|----------|
| Init | scan-project.sh scans dirs/deps/git | Generates CLAUDE.md content |
| Tracking | Single jq call writes events | — |
| Update | pre-analyze.sh aggregates stats | Reads analysis, decides what to write |
| Injection | Scripts assemble context | — |

### Three-Space Isolation

| Space | Location | Access |
|-------|----------|--------|
| Install | plugin dir or `standalone/` | Read-only |
| Workspace | `${CLAUDE_PROJECT_DIR}` | Skill scans |
| Data | `${CLAUDE_PROJECT_DIR}/.claude/` | Hooks read/write |

### Safety

- All operations silently exit under `$HOME` or `/`
- `/knowledge-graph init` counts files and asks for confirmation before scanning
- Repeated init is idempotent (append only, never overwrite)
- No background processes, no `claude -p` spawning

## Workflow

```
In session  → PostToolUse         Single jq records w:new/w:edit/r/s events
            → InstructionsLoaded  Records CLAUDE.md loading
            → PostToolUseFailure  Records failures + error summary
            → SubagentStart       Injects project prohibitions + failure patterns

Compaction  → SessionStart(compact)  Restores active dirs + prohibitions + failures + git commits

Session end → on-stop.sh         Prints reminder if ≥20 events accumulated (no LLM, < 1s)

On demand   → /knowledge-graph update
              Step 1: Scan for new modules (no events needed)
              Step 2: Event-based refresh (if ≥5 events)
                Light (<15 events): blind spots + broken ref fixes
                Standard (≥15):     + feedback loop + cross-module rules

Next session → SessionStart(startup) Injects updates + heatmap + git + health warnings
```

## Event Format

```jsonl
{"e":"w:new","p":"src/auth/handler.ts","t":1711...}
{"e":"w:edit","p":"src/auth/handler.ts","t":1711...}
{"e":"r","p":"src/auth/handler.ts","t":1711...}
{"e":"s","p":"src/","q":"AuthToken","t":1711...}
{"e":"i","p":"src/auth/CLAUDE.md","t":1711...}
{"e":"f","tool":"Bash","err":"permission denied","t":1711...}
```

## CLAUDE.md Structure

```markdown
# Module Name
## Prohibitions
- Specific & actionable (evidence-backed, never vague "be careful")
## When Changing
- Changed X → see @../api/CLAUDE.md
## Conventions
- How this module works
```

Principles: instructions not docs / @ references = graph edges / extreme compression / no evidence = no rule

## Project Structure

```
knowledge-graph/
├── .claude-plugin/marketplace.json    ← Marketplace definition
├── plugins/knowledge-graph/           ← Plugin path
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json
│   └── scripts/
│       ├── guard.sh                   ← Guard + json_escape + emit_hook_context
│       ├── scan-project.sh            ← Init pre-scan (dirs/deps/git)
│       ├── pre-analyze.sh             ← Update pre-computation (aggregation/blind spots/stale/broken)
│       ├── track-activity.sh          ← PostToolUse (single jq)
│       ├── track-instructions.sh      ← InstructionsLoaded (single jq)
│       ├── track-failure.sh           ← PostToolUseFailure (single jq)
│       ├── inject-graph-context.sh    ← SessionStart(startup|clear)
│       ├── inject-resume-context.sh   ← SessionStart(resume)
│       ├── on-compact.sh              ← SessionStart(compact) context recovery
│       ├── inject-subagent-context.sh ← SubagentStart prohibition injection
│       └── run-evolution.sh           ← Stop hook reminder (no LLM)
└── standalone/                        ← Standalone install (no plugin system needed)
    ├── install.sh                     ← Copies scripts + skill, merges hooks into settings.json
    ├── commands/knowledge-graph.md    ← Skill file
    └── scripts/                       ← Same scripts as plugin path
        └── on-stop.sh                 ← Stop hook reminder
```

## Team Usage

```bash
# Commit knowledge nodes (share team knowledge)
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# .gitignore runtime data
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/graph-analysis.json' >> .gitignore
echo '.claude/graph-scan.json' >> .gitignore
```

## Commands

| Command | Description |
|---------|-------------|
| `/knowledge-graph init` | Initialize knowledge graph (bash pre-scan + LLM generation) |
| `/knowledge-graph status` | Coverage / health / heatmap / blind spots |
| `/knowledge-graph update` | Detect new modules + refresh existing nodes from activity |

---

<a id="中文"></a>

# 知识图谱

Claude Code 的持久记忆层。自动追踪每次对话中 Claude 的操作，按需运行 `/knowledge-graph update` 刷新分布式 CLAUDE.md 知识节点。

**依赖**：`jq`（必需）、`git`（可选，增强依赖分析）

## 它做什么

1. **初始化** — bash 预扫描项目结构和依赖，LLM 为每个模块生成 CLAUDE.md 行为指令
2. **实时追踪** — 单 jq 调用记录文件变更/读取/搜索/失败（< 30ms，无 LLM）
3. **按需更新** — 运行 `/knowledge-graph update`，检测新模块 + 基于积累的活动记录刷新现有节点
4. **智能注入** — 会话开始注入 CLAUDE.md 摘要，压缩后恢复上下文，子 agent 继承禁忌

## 安装（Standalone，推荐）

无需插件系统，直接将脚本和 skill 复制到项目中。

```bash
# Clone 或下载本仓库，然后运行安装脚本：
bash /path/to/knowledge-graph/standalone/install.sh /path/to/your-project

# 重启 Claude Code session 后运行：
/knowledge-graph init
```

## 安装（插件方式）

```bash
# 第一步：添加 marketplace
/plugin marketplace add hilyfux/knowledge-graph

# 第二步：安装插件
/plugin install knowledge-graph@knowledge-graph
```

> ⚠️ **仅支持项目级别安装。** 不要在 user 级别安装（`--scope user`）。全局安装会导致 hooks 在所有目录触发，包括非项目目录。

## 卸载（插件方式）

```bash
/plugin uninstall knowledge-graph@knowledge-graph
/plugin marketplace remove knowledge-graph
```

## 使用

```bash
# 初始化（首次使用，或手动新建模块后）
/knowledge-graph init

# 查看图谱状态
/knowledge-graph status

# 更新知识节点（检测新模块 + 基于近期活动刷新）
/knowledge-graph update
```

积累 ≥20 条活动记录后，会话结束时 Stop hook 会打印提示：
```
[kg] 💡 已积累 37 条活动记录，可运行 /knowledge-graph update 更新知识图谱
```

## 设计原则

### bash 做计算，LLM 做判断

| 阶段 | bash 做的 | LLM 做的 |
|------|-----------|----------|
| 初始化 | scan-project.sh 扫描目录/依赖/git | 生成 CLAUDE.md 内容 |
| 追踪 | 单 jq 调用写事件 | — |
| 更新 | pre-analyze.sh 聚合统计 | 读分析结果，决定写什么 |
| 注入 | 脚本组装上下文 | — |

### 三空间隔离

| 空间 | 位置 | 读写 |
|------|------|------|
| 安装 | 插件目录或 `standalone/` | 只读 |
| 工作 | `${CLAUDE_PROJECT_DIR}` | skill 扫描 |
| 数据 | `${CLAUDE_PROJECT_DIR}/.claude/` | hooks 读写 |

### 安全设计

- `$HOME`、`/` 下所有操作静默退出
- `/knowledge-graph init` 先统计文件数，用户确认后才扫描
- 重复 init 幂等（只追加不覆盖）
- 无后台进程，不 spawn `claude -p`

## 工作流

```
对话中    → PostToolUse         单 jq 记录 w:new/w:edit/r/s 事件
         → InstructionsLoaded  记录 CLAUDE.md 加载
         → PostToolUseFailure  记录失败 + 错误摘要
         → SubagentStart       注入项目禁忌 + 失败模式

压缩时    → SessionStart(compact)  恢复活跃目录 + 禁忌 + 失败 + git 提交

对话结束  → on-stop.sh         积累 ≥20 条时打印提示（无 LLM，< 1秒）

按需执行  → /knowledge-graph update
            步骤 1：扫描新模块（不依赖事件）
            步骤 2：基于事件刷新（需 ≥5 条事件）
              轻量（<15事件）：盲区 + 断裂引用修复
              标准（≥15事件）：+ 反馈回路 + 跨模块规则

下次对话  → SessionStart(startup) 注入更新 + 热力图 + git + 健康警告
```

## 事件格式

```jsonl
{"e":"w:new","p":"src/auth/handler.ts","t":1711...}
{"e":"w:edit","p":"src/auth/handler.ts","t":1711...}
{"e":"r","p":"src/auth/handler.ts","t":1711...}
{"e":"s","p":"src/","q":"AuthToken","t":1711...}
{"e":"i","p":"src/auth/CLAUDE.md","t":1711...}
{"e":"f","tool":"Bash","err":"permission denied","t":1711...}
```

## CLAUDE.md 结构

```markdown
# 模块名
## 禁忌
- 具体可执行（有证据支撑，不写「注意」「小心」）
## 改动时
- 改了 X → 看 @../api/CLAUDE.md
## 约定
- 本模块工作方式
```

原则：指令不是文档 / @ 引用 = 图的边 / 极致压缩 / 无证据不写

## 项目结构

```
knowledge-graph/
├── .claude-plugin/marketplace.json    ← Marketplace 定义
├── plugins/knowledge-graph/           ← 插件路径
│   ├── .claude-plugin/plugin.json
│   ├── hooks/hooks.json
│   └── scripts/
│       ├── guard.sh                   ← 守卫 + json_escape + emit_hook_context
│       ├── scan-project.sh            ← init 预扫描（目录/依赖/git）
│       ├── pre-analyze.sh             ← update 预计算（事件聚合/盲区/过时/断裂）
│       ├── track-activity.sh          ← PostToolUse（单 jq）
│       ├── track-instructions.sh      ← InstructionsLoaded（单 jq）
│       ├── track-failure.sh           ← PostToolUseFailure（单 jq）
│       ├── inject-graph-context.sh    ← SessionStart(startup|clear)
│       ├── inject-resume-context.sh   ← SessionStart(resume)
│       ├── on-compact.sh              ← SessionStart(compact) 恢复上下文
│       ├── inject-subagent-context.sh ← SubagentStart 注入禁忌
│       └── run-evolution.sh           ← Stop hook 提示（无 LLM）
└── standalone/                        ← 独立安装（无需插件系统）
    ├── install.sh                     ← 复制脚本+skill，合并 hooks 到 settings.json
    ├── commands/knowledge-graph.md    ← Skill 文件
    └── scripts/                       ← 同插件路径的脚本
        └── on-stop.sh                 ← Stop hook 提示
```

## 团队使用

```bash
# 提交知识节点（共享团队知识）
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# .gitignore 排除运行时数据
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/graph-analysis.json' >> .gitignore
echo '.claude/graph-scan.json' >> .gitignore
```

## 命令

| 命令 | 说明 |
|------|------|
| `/knowledge-graph init` | 初始化知识图谱（bash 预扫描 + LLM 生成） |
| `/knowledge-graph status` | 覆盖率 / 健康度 / 热力图 / 盲区 |
| `/knowledge-graph update` | 检测新模块 + 基于近期活动刷新节点 |
