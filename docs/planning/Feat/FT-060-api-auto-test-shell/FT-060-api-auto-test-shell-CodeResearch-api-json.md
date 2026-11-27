# FT-060 CodeResearch — api.json（接口资产数据源）

> 代码库：本工作区 `docs/api.json`（ASDM Admin 全量 API Postman v2.1.0 集合，由被测系统代码静态分析自动生成）

> 最后更新：2026-11-26

---

## 1. 目录结构与规模

| 维度 | 数据 |
|------|------|
| 文件 | `docs/api.json`（单一 JSON 文件） |
| 结构层级 | 域（12）→ 服务（13 个目录条目）→ 模块（如 Authentication/Sso）→ 接口 |
| 接口总数 | 1000 |
| 变量 | 13 个 baseUrl 变量 + 5 个凭据变量（token/pat/internalToken/openAccessToken/citicSecret） |

## 2. 关键统计（逐接口遍历实测）

| 维度 | 分布 |
|------|------|
| HTTP 方法 | GET 566 / POST 281 / PUT 63 / DELETE 70 / PATCH 20 |
| 鉴权头分布 | Bearer JWT 501 / 无鉴权头 398 / X-Internal-Token 90 / X-Citic-Secret 7 / X-Asdm-Pat 头 3 / X-Open-Access-Token 1 |
| asdmPat 查询参数 | 44 个接口（integration 域为主） |
| 请求体 | 256 个接口含 body.raw（其余 744 无请求体） |
| 登录接口 body | `POST /api/auth/login`：`{"email": "...", "password": "..."}` |

各服务接口数：core 100 / integration 82 / portal-backend 60 / agentorbit 55 / adapter-ads 42 / adapter-codearts 28 / adapter-gitlab 28 / telemetry 28 / adapter-automation 22 / file-service 18 / org-mapping 10 / sso 9 / mcp-hosting 6。

## 3. 现有实现分析

- api.json 是**接口目录快照**，不含依赖关系、不含响应示例（部分描述标注【推断】）；
- 请求结构完整度高：method、header（含鉴权头）、url（含 query、path 变量 `:id` 形式）、body.raw（JSON 字符串）均可直接转换为 curl 请求；
- 依赖变量引用采用 Postman `{{var}}` 语法（如 `{{coreBaseUrl}}`、`{{token}}`、路径中的 `:id`），脚本需实现变量替换引擎；
- 13 个 baseUrl 变量默认 localhost 端口，SIT 环境收敛为网关域名时需统一替换。

## 4. 关键发现与缺失项

| 编号 | 发现/缺失 | 影响 |
|------|-----------|------|
| api-G1 | 接口清单可由 api.json 全量提取，脚本无需手写 1000 接口定义 | 执行引擎应以 api.json 为唯一接口来源，杜绝双维护 |
| api-G2 | api.json 无依赖关系信息 | 依赖编排需脚本侧自定义（分层编排已决策） |
| api-G3 | 398 个接口无鉴权头（健康检查、公开接口、内部接口混布） | 断言与 SKIP 规则需按接口逐个配置 |
| api-G4 | 路径参数 `:id` 与 Postman 变量 `{{var}}` 两种占位并存 | 变量替换引擎需同时支持两种语法 |
| api-G5 | 44 个接口用查询参数 `asdmPat` 鉴权（非请求头） | 鉴权注入需支持 query 参数追加 |
| api-G6 | api.json 版本为 v1.3.11 快照（与被测源码 asdm_v1.3.11 同版本） | 接口演进时需重新导出并 diff |

## 5. 与其他代码库的交互

- 生成来源：被测系统 `D:\workspace\ASDM\asdm-admin\asdm_v1.3.11\asdm-admin`（代码静态分析自动生成），详见 [FT-060-api-auto-test-shell-CodeResearch-asdm-admin.md](./FT-060-api-auto-test-shell-CodeResearch-asdm-admin.md)；
- 脚本消费方式：执行引擎遍历 `item` 树展平为接口清单（域/服务/模块/接口四元组）。

## 6. 待确认问题清单

1. SIT 网关（`https://asdm-sit.leansoftx.com/`）是否按服务路径前缀路由全部 13 个服务（实跑验证）；
2. 路径中 `:id` 占位符对应的实际 id 来源（上下文变量捕获表，详细设计阶段定义）。
