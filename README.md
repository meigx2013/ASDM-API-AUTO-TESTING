# ASDM-API-AUTO-TESTING

ASDM Admin 后端接口自动化测试工程（FT-060）。以 `docs/api.json`（Postman v2.1，1000 接口 / 12 业务域 / 13 服务）为唯一接口来源，Bash + curl + node/jq 实现每日一键回归。

## 快速开始

```bash
# 1. 配置凭据（config/env.sh 填写，或用环境变量 / CLI 注入）
vi config/env.sh    # LOGIN_EMAIL / LOGIN_PASSWORD / ASDM_PAT 等

# 2. 全量执行（默认 SIT 环境）
bash scripts/run.sh

# 3. 指定业务域快速验证
bash scripts/run.sh --domains 认证授权域,项目管理域

# 4. 动态传参（优先级: CLI > 环境变量 > 配置文件）
bash scripts/run.sh --base-url https://asdm-dt01.leansoftx.com --timeout 60 --login-email=a@b.com

# 已有长效 JWT 时可跳过登录
ASDM_TOKEN=<jwt> bash scripts/run.sh --domains 认证授权域
```

## 退出码

| 码 | 语义 |
|:--:|------|
| 0 | 全部 PASS/SKIP（无 FAIL） |
| 1 | 存在 FAIL 接口 |
| 2 | 关键链路中止（配置缺失 / 域名非法 / 登录失败） |

## 工程结构

```
scripts/run.sh            唯一入口（参数解析 / 五层管线 / 退出码）
scripts/lib/common.sh     json_get(jq/node降级) / http_request / 日志 / 脱敏
scripts/lib/loader.sh     api.json 展平装载（+ flatten.js）
scripts/lib/vars.sh       变量表与渲染接线（+ vars-build.js / render.js）
scripts/lib/auth.sh       L1 登录鉴权（data.token 双校验，防 HTTP 200+401 陷阱）
config/env.sh             环境地址与凭据（留空触发 SKIP / 登录前置校验）
config/params.json        业务参数（common + 按域）
config/iface.json         域开关 / domainOrder / 响应类型 / route 映射 / 接口断言资产
logs/                     执行日志（run-<时间戳>.log）
reports/                  测试报告（Phase 3 交付）
```

## 当前进度（Phase 1 已完成）

- ✅ 工程骨架与配置加载（三层参数优先级 / L0 校验 / 尾斜杠规范化）
- ✅ api.json 展平（1000 接口零遗漏）与单接口执行通路（变量替换 / baseUrl 收敛 / 双 Authorization 去重 / 进度日志）
- ✅ L1 登录鉴权与 TOKEN 捕获（admin-G5 双校验）
- ⏳ Phase 2：断言引擎 / 自建数据闭环 / 业务域编排（当前非 GET 接口 SKIP 待数据闭环）
- ⏳ Phase 3：Markdown 报告 / SIT 全量实跑校准

计划详情见 `docs/planning/Feat/FT-060-api-auto-test-shell/FT-060-api-auto-test-shell-Plan.md`。

## 环境要求

- Git Bash（Windows）或 Linux；curl；**node 必需**（展平/渲染引擎），jq 可选（存在时用于 json_get 加速）
- SIT 网关可达；凭据缺失的外部依赖接口自动 SKIP，不产生误报 FAIL
