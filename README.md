# Knowledge Graph · 知识图谱

A persistent memory layer for Claude Code — hooks silently track every file operation, CLAUDE.md files store what Claude learns, and you run `/knowledge-graph update` when you're ready to refresh.

Claude Code 的持久记忆层 —— Hooks 静默追踪每次文件操作，CLAUDE.md 存储 Claude 学到的知识，你觉得时机合适时运行 `/knowledge-graph update` 刷新记忆。

**Requirements · 依赖**：`jq` (required · 必需), `git` (optional · 可选, enhances dependency analysis · 增强依赖分析)

---

## How It Works · 工作原理

Each phase is handled by the right tool — bash for data collection, LLM for decisions.

每个阶段由合适的工具负责 —— bash 负责数据采集，LLM 负责决策。

```
During session · 对话中
  PostToolUse          → track.sh               records writes; auto-triggers update every 15 writes via block
                                                 记录写入；每 15 次写入通过 block 机制自动触发 update
  PostToolUseFailure   → track.sh               records failures + error message
                                                 记录失败 + 错误信息
  InstructionsLoaded   → track.sh               records which CLAUDE.md was loaded
                                                 记录加载了哪些 CLAUDE.md
  SubagentStart        → context.sh             injects prohibitions into subagents
                                                 向子 agent 注入禁忌规则
  SessionStart         → context.sh             injects knowledge summary; warns if ≥10 events pending
                                                 启动时注入知识摘要；积压 ≥10 条时附带提醒

Session end · 对话结束
  Stop                 → analyze.sh             runs pre-analysis in background if ≥20 events, no LLM
                                                积累 ≥20 条时后台运行预分析，无 LLM

On demand · 按需
  /knowledge-graph init    full project scan, generates all CLAUDE.md
                           全量扫描项目，生成所有 CLAUDE.md
  /knowledge-graph update  detect new modules + refresh from accumulated activity
                           检测新模块 + 基于积累的活动记录刷新（也会被自动触发）
  /knowledge-graph status  coverage / health / blind spots / heatmap
                           覆盖率 / 健康度 / 盲区 / 热力图
```

---

## Install · 安装

```bash
bash /path/to/knowledge-graph/standalone/install.sh /path/to/your-project
```

Copies all scripts and the skill into `.claude/`, and merges hooks into `.claude/settings.json`. Safe to run on existing projects — it detects if already installed and skips.

将所有脚本和 skill 复制到 `.claude/`，并将 hooks 合并到 `.claude/settings.json`。对已有项目安全 —— 检测到已安装时自动跳过。

Then restart your Claude Code session and initialize:

重启 Claude Code session 后初始化：

```bash
/knowledge-graph init
```

---

## Commands · 命令

| Command · 命令 | When · 时机 |
|----------------|------------|
| `/knowledge-graph init` | First time, or after manually creating new modules · 首次使用，或手动新建模块后 |
| `/knowledge-graph status` | Anytime you want to see the graph state · 随时查看图谱状态 |
| `/knowledge-graph update` | Auto-triggered every 15 writes, or run manually anytime · 每 15 次写入自动触发，也可随时手动运行 |

**Auto-trigger · 自动触发**

Every 15 file writes, `track.sh` emits a `block` decision that instructs Claude to run `update` immediately in the current session — no user prompt needed.

每写入 15 个文件，`track.sh` 通过 `block` 机制向 Claude 注入指令，Claude 会立即在当前对话中执行 `update`，无需用户介入。

```
PostToolUse:Edit hook → [kg] 已积累 75 条变更记录，活跃区域：src/views/pages(3次)
                         【kg 自动指令】请立即执行知识图谱增量更新 ...
                         → Claude runs /knowledge-graph update automatically
```

---

## Design Principles · 设计原则

**Bash computes, LLM decides · Bash 做计算，LLM 做判断**

Bash handles all data collection and aggregation — it's fast, cheap, and deterministic. LLM only steps in when judgment is needed: reading the analysis and deciding what to write.

Bash 负责所有数据采集和聚合 —— 快速、低成本、确定性。LLM 只在需要判断时介入：读取分析结果，决定写什么。

| Phase · 阶段 | Bash | LLM |
|---|---|---|
| Tracking · 追踪 | single `jq` call per event · 每次事件单 jq 调用 | — |
| Pre-analysis · 预分析 | `pre-analyze.sh` aggregates stats · 聚合统计 | — |
| Writing CLAUDE.md · 写知识节点 | — | reads analysis, decides · 读分析，做决策 |
| Context injection · 注入上下文 | scripts assemble summary · 脚本组装摘要 | — |

**No background processes · 无后台进程**

No `claude -p`. No automatic LLM calls. All LLM work is triggered manually by you — you stay in control.

没有 `claude -p`。没有自动 LLM 调用。所有 LLM 工作由你手动触发 —— 你保持完全控制。

**Idempotent · 幂等**

`init` and `update` are safe to re-run at any time. They append missing content and skip anything already complete — they never overwrite.

`init` 和 `update` 随时可以重复运行。它们追加缺失内容，跳过已有内容 —— 不会覆盖。

**Evidence-based · 有证据才写**

Every rule written to CLAUDE.md requires a traceable source: git commit history, recorded error events, or direct code analysis. If there's no evidence, the rule is not written. An unverified rule is more dangerous than no rule.

写入 CLAUDE.md 的每条规则都必须有可追溯的来源：git 提交历史、记录的错误事件或代码分析。没有证据就不写。一条未经验证的规则比没有规则更危险。

---

## CLAUDE.md Structure · 知识节点格式

Each module gets a CLAUDE.md that Claude loads automatically when working in that directory.

每个模块有一个 CLAUDE.md，Claude 进入该目录时自动加载。

```markdown
# Module Name · 模块名

## Prohibitions · 禁忌
- Don't do X → causes Y (source: commit abc123)
- 不要做 X → 会导致 Y（来源：commit abc123）

## When Changing · 改动时
- When you touch auth → also check @../middleware/CLAUDE.md
- 改动 auth → 同时看 @../middleware/CLAUDE.md

## Conventions · 约定
- This module uses pattern X because Y
- 本模块使用 X 模式，原因是 Y
```

`@` references create a graph of dependencies — when Claude follows a reference, it loads the target CLAUDE.md too.

`@` 引用构成依赖图 —— Claude 跟随引用时，也会加载目标 CLAUDE.md。

---

## Project Structure · 项目结构

```
knowledge-graph/
├── standalone/
│   ├── install.sh                     ← entry point · 入口
│   │                                    copies scripts + skill, merges hooks into settings.json
│   │                                    复制脚本 + skill，合并 hooks 到 settings.json
│   │
│   └── skills/
│       └── knowledge-graph/
│           ├── SKILL.md               ← skill file (init / status / update)
│           │                            skill 文件，定义三个命令的执行逻辑
│           └── scripts/
│               ├── track.sh           ← PostToolUse / PostToolUseFailure / InstructionsLoaded
│               │                        记录文件操作、错误、CLAUDE.md 加载
│               ├── context.sh         ← SessionStart / SubagentStart: injects summary + prohibitions
│               │                        注入知识摘要 + 子 agent 禁忌规则
│               ├── analyze.sh         ← Stop hook: pre-analysis when ≥20 events, no LLM
│               │                        Stop hook：≥20 条时后台预分析，无 LLM
│               └── guard.sh           ← shared: validates project dir, helpers
│                                        共享：校验项目目录，工具函数
└── docs/
```

---

## Team Usage · 团队使用

CLAUDE.md files are project knowledge — commit them. Runtime data is local — gitignore it.

CLAUDE.md 文件是项目知识 —— 提交它们。运行时数据是本地的 —— 加入 gitignore。

```bash
# Commit knowledge to share with the team · 提交知识，共享给团队
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# Keep runtime data local · 运行时数据保持本地
echo '.claude/graph-events.jsonl'  >> .gitignore
echo '.claude/graph-analysis.json' >> .gitignore
echo '.claude/graph-scan.json'     >> .gitignore
```
