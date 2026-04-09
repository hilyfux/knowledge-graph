# Sample Session Walkthrough

## 1. Initialize

```
> /knowledge-graph init

当前目录：/Users/dev/my-app，发现 TypeScript 项目，共 142 个文件，8 个模块。
已有 0 个 CLAUDE.md。即将新增 8 个。继续？(y/n)

> y

初始化完成：8 个模块 / 新增 8 个 CLAUDE.md / 追加 0 条段落 / 2 条 rules / 0 个跳过
```

## 2. Generated CLAUDE.md example

```markdown
# auth

## Prohibitions
- Don't store raw tokens in localStorage → XSS exposure (source: commit a3f21b)
- Don't skip token refresh in test mocks → causes flaky CI (source: fix in commit 8c4e01)

## When Changing
- Modifying token flow → check @middleware/CLAUDE.md
- Changing user model → check @api/users/CLAUDE.md

## Conventions
- All auth errors return 401 with { code, message } shape
- Refresh tokens use httpOnly cookies, never exposed to JS
```

## 3. Normal coding session

You work normally. Hooks silently track file writes, edits, and failures:

```
[kg] 已积累 15 条变更记录，活跃区域：src/api(8次)、src/auth(4次)。
【kg 自动指令】请立即执行知识图谱增量更新...
```

Claude automatically runs `/knowledge-graph update` — no manual action needed.

## 4. Completion signal triggers update

```
> 搞定了，这个功能可以了

(prompt-trigger.sh detects completion signal)
(Claude finishes responding, then runs knowledge-graph update)

更新完成：新增 1 个模块 / 修复 0 个节点 / 新增 0 条规则
```

## 5. Failure signal captures lessons

```
> 还是不行，又报错了

(prompt-trigger.sh detects failure signal)
(Claude responds to the error, then runs update to record the lesson)
```

The failure pattern gets recorded in the relevant `CLAUDE.md` prohibitions section.

## 6. Check status

```
> /knowledge-graph status

## 知识图谱状态

### 覆盖率
9/10 (90%)

### 健康度
过时: 1 | 断裂引用: 0 | 空壳: 0

### 盲区（高活动未覆盖目录）
- src/utils/ （写入:5次，读取:12次）

### 热力图 Top 5
| 目录       | 新建 | 修改 | 读取 | 失败 |
|-----------|------|------|------|------|
| src/api   | 2    | 6    | 15   | 1    |
| src/auth  | 0    | 4    | 8    | 0    |
| src/views | 3    | 3    | 5    | 0    |
| src/store | 1    | 2    | 4    | 0    |
| src/types | 0    | 1    | 3    | 0    |
```

## 7. Query the knowledge graph

```
> /knowledge-graph query 哪个模块负责用户认证？

认证由 src/auth 模块负责。

关键约束：
- token 存储使用 httpOnly cookie，不暴露给 JS
- 所有认证错误统一返回 401 + { code, message }
- 修改 token 逻辑时需同步检查 middleware

→ 来自 src/auth/CLAUDE.md
→ 来自 src/middleware/CLAUDE.md
```

## 8. Next session

When you start a new Claude Code session, `context.sh` automatically injects:

```
[知识索引]
| 模块 | 路径 | 摘要 |
|------|------|------|
| auth | src/auth/CLAUDE.md | Don't store raw tokens in localStorage |
| api  | src/api/CLAUDE.md  | REST endpoints, validate input at boundary |
| ...  | ...                | ...                                       |

[活跃区域]
  8次写入 src/api
  4次写入 src/auth

[最近提交]
a3f21b fix: prevent XSS via token storage
8c4e01 fix: stabilize auth test mocks
```

Claude immediately knows where to look and what to avoid — no re-discovery needed.
