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
  changelog: .claude/graph-changelog.jsonl（优先）或 .claude/graph-changelog.jsonl.reported（fallback）
  rules:     .claude/rules/*.md
</data_paths>

<collection>
并行执行以下所有读取（不要顺序执行，同时发出工具调用）：
1. 读取 `graph-analysis.json`（若存在）
2. Glob `**/CLAUDE.md`（排除 .git、node_modules）
3. 读取 `graph-events.jsonl` 最后 500 行
4. Glob `.claude/rules/*.md`
5. 优先读取 `graph-changelog.jsonl`；若不存在则读取 `graph-changelog.jsonl.reported`；取最后 10 行

原因：并行读取避免串行等待，status 模式必须快速完成。
</collection>

<analysis>
根据采集结果计算：
- 覆盖率 = 有 CLAUDE.md 的目录数 / 总模块目录数（≥3 个文件的目录）
- 空壳节点 = CLAUDE.md 存在但「## 禁忌」标题下无任何列表项（即段落内容缺失或只有空行）
- 盲区 = graph-analysis.json 的 blind_spots 字段；
         缓存不存在时：写入次数 > 2 且无对应 CLAUDE.md 的目录
- 过时 = graph-analysis.json 的 stale 字段；缓存不存在时显示 N/A
- 断裂引用 = graph-analysis.json 的 broken_refs 字段；缓存不存在时显示 N/A
</analysis>

<output_format>
严格按以下格式输出，不添加额外解释，不省略任何段落：

## 知识图谱状态

### 覆盖率
{有 CLAUDE.md 的模块数}/{总模块数} ({百分比}%)

### 健康度
过时: {N} | 断裂引用: {N} | 空壳: {N}

### 盲区（高活动未覆盖目录）
{若无盲区，只输出一行：「✓ 无盲区」，不输出列表。若有盲区，只输出列表，不输出「✓ 无盲区」}
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

<mode name="init">
<!-- 幂等：可重复执行，只追加缺失段落，不覆盖已有内容 -->

<step id="1" name="扫描">
用 Bash 运行扫描脚本（纯 bash，不消耗 LLM token）：
```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/scan-project.sh"
```
若脚本不可用（报错），用以下命令手动统计，并在步骤 3 自行用 Glob/Grep 扫描（跳过读取 graph-scan.json）：
```bash
find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.claude/*' | wc -l
```
</step>

<step id="2" name="确认">
读取 `.claude/graph-scan.json`，输出：
「发现 {project_type} 项目，共 {total_files} 个文件，{total_dirs} 个模块。
  已有 {existing_claude_md 数量} 个 CLAUDE.md。即将新增/补充 {差值} 个。继续？(y/n)」

等待用户确认。若拒绝，停止并提示「已取消，未做任何修改」。
</step>

<step id="3" name="生成 CLAUDE.md">
读取 graph-scan.json 的 modules、dependencies、cochange_files、recent_fixes、conventions。

对每个 module（existing_claude_md 中已有的跳过，除非缺少段落则追加）：

并行读取该目录的关键文件（最多 3 个：index/main/README）以理解模块职责。

生成 CLAUDE.md，格式严格如下（≤30 行）：

# {模块名}
## 禁忌
- {具体行为} → {具体后果}（来源：{git commit / 错误事件}）
## 改动时
- {触发条件} → 看 @{相对路径/CLAUDE.md}
## 约定
- {本模块的工作方式}

<quality_check>
写入前自检每条规则：
1. 禁忌是否有来自 recent_fixes 或 graph-events 的具体证据？无证据 → 删除
2. @ 引用的目标文件是否存在（在 dependencies 或 cochange_files 中可找到）？不存在 → 删除
3. 内容是否只写了代码本身读不到的信息？只是重复代码注释 → 删除

原则：无证据的规则比没有规则更危险。宁缺毋滥。
</quality_check>
</step>

<step id="4" name="规则文件">
跨模块出现相同错误模式 → 生成 `.claude/rules/{name}.md`，带 `paths:` frontmatter。
幂等：只补充不存在的规则。
</step>

<step id="5" name="初始化数据文件">
```bash
mkdir -p .claude
touch .claude/graph-events.jsonl .claude/graph-changelog.jsonl .claude/graph-events-archive.jsonl
```
向 changelog 写入一条记录：
```json
{"action":"initialized","path":".","reason":"首次初始化","timestamp":{unix_time}}
```
若已初始化过则写 `re-initialized`。
删除临时文件 `.claude/graph-scan.json`。
</step>

<step id="6" name="报告">
输出：「初始化完成：{X} 个模块 / 新增 {Y} 个 CLAUDE.md / 追加 {Z} 条段落 / {W} 条 rules / {N} 个跳过（已有完整内容）」
</step>

</mode>

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
