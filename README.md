# Knowledge Graph

[English](#english) | [中文](#中文)

---

<a id="english"></a>

A persistent memory layer for Claude Code. Hooks automatically track every file operation in each session. Run `/knowledge-graph update` when you want to refresh the distributed CLAUDE.md knowledge nodes.

**Requirements**: `jq` (required), `git` (optional, enhances dependency analysis)

## How It Works

```
In session  → hooks (pure bash, < 30ms each)
              PostToolUse        → records file writes/reads/searches
              PostToolUseFailure → records failures + error summary
              InstructionsLoaded → records CLAUDE.md loads
              SubagentStart      → injects prohibitions into subagents
              SessionStart       → injects knowledge summary on startup

Session end → on-stop.sh        → prints reminder if ≥20 events (no LLM, < 1s)

On demand   → /knowledge-graph init    first-time setup
            → /knowledge-graph update  detect new modules + refresh from activity
            → /knowledge-graph status  coverage / health / heatmap
```

## Install

```bash
bash /path/to/knowledge-graph/standalone/install.sh /path/to/your-project
```

Copies scripts + skill into `.claude/`, merges hooks into `.claude/settings.json`.

Then restart your Claude Code session and run:

```bash
/knowledge-graph init
```

## Usage

| Command | When to run |
|---------|-------------|
| `/knowledge-graph init` | First time, or after manually adding new modules |
| `/knowledge-graph status` | Check coverage / health / blind spots |
| `/knowledge-graph update` | After accumulating activity — refreshes CLAUDE.md nodes |

The Stop hook reminds you when it's time:
```
[kg] 💡 已积累 37 条活动记录，可运行 /knowledge-graph update 更新知识图谱
```

## Design

**Bash computes, LLM decides.**

| Phase | Bash | LLM |
|-------|------|-----|
| Tracking | single `jq` call writes events | — |
| Update pre-analysis | `pre-analyze.sh` aggregates stats | — |
| Writing CLAUDE.md | — | reads analysis, decides what to write |
| Context injection | scripts assemble summary | — |

**No background processes.** No `claude -p`. No automatic LLM calls. Everything LLM-driven is triggered manually by you.

**Idempotent.** `init` and `update` are safe to re-run — they append missing content, never overwrite.

**Evidence-based.** Every rule written to CLAUDE.md must have a source (git history, error events, or code analysis). No evidence → no rule.

## CLAUDE.md Structure

```markdown
# Module Name
## Prohibitions
- Specific & actionable (evidence-backed)
## When Changing
- Changed X → see @../other/CLAUDE.md
## Conventions
- How this module works
```

## Project Structure

```
knowledge-graph/
├── standalone/
│   ├── install.sh              ← copies scripts + skill, merges hooks
│   ├── commands/
│   │   └── knowledge-graph.md  ← skill (init / status / update)
│   └── scripts/
│       ├── on-stop.sh                 ← Stop hook: reminder if ≥20 events
│       ├── track-activity.sh          ← PostToolUse
│       ├── track-failure.sh           ← PostToolUseFailure
│       ├── track-instructions.sh      ← InstructionsLoaded
│       ├── inject-graph-context.sh    ← SessionStart(startup)
│       ├── inject-resume-context.sh   ← SessionStart(resume)
│       ├── on-compact.sh              ← SessionStart(compact)
│       ├── inject-subagent-context.sh ← SubagentStart
│       ├── scan-project.sh            ← init pre-scan
│       ├── pre-analyze.sh             ← update pre-computation
│       └── guard.sh                   ← shared guard + helpers
└── docs/
```

## Team Usage

```bash
# Commit knowledge nodes (share with team)
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# Exclude runtime data from git
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/graph-analysis.json' >> .gitignore
echo '.claude/graph-scan.json' >> .gitignore
```

---

<a id="中文"></a>

# 知识图谱

Claude Code 的持久记忆层。Hooks 自动追踪每次对话中的文件操作。按需运行 `/knowledge-graph update` 刷新分布式 CLAUDE.md 知识节点。

**依赖**：`jq`（必需）、`git`（可选，增强依赖分析）

## 工作原理

```
对话中    → hooks（纯 bash，每次 < 30ms）
            PostToolUse        → 记录文件写入/读取/搜索
            PostToolUseFailure → 记录失败 + 错误摘要
            InstructionsLoaded → 记录 CLAUDE.md 加载
            SubagentStart      → 向子 agent 注入禁忌
            SessionStart       → 启动时注入知识摘要

对话结束  → on-stop.sh        → 积累 ≥20 条时打印提示（无 LLM，< 1秒）

按需执行  → /knowledge-graph init    首次初始化
          → /knowledge-graph update  检测新模块 + 基于活动刷新
          → /knowledge-graph status  覆盖率 / 健康度 / 热力图
```

## 安装

```bash
bash /path/to/knowledge-graph/standalone/install.sh /path/to/your-project
```

将脚本和 skill 复制到 `.claude/`，并将 hooks 合并到 `.claude/settings.json`。

重启 Claude Code session 后运行：

```bash
/knowledge-graph init
```

## 使用

| 命令 | 时机 |
|------|------|
| `/knowledge-graph init` | 首次使用，或手动新建模块后 |
| `/knowledge-graph status` | 查看覆盖率 / 健康度 / 盲区 |
| `/knowledge-graph update` | 积累了足够活动记录后，刷新 CLAUDE.md |

Stop hook 会在合适时机提示你：
```
[kg] 💡 已积累 37 条活动记录，可运行 /knowledge-graph update 更新知识图谱
```

## 设计原则

**bash 做计算，LLM 做判断。**

| 阶段 | Bash | LLM |
|------|------|-----|
| 追踪 | 单 jq 调用写事件 | — |
| 更新预分析 | pre-analyze.sh 聚合统计 | — |
| 写 CLAUDE.md | — | 读分析结果，决定写什么 |
| 上下文注入 | 脚本组装摘要 | — |

**无后台进程。** 无 `claude -p`。无自动 LLM 调用。所有 LLM 操作由你手动触发。

**幂等。** `init` 和 `update` 可重复运行——只追加缺失内容，不覆盖已有内容。

**有证据才写。** CLAUDE.md 里的每条规则必须有来源（git 历史、错误事件或代码分析）。无证据不写。

## CLAUDE.md 结构

```markdown
# 模块名
## 禁忌
- 具体可执行（有证据支撑）
## 改动时
- 改了 X → 看 @../other/CLAUDE.md
## 约定
- 本模块工作方式
```

## 项目结构

```
knowledge-graph/
├── standalone/
│   ├── install.sh              ← 复制脚本 + skill，合并 hooks
│   ├── commands/
│   │   └── knowledge-graph.md  ← skill（init / status / update）
│   └── scripts/
│       ├── on-stop.sh                 ← Stop hook：≥20 条时提示
│       ├── track-activity.sh          ← PostToolUse
│       ├── track-failure.sh           ← PostToolUseFailure
│       ├── track-instructions.sh      ← InstructionsLoaded
│       ├── inject-graph-context.sh    ← SessionStart(startup)
│       ├── inject-resume-context.sh   ← SessionStart(resume)
│       ├── on-compact.sh              ← SessionStart(compact)
│       ├── inject-subagent-context.sh ← SubagentStart
│       ├── scan-project.sh            ← init 预扫描
│       ├── pre-analyze.sh             ← update 预计算
│       └── guard.sh                   ← 共享守卫 + 工具函数
└── docs/
```

## 团队使用

```bash
# 提交知识节点（共享给团队）
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# .gitignore 排除运行时数据
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/graph-analysis.json' >> .gitignore
echo '.claude/graph-scan.json' >> .gitignore
```
