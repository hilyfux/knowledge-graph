# Knowledge Graph

[English](#english) | [中文](#中文)

---

<a id="english"></a>

Claude Code plugin — fully automatic knowledge graph. Compensates for AI's weaknesses: cross-session amnesia, unknown project constraints, invisible module dependencies.

**Requirements**: `jq` (required), `git` (optional, enhances dependency analysis)

## What It Does

1. **Initial scan** — bash pre-scans project structure & dependencies, LLM generates CLAUDE.md behavior instructions
2. **Real-time tracking** — single jq call records file changes/reads/searches/failures (< 30ms)
3. **Tiered evolution** — bash pre-computes analysis at session end → auto-selects light/standard mode → LLM only makes decisions
4. **Smart injection** — session start injects summary, post-compaction restores working context, subagents inherit prohibitions

## Install

```bash
# Step 1: Add marketplace
/plugin marketplace add hilyfux/knowledge-graph

# Step 2: Install plugin (via /plugin UI or command)
/plugin install knowledge-graph@hilyfux-knowledge-graph

# Alternative: local development
claude --plugin-dir /path/to/knowledge-graph
```

## Usage

```bash
cd your-project
claude
# Auto-prompts initialization on first use, or manually:
> /knowledge-graph:init-knowledge-graph
# Check graph status:
> /knowledge-graph:graph-status
```

Fully automatic after init — hooks track activity, evolution engine runs on its own.

## Design Principles

### Bash Computes, LLM Decides

| Phase | Bash does | LLM does |
|-------|-----------|----------|
| Init | scan-project.sh scans dirs/deps/git | Generates CLAUDE.md content |
| Tracking | Single jq call writes events | — |
| Evolution | pre-analyze.sh aggregates stats | Reads analysis, decides what to write |
| Injection | Scripts assemble context | — |

### Three-Space Isolation

| Space | Location | Access |
|-------|----------|--------|
| Install | `~/.claude/plugins/.../knowledge-graph/` | Read-only |
| Workspace | `${CLAUDE_PROJECT_DIR}` | Skill scans |
| Data | `${CLAUDE_PROJECT_DIR}/.claude/` | Hooks read/write |

### Misoperation Protection

- All operations silently exit under `$HOME` or `/`
- `/init` counts files and asks for confirmation before scanning
- Repeated `/init` is idempotent (append only, never overwrite)
- Plugin uninstall/upgrade does not affect project data

## Workflow

```
In session  → PostToolUse        Single jq records w:new/w:edit/r/s events
            → InstructionsLoaded  Records CLAUDE.md loading
            → PostToolUseFailure  Records failures + error summary
            → SubagentStart       Injects project prohibitions + failure patterns

Compaction  → SessionStart(compact)  Restores active dirs + prohibitions + failures + git commits

Session end → on-stop.sh          Guard + pre-analyze.sh pre-computation
            → Evolution agent      Reads analysis JSON → tiered decisions → quality check → writes
              Light (<15 events): blind spots + broken ref fixes
              Standard (≥15):     + feedback loop + cross-module rules

Next session → SessionStart(startup) Injects updates + heatmap + git + health warnings
                                     Auto-suggests init on first use
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

## Plugin Structure

```
knowledge-graph/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── scripts/
│   ├── guard.sh                  ← Guard + json_escape + emit_hook_context
│   ├── scan-project.sh           ← Init pre-scan (dirs/deps/git)
│   ├── pre-analyze.sh            ← Evolution pre-computation (aggregation/blind spots/stale/broken)
│   ├── track-activity.sh         ← PostToolUse (single jq)
│   ├── track-instructions.sh     ← InstructionsLoaded (single jq)
│   ├── track-failure.sh          ← PostToolUseFailure (single jq)
│   ├── inject-graph-context.sh   ← SessionStart(startup|clear)
│   ├── inject-resume-context.sh  ← SessionStart(resume)
│   ├── on-compact.sh             ← SessionStart(compact) context recovery
│   ├── inject-subagent-context.sh ← SubagentStart prohibition injection
│   └── on-stop.sh                ← Stop guard + trigger pre-analysis
└── skills/
    ├── init-knowledge-graph/SKILL.md
    └── graph-status/SKILL.md
```

## Team Usage

```bash
# Commit knowledge nodes (share team knowledge)
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# .gitignore runtime data
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/.evolving' >> .gitignore
echo '.claude/graph-analysis.json' >> .gitignore
echo '.claude/graph-scan.json' >> .gitignore
```

## Commands

| Command | Description |
|---------|-------------|
| `/knowledge-graph:init-knowledge-graph` | Initialize knowledge graph (bash pre-scan + LLM generation) |
| `/knowledge-graph:graph-status` | Coverage / health / heatmap / blind spots / failure patterns |

---

<a id="中文"></a>

# 知识图谱

Claude Code 插件 — 全自动知识图谱。弥补 AI 的短板：跨会话失忆、不知道项目禁忌、看不到模块依赖。

**依赖**：`jq`（必需）、`git`（可选，增强依赖分析）

## 它做什么

1. **首次扫描** — bash 预扫描项目结构和依赖，LLM 生成 CLAUDE.md 行为指令
2. **实时追踪** — 单 jq 调用记录文件变更/读取/搜索/失败（< 30ms）
3. **分级进化** — 对话结束时 bash 预计算分析 → 轻量/标准模式自动选择 → LLM 只做判断
4. **智能注入** — 会话开始注入摘要，压缩后恢复工作上下文，子 agent 继承禁忌

## 安装

```bash
# 第一步：添加 marketplace
/plugin marketplace add hilyfux/knowledge-graph

# 第二步：安装插件（通过 /plugin 界面或命令）
/plugin install knowledge-graph@hilyfux-knowledge-graph

# 或者：本地测试
claude --plugin-dir /path/to/knowledge-graph
```

## 使用

```bash
cd your-project
claude
# 首次自动提示初始化，或手动执行：
> /knowledge-graph:init-knowledge-graph
# 查看图谱状态：
> /knowledge-graph:graph-status
```

之后全自动 — hooks 追踪，进化引擎自动运行。

## 设计原则

### bash 做计算，LLM 做判断

| 阶段 | bash 做的 | LLM 做的 |
|------|-----------|----------|
| 初始化 | scan-project.sh 扫描目录/依赖/git | 生成 CLAUDE.md 内容 |
| 追踪 | 单 jq 调用写事件 | — |
| 进化 | pre-analyze.sh 聚合统计 | 读分析结果，决定写什么 |
| 注入 | 脚本组装上下文 | — |

### 三空间隔离

| 空间 | 位置 | 读写 |
|------|------|------|
| 安装 | `~/.claude/plugins/.../knowledge-graph/` | 只读 |
| 工作 | `${CLAUDE_PROJECT_DIR}` | skill 扫描 |
| 数据 | `${CLAUDE_PROJECT_DIR}/.claude/` | hooks 读写 |

### 防误操作

- `$HOME`、`/` 下所有操作静默退出
- `/init` 先统计文件数，用户确认后才扫描
- 重复 `/init` 幂等（只追加不覆盖）
- 插件卸载不影响项目数据

## 工作流

```
对话中    → PostToolUse        单 jq 记录 w:new/w:edit/r/s 事件
         → InstructionsLoaded  记录 CLAUDE.md 加载
         → PostToolUseFailure  记录失败 + 错误摘要
         → SubagentStart       注入项目禁忌 + 失败模式

压缩时    → SessionStart(compact)  恢复活跃目录 + 禁忌 + 失败 + git 提交

对话结束  → on-stop.sh          守卫 + pre-analyze.sh 预计算
         → 进化引擎 agent       读分析 JSON → 分级决策 → 质量自检 → 写入
           轻量（<15事件）：盲区 + 断裂修复
           标准（≥15事件）：+ 反馈回路 + 跨模块规则

下次对话  → SessionStart(startup) 注入更新 + 热力图 + git + 健康警告
                                 首次自动提示初始化
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

## 插件结构

```
knowledge-graph/
├── .claude-plugin/plugin.json
├── hooks/hooks.json
├── scripts/
│   ├── guard.sh                  ← 守卫 + json_escape + emit_hook_context
│   ├── scan-project.sh           ← init 预扫描（目录/依赖/git）
│   ├── pre-analyze.sh            ← 进化预计算（事件聚合/盲区/过时/断裂）
│   ├── track-activity.sh         ← PostToolUse（单 jq）
│   ├── track-instructions.sh     ← InstructionsLoaded（单 jq）
│   ├── track-failure.sh          ← PostToolUseFailure（单 jq）
│   ├── inject-graph-context.sh   ← SessionStart(startup|clear)
│   ├── inject-resume-context.sh  ← SessionStart(resume)
│   ├── on-compact.sh             ← SessionStart(compact) 恢复上下文
│   ├── inject-subagent-context.sh ← SubagentStart 注入禁忌
│   └── on-stop.sh                ← Stop 守卫 + 触发预分析
└── skills/
    ├── init-knowledge-graph/SKILL.md
    └── graph-status/SKILL.md
```

## 团队使用

```bash
# 提交知识节点
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# .gitignore 排除运行时数据
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/.evolving' >> .gitignore
echo '.claude/graph-analysis.json' >> .gitignore
echo '.claude/graph-scan.json' >> .gitignore
```

## 命令

| 命令 | 说明 |
|------|------|
| `/knowledge-graph:init-knowledge-graph` | 初始化知识图谱（bash 预扫描 + LLM 生成） |
| `/knowledge-graph:graph-status` | 覆盖率 / 健康度 / 热力图 / 盲区 / 失败模式 |
