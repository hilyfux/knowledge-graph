---
name: graph-status
description: 查看知识图谱的当前状态：覆盖率、热力图、盲区、最近更新。
allowed-tools: Read, Glob, Grep, Bash(wc *), Bash(cat *), Bash(find *), Bash(tail *)
---

分析当前项目的知识图谱状态并输出报告。

## 步骤

1. 用 Glob 统计所有 CLAUDE.md 文件数量和位置（`**/CLAUDE.md`）
2. 用 Glob 统计所有 `.claude/rules/*.md` 文件数量
3. 用 Glob 统计有 3+ 文件的目录，排除 .git/node_modules/dist/build/.claude，与已有 CLAUDE.md 对比找出盲区
4. 读取 `.claude/graph-events.jsonl`（最近 500 行），统计各目录的写入/读取/搜索/加载/失败次数
5. 读取 `.claude/graph-changelog.jsonl`，列出最近 10 条更新记录
6. 计算覆盖率 = 有 CLAUDE.md 的模块目录数 / 总模块目录数

## 输出格式

```
## 知识图谱状态报告

### 覆盖率
X/Y 个模块已覆盖 (Z%)

### 知识节点
- path/to/CLAUDE.md
- ...

### 条件规则
- .claude/rules/xxx.md (paths: ...)
- ...

### 盲区（无 CLAUDE.md 的活跃目录）
- path/to/uncovered/dir/ (写入: N, 读取: M)
- ...

### 热力图 Top 5
| 目录 | 写入 | 读取 | 加载 | 失败 |
|------|------|------|------|------|
| ... | ... | ... | ... | ... |

### 最近进化记录
- [时间] action: path (reason)
- ...
```
