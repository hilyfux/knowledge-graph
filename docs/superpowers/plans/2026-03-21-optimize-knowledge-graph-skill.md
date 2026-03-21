# Knowledge Graph Skill 全方位优化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Claude 官方 prompt engineering 最佳实践重写 `knowledge-graph.md` skill，提升可靠性、可维护性和执行质量。

**Architecture:** 拆解现有单文件 skill 的三个模式（status/init/evolve），用 XML 标签结构化分区、明确角色定义、内联 evolve 逻辑（消除外部文件依赖）、加入并行工具调用指引和质量自检步骤。

**Tech Stack:** Markdown skill 文件、Claude XML prompt 结构、bash 脚本调用

---

## 当前问题诊断

| 问题 | 影响 | 最佳实践对策 |
|------|------|-------------|
| 无角色定义 | Claude 行为随机 | 开头 `<role>` 定义 |
| 无 XML 结构 | 模式边界模糊，误解率高 | 用 `<mode>` 标签隔离 |
| guard 无原因 | Claude 可能跳过 | 加 "因为..." 解释 |
| evolve 依赖外部文件 | 间接层增加失败点 | 内联全部逻辑 |
| 数据路径散落 | 难维护 | 集中到 `<data_paths>` |
| 无并行读取指引 | status 模式慢 | 显式并行指令 |
| 无质量自检 | 可能写无证据规则 | 每次写入前自检 |
| 残留 lock 引用 | 逻辑错误 | 删除 .evolving 相关 |

---

## 文件结构

**修改：**
- `.claude/commands/knowledge-graph.md` — 主 skill 文件（完全重写）

**同步修改：**
- `standalone/commands/knowledge-graph.md` — 同上内容

---

## Task 1：角色定义 + 全局守卫 + 模式分发

**Files:**
- Modify: `.claude/commands/knowledge-graph.md`

- [ ] **Step 1：在文件头部写角色定义**

```markdown
<role>
你是知识图谱管理引擎。你的职责是维护项目的分布式知识网络——
追踪哪些模块存在、它们如何关联、哪里有盲区需要补充文档。
你的输出直接影响 Claude 未来在此项目中的判断质量，因此准确性
优先于完整性：宁可少写，不可写无证据的规则。
</role>
```

- [ ] **Step 2：写全局守卫（包含原因说明）**

```markdown
<guards>
在执行任何操作之前，检查：
- `$CLAUDE_PROJECT_DIR` 为空、等于 `$HOME` 或 `/` →
  告知用户「知识图谱只能在项目目录中运行，HOME 和根目录不受支持」，停止。
  原因：在非项目目录运行会污染全局 Claude 配置，产生误导性知识节点。
</guards>
```

- [ ] **Step 3：写模式分发（显式检测逻辑）**

```markdown
<dispatch>
检查用户提供的第一个参数（$ARGUMENTS 的首个词）：
- 参数为 `init`           → 执行 <mode name="init">
- 参数为 `evolve`         → 执行 <mode name="evolve">
- 参数为 `status` 或无参数 → 执行 <mode name="status">
- 其他参数               → 输出帮助：「用法：/knowledge-graph [init|status|evolve]」
</dispatch>
```

- [ ] **Step 4：运行验证（角色定义不报错，dispatch 逻辑清晰）**

  人工检查：三个分支都有对应入口？guard 有原因说明？

- [ ] **Step 5：Commit**

```bash
git add .claude/commands/knowledge-graph.md
git commit -m "feat: add role definition, guards with rationale, explicit mode dispatch"
```

---

## Task 2：重写 status 模式（并行采集 + 严格输出格式）

**Files:**
- Modify: `.claude/commands/knowledge-graph.md`

- [ ] **Step 1：写 status 模式数据路径集中声明**

```xml
<mode name="status">
<data_paths>
  cache:    .claude/graph-analysis.json
  events:   .claude/graph-events.jsonl
  changelog:.claude/graph-changelog.jsonl（或 .reported 后缀）
  rules:    .claude/rules/*.md
</data_paths>
```

- [ ] **Step 2：写并行采集指令（官方最佳实践：并行工具调用）**

```markdown
<collection>
并行执行以下所有读取（不要顺序执行，同时发出工具调用）：
1. 读取 `graph-analysis.json`（若存在）
2. Glob `**/CLAUDE.md`（排除 .git、node_modules）
3. 读取 `graph-events.jsonl` 最后 500 行
4. Glob `.claude/rules/*.md`
5. 读取 `graph-changelog.jsonl`（或 .reported）最后 10 行

原因：并行读取避免串行等待，status 模式必须在 3 秒内完成。
</collection>
```

- [ ] **Step 3：写计算逻辑（覆盖率、盲区、健康度）**

```markdown
<analysis>
根据采集结果计算：
- 覆盖率 = 有 CLAUDE.md 的目录数 / 总模块目录数（≥3 个文件的目录）
- 空壳节点 = CLAUDE.md 存在但「## 禁忌」段落为空
- 盲区 = graph-analysis.json 的 blind_spots 字段；
         缓存不存在时：写入次数 > 2 且无对应 CLAUDE.md 的目录
- 过时 = graph-analysis.json 的 stale 字段
- 断裂引用 = graph-analysis.json 的 broken_refs 字段
</analysis>
```

- [ ] **Step 4：写严格输出格式（官方最佳实践：明确格式规范）**

```markdown
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
```

- [ ] **Step 5：Commit**

```bash
git add .claude/commands/knowledge-graph.md
git commit -m "feat: rewrite status mode with parallel collection and strict output format"
```

---

## Task 3：重写 init 模式（步骤明确 + 质量自检）

**Files:**
- Modify: `.claude/commands/knowledge-graph.md`

- [ ] **Step 1：写 init 模式头部（幂等说明 + 扫描步骤）**

```xml
<mode name="init">
<!-- 幂等：可重复执行，只追加缺失段落，不覆盖已有内容 -->

<step id="1" name="扫描">
用 Bash 运行扫描脚本（纯 bash，不消耗 LLM token）：
```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/scan-project.sh"
```
若脚本不可用（报错），用以下命令手动统计，并在步骤 3 自行用 Glob/Grep 扫描：
```bash
find . -type f -not -path '*/.git/*' -not -path '*/node_modules/*' \
  -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.claude/*' | wc -l
```
</step>
```

- [ ] **Step 2：写确认步骤（防止误操作）**

```markdown
<step id="2" name="确认">
读取 `.claude/graph-scan.json`，输出：
「发现 {project_type} 项目，共 {total_files} 个文件，{total_dirs} 个模块。
  已有 {existing_claude_md 数量} 个 CLAUDE.md。即将新增/补充 {差值} 个。继续？(y/n)」

等待用户确认。若拒绝，停止并提示「已取消，未做任何修改」。
</step>
```

- [ ] **Step 3：写 CLAUDE.md 生成规则（含证据要求）**

```markdown
<step id="3" name="生成 CLAUDE.md">
读取 graph-scan.json 的 modules、dependencies、cochange_files、recent_fixes、conventions。

对每个 module（existing_claude_md 中已有的跳过，除非缺少段落则追加）：

并行读取该目录的关键文件（最多 3 个：index/main/README）以理解模块职责。

生成 CLAUDE.md，格式严格如下（≤30 行）：
```markdown
# {模块名}
## 禁忌
- {具体行为} → {具体后果}（来源：{git commit / 错误事件}）
## 改动时
- {触发条件} → 看 @{相对路径/CLAUDE.md}
## 约定
- {本模块的工作方式}
```

<quality_check>
写入前自检每条规则：
1. 禁忌是否有来自 recent_fixes 或 graph-events 的具体证据？无证据 → 删除
2. @ 引用的目标文件是否存在（在 dependencies 或 cochange_files 中可找到）？不存在 → 删除
3. 内容是否只写了代码本身读不到的信息？只是重复代码注释 → 删除

原则：无证据的规则比没有规则更危险。宁缺毋滥。
</quality_check>
</step>
```

- [ ] **Step 4：写收尾步骤**

```markdown
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
```

- [ ] **Step 5：Commit**

```bash
git add .claude/commands/knowledge-graph.md
git commit -m "feat: rewrite init mode with evidence-based quality checks and idempotent steps"
```

---

## Task 4：重写 evolve 模式（内联逻辑，删除外部文件依赖）

**Files:**
- Modify: `.claude/commands/knowledge-graph.md`

- [ ] **Step 1：写 evolve 守卫（含原因）**

```xml
<mode name="evolve">
<guards>
检查前置条件（任一不满足则停止）：
- `.claude/graph-events.jsonl` 不存在或行数 < 5 →
  告知「活动数据不足（需要至少 5 次工具调用记录）。继续使用项目后再运行。」
  原因：数据不足时进化引擎会产生无意义的更新，浪费时间。
</guards>
```

- [ ] **Step 2：写预分析步骤**

```markdown
<step id="1" name="预分析">
运行预分析脚本生成结构化数据（纯 bash，无 LLM）：
```bash
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/pre-analyze.sh"
```
然后读取 `.claude/graph-analysis.json`。
若脚本失败，直接读取 `.claude/graph-events.jsonl` 自行分析。
</step>
```

- [ ] **Step 3：写模式选择 + P1-P4 任务（内联，不引用外部文件）**

```markdown
<step id="2" name="选择执行模式">
根据 event_count 字段：
- 轻量（< 15 events）：只执行 P2 + P3，最多处理 2 个文件
- 标准（≥ 15 events）：执行 P1 → P2 → P3 → P4，最多处理 5 个文件
</step>

<step id="3" name="P1 反馈回路（仅标准模式）">
读取 loaded_knowledge 中每个已加载的 CLAUDE.md，提取「## 禁忌」段落。
对比 dirs 中该目录的 f（失败）事件：禁忌所描述的行为是否仍在发生？
是 → 用 Edit 重写该禁忌，使其更具体可执行。
</step>

<step id="4" name="P2 修复断裂引用和过时节点">
- broken_refs 中的 @ 引用目标不存在 → 删除该行
- stale 列表中的 CLAUDE.md（目录有大量新文件变动）→ 重新读取目录关键文件，用 Edit 刷新内容
</step>

<step id="5" name="P3 填补盲区">
blind_spots 中的目录（高写入频率但无 CLAUDE.md）：
并行用 Grep 分析 import/require 语句发现真实依赖，结合 cochange_files。
生成 CLAUDE.md，格式和质量标准同 init 模式的 <quality_check>。
</step>

<step id="6" name="P4 跨模块规则（仅标准模式）">
多个目录出现相同 top_err → 生成 `.claude/rules/{rule-name}.md`，带 `paths:` frontmatter。
recent_fixes 中反复出现的问题 → 同上。
</step>
```

- [ ] **Step 4：写收尾（删除所有废弃的 lock 逻辑）**

```markdown
<step id="7" name="收尾">
1. 变更追加到 `.claude/graph-changelog.jsonl`（每条一行 JSON）
2. 事件追加到 `.claude/graph-events-archive.jsonl`，然后清空 `graph-events.jsonl`
3. 若 archive 超过 5000 行，保留最后 2000 行
4. 删除 `.claude/graph-analysis.json`（临时缓存）
</step>
</mode>
```

- [ ] **Step 5：确认 evolve 模式中无 `.evolving` lock 任何引用**

  搜索并确认文件中不含字符串 `.evolving`

- [ ] **Step 6：Commit**

```bash
git add .claude/commands/knowledge-graph.md
git commit -m "feat: inline evolve mode, remove external file dependency and stale lock references"
```

---

## Task 5：同步 standalone 目录 + 最终验证

**Files:**
- Modify: `standalone/commands/knowledge-graph.md`

- [ ] **Step 1：将 `.claude/commands/knowledge-graph.md` 内容同步到 `standalone/commands/`**

```bash
cp .claude/commands/knowledge-graph.md standalone/commands/knowledge-graph.md
```

- [ ] **Step 2：全文检查 — 确认以下内容存在**

  - [ ] `<role>` 标签在文件开头
  - [ ] `<guards>` 含 reason 说明
  - [ ] `<dispatch>` 显式参数检测
  - [ ] status 模式有并行读取指令
  - [ ] status 模式有严格 `<output_format>`
  - [ ] init 模式有 `<quality_check>` 自检
  - [ ] evolve 模式完全内联（无 `evolution-prompt.md` 引用）
  - [ ] 全文无 `.evolving` 字符串

- [ ] **Step 3：最终 Commit**

```bash
git add .claude/commands/knowledge-graph.md standalone/commands/knowledge-graph.md
git commit -m "feat: sync standalone skill, complete knowledge-graph skill optimization"
```

---

## 优化前后对比

| 维度 | 优化前 | 优化后 |
|------|--------|--------|
| 结构 | Markdown 标题 | XML 标签，边界清晰 |
| 角色 | 无 | `<role>` 定义职责和价值观 |
| 守卫 | 只说 what | what + why |
| 数据路径 | 分散各处 | `<data_paths>` 集中 |
| 工具调用 | 串行（慢） | 并行（快） |
| 质量保证 | 提到一次 | 每次写入前强制自检 |
| evolve 依赖 | 外部文件 | 完全内联 |
| lock 引用 | 存在（已废弃）| 已清除 |
