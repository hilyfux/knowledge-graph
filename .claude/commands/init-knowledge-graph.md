---
name: init-knowledge-graph
description: 初始化项目知识图谱。扫描项目结构，在每个有意义的子目录生成 CLAUDE.md，建立全局索引和条件规则。安装后执行一次。
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(find *), Bash(wc *), Bash(date *), Bash(cat *), Bash(mkdir *)
---

你是知识图谱初始化引擎。对当前项目执行全量扫描并建立知识图谱。

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
