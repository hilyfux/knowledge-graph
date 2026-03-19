---
name: init-knowledge-graph
description: 初始化项目知识图谱。扫描项目结构，生成 CLAUDE.md 和条件规则。幂等，可重复执行。
---

知识图谱初始化引擎。扫描项目并建立知识图谱。

跳过目录：.git, node_modules, dist, build, .next, __pycache__, .venv, vendor, target, .claude

## 0. 守卫
- 当前目录 = $HOME 或 / → 告知用户「请在项目目录中执行」，停止
- ~/Desktop、~/Downloads 等非项目路径 → 下一步特别警告

## 1. 确认
- Glob 统计文件数和子目录数（排除上述跳过目录）
- 输出：「当前目录：{path}，共 {N} 个文件，{M} 个子目录」
- 询问确认，拒绝则停止

## 2. 扫描
- Glob `**/*` 识别有实质内容的目录
- 读取项目元文件（README.md, package.json, Cargo.toml, pyproject.toml, go.mod 等）
- 模块边界：3+ 文件且有独立职责的目录

## 3. 依赖提取
用 Grep 分析真实代码依赖（只记录跨目录的）：
- JS/TS: `import.*from|require\(`
- Python: `from.*import|import`
- Go: `import` 块
- Rust: `use `, `mod `

如果是 git 仓库，补充：
- `git log --pretty=format: --name-only -50` → 共变文件 = 隐式依赖
- `git log --oneline --grep='fix\|bug\|revert' -20` → 失败历史 → 禁忌素材
- commit message 风格 → 团队约定

输出依赖矩阵：模块A → 模块B（证据）

## 4. 生成 CLAUDE.md（幂等：已有则只追加缺失段落）

根 CLAUDE.md 模板：
```markdown
# {项目名}
@README.md
## 全局约定
- {从配置/git 推断}
## 禁忌
- {从结构/git失败历史推断}
```

子模块 CLAUDE.md 模板：
```markdown
# {模块名}
## 禁忌
- {具体可执行的禁忌，不写「注意」「小心」}
## 改动时
- {条件} → 看 @{相对路径CLAUDE.md}
## 约定
- {本模块工作方式}
```

约束：≤30 行 / @ 引用基于步骤 3 的真实依赖 / 禁忌必须具体

## 5. 生成 .claude/rules/（幂等：只补充新规则）
跨模块共性 → 带 `paths:` frontmatter 的条件规则文件

## 6. 初始化数据文件
```bash
mkdir -p .claude
touch .claude/graph-events.jsonl .claude/graph-changelog.jsonl .claude/graph-events-archive.jsonl
```
写入 changelog：首次 `initialized` / 重复 `re-initialized`

## 7. 报告
- X 个模块 / Y 个 CLAUDE.md / Z 条 @ 引用 / W 条 rules / N 个跳过
- 建议：CLAUDE.md 和 .claude/rules/ 提交 Git；运行时数据加 .gitignore
