#!/bin/bash
# infer.sh — 事件流推理引擎
# 从 graph-events.jsonl 中挖掘序列模式、co-change 关系、知识衰减
# Usage: infer.sh <cochange|sequences|decay|predict>
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/guard.sh"

EVENTS="$KG_DATA/graph-events.jsonl"
INFER="$KG_DATA/graph-infer.json"

[ ! -f "$EVENTS" ] && echo '{"error":"no events"}' && exit 0

CMD="${1:-cochange}"

case "$CMD" in

  cochange)
    # Co-change 分析：哪些文件总是一起被修改？
    # 在同一个 10 分钟窗口内被修改的文件对 → 隐含依赖
    jq -s '
      [.[] | select(.e | startswith("w"))] |
      sort_by(.t) |
      # 按 600 秒窗口分组
      reduce .[] as $ev (
        {windows: [], current: [], last_t: 0};
        if ($ev.t - .last_t) > 600 and (.current | length) > 0
        then {windows: (.windows + [.current]), current: [$ev], last_t: $ev.t}
        else {windows: .windows, current: (.current + [$ev]), last_t: $ev.t}
        end
      ) | .windows + [.current] |
      # 提取每个窗口中的不同目录对
      map(
        [.[] | .p | split("/") | if length > 1 then .[:-1] | join("/") else "." end] | unique |
        select(length > 1) |
        . as $dirs |
        [range(length) | . as $i | range($i+1; $dirs | length) | [$dirs[$i], $dirs[.]] | sort] |
        .[]
      ) | group_by(.) | map({pair: .[0], count: length}) |
      sort_by(-.count) | .[0:10]
    ' "$EVENTS" 2>/dev/null || echo "[]"
    ;;

  sequences)
    # 序列模式挖掘：read A → read B → write C 的重复模式
    # 发现隐含的"前置知识"关系
    jq -s '
      # 提取 read→write 序列（按时间排序，30 秒窗口内）
      [.[] | select(.e == "r" or .e | startswith("w"))] |
      sort_by(.t) |
      # 滑动窗口：找 write 前的 read 序列
      . as $events |
      [range(length) | . as $i |
        select($events[$i].e | startswith("w")) |
        $events[$i] as $write |
        $write.p | split("/") | (if length > 1 then .[:-1] | join("/") else "." end) as $write_dir |
        # 向前看最多 5 个事件，30 秒内的 read
        [range(([0, $i-5] | max); $i) |
          $events[.] | select(.e == "r") |
          select(($write.t - .t) < 30) |
          .p | split("/") | (if length > 1 then .[:-1] | join("/") else "." end)
        ] | unique | map(select(. != $write_dir)) |
        select(length > 0) |
        {write_dir: $write_dir, read_dirs: ., t: $write.t}
      ] |
      # 聚合：哪些 read→write 模式重复出现？
      group_by({write_dir, read_dirs}) |
      map({
        write_dir: .[0].write_dir,
        read_dirs: .[0].read_dirs,
        count: length
      }) |
      sort_by(-.count) | map(select(.count >= 2)) | .[0:10]
    ' "$EVENTS" 2>/dev/null || echo "[]"
    ;;

  decay)
    # 知识衰减检测：CLAUDE.md 中的规则是否仍然有效？
    # 对比禁忌规则和该目录的失败事件
    RESULTS="[]"
    NOW=$(date +%s)
    THIRTY_DAYS=$((30 * 86400))

    for cmd_file in $(find "$CLAUDE_PROJECT_DIR" -name "CLAUDE.md" \
      -not -path "*/.git/*" -not -path "*/node_modules/*" 2>/dev/null | head -20); do
      REL="${cmd_file#$CLAUDE_PROJECT_DIR/}"
      DIR=$(dirname "$REL")
      [ "$DIR" = "." ] && continue

      # 统计该目录的事件
      STATS=$(jq -s --arg dir "$DIR" --argjson now "$NOW" --argjson window "$THIRTY_DAYS" '
        [.[] | select(.p != null) |
          select((.p | split("/") | if length > 1 then .[:-1] | join("/") else "." end) == $dir)
        ] |
        {
          total: length,
          failures: [.[] | select(.e == "f")] | length,
          writes: [.[] | select(.e | startswith("w"))] | length,
          last_event: (map(.t) | max // 0),
          days_silent: ((($now - (map(.t) | max // $now)) / 86400) | floor)
        }
      ' "$EVENTS" 2>/dev/null)

      DAYS_SILENT=$(echo "$STATS" | jq '.days_silent')
      FAILURES=$(echo "$STATS" | jq '.failures')
      WRITES=$(echo "$STATS" | jq '.writes')

      # 判定状态
      STATUS="active"
      if [ "$DAYS_SILENT" -gt 30 ]; then
        STATUS="stale"
      elif [ "$FAILURES" -gt 0 ] && [ "$WRITES" -gt 3 ]; then
        STATUS="ineffective"  # 有禁忌但仍然失败
      elif [ "$FAILURES" -eq 0 ] && [ "$WRITES" -gt 2 ]; then
        STATUS="effective"    # 有禁忌且零失败
      fi

      RESULTS=$(echo "$RESULTS" | jq --arg dir "$DIR" --arg status "$STATUS" \
        --argjson days "$DAYS_SILENT" --argjson failures "$FAILURES" --argjson writes "$WRITES" \
        '. + [{dir: $dir, status: $status, days_silent: $days, failures: $failures, writes: $writes}]')
    done

    echo "$RESULTS" | jq 'sort_by(-.failures)'
    ;;

  predict)
    # 预测性上下文：基于当前触碰的文件，预测接下来需要哪些模块的知识
    # 输入：stdin 传入当前文件路径
    TARGET_DIR=$(cat | jq -r '.file_path // ""' 2>/dev/null | sed "s|^$CLAUDE_PROJECT_DIR/||" | xargs dirname 2>/dev/null)
    [ -z "$TARGET_DIR" ] && exit 0

    # 从 co-change 数据找关联目录
    jq -s --arg dir "$TARGET_DIR" '
      [.[] | select(.e | startswith("w"))] |
      sort_by(.t) |
      # 找同一 600 秒窗口内和 target_dir 一起出现的其他目录
      reduce .[] as $ev (
        {windows: [], current: [], last_t: 0};
        if ($ev.t - .last_t) > 600 and (.current | length) > 0
        then {windows: (.windows + [.current]), current: [$ev], last_t: $ev.t}
        else {windows: .windows, current: (.current + [$ev]), last_t: $ev.t}
        end
      ) | .windows + [.current] |
      # 只看包含 target_dir 的窗口
      map(
        . as $w |
        [.[] | .p | split("/") | if length > 1 then .[:-1] | join("/") else "." end] | unique |
        select(any(. == $dir)) |
        map(select(. != $dir))
      ) | add // [] |
      group_by(.) | map({dir: .[0], freq: length}) |
      sort_by(-.freq) | .[0:5]
    ' "$EVENTS" 2>/dev/null || echo "[]"
    ;;

esac

exit 0
