# ASDM 接口自动化测试 Shell 脚本：VibeCoding 提示词模板

## 使用方法

1. 将下方“提示词正文”完整复制给具备代码读写和命令执行能力的 AI 编程助手。
2. 默认输入集合为 `asdm-api-auto-testing/api.json`，输出目录为 `asdm-api-auto-testing/`。
3. 首次生成后，把真实的非敏感环境参数写入环境配置，把密钥通过环境变量注入，再按 AI 给出的命令执行。
4. 如果只需要局部迭代，可在末尾追加本轮要求，但不要删除覆盖率、依赖、日志、报告和安全约束。

## 已知输入基线

以下数据来自当前 `api.json`，用于帮助 AI 校验解析是否完整；实现时仍须以实际文件为准，禁止把数量硬编码为业务逻辑。

| 项目 | 当前基线 |
| --- | --- |
| 集合格式 | Postman Collection v2.1 |
| 集合名称 | ASDM Admin API |
| 接口总数 | 1000 |
| 业务域 | 12 |
| 后端服务 | 13 |
| 请求方法 | GET 566、POST 281、PUT 63、DELETE 70、PATCH 20 |
| 请求体 | raw 256、formdata 24、无请求体 720 |
| 集合变量 | 18 个，包含 13 个服务地址和 token、pat、internalToken、openAccessToken、citicSecret |
| 主要认证方式 | JWT Bearer、PAT、X-Internal-Token、X-Open-Access-Token、X-Citic-Secret、X-Asdm-Pat |

## 提示词正文

````text
你是一名资深测试开发工程师、Shell 工程师和 DevOps 工程师。请直接在当前工作区开发一套可运行、可维护、可每天重复执行的接口自动化测试工程，不要只给架构建议、伪代码或单个庞大脚本。

# 一、任务目标

输入文件：d:/dev-src/Ai-Fast/asdm-api-auto-testing/api.json
工程目录：d:/dev-src/Ai-Fast/asdm-api-auto-testing/
输入性质：Postman Collection v2.1，集合名 ASDM Admin API。

以 api.json 为唯一接口来源，使用 Bash + curl + jq 实现接口自动化测试。测试人员配置好环境后，每天只需执行一次入口命令，即可完成全部适用接口的测试、日志记录和报告生成：

  ./run-api-tests.sh --env daily

也必须支持不带业务参数的日常默认执行方式；环境名可以有默认值。不得要求测试人员逐条复制 curl 命令。

当前集合基线为 1000 个接口、12 个业务域、13 个服务。解析后必须重新计数并与源集合对账，不能因只读取了部分 JSON、只实现示例接口或过滤困难接口而悄悄缩小范围。接口数量后续可能变化，覆盖校验须动态计算。

# 二、先分析，再小步实现

按以下顺序推进，每一步完成后验证再继续，但除非遇到真实凭据或高风险环境操作，不要停下来等待确认：

1. 使用 JSON 解析器完整读取 api.json，递归展开所有 item 层级，不要靠正则截取 JSON。
2. 输出简要盘点：接口总数、业务域/服务分布、方法分布、变量、请求体类型、认证方式、路径参数和响应示例特征。
3. 给出简短实现计划和文件结构，然后直接创建工程。
4. 先打通“集合解析 → 登录 → token 提取 → 一个鉴权 GET → 一条自包含 CRUD 链 → 报告”的垂直切片。
5. 再覆盖全部接口、依赖编排、失败归因、清理和自测，持续运行校验并修复问题。
6. 最终交付完整代码和可执行命令，不要用 TODO、占位实现或“你可以自行补充”代替核心功能。

api.json 是只读输入，不要修改它。人工维护的参数、断言和依赖必须放在独立配置中，重新生成接口目录时不能丢失人工配置。

# 三、必须交付的工程能力

## 1. 统一入口与模块化结构

至少提供：

- run-api-tests.sh：唯一日常入口。
- scripts/：集合解析、公共函数、参数渲染、请求执行、断言、依赖调度、报告等模块，按职责拆分。
- config/：环境参数、接口覆盖配置、依赖关系、测试数据和断言配置。
- tests/fixtures/：表单上传等所需的最小测试文件。
- tests/：不依赖真实后端的核心自测。
- logs/：按运行批次保存日志。
- reports/：按运行批次保存报告。
- README.md：安装、配置、日常执行、动态传参、筛选、报告查看、失败排查和清理说明。

运行期依赖保持轻量：Bash、curl、jq 和常见 POSIX 工具。入口先检查依赖和版本，缺失时给出可操作的错误信息。兼容 Linux，并尽量兼容 macOS 与 Windows Git Bash；若存在平台限制须明确写出。

所有 Shell 文件通过 bash -n；如环境有 ShellCheck，则运行并修复合理告警。正确处理空格、中文、引号、换行、JSON 特殊字符和非零退出码，禁止使用 eval 拼接请求，禁止因为管道或 tee 丢失 curl 的真实退出码。

## 2. 自动接口目录，不手写 1000 份请求

从 Postman 集合递归提取并生成规范化的接口目录，每条至少包含：

- 稳定 id：优先由 HTTP 方法 + url.raw 生成，不能依赖数组下标。
- name、domain、service、group。
- method、url.raw、path、query、headers、body。
- 文档中的成功响应码、断言配置、依赖、数据提取和标签。

保留中文名称和 UTF-8 编码。生成目录与源集合按“方法 + 原始 URL”对账，检查重复 id、遗漏和多余记录。当前集合没有重复的“方法 + url.raw”，但程序仍应检测并在未来出现重复时明确报错。

请求渲染必须支持：

- {{variable}} 形式的集合变量和运行期变量。
- :id、:projectId、:instanceId 等路径参数。
- URL query，不能因使用 url.raw 而丢失 query 数组中的参数。
- raw JSON、无请求体和 formdata；formdata 文件从 fixtures 或配置路径读取。
- header 的 disabled 状态和同名 header 冲突处理。

集合中部分接口同时出现“Bearer {{token}}”和“{{token}}”两个 Authorization 头。必须制定确定性的去重/优先级规则，默认使用符合接口说明的 Bearer 形式，并允许在覆盖配置中调整；不要盲目把两个认证头都发给服务端。

变量替换要具备 JSON 安全性。不得用未转义的 sed 替换直接拼 JSON，不得让密钥中的 &、反斜杠、引号或换行破坏请求。请求体通过临时文件和 curl --data-binary 发送。拼接 baseUrl 与路径前规范化末尾斜杠，避免出现 //api/...。

## 3. 接口参数维护机制

同时支持“手工维护”和“执行时动态传参”，并清楚展示最终生效参数来源。

### 手工维护

- config/params.<env>.json：维护 baseUrl、账号标识、路径参数、测试数据等非敏感值，提供 local、daily/example 配置模板。
- config/overrides.json：按稳定接口 id 覆盖请求头、query、路径参数、请求体、预期状态码、业务断言、超时和标签。
- config/dependencies.json：维护依赖、执行顺序、响应提取和资源清理关系。
- config/test-data.json：维护跨接口业务数据及异步轮询配置。
- 真实密码和令牌不得写入示例文件或版本库；提供 .env.example 和 .gitignore。

### 动态传参

至少支持：

- --env <name>：选择环境。
- --set key=value：重复出现以覆盖任意输入参数。
- --param-file <file>：额外加载一次运行参数文件。
- --domain <name>、--service <name>、--api-id <id>：调试时筛选，默认不筛选。
- --timeout <seconds>、--connect-timeout <seconds>。
- --output-dir <path>、--dry-run、--verbose。
- --allow-skip：显式允许存在 SKIP 时仍返回成功；默认不能因为跳过而显示全套测试成功。

支持 ASDM_TOKEN、ASDM_PAT、ASDM_INTERNAL_TOKEN、ASDM_OPEN_ACCESS_TOKEN、ASDM_CITIC_SECRET 等环境变量，并为所有 baseUrl 和登录字段提供一致的 ASDM_ 大写变量映射。

静态输入优先级固定并写入文档：

  --set > --param-file > 环境变量 > params.<env>.json > Postman 集合默认值

依赖接口产生的运行期值写入独立的运行时上下文，并在依赖完成后更新给下游使用；其优先级高于静态同名值，避免登录后仍使用过期 token。dry-run 输出每个变量的来源，但敏感值只能显示为 ******。

禁止把密钥拼进可能暴露在进程列表或 Shell 历史中的示例命令。文档中密钥示例使用环境变量或交互式隐藏输入。

## 4. 依赖关系与执行编排

把接口执行建模为有向无环图，不要只按 Postman 文件顺序执行。依赖配置至少支持：

- dependsOn：前置接口 id 列表。
- extract：从响应提取变量，使用明确的 jq 路径表达式，例如登录 token 的 $.data.token。
- exports：把提取值映射为下游使用的变量名。
- cleanup：本接口创建资源对应的清理接口及参数映射。
- eventually：异步状态轮询路径、期望值、间隔和超时，禁止只用固定 sleep 猜测完成时间。
- required：前置条件缺失时是阻断还是可跳过，禁止静默忽略。

至少实现以下真实依赖模式，并继续从集合描述中识别其余关系：

1. POST /api/auth/login 先执行，从响应 data.token 提取 token；依赖 JWT 的接口在 token 就绪后执行。
2. PersonalAccessToken 创建接口依赖登录；PAT 的真实提取路径根据实际响应确认，不要因为示例 data 是 string 就臆造字段。
3. integration 的 workitems、pull-requests、test-management 等接口按集合说明传递 asdmPat。
4. agentorbit 相关接口按说明传递 X-Asdm-Pat；internal、OpenAccess、Citic 接口分别使用对应认证变量。
5. 项目、项目集合、工作空间、上下文、流水线等资源按“前置资源创建 → 当前接口 → 查询/更新验证 → 逆向清理”编排。
6. DELETE 默认只删除本次运行创建的资源；update/delete/get-by-id 从创建响应或受控查询结果中取得真实 id，不使用固定示例 id。

执行前检测未知依赖、循环依赖和不可达节点并中止，打印具体依赖链。某个前置失败后：前置本身记 FAIL，直接和间接受阻接口记 SKIP，原因包含首个失败依赖的 id；其他无关节点继续执行。禁止把因依赖未执行记为 PASS。

默认顺序执行，优先保证可重复性和数据安全，不必为了速度引入复杂并发。

## 5. 每天可重复执行与测试数据生命周期

- 每次运行生成 RUN_ID 和时间戳，资源名、邮箱、UID 等使用可读且唯一的前缀，避免与历史数据冲突。
- 动态生成过期时间等时间字段；不要照抄集合中已经过期的示例时间。
- 创建类接口优先形成闭环：创建后断言可查询，再测试更新/详情/删除。
- 使用 trap 和显式清理阶段，即使中途失败也尽量清理本次创建的资源；清理按依赖逆序执行。
- 只清理由本次运行登记的资源，绝不根据模糊名称批量删除既有数据。
- 清理失败要记录 CLEANUP_FAIL 或明确告警，并在汇总中体现，不能掩盖原接口结果。
- 连续运行两次不应要求人工删除上一轮数据。
- 修改密码、注销、批量删除、向外部系统写数据等高风险操作，必须使用专用测试账号、测试资源和沙箱配置；无法安全执行时明确记 SKIP 并说明缺少什么安全配置，不能在真实环境擅自尝试。

## 6. 请求执行与断言

每次请求至少记录：接口 id、名称、方法、解析后的路径、HTTP 状态码、curl 退出码、响应耗时、开始/结束时间和结果。

使用 curl 的 time_total 获取耗时，报告中统一展示毫秒；网络失败时 HTTP 状态可显示 000，但失败原因必须区分 DNS、连接拒绝、TLS、连接超时、总超时和其他 curl 错误。

断言默认来自接口的成功响应示例和描述，并允许 overrides 覆盖：

- HTTP 状态码：不要简单接受任意 2xx，也不要把响应示例中的 400/401/404/500 错当成成功预期。
- 业务 code：仅对响应结构明确的接口启用，可配置预期值。
- JSON 可解析性、必填字段、字段类型、非空值及数组条件。
- 数据提取：jq 路径不存在、值为 null 或空字符串时记 EXTRACT_FAIL，并指出路径。
- 对异步资源使用有界轮询，超时给出最后观测状态。

不要把所有接口都硬编码为“HTTP 200 且业务 code=200”。当前集合同时含 200、201 及错误响应示例，须选择文档化的成功响应并允许人工校准。对于集合明确标注“推断”的细节，要在配置或文档中标识待真实服务确认。

## 7. 进度日志

控制台和 logs/<RUN_ID>/run.log 同步输出带时间戳的日志，至少包含：

- 运行开始：RUN_ID、环境、接口总数、筛选条件、配置校验结果；敏感值脱敏。
- 当前进度：[当前序号/总数]、业务域、接口名称、方法和路径。
- 依赖信息：等待的前置、提取成功的变量名，不打印变量秘密值。
- 请求结束：PASS/FAIL/SKIP、HTTP 状态、耗时和简短原因。
- 清理进度、汇总数量、报告路径和总耗时。

提供 --verbose 记录更详细的已脱敏请求/响应；默认日志不打印完整响应体。单个响应诊断内容限制大小，防止超大响应淹没日志。

统一脱敏 Authorization、X-Asdm-Pat、X-Internal-Token、X-Open-Access-Token、X-Citic-Secret、Cookie、password、newPassword、token、pat，以及 URL query 中的 asdmPat 等敏感字段。报告同样脱敏。

## 8. 自动化测试报告

每次运行生成独立目录 reports/<RUN_ID>/，至少包含：

- report.md：测试人员直接阅读的 Markdown 单文件报告。
- results.json：完整结构化结果，供后续工具消费。
- summary.txt：简要汇总。
- response/：仅保存必要且已脱敏的失败诊断响应，限制文件大小。

可提供 reports/latest.md 作为最近一次报告的副本或链接，但不能覆盖历史报告。

Markdown 报告必须有：

1. 汇总：环境、RUN_ID、开始/结束时间、总耗时、总数、PASS、FAIL、SKIP、通过率和失败依赖根因。
2. 失败区置顶：使用独立章节和加粗的 **FAIL** 文本突出显示所有失败，同时不能仅靠颜色表达失败。
3. 全量明细表：使用 Markdown 表格，每一行都列出接口名称、方法、请求路径、状态、HTTP 状态码、响应时间、失败/跳过原因。
4. 按状态、业务域和服务分组或提供目录锚点，便于阅读和编辑器内关键字搜索；正确转义表格中的竖线、反斜杠和换行，过长内容放入详情章节。
5. 失败详情：预期与实际、curl 错误、断言失败位置、首个失败依赖、经过脱敏和截断的响应摘要。
6. SKIP 的响应时间显示 N/A，并明确是依赖失败、缺少参数、缺少外部资源还是安全策略，不得伪装成通过。

失败原因使用稳定分类，例如 CONFIG_ERROR、DEPENDENCY_FAILED、NETWORK_ERROR、TIMEOUT、HTTP_STATUS_MISMATCH、BUSINESS_CODE_MISMATCH、SCHEMA_ASSERT_FAIL、EXTRACT_FAIL、CLEANUP_FAIL。报告中的总接口数必须等于本次目录对账后的接口数；筛选调试时同时显示“源集合总数/本次筛选数”。

## 9. 退出码

- 0：本次应执行的接口全部通过，且没有未获允许的 SKIP。
- 1：至少一个接口 FAIL、出现未获允许的 SKIP，或清理失败。
- 2：用法错误、配置错误、目录对账失败、依赖图错误等导致无法开始完整执行。

入口在生成报告后再返回正确退出码，不能因 set -e 或某个 curl 失败而提前丢失后续结果和报告。

# 四、建议文件结构

可按实际实现调整，但职责不要全部堆到一个脚本：

- run-api-tests.sh
- scripts/generate-catalog.sh
- scripts/lib/common.sh
- scripts/lib/config.sh
- scripts/lib/render.sh
- scripts/lib/dependencies.sh
- scripts/lib/request.sh
- scripts/lib/assert.sh
- scripts/lib/report.sh
- config/params.example.json
- config/params.local.json（只放本机非敏感配置）
- config/overrides.json
- config/dependencies.json
- config/test-data.json
- tests/self-test.sh
- tests/fixtures/
- logs/
- reports/
- README.md

# 五、验证与验收

完成后必须实际运行可行的本地校验，不要只声称“应该可以”。至少覆盖：

1. 目录解析：当前源文件解析出 1000 个接口，方法分布为 GET 566、POST 281、PUT 63、DELETE 70、PATCH 20；无重复 id、无静默遗漏。
2. 参数优先级：集合默认、文件、环境变量、--param-file、--set 的覆盖结果符合文档，dry-run 不泄露秘密。
3. 渲染：路径参数、query、JSON 特殊字符、formdata、baseUrl 尾斜杠和重复 Authorization 处理正确。
4. 依赖：登录成功才释放下游；构造登录失败时，下游为 DEPENDENCY_FAILED/SKIP，无关节点继续；循环依赖在发请求前被检测。
5. 成功链路：用本地 mock 或可控测试服务验证登录、token 提取、鉴权请求和 CRUD 清理。
6. 失败报告：分别模拟 HTTP 500、业务断言失败、超时和响应字段缺失，报告中均以醒目的 **FAIL** 标识并给出不同原因和响应时间。
7. 报告字段：逐行检查名称、方法、路径、状态、响应时间完整，失败原因可见，Markdown 与 JSON 汇总一致。
8. 可重复性：在可控环境连续执行两次，测试数据不冲突，清理逻辑可用。
9. Shell 质量：bash -n 全部通过；有 ShellCheck 时执行并记录结果。
10. 安全：扫描日志和报告，确认测试用的密码、token、PAT 等未以明文出现。

没有真实后端或凭据时，使用本地 mock 完成框架自测，并明确标记“未进行真实环境全量验证”；不得伪造 1000 个接口的真实通过结果。真实环境执行前，列出仍需人工提供的环境参数和外部资源，但不要因此停止代码交付。

# 六、完成标准与最终答复

只有满足以下条件才算完成：

- 测试人员能通过一个入口命令启动日常全量测试。
- 1000 个当前接口全部进入目录、依赖图和结果清单；不能安全执行的项也有明确 SKIP 和原因。
- 手工配置、环境变量和命令行动态传参均可用，优先级明确。
- JWT/PAT 等认证依赖和 CRUD 数据依赖可运行，失败会沿依赖链传播，无关节点不中断。
- 控制台与文件日志可跟踪进度，Markdown/JSON 报告字段完整且失败醒目。
- 密钥脱敏、测试数据隔离和清理机制已落实。
- 所有可运行的本地校验已执行，结果真实记录。

最终答复只需简要列出：生成的核心文件、日常执行命令、动态传参示例、报告位置、已执行验证及结果、真实环境仍需配置的事项。若存在未解决项，给出具体文件、错误和下一步，不要笼统说“已完成”。
````

## 可选追加指令

用于后续迭代时附加在提示词末尾：

- **只完善某模块**：保留现有公开命令和配置兼容性，仅修改指定模块，并回归目录对账、依赖和报告。
- **接入新环境**：新增 `params.<env>.json`，不改动其他环境；秘密仍由环境变量提供。
- **校准真实响应**：把真实成功响应与集合示例的差异沉淀到 `overrides.json`，不要直接修改 `api.json`。
- **排查失败**：先定位首个根因 FAIL，再区分其下游 SKIP，避免把整组失败都当成独立接口缺陷。
- **集合更新**：重新生成目录并执行接口数量、重复 id、依赖有效性和人工覆盖配置兼容性检查。
