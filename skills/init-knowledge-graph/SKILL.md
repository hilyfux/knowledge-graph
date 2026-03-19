---
name: init-knowledge-graph
description: 初始化项目知识图谱。扫描项目结构，生成 CLAUDE.md 和条件规则。幂等，可重复执行。
---

知识图谱初始化引擎。

## 0. 守卫
- 当前目录 = $HOME 或 / → 告知「请在项目目录中执行」，停止
- ~/Desktop、~/Downloads 等 → 下一步特别警告

## 1. 扫描（bash 执行，不消耗 LLM token）
用 Bash 执行：`bash "${CLAUDE_PLUGIN_ROOT:-$(find ~/.claude/plugins -name scan-project.sh -path '*/knowledge-graph/*' 2>/dev/null | head -1 | xargs dirname)}/scripts/scan-project.sh"`

如果脚本不可用，用 Bash 执行：`find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.claude/*' | wc -l` 手动统计。

## 2. 确认
读取 .claude/graph-scan.json，输出：
「当前目录：{path}，{project_type} 项目，{total_files} 个文件，{total_dirs} 个模块」
询问确认。拒绝则停止。

## 3. 生成 CLAUDE.md（你的核心工作）

读取 graph-scan.json 的 modules、dependencies、cochange_files、recent_fixes、conventions 字段。

对每个 module（跳过 existing_claude_md 中已有的，除非追加缺失段落）：
1. 读取该目录的几个关键文件（入口文件、index、README），理解模块职责
2. 用 dependencies 字段生成 @ 引用（不用自己 Grep）
3. 用 cochange_files 补充隐式依赖的 @ 引用
4. 用 recent_fixes 中涉及该目录的修复提交生成禁忌
5. 生成 CLAUDE.md：

```markdown
# {模块名}
## 禁忌
- {具体可执行，有证据}
## 改动时
- {条件} → 看 @{相对路径}
## 约定
- {本模块工作方式}
```

约束：≤30 行 / 禁忌必须具体 / 已有 CLAUDE.md 只追加

根 CLAUDE.md：加入 conventions 字段发现的团队约定。

## 4. 生成 .claude/rules/（幂等：只补充）
跨模块共性 → `paths:` frontmatter 条件规则

## 5. 数据文件
```bash
mkdir -p .claude && touch .claude/graph-events.jsonl .claude/graph-changelog.jsonl .claude/graph-events-archive.jsonl
```
写入 changelog：首次 `initialized` / 重复 `re-initialized`
删除 .claude/graph-scan.json（临时文件）

## 6. 报告
- X 模块 / Y 个 CLAUDE.md / Z 条 @ 引用 / W 条 rules / N 个跳过
- 建议：CLAUDE.md 和 .claude/rules/ 提交 Git；运行时数据加 .gitignore
