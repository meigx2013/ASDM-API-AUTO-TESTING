# FT-060 接口自动化测试Shell脚本 实施计划

> **🔗 前置文档引用**：本计划基于 [FT-060-api-auto-test-shell-Feature-Overall.md](./FT-060-api-auto-test-shell-Feature-Overall.md)（概要设计）与 [FT-060-api-auto-test-shell-Feature-Detailed.md](./FT-060-api-auto-test-shell-Feature-Detailed.md)（详细设计）拆解生成，任务编号与详细设计 DoD（D1~D21）的映射关系在各任务中标注。

> 最后更新：2026-11-26

---

## 项目概述

本计划将 FT-060 的设计落地为 8 个可独立验证的任务，分三个 Phase 实施：

1. **Phase 1 工程骨架与最小执行通路**：搭好 `scripts/` + `config/` 骨架、api.json 展平加载器与单接口执行通路、登录鉴权层；
2. **Phase 2 断言引擎与编排核心**：实现断言引擎（响应三分法 + 五级判定链）、自建数据闭环（上下文捕获 + `:id` 路由 + 清理）、业务域编排与域过滤；
3. **Phase 3 报告与实跑校准**：实现 Markdown 报告生成，SIT 全量实跑并校准 iface.json 断言资产。

### 前置依赖

- `docs/api.json` v1.3.11 快照已就位（1000 接口，本工作区 `docs/` 下）；
- SIT 环境可访问（`https://asdm-sit.leansoftx.com/`），登录账号等凭据由测试人员填入 `config/env.sh`；
- 运行环境具备 Git Bash 或 Linux + curl，且 jq 与 node 至少其一可用。

### 后续依赖

- 无下游特性依赖本计划；
- 产出脚本可作为后续 CI 定时回归的消费方（退出码 0/1/2 直接对接 CI 判定）。

---

## 进度概要

| Phase | 任务 | 状态 | 交付物 |
|-------|------|:----:|--------|
| Phase 1 | 任务 1.1: 工程骨架与配置加载 | ✅ | `scripts/run.sh`、`scripts/lib/common.sh`、config 三件套 |
| Phase 1 | 任务 1.2: api.json 展平与单接口执行通路 | ✅ | `scripts/lib/loader.sh`、`scripts/lib/vars.sh`、进度日志 |
| Phase 1 | 任务 1.3: L1 登录鉴权与 TOKEN 捕获 | ✅ | `scripts/lib/auth.sh` |
| Phase 2 | 任务 2.1: 断言引擎 | ⏳ | `scripts/lib/assert.sh` |
| Phase 2 | 任务 2.2: 自建数据闭环与上下文捕获 | ⏳ | `scripts/lib/prepare.sh`、`scripts/lib/cleanup.sh`、`:id` 路由 |
| Phase 2 | 任务 2.3: L3 业务域编排与域过滤 | ⏳ | 域编排调度、`--domains` 依赖补齐、退出码判定 |
| Phase 3 | 任务 3.1: Markdown 报告生成 | ⏳ | `scripts/lib/report.sh`、报告六章节、latest 副本 |
| Phase 3 | 任务 3.2: SIT 全量实跑与 iface.json 校准 | ⏳ | 校准后的 iface.json、基线报告、双端冒烟记录 |

---

## Phase 1: 工程骨架与最小执行通路

### 目标

建立 `scripts/` + `config/` 工程骨架，打通「api.json 展平 → 变量替换 → 单接口执行 → 进度日志」与「登录鉴权 → TOKEN 捕获」两条最小通路，Phase 结束时可用真实凭据对少量接口跑出 PASS。

### 任务 1.1: 工程骨架与配置加载

#### 配置要点

| 文件/变量 | 用途 | 必填 |
|-----------|------|:----:|
| `scripts/run.sh` | 唯一入口：解析 `--base-url/--domains/--timeout/--key=value/--keep/--help`，调度五层管线，判定退出码 0/1/2 | 是 |
| `scripts/lib/common.sh` | 公共函数：`json_get`（jq 探测 / node 降级）、`log_line`/`log_summary` 日志、`http_request`（curl 封装：状态码与 `time_total` 元数据分离采集）、base-url 尾斜杠规范化 | 是 |
| `config/env.sh` | 环境地址 + 登录凭据 + 5 类外部凭据 + 3 个 per-service internal-token（默认值留空） | 是 |
| `config/params.json` | 业务参数（common + 按域两段） | 是 |
| `config/iface.json` | 域开关、`domainOrder`、`responseTypeDefault`、`prepare`、`route`、`interfaces` 六个配置域 | 是 |

核心逻辑（对应 DoD D10~D14、D19）：

- 参数优先级实现为三层覆盖：CLI `--key=value` > 环境变量（如 `ASDM_BASE_URL`）> 配置文件；
- L0 校验：jq/node 至少其一可用（否则 exit 2）、三份配置文件存在且可解析（否则 exit 2）、`--domains` 值与 iface.json 域清单交集校验；
- base-url 尾斜杠规范化：装载时去除尾部 `/`，防止拼接出 `//api/...` 被网关 404；
- 动态传参仅作用于本次执行，禁止回写配置文件。

#### 交付物

- `scripts/run.sh`（含 `--help` 输出）
- `scripts/lib/common.sh`
- `config/env.sh`（含凭据填写注释模板）、`config/params.json`、`config/iface.json`（初始骨架）
- `reports/`、`logs/` 目录（含 `.gitkeep`）

#### 验证步骤

- [x] **V1.1.1** 执行帮助命令 → 输出全部参数说明及默认值（SIT 地址、timeout 30s、keep 10）
  `bash scripts/run.sh --help`
- [x] **V1.1.2** 检查三份配置文件与输出目录就位 → 全部存在且 JSON 可解析
  `ls config/ reports/ logs/ && cat config/iface.json | jq .`
- [x] **V1.1.3** 临时移除 `config/iface.json` 后启动 → 退出码 2 且错误信息指明缺失文件名
  `mv config/iface.json /tmp/ && bash scripts/run.sh; echo "exit=$?"; mv /tmp/iface.json config/`
- [x] **V1.1.4** `json_get` 探测与降级 → 有 jq 时走 jq；屏蔽 jq 后走 node，两次取值一致
  `bash -c 'source scripts/lib/common.sh; json_get "{\"a\":1}" ".a"'`（本机无 jq，node 路径实测通过：`.a`/`$.data.token`/`.code` 取值正确，null 路径退出码 1）
- [x] **V1.1.5** 尾斜杠规范化 → `--base-url` 传带斜杠地址，日志中的请求 URL 无 `//` 路径
  `bash scripts/run.sh --base-url https://asdm-sit.leansoftx.com/ --domains 认证授权域 2>&1 | grep -c '//api'`（实测 0）
- [x] **V1.1.6** 参数优先级 → 配置文件、环境变量、CLI 三层各设不同值，日志回显生效值为 CLI 值
  `bash scripts/run.sh --base-url https://cli.example.com 2>&1 | head -5`（三层回显：cli.example.com > env.example.com > sit 默认）

### 任务 1.2: api.json 展平与单接口执行通路

#### 核心逻辑

对应 DoD D1、D5、D6（loader + 变量替换 + baseUrl 收敛）：

1. `loader.sh` 递归遍历 `docs/api.json` 的 `item` 树，展平为接口清单（四元组：域/服务/方法/路径），统计总数与各服务计数；
2. `vars.sh` 实现双语法占位替换：先将 `:id` 按 iface.json `route` 归一为 `{{var}}`，再做变量表统一替换（环境类/凭据类/上下文类/业务参数类），`body.raw` 替换后校验 JSON 合法性；
3. baseUrl 收敛：13 个 `{{xxxBaseUrl}}` 变量统一装载为网关域名，env.sh 的 `SERVICE_BASE_URL_*` 可逐服务覆盖；
4. `http_request` 以 curl 执行：`-o` 落盘响应体、`-w` 分离采集 HTTP 状态码与 `time_total`、`--max-time` 取 `--timeout` 值（默认 30s）；
5. 进度日志逐接口输出 `[序号/总数][域][方法][路径] 结果 状态码 耗时` 并写 `logs/run-<ts>.log`。

#### 交付物

- `scripts/lib/loader.sh`（接口清单加载与统计）
- `scripts/lib/vars.sh`（占位符替换引擎 + 变量表装载）
- `http_request` 函数（common.sh 内实现并接线）
- 进度日志通路（终端回显 + `logs/run-YYYYMMDD-HHMMSS.log` 落盘）

#### 验证步骤

- [x] **V1.2.1** 展平统计与调研一致 → 接口总数 1000、服务数与 core 100/integration 82 等分布吻合
  `bash -c 'source scripts/lib/loader.sh; load_interfaces; echo "total=$TOTAL"'`（实测 total=1000，GET566/POST281/PUT63/DELETE70/PATCH20，域/服务条目分布与调研完全吻合）
- [x] **V1.2.2** 清单四元组字段完整 → 每条记录含域/服务/方法/路径
  `bash -c 'source scripts/lib/loader.sh; load_interfaces; list_first'`（首条：域=认证授权域 服务=core 方法=POST 路径={{coreBaseUrl}}/api/auth/change-password）
- [x] **V1.2.3** 单接口执行（选一个无鉴权 GET 接口）→ 输出 PASS 进度行且含状态码与耗时
  `bash scripts/run.sh --domains 认证授权域 2>&1 | head -3`（实测 `[6/53][认证授权域][GET][/api/auth/register-status] PASS 200 0.458675s`；第 1/2 条为非 GET SKIP 属预期；前 3 条含 PASS 需有效凭据，本机以 ASDM_TOKEN 直通验证通路）
- [x] **V1.2.4** baseUrl 收敛生效 → 进度日志中的完整请求 URL 为网关域名而非 localhost 端口
  `grep -o 'https://[^ ]*' logs/run-*.log | sort -u | head -5`（实测仅 https://asdm-sit.leansoftx.com 及其路径）
- [x] **V1.2.5** 元数据分离采集 → 同一次执行可分别取到状态码与响应时间两个独立值
  `bash -c 'source scripts/lib/common.sh; http_request GET https://asdm-sit.leansoftx.com/api/health; echo "code=$HTTP_CODE time=$TIME_TOTAL"'`（实测 code=200 time=0.340688 独立输出）
- [x] **V1.2.6** 日志落盘 → `logs/` 下生成 `run-<时间戳>.log` 且包含进度行
  `ls logs/ && tail -5 logs/run-*.log`（实测 run-20261126-172425.log 含全部 53 条进度行与汇总）

### 任务 1.3: L1 登录鉴权与 TOKEN 捕获

#### 核心逻辑

对应 DoD D4（TOKEN 捕获）与 admin-G5 陷阱应对：

1. `auth.sh` 执行 `POST /api/auth/login`（email/password 取参数体系，body 走 vars.sh 替换）；
2. 断言按 6.2 特判规则：**解析 `data.token` 存在性**（HTTP 200 + code=401 的登录失败陷阱不能只看状态码）；
3. 成功后 TOKEN 写入凭据变量表，供 501 个 Bearer JWT 接口替换消费；
4. 失败即中止（exit 2），输出凭据核对提示（账号来源、环境地址）；凭据未配置时前置校验直接失败，不发空请求。

#### 交付物

- `scripts/lib/auth.sh`
- TOKEN 上下文捕获（`$.data.token` → `TOKEN`）
- L1 失败中止与错误提示输出

#### 验证步骤

- [ ] **V1.3.1** 填入有效 SIT 凭据后执行 L1 → TOKEN 捕获成功且非空
  `bash -c 'source scripts/lib/common.sh; source scripts/lib/auth.sh; do_login && echo "token_len=${#TOKEN}"'`（待测试人员提供真实凭据后执行；通路已用 ASDM_TOKEN 直通机制验证变量表写入与 Bearer 注入）
- [x] **V1.3.2** 填入错误密码 → 识别 HTTP 200 + code=401 陷阱并判定失败，退出码 2，输出凭据核对提示
  `bash scripts/run.sh 2>&1 | tail -3; echo "exit=$?"`（实测：错误凭据登录 → `[L1] 登录失败（admin-G5 双校验: HTTP 状态 200 / 业务码 401）` + 凭据核对提示，exit=2）
- [ ] **V1.3.3** TOKEN 注入后带 Bearer 调用任一 core GET 接口 → HTTP 200（鉴权链路端到端打通）
  `bash -c 'source scripts/lib/common.sh; source scripts/lib/auth.sh; do_login; http_request GET "$ASDM_BASE_URL/api/users?page=1" "Authorization: Bearer $TOKEN"'`（待真实凭据；通路已验证：假 TOKEN 注入 Bearer 头请求 /api/auth/me → HTTP 401 预期拒绝，渲染与头注入正确）
- [x] **V1.3.4** 凭据未配置（LOGIN_EMAIL 为空）→ L1 前置校验失败退出码 2，且未发出任何登录请求
  `bash scripts/run.sh 2>&1 | grep -E "凭据|LOGIN_EMAIL"`（实测：提示凭据未配置，日志无任何登录请求行，exit=2）

---

## Phase 1 实施记录（2026-11-26 完成）

### 交付文件

- `scripts/run.sh`（入口：参数解析/三层优先级/L0 校验/五层管线调度/退出码）
- `scripts/lib/common.sh`（json_get jq/node 降级、http_request 元数据分离、日志、脱敏、尾斜杠规范化）
- `scripts/lib/loader.sh` + `scripts/lib/flatten.js`（api.json 递归展平，实测 1000 接口零遗漏）
- `scripts/lib/vars.sh` + `scripts/lib/vars-build.js`（变量表装载 + 13 baseUrl 收敛 + per-service 覆盖）
- `scripts/lib/render.js`（占位符渲染引擎：`:id` 归一、`{{var}}` 替换、双 Authorization 去重、body JSON 校验）
- `scripts/lib/auth.sh`（L1 登录 + admin-G5 双校验 + TOKEN 写入变量表）
- `config/env.sh`、`config/params.json`、`config/iface.json`（骨架）、`reports/`、`logs/`

### 关键实现决策（与设计的偏差与补充）

1. **node 辅助脚本 3 个**（flatten/vars-build/render）：展平与渲染为复杂 JSON 结构转换，统一用 node 实现（json_get 层面仍保持 jq/node 双路径）；node 为渲染管线必需依赖，L0 校验 jq/node 至少其一（本机无 jq 实测 node 路径全通）。
2. **TSV 分隔符改用 0x1F（八进制 \037）**：bash `read` 会将连续 tab（空 body 字段）压缩为单分隔符导致字段左移错位（实测发现并修复），0x1F 为非 IFS 空白字符不受压缩。
3. **L3 安全阀**：Phase 1 仅执行 GET 接口（非 GET 记 SKIP「非GET接口待Phase2数据闭环」），防止破坏性接口在自建数据闭环（Phase 2）就绪前污染 SIT；判定为简化版（HTTP <400 即 PASS），Phase 2 由断言引擎接管。
4. **ASDM_TOKEN 直通**：提供 `ASDM_TOKEN` 环境变量时跳过登录（复用 30 天 JWT / 无凭据调试通路），参照同体系 Ai-Fast asdm-api-test 先例。
5. **login 请求体不走 api.json 示例值**：从参数体系（LOGIN_EMAIL/LOGIN_PASSWORD）经 node JSON.stringify 构造，密码特殊字符安全。

### 验证结果汇总

V1.1.1~V1.1.6、V1.2.1~V1.2.6、V1.3.2、V1.3.4 实测通过（详见证步骤备注）；V1.3.1/V1.3.3 需测试人员填入真实 SIT 凭据后执行（通路已用 ASDM_TOKEN 直通验证）。端到端单域实跑：`--domains 认证授权域` 53/53 三态全覆盖（PASS=2 FAIL=18 SKIP=33，假 TOKEN 下 401 属预期），退出码 1 语义正确。

---

## Phase 2: 断言引擎与编排核心

### 目标

实现断言引擎五级判定链、自建数据闭环（上下文捕获 + `:id` 路由 + 清理层）、业务域编排与 `--domains` 依赖补齐，Phase 结束时可在 SIT 上完成多域接口的正确三态判定与破坏性接口闭环。

### 任务 2.1: 断言引擎

#### 校验范围

对应 DoD D7、D8、D18，按响应类型与判定链组织：

| 校验对象 | 校验规则 |
|----------|----------|
| 响应类型判定 | WRAPPED（校验 code==200）/ BARE（仅 HTTP 状态）/ NON_JSON（仅 HTTP 状态，重定向类 2xx/3xx 均可），按服务默认 + 接口覆盖 |
| 连接失败 | curl exit 7 / HTTP 000 → 失败原因「连接失败」 |
| 请求超时 | curl exit 28 或达 `--timeout` → 失败原因「请求超时」 |
| HTTP 状态 | 默认预期 2xx，iface.json `expectedHttp` 按接口覆盖（如删除类 200/204、错误场景 400/404） |
| 业务码 | WRAPPED 类型 code == `expectedCode`（默认 200，非 0） |
| 响应解析 | WRAPPED 响应体无法解析为 JSON → 失败原因「响应解析失败」 |
| SKIP | 凭据缺失 / 域未启用 / 路径参数缺失 → SKIP 并注明原因，不计失败 |
| 慢接口 | `time_total` > 3s → ⚠️ 标记，独立维度不影响 PASS/FAIL |

#### 交付物

- `scripts/lib/assert.sh`（类型判定 + 五级判定链 + 失败原因五分类 + SKIP 四分类 + 慢接口标记）
- 失败接口的响应体摘要采集（截断 200 字符）
- iface.json `responseTypeDefault` 与 `interfaces[].expectedHttp/expectedCode` 接线

#### 验证步骤

- [ ] **V2.1.1** WRAPPED 接口返回 HTTP 200 + code=200 → 判定 PASS
  `bash scripts/run.sh --domains 认证授权域 2>&1 | grep -c ' PASS '`
- [ ] **V2.1.2** 构造业务码非预期场景（错误参数请求）→ 判定 FAIL 且失败原因为「业务码非预期」
  `bash scripts/run.sh --domains 认证授权域 2>&1 | grep '业务码非预期' | head -2`
- [ ] **V2.1.3** sso 域（NON_JSON，302 重定向）→ 仅状态码判定，2xx/3xx 判 PASS 不报解析失败
  `bash scripts/run.sh --domains sso域 2>&1 | grep -E 'sso.*PASS' | head -2`
- [ ] **V2.1.4** 以 `--timeout 1` 执行含慢接口的域 → 该接口 FAIL 且原因为「请求超时」，其余接口不受影响
  `bash scripts/run.sh --timeout 1 --domains telemetry域 2>&1 | grep '请求超时' | head -2`
- [ ] **V2.1.5** `--base-url` 指向无效域名 → 全部接口 FAIL 且原因为「连接失败」
  `bash scripts/run.sh --base-url https://invalid.example.com --domains 认证授权域 2>&1 | grep -c '连接失败'`
- [ ] **V2.1.6** `CITIC_SECRET` 留空 → 依赖该凭据的接口 SKIP 且原因为「凭据缺失」，无误报 FAIL
  `bash scripts/run.sh --domains citic域 2>&1 | grep 'SKIP' | head -3`
- [ ] **V2.1.7** 响应超 3s 的接口 → 明细行带 ⚠️ 标记且判定仍为 PASS
  `grep '⚠️' reports/latest.md | head -3`

### 任务 2.2: 自建数据闭环与上下文捕获

#### 核心逻辑

对应 DoD D4、D9（L2 数据准备 + 上下文捕获 + `:id` 路由 + L4 清理）：

1. `prepare.sh` 按 iface.json `prepare` 清单执行创建接口，PASS 后立即按 `capture` 规则提取 id 写入 `CAPTURED.*`（初始最小集：projectId/userId/workspaceId，`$.data.id` 表达式）；
2. `route` 映射：`:projectId` → `{{CAPTURED.projectId}}` 等；未映射且 params.json 无兜底值的 `:id` → SKIP「路径参数缺失」；
3. `cleanup.sh` 逆序删除自建数据，失败仅记录（输出残留清单），不改退出码；`--keep-data` 跳过清理保留现场；
4. 破坏性接口（PUT/DELETE/PATCH，153 个）全部作用于自建数据，先创建后变更后删除闭环。

#### 交付物

- `scripts/lib/prepare.sh`（L2 数据准备 + 捕获）
- `scripts/lib/cleanup.sh`（L4 清理 + 残留清单 + `--keep-data`）
- iface.json `route` 映射表与 `prepare` 清单的执行接线

#### 验证步骤

- [ ] **V2.2.1** L2 创建项目接口执行 → `CAPTURED.projectId` 捕获成功且非空
  `bash scripts/run.sh --domains 项目管理域 2>&1 | grep 'CAPTURED' | head -2`
- [ ] **V2.2.2** `:projectId` 路由替换 → GET 项目详情返回新建项目（200 + 项目名匹配）
  `bash scripts/run.sh --domains 项目管理域 2>&1 | grep 'auto-test-proj' | head -2`
- [ ] **V2.2.3** 破坏性闭环 → DELETE 自建项目 PASS；再次 GET 该项目 → 404（先创建后删除闭环成立）
  `grep -A2 'auto-test-proj' reports/latest.md | head -6`
- [ ] **V2.2.4** `--keep-data` 生效 → 清理层跳过，SIT 环境可查到残留的自建数据（排障场景）
  `bash scripts/run.sh --keep-data --domains 项目管理域 2>&1 | grep -i 'keep'`
- [ ] **V2.2.5** 未映射 `:id` 且 params 无兜底 → SKIP 且原因为「路径参数缺失」
  `bash scripts/run.sh --domains integration域 2>&1 | grep '路径参数缺失' | head -3`
- [ ] **V2.2.6** 清理失败容错 → 模拟删除 404 时仅记录残留清单，整体退出码不受影响
  `grep '残留' logs/run-*.log | head -3`

### 任务 2.3: L3 业务域编排与域过滤

#### 核心逻辑

对应 DoD D2、D3（域编排 + 过滤 + 依赖补齐 + 退出码）：

1. 按 iface.json `domainOrder` 顺序逐域执行，域内按展平原序；core 系域优先、adapter 外部依赖域殿后；
2. `--domains` 过滤时执行依赖补齐：所选域的 `dependsOn` 前置域未在过滤集内 → 自动纳入前置域最小集（含其 L2 数据准备），保证上下文变量可用；
3. 域开关（持久配置）与 `--domains`（本次过滤）取交集生效，未启用域在报告汇总标注「未启用」；
4. 每 100 条输出心跳汇总行：`已执行 N/1000 | PASS=x FAIL=y SKIP=z`；
5. 退出码判定：全部 PASS/SKIP → 0；存在 FAIL → 1；L0/L1/L2 关键失败 → 2。

#### 交付物

- run.sh 中 L3 编排调度与心跳汇总输出
- `--domains` 过滤与依赖补齐逻辑
- 退出码 0/1/2 判定实现（CI 可直接消费）

#### 验证步骤

- [ ] **V2.3.1** 全量执行 → 日志按 `domainOrder` 顺序逐域推进且心跳汇总行周期出现
  `bash scripts/run.sh 2>&1 | grep '已执行' | tail -3`
- [ ] **V2.3.2** 单域过滤 → 仅该域接口执行、总执行条数显著小于 1000、耗时显著缩短
  `bash scripts/run.sh --domains 认证授权域 2>&1 | tail -2`
- [ ] **V2.3.3** 依赖补齐 → 选 agentorbit 域执行时 core 前置数据准备自动纳入（日志可见 core 域前置接口）
  `bash scripts/run.sh --domains agentorbit域 2>&1 | grep -E 'core' | head -3`
- [ ] **V2.3.4** 域开关关闭某域且不带 `--domains` → 该域不出现在明细且汇总标注「未启用」
  `grep '未启用' reports/latest.md`
- [ ] **V2.3.5** 退出码语义 → 全 PASS/SKIP 为 0；存在 FAIL 为 1；登录失败为 2
  `bash scripts/run.sh --domains 认证授权域; echo "exit=$?"`

---

## Phase 3: 报告与实跑校准

### 目标

实现 Markdown 报告六章节生成与历史保留，完成 SIT 全量实跑并依据失败明细校准 iface.json 断言资产，产出首个基线报告。

### 任务 3.1: Markdown 报告生成

#### 核心逻辑

对应 DoD D15~D18（R4/R5 验收），报告结构：

| 章节 | 内容 |
|------|------|
| 执行概览 | 环境、执行时间、总耗时、总数、PASS/FAIL/SKIP 数、平均响应时间 |
| 失败明细 | 🔴 失败接口逐条：名称/方法/路径/失败原因（五分类）/响应体摘要（≤200 字符）/响应时间 |
| 慢接口清单 | ⚠️ 超 3s 接口按耗时降序 |
| SKIP 清单 | SKIP 接口逐条注明原因（四分类） |
| 全量明细 | 每接口一行：名称/方法/请求路径/状态/响应时间（域分组 + 域小计） |
| 域汇总 | 按域 PASS/FAIL/SKIP 统计，未启用域标注 |

- 输出 `reports/api-test-report-YYYYMMDD-HHMMSS.md` + `latest.md` 副本；
- 自动保留最近 N 份（默认 10，`--keep` 可配），超出删除最旧。

#### 交付物

- `scripts/lib/report.sh`（六章节渲染 + latest 副本 + 历史保留）

#### 验证步骤

- [ ] **V3.1.1** 执行完成 → 时间戳报告与 `latest.md` 副本均生成
  `ls reports/ | head -3 && ls reports/latest.md`
- [ ] **V3.1.2** 报告六章节齐备 → 逐章节标题存在
  `grep -E '^## ' reports/latest.md`
- [ ] **V3.1.3** 失败明细 → 每条含五分类原因之一且响应体摘要不超过 200 字符
  `awk '/失败明细/,/慢接口/' reports/latest.md | head -8`
- [ ] **V3.1.4** 全量明细 → 每接口一行且含名称/方法/路径/状态/响应时间五要素
  `awk '/全量明细/,/域汇总/' reports/latest.md | head -5`
- [ ] **V3.1.5** 历史保留 → 连续执行超过 N 次后报告总数收敛为 N 份
  `ls reports/*.md | grep -v latest | wc -l`
- [ ] **V3.1.6** 概览数据一致 → 平均响应时间与总耗时与日志心跳汇总吻合
  `head -20 reports/latest.md && tail -3 logs/run-*.log`

### 任务 3.2: SIT 全量实跑与 iface.json 校准

#### 校验范围

对应 DoD D20、D21（实跑校准 + 双端兼容），校准对象为 iface.json 断言资产：

| 校准项 | 依据 |
|--------|------|
| `route` 映射表 | 全量实跑中 SKIP「路径参数缺失」的接口逐个补充 `:id` 映射来源 |
| `capture` 捕获规则 | 失败明细中因前置数据缺失而失败的接口补充捕获表达式 |
| `expectedHttp/expectedCode` | 失败明细中确认非缺陷的接口（如 404 语义、非 200 成功码）配置预期值 |
| `responseType` | 报「响应解析失败」的接口复核类型归属（BARE/NON_JSON） |
| adapter 域策略 | adapter-* 失败明细标注外部依赖类别（Azure DevOps/GitLab/CodeArts），必要时域开关默认关闭 |
| 网关路由 | 各域 baseUrl 连通性，不可路由服务整域调整 `SERVICE_BASE_URL_*` |

#### 交付物

- 校准后的 `config/iface.json`（全量接口断言资产首版）
- SIT 全量实跑基线报告（归档于 reports/，作为每日回归对比基准）
- Git Bash 与 Linux 双端冒烟记录（各跑单域一次，行为一致）

#### 验证步骤

- [ ] **V3.2.1** 全量实跑 → 1000 接口三态全覆盖（PASS+FAIL+SKIP=1000）且报告完整生成
  `bash scripts/run.sh; echo "exit=$?"; head -20 reports/latest.md`
- [ ] **V3.2.2** 校准迭代 → 依据首轮失败明细扩充 iface.json 后二次实跑，误报 FAIL 数较首轮下降
  `grep -c '🔴' reports/api-test-report-*.md | tail -2`
- [ ] **V3.2.3** adapter 域外部依赖标注 → 报告失败明细区分「被测服务故障」与「外部依赖不可达」
  `grep -E 'Azure DevOps|GitLab|CodeArts' reports/latest.md | head -3`
- [ ] **V3.2.4** 双端兼容冒烟 → Git Bash 与 Linux（或 WSL）各执行单域，进度行与退出码一致
  `bash scripts/run.sh --domains 认证授权域 2>&1 | tail -1`
- [ ] **V3.2.5** 基线归档 → 最终基线报告时间戳文件名固定并登记到本任务交付物（供每日回归对比）
  `ls reports/ | grep api-test-report | tail -1`

---

## 实施顺序建议

1. 任务 1.1 → 任务 1.2 → 任务 1.3（骨架内顺序依赖：配置加载是加载器与登录的前置）；
2. 任务 2.1 → 任务 2.2 → 任务 2.3（断言是闭环与编排的判定依赖；闭环是编排的数据依赖）；
3. 任务 3.1 → 任务 3.2（报告是实跑校准的观测工具）；
4. 任务 3.2 过程中如发现接口资产缺口，回补 iface.json 后重跑任务 3.2 的验证步骤闭环（校准为迭代性质，不回退代码任务）。

## 风险与挑战

| 风险 | 影响 | 应对措施 |
|------|------|----------|
| SIT 凭据未及时提供（登录账号/internal-token/oat 等） | 登录链路无法验证，任务 1.3/2.2/3.2 阻塞 | 任务 1.3 起即向测试人员索取凭据清单；凭据敏感项缺失不阻塞其余任务（SKIP 语义已内建设计） |
| adapter-* 域外部依赖不可达 | 全量实跑大量 FAIL 干扰判读（任务 3.2 校准困难） | 报告区分外部依赖类别；必要时 adapter 域默认关闭，域开关恢复后再校准 |
| `:id` 来源无法静态推导 | 破坏性接口与详情接口大面积 SKIP | 设计已定 SKIP 策略不产生误报；任务 3.2 依据失败明细渐进扩充 route 表 |
| HTTP 200 + 错误码陷阱类型未全覆盖 | 个别接口误判 PASS | 断言引擎 WRAPPED 默认开启 code 校验（任务 2.1），误判面已收敛到 BARE 类型 |
| 清理失败导致环境残留 | SIT 环境脏数据累积 | 任务 2.2 残留清单输出 + `--keep-data` 显式保留现场；每日实跑前先清理前日残留 |
| 网关路由规则与预期不符（路径前缀/子域） | 整域连接失败 | 任务 3.2 首轮实跑即验证 13 服务路由，`SERVICE_BASE_URL_*` 逐服务覆盖兜底 |

## 变更模块总览

| 变更模块 | 涉及 Phase | 核心变更 |
|----------|-----------|----------|
| `scripts/run.sh` | P1~P3 | 入口、参数解析、五层管线调度、退出码判定 |
| `scripts/lib/`（7 个库文件） | P1~P3 | common/loader/vars/auth 断言闭环编排报告（loader、vars、common 于 P1；auth 于 P1；assert/prepare/cleanup 于 P2；report 于 P3） |
| `config/env.sh` + `params.json` | P1 | 环境凭据与业务参数体系 |
| `config/iface.json` | P1（骨架）→ P3（校准扩充） | 域开关、域顺序、断言资产、捕获规则 |
| `reports/` | P3 | Markdown 报告输出与历史保留 |
| `logs/` | P1 起 | 执行日志逐接口落盘 |

---

**文档版本**：1.1.0
**最后更新**：2026-11-26（Phase 1 完成）
**维护者**：meiguangxuan
