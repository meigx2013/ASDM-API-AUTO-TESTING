#!/usr/bin/env bash
# scripts/lib/loader.sh — api.json 展平加载器（D1）
#
# load_interfaces: 递归展平 docs/api.json item 树 → $IFACE_TSV（域/服务/模块/接口四元组+请求结构）
# list_first:      打印清单首条四元组（自检用）
# 统计落盘:        $WORK_DIR/iface-stats.txt（总数/方法分布/域分布/服务分布，供对账）

# 展平并装载接口清单（重复调用幂等：重新生成）
load_interfaces() {
  if [ ! -f "$ASDM_TEST_ROOT/docs/api.json" ]; then
    log_line "[L0] 致命错误: 接口资产文件不存在 docs/api.json"
    return 2
  fi
  node "$ASDM_TEST_ROOT/scripts/lib/flatten.js" \
    "$ASDM_TEST_ROOT/docs/api.json" \
    "$IFACE_TSV" \
    "$WORK_DIR/iface-stats.txt" >/dev/null || return 2
  TOTAL="$(grep -c . "$IFACE_TSV" || true)"
  IFACE_STATS="$WORK_DIR/iface-stats.txt"
  return 0
}

# 打印首条接口四元组（域/服务/方法/路径）
list_first() {
  local first line
  first="$(head -1 "$IFACE_TSV" 2>/dev/null)" || return 1
  IFS=$'\037' read -r domain svc svcfull module name method rawurl _rest <<<"$first"
  printf '域=%s 服务=%s 方法=%s 路径=%s 名称=%s 模块=%s\n' \
    "$domain" "$svc" "$method" "$rawurl" "$name" "$module"
}

# 域过滤：按 --domains 逗号分隔清单筛选行到 $IFACE_SELECTED（保持原序）
filter_interfaces() {
  local filter="$1"
  local selected="$WORK_DIR/interfaces-selected.tsv"
  : >"$selected"
  local d
  local IFS=','
  for d in $filter; do
    d="$(printf '%s' "$d" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$d" ] && awk -F'\037' -v dom="$d" '$1 == dom' "$IFACE_TSV" >>"$selected"
  done
  IFACE_SELECTED="$selected"
  TOTAL_SELECTED="$(grep -c . "$selected" || true)"
}
