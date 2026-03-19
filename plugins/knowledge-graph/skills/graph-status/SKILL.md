---
name: graph-status
description: 查看知识图谱状态：覆盖率、健康度、热力图、盲区。
---

知识图谱状态报告。

## 守卫
- 当前目录 = $HOME 或 / → 告知「请在项目目录中执行」，停止
- 无任何 `**/CLAUDE.md` → 告知先执行 /knowledge-graph:init-knowledge-graph，停止

## 数据采集（优先用缓存）

**如果 .claude/graph-analysis.json 存在**（进化引擎或 Stop hook 生成的缓存），直接读取它。其中已包含目录统计、盲区、过时节点、断裂引用、共变文件。跳到「补充采集」。

**如果缓存不存在**，手动采集：
1. Glob `**/CLAUDE.md` → 节点列表
2. 读取 `.claude/graph-events.jsonl` 最近 500 行，按目录聚合 w:new/w:edit/r/i/f
3. 对比模块目录（3+ 文件）和 CLAUDE.md 覆盖 → 盲区

**补充采集**（无论缓存是否存在）：
- Glob `.claude/rules/*.md` → 规则列表
- 覆盖率 = 有 CLAUDE.md 的模块数 / 总模块数
- 检查 CLAUDE.md 禁忌段落是否为空 → 空壳节点
- `.claude/graph-changelog.jsonl`（或 .reported）最近 10 条

## 输出

```
## 知识图谱状态报告

### 覆盖率
X/Y 模块 (Z%)

### 健康度
- 过时: X | 断裂引用: Y | 空壳: Z

### 盲区
- dir/ (写入:N, 读取:M)

### 热力图 Top 5
| 目录 | 新建 | 修改 | 读取 | 失败 |
|------|------|------|------|------|

### 失败 Top 3
| 目录 | 错误 | 次数 |

### 最近进化
- [时间] action: path (reason)
```
