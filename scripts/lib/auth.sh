#!/usr/bin/env bash
# scripts/lib/auth.sh — L1 登录鉴权层（D4 / admin-G5 陷阱应对）
#
# do_login: 执行 POST /api/auth/login
#   - email/password 取参数体系（env.sh / 环境变量 / CLI --login-email=... 等），非 api.json 示例值
#   - 断言规则（admin-G5 特判）: 登录失败陷阱为 HTTP 200 + code=401，必须解析 $.data.token 存在性，
#     不能只看 HTTP 状态码
#   - 成功: TOKEN 写入变量表（creds.token），供 501 个 Bearer JWT 接口替换消费
#   - 失败: 返回 2（run.sh 判定 exit 2 中止），输出凭据核对提示
#   - 凭据未配置: 前置校验直接失败，不发出任何登录请求

do_login() {
  # ---- 外部令牌直通: 提供 ASDM_TOKEN 时跳过登录（调试/复用 30 天有效期 JWT）----
  if [ -n "${ASDM_TOKEN:-}" ]; then
    TOKEN="$ASDM_TOKEN"
    ensure_var_table || return 2
    update_var creds token "$TOKEN" || return 2
    export TOKEN
    log_line "[L1] 使用环境变量 ASDM_TOKEN 跳过登录（token_len=${#TOKEN}）"
    return 0
  fi

  # ---- 前置校验：凭据未配置不发空请求（V1.3.4）----
  if [ -z "$LOGIN_EMAIL" ] || [ -z "$LOGIN_PASSWORD" ]; then
    log_line "[L1] 登录凭据未配置: LOGIN_EMAIL/LOGIN_PASSWORD 为空，跳过登录请求"
    log_line "[L1] 请在 config/env.sh 填写，或通过环境变量 / --login-email= --login-password= 注入"
    return 2
  fi

  ensure_var_table || return 2

  local login_url
  login_url="$(rstrip_slash "$ASDM_BASE_URL")/api/auth/login"

  # 登录请求体从参数体系构造（JSON 安全：node stringify，密码含特殊字符不破坏结构）
  REQ_BODY_FILE="$WORK_DIR/login-body.json"
  LOGIN_EMAIL="$LOGIN_EMAIL" LOGIN_PASSWORD="$LOGIN_PASSWORD" OUT="$REQ_BODY_FILE" \
    node -e '
      const fs = require("fs");
      const env = process.env;
      fs.writeFileSync(env.OUT, JSON.stringify({
        email: env.LOGIN_EMAIL,
        password: env.LOGIN_PASSWORD,
      }));
    ' || { log_line "[L1] 登录请求体构造失败"; return 2; }

  log_line "[L1] 登录请求: POST $(mask_sensitive "$login_url")"

  http_request POST "$login_url" "Content-Type: application/json"

  # ---- 断言: 解析 data.token 存在性（HTTP 200 + code=401 陷阱不能只看状态码）----
  TOKEN="$(json_get_file "$RESP_FILE" '$.data.token' 2>/dev/null || true)"
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    local code
    code="$(json_get_file "$RESP_FILE" '$.code' 2>/dev/null || true)"
    local body_head
    body_head="$(head -c 200 "$RESP_FILE" 2>/dev/null)"
    log_line "[L1] 登录失败（admin-G5 双校验: HTTP 状态 $HTTP_CODE / 业务码 ${code:-无}）"
    log_line "[L1] 响应摘要: $(mask_sensitive "$body_head")"
    log_line "[L1] 凭据核对提示: 账号来源=${LOGIN_EMAIL} 环境地址=$(rstrip_slash "$ASDM_BASE_URL")"
    log_line "[L1] 注意: 登录失败陷阱为 HTTP 200 + code=401，请核对账号密码是否正确、账号是否锁定"
    return 2
  fi

  # TOKEN 写入变量表，供渲染引擎替换 {{token}}
  update_var creds token "$TOKEN" || return 2
  export TOKEN
  log_line "[L1] 登录成功: TOKEN 已捕获（token_len=${#TOKEN}，curl exit=$CURL_EXIT http=$HTTP_CODE 耗时 ${TIME_TOTAL}s）"
  return 0
}
