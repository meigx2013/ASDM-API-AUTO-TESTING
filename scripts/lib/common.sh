#!/usr/bin/env bash
# scripts/lib/common.sh — 公共函数库（日志 / JSON 解析降级 / curl 封装）
#
# 被 run.sh 与各 lib 模块 source；也可独立 source 后调用 json_get / http_request。
# 注意: 本文件 source 时会装载 config/env.sh 默认值并初始化 logs/.work 目录。

# ---------------------------------------------------------------------------
# 工作区根目录定位（lib/common.sh → 上两级）
# ---------------------------------------------------------------------------
ASDM_TEST_ROOT="${ASDM_TEST_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# 装载环境配置（env.sh 内部用 ${VAR:-default}，外部环境变量可覆盖文件默认值）
# shellcheck source=../../config/env.sh
source "$ASDM_TEST_ROOT/config/env.sh" 2>/dev/null || {
  echo "[L0] 致命错误: 缺少 config/env.sh（$ASDM_TEST_ROOT/config/env.sh）" >&2
  exit 2
}

# ---------------------------------------------------------------------------
# 运行批次标识与输出目录
# ---------------------------------------------------------------------------
RUN_TS="${RUN_TS:-$(date +%Y%m%d-%H%M%S)}"
LOG_DIR="$ASDM_TEST_ROOT/logs"
REPORT_DIR="$ASDM_TEST_ROOT/reports"
WORK_DIR="${WORK_DIR:-$ASDM_TEST_ROOT/.work/$RUN_TS}"
mkdir -p "$LOG_DIR" "$REPORT_DIR" "$WORK_DIR" 2>/dev/null
LOG_FILE="$LOG_DIR/run-$RUN_TS.log"
VARS_FILE="$WORK_DIR/vars.json"
IFACE_FILE="$ASDM_TEST_ROOT/config/iface.json"
IFACE_TSV="$WORK_DIR/interfaces.tsv"

# ---------------------------------------------------------------------------
# 工具探测: JSON 引擎优先 jq，缺失降级 node；node 为展平/渲染引擎必需依赖
# ---------------------------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  JSON_ENGINE="jq"
elif command -v node >/dev/null 2>&1; then
  JSON_ENGINE="node"
else
  echo "[L0] 致命错误: jq 与 node 均不可用，无法解析 JSON（jq/node 至少需要其一，node 为渲染引擎必需）" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# 基础函数
# ---------------------------------------------------------------------------
# 尾斜杠规范化（防止 baseUrl 拼接出 //api/... 被网关 404）
rstrip_slash() {
  printf '%s' "${1%/}"
}

# 统一日志（终端回显 + logs/run-<ts>.log 落盘）
log_line() {
  printf '%s\n' "$*" | tee -a "$LOG_FILE" 2>/dev/null || printf '%s\n' "$*"
}

# 带时间戳日志
log_ts() {
  log_line "[$(date '+%H:%M:%S')] $*"
}

# 汇总心跳行
log_summary() {
  log_line "已执行 $1/$2 | PASS=$3 FAIL=$4 SKIP=$5"
}

# 敏感值脱敏（bash 子串替换，无正则元字符风险）
mask_sensitive() {
  local s="$1"
  local v
  for v in "$TOKEN" "$ASDM_PAT" "$OPEN_ACCESS_TOKEN" "$CITIC_SECRET" \
    "$INTERNAL_TOKEN_CORE" "$INTERNAL_TOKEN_AGENTORBIT" "$INTERNAL_TOKEN_TELEMETRY" \
    "$LOGIN_PASSWORD"; do
    if [ -n "$v" ]; then s="${s//"$v"/\*\*\*\*\*\*}"; fi
  done
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# JSON 解析（D14: jq 探测 / node 降级，取值失败 exit 1）
#   json_get      <json字符串> <路径，如 $.data.token 或 .data.token>
#   json_get_file <json文件>   <路径>
# ---------------------------------------------------------------------------
json_get() {
  local json="$1" path="$2"
  path="${path#\$.}"
  path="${path#.}"
  if [ "$JSON_ENGINE" = "jq" ]; then
    printf '%s' "$json" | jq -er "$path" 2>/dev/null
    return $?
  fi
  JG_PATH="$path" node -e '
    const fs = require("fs");
    let s = "";
    try { s = fs.readFileSync(0, "utf8"); } catch (e) { process.exit(1); }
    let o;
    try { o = JSON.parse(s); } catch (e) { process.exit(1); }
    let v = o;
    for (const k of process.env.JG_PATH.split(".")) {
      if (v == null) process.exit(1);
      v = v[k];
    }
    if (v === undefined || v === null) process.exit(1);
    if (typeof v === "object") console.log(JSON.stringify(v));
    else console.log(String(v));
  ' <<<"$json"
}

json_get_file() {
  local file="$1" path="$2"
  path="${path#\$.}"
  path="${path#.}"
  if [ "$JSON_ENGINE" = "jq" ]; then
    jq -er "$path" "$file" 2>/dev/null
    return $?
  fi
  JG_PATH="$path" JG_FILE="$file" node -e '
    const fs = require("fs");
    let s;
    try { s = fs.readFileSync(process.env.JG_FILE, "utf8"); } catch (e) { process.exit(1); }
    let o;
    try { o = JSON.parse(s); } catch (e) { process.exit(1); }
    let v = o;
    for (const k of process.env.JG_PATH.split(".")) {
      if (v == null) process.exit(1);
      v = v[k];
    }
    if (v === undefined || v === null) process.exit(1);
    if (typeof v === "object") console.log(JSON.stringify(v));
    else console.log(String(v));
  '
}

# JSON 文件合法性校验（合法返回 0）
json_validate_file() {
  JV_FILE="$1" node -e '
    const fs = require("fs");
    try { JSON.parse(fs.readFileSync(process.env.JV_FILE, "utf8")); process.exit(0); }
    catch (e) { process.exit(1); }
  '
}

# ---------------------------------------------------------------------------
# http_request — curl 封装（元数据分离采集，D6/V1.2.5）
#   用法: REQ_BODY_FILE=<可选请求体文件> http_request METHOD URL [Header...] 
#   Header 形如 "Authorization: Bearer xxx"（多个可变参数）
#   产出全局变量: HTTP_CODE（"000"=未得到响应）、TIME_TOTAL（秒）、CURL_EXIT、RESP_FILE
# ---------------------------------------------------------------------------
http_request() {
  local method="$1"
  local url="$2"
  shift 2
  local h
  local -a hdr_args=()
  for h in "$@"; do
    if [ -n "$h" ]; then hdr_args+=(-H "$h"); fi
  done
  local -a body_args=()
  # 防御: GET/HEAD 不携带请求体（curl --data-binary 会隐式改方法为 POST）
  case "$method" in
    GET|HEAD) REQ_BODY_FILE="" ;;
  esac
  if [ -n "${REQ_BODY_FILE:-}" ] && [ -f "${REQ_BODY_FILE:-}" ]; then
    body_args=(--data-binary "@$REQ_BODY_FILE")
  fi
  local meta_file="$WORK_DIR/curl-meta.txt"
  local resp_file="$WORK_DIR/curl-resp.txt"
  local err_file="$WORK_DIR/curl-err.txt"
  CURL_EXIT=0
  curl -sS -X "$method" -o "$resp_file" \
    -w '%{http_code} %{time_total}\n' \
    --max-time "${TIMEOUT:-30}" \
    ${hdr_args[@]+"${hdr_args[@]}"} \
    ${body_args[@]+"${body_args[@]}"} \
    "$url" >"$meta_file" 2>"$err_file" || CURL_EXIT=$?
  HTTP_CODE="$(head -1 "$meta_file" 2>/dev/null | awk '{print $1}')"
  HTTP_CODE="${HTTP_CODE:-000}"
  TIME_TOTAL="$(head -1 "$meta_file" 2>/dev/null | awk '{print $2}')"
  TIME_TOTAL="${TIME_TOTAL:-0}"
  RESP_FILE="$resp_file"
}

# curl 退出码 → 失败原因分类（Phase 2 断言引擎判定链第 1/2 级复用）
curl_exit_reason() {
  case "$1" in
    28) printf '请求超时' ;;
    7|6|35|56|16) printf '连接失败' ;;
    0) printf '' ;;
    *) printf 'curl错误(exit=%s)' "$1" ;;
  esac
}
