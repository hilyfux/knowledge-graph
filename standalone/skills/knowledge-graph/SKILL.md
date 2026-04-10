---
name: knowledge-graph
description: >
  管理项目知识图谱（CLAUDE.md 节点）。维护模块知识、禁忌、依赖关系。
  参数：init（首次全量扫描）/ update（增量刷新）/ status（健康检查）/ query（查询）。
when_to_use: >
  1. 收到"【kg 自动指令】"消息（hook 自动注入）；
  2. 用户主动说"更新/刷新知识图谱"、"图谱状态"、"有多少盲区"；
  3. 用户提到 CLAUDE.md 覆盖率、节点缺失、模块文档。
  不要用于普通编码任务。完成/失败信号由 hook 自动处理，无需 skill 判断。
argument-hint: [init|update|status|query <问题>]
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

<!-- 项目当前状态（启动时自动注入，无需额外工具调用）-->
!`bash "${CLAUDE_SKILL_DIR}/scripts/analyze.sh" quick-status 2>/dev/null || echo "状态读取失败（项目可能未初始化）"`

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
- 参数为 `update`          → 执行 update 模式（见下文）
- 参数为 `query`           → 执行 query 模式（见下文），$ARGUMENTS 去掉首词后为查询问题
- 参数为 `status` 或无参数  → 执行 status 模式（见下文）
- 其他参数                 → 输出帮助：「用法：/knowledge-graph [init|status|update|query <问题>]」
</dispatch>

---

<mode name="status">

<data_paths>
  cache:     .knowledge-graph/graph-analysis.json
  events:    .knowledge-graph/graph-events.jsonl
  rules:     .claude/rules/*.md
</data_paths>

<collection>
并行执行以下所有读取（不要顺序执行，同时发出工具调用）：
1. 读取 `graph-analysis.json`（若存在）
2. Glob `**/CLAUDE.md`（排除 .git、node_modules）
3. 读取 `graph-events.jsonl` 最后 500 行
4. Glob `.claude/rules/*.md`

原因：并行读取避免串行等待，status 模式必须快速完成。
</collection>

<analysis>
根据采集结果计算：
- 覆盖率 = 有 CLAUDE.md 的目录数 / 总模块目录数（≥3 个文件的目录）
- 空壳节点 = CLAUDE.md 存在但「## 禁忌」标题下无任何列表项
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
{若无盲区，只输出一行：「✓ 无盲区」。若有盲区，只输出列表}
- {dir}/ （写入:{N}次，读取:{N}次）

### 热力图 Top 5
| 目录 | 新建 | 修改 | 读取 | 失败 |
|------|------|------|------|------|
| {dir} | {w_new} | {w_edit} | {r} | {f} |
</output_format>

</mode>

---

<mode name="init">
<!-- 幂等：可重复执行，只追加缺失段落，不覆盖已有内容 -->

<step id="1" name="扫描">
用 Bash 运行扫描脚本（纯 bash，不消耗 LLM token）：
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/analyze.sh" scan
```
若脚本不可用（报错），用以下命令手动统计，并在步骤 3 自行用 Glob/Grep 扫描（跳过读取 graph-scan.json）：
```bash
find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.claude/*' | wc -l
```
</step>

<step id="2" name="确认">
读取 `.knowledge-graph/graph-scan.json`，输出：
「当前目录：{project_root}，发现 {project_type} 项目，共 {total_files} 个文件，{total_dirs} 个模块。
  已有 {existing_claude_md 数量} 个 CLAUDE.md。即将新增/补充 {差值} 个。继续？(y/n)」

等待用户确认。若拒绝，停止并提示「已取消，未做任何修改」。
</step>

<step id="3" name="生成 CLAUDE.md">
读取 graph-scan.json 的 modules、dependencies、cochange_files、recent_fixes、conventions。

对每个 module（existing_claude_md 中已有的跳过，除非缺少段落则追加）：

并行读取该目录的关键文件（最多 3 个：index/main/README）以理解模块职责。

生成 CLAUDE.md，格式严格如下（≤20 行，极致精简）：

# {模块名}
## 禁忌
- {行为} → {后果}（{commit hash}）
## 改动时
- {条件} → @{路径}/CLAUDE.md
## 约定
- {规则}

<writing_style>
极致压缩，每个 token 都必须有信息量：
- 省略冠词、连词、语气词（"不要直接" → "禁止直接"）
- 用符号代替文字（→ 代替"导致/会引起"，@ 代替"参考/查看"）
- 来源只写 commit hash 前 7 位，不写完整描述
- 一条规则一行，不换行不解释
- 如果代码注释/变量名已表达清楚的，不写
</writing_style>

<quality_check>
写入前自检：
1. 无证据（recent_fixes / graph-events）→ 删除
2. @ 引用目标不存在 → 删除
3. 代码已表达的信息 → 删除
4. 超过 20 行 → 砍掉最弱的条目

原则：无证据的规则比没有规则更危险。宁缺毋滥。
</quality_check>
</step>

<step id="4" name="规则文件">
跨模块出现相同错误模式 → 生成 `.claude/rules/{name}.md`，带 `paths:` frontmatter。
幂等：只补充不存在的规则。
</step>

<step id="5" name="初始化数据文件">
```bash
mkdir -p "$CLAUDE_PROJECT_DIR/.knowledge-graph"
touch "$CLAUDE_PROJECT_DIR/.knowledge-graph/graph-events.jsonl"
```
删除临时文件 `.knowledge-graph/graph-scan.json`。
</step>

<step id="6" name="生成知识索引">
Glob `**/CLAUDE.md`（排除 .git、node_modules），对每个文件读取 `# 标题` 和首条禁忌。
生成 `.knowledge-graph/knowledge-index.md`，极致精简：

```
# KG Index ({ISO日期})
{路径}: {首条禁忌或约定，≤60字}
{路径}: {首条禁忌或约定，≤60字}
```

不用表格（省 token），一行一个模块，路径即标识。

然后确保 `.claude/CLAUDE.md` 中包含 @include 指令：
若 `.claude/CLAUDE.md` 不存在，创建它。
若已存在但不含 `@.knowledge-graph/knowledge-index.md`，在末尾追加。
这样知识索引成为系统提示词的一部分，自动存活 compact，无需 hook 重新注入。
</step>

<step id="7" name="报告">
输出：「初始化完成：{X} 个模块 / 新增 {Y} 个 CLAUDE.md / 追加 {Z} 条段落 / {W} 条 rules / {N} 个跳过（已有完整内容）」
</step>

</mode>

---

<mode name="update">
<!-- 增量更新：两件事并行处理——扫描新模块 + 基于活动记录刷新现有节点 -->

<step id="1" name="扫描新模块">
并行执行：
1. Glob `**/*`（只取目录，排除 .git、node_modules、dist、build、.claude）
2. Glob `**/CLAUDE.md`（已有知识节点）

找出「含 ≥3 个文件但尚无 CLAUDE.md」的目录 → 新模块列表。
若新模块列表为空，输出「✓ 无新模块」，跳过步骤 2-3。
</step>

<step id="2" name="确认新模块">
输出：「发现 {N} 个新模块：\n{列表}。\n为它们生成 CLAUDE.md？(y/n)」
若拒绝，跳过步骤 3。
</step>

<step id="3" name="为新模块生成 CLAUDE.md">
对每个新模块，并行读取关键文件（最多 3 个：index/main/README）以理解模块职责。

生成 CLAUDE.md（≤20 行，极致精简，同 init 步骤 3 的 writing_style）。
写入前自检：无证据 → 不写。@ 引用目标不存在 → 不写。超 20 行 → 砍最弱条目。
</step>

<step id="4" name="基于事件更新现有节点">
检查 `.knowledge-graph/graph-events.jsonl` 行数：
- 不存在或 < 5 → 输出「活动数据不足，跳过事件分析」，直接进入收尾
- ≥ 5 → 继续：

运行预分析脚本（纯 bash，无 LLM）：
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/analyze.sh" analyze
```
然后读取 `.knowledge-graph/graph-analysis.json`。
若脚本失败，直接读取 `graph-events.jsonl` 自行分析。

根据 event_count 选择：
- 轻量（< 15）：执行 P2 + P3，最多处理 2 个文件
- 标准（≥ 15）：执行 P1 → P2 → P3 → P4，最多处理 5 个文件

**P1 反馈回路（仅标准）**
读取 loaded_knowledge 中每个 CLAUDE.md 的「## 禁忌」，对比该目录的失败事件。
禁忌所描述的行为仍在发生 → 用 Edit 重写使其更具体可执行。

**P2 修复**
- broken_refs 中 @ 引用目标不存在 → 删除该行
- stale 列表中的 CLAUDE.md → 重新读取目录关键文件，用 Edit 刷新

**P3 事件盲区**
blind_spots 中的目录（高写入但无 CLAUDE.md，步骤 1-3 未处理的）：
并行用 Grep 分析 import/require 发现真实依赖，结合 cochange_files，生成 CLAUDE.md（同上质量标准）。

**P4 跨模块规则（仅标准）**
多个目录相同 top_err → `.claude/rules/{name}.md`，带 `paths:` frontmatter。幂等。

**P5 外化提问（默会知识提取）**
分析 graph-events 中同一文件被 w:edit 修改 ≥ 3 次的情况。
对这些文件，向用户提问（输出到对话中，等待回答）：
「你在 {file} 反复修改了 {N} 次，有什么容易踩的坑或需要记住的经验吗？（回复即记录，跳过输入空行）」
用户回答后，将内容追加到该文件所在目录的 CLAUDE.md `## 禁忌` 段。
每次 update 最多问 1 个外化问题，避免打扰。
注意：非交互模式（claude -p / --print）下跳过外化提问，直接进入收尾。

**P6 序列模式推理（仅标准）**
运行推理引擎：
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/infer.sh" sequences
```
发现 read→write 重复模式（count ≥ 2）→ 在 write_dir 的 CLAUDE.md `## 改动时` 段追加：
`- 改动前 → 先看 @{read_dir}/CLAUDE.md`
已存在的引用跳过。

**P7 Co-change 依赖发现（仅标准）**
运行推理引擎：
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/infer.sh" cochange
```
发现 co-change 频率 ≥ 3 的目录对 → 在两个目录的 CLAUDE.md `## 改动时` 段互相引用。
已存在的引用跳过。

**P8 知识衰减检测**
运行推理引擎：
```bash
bash "${CLAUDE_SKILL_DIR}/scripts/infer.sh" decay
```
对结果中的每个模块：
- status=stale（30+ 天无事件）→ 在该 CLAUDE.md 顶部加注释 `<!-- stale: 30+天无活动，待验证 -->`
- status=ineffective（有禁忌但仍在失败）→ 重新读取目录关键文件，用 Edit 重写禁忌使其更具体
- status=effective（有禁忌且零失败）→ 不动，规则有效
</step>

<step id="5" name="收尾">
1. 清空 `.knowledge-graph/graph-events.jsonl`（已分析完毕）
2. 删除 `.knowledge-graph/graph-analysis.json`（临时缓存）
3. 删除 `.knowledge-graph/graph-infer.json`（临时缓存）
4. 重新生成 `.knowledge-graph/knowledge-index.md`（同 init 步骤 6 的格式）
5. 输出：「更新完成：新增 {N} 个模块 / 修复 {N} 个节点 / 新增 {N} 条规则 / 发现 {N} 条隐含依赖 / {N} 个衰减节点」
</step>

</mode>

---

<mode name="query">
<!-- 从知识图谱中检索和综合回答 -->

<step id="1" name="定位">
读取 `.knowledge-graph/knowledge-index.md`。
若不存在，Glob `**/CLAUDE.md`（排除 .git、node_modules）作为备选。
根据用户问题关键词，从索引中筛选相关模块（最多 5 个）。
</step>

<step id="2" name="检索">
并行读取筛选出的 CLAUDE.md 文件。
同时读取 `.claude/rules/*.md` 中与问题相关的规则。
</step>

<step id="3" name="综合回答">
基于检索到的知识节点，综合回答用户问题。
回答格式：
- 直接回答问题
- 列出依据来源：`→ 来自 {路径}/CLAUDE.md`
- 若知识不足以回答，明确说明哪些模块尚无文档（盲区）
</step>

</mode>
