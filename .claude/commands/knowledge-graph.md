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
- 参数为 `status` 或无参数  → 执行 status 模式（见下文）
- 其他参数                 → 输出帮助：「用法：/knowledge-graph [init|status|update]」
</dispatch>

# 知识图谱

根据参数执行不同操作：

- 无参数 / `status`：查看知识图谱状态报告
- `init`：首次初始化（全量扫描项目，生成所有 CLAUDE.md）
- `update`：增量更新（检测新模块 + 基于活动记录刷新现有节点）

---

<mode name="status">

<data_paths>
  cache:     .claude/graph-analysis.json
  events:    .claude/graph-events.jsonl
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
「当前目录：{project_root}，发现 {project_type} 项目，共 {total_files} 个文件，{total_dirs} 个模块。
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
touch .claude/graph-events.jsonl
```
删除临时文件 `.claude/graph-scan.json`（若步骤 1 使用了备用手动统计则此文件不存在，跳过删除）。
</step>

<step id="6" name="报告">
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

生成 CLAUDE.md（≤30 行）：

# {模块名}
## 禁忌
- {具体行为} → {具体后果}（来源：{git commit / 代码分析}）
## 改动时
- {触发条件} → 看 @{相对路径/CLAUDE.md}
## 约定
- {本模块的工作方式}

写入前自检：
- 每条禁忌必须有代码分析或 git 历史的具体证据，无证据 → 不写
- 每条 @ 引用的目标文件必须存在，不存在 → 不写
- 只写代码本身读不到的信息
原则：无证据的规则比没有规则更危险。宁缺毋滥。
</step>

<step id="4" name="基于事件更新现有节点">
检查 `.claude/graph-events.jsonl` 行数：
- 不存在或 < 5 → 输出「活动数据不足，跳过事件分析」，直接进入收尾
- ≥ 5 → 继续：

运行预分析脚本（纯 bash，无 LLM）：
```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/pre-analyze.sh"
```
然后读取 `.claude/graph-analysis.json`。
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
</step>

<step id="5" name="收尾">
1. 清空 `graph-events.jsonl`（已分析完毕，无需归档）
2. 删除 `.claude/graph-analysis.json`（临时缓存）
3. 输出：「更新完成：新增 {N} 个模块 / 修复 {N} 个节点 / 新增 {N} 条规则」
</step>

</mode>