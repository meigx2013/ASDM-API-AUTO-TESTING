# config/env.sh — ASDM 接口自动化测试环境与凭据配置
# 使用方法：直接编辑本文件填写非敏感值；凭据建议通过环境变量注入（优先级：CLI > 环境变量 > 本文件）
# 注意：本文件所有取值均使用 ${VAR:-default} 形式，外部环境变量可覆盖文件默认值。

# ---------------------------------------------------------------------------
# 环境地址（尾斜杠由脚本规范化去除，防止拼接出 //api/... 被网关 404）
# ---------------------------------------------------------------------------
ASDM_BASE_URL="${ASDM_BASE_URL:-https://asdm-sit.leansoftx.com}"

# ---------------------------------------------------------------------------
# 登录凭据（L1 登录鉴权层使用，缺失时启动即 exit 2 并提示，不发空请求）
# ---------------------------------------------------------------------------
LOGIN_EMAIL="${LOGIN_EMAIL:-}"
LOGIN_PASSWORD="${LOGIN_PASSWORD:-}"

# ---------------------------------------------------------------------------
# 外部凭据（缺失 → 依赖该凭据的接口 SKIP，不产生误报 FAIL）
# ---------------------------------------------------------------------------
ASDM_PAT="${ASDM_PAT:-}"                # X-Asdm-Pat 头 + asdmPat query 参数
OPEN_ACCESS_TOKEN="${OPEN_ACCESS_TOKEN:-}"  # X-Open-Access-Token（oat_ 组织级令牌）
CITIC_SECRET="${CITIC_SECRET:-}"        # X-Citic-Secret（/_api/citic/**）

# ---------------------------------------------------------------------------
# 内部令牌（X-Internal-Token，各服务预期值不同，见 asdm-admin 调研 admin-G3）
# ---------------------------------------------------------------------------
INTERNAL_TOKEN_CORE="${INTERNAL_TOKEN_CORE:-}"
INTERNAL_TOKEN_AGENTORBIT="${INTERNAL_TOKEN_AGENTORBIT:-}"
INTERNAL_TOKEN_TELEMETRY="${INTERNAL_TOKEN_TELEMETRY:-}"

# ---------------------------------------------------------------------------
# 可选：逐服务独立 baseUrl 覆盖（缺省全部收敛为 ASDM_BASE_URL 网关域名）
# 取消注释并填写后，仅对应服务的 {{xxxBaseUrl}} 使用该地址
# ---------------------------------------------------------------------------
# SERVICE_BASE_URL_CORE="https://core-sit.example.com"
# SERVICE_BASE_URL_SSO="https://sso-sit.example.com"
# SERVICE_BASE_URL_INTEGRATION="https://integration-sit.example.com"
# SERVICE_BASE_URL_ADS_ADAPTER="https://ads-adapter-sit.example.com"
# SERVICE_BASE_URL_GITLAB_ADAPTER="https://gitlab-adapter-sit.example.com"
# SERVICE_BASE_URL_AGENTORBIT="https://agentorbit-sit.example.com"
# SERVICE_BASE_URL_MCP_HOSTING="https://mcp-hosting-sit.example.com"
# SERVICE_BASE_URL_TELEMETRY="https://telemetry-sit.example.com"
# SERVICE_BASE_URL_FILE_SERVICE="https://file-service-sit.example.com"
# SERVICE_BASE_URL_CODEARTS_ADAPTER="https://codearts-adapter-sit.example.com"
# SERVICE_BASE_URL_ORG_MAPPING="https://org-mapping-sit.example.com"
# SERVICE_BASE_URL_PORTAL_BACKEND="https://portal-backend-sit.example.com"
# SERVICE_BASE_URL_AUTOMATION_ADAPTER="https://automation-adapter-sit.example.com"
