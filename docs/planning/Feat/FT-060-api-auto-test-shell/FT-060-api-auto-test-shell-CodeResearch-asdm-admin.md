# FT-060 CodeResearch — asdm-admin（被测系统源码）

> 代码库：`D:\workspace\ASDM\asdm-admin\asdm_v1.3.11\asdm-admin`（Java 后端微服务群 + Web 前端 + deploy 部署脚本）

> 最后更新：2026-11-26

---

## 1. 目录结构与关键文件

| 模块 | 内容 | 与本特性相关性 |
|------|------|----------------|
| `asdm-admin-services/` | 2519 个 Java 文件，13 个微服务子模块 | 断言引擎、鉴权层设计依据 |
| `asdm-admin-web/` | 前端（318 tsx / 182 ts） | 无关（本特性只测后端 API） |
| `deploy/` | 214 个 SQL migration + 部署脚本 | 无关（本特性不涉及 DB 变更） |

13 个微服务端口：core 8880 / sso 8881 / integration 8882 / adapter-ads 8883 / adapter-gitlab 8884 / agentorbit 8884（与 gitlab 冲突，本机二选一）/ mcp-hosting 8885 / telemetry 8886 / file-service 8887 / adapter-codearts 8888 / org-mapping 8889 / portal-backend 8889 / adapter-automation 8890（证据：各模块 `src/main/resources/application.yml`）。

## 2. 现有实现分析（调研结论）

### 2.1 统一响应结构

各服务均有 `ApiResponse<T>` 包装类（core/integration/telemetry/file-service/portal-backend/mcp-hosting）：字段 `code/message/data`，**成功值 = 200**（非 0）。core 额外带 `requestId/timestamp/errorCode/retryable/details`（NON_NULL 序列化）。

- core：`asdm-admin-services-core/.../core/dto/auth/ApiResponse.java:9-38`，`success(data)` → `(200, "success", data)`；
- telemetry：同名类，成功 message 为 "Success"（大小写不同）；
- sso 与 adapter-* **没有**统一 ApiResponse 类（sso 多为 302 重定向/cookie，adapter 控制器直接返回业务对象）。

### 2.2 登录接口

- `POST /api/auth/login`（core）：`AuthController.java:92-137`；
- 请求体 `{email, password}`；响应 `ApiResponse<LoginResponse>`，token 在 **`data.token`**（无 accessToken、无过期时间字段）；
- LoginResponse：`token` + `user`（id/guid/username/nickname/roles/permissions 等）；
- token 为 JWT（HMAC-SHA，密钥 `asdm.jwt.secret`，有效期 30 天硬编码）。

### 2.3 鉴权机制实现

| 机制 | 实现位置 | 要点 |
|------|----------|------|
| Bearer JWT（core） | `core/config/JwtInterceptor.java:33-126` | `Authorization: Bearer <token>` 或 cookie；无效→HTTP 401；login 等白名单放行 |
| asdmPat 查询参数（integration） | `integration/interceptor/AsdmPatValidationInterceptor.java:53-114` | PAT 须 ACTIVE，换取 JWT 注入；缺失→401 |
| X-Asdm-Pat（agentorbit） | `InternalWorkspaceOpenAccessController.java:41-44` | 透传注入成员环境，**非鉴权凭证** |
| X-Internal-Token | core `InternalTokenInterceptor`；agentorbit/telemetry 各自拦截器 | 预期值来自配置：core 默认 `asdm-core-m2m-2026`，agentorbit 默认 `agentorbit-m2m-token`，telemetry 默认 `asdm-telemetry-m2m-2026` |
| X-Citic-Secret | `core/config/CiticSecretInterceptor.java:27-57` | 作用于 `/_api/citic/**`，不匹配→HTTP 401 |
| X-Open-Access-Token | `core/config/OpenAccessTokenInterceptor.java:36-56` | 组织级 `oat_...`，作用于 `/api/v1/agentorbit/workspaces/**` |

### 2.4 全局异常处理（断言关键）

core 双 Advice，业务错误**多数映射为真实 4xx/5xx**，但存在 HTTP 200 + 错误码陷阱：

| 场景 | HTTP | body |
|------|------|------|
| `ApiBusinessException`（100-599 码） | 同业务码 | 完整业务码 |
| `UnifiedApiBusinessException` | **200** | 错误 code |
| 登录用户/密码错误 | **200** | code=401（`AuthController.java:103,111`） |
| 请求体解析失败 | 400 | code=400 |
| ConstraintViolation / 未知异常 | **200** | code=400 / 500 |
| telemetry internal-token 失败 | **200** | code=401 |
| 拦截器鉴权失败（JWT/PAT/Citic） | 401 | — |

## 3. 关键发现与缺失项

| 编号 | 发现 | 对 FT-060 设计的影响 |
|------|------|----------------------|
| admin-G1 | 成功判定不能只用 HTTP 2xx：多处 HTTP 200 + 错误 code | 断言引擎必须校验 `data.code == 200`（当响应为 JSON 包装结构时） |
| admin-G2 | 非 JSON 响应（sso 302、file-service 二进制流、adapter 直返业务对象） | 断言策略需按接口配置响应类型：JSON 包装 / JSON 裸对象 / 非 JSON（仅状态码） |
| admin-G3 | internal-token 各服务预期值不同且来自环境配置 | env.sh 需 per-service internalToken 配置项，SIT 实际值待测试人员提供 |
| admin-G4 | agentorbit 与 adapter-gitlab 同端口 8884（本机冲突），api.json 标注部署二选一 | SIT 网关下需按路径路由，脚本按域独立 baseUrl 处理 |
| admin-G5 | 登录失败陷阱：HTTP 200 + code=401 | login 成功断言必须解析 `data.token` 存在性，不能只看 HTTP 状态 |
| admin-G6 | JWT 有效期 30 天 | 理论上 token 可缓存复用，但每日执行仍建议每次重新登录（简单可靠） |
| admin-G7 | telemetry 拦截器失败返回 200+401 | 失败原因分类需含"业务码非预期"维度 |

## 4. 与其他代码库的交互

- api.json 由本代码库静态分析生成（v1.3.11 快照），接口清单以 api.json 为准；
- FT-060 脚本与本代码库无编译/部署耦合，仅 HTTP 交互。

## 5. 待确认问题清单

1. SIT 环境各 internal-token 的实际配置值（core/agentorbit/telemetry 各不同）——由测试人员填入 env.sh；
2. SIT 网关对 13 个服务的路由规则（路径前缀 or 独立子域）——实跑验证；
3. OpenAccess `oat_...` 组织令牌与 Citic secret 的 SIT 取值——凭据缺失时相关接口自动 SKIP；
4. adapter-*（ads/gitlab/codearts/automation）依赖外部系统（Azure DevOps/GitLab/CodeArts），SIT 可连通性未知——预期大量 SKIP 或失败，报告需区分"被测服务故障"与"外部依赖不可达"。
