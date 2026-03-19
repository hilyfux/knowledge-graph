# 知识图谱 (Knowledge Graph)

Claude Code 插件 — 自动化知识图谱系统。通过 hooks 自动追踪活动、检测盲区、生成和进化分布式 CLAUDE.md 知识节点。

## 它做什么

1. **首次扫描** — 分析项目结构，在每个有意义的子目录生成 CLAUDE.md 行为指令
2. **实时追踪** — 通过 hooks 记录文件变更、读取、搜索、加载、失败事件
3. **自动进化** — 每次对话结束时自动检测盲区，补充/更新 CLAUDE.md
4. **上下文注入** — 每次对话开始时注入图谱摘要和更新报告

## 安装

```bash
# 从 GitHub 安装（user 级别，所有项目可用）
claude plugin install --scope user https://github.com/hilyfux/knowledge-graph

# 或安装到当前项目
claude plugin install --scope project https://github.com/hilyfux/knowledge-graph

# 本地开发测试
claude --plugin-dir /path/to/knowledge-graph
```

## 使用

```bash
cd your-project
claude

# 首次执行（安装后在项目中运行一次）
> /knowledge-graph:init-knowledge-graph

# 查看图谱状态
> /knowledge-graph:graph-status
```

之后无需任何操作 — hooks 自动追踪，进化引擎自动运行。

## 安全设计

### 三空间隔离

| 空间 | 位置 | 说明 |
|------|------|------|
| 安装空间 | `~/.claude/plugins/cache/knowledge-graph/` | 只读，插件代码 |
| 工作空间 | 当前项目目录 | skill 扫描和生成 CLAUDE.md |
| 数据空间 | 项目的 `.claude/` | 运行时事件数据（跟项目走） |

### 防误操作

- 在 `$HOME` 或 `/` 下不会执行任何操作（所有脚本和 skill 有守卫检查）
- `/init` 执行前会统计文件数量并要求用户确认
- 重复执行 `/init` 不会覆盖已有内容（幂等）
- 插件卸载/升级不影响项目中的数据和 CLAUDE.md

## 工作原理

```
对话中 → PostToolUse hook 记录文件变更/读取 (< 50ms)
       → InstructionsLoaded hook 追踪知识节点加载
       → PostToolUseFailure hook 追踪失败模式

对话结束 → Stop hook 守卫检查 + agent 启动进化引擎
         → 三维盲区检测（变更频率 × 访问频率 × 知识加载频率）
         → 自动生成/更新 CLAUDE.md
         → 记录变更到 changelog

下次对话 → SessionStart hook 注入更新报告
         → Claude 告知用户知识图谱的变化
```

## 插件结构

```
knowledge-graph/
├── .claude-plugin/
│   └── plugin.json              ← 插件 manifest
├── hooks/
│   └── hooks.json               ← 所有 hook 定义
├── scripts/
│   ├── guard.sh                 ← 公共守卫（三层检查 + 自动创建 .claude/）
│   ├── track-activity.sh        ← PostToolUse: 记录文件变更/读取
│   ├── track-instructions.sh    ← InstructionsLoaded: 记录知识加载
│   ├── track-failure.sh         ← PostToolUseFailure: 记录失败
│   ├── inject-graph-context.sh  ← SessionStart(startup|clear): 注入上下文
│   ├── inject-resume-context.sh ← SessionStart(resume): 恢复上下文
│   ├── on-compact.sh            ← SessionStart(compact): 压缩提示
│   ├── inject-subagent-context.sh ← SubagentStart: 子 agent 提示
│   └── on-stop.sh               ← Stop: 进化条件守卫
└── skills/
    ├── init-knowledge-graph/
    │   └── SKILL.md             ← /knowledge-graph:init-knowledge-graph
    └── graph-status/
        └── SKILL.md             ← /knowledge-graph:graph-status
```

安装后项目中会生成：

```
项目/
├── .claude/
│   ├── rules/                     ← 条件规则（进化引擎自动生成）
│   ├── graph-events.jsonl         ← 运行时事件流
│   ├── graph-changelog.jsonl      ← 进化变更日志
│   └── graph-events-archive.jsonl ← 归档事件
├── CLAUDE.md                      ← 根知识节点
├── src/
│   └── auth/
│       └── CLAUDE.md              ← 子模块知识节点（懒加载）
└── ...
```

## CLAUDE.md 结构

每个 CLAUDE.md 遵循三段式模板：

```markdown
# 模块名

## 禁忌
- 不要做的事

## 改动时
- 改了 X → 同步更新 @../api/CLAUDE.md

## 约定
- 本模块特有的工作方式
```

核心原则：
- **指令不是文档** — 只写代码里读不到的东西
- **`@` 引用即图谱边** — 关联内嵌在触发条件中
- **极致压缩** — 每个字都消耗 token

## 团队使用

```bash
# 提交知识节点（共享团队知识）
git add CLAUDE.md **/CLAUDE.md .claude/rules/

# .gitignore 中排除运行时数据
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/.evolving' >> .gitignore
```

## 命令

| 命令 | 说明 |
|------|------|
| `/knowledge-graph:init-knowledge-graph` | 首次全量扫描，生成知识图谱 |
| `/knowledge-graph:graph-status` | 查看覆盖率、热力图、盲区 |
