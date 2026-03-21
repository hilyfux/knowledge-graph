---
name: run-evolution
description: 手动触发知识图谱进化：分析活动数据，更新 CLAUDE.md，修复断裂引用，填补盲区。
---

知识图谱手动进化。

## 守卫
- 当前目录 = $HOME 或 / → 告知「请在项目目录中执行」，停止
- `.claude/.evolving` 存在且不超过 10 分钟 → 告知「进化正在进行中，请稍后再试」，停止
- `.claude/graph-events.jsonl` 不存在或行数 < 5 → 告知「活动数据不足，继续使用项目后再执行」，停止

## 执行
直接执行进化引擎 prompt（与自动进化逻辑完全一致）：

用 Bash 运行预分析脚本生成缓存数据：
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pre-analyze.sh"
```

然后按以下步骤执行：

1. 创建锁 `.claude/.evolving`（用 Bash: `touch .claude/.evolving`）
2. 读取 `.claude/graph-analysis.json`（预计算数据），不存在则读 `.claude/graph-events.jsonl` 自行分析
3. 根据 event_count 选择模式：
   - **轻量**（< 15）：只做 P2 + P3，最多 2 个文件
   - **标准**（≥ 15）：执行 P1-P4，最多 5 个文件

### P1 反馈回路（仅标准模式）
读取 loaded_knowledge 中 CLAUDE.md 的禁忌段落，对比 dirs 中对应目录的写入/失败。违反 → 用 Edit 重写使其更清晰具体。

### P2 断裂引用和过时节点
修复 broken_refs 中的 @ 引用（删除或更正）。更新 stale 列表中的 CLAUDE.md。

### P3 盲区
为 blind_spots 中的目录生成 CLAUDE.md。用 Grep 分析 import/require 发现真实依赖。

### P4 跨模块规则（仅标准模式）
多目录相同 top_err → `.claude/rules/`。

## 输出规范
- CLAUDE.md：`## 禁忌 / ## 改动时 / ## 约定`，≤30 行，禁忌必须有证据
- @ 引用必须有 import/require 或 cochange 证据
- 用 Edit 最小更新

## 收尾
1. 变更追加到 `.claude/graph-changelog.jsonl`
2. 事件追加到 `.claude/graph-events-archive.jsonl`，清空 `graph-events.jsonl`
3. 删除 `.claude/graph-analysis.json`
4. 删除锁：`rm -f .claude/.evolving`

## 完成报告
输出：处理了 X 个文件，新增/更新 Y 个 CLAUDE.md，修复 Z 个引用。
