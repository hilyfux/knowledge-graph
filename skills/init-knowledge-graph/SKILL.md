---
name: init-knowledge-graph
description: 初始化项目知识图谱。扫描项目结构，在每个有意义的子目录生成 CLAUDE.md，建立全局索引和条件规则。安装后执行一次。
---

你是知识图谱初始化引擎。对当前项目执行全量扫描并建立知识图谱。

## 步骤

### 0. 工作空间守卫
- 检查当前工作目录：不能是 $HOME，不能是 /
- 如果无效 → 告知用户"请在项目目录中执行此命令，不能在用户主目录或根目录执行"，停止
- 如果目录看起来像非项目目录（如 ~/Desktop、~/Downloads）→ 在下一步确认中加入额外警告

### 1. 扫描前确认
- 用 Glob 快速统计项目根目录下的总文件数（排除 .git、node_modules、dist、build、.next、__pycache__、.venv、vendor、target、.claude）
- 输出摘要："当前目录：{path}，共 {N} 个文件，{M} 个子目录"
- 询问用户："确认要在此目录初始化知识图谱吗？"
- 仅在用户确认后继续。如果用户拒绝，停止。

### 2. 项目感知
- 用 Glob 扫描项目结构（`**/*`），识别所有有实质内容的目录
- 跳过：.git、node_modules、dist、build、.next、__pycache__、.venv、vendor、target、.claude
- 跳过 .gitignore 中列出的路径
- 读取项目元文件（README.md、package.json、Cargo.toml、pyproject.toml、go.mod 等）
- 识别项目类型：代码/文档/混合
- 识别模块边界：每个有 3+ 文件且有独立职责的目录视为一个模块

### 2.5. 依赖关系提取（关键步骤）
对每个识别出的模块目录，用 Grep 分析真实的代码依赖：

- **JS/TS 项目**：搜索 `import .* from|require\(` 语句，提取相对路径引用
- **Python 项目**：搜索 `from .* import|import .*` 语句，提取模块引用
- **Go 项目**：搜索 `import` 块中的包路径
- **Rust 项目**：搜索 `use ` 和 `mod ` 语句
- **通用**：搜索跨目录的文件引用（配置文件中的路径引用等）

构建依赖矩阵：
```
模块A → 模块B（import 了 B 的文件）
模块A → 模块C（配置中引用了 C 的路径）
```

只记录跨目录的依赖关系（同目录内的 import 不需要 @ 引用）。
这个矩阵直接用于后续步骤中生成 @ 引用，不要猜测依赖关系。

### 2.6. Git 历史挖掘（如果是 git 仓库）
如果项目有 git 历史，分析以下信号来增强知识图谱质量：

**共变分析**：
- 执行 `git log --pretty=format: --name-only -50 | sort | uniq -c | sort -rn`
- 找出总是一起修改的文件对 → 补充到依赖矩阵（即使代码中没有显式 import）
- 例：schema.prisma 和 types.ts 总是一起改 → 说明有隐式依赖

**失败历史**：
- 执行 `git log --oneline --all --grep='fix\|bug\|revert\|broken\|wrong' -20`
- 分析哪些目录/文件反复出现在修复提交中 → 这些区域需要更强的禁忌
- 分析 revert 提交 → 理解什么改动是错误的，写入禁忌

**约定发现**：
- 从 commit message 风格推断团队约定（如 conventional commits）
- 从近期提交模式推断工作流（如先改 test 再改 src = TDD）
- 这些约定写入根 CLAUDE.md 的「全局约定」或 .claude/rules/

### 3. 生成根 CLAUDE.md
如果项目根已有 CLAUDE.md：
- 读取现有内容，仅追加缺失的段落，不覆盖已有内容

如果没有 CLAUDE.md：
```markdown
# {从 README 或 package.json 提取的项目名}

@README.md

## 全局约定
- {从项目配置和代码风格推断的约定}

## 禁忌
- {从项目结构推断的禁忌，如不要手动修改生成文件}
```

### 4. 生成子模块 CLAUDE.md
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
- @ 引用必须基于步骤 2.5 提取的真实依赖矩阵，不要猜测
- 禁忌必须具体可执行：不写「注意兼容性」，写「修改 API 响应格式时必须同步更新 client/types.ts」
- 已有 CLAUDE.md 的目录 → 读取现有内容，仅追加缺失的段落（禁忌/改动时/约定），不覆盖

### 5. 生成 .claude/rules/
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

检查已有规则文件，只补充新发现的规则，不覆盖已有规则

### 6. 初始化数据文件
```bash
mkdir -p .claude
touch .claude/graph-events.jsonl
touch .claude/graph-changelog.jsonl
touch .claude/graph-events-archive.jsonl
```

将初始化事件写入 changelog：
- 首次初始化：`{"action":"initialized","path":".","reason":"知识图谱首次初始化","ts":{当前时间戳}}`
- 重新初始化：`{"action":"re-initialized","path":".","reason":"知识图谱重新初始化","ts":{当前时间戳}}`

### 7. 输出初始化报告
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
