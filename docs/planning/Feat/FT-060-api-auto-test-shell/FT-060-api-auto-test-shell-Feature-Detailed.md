# FT-060 接口自动化测试Shell脚本特性文档

> **🔗 前置文档引用**：本文档基于 [FT-060-api-auto-test-shell-Feature-Overall.md](./FT-060-api-auto-test-shell-Feature-Overall.md)（概要设计文档）编写。Overall 中的总体概述、使用场景、核心概念等是本详细设计的直接输入来源，并融合了两份代码调研的结论（[api.json 调研](./FT-060-api-auto-test-shell-CodeResearch-api-json.md)、[asdm-admin 调研](./FT-060-api-auto-test-shell-CodeResearch-asdm-admin.md)）。

> 最后更新：2026-11-26

---

## 修订记录

| 版本 | 日期 | 修订人 | 修订内容 |
|------|------|--------|----------|
| 1.0.0 | 2026-11-26 | meiguangxuan | 初始版本（基于 Overall + 双库调研完成详细设计） |

---

## 目录

- [1. 总体概述](#1-总体概述)
  - [1.1 背景与目标](#11-背景与目标)
  - [1.2 核心价值](#12-核心价值)
  - [1.3 变更范围](#13-变更范围)
  - [1.4 关键技术决策](#14-关键技术决策)
- [2. 使用场景](#2-使用场景)
  - [2.1 每日全量接口回归](#21-每日全量接口回归)
  - [2.2 指定业务域快速验证](#22-指定业务域快速验证)
  - [2.3 参数维护与动态传参](#23-参数维护与动态传参)
  - [2.4 报告查看与失败定位](#24-报告查看与失败定位)
  - [2.5 慢接口与超时排查](#25-慢接口与超时排查)
- [3. 总体架构与文件组织](#3-总体架构与文件组织)
  - [3.1 执行架构](#31-执行架构)
  - [3.2 文件清单](#32-文件清单)
  - [3.3 运行入口与退出码](#33-运行入口与退出码)
- [4. 执行编排设计](#4-执行编排设计)
  - [4.1 五层执行管线](#41-五层执行管线)
  - [4.2 域顺序与依赖补齐](#42-域顺序与依赖补齐)
  - [4.3 上下文变量捕获](#43-上下文变量捕获)
- [5. 变量替换与鉴权注入设计](#5-变量替换与鉴权注入设计)
  - [5.1 变量分类与优先级](#51-变量分类与优先级)
  - [5.2 占位符替换引擎](#52-占位符替换引擎)
  - [5.3 鉴权注入机制](#53-鉴权注入机制)
- [6. 断言引擎设计](#6-断言引擎设计)
  - [6.1 响应类型三分法](#61-响应类型三分法)
  - [6.2 判定链与失败原因分类](#62-判定链与失败原因分类)
  - [6.3 SKIP 规则](#63-skip-规则)
  - [6.4 慢接口标记](#64-慢接口标记)
- [7. 配置数据模型](#7-配置数据模型)
  - [7.1 config/env.sh](#71-configenvsh)
  - [7.2 config/params.json](#72-configparamsjson)
  - [7.3 config/iface.json](#73-configifacejson)
- [8. 日志与报告设计](#8-日志与报告设计)
  - [8.1 执行日志](#81-执行日志)
  - [8.2 Markdown 报告](#82-markdown-报告)
- [9. 调研发现应对映射](#9-调研发现应对映射)
- [10. 依赖关系与风险](#10-依赖关系与风险)
- [11. 相关文档](#11-相关文档)
- [12. 完成规范 (DoD)](#12-完成规范-dod)

---

## 1. 总体概述

### 1.1 背景与目标

ASDM Admin 后端提供全量 API 共 1000 个（见 [docs/api.json](../../../docs/api.json)，12 个业务域、25 个服务、5 种鉴权机制）。当前缺乏系统化的接口回归手段，接口验证依赖测试人员手工逐个调用，效率低且无法每日覆盖。

本特性在 `ASDM-API-AUTO-TESTING` 工作区交付一套 Bash 接口自动化测试脚本：测试人员每天执行一次脚本即可完成全部接口的测试，脚本自动完成鉴权获取、依赖数据准备、接口按依赖顺序执行、结果断言、日志输出与 Markdown 报告生成。

> 调研补充：api.json 为被测系统 v1.3.11 的静态分析快照，请求结构完整度高（method/鉴权头/url/body 均可直接转换为 curl 请求），执行引擎以其为唯一接口来源（api-G1），无需手写接口定义；被测系统存在 HTTP 200 + 错误业务码的响应陷阱（admin-G1、admin-G5），断言引擎必须做双校验。

### 1.2 核心价值

- **一键回归**：单命令启动，覆盖 api.json 全量 1000 接口，无需人工干预；
- **参数可维护**：环境凭据与业务参数分离维护，支持手工编辑配置文件与运行时动态传参两种方式；
- **依赖自动编排**：按"登录鉴权 → 数据准备 → 业务域 → 清理"分层编排，依赖数据通过上下文变量自动捕获传递；
- **执行可跟踪**：每个接口输出进度日志（序号/总数/域/方法/路径/结果），PASS/FAIL/SKIP 计数实时汇总；
- **报告即台账**：执行完成产出 Markdown 报告，每接口含名称、方法、请求路径、状态、响应时间，失败接口重点标识并说明原因，同时充当接口资产台账。

### 1.3 变更范围

| 变更模块 | 变更类型 | 功能说明 | 关联需求 |
|----------|:--------:|----------|----------|
| `scripts/` | 🔲 新增 | 测试脚本主体：执行引擎、断言、日志、报告生成 | R1/R3/R4/R5 |
| `config/` | 🔲 新增 | 参数维护入口：env.sh（环境凭据）+ params.json（业务参数）+ iface.json（接口级配置） | R2 |
| `reports/` | 🔲 新增 | Markdown 测试报告输出目录（时间戳报告 + latest 副本） | R5 |
| `logs/` | 🔲 新增 | 执行日志输出目录 | R4 |

### 1.4 关键技术决策

以下决策已在需求访谈中确认（详见 AskMe 文档决策点 1~12）：

| 决策项 | 结论 |
|--------|------|
| 覆盖范围 | 全量 1000 接口 + 域开关（`--domains` 过滤），外部凭据缺失自动 SKIP |
| 默认环境 | SIT（`https://asdm-sit.leansoftx.com/`），`--base-url` / 环境变量可覆盖 |
| 运行平台 | Bash（POSIX 兼容），Git Bash / Linux 双兼容 |
| JSON 解析 | 运行时探测：优先 jq，缺失自动降级 node（封装为统一函数） |
| 参数优先级 | CLI 传参 > 环境变量 > 配置文件 |
| 断言策略 | HTTP 状态码为主 + 响应含 code 字段时校验业务码（可按接口配置预期值） |
| 破坏性接口 | 在脚本自建数据上闭环执行（先创建后删除） |
| 失败处理 | login/token 等关键链路失败立即中止，普通接口失败继续记录 |
| 超时 | curl `--max-time 30s`（`--timeout` 可配），响应时间取 `time_total`，超 3s 标慢接口告警 |

---

## 2. 使用场景

### 2.1 每日全量接口回归

使用者：测试人员（每日例行）。

操作步骤：

1. 打开 Git Bash（或 Linux 终端），进入工作区根目录；
2. 执行 `scripts/run.sh`（无参数，使用配置文件默认 SIT 环境）；
3. 观察终端日志：逐接口输出进度行（序号/总数/域/方法/路径/结果），实时汇总 PASS/FAIL/SKIP 计数；
4. 等待执行完成（登录鉴权层 → 数据准备层 → 业务域层 → 清理层依次执行）；
5. 打开 `reports/latest.md` 查看当日报告。

预期结果：

- 全量 1000 接口均有执行结果（PASS/FAIL/SKIP 三态之一），SKIP 接口在报告中注明原因（如外部凭据缺失）；
- login/token 等关键链路失败时脚本立即中止并输出明确错误信息；
- 普通接口失败不影响后续接口执行，失败原因与响应体摘要（截断 200 字符）记录入报告。

### 2.2 指定业务域快速验证

使用者：测试人员（聚焦验证某次变更影响的域）。

操作步骤：

1. 执行 `scripts/run.sh --domains 认证授权域,项目管理域`，仅执行指定业务域的接口；
2. 也可通过域开关配置临时关闭不需要的域；
3. 执行完成后查看 `reports/latest.md` 中该域的结果明细。

预期结果：

- 仅指定域的接口被执行，执行时长显著缩短；
- 未执行域不出现在报告明细中（或在汇总中标注未启用）；
- 域内接口仍按依赖分层顺序执行（若所选域依赖其他域的数据准备，自动补齐前置依赖链）。

### 2.3 参数维护与动态传参

使用者：测试人员（环境/数据变更时）。

操作步骤：

1. 手工维护方式：编辑 `config/env.sh` 修改环境地址与凭据（baseUrl、登录账号、pat、openAccessToken 等）；编辑 `config/params.json` 修改接口业务参数（请求 body 中的项目名、用户邮箱等）；
2. 动态传参方式：执行时附加参数覆盖配置值，如 `scripts/run.sh --base-url https://asdm-dt01.leansoftx.com --key=value`；
3. 也可通过环境变量传入（如 `ASDM_BASE_URL`）；
4. 脚本按优先级 CLI 传参 > 环境变量 > 配置文件取值。

预期结果：

- 配置文件手工编辑后无需修改脚本即可生效；
- 运行时动态传参仅对本次执行生效，不回写配置文件；
- 凭据缺失时，依赖该凭据的接口自动 SKIP 并在报告中说明，不产生误报 FAIL。

### 2.4 报告查看与失败定位

使用者：测试人员、测试经理（质量汇报）。

操作步骤：

1. 执行完成后打开 `reports/api-test-report-YYYYMMDD-HHMMSS.md`（或 `latest.md` 副本）；
2. 查看报告头部汇总统计：总数、PASS/FAIL/SKIP 数量、总耗时、平均响应时间；
3. 查看失败接口明细章节：失败接口以红色标记重点标识，逐条列出接口名称、方法、请求路径、失败原因（HTTP 状态码非预期 / 业务码非预期 / 超时 / 连接失败）与响应体摘要；
4. 对比历史时间戳报告，观察失败接口趋势。

预期结果：

- 每个接口在报告中均有一行明细：名称、方法、请求路径、状态、响应时间；
- 失败接口集中展示且原因可读，测试人员无需翻查日志即可定位初步原因；
- 报告自动保留最近 N 份，历史报告可通过时间戳文件名追溯。

### 2.5 慢接口与超时排查

使用者：测试人员、后端开发（性能问题跟进）。

操作步骤：

1. 打开执行报告，查看响应时间列中带慢接口告警标记（响应时间超过 3 秒）的接口；
2. 查看超时失败的接口（超过 `--timeout` 配置值，默认 30 秒）及其失败原因；
3. 结合日志 `logs/run-<时间戳>.log` 中的原始请求记录进一步排查。

预期结果：

- 慢接口（>3 秒）在报告中被显式标记，便于日常巡检性能劣化；
- 超时接口判为 FAIL，失败原因明确标注"请求超时"，不阻塞其他接口执行。

---

## 3. 总体架构与文件组织

### 3.1 执行架构

```text
docs/api.json ──(loader 展平)──> 接口清单（域/服务/模块/接口 四元组，1000 条）
                                        │
config/env.sh + params.json + iface.json ──(参数加载：CLI > 环境变量 > 配置文件)
                                        │
scripts/run.sh 五层管线调度
  L0 环境与工具校验 → L1 登录鉴权 → L2 数据准备 → L3 业务域 → L4 清理
                                        │
  每接口执行循环：
    vars.sh 占位符替换 → http_request(curl) → assert.sh 判定 → 上下文捕获
                                        │
    日志逐行写 logs/run-<ts>.log ──> report.sh 生成 reports/<ts>.md + latest.md
```

设计要点：

- **单一数据源**：接口清单只从 api.json 展平生成，脚本侧不复制接口定义（api-G1），杜绝双维护；
- **执行与断言分离**：HTTP 发送（common.sh）与结果判定（assert.sh）解耦，便于断言规则独立演进；
- **配置驱动**：接口级行为（响应类型、预期码、捕获规则、域开关）全部外置到 `config/iface.json`，脚本零硬编码。

### 3.2 文件清单

| 文件 | 层次 | 职责与关键函数 |
|------|------|----------------|
| `scripts/run.sh` | 入口 | CLI 参数解析（`--base-url/--domains/--timeout/--key=value/--keep/--help`）、五层管线调度、汇总输出、退出码判定 |
| `scripts/lib/common.sh` | 公共 | 日志函数 `log_line/log_summary`；JSON 解析 `json_get`（jq 探测、node 降级）；HTTP 发送 `http_request`（curl 封装：状态码/响应时间/超时元数据分离采集）；base-url 尾斜杠规范化 |
| `scripts/lib/loader.sh` | 加载 | 遍历 api.json `item` 树展平为接口清单；解析域/服务/模块/接口四元组；统计总数 |
| `scripts/lib/vars.sh` | 变量 | 占位符替换引擎：`{{var}}` 与 `:id` 双语法；变量表装载（环境/凭据/上下文三类） |
| `scripts/lib/auth.sh` | L1 | 登录鉴权层：执行 `POST /api/auth/login`，断言 `data.token` 存在（admin-G5），写入 TOKEN 上下文 |
| `scripts/lib/prepare.sh` | L2 | 数据准备层：创建自建闭环数据（项目/用户等），按捕获规则提取 id 写入 `CAPTURED.*` |
| `scripts/lib/assert.sh` | 断言 | 响应类型判定（WRAPPED/BARE/NON_JSON）；HTTP 状态 + 业务码双校验；失败原因分类；SKIP 判定 |
| `scripts/lib/report.sh` | 报告 | 汇总统计、明细表、失败章节、慢接口清单、SKIP 清单渲染；时间戳报告 + latest.md 副本；历史保留 N 份 |
| `scripts/lib/cleanup.sh` | L4 | 清理层：删除自建闭环数据；`--keep-data` 可跳过（排障场景保留现场） |
| `config/env.sh` | 配置 | 环境凭据与环境地址（见 7.1） |
| `config/params.json` | 配置 | 业务参数（见 7.2） |
| `config/iface.json` | 配置 | 域开关、域顺序、接口级断言与捕获规则（见 7.3） |
| `reports/` | 输出 | `api-test-report-YYYYMMDD-HHMMSS.md` + `latest.md` |
| `logs/` | 输出 | `run-YYYYMMDD-HHMMSS.log` |

### 3.3 运行入口与退出码

| 退出码 | 语义 | 触发条件 |
|:------:|------|----------|
| 0 | 成功 | 全部接口 PASS 或 SKIP（无 FAIL） |
| 1 | 存在失败 | 存在任意 FAIL 接口（普通失败不中止，最终汇总退出） |
| 2 | 关键链路中止 | L0 校验失败、登录失败、脚本自身错误（语法/配置缺失） |

---

## 4. 执行编排设计

### 4.1 五层执行管线

| 层 | 名称 | 内容 | 失败策略 |
|:--:|------|------|----------|
| L0 | 环境与工具校验 | jq/node 二选一探测（至少其一可用，否则 exit 2）；加载三份配置文件；base-url 尾斜杠规范化；`--domains` 合法性校验 | 失败即中止（exit 2） |
| L1 | 登录鉴权 | `POST /api/auth/login`（email/password 取参数体系）；解析 `data.token`；TOKEN 注入凭据变量表 | 失败即中止（exit 2），输出凭据核对提示 |
| L2 | 数据准备 | 按 iface.json `prepare` 清单创建闭环数据；每个创建接口按捕获规则提取 id；断言失败视为关键失败 | 失败即中止（exit 2）：L3 业务域将大面积依赖该数据 |
| L3 | 业务域 | 按 `domainOrder` 顺序逐域执行；域内按 api.json 展平原序逐接口执行；输出进度日志与判定结果 | 接口级失败继续（记录 FAIL），域级不中止 |
| L4 | 清理 | 删除 L2 自建数据（逆序删除）；`--keep-data` 跳过 | 失败仅记录，不影响退出码判定（数据残留提示） |

进度日志在 L3 逐接口输出：`[序号/总数][域][方法][路径] 结果 状态码 耗时`。

### 4.2 域顺序与依赖补齐

- 域执行顺序维护于 iface.json `domainOrder`（有序数组），默认顺序原则：**core 系域优先**（登录/用户/项目等基础数据域）→ 依赖 core 数据的业务域（agentorbit/workspace/integration 等）→ **adapter 外部依赖域殿后**（ads/gitlab/codearts/automation，预期 SKIP 或失败集中区，避免污染前段执行节奏）；
- `--domains` 过滤时执行**依赖补齐**：若所选域的 `dependsOn` 声明的前置域未在过滤集内，自动将前置域的 L2 数据准备与前置域接口一并纳入（仅纳入依赖所需最小集），保证上下文变量可用；
- 域开关（iface.json `domains` 布尔映射）与 `--domains` 的关系：开关为**持久配置**，`--domains` 为**本次过滤**，两者取交集后生效；被关闭的域在报告汇总中标注"未启用"。

### 4.3 上下文变量捕获

- 捕获规则按接口配置于 iface.json（JSONPath 表达式 → 变量名），形如 `"capture": {"$.data.id": "CAPTURED.projectId"}`；
- 捕获时机：接口判定为 PASS 之后立即执行，供后续接口的 `:id`/`{{var}}` 替换消费；
- 变量作用域为**单次执行全局**（L1~L4 共享一张变量表），清理层执行后不回退（幂等安全）；
- 初始捕获表（首版最小集，实跑后按失败明细逐步校准）：

| 来源接口 | 捕获表达式 | 变量名 | 消费方 |
|----------|-----------|--------|--------|
| `POST /api/auth/login` | `$.data.token` | `TOKEN` | 全部 Bearer JWT 接口（501 个） |
| L2 创建项目 | `$.data.id` | `CAPTURED.projectId` | 项目详情/更新/删除及引用 `:projectId` 的接口 |
| L2 创建用户 | `$.data.id` | `CAPTURED.userId` | 用户管理类接口 |
| L2 创建工作区 | `$.data.id` | `CAPTURED.workspaceId` | agentorbit 域引用接口 |

> 未被捕获规则覆盖的 `:id` 占位符（api.json 中存在大量路径参数接口），首版策略为：优先尝试从 params.json 同名键取值兜底，无值则 SKIP 并注明**路径参数缺失**，避免以空值拼 URL 产生误报。

---

## 5. 变量替换与鉴权注入设计

### 5.1 变量分类与优先级

| 变量类 | 示例 | 来源 | 说明 |
|--------|------|------|------|
| 环境类 | `{{coreBaseUrl}}` 等 13 个服务 baseUrl 变量 | env.sh（或 CLI/环境变量覆盖） | SIT 网关下默认全部收敛为主域名（见 5.3） |
| 凭据类 | `{{token}}`、`{{pat}}`、`{{internalToken.core}}` 等 | env.sh + L1 动态产出（TOKEN） | 缺失触发生成式凭据相关接口 SKIP |
| 上下文类 | `{{CAPTURED.projectId}}` | L1/L2 捕获 | 缺失触发路径参数类接口 SKIP |
| 业务参数类 | `{{params.projectName}}` 等 | params.json | 缺失报脚本配置错误（exit 2） |

取值优先级统一为：**CLI 传参 > 环境变量 > 配置文件**（决策点 5）。

### 5.2 占位符替换引擎

api.json 中存在两种占位语法（api-G4），替换引擎统一在 vars.sh 处理：

| 语法 | 出现位置 | 替换规则 |
|------|----------|----------|
| `{{var}}` | url.host/query/路径、header、body.raw | 变量表逐项正则替换；body.raw 为 JSON 字符串，替换后校验 JSON 合法性（失败计"响应解析失败"同级错误） |
| `:id` | url.path 段 | 查 iface.json `route` 映射（`:projectId` → `{{CAPTURED.projectId}}`）；未映射时按 4.3 缺失策略 SKIP |

替换顺序：先 `:id` 归一为 `{{var}}`，再统一做变量表替换，最后做 base-url 收敛（见 5.3）。

### 5.3 鉴权注入机制

基于 asdm-admin 调研的 6 种鉴权形态（admin-G3、api-G5），注入规则如下：

| 机制 | 注入方式 | 凭据来源 | 缺失行为 |
|------|----------|----------|----------|
| Bearer JWT | api.json 自带 `Authorization: Bearer {{token}}` 头，TOKEN 由 L1 登录产出 | L1 登录 | TOKEN 空 → 关键链路已中止（L1 即失败） |
| X-Internal-Token | api.json 自带头 + env.sh 按服务覆盖预期值 | env.sh `INTERNAL_TOKEN_CORE/AGENTORBIT/TELEMETRY` | 缺 → 相关接口 SKIP |
| X-Asdm-Pat | api.json 自带头（agentorbit 透传用途） | env.sh `ASDM_PAT` | 缺 → SKIP |
| X-Open-Access-Token | api.json 自带头（组织级 oat_） | env.sh `OPEN_ACCESS_TOKEN` | 缺 → SKIP |
| X-Citic-Secret | api.json 自带头（/_api/citic/**） | env.sh `CITIC_SECRET` | 缺 → SKIP |
| asdmPat 查询参数 | 44 个 integration 域接口以 query 传参 | env.sh `ASDM_PAT` | 缺 → query 项不注入并 SKIP |

**baseUrl 收敛**：api.json 的 13 个服务 baseUrl 变量默认 localhost 各端口（admin-G4：agentorbit 与 adapter-gitlab 本机 8884 冲突）。脚本装载变量表时统一执行：`http(s)://<网关域名>` 替换全部 `{{xxxBaseUrl}}`（网关路由按路径前缀到各服务，待实跑验证）；如某服务在 SIT 为独立子域，可在 env.sh 逐个覆盖 `SERVICE_BASE_URL_<NAME>`。

---

## 6. 断言引擎设计

### 6.1 响应类型三分法

针对被测系统无统一响应结构的问题（admin-G1、admin-G2），按接口配置响应类型：

| 类型 | 适用服务/接口 | 判定规则 |
|------|---------------|----------|
| WRAPPED | core/integration/telemetry/file-service/portal-backend/mcp-hosting（ApiResponse 结构） | HTTP 状态预期 + 响应 JSON 存在 code 字段时校验 `code == 200`（成功值=200，非 0，admin-G1） |
| BARE | adapter-*（控制器直返业务对象）、无包装 JSON | 仅 HTTP 状态预期 |
| NON_JSON | sso（302 重定向/cookie）、file-service 二进制流、HTML/空响应 | 仅 HTTP 状态预期（重定向类默认 2xx/3xx 均可） |

类型配置粒度：**按服务设默认值 + 按接口覆盖**（iface.json `responseType` 字段，缺省 WRAPPED）。

### 6.2 判定链与失败原因分类

每个接口的判定按固定顺序执行，首个失败即定因：

| 顺序 | 判定 | 失败原因标签 | 依据 |
|:----:|------|-------------|------|
| 1 | curl 连接是否成功（exit 7 / HTTP 000） | 连接失败 | curl 退出码语义 |
| 2 | 是否超时（exit 28，或达到 `--timeout`） | 请求超时 | curl 退出码语义 |
| 3 | HTTP 状态码是否等于预期（默认 2xx，可按接口配置 expectedHttp） | HTTP 状态码非预期 | 决策点 7 |
| 4 | WRAPPED 类型：code 字段是否等于预期（默认 200，可按接口配置 expectedCode） | 业务码非预期 | admin-G1、admin-G7 |
| 5 | 响应体可解析为 JSON（WRAPPED 时） | 响应解析失败 | 防御性兜底 |

特判规则：

- **登录接口**（admin-G5）：登录失败陷阱为 HTTP 200 + code=401，L1 断言必须解析 `data.token` 存在性，不能只看 HTTP 状态；
- 预期值可按接口配置（决策点 7）：如删除类接口预期 404/204、参数错误场景预期 400，均通过 iface.json `expectedHttp/expectedCode` 表达。

失败接口随报告输出响应体摘要（截断 200 字符）与响应时间（取 `time_total`）。

### 6.3 SKIP 规则

SKIP 与 FAIL 严格区分（决策点 8），SKIP 不计失败：

| SKIP 原因 | 判定条件 |
|-----------|----------|
| 凭据缺失 | 接口依赖的凭据变量为空（5.3 表） |
| 域未启用 | 域开关关闭或 `--domains` 过滤未选中 |
| 路径参数缺失 | `:id` 映射的上下文变量未捕获且 params.json 无兜底值 |
| 前置数据缺失 | 依赖的 CAPTURED 变量因 L2 失败而缺失（L2 失败整体中止，此为兜底） |

每个 SKIP 接口在报告中注明原因（R1 验收标准）。

### 6.4 慢接口标记

- 响应时间取 curl `time_total`（决策点 11）；
- 阈值 3s（可用 `--slow-threshold` 覆盖）：超阈值的接口在报告明细行追加 ⚠️ 标记并单独汇总清单；
- 慢接口标记为**独立维度**，不影响 PASS/FAIL 判定；超时（30s 可配）才判 FAIL（理由：HTTP 状态码与业务码均预期，仅耗时偏长不构成接口功能失败）。

---

## 7. 配置数据模型

### 7.1 config/env.sh

Bash 变量文件（含默认值，凭据留空触发 SKIP）：

```bash
# 环境地址
ASDM_BASE_URL="https://asdm-sit.leansoftx.com"   # 尾斜杠由脚本规范化去除
# 登录凭据
LOGIN_EMAIL=""
LOGIN_PASSWORD=""
# 外部凭据（缺失 → 相关接口 SKIP）
ASDM_PAT=""                    # X-Asdm-Pat 头 + asdmPat query 参数
OPEN_ACCESS_TOKEN=""           # X-Open-Access-Token（oat_）
CITIC_SECRET=""                # X-Citic-Secret
# 内部令牌（各服务预期值不同，admin-G3）
INTERNAL_TOKEN_CORE=""
INTERNAL_TOKEN_AGENTORBIT=""
INTERNAL_TOKEN_TELEMETRY=""
# 可选：逐服务独立 baseUrl 覆盖（缺省全部收敛为 ASDM_BASE_URL）
# SERVICE_BASE_URL_CORE="https://core-sit.xxx" ...
```

### 7.2 config/params.json

业务参数（请求 body 内容项），分公共与按域两段：

```json
{
  "common": {
    "projectName": "auto-test-proj",
    "userEmail": "auto-test-user@asdm.ai",
    "workspaceName": "auto-test-ws"
  },
  "domains": {
    "integration": { "webhookUrl": "https://example.com/hook" }
  }
}
```

### 7.3 config/iface.json

接口级行为配置（脚本零硬编码的载体）：

```json
{
  "domainOrder": ["认证授权域", "...", "adapter-ads 域"],
  "domains": { "认证授权域": true, "integration": true },
  "responseTypeDefault": { "core": "WRAPPED", "sso": "NON_JSON", "adapter-ads": "BARE" },
  "prepare": [
    { "name": "create-project", "call": "POST /api/projects", "capture": { "$.data.id": "CAPTURED.projectId" } }
  ],
  "route": { ":projectId": "{{CAPTURED.projectId}}", ":userId": "{{CAPTURED.userId}}" },
  "interfaces": {
    "POST /api/auth/login": { "responseType": "WRAPPED", "capture": { "$.data.token": "TOKEN" } },
    "DELETE /api/projects/:projectId": { "expectedHttp": [200, 204] }
  }
}
```

> 初始版 `route`/`prepare`/`interfaces` 仅覆盖 4.3 最小捕获集；执行引擎对其余接口使用默认规则（WRAPPED + 2xx + code=200）。随实跑失败明细迭代扩充，最终形成全量接口的断言资产。

---

## 8. 日志与报告设计

### 8.1 执行日志

- 文件：`logs/run-YYYYMMDD-HHMMSS.log`（同步回显终端）；
- 进度行格式（R4）：`[12/1000][core][POST][/api/auth/login] PASS 200 0.35s`；
- 每 100 条输出一次汇总心跳行：`已执行 100/1000 | PASS=95 FAIL=3 SKIP=2`；
- FAIL/SKIP 接口追加明细行（原因 + 响应体摘要），保留原始请求记录（方法/完整 URL/请求头脱敏摘要/body）供慢接口与失败排查（使用场景 2.5）。

### 8.2 Markdown 报告

- 文件：`reports/api-test-report-YYYYMMDD-HHMMSS.md` + `latest.md` 副本；自动保留最近 N 份（默认 10，`--keep` 可配），超出删除最旧；
- 报告结构（R5）：

| 章节 | 内容 |
|------|------|
| 执行概览 | 环境、执行时间、总耗时、总数、PASS/FAIL/SKIP 数、平均响应时间 |
| 失败明细 | 🔴 失败接口逐条：名称/方法/路径/失败原因（6.2 五分类）/响应体摘要（≤200 字符）/响应时间 |
| 慢接口清单 | ⚠️ 超 3s 接口按耗时降序 |
| SKIP 清单 | SKIP 接口逐条注明原因（6.3 四分类） |
| 全量明细 | 每接口一行：名称/方法/请求路径/状态/响应时间（域分组、域小计） |
| 域汇总 | 按域统计 PASS/FAIL/SKIP，未启用域标注"未启用" |

---

## 9. 调研发现应对映射

| 发现编号 | 摘要 | 详细设计应对 | 落点章节 |
|:--------:|------|--------------|----------|
| api-G1 | 接口清单可全量提取 | 执行引擎以 api.json 为唯一接口来源 | 3.1、3.2 loader.sh |
| api-G2 | api.json 无依赖信息 | 依赖编排脚本侧自定义（五层管线 + domainOrder） | 4.1、4.2 |
| api-G3 | 398 接口无鉴权头混布 | 响应类型 + 预期值按接口配置 | 6.1、6.2 |
| api-G4 | `:id` 与 `{{var}}` 双占位并存 | 统一替换引擎，先归一再替换 | 5.2 |
| api-G5 | 44 接口 asdmPat 走 query | 鉴权注入支持 query 追加 | 5.3 |
| api-G6 | v1.3.11 快照版本 | 版本演进需重导出 diff（风险项跟踪） | 10 |
| admin-G1 | HTTP 200 + 错误 code 陷阱 | WRAPPED 类型强校验 code==200 | 6.1、6.2 |
| admin-G2 | 非 JSON 响应形态多样 | 响应类型三分法（WRAPPED/BARE/NON_JSON） | 6.1 |
| admin-G3 | internal-token 各服务不同 | env.sh 按服务三配置项 | 5.3、7.1 |
| admin-G4 | 同端口本机部署冲突 | baseUrl 全量收敛网关域名 + 可逐服务覆盖 | 5.3 |
| admin-G5 | 登录失败 200+401 陷阱 | L1 断言 data.token 存在性 | 4.1、6.2 |
| admin-G6 | JWT 30 天有效期 | 每次执行重新登录（简单可靠） | 4.1 L1 |
| admin-G7 | 业务码失败维度存在 | 失败原因分类含"业务码非预期" | 6.2 |

---

## 10. 依赖关系与风险

### 10.1 依赖关系

| 依赖项 | 类型 | 说明 |
|--------|------|------|
| docs/api.json | 数据 | 接口清单唯一来源（v1.3.11 快照）；被测系统接口演进时需重新导出并 diff（api-G6），diff 差异应同步 iface.json |
| SIT 环境 | 环境 | 网关 `https://asdm-sit.leansoftx.com/` 对 13 个服务的路由规则（路径前缀/子域）待实跑验证；不可路由的服务整域 FAIL/SKIP，需在 iface.json 调整 baseUrl |
| 测试人员凭据 | 凭据 | 登录账号、pat、oat、citicSecret、三个 internal-token 实际值填入 env.sh（缺失自动 SKIP，不阻塞执行） |
| 运行平台 | 工具 | Git Bash / Linux + curl；jq 或 node 至少其一（均缺失 exit 2） |

### 10.2 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| adapter-* 域依赖外部系统（Azure DevOps/GitLab/CodeArts），SIT 连通性未知 | 大量 SKIP 或失败，干扰整体判读 | 报告区分"被测服务故障"与"外部依赖不可达"（adapter 域失败明细单独标注外部依赖类别）；初期可将 adapter 域默认关闭 |
| `:id` 占位符的 id 来源无法静态推导 | 部分接口 SKIP | 4.3 缺失即 SKIP 策略 + iface.json route 表渐进扩充（实跑校准） |
| 破坏性接口自建数据闭环失败 | 环境残留脏数据 | L4 清理逆序删除 + `--keep-data` 保留现场排障；清理失败输出残留清单 |
| HTTP 200 + 错误码陷阱类型未被覆盖 | 误判 PASS | 断言引擎强制 code 校验（WRAPPED 默认开启），非包装接口按 BARE 仅状态码，误判面已收敛 |

---

## 11. 相关文档

- [FT-060-api-auto-test-shell-AskMe.md](./FT-060-api-auto-test-shell-AskMe.md) — 需求访谈（决策点 1~12 与用户故事的原始来源）
- [FT-060-api-auto-test-shell-Feature-Overall.md](./FT-060-api-auto-test-shell-Feature-Overall.md) — 概要设计（本文档的直接输入）
- [FT-060-api-auto-test-shell-CodeResearch-api-json.md](./FT-060-api-auto-test-shell-CodeResearch-api-json.md) — api.json 调研（api-G1~G6）
- [FT-060-api-auto-test-shell-CodeResearch-asdm-admin.md](./FT-060-api-auto-test-shell-CodeResearch-asdm-admin.md) — asdm-admin 调研（admin-G1~G7）
- [docs/api.json](../../../docs/api.json) — 接口资产数据源（1000 接口）
- [ASDM-ProductPlanning.md](../../ASDM-ProductPlanning.md) — 产品规划总览

---

## 12. 完成规范 (DoD)

> **状态说明**：
> - **已完成**：✅ 该功能点已实现，无需额外开发
> - **部分完成**：🟡 该功能点部分实现，需进一步完善
> - **待实现**：❌ 该功能点尚未实现，需要在开发阶段实现

### 12.1 核心功能（R1/R3）

| 编号 | 完成点 | 说明 | 状态 | 完成状态说明 |
|:----:|--------|------|:----:|--------------|
| D1 | api.json 展平加载器 | loader.sh 遍历 item 树产出 1000 条接口清单（域/服务/模块/接口四元组），总数与调研统计一致 | ❌ | 待实现 |
| D2 | 五层执行管线 | L0~L4 按序调度；login 失败 exit 2 中止；接口级失败不中止 | ❌ | 待实现 |
| D3 | 域过滤与依赖补齐 | `--domains` 过滤 + dependsOn 前置域自动补齐 + 域开关交集生效 | ❌ | 待实现 |
| D4 | 上下文变量捕获 | login→TOKEN、L2 创建接口→CAPTURED.*（初始最小集 4 项） | ❌ | 待实现 |
| D5 | 变量替换引擎 | `{{var}}` 与 `:id` 双语法统一替换；body 替换后 JSON 合法性校验 | ❌ | 待实现 |
| D6 | baseUrl 收敛 | 13 个服务 baseUrl 统一收敛网关域名；env.sh 逐服务覆盖生效；尾斜杠规范化 | ❌ | 待实现 |
| D7 | 断言引擎 | 三类响应类型 + 五级判定链 + 按接口 expectedHttp/expectedCode 配置 + 失败原因五分类 | ❌ | 待实现 |
| D8 | SKIP 规则 | 凭据缺失/域未启用/路径参数缺失三类 SKIP 如实入报告并注明原因，不产生误报 FAIL | ❌ | 待实现 |
| D9 | 自建数据闭环 | 破坏性接口先创建后删除；L4 清理逆序删除 + `--keep-data` 逃生口 | ❌ | 待实现 |

### 12.2 参数与配置（R2）

| 编号 | 完成点 | 说明 | 状态 | 完成状态说明 |
|:----:|--------|------|:----:|--------------|
| D10 | env.sh 凭据体系 | 环境地址 + 登录凭据 + 5 类外部凭据 + 3 个 per-service internal-token 配置项 | ❌ | 待实现 |
| D11 | params.json 业务参数 | common + 按域两段结构，body 参数注入 | ❌ | 待实现 |
| D12 | iface.json 接口配置 | domainOrder/域开关/responseType 默认/prepare/route/interfaces 六个配置域生效 | ❌ | 待实现 |
| D13 | 参数优先级 | CLI > 环境变量 > 配置文件；动态传参不回写 | ❌ | 待实现 |
| D14 | JSON 解析降级 | json_get 运行时 jq/node 探测降级；两者皆缺 exit 2 并提示 | ❌ | 待实现 |

### 12.3 日志与报告（R4/R5）

| 编号 | 完成点 | 说明 | 状态 | 完成状态说明 |
|:----:|--------|------|:----:|--------------|
| D15 | 进度日志 | 逐接口进度行（序号/总数/域/方法/路径/结果）+ 100 条心跳汇总 + `logs/run-<ts>.log` 落盘 | ❌ | 待实现 |
| D16 | Markdown 报告 | 六章节结构（概览/失败明细/慢接口/SKIP/全量明细/域汇总）+ latest.md 副本 + 保留 N 份 | ❌ | 待实现 |
| D17 | 失败可定位 | 失败原因五分类 + 响应体摘要 ≤200 字符 + 日志原始请求记录 | ❌ | 待实现 |
| D18 | 慢接口标记 | time_total > 3s 标 ⚠️ 独立清单，不影响 PASS/FAIL 判定 | ❌ | 待实现 |

### 12.4 健壮性与兼容性

| 编号 | 完成点 | 说明 | 状态 | 完成状态说明 |
|:----:|--------|------|:----:|--------------|
| D19 | 退出码约定 | 0 成功 / 1 存在 FAIL / 2 关键链路中止，CI 可直接消费 | ❌ | 待实现 |
| D20 | Git Bash / Linux 双兼容 | POSIX 兼容写法（无 bashism 依赖 bash 独有特性导致 Git Bash 失败的场景）；两端冒烟验证 | ❌ | 待实现 |
| D21 | SIT 实跑校准 | 全量执行一次，校准业务码成功值、`:id` 捕获表、网关路由；产出实跑报告作为基线 | ❌ | 待实现 |

---

**文档版本**：1.0.0
**最后更新**：2026-11-26
**维护者**：meiguangxuan
