#!/usr/bin/env bash
# scripts/run.sh — ASDM 接口自动化测试唯一入口（FT-060）
#
# 五层管线: L0 环境与工具校验 → L1 登录鉴权 → L2 数据准备(Phase 2) → L3 业务域 → L4 清理(Phase 2)
#
# 退出码: 0=全部 PASS/SKIP  1=存在 FAIL  2=L0/L1 关键失败（用法/配置/登录）
#
# Phase 1 实现范围: 工程骨架、api.json 展平、变量替换、单接口执行通路、登录鉴权与 TOKEN 捕获。
# Phase 1 安全阀: L3 仅执行 GET 接口（非 GET 接口 SKIP，等待 Phase 2 自建数据闭环）；
#                判定为简化版（HTTP <400 即 PASS），Phase 2 由断言引擎接管三态判定。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/loader.sh"
source "$SCRIPT_DIR/lib/vars.sh"
source "$SCRIPT_DIR/lib/auth.sh"

# 运行结束清理本次临时工作目录（日志与统计已落 logs/，独立 source 调试场景不受影响）
trap 'rm -rf "$WORK_DIR"; rmdir "$ASDM_TEST_ROOT/.work" 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# CLI 参数解析（优先级: CLI --key=value > 环境变量 > config/env.sh 配置文件）
# ---------------------------------------------------------------------------
DOMAIN_FILTER=""
KEEP_REPORTS="${KEEP_REPORTS:-10}"
TIMEOUT="${TIMEOUT:-30}"
START_TS="$(date +%s)"

usage() {
  cat <<'EOF'
ASDM 接口自动化测试（FT-060）

用法: scripts/run.sh [选项]

选项:
  --base-url <url>     环境地址（默认 https://asdm-sit.leansoftx.com，尾斜杠自动规范化）
  --domains <清单>     仅执行指定业务域，逗号分隔（如: 认证授权域,项目管理域）；默认全部
  --timeout <秒>       单请求超时（默认 30）
  --keep <份数>        报告历史保留份数（默认 10，Phase 3 生效）
  --key=value          覆盖任意输入参数（key 转大写下划线后注入环境变量，
                       如 --login-email=a@b.c 等价 LOGIN_EMAIL=a@b.c）
  --help               显示本帮助

环境变量（优先级高于 config/env.sh，低于 CLI）:
  ASDM_BASE_URL / LOGIN_EMAIL / LOGIN_PASSWORD / ASDM_PAT / OPEN_ACCESS_TOKEN /
  CITIC_SECRET / INTERNAL_TOKEN_CORE / INTERNAL_TOKEN_AGENTORBIT / INTERNAL_TOKEN_TELEMETRY /
  SERVICE_BASE_URL_<服务>（逐服务 baseUrl 覆盖）

参数优先级: --key=value > 环境变量 > config/env.sh > Postman 集合默认值
退出码: 0=全部通过(含SKIP)  1=存在FAIL  2=关键链路中止(L0/L1)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h)
      usage
      exit 0
      ;;
    --base-url)
      [ $# -ge 2 ] || { echo "错误: --base-url 缺少参数" >&2; exit 2; }
      ASDM_BASE_URL="$2"; shift 2 ;;
    --base-url=*)
      ASDM_BASE_URL="${1#*=}"; shift ;;
    --domains)
      [ $# -ge 2 ] || { echo "错误: --domains 缺少参数" >&2; exit 2; }
      DOMAIN_FILTER="$2"; shift 2 ;;
    --domains=*)
      DOMAIN_FILTER="${1#*=}"; shift ;;
    --timeout)
      [ $# -ge 2 ] || { echo "错误: --timeout 缺少参数" >&2; exit 2; }
      TIMEOUT="$2"; shift 2 ;;
    --timeout=*)
      TIMEOUT="${1#*=}"; shift ;;
    --keep)
      [ $# -ge 2 ] || { echo "错误: --keep 缺少参数" >&2; exit 2; }
      KEEP_REPORTS="$2"; shift 2 ;;
    --keep=*)
      KEEP_REPORTS="${1#*=}"; shift ;;
    --*=*)
      # 通用 --key=value 动态传参（key 大写下划线化后导出，仅本次执行生效，不回写配置）
      _k="${1%%=*}"; _v="${1#*=}"
      _k="${_k#--}"; _k="${_k//-/_}"
      _k="$(printf '%s' "$_k" | tr '[:lower:]' '[:upper:]')"
      export "$_k=$_v"
      shift ;;
    *)
      echo "错误: 未知参数 $1（--help 查看用法）" >&2
      exit 2 ;;
  esac
done

# 尾斜杠规范化（admin-G4 / 尾斜杠陷阱）
ASDM_BASE_URL="$(rstrip_slash "$ASDM_BASE_URL")"

# ===========================================================================
# L0 环境与工具校验（失败 exit 2）
# ===========================================================================
log_line "===================================================================="
log_line "ASDM 接口自动化测试 RUN_TS=$RUN_TS"
log_line "[L0] JSON 引擎: $JSON_ENGINE（jq 探测 / node 降级）"
log_line "[L0] 生效配置: base-url=$ASDM_BASE_URL timeout=${TIMEOUT}s keep=$KEEP_REPORTS domains=${DOMAIN_FILTER:-全部}"

for f in config/env.sh config/params.json config/iface.json; do
  if [ ! -f "$ASDM_TEST_ROOT/$f" ]; then
    log_line "[L0] 致命错误: 配置文件缺失 $f"
    exit 2
  fi
done
for f in config/params.json config/iface.json; do
  if ! json_validate_file "$ASDM_TEST_ROOT/$f"; then
    log_line "[L0] 致命错误: $f JSON 解析失败"
    exit 2
  fi
done

# --domains 合法性校验（值必须 ⊆ iface.json domainOrder，交集为空即 exit 2）
if [ -n "$DOMAIN_FILTER" ]; then
  VALID_DOMAINS="$(IFACE_FILE="$IFACE_FILE" node -e '
    const fs = require("fs");
    const iface = JSON.parse(fs.readFileSync(process.env.IFACE_FILE, "utf8"));
    console.log((iface.domainOrder || []).join(","));
  ')"
  log_line "[L0] 域过滤: $DOMAIN_FILTER（合法域: $VALID_DOMAINS）"
  IFS=','
  _bad=""
  for _d in $DOMAIN_FILTER; do
    _d="$(printf '%s' "$_d" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case ",$VALID_DOMAINS," in
      *",$_d,"*) : ;;
      *) _bad="${_bad:+$_bad }$_d" ;;
    esac
  done
  unset IFS
  if [ -n "$_bad" ]; then
    log_line "[L0] 致命错误: --domains 含未知域 [$_bad]，合法域清单: $VALID_DOMAINS"
    exit 2
  fi
fi

# ===========================================================================
# L1 登录鉴权（失败 exit 2）
# ===========================================================================
do_login || exit 2

# ===========================================================================
# L2 数据准备（Phase 2 实现: prepare 清单 + CAPTURED.* 上下文捕获）
# ===========================================================================
log_line "[L2] 数据准备层: 待 Phase 2 实现（自建数据闭环 + 上下文捕获）"

# ===========================================================================
# L3 业务域执行（Phase 1: GET-only 执行 + 简化判定 <400 → PASS）
# ===========================================================================
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

load_interfaces || { log_line "[L3] 致命错误: api.json 展平失败"; exit 2; }
log_line "[L3] 接口清单: 总数=$TOTAL（源集合对账见 $IFACE_STATS）"
list_first >/dev/null || true

if [ -n "$DOMAIN_FILTER" ]; then
  filter_interfaces "$DOMAIN_FILTER"
  log_line "[L3] 域过滤生效: 选中 $TOTAL_SELECTED / $TOTAL"
  RUN_LIST="$IFACE_SELECTED"
  RUN_TOTAL="$TOTAL_SELECTED"
else
  RUN_LIST="$IFACE_TSV"
  RUN_TOTAL="$TOTAL"
fi

idx=0
while IFS=$'\037' read -r domain svc svcfull module name method rawurl headersj bodyj queryj; do
  [ -n "$method" ] || continue
  idx=$((idx + 1))

  # ---- 渲染（变量替换 + :id 归一 + baseUrl 收敛 + 同名头去重）----
  render_interface "$domain" "$svc" "$method" "$rawurl" "$headersj" "$bodyj"

  # ---- Phase 1 安全阀: 非 GET 接口等待 Phase 2 自建数据闭环 ----
  if [ "$method" != "GET" ]; then
    SKIP_COUNT=$((SKIP_COUNT + 1))
    log_line "[$idx/$RUN_TOTAL][$domain][$method][${RENDER_PATH:-$rawurl}] SKIP - (非GET接口待Phase2数据闭环)"
    if (( idx % 100 == 0 )); then
      log_summary "$idx" "$RUN_TOTAL" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
    fi
    continue
  fi

  # ---- 渲染缺失 → SKIP（路径参数缺失 / 凭据缺失 / 前置数据缺失）----
  if [ "${#RENDER_MISSING[@]}" -gt 0 ]; then
    SKIP_COUNT=$((SKIP_COUNT + 1))
    log_line "[$idx/$RUN_TOTAL][$domain][$method][${RENDER_PATH:-$rawurl}] SKIP - ${RENDER_MISSING[0]}"
    if (( idx % 100 == 0 )); then
      log_summary "$idx" "$RUN_TOTAL" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
    fi
    continue
  fi

  # ---- 执行请求 ----
  log_line "  → GET $(mask_sensitive "$RENDER_URL")"
  REQ_BODY_FILE="${RENDER_BODY_FILE:-}"
  http_request GET "$RENDER_URL" "${RENDER_HEADERS[@]+"${RENDER_HEADERS[@]}"}"

  # ---- Phase 1 简化判定（Phase 2 由断言引擎接管: 响应三分法 + 五级判定链）----
  result="PASS"; reason=""
  if [ "$HTTP_CODE" = "000" ]; then
    result="FAIL"; reason="- $(curl_exit_reason "$CURL_EXIT")"
  elif [ "$HTTP_CODE" -ge 400 ] 2>/dev/null; then
    result="FAIL"; reason="- HTTP状态码非预期($HTTP_CODE)"
  fi
  if [ "$result" = "PASS" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
  log_line "[$idx/$RUN_TOTAL][$domain][$method][${RENDER_PATH:-$rawurl}] $result $HTTP_CODE ${TIME_TOTAL}s $reason"

  if (( idx % 100 == 0 )); then
    log_summary "$idx" "$RUN_TOTAL" "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  fi
done <"$RUN_LIST"

# ===========================================================================
# L4 清理（Phase 2 实现: 逆序删除自建数据 + --keep-data 逃生口）
# ===========================================================================
log_line "[L4] 清理层: 待 Phase 2 实现（逆序清理自建数据）"

# ===========================================================================
# 汇总与退出码
# ===========================================================================
ELAPSED=$(( $(date +%s) - START_TS ))
log_line "===================================================================="
log_line "执行完成: 总数=$RUN_TOTAL PASS=$PASS_COUNT FAIL=$FAIL_COUNT SKIP=$SKIP_COUNT 总耗时=${ELAPSED}s"
log_line "（Phase 1 范围: GET-only 执行；SKIP 中非 GET 接口待 Phase 2 数据闭环）"
log_line "日志: $LOG_FILE"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
