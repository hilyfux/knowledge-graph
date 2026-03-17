# 知识图谱 (Knowledge Graph)

自动化的 Claude Code 知识图谱系统。安装到任何项目后，通过 hooks 自动追踪活动、检测盲区、生成和进化分布式 CLAUDE.md 知识节点。

## 它做什么

1. **首次扫描** — 分析项目结构，在每个有意义的子目录生成 CLAUDE.md 行为指令
2. **实时追踪** — 通过 hooks 记录文件变更、读取、搜索、加载、失败事件
3. **自动进化** — 每次对话结束时自动检测盲区，补充/更新 CLAUDE.md
4. **上下文注入** — 每次对话开始时注入图谱摘要和更新报告

## 安装

```bash
# 方式 1: 安装脚本
git clone <this-repo>
bash knowledge-graph/install.sh /path/to/your-project

# 方式 2: 直接复制
cp -r knowledge-graph/.claude/ /path/to/your-project/.claude/
chmod +x /path/to/your-project/.claude/scripts/*.sh
```

## 使用

```bash
cd your-project
claude

# 首次执行（安装后运行一次）
> /init-knowledge-graph

# 查看图谱状态
> /graph-status
```

之后无需任何操作 — hooks 自动追踪，进化引擎自动运行。

## 工作原理

```
对话中 → PostToolUse hook 记录文件变更/读取 (< 50ms)
       → InstructionsLoaded hook 追踪知识节点加载
       → PostToolUseFailure hook 追踪失败模式

对话结束 → Stop agent hook 启动进化引擎
         → 三维盲区检测（变更频率 × 访问频率 × 知识加载频率）
         → 自动生成/更新 CLAUDE.md
         → 记录变更到 changelog

下次对话 → SessionStart hook 注入更新报告
         → Claude 告知用户知识图谱的变化
```

## 文件结构

安装后你的项目会有：

```
项目/
├── .claude/
│   ├── settings.json              ← hooks + 权限配置
│   ├── scripts/                   ← 7 个 hook 脚本（自动运行）
│   ├── commands/
│   │   ├── init-knowledge-graph.md   ← /init-knowledge-graph
│   │   └── graph-status.md           ← /graph-status
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
git add CLAUDE.md **/CLAUDE.md .claude/rules/ .claude/commands/ .claude/scripts/ .claude/settings.json

# .gitignore 中排除运行时数据
echo '.claude/graph-events.jsonl' >> .gitignore
echo '.claude/graph-events-archive.jsonl' >> .gitignore
echo '.claude/graph-changelog.jsonl' >> .gitignore
echo '.claude/.evolving' >> .gitignore
```

## 命令

| 命令 | 说明 |
|------|------|
| `/init-knowledge-graph` | 首次全量扫描，生成知识图谱 |
| `/graph-status` | 查看覆盖率、热力图、盲区 |
