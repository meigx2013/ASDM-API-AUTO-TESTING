#!/usr/bin/env bash
# scripts/lib/vars.sh — 变量表装载与单接口渲染接线（D5/D6）
#
# ensure_var_table: 惰性确保 $VARS_FILE 存在
# load_var_table:   装载变量表（13 个 baseUrl 收敛网关域名 + 逐服务覆盖 + 凭据 + params）
# update_var:       更新变量表字段（token 等运行期上下文写入）
# render_interface: 调 render.js 渲染单接口，产出全局:
#                   RENDER_URL / RENDER_PATH / RENDER_HEADERS[] / RENDER_BODY_FILE / RENDER_MISSING[]

# 惰性初始化变量表
ensure_var_table() {
  if [ ! -f "$VARS_FILE" ]; then
    load_var_table || return 2
  fi
  return 0
}

# 装载变量表（baseUrl 收敛规则见 vars-build.js 头注释）
load_var_table() {
  ASDM_BASE_URL="$ASDM_BASE_URL" \
  ASDM_PAT="$ASDM_PAT" \
  TOKEN="${TOKEN:-}" \
  OPEN_ACCESS_TOKEN="$OPEN_ACCESS_TOKEN" \
  CITIC_SECRET="$CITIC_SECRET" \
  INTERNAL_TOKEN_CORE="$INTERNAL_TOKEN_CORE" \
  INTERNAL_TOKEN_AGENTORBIT="$INTERNAL_TOKEN_AGENTORBIT" \
  INTERNAL_TOKEN_TELEMETRY="$INTERNAL_TOKEN_TELEMETRY" \
  SERVICE_BASE_URL_CORE="${SERVICE_BASE_URL_CORE:-}" \
  SERVICE_BASE_URL_SSO="${SERVICE_BASE_URL_SSO:-}" \
  SERVICE_BASE_URL_INTEGRATION="${SERVICE_BASE_URL_INTEGRATION:-}" \
  SERVICE_BASE_URL_ADS_ADAPTER="${SERVICE_BASE_URL_ADS_ADAPTER:-}" \
  SERVICE_BASE_URL_GITLAB_ADAPTER="${SERVICE_BASE_URL_GITLAB_ADAPTER:-}" \
  SERVICE_BASE_URL_AGENTORBIT="${SERVICE_BASE_URL_AGENTORBIT:-}" \
  SERVICE_BASE_URL_MCP_HOSTING="${SERVICE_BASE_URL_MCP_HOSTING:-}" \
  SERVICE_BASE_URL_TELEMETRY="${SERVICE_BASE_URL_TELEMETRY:-}" \
  SERVICE_BASE_URL_FILE_SERVICE="${SERVICE_BASE_URL_FILE_SERVICE:-}" \
  SERVICE_BASE_URL_CODEARTS_ADAPTER="${SERVICE_BASE_URL_CODEARTS_ADAPTER:-}" \
  SERVICE_BASE_URL_ORG_MAPPING="${SERVICE_BASE_URL_ORG_MAPPING:-}" \
  SERVICE_BASE_URL_PORTAL_BACKEND="${SERVICE_BASE_URL_PORTAL_BACKEND:-}" \
  SERVICE_BASE_URL_AUTOMATION_ADAPTER="${SERVICE_BASE_URL_AUTOMATION_ADAPTER:-}" \
  PARAMS_FILE="$ASDM_TEST_ROOT/config/params.json" \
  VARS_FILE="$VARS_FILE" \
    node "$ASDM_TEST_ROOT/scripts/lib/vars-build.js" || return 2
  return 0
}

# 更新变量表: update_var <section> <key> <value>（section: creds/captured）
update_var() {
  local sec="$1" key="$2" val="$3"
  UPD_SEC="$sec" UPD_KEY="$key" UPD_VAL="$val" VARS_FILE="$VARS_FILE" node -e '
    const fs = require("fs");
    const env = process.env;
    const vars = JSON.parse(fs.readFileSync(env.VARS_FILE, "utf8"));
    if (env.UPD_SEC === "creds") vars.creds[env.UPD_KEY] = env.UPD_VAL;
    else if (env.UPD_SEC === "captured") vars.captured[env.UPD_KEY] = env.UPD_VAL;
    else { console.error("未知 section: " + env.UPD_SEC); process.exit(2); }
    fs.writeFileSync(env.VARS_FILE, JSON.stringify(vars, null, 1));
  ' || return 2
}

# 渲染单接口（入参为 TSV 展开后的各字段），产出 RENDER_* 全局变量
# 用法: render_interface <domain> <svc> <method> <rawurl> <headersJ> <bodyJ>
render_interface() {
  local domain="$1" svc="$2" method="$3" rawurl="$4" headersj="$5" bodyj="$6"
  RENDER_URL=""
  RENDER_PATH=""
  RENDER_HEADERS=()
  RENDER_BODY_FILE=""
  RENDER_MISSING=()
  local out line k v
  out="$(IF_RAW_URL="$rawurl" IF_METHOD="$method" IF_SVC="$svc" \
    IF_HEADERS="$headersj" IF_BODY="$bodyj" \
    IFACE_FILE="$IFACE_FILE" VARS_FILE="$VARS_FILE" WORK_DIR="$WORK_DIR" \
    node "$ASDM_TEST_ROOT/scripts/lib/render.js")" || return 2
  while IFS=$'\t' read -r k v; do
    case "$k" in
      url) RENDER_URL="$v" ;;
      path) RENDER_PATH="$v" ;;
      header) RENDER_HEADERS+=("$v") ;;
      bodyFile) RENDER_BODY_FILE="$v" ;;
      missing) RENDER_MISSING+=("$v") ;;
    esac
  done <<<"$out"
  return 0
}
