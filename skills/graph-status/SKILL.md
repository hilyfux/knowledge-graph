---
name: graph-status
description: 查看知识图谱状态：覆盖率、健康度、热力图、盲区。
---

知识图谱状态报告。

## 守卫
- 当前目录 = $HOME 或 / → 告知用户「请在项目目录中执行」，停止
- 无任何 CLAUDE.md → 告知用户先执行 /knowledge-graph:init-knowledge-graph，停止

## 数据采集
1. Glob `**/CLAUDE.md` — 节点列表
2. Glob `.claude/rules/*.md` — 规则列表
3. 识别模块目录（3+ 文件，排除 .git/node_modules/dist/build/.claude），对比 CLAUDE.md 覆盖
4. 读取 `.claude/graph-events.jsonl` 最近 500 行，按目录聚合：
   - w:new / w:edit / r / s / i / f，失败按 err 分组
5. 读取 `.claude/graph-changelog.jsonl`（或 .reported）最近 10 条
6. 健康检查：@ 引用是否存在（断裂）/ CLAUDE.md 是否过时 / 禁忌段落是否为空

## 输出

```
## 知识图谱状态报告

### 覆盖率
X/Y 模块 (Z%)

### 健康度
- 过时节点: X 个（活跃目录但 CLAUDE.md 长期未更新）
- 断裂引用: Y 个
- 空壳节点: Z 个（禁忌段落为空）

### 盲区
- dir/ (写入:N, 读取:M)

### 热力图 Top 5
| 目录 | 新建 | 修改 | 读取 | 失败 |
|------|------|------|------|------|

### 失败模式 Top 3
| 目录 | 错误 | 次数 |

### 最近进化
- [时间] action: path (reason)
```
