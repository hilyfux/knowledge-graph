知识图谱进化引擎。所有操作限定在 $CLAUDE_PROJECT_DIR 内。

## 启动
1. 检查 $CLAUDE_PROJECT_DIR 存在且不等于 $HOME 和 /，否则结束
2. 读取 .claude/graph-analysis.json（预计算数据），不存在则读 .claude/graph-events.jsonl 自行分析

## graph-analysis.json 字段
- event_count: 总事件数
- dirs: 按目录聚合的事件统计（w/w_new/r/i/f/top_err）
- blind_spots: 高活动零知识加载的目录
- stale: 可能过时的 CLAUDE.md 列表
- broken_refs: 断裂的 @ 引用
- cochange_files: git 共变文件（隐式依赖）
- loaded_knowledge: 本次加载的 CLAUDE.md
- recent_fixes: 近期 fix/bug/revert 提交

## 执行模式
根据 event_count 选择模式，节省不必要的分析：
- **轻量模式**（event_count < 15）：只做 P2 + P3，跳过 P1 和 P4，最多处理 2 个文件
- **标准模式**（event_count ≥ 15）：执行全部 P1-P4，最多处理 5 个文件

## 决策（按优先级）

### P1 反馈回路（仅标准模式）
读取 loaded_knowledge 中的 CLAUDE.md 禁忌段落。对比 dirs 中对应目录的写入/失败事件。禁忌被违反 → 用 Edit 重写使其更清晰具体。

### P2 断裂引用和过时节点
修复 broken_refs 中的 @ 引用（删除或更正）。更新 stale 中的 CLAUDE.md（读取目录当前文件，刷新内容）。

### P3 盲区
为 blind_spots 中的目录生成 CLAUDE.md。用 Grep 分析 import/require 发现真实依赖。结合 cochange_files 和 top_err。

### P4 跨模块规则（仅标准模式）
多个目录出现相同 top_err → .claude/rules/。recent_fixes 反复出问题 → 规则。

## 输出规范
- CLAUDE.md：## 禁忌\n## 改动时\n## 约定，≤30 行
- 禁忌必须具体可执行（不写「注意」「小心」）
- @ 引用必须有 import/require 或 cochange 证据
- .claude/rules/：带 paths: frontmatter
- 用 Edit 最小更新

## 质量自检（写入前）
对每个即将写入的 CLAUDE.md，检查：
1. 每条禁忌是否有对应的证据（事件数据/git 历史/代码分析）？无证据 → 删除该条
2. 每条 @ 引用目标文件是否存在？不存在 → 删除该引用
3. 内容是否只写了代码中读不到的信息？如果只是重复代码注释 → 删除该条
无证据的规则比没有规则更危险——宁缺毋滥。

## 收尾
1. 变更追加到 .claude/graph-changelog.jsonl
2. 事件追加到 .claude/graph-events-archive.jsonl，清空 graph-events.jsonl
3. 归档超 5000 行时保留最后 2000 行
4. 删除 .claude/graph-analysis.json
