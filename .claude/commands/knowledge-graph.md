<role>
你是知识图谱管理引擎。你的职责是维护项目的分布式知识网络——
追踪哪些模块存在、它们如何关联、哪里有盲区需要补充文档。
你的输出直接影响 Claude 未来在此项目中的判断质量，因此准确性
优先于完整性：宁可少写，不可写无证据的规则。
只维护 .claude/ 目录下的知识文件，不修改项目源代码。
</role>

<guards>
在执行任何操作之前，检查：
（$CLAUDE_PROJECT_DIR 由 Claude Code 自动注入，等于当前项目根目录）
- `$CLAUDE_PROJECT_DIR` 为空、等于 `$HOME` 或 `/` →
  告知用户「知识图谱只能在项目目录中运行，HOME 和根目录不受支持」，停止。
  原因：在非项目目录运行会污染全局 Claude 配置，产生误导性知识节点。
</guards>

<dispatch>
检查用户提供的第一个参数（$ARGUMENTS 的首个词）：
参数匹配大小写不敏感，忽略额外参数（如 init --force 按 init 处理）。
- 参数为 `init`            → 执行 init 模式（见下文）
- 参数为 `evolve`          → 执行 evolve 模式（见下文）
- 参数为 `status` 或无参数  → 执行 status 模式（见下文）
- 其他参数                 → 输出帮助：「用法：/knowledge-graph [init|status|evolve]」
</dispatch>

# 知识图谱

根据参数执行不同操作：

- 无参数 / `status`：查看知识图谱状态报告
- `init`：初始化知识图谱（扫描项目，生成 CLAUDE.md）
- `evolve`：手动触发进化引擎

---

<mode name="status">

<data_paths>
  cache:     .claude/graph-analysis.json
  events:    .claude/graph-events.jsonl
  changelog: .claude/graph-changelog.jsonl（或 .reported 后缀）
  rules:     .claude/rules/*.md
</data_paths>

<collection>
并行执行以下所有读取（不要顺序执行，同时发出工具调用）：
1. 读取 `graph-analysis.json`（若存在）
2. Glob `**/CLAUDE.md`（排除 .git、node_modules）
3. 读取 `graph-events.jsonl` 最后 500 行
4. Glob `.claude/rules/*.md`
5. 读取 `graph-changelog.jsonl`（或 .reported）最后 10 行

原因：并行读取避免串行等待，status 模式必须快速完成。
</collection>

<analysis>
根据采集结果计算：
- 覆盖率 = 有 CLAUDE.md 的目录数 / 总模块目录数（≥3 个文件的目录）
- 空壳节点 = CLAUDE.md 存在但「## 禁忌」段落为空
- 盲区 = graph-analysis.json 的 blind_spots 字段；
         缓存不存在时：写入次数 > 2 且无对应 CLAUDE.md 的目录
- 过时 = graph-analysis.json 的 stale 字段
- 断裂引用 = graph-analysis.json 的 broken_refs 字段
</analysis>

<output_format>
严格按以下格式输出，不添加额外解释，不省略任何段落：

## 知识图谱状态

### 覆盖率
{有 CLAUDE.md 的模块数}/{总模块数} ({百分比}%)

### 健康度
过时: {N} | 断裂引用: {N} | 空壳: {N}

### 盲区（高活动未覆盖目录）
{若无盲区：「✓ 无盲区」}
- {dir}/ （写入:{N}次，读取:{N}次）

### 热力图 Top 5
| 目录 | 新建 | 修改 | 读取 | 失败 |
|------|------|------|------|------|
| {dir} | {w_new} | {w_edit} | {r} | {f} |

### 最近进化
{若无记录：「尚未进化，运行 /knowledge-graph evolve 开始」}
- [{timestamp}] {action}: {path} ({reason})
</output_format>

</mode>

---

## init 模式

### 1. 扫描（bash，不消耗 LLM token）
```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/scan-project.sh"
```
脚本不可用时手动统计文件数，步骤 3 自行用 Glob/Grep 扫描（跳过读取 graph-scan.json）。

### 2. 确认
读取 `.claude/graph-scan.json`，输出：
「当前目录：{path}，{project_type} 项目，{total_files} 个文件，{total_dirs} 个模块」
询问确认。拒绝则停止。

### 3. 生成 CLAUDE.md
读取 graph-scan.json 的 modules、dependencies、cochange_files、recent_fixes、conventions。
对每个 module（跳过 existing_claude_md 中已有的，除非追加缺失段落）：
1. 读取该目录的几个关键文件，理解模块职责
2. 用 dependencies 字段生成 @ 引用
3. 用 cochange_files 补充隐式依赖的 @ 引用
4. 用 recent_fixes 生成禁忌
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

根 CLAUDE.md：加入 conventions 发现的团队约定。

### 4. 生成 .claude/rules/（幂等：只补充）
跨模块共性 → `paths:` frontmatter 条件规则

### 5. 初始化数据文件
```bash
mkdir -p .claude && touch .claude/graph-events.jsonl .claude/graph-changelog.jsonl .claude/graph-events-archive.jsonl
```
写入 changelog：首次 `initialized` / 重复 `re-initialized`
删除 `.claude/graph-scan.json`

### 6. 报告
X 模块 / Y 个 CLAUDE.md / Z 条 @ 引用 / W 条 rules / N 个跳过

---

## evolve 模式

### 守卫
- `.claude/.evolving` 存在且不超过 10 分钟 → 告知「进化进行中」，停止
- `.claude/graph-events.jsonl` 行数 < 5 → 告知「活动数据不足」，停止

### 执行
```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/pre-analyze.sh"
```
然后按进化引擎逻辑执行（见 `.claude/scripts/evolution-prompt.md` 完整规范）：

1. `touch .claude/.evolving`
2. 读取 `.claude/graph-analysis.json`
3. 按 event_count 选择模式：
   - **轻量**（< 15）：P2 + P3，最多 2 个文件
   - **标准**（≥ 15）：P1-P4，最多 5 个文件

**P1** 反馈回路：禁忌被违反 → 重写使其更清晰
**P2** 修复 broken_refs、更新 stale
**P3** 为 blind_spots 生成 CLAUDE.md
**P4** 跨模块规则 → `.claude/rules/`

### 收尾
1. 变更追加到 `.claude/graph-changelog.jsonl`
2. 事件归档，清空 `graph-events.jsonl`
3. 删除 `.claude/graph-analysis.json`
4. `rm -f .claude/.evolving`
