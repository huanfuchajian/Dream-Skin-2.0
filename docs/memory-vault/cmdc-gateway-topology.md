---
name: command-code-go-gateway-topology
description: Command Code Go local gateways (cmdc-pak 8787 vs cmdc-hub 8888), 35 reqs/week quota, auth.json switch trap, TTY requirement, fake-ip license fix; 含 cmdc-hub 魔改落地、Gemini AI Pro 线（v0.6.4）客户端填法与 base URL /v1 玄学、Claude Code 指纹死通道定案；09-27 新版 ea458450（回滚=.prev、下载走10808代理）、模型白名单全量 9+4、/v1/responses 端点与 input.type 400 判据、Gemini high 单挂案✅已结（换台北节点四档全绿、节点须固定）；10-02 面板自报 v0.8.9 三面板=三产品线分组（CC订阅/Gemini订阅/OpenCode Free 中继，后者 9 free 模型、ling-3.0 上游 502）；ZCode2 cmdc 三供应商✅已执行且 muse-free 改 openai-responses 后端到端实测通过；付费 muse 两条=Meta 地区封区（台/港都拒、新加坡放行且呈间歇态=商家 Console 池混坏节点）；节点矩阵终榜=新加坡 15/16 登顶 > 台北 13/16 > 香港 12/16；cmdc/OpenCode 报错五型分型表已收齐（503 过载=等会手动重发【ZCode retryable=false 不自动重试】、502 端点挂、400 方言、403 RegionError、Meta 封区 200 空包壳）；Cherry Studio 三线配置✅定稿（Anthropic 线 base 不带 /v1=404 陷阱、muse-free 不进 Cherry、muse 长生成偶发 EOF）；Gemini 订阅已换绑 ningmengningmeng233@gmail.com（G-cpil 码转正现役）（见 [[zcode-desktop-cdp-skinning-and-multi-instance]]）
metadata:
  node_type: memory
  type: reference
  originSessionId: sess_68b0ca66-3a4b-4ed1-b26a-39997e31ea2a
---

## 1. 软件定位与中继架构

Command Code 官方仅提供基于 Ink 终端的 CLI 工具（`command-code`），使用私有协议通讯（`api.commandcode.ai/alpha/generate`）。本地网关将其转译为标准 OpenAI API（`/v1/chat/completions`），供 Cherry Studio、Cline、Aider 等客户端调用。

- **8787（商业版 `cmdc-pak`）**：
  - 开发者「鳕鱼」，官网 `https://cmdc-pak.ljj233.top`，带托盘与 Web 管理面板（`http://127.0.0.1:8787`）。
  - **授权绑定机制**：启动时调用 `https://cmdc-pak.ljj233.top/api/license/verify` 验证卡密 Token。**Token 与本地 `auth.json` 中的 `userName` 强绑定**。若本地用户名与 Token 绑定的用户名不一致，会报 `该 Token 已绑定其他 Command Code 账号`。换号时必须在 8787 面板底部更换为绑定该新号的新 Token，或联系作者换绑。
  - **实证绑定陷阱与最终闭环（2026-09-18）**：
    - Token `40Fn6...` 被云端永久绑定至 `local-user`；新 Token `gKYb0...` 被绑定至 `1819116334s9ds`；`2Hf_...` 与 `HTWBi...` 绑定至 `34ddd827...`。
    - **当前现役 Token**：9月11日发放的 **`taVIX6KjI7xZoUngqAtRncuWRYIf2pJQ`** 绑定满血的 `ningmengningmenl6jn` 账号，运行正常（`status: running`）。
    - **待用新卡密（备用）**：商家最新提供的全新未绑定卡密 **`arei2TZ6PODGONbHb6gvPMj6G9nKeYZC`**（留给下一个全新 Command Code 号使用，换号时在 8787 面板填入绑定）。
  - 配置保存在 `C:\Users\Janson\AppData\Roaming\cmdc-pak\config.json` (`{token, port}`)。
  - 推荐模型：`dsv4f`、`muse spark 1.3 contributor`。兼容 Cherry Studio、Qoder、Cline 等所有 OpenAI 兼容 Harness（接口 `http://127.0.0.1:8787/v1`，Token 填有效卡密，模型填 `dsv4f`，需关闭客户端的 reasoning/thinking 扩展字段防 400）。
  - **🔴 muse-free 协议红线（2026-10-03 Qoder 案七探针实锤）**：`muse-spark-1.3-contributor-free` **只吃 `/v1/responses` 或 anthropic `/v1/messages`**（两者均实测 200 出字）；走 `/v1/chat/completions` 必得 **HTTP 502「OpenCode Free 上游异常：OpenCode 返回 HTTP 500: Internal server error」**——Qoder 把它显示成笼统的「服务内部处理错误，请稍后重试」（重试三遍无效=确定性路由错，别被「请稍后重试」文案骗去查瞬时故障）。面板明示：free 版思考档位 **low/medium/high/xhigh「必须填对」**、1M ctx/131072 out；其余 8 个 free 模型（space-bunny/mimo-v2.6-flash/longcat-2.5/ling-3.0-flash-fin/nemotron×2 等）全走 Chat Completions。**Qoder 修复方=GUI 新建 anthropic 协议提供方**：Base URL 裸根 `http://localhost:8787`（勿带 /v1，anthropic 线填 /v1 会 404）、key `local-proxy`、思考档四值选一、并删掉误挂在 Chat Completions 提供方下的 `-free` 条目；不带 free 的 `muse-spark-1.3/1.2-contributor` 在 chat 线实测 200 可原样保留。教训：Qoder 报错文案是壳，真死因在网关返回原文，先探针后下结论。
- **8888（开源版 `cmdc-hub`）**：
  - GitHub: `zmjjcjb/cmdc-hub`，单文件 `cmdc-server.mjs` / `dist\cmdc-hub.exe`。
  - 直接读取 `~/.commandcode/auth.json` 中的 `apiKey`，无卡密与用户名绑定校验，直连官方 `/alpha/generate`。适合卡密被作者云端死锁时的即时替代方案。

## 2. Command Code 凭证与换号陷阱

- 凭证路径：`C:\Users\Janson\.commandcode\auth.json`（包含 `apiKey`, `userId`, `userName`, `keyName`, `authenticatedAt`）。
- **「Already logged in」静默跳过陷阱**：若 `auth.json` 存在，在终端运行 `cmdc login` 会直接显示 `Already logged in as <user>` 并立即退出，**不会拉起浏览器登录新账号**。换号前必须先物理删除 `auth.json`（或重命名备份），然后再执行 `cmdc login`。
- **TTY 强依赖**：`command-code` CLI 基于 React Ink 构建，**必须在真实交互式控制台（TTY）中运行**。在后台子进程、管道或非交互式 shell 中执行会报 `Raw mode is not supported on the current process.stdin`；通过 winpty 调用会报 `stdin is not a tty`。因此登录操作无法由 Agent 在后台自动化完成，必须由用户通过桌面脚本（如 `双击_登录新账号.bat`）在真实命令提示符窗口中完成 OAuth。
- **CLI 自更新损坏风险**：CLI 自带更新逻辑，若更新过程被强杀或文件被占用，会导致 `dist/index.mjs` 丢失损坏。修复方式：在进程管理器杀掉残留 node 进程后执行 `npm install -g command-code`。
- **Node 环境拓扑**：Node v24 位于 `C:\Program Files\nodejs`；全局模块路径配置在 `C:\Users\Janson\.npmrc`（`prefix=E:\ai-env\npm_global`），全局 bin 在 `E:\ai-env\npm_global\cmdc.cmd`。

## 3. 额度机制与使用禁忌

- **周额度 35 次上限**：Command Code Go 订阅存在严格的周请求上限——**每周仅 35 次请求**（`{"code":"RATE_LIMITED","rateLimit":{"limit":35,"remaining":0,"window":"weekly"}}`）。
- **重置周期**：自账号授权起每 7 天重置一次（按 UTC 时间戳 `reset: <timestamp>`），精确到秒。
- **账号实测状态（2026-09-18）**：
  - `ningmengningmenl6jn`：重置时间戳 `1789662215`（2026-09-18 08:23 北京时间）。直连官方 `https://api.commandcode.ai/alpha/generate` 经底层实测已满血恢复（HTTP 200，成功流式返回 `deepseek/deepseek-v4-flash` 推理 token）。
  - `1819116334s9ds`：周额度已耗尽（`remaining: 0`），重置时间为 `2026-09-22 17:33`（4 天后）。
- **官方 API 直连协议特征**：直连 `/alpha/generate` 必须携带 Header：`User-Agent: cli`、`x-command-code-version: 0.18.10`（否则 403 `upgrade_required`）；模型需传上游真实 ID 如 `deepseek/deepseek-v4-flash`。
- **Agent 使用禁忌**：Cline、Aider、AutoGPT 等自主 Agent 会在读写文件、跑测试时进行高频自动化多轮调用，单次任务即可消耗 5~15 次额度，极易几分钟内耗光整周配额。该渠道仅适合单次关键代码生成或在 Cherry Studio 等客户端中人工对话，不宜作为自主循环 Agent 的主力底模。

## 4. 网络与授权排障要点

- **10808 代理拒绝**：若用户环境变量中残留 `HTTP_PROXY=http://127.0.0.1:10808` 且本地代理软件未开启对应端口，cmdc-pak 启动鉴权会报 `proxyconnect tcp: dial tcp 127.0.0.1:10808: connectex ... refused it`。需清理用户环境变量中的代理设置。
- **Clash Fake-IP 域名劫持超时**：授权域名 `cmdc-pak.ljj233.top` 可能被 Clash Fake-IP 解析至 `198.18.0.x` 导致 `context deadline exceeded`。真实服务器为阿里云主机 `8.140.207.129`（TCP 443 通畅）。若鉴权超时，需在 `C:\Windows\System32\drivers\etc\hosts` 添加 `8.140.207.129 cmdc-pak.ljj233.top` 并刷新 DNS。
- **用户行为准则（2026-09-18）**：「我让你改成正确的 配置不用你来」——用户明确要求客户端（Cherry Studio / VS Code 等）的配置由其自行完成，Agent 只负责修复底层的 `auth.json` 与服务端网关健康状态，禁止擅自修改客户端配置。

## 5. 文档交付物归档
完整从零安装与排障手册已归档于：
- 桌面：`C:\Users\Janson\Desktop\Command_Code_Go使用指南.md`
- 长期归档：`C:\Users\Janson\Desktop\总结文档\重要总结\Command_Code_Go使用指南.md`

## 6. Command Code 原生底牌与 Qoder/Agent 适配改造路线

- **模型真实规格与原生能力（非普通日常聊天机）**：
  - **超大上下文与输出**：官方原生支持 **1,000,000 token（100万）上下文** 与 **200,000 token 单次最大输出**，适合吞吐几十万字长文或一整个代码库。
  - **原生 Agent Payload 结构**：官方接口接收包含 `config: {structure, isGitRepo, gitStatus, recentCommits}`, `skills`, `mode: 'agent'`, `params.tools` 的重型工程参数，具备底层自主沙盒感知能力。
  - **弱道德审查**：面向底层开发者的推理集群，前置安全围栏极低，适合去AI味、重构与敏感创作任务。
- **Harness 额度消耗差异**：
  - 限制根源在云端账号（周 35 次），所有客户端共用。
  - Cherry Studio 等纯聊天软件 1 次交互 = 1 次请求（可聊 35 轮）；Qoder、Cline 等 Autonomous Agent 一次指令后台自主循环 3~10 次请求，3~5 个任务即可吃光全周配额。
- **Qoder 深度适配魔改路线（基于开源版 `cmdc-hub`，约 100~150 行代码）**：
  1. **入参清洗（防止 400）**：在网关入口处剥离 Qoder/VS Code 附带的非标或 Anthropic 字段（如 `thinking: {type: "enabled"}`、`extra_metadata`），强制 `stream: true`。
  2. **模型参数宣告**：在 `GET /v1/models` 中为 `dsv4f` 注入 `context_window: 1000000` 与 `max_output_tokens: 200000`，防止 Qoder 默认按 4k/8k 限制吞吐。
  3. **多账号池与 429 自动无感轮转**：本地维护多账号数组，当官方云端返回 429 时，网关捕获后自动切换下一个账号凭证并立即重发重试，让 Qoder 任务不中断、实现“无限换弹”。
  4. **工具调用转译**：将 OpenAI 规范的 `tools`/`tool_choice` 映射为 Command Code 的 `params.tools`，流式返回中装配 `choices[0].delta.tool_calls`。

### 6.1 魔改落地状态（2026-09-20，未提交在工作区 diff）

四项设计已全部实装于本机副本 `C:\Users\Janson\.zcode\workspace\default\cmdc-hub`：
①`/v1/models` 从目录元数据注入 context_window/max_output_tokens + `MODEL_ALIASES`（dsv4f→deepseek-v4-flash，列表与调用都认）；
②多账号池 `~/.commandcode/accounts/*.json`（按 apiKey 去重；429 轮转只落在本请求未试过的账号、池尽即弃、成功后粘性停留；MAX_ATTEMPTS=池+2）；
③入参清洗/工具转译 v1.0 原生已有，未动；④env 三开关 `CMDC_UPSTREAM_BASE`（自检 mock 用，远端指向启动即警告泄 key）/`CMDC_LISTEN_HOST`（默认锁回环，非回环启动警告）/`CMDC_HEADLESS`。
验收：`node selftest.mjs` 零真实请求 17/17 PASS（含 A→C→B 跳过耗尽账号的回归场景、全目录解析契约）；真实冒烟+远端告警双路径复验通过；代码评审卡 Warning×3 全修。用法已写入 cmdc-hub README。**当前池是空的（只有主账号 1 号）——拿到第二个 cmdc 号后把其 auth.json 备份丢进 accounts/ 即生效，8888 起服即可替代 8787 的周额度瓶颈。**

### 6.2 Gemini 线「Claude Code 指纹死通道」定案（2026-09-21 独立复核）

Cherry agent 模式（Claude Code 运行时）走 8787 Gemini 线必死、ZCode 正常。**因果活体实锤**：同一请求带 `x-anthropic-billing-header: cc_version=…` 行 → 上游回 0 输出 token 的空 text 块（HTTP 200 伪装成功，日志 `GEMINI OK ... out=0 finish=MAX_TOKENS`）；删该行 → 正常。tools=39 流量 38 死 16 活（死=agent 模式，活=普通聊天），退避 49/502×40/429×128 与报告逐项吻合。**两处修正原报告**：①分流不在本地 exe——v0.6.4 二进制（桌面 `cmdc-pak (2).exe`，进程仍报旧 Downloads 路径）零命中 billing/cloudcode/googleapis/oauth2 字符串且非压缩壳，**扫描分流在商家云端中继，本地无开关**；②症状已从硬 429 漂移为「200+空内容」。给商家话术：其服务端按 billing-header 指纹分流的 lane 上游池已空，修池或并回主通道。短期规避：Cherry 只用普通聊天；agent 需求走 ZCode 或 Command Code 线 dsv4f。另记：现役 exe 已升 v0.6.4（09-21 10:13，G-cpil 码绑 ningmeng233 Google 账号，config.json 新增 gemini_token 字段，grant=gemini_ai_pro；日志现写在 Downloads\cmdc-pak.log）。

**ZCode 自定义提供方填法（Gemini 线，2026-09-21 定案）**：Provider ID `cmdc-gemini`（小写开头，用于派生凭据名）、API 地址 `http://localhost:8787/v1`、协议选 `anthropic-messages`、密钥 `local-proxy`（任意非空，不参与鉴权）。**8787 的 /v1/models 只返回 Command Code 线 26 模型、不含 gemini 四件套**——须手动「添加模型」逐条填 API ID：`gemini-3.8-flash-{high,medium,low,tiered}`；每模型上下文 `1000000`、最大输出 `64000`（硬上限，填错/留空=空回复）。表单提示「目录外 ID 仍可直接发送」即为此设计。保存后新开会话生效（配置为启动快照）。

**Base URL 带不带 `/v1` 是分客户端的玄学，404 先查这个（2026-09-21 dsh 实证）**：ZCode 要带（`http://localhost:8787/v1`）；dsh 这类客户端自己会补 `/v1/messages`，base 必须填裸根 `http://localhost:8787`——填错时网关日志现出原形 `POST /v1/v1/messages -> 404`，客户端只看到 Go 原样的「404 page not found」。另：日志里 `POST /v1/messages/count_tokens -> 404` 刷屏是 **Claude Code 系客户端的数 token 试探**，cmdc-pak 没实现该端点、客户端会自行跳过，属正常流量勿当故障排查。**ToonFlow v2 同属裸根阵营（09-25 源码实锤）**：其 anthropic-messages 适配器用 pi-ai 库=官方 `@anthropic-ai/sdk`（baseURL 直接传、SDK 自补 `/v1/messages`），ToonFlow 侧 cmdc-gemini 填裸根 `http://127.0.0.1:8787`；且 ToonFlow 非 Claude Code 运行时不带 billing header=安全通道。**ToonFlow 专用免费探针**：POST `/v1/messages` 带 `__probe__` 模型 → 400 原文回 Gemini 白名单四件套（本地拒绝零额度消耗）。

## 7. 局域网共享方案与致命风险

- **默认回环绑定限制**：`cmdc-pak` (8787) 闭源二进制硬编码绑定 `127.0.0.1`；`cmdc-hub` (8888) 在 `cmdc-server.mjs:2474` 亦硬编码 `server.listen(port, '127.0.0.1', ...)`。局域网外部设备直连默认被拒绝（Connection Refused）。
- **打通局域网共享方案**：
  1. **开源版 `cmdc-hub`**：直接将 `cmdc-server.mjs` 第 2474 行改写为 `server.listen(port, '0.0.0.0', ...)`，并配置 Windows 高级防火墙开放 8888 端口入站。
  2. **闭源版 `cmdc-pak`**：使用 Windows 原生端口转发命令（管理员运行）：
     `netsh interface portproxy add v4tov4 listenport=8789 listenaddress=0.0.0.0 connectport=8787 connectaddress=127.0.0.1`，局域网客户端请求 `http://<本机IP>:8789/v1` 即可。
- **致命风险与使用建议**：
  - **35 次周额度蒸发**：Command Code 官方配额按云端账号统一扣减，网关缺乏类似 8045 的独立多用户 Token 鉴权与配额隔离系统。一旦外部用户接入 Autonomous Agent（如 Qoder、Cline），单次任务多轮循环会在几分钟内吸干全部 35 次周额度。
  - **建议使用场景**：仅限本人在台式机与笔记本间切换使用；若分享给他人，必须在网关层编写简易 IP 频次拦截器（如单 IP 每日限额 2~3 次），或建议对方自购账号。
- **Gemini 线跨机共享（2026-09-21 用户问答定案，开洞待拍板）**：B 机**不装 cmdc-pak** 也能吃本机 Gemini 专线——上面第 2 条的 portproxy 8789→8787 同样服务 `/v1/messages`（Gemini 大脑本来就跑在本机+用户 Google 授权，B 机只是网络连过来）。B 机 DSH 填 `http://<本机IP>:8789`（裸根，见 §6.2 末段）。三前提：本机开机+8787 活着、一次性管理员配 netsh+防火墙、WLAN DHCP 的 IP 会变。⚠️ 开洞同时把 Command Code 35 次/周额度暴露给整个局域网（入站零鉴权）；家里 Wi-Fi 可控，热点/陌生网络环境别开。另一条未验证路线：同一张 `G-cpil` 卡密能否在 B 机自装 cmdc-pak + 同 Google 账号双机并发授权——需问商家，勿默认可以。

## 8. cmdc-pak v0.6.0 重大更新与 Gemini 专线事实（2026-09-20）

- **官网与版本发布**：官网 `https://cmdc-pak.ljj233.top` 于 2026-09-20 14:20 发布 `v0.6.0`。
- **双独立产品线与卡密互斥**：
  - 后台代码明确划分为 `command_code_go` 与 `gemini_ai_pro` 两个独立产品线，规则为“不签发双线 Key”，卡密互不通用。
  - Command Code 卡密（如 `taVIX...`）无法解锁 Gemini 专线，需单独购买或索取 Gemini 专属 Token。
- **Gemini AI Pro 接入规范**：
  - **授权机制**：客户端面板直接调用 Google OAuth 鉴权，授权码与个人 Google 账号强绑定（换号需后台重置）。
  - **通信协议**：客户端（ZCode / Cursor）**必须配置为 Anthropic (Messages) 协议**，不可使用 OpenAI 协议。
  - **模型名称**：精选主力模型为 `gemini-3.8-flash-high`，锁定最高思考推理档位，原生支持多模态截图与看图。
  - **稳定性修复**：针对自主 Agent 修复了流式多工具调用的名称拼接与参数丢失问题。

### 8.1 v0.6.1、G- 新格式卡密与升级待执行（2026-09-21 凌晨）

- **版本链获取法**：官网 SPA 无版本 API（FastAPI 404），changelog 全嵌在 `https://cmdc-pak.ljj233.top/assets/index-*.js` bundle 里；Windows 下载源 = **`/files/cmdc-pak.exe`**，HEAD 的 last-modified 与发布时间对齐可验版本。
- **v0.6.1** 发布于 2026-09-21 01:00（工具调用与稳定性大幅提升、长会话更稳、核心与安全机制同步）。桌面 exe 停留在 09-18 的 v0.5.8。
- **新一代卡密格式 = `G-` 前缀+连字符**（旧批次全是 32 位纯字符）。旧版面板/错误入口兑新码会报含糊的「已使用」。
- **「已使用」疑案自证法**：商家首码 `G-OrsF-rgJyYPFl75ST6i0GJur7hfiwcm3` 报已用过——grep 桌面 cmdc-pak.log 全量 2.7MB 该码零痕迹、当天无任何 verify/卡密变更 POST，**证明本机从未消耗此码**，举证责任推回商家要兑换记录；商家随后换发新码。教训：卡密纠纷第一步永远是查本地日志。
- **现役待启用**：`G-cpilNKQ95hBavoXpoG4JWXxydWeV0Tdm`（商家称属 gemini_ai_pro 线、已绑定用户 Google 账号 **ningmeng233**）。
- **v0.6.1 安装包已备好**：`F:\AI\tools\cmdc-pak\cmdc-pak-v0.6.1.exe`（14.0MB，sha256 `7b4ab4aa904a9c980bb852b1c1d0ab5b8d34ea60cae22946c41a3558e711c541`，落 F 盘符合不落 C 铁律）。
- **卡密台账（2026-09-22 已核实）**：`G-r0TwVlfSJepqPQb_KAAVwJaraHDBoa2S` 已给 **3315 = 33150804w@gmail.com**（用户 Google 账号，8045 反代 `/api/accounts` 在册，当前 `proxy_disabled=true` 未参与反代轮转）使用——即又一条 Gemini 线卡码绑到了第二个谷歌号上（G-cpil 绑 ningmeng233 是第一条）。此码不在本机 8787 面板兑换；纠纷自证走 grep 本地日志（§8.1 自证法）。**另记（09-22 用户口述）：8045 池里 `proxy_disabled=true` 的号（ningmeng233、33150804w、sammythomas1587）都是用户主动关的——「那边已经配置好了」，号已部署在他处专用；这不是故障也不是陈旧值，任何 agent/guard 不得把它们当坏账号"修回"轮转。**
- ✅ **升级已闭环（09-21 上午，无需再执行）**：三件套未等用户批复，用户**自行**从官网升级到 v0.6.4（10:13 完成，比当时备好的 0.6.1 又新两级——官网 `/files/cmdc-pak.exe` 永远指向最新版，SPA 无版本 API 时以 HEAD last-modified 对齐 changelog 发布时间验版本），并自己在面板完成 G-cpil 码 + Google OAuth（ningmeng233）绑定。`F:\AI\tools\cmdc-pak\cmdc-pak-v0.6.1.exe` 沦为冗余备份可删。后续客户端接入填法见 §6.2 末段。

## 9. http2 断连报错判读与 8787 活体探测（2026-09-20 晚实测）

- **报错判读**：ZCode 里出现 `upstream error: Post "https://api.commandcode.ai/alpha/generate": http2: client connection force closed via ClientConn.Close` = pak 内部 Go http2 客户端的复用长连接被单方面掐断（服务器回收空闲连接或网络闪断），请求正好落在掐断瞬间。**不是额度用尽**（额度超了明确报 429 `RATE_LIMITED`），不是配置坏——瞬时事件，消息重发即可。
- **8787 活体探测法**：POST `http://127.0.0.1:8787/v1/chat/completions` 带任意未知模型名 → 返回 400 + 完整模型清单（deepseek-v4-flash / deepseek-v4-flash-vision / deepseek-v4.1-flash / mimo-v2.5 / mimo-v2.5-pro / muse-spark-1.2-contributor / muse-spark-1.3-contributor / qwen3.8-flash），即为服务健康。注意 **8787 不支持 CONNECT**：`curl -x 127.0.0.1:8787 https://…` 会 exit 56 秒失败，这不是宕机信号，别误判。
- **TUN 关联（09-20 深夜实锤）**：8787→api.commandcode.ai 出网流量确被 TUN 收编——该域名解析=假 IP 198.18.0.23，亚毫秒本地握手+TLS 0.45~3.25s 抖动全花在 FlClash 替走节点/绕路上，这就是 http2 断连的土壤。用户 GUI 加 filter 豁免已随 FlClash 案 4 条豁免包落地（34 条，重启后五域名全真 IP ✅）。
- **ccgo 硬依赖代理在位（09-21 凌晨实测定案）**：`api.commandcode.ai` 真 IP=Cloudflare 172.67.x，**大陆无代理裸连必挂**（python/curl 一律 2.0s SYN 掉、http=000）——FlClash 半死/TUN 未开的当晚 ccgo 全线不可用，唯一解=先把代理（TUN 或 10808）弄活走节点出网。filter 豁免只防假 IP 缓存炸，**不改变该域名须走节点的事实**；早前"复发把 api.commandcode.ai 加直连"的说法作废（直连=死路）。相关：[[flclash-tun-topology-20260920]]
- **2026-09-21 新事实**：①8787 的 `/v1/models` 清单**不显示** `gemini-3.8-flash-high`，但网关在 `/v1/messages`（Anthropic 协议）通道认识它——pak 对 Gemini 订阅强制走 Messages 端点（chat/completions 会返回明确指引 400），实测 6.2s 活体返回；ZCode 新 provider「真 哈基米」=`new-provider-2`（anthropic-messages + localhost:8787/v1）即此通道，8 张 gemini 子代理卡已换绑到它（见 [[zcode-subagent-model-selection]]）。②桌面 pak 已改名 `cmdc-pak (2).exe`，`start-proxies-hidden.vbs` 末尾硬编码的 `Desktop\cmdc-pak.exe` 报"找不到文件"（不影响六个 python 代理，它们先启动）；v0.6.1 升级仍挂起（`F:\AI\tools\cmdc-pak\cmdc-pak-v0.6.1.exe` 已备好），升级时顺手修 vbs 路径。③今晚实测 8787 对未知模型名"x"不再回 400 清单而是静默回退 deepseek-v4.1-flash——活体探测判读口径有变，别拿 200 当"模型存在"证据。④09-21 傍晚再测：未知模型 `__probe__` **又回了 400+清单**（③与④两种行为并存、随时间/入参漂移，判读时两种都要认）。同日实锤：**8787 没有任何向量/嵌入接口**（`POST /v1/embeddings` → 404 page not found）——做不了图书馆/RAG 的嵌入后端；DSH settings.yaml 的哈基米卡模型名 `gemini-3.8-flash-high` 虽不在该 400 清单（chat 通道）里，但 DSH 走 `/v1/messages`（Anthropic 协议）通道认识它，不受影响（见上①与 [[dsh-desktop-identity-and-variants]]）。**2026-09-25 补充**：探针打在裸 `/v1` 路径（POST `/v1` 带 `__probe__` body）实测得 **404 page not found**——「400+清单」口径只对 `/v1/chat/completions` 路径成立；整链活体判据改用「cmdc-pak 进程在 + 8788 `GET /v1/models` 返 200 带模型清单」（当天实测有效，不烧周额度）。

## 10. Qoder 接入 8787 双线条规（2026-09-23 凌晨实测）

- **Qoder 支持 BYOK 自定义提供方**：配置在 `~/.qoder/settings.json` 的 `providers.qoder-custom-<uuid>`（字段：baseUrl/apiKey/type=openai-compatible/protocol=openai|anthropic/authType/model/models[+capabilities]）。启动日志见 `byok_ready=true`、`[custom-providers] allowed:true`。**默认聊天全走 `qfmodel`（api3.qoder.sh 云端 SSE agent_chat_generation），必须在模型选择器手动切到自定义模型才走本地线**——用户"配置没生效"多半只是没切模型。
- **deepseek 线实测可用**：protocol=openai + `http://localhost:8787/v1` + bearer/local-proxy，09-23 01:12 起流式带工具 100 请求全 200。更稳可改指 8788 南孚消毒线（防 effort 字段 400）。
- **gemini 真哈基米线本地 400 案（两层错误）**：①模型声明带 `capabilities.thinking={modes:[enabled],supportsEffort:true,...}` 时，Qoder **发送前本地校验**判死：`Invalid Anthropic thinking configuration ... requires an explicit fixed budget ... budgetTokens`，status=400、6ms、不重试、**请求不出网**（pak 日志无 /v1/messages 记录=本地拒绝的免费探针）。②删掉声明后若**会话还开着思考档位**，错误变体 `reasoning.effort 'max' is not supported by this model`——两层都要关：文件删 thinking 块 + 会话/新对话别选思考档。删声明后的旁证：Qoder 内部 utility 请求（session-title 生成，不带 thinking）立即 `GEMINI OK ... finish=STOP` 成功出字。
- 🛑 **settings.json 会被运行中的 Qoder 进程回写覆盖**——用户手改又被改回（"我自己试着改了 改不掉"谜底）。09-23 实证：agent 01:19 删块生效→用户 01:25 在提供方编辑界面一保存，thinking 块整段复活**且 baseUrl 被改成 `http://localhost:8787/v1`**——anthropic 协议下 Qoder 自动拼 `/v1/messages`，填 /v1 变 `/v1/v1/messages` → 404（同 DSH 裸根铁律，见 [[dsh-desktop-identity-and-variants]]）。结论：**改前必完全退 Qoder（含托盘），改完重开勿再进提供方设置界面**；或纯 GUI 修两处（Base URL 去 /v1 + 思考开关关）。旁注：编辑对话框开着期间其它会话会瞬时报 `get_model_policy failed: outerProvider is required for external provider model`，保存关闭即消失，非独立故障。
- **结案（09-23 01:36 实核）**：用户 01:32:01 在 GUI **重建了提供方**（新 uuid `qoder-custom-79b00e09`，baseUrl 填对=裸根 `http://localhost:8787`），01:32:41 pak 实测主消息请求 200：`GEMINI OK stream=true msgs=3 tools=27 in=42218 out=45 ttfb=14.19s dur=14.52s`。**注意 thinking 声明仍在文件里**（未再删）——只要会话不开思考档就能用，开档必 400，属留雷。todo 曾记「三刀 01:35:45 已执行+备份 .bak3」为**不实**：`.bak3` 不存在、settings.json mtime 停在 01:32:01，勿据此找备份。速度画像：小请求 ttfb≈3.2s；agent 大请求（42k 输入+27 工具）≈14s，慢在全量预填充，出字后 ~136 tok/s 很快——属线路正常特性。
- 旁证：**pak 日志实际位置 = `C:\Users\Janson\Desktop\cmdc-pak.log`**（§8.1 记的 Downloads 路径已过时）。
- **Command Code 余额耗尽事件（09-23 01:4x）**：ZCode 报 `Compact failed provider=7d703230(自行车) model=deepseek-v4.1-flash 400 insufficient credits`——commandcode.ai 官方文案"购买更多额度"。8787 双探针实锤分叉：deepseek 线（taVIX 卡 Command Code 账号）**死**，gemini 线（G-cpil）**200 无恙**（两条产品线独立账号/池，一荣不共享一枯不同枯）。头号消耗嫌疑=01:12-01:21 用户 Qoder agent 测试在 deepseek 线连打 100+ 条 ≈4万 token 全量上下文请求。影响面：自行车四模型同账号（qwen3.8-flash/muse/dsv4f/deepseek-v4.1-flash）随时全炸、8788 南孚与派 deepseek 卡同样不可用。处置=找商家充值/给新码或等其额度重置；期间用 gemini 线顶替。对质凭据=ZCode 报错 TraceID `7f2a6018-0a4c-4cb1-8013-e483672b1d05`。
- **pak 卡密存储位置（09-24 实查）**：`C:\Users\Janson\AppData\Roaming\cmdc-pak\config.json` = `{token(现行 CC 卡密；09-24 11:13 起=jwrEYU19X0…，此前=taVIX…2pJQ), port, verified_at, gemini_token(G-cpil…)}`——换号验证/回滚先看这里；同目录另有 gemini_grant.json/gemini_token.json。注意与 `~/.commandcode/config.json`（只有 installed 标志）是两码事，§8.1 旧文"config.json 新增 gemini_token"指的是 AppData 这份。
- **「换 ccgo 账号无效」取证（09-24 上午）**：用户报"换了好几次账号都说没额度，最夸张连没绑定的新号也没额度"——本地实锤**换号从未生效**：`~/.commandcode/auth.json` mtime 停在 09-18 17:15（userName=ningmengningmenl6jn、apiKey user_4e7dgok…、authenticatedAt 09-10），pak 日志最后一条 verify=09-22 15:38（taVIX 卡）；**gateway 发流量只认 auth.json 缓存身份（"already logged in"陷阱再证），浏览器/官网换号毫无意义**，所有"insufficient credits"都是老账号那堵墙，包括"没绑定的新账号"。真换号双要素：①本地身份=8787 面板退出重登，或全退 pak 后备份删 `auth.json` 重启走登录（09-18 旧档=`auth.json.bak-ningmeng-0918`）；②卡码须商家重绑到新用户名（卡密与 userName 强绑，缺了报"该 Token 已绑定其他 Command Code account"）。若官网面板显示每个新号确实零余额=池子在商家手里，纯商家账，拿 TraceID 对质。⚠️ 乱点面板登录前先确认不会把 gemini 线的 Google 授权（G-cpil/ningmeng233）一起退掉。
- **13 码全量台账（09-24 对账自商家 QQ 聊天记录全档 = `C:\Users\Janson\Desktop\6haha\6haha.txt`，明文码以该文件为准）**：商家（QQ 1120166455，cmdc-pak 作者）**自认查不到绑定史**。CC 线 8 把：`40Fn6…`(09-09 赠送初代)、`2Hf_…`(09-10 补发已废)、`HTWBi…`(09-10 台式迁移赠送)、**`taVIX6…2pJQ`=本机现役(09-23 耗尽)**、`jwrEY…`(用户口述"iwr 开头"，09-24 用户亲证=**绑定 2663489968@qq.com 的新号码，现役可用**，本机换号正解=先把 cmdc CLI 重登成新号再在面板贴这把码，09-15 案底"先登录后授权"顺序教训)、`ShukX…`(09-15 填错期补发，去向未核)、`gKYb0…`(09-15 末次成功=已绑)、`arei2…eYZC`(09-18 发"新号"，本机从未绑、公司电脑/台式去向未知=唯一待试码)。G 线 5 把：`G-OrsF`(纠纷码本机零痕迹)、`G--UEZy`(09-21 发公司电脑，本机面板未见入池)、`G-OrsF` 同上。
- **Gemini 线三号池面板实盘（09-24 用户截图，pak 多账号管理已上线）**：①**当前激活= `sammythomas1587@gmail.com` ↔ `G-5mQP…LW3NU2`**（该码 09-21 02:06 商家原发"公司电脑"，实际在本机激活；sammythomas1587 同时是 8045 池里 proxy_disabled 的号——"已在他处配置好"的去处之一实锤）；②`33150804w@gmail.com` ↔ `G-r0Tw…DB0a2S`（待命，与 §8.1"给3315"台账对上）；③`ningmengningmeng233@gmail.com` ↔ `G-cpil…eV0Tdm`（待命，**并非现役**——09-23 前所有"G-cpil=本机现役"的记述按此更正）。真哈基米线若炸，第一反应=看面板激活灯在哪号、该号 AI Pro 池是否耗尽，可切灯换号继续用。
- **换号闭环（09-24 11:3x 全绿）**：CC 线新现役=**`jwrEYU19X0…` 绑用户名 `ningmeng233333`**（注册邮箱 2663489968@qq.com，登录页认用户名不认邮箱）；`taVIX6…2pJQ` 退役封存（老号 ningmengningmenl6jn 已耗尽，auth.json 旧备份 `auth.json.bak-ningmeng-0918`）。执行链：`cmdc logout`→删净 auth.json→`cmdc login` 新号（apiKey=user_2k3ULXF…）→面板贴 jwrEY 码 verify ok→**deepseek 探针 200，且 pak 无需重启**（v0.6.4 按请求现读 auth.json）。三层身份铁律：**商家码(面板)管授权、官网 CLI 登录(auth.json)管扣额账号、二者独立换一不换二**——09-23/24 两晚"换号没反应"全因只做了一层。坑：Git Bash 弹的窗口带 `TERM=xterm-256color` 会把 cmdc TUI 噎得无声退出，`set TERM=` 清空后 `start cmd /k cmdc login` 才见界面。
  - ⚠️ **09-24 附注（h开头账号疑云定案，09-25 破案）**：用户反映 `2663489968@qq.com` 似乎绑定到了一个 `h` 开头的账号。**09-25 实锤破案**：根本不是账号名以 h 开头，而是 19:45 cmdc-pak 重装拉起后，Edge 弹开的 8787 面板上卡密变成了 09-10 赠送的老卡密 **`HTWBiWs0nbJCYv9s-KqJS4GB-dit9S_9`**（以 H 开头），用户一眼看到 H 开头误以为账号绑定错。本地 `auth.json` 真实身份仍是 **`ningmeng233333`**（邮箱 2663489968@qq.com，userId `34ddd827-18e4-4bfd-9250-dea255953519`），对应的现役满血有效卡密是 **`jwrEYU19X0MD68kdXFQmF4VD8dFGR3ii`**，在 8787 面板底部重新贴回 verify 即可恢复。
  - **1819116334@qq.com 账号台账与密钥（09-25 实盘记录）**：该邮箱对应的完整账号信息记录在 `C:\Users\Janson\AppData\Roaming\cmdc-pak\commandcode_accounts\`（多账号池 `index.json` 与 `6650e24c13e194dbea965027af272a05.json`）：
    - **登录用户名**：`1819116334s9ds`
    - **User ID**：`0e7a8924-0c9c-4f95-a768-791ee3355e35`
    - **API Key**：`user_4bqaxxrke8eWXVjuTq7m1TVSp6Nw6fcuQG3WjbiCujS4vm7z9mURL7pA7m4Zefyckz5QvF1Jwn1keg1ybicxZRSH`（09-15 初版）/ `user_5qGfjwgtNzLY6YUB5VAXinkKHUy89h4dfxH9zwpRuzcmotJfQETu3gfGZxCGQm9K71PThGtGDWhjofNWSQyCmW6e`（09-24 刷新）
    - **专属绑定商家卡密 (Token)**：**`gKYb0n-igR5OX7QL8VpUTGe0XfbwxEz2`**（09-15 锁定绑定至该号，额度早已重置满血）
    - **状态**：09-25 已被设为 `active_user_id` 并同步写入本地 `C:\Users\Janson\.commandcode\auth.json`。
  - **全量三账号与卡密绑定矩阵（09-25 终审定案）**：
    1. `1819116334@qq.com` ↔ 用户名 `1819116334s9ds` ↔ 卡密 `gKYb0n-igR5OX7QL8VpUTGe0XfbwxEz2`（满血可用）
    2. `2663489968@qq.com`（新） ↔ 用户名 `ningmeng233333` ↔ 卡密 `jwrEYU19X0MD68kdXFQmF4VD8dFGR3ii`（现役主力）
    3. `2663489968@qq.com`（老） ↔ 用户名 `ningmengningmenl6jn` ↔ 卡密 `taVIX6KjI7xZoUngqAtRncuWRYIf2pJQ`（已耗尽退役）
    - 备用未绑定新码：`arei2TZ6PODGONbHb6gvPMj6G9nKeYZC`
    - 误填/历史码：`HTWBiWs0nbJCYv9s-KqJS4GB-dit9S_9`（重装拉起 8787 面板时可能自动回填，若见到 H 开头即是它，手动换回现役码即可）
- **Qoder 自定义模型全崩 `outerProvider is required for external provider model`（09-25 破案）**：
  - **症状**：Qoder 发起任何消息时，QueryEngine 报错 `outerProvider is required for external provider model "qoder-custom-<uuid>/..."`。
  - **根因**：Qoder 的 CLI Worker 进程（如 PID 7004）在后台持续常驻未退，外部重装网关或修改配置后，Worker 内存中的 `allModels` 列表未刷新，无法识别私有 `qoder-custom-...` 前缀，误将其判定为未配置的云端托管外部模型（如 OpenRouter）而强行拦截。
  - **解法**：**彻底退出 Qoder 客户端（任务栏托盘右键退出，确保 Qoder.exe 全退）后冷启动**。重新打开后 Worker 会从 `~/.qoder/settings.json` 重新扫描注册自定义模型，报错彻底消失。
  - **附加长上下文 408 坑**：当上下文过大（如 261 消息、67 万字符）走 8787 Gemini 时，首字生成前全量预填充会使首字超过 60s，触发 `ModelFirstPayloadTimeoutError` (ETIMEDOUT 408)。Qoder 会自动重试一次（第二次 10s 内返回 200）。
- **商家侧规则与自认事实（6haha 档，09-24 定案"勿盲试"）**：①一码绑一号、verify 成功=当场占绑给当前 auth.json 账号——盲试会烧码；②商家惯例=码用完**找他要新码**（09-10~09-21 免费补发 6 次先例，"用完了点退出然后找我要个 key 就行"）——正解是补码非试旧码；③commandcode.ai 官网"用量显示"商家自认完全不准（cookie 管理烂，09-24 强刷也没救回），但 **API 返回的 insufficient credits 是真错**，两种信号分开判；④商家只适配 ZCode/DSH/opencode，**Qoder/Cherry 明说没适配**（"qoder 闭源没法适配、很难用"）——Qoder 接 8787 纯用户自研（§10），出问题商家不管；⑤Gemini 思考预算 **high=10000、tiered=32000**——"gemini 思考两分钟"多为回退 tiered 所致；⑥**用户本人 QQ=2663489968**——商家侧账号、"换号"、github 提交名 ningmeng233333/2663489968@qq.com 全是用户自己的身份标识，非第三方。


**2026-09-25 重装落定**：新版（15.65MB，MD5 9ab9a902e317784fccb54166150682a4，双份独立下载一致）装于 D:\cmdc-pak\cmdc-pak.exe 并运行中（8787 监听、面板 HTTP 200）。官网真实直链 = https://cmdc-pak.ljj233.top/files/cmdc-pak.exe（下载页是 SPA 抓不到，直链藏在前端 /assets/index-*.js bundle 里）；nginx etag 不是内容 MD5，校验别拿它对。**Defender 已加路径排除 D:\cmdc-pak**（5007 事件验证生效）；教训：未签名 exe 被吞是「延迟几秒动手」，下载完立刻 ls 到文件不代表安全，排除生效验证走事件日志 5007（普通权限读排除清单与 MpCmdRun -CheckExclusion 均 0x80070005 拒绝）；Git Bash 里 cmd //c start 的 /D 会被 MSYS 路径改写毁掉，拉起 GUI 程序用 PowerShell Start-Process。F:\AI\tools\cmdc-pak\cmdc-pak-v0.6.1.exe 旧版未动。

**更新套路（09-25 定稿，高频更新软件）**：对 agent 说「更新 cmdc-pak」即执行——退出进程→覆盖 D:\cmdc-pak\cmdc-pak.exe（直链 /files/cmdc-pak.exe 恒定，失效就去前端JS bundle grep /files/）→双份MD5校验→桌面「cmdc-pak 网关」快捷方式启动（Start-Process，勿 Git Bash start /D）→8787+面板200验收；Defender 排除 D:\cmdc-pak 常驻，被秒删=排除丢了重加并走5007事件验证。完整方法已存 OpenViking 图书馆。
**2026-09-26 更新回合（终）**：换到 0925 深夜构建（09-25 15:36 UTC，16409088B，MD5 2068d2a2444db48ce428c31e2c737ce1），覆盖 D:\cmdc-pak\cmdc-pak.exe 运行中，验收全绿（8787 监听+面板 200）。旧版移入 桌面\待删除区_20260926\：F:\AI\tools\cmdc-pak（v0.6.1 整目录）、桌面旧包 cmdc-pak (3).exe、0925 版回滚备份 exe；F 盘已无 cmdc 目录；真删待用户「清空待删除区」口令。GateGuard 教训：危险词按命令文本字面匹配，连写进记忆引文都误伤（本次命中一次），三件套+用户「执行」后原样重试放行。

**桌面快捷方式「看不见」案（09-27 定案）**：用户报 cmdc-pak 快捷方式消失，实查 `Desktop\cmdc-pak 网关.lnk` 一直在、无隐藏属性、指向 D:\cmdc-pak\cmdc-pak.exe 全部有效——是 Explorer 显示层没刷新。修法=用 WScript.Shell 原地重写该 lnk（内容不变、时间戳刷新）强制资源管理器重识别；排障阶梯：F5 刷新 → 右键桌面「查看→自动排列图标」（防图标被挤到屏幕外）→ 原地重写。

**三协议路径实测与「别人电脑 input.type 400」诊断（09-27 定案）**：8787 三路实测全绿——①`/v1/chat/completions` 打 deepseek-v4.1-flash 带/不带 `deepseek/` 前缀均 200（两别名都在 /v1/models）；②`/v1/messages` 打非 gemini 白名单模型=明确报「不支持的模型…Gemini AI Pro 当前仅支持严格白名单 gemini-3.8-flash-{high,medium,low,tiered}」，不伪装成别的错；③**`/v1/responses` 端点存在且可用**（字符串 input 与无 type 的数组 input 均 200）。**判据：报 `MissingParameter: missing input.type` 的 400=请求被路由到 Responses 方言的上游池而 input 项缺 type**——换 Chat Completions 协议即绕开；同名模型在不同卡密/账号绑定的线路上可能接不同上游，别默认「别人的线=我的线」。

**2026-09-27 更新回合（✅终态全绿，勿再执行）**：用户令「更新 快快快 放桌面」。新版双份下载比对一致 **MD5 `ea458450d73c4aa998106c5a0785cb9b`**（≠旧 2068d2a2），**直链裸连超时（exit 28），必须走 `-x http://127.0.0.1:10808` 代理**（慢，单份要 90~240s 时限）。热替换：`mv cmdc-pak.exe cmdc-pak.exe.prev`（**运行中的 exe 可以改名，不必先杀**）→ Stop-Process 被 GateGuard 首拒 → 用户回「执行」后**原样重试**放行 → 新版 PID 16184，验收 8787 监听+面板 200+deepseek 探针 200 全绿；面板授权 Token 重启后不丢无需重填。桌面副本 `Desktop\cmdc-pak_20260927.exe` 已放（MD5 复核一致；桌面不在 Defender 排除内，若被秒删从 D 盘权威副本重拷即可，别当故障）。回滚=杀进程后把 `.prev` 改回原名再启动。更新记录已存 OpenViking（写入时服务又静默掉线一次，重拉启动 vbs 约 50 秒恢复后补写成功）。

**模型白名单全量菜单（09-27 实测定案）**：两条协议线都是严格白名单，未登记模型名（连真实存在的 claude-sonnet-4-5 也一样）一律 400「未知模型」，客户端手动添加模型名无效——客户端侧手动添加仅适用于「网关有但客户端列表没显示」的补登记场景（gemini 四件套即此用法）。全量=chat/completions 线 9 个：deepseek-v4-flash、deepseek-v4.1-flash、mimo-v2.5、mimo-v2.5-pro、mimo-v2.6-flash、mimo-v2.6-pro、muse-spark-1.2-contributor、muse-spark-1.3-contributor、qwen3.8-flash；Gemini 线 4 个：gemini-3.8-flash-{high,medium,low,tiered}。菜单可随时用假模型名探针的报错原文重新抓取（§9 的旧清单已漂移，以此为准）。

**Gemini「全挂+网页1060」案（09-27 ✅已结案）**：用户报 cmdc Gemini 通道全用不了、Gemini 网页显示 1060。实测反转：白名单四档里 **只有 high 挂**（网关原话「上游服务暂时不可用，请尝试更换代理节点后重试」），low/medium/tiered 全 200；当时出口 IP=东京 JP 照样单挂 high，说明门槛按更细的 IP 信誉/机房属性判而非只看国家。关键认知：**Gemini 线从本机出口 IP 打 Google**（AppData\Roaming\cmdc-pak\gemini_token.json 本地 OAuth 令牌）——用户节点直接决定这条线生死，网页 1060（节点脏，见 [[antigravity-account-403-validation-block]]）与本机 API 通道同源。**结案证据：用户换节点后复验——新出口=台湾台北 155.254.124.35（Micfo 机房，hosting/proxy 标记齐全），四档全绿含 high**；换节点立竿见影即根因铁证。🔴纪律：此节点已验证可用，**固定使用勿频繁切换**（防「不可能旅行」风控，sammythomas1587 前科即被越切越锁）。未完事项：新版日志位置仍不明（旧 Desktop\cmdc-pak.log 停在 09-24 10:21）；该验收结论存 OpenViking 时服务恰逢掉线**未入库**，待补。

**卡密找回通道（2026-09-26 定案）**：来历不明的历史 32 位卡密可经**只读查 ZCode 会话库** `C:\Users\Janson\.zcode\cli\db\db.sqlite`（mode=ro）从旧会话记录里找回——10 个来源不明码已全量找回；`ShukX…`（09-15 补发）去向仍未核实（低优先级）。铁律重申：一码一号 verify 即占绑，找回的码勿盲试。09-26 会话已把台账/排障增量存入 OpenViking 图书馆（密钥明文不入馆，只存对应关系与查证路径）。


**🔴 2026-10-02 白名单变天实锤（旧"9chat+4gemini"口径作废）**：ZCode2 经 8787 请求 muse-spark-1.3-contributor 吃 400，网关官方文案=Gemini AI Pro 原生白名单仅 [gemini-3.8-flash-high/medium/low/tiered] + Claude 官方全系别名(Sonnet/Haiku/Opus/Fable)——**muse-spark 等 9chat 旧名单已下架，疑似 cmdc 卡型/授权档变更**。ZCode2 分身（家目录=F:/AI/ZCode2/data，配置在 .zcode/v2/provider_config.json，providerId=new-provider-2 名"ccgo" 指 8787）三处模型名已改 gemini-3.8-flash-medium（备份 provider_config.json.bak-20261002-104451）。muse-spark 仍活在主实例 Atria 线（providerId=7d703230，含 qwen3.8-flash/muse-spark-1.3-contributor/deepseek-v4*）。ZCode2 配置改动需重开会话生效。

**⚠️ 与上条的矛盾证据（10-02 同日稍晚，执行 ZCode2 配置前必须先复核）**：用户当日 10:52 贴来的 cmdc 面板日志显示 10:52~10:57 间 muse-spark-1.3-contributor 经 `/v1/chat/completions` **连续 200（UPSTREAM OK ttfb 0.3s 级）**，且面板官方模型表仍完整列出 9 个 chat 模型带规格——「9chat 已下架」结论与面板实况冲突。两种可能：①上一条的 400 是请求打错路径（撞上 /v1/messages 的 Gemini 白名单文案）；②卡型在当天内反复变动。**动手改配置前先发一条 chat/completions 假名探针重抓菜单为准，勿直接信任何一侧。**

**面板官方模型规格表（10-02 用户贴自 cmdc 面板，写 ZCode/客户端配置用）**：全部上下文 1M、协议 Chat Completions（⚠勿选 Responses）。deepseek-v4.1-flash（默认推荐）与 deepseek-v4-flash：最大输出 **200000**、思考档 low/high/max；muse-spark-1.3/1.2-contributor：131072、low/medium/high/xhigh（面板标注「隐私或敏感内容勿用」）；qwen3.8-flash：131072、low/medium/xhigh；mimo-v2.6-pro/v2.6-flash（图文）/v2.5/v2.5-pro：131072、思考「默认开启（不可调）」= 配置里不写 reasoningLevel 档位。Base URL `http://localhost:8787/v1` + API Key `local-proxy`（不能留空）。Gemini 线另有 opencode_free / gemini_ai_pro 产品线标注（启动日志「门内产品线」）。

**OpenCode Free 协议探针与 ZCode2 修正回合（10-02 补）**：①muse-spark-1.3-contributor-free **chat/completions 实测上游 502（OpenCode 500 内部错）**，坐实面板「Responses 或 /v1/messages」——该模型只能挂 anthropic-messages 线（/v1/messages 实测 SSE 正常、/v1/responses 也通），这正是 ZCode2 需单开 opencode-free 供应商的原因，非多余配置；②网关 /v1/models 实际挂 **9 个 free 模型**（面板只列 7，多出 mimo-v2.5-free、muse-spark-1.2-contributor-free，参数面板未给暂不配）；③6 个 chat 线 free 模型探针 5 通，ling-3.0-flash-fin-free 连续 502「Endpoint is unavailable」＝OpenCode 上游端点暂挂，非本地配置问题，配置照加等恢复；④用户纠正「配错了」＝第一轮多加的真哈基米 gemini 供应商要删（用户只要粘贴过的内容）。

**✅ ZCode2 第二轮执行终态（10-02，备份 `provider_config.json.bak-20261002-111416`，校验 16 规则无孤儿全绿）**：用户「退出了 执行」并追加铁律 **「opencode 那个我自己电脑没配置过，别和 ccgo 搞混」→ ccgo 一字不动**（原「6 个 free chat 塞进 ccgo」方案作废，free 系全部独立成线）。终态三供应商：ccgo（new-provider-2，9 付费 chat 模型原样）+ opencode-free（6 free chat）+ opencode-free-muse（anthropic 线挂 muse-free）——细节与参数见 [[zcode-desktop-cdp-skinning-and-multi-instance]]。

**🔴 muse-free 协议翻案（10-02 实测定案，「OpenCode Free·muse 无法正常使用」根因）**：上一条里「/v1/messages 实测 SSE 正常」是**假阳性**——当时探针被 head 截在流开头没看到结尾；完整流跑完=**200 空包**（message_delta `output_tokens: 0`、end_turn 收尾零输出，即 §6.2 同款「200空包」死法），ZCode 收到空回合→无限重连。三条协议全量复测：`/v1/messages`=200空包、`/v1/chat/completions`=上游 500、**`/v1/responses`=真出字**（`TEXT:'OK'`、status completed、output 28 tokens 含 encrypted reasoning）。**修法**=ZCode2 的 opencode-free-muse 供应商 `api.type` 由 `anthropic-messages` 改 **`openai-responses`**（该枚举已在 F:\AI\ZCode\resources\app.asar 里实锤存在，同族还有 openai-chat-completions / openai-compatible），base URL 不变（网关 /v1/responses 同在 /v1 下）。三件套已交等「执行」，改前 ZCode2 须全退。**教训：SSE 探针必须看到 message_stop/finish_reason/usage 完整收尾才算「能用」，截开头=没测。**

**ZCode2「重新连接中 x/10」疑云（10-02，与 cmdc 无关的方向）**：ZCode2 主日志（F:\AI\ZCode2\data\.zcode\v2\logs\YYYY-MM-DD.log）grep '8787' 零命中（仅 UUID 巧合）——ZCode2 从未向 cmdc 网关发过请求；同日志 billing 显示其默认模型 **GLM-5.3-Flash（zai-start-plan）额度 1亿/1亿 全耗尽、2026-10-02 08:00 过期**（setting.json: providerFamilyDomain=zai、enabledBuiltinAgentCliProviders=["glm"]）。用户报「重新连接中 3/10」+「你确定能用了？」大概率是**没切模型就用默认 GLM 发消息**在重连 Z.ai，与 ccgo/opencode-free 无关——排障时先问「模型选择器切到哪了」再查通道。

**香港节点矩阵（10-02 实测，156.224.78.209 Akile）与选点推荐**：HK 12/16 通——gemini 四档**全绿含 high**（推翻「香港必挂 Gemini」预期：cmdc 的 Gemini API 线与网页 1060 是两套门槛）；付费 chat（deepseek/qwen/mimo）与 free chat 全绿；❌付费 muse 1.3/1.2＝Meta Geographic Use Policy **连香港一起封**（台/港都拒，要救只可能试美区/新加坡）；❌muse-free＝OpenCode 上游 RegionError 403 拒港（台湾独活）；❌ling-3.0 上游 502 未愈（与节点无关）。对比裁决（后被新加坡推翻）：当时判台北 13/16 > 香港 12/16。deepseek「content:null」假警报口径：max_tokens 给太小会被思考吃光，给足 2000+ 即出字，各节点均如此。

**🏆 新加坡节点登顶（10-02 终测，155.254.108.8 Akari）＝三节点终榜冠军**：16 模型全量扫描 **15/16 绿**——①gemini 四档全绿（high 首测疑 FAIL 又是思考吃光 max_tokens 的假象，2000 档复测 `content='OK'` finish=end_turn）；②付费 chat 七模型全绿；③**付费 muse 1.3/1.2 复活**——**Meta 认新加坡**（台/港都拒的唯一解，169 token 思考后正常出字）；④free chat 五绿 + muse-free 走 /v1/responses 绿；⑤唯一死=ling-3.0-flash-fin-free（OpenCode 上游 Endpoint unavailable，台/港/新三节点同挂＝商家上游故障与节点无关，等修）。**终榜：新加坡 15/16 > 台北 13/16 > 香港 12/16**。最终建议已交付用户：固定新加坡为 cmdc 专用节点；ZCode2 配置与节点无关零改动。三节点矩阵与登顶结论均已存 OpenViking 图书馆。

**报错分型总表（10-02 收齐五型，ZCode/opencode 线报错见错对号）**：①`503 service_overloaded`（「backend is temporarily overloaded. Please retry」）=上游后端临时过载，瞬态非配置——**等几十秒到几分钟手动重发**；🔴ZCode 会标 `retryable=false` 不会自动重试（provider_code=upstream_stream_error reason=unknown），须手动再发。②`502 Endpoint unavailable`＝上游端点挂（ling-3.0-flash-fin-free 三节点长期同挂），等商家修。③`400 missing input.type`＝协议方言错。④`403 RegionError`＝OpenCode 拒当前节点地区。⑤Meta 封区（报错正文含「Meta's Geographic Use Policy」，且 cmdc-pak 会**吞掉上游错误外包一层 200 空 content 的成功壳**，有时两段 JSON 拼接、有时流式 2-3 事件 text=0 finished=false）＝换节点——**「200空包」不一定是指纹问题，排障必须看原始响应体不能只看状态码**。样本 TraceID（503 案）=97589839-9800-43de-b573-4b36c0d75db6。⑥**出口用量 RateLimit**（「OpenCode 提示当前网络出口用量已达上限（RateLimit），请在网络代理工具中切换出口线路后重试」，10-02 首见，TraceID 10bbc0db）＝OpenCode 免费中继**按出口 IP 记账**，该 IP 桶的额度被打满——**间歇性非拉黑**（同 IP 换发小探针即过；出口 IP 还会在同池内漂移 155.254.108.8→.6，各自记账）；`retryable=false` 须手动重发；**无固定冷却窗口**（10-02 追查定案：cmdc 转发的响应头里没有任何 x-ratelimit/retry-after 字段可读，社区一手观察=免费模型共享公共池、瞬时节流秒~分钟级自愈、非按日/小时窗口重置，与当日实测「几分钟后两次探针全过」吻合）——**切节点无冷却惩罚，随时可切回**，撞上限额只是赶上了热点 IP。处置=等一两分钟手动重发，频发才切节点换 IP 桶。⑦**「Tool result is missing for tool call call_XXX」（10-06 首见，provider=zhen-hajimi-gemini/8787 Gemini 线，TraceID c8e0f0e9）＝会话历史损坏**：anthropic-messages 协议要求每个 assistant tool_use 后紧跟同 id 的 tool_result，历史里缺配对（call_ 前缀=OpenAI 风格 id）即整轮拒收，`retryable=false`——重发同历史永远失败，非瞬时病。成因=上一轮流式被掐（10-03 muse EOF 全谱同源）/手动停止/压缩吃块，留下断头工具调用。处置=**重启 ZCode 客户端即愈（10-06 用户实测推翻「历史不可逆」初判）**——断头块在 ZCode 的**内存态在途轮次**里，盘上会话转录无损；「重试」按钮重放的正是内存里的坏轮次所以永远炸，重启丢弃之并从盘上重载干净历史。rewind/新开对话仍是备选。成因=上一轮流式被掐（10-03 muse EOF 全谱同源）/手动停止/压缩吃块，留下断头工具调用。**禁止反复点重试**。预防：长工具调用轮被掐断后不要原地续发，重启或回退都行。分型已存 OpenViking。

**Meta 封区错误在新加坡呈间歇态（10-02 用户实测报错后复测定案）**：用户在 ZCode2（provider=new-provider-2/ccgo）报 muse-spark-1.3-contributor 吃 Meta Geographic Use Policy 500（`retryable=true`，TraceID 与 503 案相同=面板把多次错误归同一 trace，勿当独立证据）。立即复核：**出口 IP 未漂**（仍 155.254.108.8 Akari 新加坡）、muse-1.3 当场探针即通（content 'OK'）——结论：**SG 下该错非持续性，是商家上游「Console」后端池轮询混入了被封地区的坏节点**，轮到它就蹦一次。处置：偶发=无视（retryable=true ZCode 自动重试，手动重发也过）；频发=拿 TraceID+报错原文找商家（QQ 群 120363664）把 Console 池里的坏地区节点踢掉。排障口诀：见 Meta 封区先查出口 IP 漂没漂，IP 没漂就是商家池的事，别乱切节点。

**🔴 muse 付费线流中断 EOF 全谱定案（2026-10-03 凌晨，ZCode 主实例 db+8787 面板日志环双源实锤）**：用户问「muse 什么原因」。全天 muse-spark-1.3-contributor@new-provider-2 共 339 呼（10:38–00:13）：subagent 254 完成/34 错/1 取消，main_turn 47 完成/3 错。**网关侧真相**（面板 `/api/status` 的 logs 300 行内存环；`cmdc-pak.log` 文件自 09-24 停写不落盘）：muse 付费流**天生「无文本+长静默」**——`STREAM DONE mode=chat ... text=0 tools=1 maxread=259.99s reads=37 finished=true`，单轮 190~420s、流中静默 4~5 分钟是常态，只吐工具调用。五种死法：**A 网关 5 分钟空闲掐断**（00:09:09 实锤 `maxread=300.01s err=upstream idle > 5m0s`；网关 `upstream idle timeout = 5m0s`，环境变量 `CMDC_PAK_IDLE_TIMEOUT` 可调）——ZCode 侧 ≥300s 的 EOF 全属此型（00:02:08 报错原文就是 `upstream idle > 5m0s` 透传，422s）。**B 上游途中掐断（主流 26 条，148–290s，21:22–23:45 密集）**：短于 5 分钟静默线，网关证据已滚出环窗；已排除 ZCode 超时（00:09 案证明 ZCode 容忍 300s 静默不 abort）、封区（新加坡节点 21 点后无封区错）、总时长上限（406.98s 成功在先）→ 与已知「Console 池混坏节点+间歇态」同源，判定商家上游/链路掐断。**C ZCode 侧自己 abort**（00:13:50 `context canceled`+`STREAM CANCEL client disconnected`，db 唯一 cancelled）。**D 封区 3 条**（11:16/14:16/14:21，19:26 网关重启换新加坡后绝迹）。**E 偶发**：15:00:22 TCP RST（172.67.167.23:443 Cloudflare wsarecv forcibly closed）+ 10:38:27 首呼 0s「Provider rejected」。**判据**：失败全在 subagent（agent 长轮工具调用）；但成功 subagent 也有 412.8s/195.3s 长轮+172K 大上下文——**时长/上下文大小都不是判据，「流中最大静默 maxread」才是**；main_turn 3 错=2 封区+1 首呼。附带：同一网关 gemini 线 00:04:22 也 `GEMINI FAIL ... unexpected EOF`（8787→上游这跳本身不稳，非 muse 独有）；23:55–23:57 `/v1/responses` 502×5=opencode-free 中继老毛病。**处置**：①muse 不适合当 agent 主力底模（中断率 ~12%、一轮几分钟）→ ZCode 子代理/主对话换 gemini 线或 ccgo deepseek 线（零成本立刻可做）；②要救 A 型就调 `CMDC_PAK_IDLE_TIMEOUT`（如 900s）重启网关=动服务启动方式，走高危三件套等用户拍板；③网关日志不落盘，要抓 B 型现行只能持续轮询 `/api/status` 环快照落盘（脚本未写，等用户发话）。

**🔴 muse free 版协议红线（2026-10-03 定案，Qoder 接入案）**：`muse-spark-1.3-contributor-free` 只支持 **Responses 或 /v1/messages**（商家面板明示），打 `/v1/chat/completions` 必 502「OpenCode Free 上游异常：OpenCode 返回 HTTP 500: Internal server error」——客户端只见笼统的「服务内部处理错误」，重试无效（确定性路由错，勿当瞬时病）。⚠️/v1/messages（anthropic 裸根）纯文本探针 200 但**带工具负载即废**（模型把工具调用当纯文本吐、JSON 引号不转义）——文本探针通过≠工具可用，验协议必须带 tools 负载。**Qoder 正解=protocol `openai-responses` + baseUrl `http://127.0.0.1:8787/v1` + authType bearer**（与 ZCode2 opencode-free-muse 提供方同款；探针实锤该线带工具返回标准 reasoning/message/function_call 三段结构）。Qoder settings.json 的 protocol 枚举=`["openai","openai-responses"]`（asar 实锤，官方文档只说「Responses API」不给字段值）。改 Qoder settings.json 必须 Qoder 全退（脚本闸 _qoder_muse_fix.py 内置检测；🔴tasklist 输出是 GBK，subprocess text=True 必炸，须 decode('gbk')）。备份 settings.json.bak-premuse-20261003-{110659,111308,112012}，终态哈希 972761fbbd47a69c（thinking 声明已恢复：enabled+low/medium/high/xhigh，responses 线带工具探针实锤 reasoning 条目正常），用户实测正常。

**OpenCode Free 六模型舰队核验（2026-10-03，Qoder 侧配置对照面板+活体抽测）**：Qoder「OpenCode Free」提供方（openai+/v1=chat 线）6 模型 ctx/max 与商家面板逐字节一致（space-bunny 1M/8192、mimo-flash-free 200k/32000、longcat 1M/131072、ling-3.0-fin 256k/32768、nemotron-ultra 1M/128000、nemotron-3.5-lightning 256k/262144）；「默认开启（不可调）」类模型 thinking 声明 modes:[]+supportsEffort:false（不发 reasoning 参数）=功能正确。抽测：space-bunny ✓ 200 秒回；nemotron-3.5-lightning ✓ 200 但输出乱码英文（模型自身质量，定位极速单任务速修，别当聊天用）；**ling-3.0-flash-fin-free ⛔ 502「Endpoint is unavailable」上游端点仍挂（10-02 定案延续），配置无错、客户端治不了，须商家修**。🔴交叉发现：**ZCode2 的 mimo-v2.6-flash-free 参数抄错行**（填 256k/262144，面板规格 200k/32000），ZCode2 侧待顺手修正。

**✅ 10-03 更新回合（新现役=MD5 `5a112d74263e9c9c8139baca1879fc5a`，16.8M；回滚 `.prev`=09-27 版 ea458450 16.2M）**：用户报「下载总被拦截」帮装。全流程照 §更新套路走通并有三条新证：①**Defender 延迟吞吃再实锤**——curl 下到 F:\AI\downloads（无排除）后 ls 可见，几秒后 md5sum 即 No such file；正门=直接下到排除路径 D:\cmdc-pak；②**桌面 exe 副本这次保不住**——30 秒生存验证被吞（09-27 时桌面副本曾存活，行为已变差），**桌面从此只放快捷方式**「cmdc-pak 网关.lnk」（已重建并回读验证 TargetPath=D:\cmdc-pak\cmdc-pak.exe），exe 权威副本只在 D 盘；用户要桌面 exe 需给 Desktop 加 Defender 排除（安全降级，未做不推荐）；③~~日志位置悬案告破~~**10-04 推翻**：`Desktop\cmdc\cmdc-pak.log` 是用户 10-03 收进来的 09-24 时代旧日志，新版无文件日志——详见下方「10-04 更正」段。**→ 10-04 更正：日志悬案并未告破**。`Desktop\cmdc\cmdc-pak.log` 里其实是 **09-24 时代的历史日志**（尾行停在 09-24 10:21）——10-03 15:22 用户只是把旧日志和旧快捷方式一起挪进了该文件夹；10-04 全面搜索确认**新版根本不写文件日志**（D:\cmdc-pak 与 AppData\Roaming\cmdc-pak 均无 10-04 后新 log）。判病正门只剩面板 `http://127.0.0.1:8787/api/status` 的 300 行内存环（logs 数组），进程重启即清零——想留证据必须提前轮询落盘（脚本仍未写）。上一段「③日志位置悬案告破」作废。

**→ 10-03 深夜第二回合（例行更新，「例行公事吧」+三件套获「执行」）**：**现役=MD5 `c9e5fddb288618d5018fb29c19cd2a9d`（17.0M）**，回滚链两代：`.prev2`=5a112d74（同夜早版 16.8M）、`.prev`=ea458450（09-27 版 16.2M）。双份下载校验沿用（第二份 verify 件比对一致后删）。验收=面板 200+付费白名单 9 模型原样+space-bunny-free 端到端 'OK'，付费周额度零消耗。新经验：**同晚已批过的 Stop-Process 命令原文重试不再吃 GateGuard 首拒**（哈希授权留痕当晚有效）；输出环境噪音大（rtk banner+/etc/post-install 假 rm 报错+表格线），关键结论必须二次干净复核再下结论（本次复核证换位早已成功，虚惊）。

**🆕 10-04 第三回合并白名单变天（现役=MD5 `50cc3096a1ace72a9e637cb5ca13ea61` 17.8M，双份校验一致；回滚链三代：`.prev3`=c9e5fddb（10-03 晚）、`.prev2`=5a112d74、`.prev`=ea458450（09-27））**：验收三连全绿（面板 200、space-bunny-free 出字 'OK'）。**付费白名单由 9→8**：🔴下架 **mimo-v2.5、mimo-v2.5-pro**，🆕新增 **deepseek-v4.1-flash-fast**（规格未探明，需看面板或问商家）。现役 8 模型=deepseek-v4-flash / deepseek-v4.1-flash / deepseek-v4.1-flash-fast / mimo-v2.6-flash / mimo-v2.6-pro / muse-spark-1.2/1.3-contributor / qwen3.8-flash。**影响面**：ZCode2 ccgo 供应商、Cherry「Command Code Go」组、主 ZCode new-provider-2 等所有登记了 mimo-v2.5/v2.5-pro 的客户端条目现在选这两个名必 400「未知模型」——待用户发话后清理（ZCode2 改动需其全退+三件套；Cherry 需退应用改 sqlite）。更新套路第三次跑通，已完全定型。

**10-04 晚收尾（用户拍板）**：①mimo-v2.5* 死条目用户自己清；②**三份历史版本全删**（`.prev` ea458450 / `.prev2` 5a112d74 / `.prev3` c9e5fddb，~51MB）——本机**已无任何旧版备份**，官网直链永远只发最新=**无法降级**；**新默认 SOP：以后每轮更新验收通过后直接删除上一版、不再滚雪球**（用户原话「你把旧版本删除了就行」）；③验收后网关进程**无声消失**（Windows 应用日志零条 cmdc 崩溃事件，托盘退出与静默 crash 无法区分），重拉后 PID 25860 面板 200+白名单 8 模型健在；若新版再无故暴毙，优先怀疑构建自身，取证只能靠 `/api/status` 内存环提前轮询；④桌面快捷方式重建（原件被用户 10-03 挪进 `Desktop\cmdc\`，现桌面新 lnk 指向 D 盘现役、回读验证通过，文件夹里那份历史遗留未动）。

**✅ 10-05 第四更（例行，现役=MD5 `cf5171817f695d418c492b3cdb403ee2`，18.3MB 双份校验一致）**：用户「又更新了」+「执行 我已经退出 把旧版本都删了」。要点：①**10-04「无声暴死」疑云消解**——用户承认更新前自己托盘退出，Stop-Process 时报进程已不在，跳过杀步骤直接拉起（PID 32424）；②白名单与上一版**零漂移**（仍 8 模型：deepseek-v4-flash/v4.1-flash/v4.1-flash-fast、mimo-v2.6-flash/pro、muse-spark-1.2/1.3-contributor、qwen3.8-flash）；③验收三连全绿（面板 200、space-bunny-free 'OK'、删 `.prev`=50cc3096 后进程健在 8787 监听），**「验收后即删上一版」SOP 首轮执行完毕**，D:\cmdc-pak 常态化单文件。⑤**桌面 lnk 反复消失观察项**：10-04 晚重建回读验证过，10-05 例行更新后再查又 MISSING（`Desktop\cmdc\` 里躺着用户 10-03 挪入的同名 587B lnk 未动，桌面这份却没了——去向不明：可能被用户习惯性挪进文件夹或被 Explorer 抽走，非 Defender 典型行为）；已再次重建并加 IconLocation=exe,0 修图标，若第三度消失要问用户是不是手动收的。✅ **10-05 结案+新位置定规**：用户证实就是他手动收纳的——**快捷方式常驻 `Desktop\cmdc\cmdc-pak 网关.lnk`，桌面不放**；已把新 lnk（带图标）移入该文件夹顶替旧份（旧份 target 同为 D:\cmdc-pak\cmdc-pak.exe，替换无损），桌面清零残留。以后例行更新勿再往桌面建 lnk。

**✅ 10-06 第五更收官（例行，现役=MD5 `319df350101187111331db2a819c59df`，18,077,184B 双份校验一致）**：用户「首先更新了 你例行公事」+三件套获「执行」。旧进程 PID 15072 终止→新版拉起 PID 11540；验收=面板 200 + **白名单 8 模型零漂移** + space-bunny-free 端到端 'OK'；`.prev`（cf517181）验收后即删，D:\cmdc-pak 单文件态。**同轮解决 ZCode2 muse-free 401**（报错摘要「Provider authentication failed/Invalid API key」，provider=38c1d501，model=muse-spark-1.3-contributor-free）：该提供商系 9 月中旬旧配置（直连 `https://opencode.ai/zen/v1` + 88 位旧 Token 已过期，实测官网原样回 401 AuthError），10-05 给 ZCode2 同步 susu/kimik3 配置时被主实例版本覆盖重新引入；修复=`F:\AI\ZCode2\data\.zcode\v2\provider_config.json` 中 38c1d501 的 baseUrl→`http://127.0.0.1:8787/v1`、apiKey→`local-proxy`（openai-responses 不动），备份 `provider_config.json.bak-muse401-20261006-202556`，回读+端到端 status=completed TEXT 'OK'（115 tok）全绿。**ZCode2 需重启生效**。**遗账三条**：①主 ZCode（.zcode/cli 与 .zcode/v2 两处）同款 38c1d501 炸弹**未拆**（用户只点名修 ZCode2；主实例=当前会话宿主不能自杀重启）；②10-02 配的 ZCode2 OpenCode Free 六 chat 模型组与 opencode-free-muse 组已被 10-05 配置同步**覆盖丢失**（5 个 free chat 模型在 ZCode2 无条目），待用户发话恢复；③muse-free 502 unexpected EOF 呈间歇（本轮早前抓到、修复验证轮全绿）。

**✅ 10-08 第六更（v0.9.2，现役 MD5 `ecad8d60f19f814c3a1eecc0cf06ec7d`，14.5MB，双份校验一致）+ 主 ZCode 拆弹完成**：①cmdc 例行：319df350（v0.9.1）→v0.9.2（PID 24756），白名单 8 模型零漂移、面板 200、space-bunny 'OK'，`.prev` 按 SOP 已删、D 盘单文件。**v0.9.2 changelog**（官网 bundle `index-7gaURQuP.js` 提取，版本时间线 0.9.0=10-05、0.9.1=10-06、0.9.2=10-07）：客户端核心安全加固；安装包体积缩小（实测 18.1→14.5MB≈-20%，官方说约17%）；**【OpenCode Free 线】修复 Muse Spark 输出预算被限制的问题——按面板填写值原样生效，长文生成不再被提前截断**（正中此前 muse 长输出腰斩痛点，待实测复验）。②主 ZCode 38c1d501 拆弹（用户「我要在这里用 这里才是主线」+三件套式授权）：四文件 cli/v2 provider_config + cli/v2 config.json 全改指 `http://127.0.0.1:8787/v1`/`local-proxy`，终扫零残留；备份 `.bak-muse401main-20261008-014650` 等 + state-backups 小时快照兜底；**需重启主 ZCode 生效（会话宿主不能自杀）**。⚠️字段坑：config.json 的 provider 条目字段名是 `baseURL`（大写 URL）且 apiKey 在 `options` 下，与 provider_config.json 的 `baseUrl`/`access.apiKey` 两种拼写——拆弹必须双拼写 walk。③前轮 ZCode2 二次 401 复发验尸=用户未重启+主实例同弹所炸，现已一并拆除。④ZCode2 的 OpenCode Free 六 chat 组仍待恢复（用户未发话）。**→ 10-08 晚处置（用户裁决：「暂时不补，你将它的内容吸收过来，今后我主要用你」）**：已从 ZCode2 的 10-02 备份 `provider_config.json.bak-20261002-112214` 把 opencode-free 六 chat 模型组完整吸收进主实例四文件（cli/v2 × provider_config/config，双源一致，备份 `.bak-absorbfree-*`，面板规格 ctx/output 照 10-03 核验值写入 config.json 镜像），网关探活六模型全知；**重启主 ZCode 生效**。ZCode2 侧不再恢复。**ZCode2 记忆体系盘点**：其家目录 `F:\AI\ZCode2\data\.zcode\` 从未建立 memories 目录（自动记忆=零）、无自有 AGENTS.md、无会话 db——ZCode2 实为纯配置分身；OpenViking 图书馆（1933）与 memory-vault 跨实例共享，用户主力迁回主实例=零损失。

**✅ 10-08 晚间第七更（v0.9.3，现役 MD5 `be0c9f4f6f270e0bc206208a07926053` 14.7MB 双份校验一致；用户免确认令「不要再让我确认了 直接执行」——例行更新自此全自动：下载→双验→换位→杀重启→验收→删上版→存档，一条消息跑完不再打断）**：PID 21576，VERSION 面板自报 0.9.3。官方 changelog 三条与 0.9.2 逐字相同（商家模板未更新，实际增量=白名单换血）。**🔴付费白名单二次变天**：`mimo-v2.6-flash/mimo-v2.6-pro` 下架、**`mimo-v2.5/mimo-v2.5-pro` 回归**——现 8 模型=deepseek-v4-flash/v4.1-flash/v4.1-flash-fast、mimo-v2.5/v2.5-pro、muse-spark-1.2/1.3-contributor、qwen3.8-flash。**连锁影响：用户前几天按指示清掉的 mimo-v2.5* 死条目现在反而是活的了，各客户端登记的 mimo-v2.6* 条目变成新的死条目**（ZCode2 ccgo 组里的 v2.6 两条等）。验收：面板 200+space-bunny-free 'OK'，`.prev`（ecad8d60）按 SOP 已删、D 盘单文件。免确认令已立，后续「更新了/例行公事」直接全程执行。**⑨报错分型补录（10-08 晚，TraceID 22c41c57）**：`OpenCode Free 上游异常：Post "https://opencode.ai/zen/v1/responses": EOF`（provider=38c1d501，ZCode 标 retryable=false）=**商家中继→OpenCode 官方那跳被瞬掐**，本地链路无罪（能出这条错说明 ZCode→8787 已通）；处置=手动重发（两连探针秒愈实测），频发拿 TraceID 找商家群 120363664；⚠️观察项：v0.9.3 当晚开始撞 EOF，若持续变多需怀疑新版上游处理（旧版已删无法回滚，只能对质商家）。**⑨官网追查补充（用户令「去官网上看看有没有我这种情况」，10-08 晚）**：结论=**官网对 EOF 零解决办法**——①v0.9.3 在官网 changelog 数组（全量 36 版）里**根本没有条目**，面板显示的「更新内容」是 0.9.2 复用文案，商家发版不写日志；②商家对这条线的稳定性已**空头承诺三轮**：0.8.6 原话「深度增强 Muse Spark 1.3 连接稳定性，解决模型复杂思考时客户端容易意外超时的难题」+「思考保活」「断点续传：万一中断，自动带着已完成的思考继续」「网络拥堵自动柔性排队恢复」、0.8.8「连接稳定性大幅提升」、0.8.10「大幅提升长代码生成的稳定性和完整度」——10-08 依旧 EOF，对质现成把柄=「0.8.6 宣称攻克超时断连，10 月 8 日仍 EOF」；③官网体系内还能用的只有两件：面板 `http://127.0.0.1:8787` 的 **OpenCode Free 线逐模型连通自检**（0.8.9 加，红=上游病/绿=偶发抖动直接重发）+ 报错自带「切换出口线路」（对 RateLimit 有用、对纯 EOF 无用）；④exe HEAD last-modified=13:23(+8) 与 0.9.3 发布吻合，官网无更新版本可等。

**🔧 10-08 muse-free 主实例截断案（用户：「怎么总是截断，我之前在 ZCode2 上是正常的」）**：验尸定案=**客户端配置差异，非网关病**——主实例 38c1d501 的 providerModelRules 只有 `contextWindow:1000000`（9 月老条目），缺 ZCode2 正常条目的 `optionSpecs.maxOutputTokens.max=131072`、`reasoningLevel(low/medium/high/xhigh)`、`inputFormat.supportsImage`、`enabled`，ZCode 拿不到输出上限规格→按小默认发→长文截断；config.json 镜像 limit.output 还是 128000（非面板值）。修复=四文件（cli/v2 provider_config+config）参数照抄 ZCode2 工作值（131072/四档思考/image），备份 `.bak-musetrunc-20261008-034919`。**网关侧实弹证明 v0.9.2 不截**：max_output_tokens=131072 请求「1 到 3000 逐行列数」→3000 行完整、output_tokens=8945（越 8192 旧线）、completed 无 incomplete。**生效需重开会话/重启主 ZCode**（配置=会话启动快照）。教训：**吸收跨实例配置时必须连 providerModelRules 的 optionSpecs 全量搬，只搬 provider 条目会截断**；用户给的证据会话 sess_f7d68253 实为 UMH 项目会话（与截断无关，编号可能记岔，配置对照已足够定案）。

**🔴 10-08 午后二次开庭，optionSpecs 根因被数据推翻（正确定案）**：用户重启后仍报截断，证据会话=sess_7306e644（UMH 总控会话，会话库尾号 74585a 实锤在跑 muse-free）。model_usage 最近 12 轮铁证：**finish_reason 全部 stop/tool-calls、零个 length**（预算掐断会报 length）；**每轮 in=30.6万~31.4万 token、out 仅 26~423、reasoning≈0**、24~33s、网关全 200。判决=**上下文过载摆烂，非输出截断**：31 万 token 巨型会话喂轻量 muse free，模型主动草草收尾。上午的 optionSpecs 修复=配置卫生（保留有效），但非用户所见截断根因，**改口记录在案**。ZCode2「正常」=当时是新短会话。正确用法：muse free 只用于新开短会话干轻活；30 万级上下文的会话（如 UMH 总控）改走 deepseek-v4.1-flash（1M 正主）或哈基米 gemini 线。网关 3000 行/8945tok 直测与 model_usage 数据互证完毕。**GUI 终验（10-08 用户亲手，本案终结）**：新开短会话选 muse-free 发「1500 字 TCP/IP 史」指令 → 七段齐、约 1900 字、末句完整句号收尾、一次吐完零截断——两路证据（网关直测+GUI 实弹）咬合，定案= muse free 无毛病，截断仅发生在大上下文旧会话（轻量模型过载主动收笔）。用法铁律：muse free 只配短会话轻活，几小时老会话走 deepseek/哈基米。

**⚠️ muse-free 截断案最终章（10-08 傍晚，sess_7306e644 UMH 总控会话实锤）**：用户贴乱码实录（半句断、整句复读、"我已经开始一项工作"刷屏）。model_usage 铁证：284 轮全在 muse-spark-1.3-contributor-free、平均输入 21.3 万 token、案发时 **36.8 万且仍在涨**；每轮 completed、fin=stop|tool-calls、**reasoning≈0**、out 141~417 碎片——线路与网关零故障，是轻量模型淹死在巨型上下文后**停止思考、条件反射吐碎片**。截断家族三症状定案：短尾→碎片→**语无伦次+复读**，同根同源。**铁律升级：muse free 禁止进任何 agent 循环型/长程会话，只配短对话快问快答；总控级任务=deepseek-v4.1-flash 或 gemini 线。该失控会话已用 GUI 误点用户真实 ZCode 设置界面两次（其日志自白），叫停+新会话接管是唯一正解。**

**🔧 10-08 截断案再修正（对照 ZCode2 正常的追问后）**：三探针隔离定性——英文内联 ✅895 tok 正常、中文 UTF-8 文件 ✅1965 tok 正常、中文内联 ❌四轮全"乱码"（=Git Bash 参数编码锅，见 [[windows-shell-gotchas-gitbash]]，该误判已二次发生）。**UMH 会话碎片轮的最终归因=OpenCode 免费池商家上游当日抖动**（同日 2×EOF、1×502、同参数好轮/碎片轮交替；284 轮平均值 out=1215/reason=919 证明该会话历史健康、非单纯体量问题——对照 75.7 万 tok 会话仍正常出长文）。ZCode2"正常"=轮次少全抽好节点，两实例配置均无罪。铁律保留：muse free 不进 agent 长会话（它经不起上游抖动放大）；排障探针中文必须走文件。

**🌆 10-08 节点榜扩军：洛杉矶 Akari 并列冠军（155.117.198.114，hosting=False 住宅）**：用户从台北（155.254.124.35，付费 muse=Meta 封区死档）切到 LA 后定点 4/4 全绿——付费 muse 'OK'/stop（**美区 Meta 放行**）、gemini-high end_turn、muse-free completed、space-bunny OK、commandcode TLS 0.80s。与 SG(155.254.108.x) 同门（Akari 系），对 Meta+Google 双线天然友好，当日"ccgo 抖"元凶即台北节点的 muse 封区。新榜：LA≈SG 双冠 > 台北（muse 系死）> 香港。**纪律照旧：选定钉死勿漂移、长连接中禁切。**

**✅ 10-08 深夜第八更（v0.9.4，现役 MD5 `dca0d38fd42aceaf32bea8eafa83025c` 14.0MB / 14,696,960B，双份校验一致；用户免确认令「老样子 直接执行 不要让我确认了 还有就是软件记得放到特定文件夹」）**：
- **执行路径**：按照 SOP 走代理 10808 下载双份至排除目录 `D:\cmdc-pak`，比对 MD5 一致后平滑切换。旧版备份为 `.prev`，终止旧进程 PID 21576 并拉起新版本（新进程 PID 2452）。
- **版本与接口**：面板自报 `v0.9.4`，`/api/status` 全绿（port 8787，offline=false，OpenCode Free 已授权）。
- **白名单再次变天**：`mimo-v2.5 / mimo-v2.5-pro` 再次下架，换回 `mimo-v2.6-flash / mimo-v2.6-pro`！现 8 模型：`deepseek-v4-flash / deepseek-v4.1-flash / deepseek-v4.1-flash-fast / mimo-v2.6-flash / mimo-v2.6-pro / muse-spark-1.2-contributor / muse-spark-1.3-contributor / qwen3.8-flash`。
- **验收验证**：面板 200 正常；`space-bunny-free` 1.60s 秒回 HTTP 200；`fledge-alpha-free` 与 `mimo-v2.6-flash` 均 HTTP 200 秒回；`muse-spark-1.3-contributor-free` 走 `/v1/responses` HTTP 200 正常出字。
- **SOP 收尾**：`.prev` 旧版已删除，`D:\cmdc-pak` 保持单文件态；快捷方式确认常驻 `Desktop\cmdc\cmdc-pak 网关.lnk` 指向 `D:\cmdc-pak\cmdc-pak.exe`。

**✅ 10-09 第十更（v0.9.8，现役 MD5 `ed1725d4887f9ec921ed94c556a0f914`，15,335,424B≈14.6MB，双份校验一致；用户口令「又更新了 例行公事」免确认直执）**：
- **一天三连跳**：v0.9.5（12:00 UTC）→ v0.9.8（17:18 UTC 官网再推，下载时又涨到 15.3MB=作者盘中重推），面板自报 0.9.8，PID 12760。
- **白名单 8→9**：🆕新增 **`zai-org/GLM-5.3`**（实测 pong 正常）；其余 8 模型不变。
- **Muse 目录扩容**：`/muse-code/models` 现返回 **38 个模型**（v0.9.5 时代约 13 个）。
- **验收全绿**：space-bunny-free 'OK'、muse-free /v1/responses completed、opencode/gemini 双 key ok。
- **🔴 用户铁律落地：每次更新必须同步复制 exe 到 `C:\Users\Janson\Desktop\cmdc`**！此前该文件夹未入 Defender 白名单，未签名 exe 秒被吞（10-09 两次实锤，威胁日志 file:_...Desktop\cmdc\cmdc-pak.exe）。本次已用 `Start-Process powershell -Verb RunAs` UAC 提权执行 `Add-MpPreference -ExclusionPath 'C:\Users\Janson\Desktop\cmdc'` 加白成功，复制后 15 秒存活、MD5 与 D 盘一致。**例行更新 SOP 自此追加第 6 步：复制到 Desktop\cmdc 并 15s 存活校验**。

**✅ 10-10 第十一更（v0.9.10，现役 MD5 `2bdfc02ba0e05922bb0781c58d3a0d3b`，15,316,480B，双份校验一致；用户口令「又更新了 你懂我的意思吧」免确认直执）**：
- 官网 last-modified 10-10 11:26（北京时间），作者跳过 0.9.9 直发 0.9.10；PID 3316 监听 8787，opencode/gemini 双 key ok、cc idle。
- **白名单 9 模型零漂移**（含 zai-org/GLM-5.3）；Muse 目录 38→37（商家侧微调）。
- 验收全绿：space-bunny 'OK'、GLM-5.3 pong、muse-code/models 200。
- **六步 SOP 首次完整跑通含桌面落盘**：复制到 `Desktop\cmdc\cmdc-pak.exe` 15s 存活、MD5 与 D 盘一致（Defender 白名单上晚已加，本次零拦截）；`.prev` 已删，D 盘单文件态。

**✅ 10-12 第十二更（v0.9.11，现役 MD5 `066d8dd8479efb6b862221f99fba5b54`，15,606,784B 双份校验一致；官网 last-modified 10-12 02:10 北京时间；用户口令「cmdc又更新了 例行公事」）**：
- 换进程 PID 20368（此前 3208 曾无故重启一次，uptime 仅 5 分钟即被我们发现，死因不明继续观察项）；GateGuard 对 Stop-Process 新会话首拒 → 三件套交付后原样重试放行（rm 清理未拦）。
- **验收**：面板 200 offline=false 自报 0.9.11；**付费白名单 9 模型零漂移**（deepseek-v4-flash/v4.1-flash/v4.1-flash-fast、mimo-v2.6-flash/pro、muse-spark-1.2/1.3-contributor、qwen3.8-flash+GLM-5.3）；/v1/models 与 /muse-code/models 均 37 项（后者返回结构=`{data:[],object:"list"}`，**别拿 'models' 键解析**，10-12 栽过一次）；space-bunny-free 'OK'。
- **🟡 唯一黄灯**：muse-free 走 /v1/responses 两连 502「OpenCode Free 上游异常：unexpected EOF」——非升级引入，系 10-12 凌晨整本工单把出口 OpenCode 免费桶打爆后的冷却延伸（同线 space-bunny 秒绿=中继活着，只 muse responses lane 在罚）；观察至次日上午，仍死拿 TraceID 找商家。
- Desktop\cmdc 落盘 15s 存活、MD5 一致零拦截；.prev（2bdfc02b）与 verify 件已删，D 盘单文件态。
- **v0.9.11 changelog**（官网 bundle `index-DY_u3Rql.js` 实抓）：Gemini 线=改善 429 报错（上游网络抖动不再误报"额度用完"）+优化上报体验问题；CC 线=安全优化；OpenCode Free 线=**用量统计上线**（面板可看 free 线消耗——正合 10-12 烧出口事件的复盘工具）。
- **10-12 上午黄灯闭合**：`muse exec "1+1"` 实弹通过（`1+1等于2。`）——OpenCode 出口冷却自行解除，无需换节点。判据新增：**exec（meta 协议 /muse-code 路由）与 /v1/responses 探针是两个不同入口，生死可不同步**——验收当时 responses 探针仍 502 EOF，次晨 exec 已通。

**🆕 10-10 新模型配置回合（用户「帮我配置它的新模型」，三件套获「执行」）**：
- **今日 changelog 亮点**：0.9.7 连接韧性（授权服务器秒连）、0.9.8 Gemini 线内核升级 Claude 体验大增、0.9.9 Gemini 多账号轮换更聪明、0.9.10 修 Muse 新用户启动；0.9.6 曾上 GLM-5.3 与 step-5-preview-free。
- **网关 37 模型全目录实抓**；新模型实测全 pong：`zai-org/GLM-5.3`（1M/131K，chat）、`step-5-preview-free`（1M/65536，chat）、`claude-fable-5-1`/`claude-fable-5`（1M/64K，/v1/messages）。
- **🔴 `exo-free` 上游 410 ModelDeprecated 永久弃用**（≠临时 502），ZCode 内死条目按用户惯例未删、等用户口令。
- **已写入 ZCode 四文件**（备份 `.bak-20261010-201528`）：自行车(7d703230)+GLM-5.3；opencode-free+step-5-preview-free；真哈基米(new-provider-2 双文件)+fable-5-1/fable-5；zhen-hajimi-gemini(v2)+同两款。**需重启 ZCode 生效**。




**🔴 10-08 晚 UMH 接手会话 sess_d2bb1ef 86k context 假截断实录（用户「怪事 又给我截断了 但是我测试是能通的」）**：
- **现场与证据（db.sqlite 铁证）**：会话在 19:47:29 切为 muse-free，19:50:54 案发请求 `in=86,670`、`out=35`（耗时2.1s）、`reasoning=0`、`fin=stop`、`tool_call_count=0`。
- **输出正文**：仅为一句口头承诺 *“终验数据齐了——更新操作包（刷新预置状态 + R7 结论），然后一次性列出你需手动做的最小动作。”*，**未发出任何工具调用便主动早停**。
- **衰减轨迹**：输出 Token 发生雪崩式萎缩（2345 → 3322 → 1102 → 112 → 245 → 35 stop）；同款现象在 36.8 万 Token 老会话（sess_7306e644）重现（out=42 stop）。
- **「单测能通 vs 会话截断」根因解密**：单测仅几百 Token，轻量模型算力集中、秒回出字；但会话历史膨胀至 8.6 万以上时，轻量模型规划能力被冲垮，思考归零，产生“空头口头承诺+提前 stop 罢工”症状。在前端看起来表现为“截断”。
- **处置方案**：会话内切换至 `deepseek-v4.1-flash`（100 万窗口）并发送“继续”即可平滑接盘。

**✅ 10-09 凌晨第九更（v0.9.5，现役 MD5 `9a5e7b33726fe87a2b1e408609672ac9` 14.2MB / 14,903,808B，双份校验一致；作者 10-09 刚刚推送官网）**：
- **执行路径与用户铁律**：用户明确要求更新后必须放到特定文件夹 **`C:\Users\Janson\Desktop\cmdc`**！
  - *杀软防御现实*：当前 Windows Defender 排除项仅配了 `D:\cmdc-pak`，未配 `Desktop\cmdc`。刚才实测复制 `cmdc-pak.exe` 到 `Desktop\cmdc` 瞬间即被 Defender 实时防护触发隔离（威胁记录已证实）。
  - *双保落地策略*：`D:\cmdc-pak\cmdc-pak.exe` 保持白名单免杀运行；同时在 `Desktop\cmdc` 维护好双击即可直启最新版的 `cmdc-pak 网关.lnk`。建议用户以管理员终端执行 `Add-MpPreference -ExclusionPath 'C:\Users\Janson\Desktop\cmdc'`，将桌面文件夹也列入排除，彻底允许 exe 实体直接常驻。

- **重大修复：Meta 官方 Muse Code 路由全线打通**：
  - 作者在 v0.9.5 中正式补齐了此前缺失的 **`GET /muse-code/models`** 专有握手路由（实测 HTTP 200 返回包含 deepseek, muse-spark 等全量模型列表）。
  - **实弹终验全绿**：执行 `muse exec "用一句话回答：1+1等于几？"`，成功加载 25 个技能并秒回 **`1+1 等于 2。`**！Meta 官方终端 Coding Agent 正式在 Windows 上彻底跑通。
- **Claude 4.6 与 Gemini 3.1 Pro 协议定案**：
  - Gemini 订阅线必须走 Anthropic Messages 协议（`/v1/messages`）。
  - Claude 4.6 (`claude-sonnet-4-6`) 提供商已修正为 `kind: "anthropic"` 直连 8787。
  - **10-09 追加 `gemini-3.1-pro-high`**：已成功在 `cli` 与 `v2` 两份 `provider_config.json` 的「真 哈基米」（`new-provider-2`）中追加 `gemini-3.1-pro-high`，直连 8787 Anthropic 端点，实测 HTTP 200 全通，备份留存 `.bak-20261009-225041`。



**🔴 10-08 深夜 cmdc 8787 Claude 4.6「Provider rejected the model request / hydrate-trace」报错定案**：
- **症状**：用户在 ZCode 恢复/打开会话时弹窗报错 `Provider rejected the model request. TraceID: hydrate-trace`（模型为真哈基米中的 Claude 4.6 / `claude-sonnet-4-6`）。
- **实锤根因（HTTP 400 拒单）**：
  - ZCode 前端水合（hydrate）恢复会话时向 8787 发送 Chat Completions 协议（`/v1/chat/completions`）。
  - **cmdc-pak 8787 当场返回 400 拒单**：`"/v1/chat/completions 不服务 Gemini 模型；claude-sonnet-4-6 属于 Gemini 订阅，走的是 Anthropic 协议。请把 API 格式改为 Anthropic（Messages），端点换成 /v1/messages，Base URL 其余部分不变"`。
  - ZCode 渲染层捕获 400 抛出 `Provider rejected the model request`。
- **验证与修复**：
  - 改用 Anthropic 协议向 `http://127.0.0.1:8787/v1/messages` 发送测试请求（带 `x-api-key: local-proxy`, `anthropic-version: 2023-06-01`），**HTTP 200 秒回出字完全正常**！
  - 修复方案：在 ZCode 中将该提供商配置为 `kind: "anthropic"`，`baseURL: "http://127.0.0.1:8787"`（ZCode 会自动拼 `/v1/messages`），`apiKey: "local-proxy"`。
  - （附加发现：8045 Antigravity 服务若未拉起，8046 净化代理会报 502，但用户澄清指的是 cmdc 里的 Claude 4.6，坐实 8787 协议格式错位才是真凶）。






**🔴 10-11 凌晨「连接 Google 节点超时（长连接不稳定）(单号: msg_91651186770535800)」根因定案**：
- **报错生成方**：错误文本不在 cmdc-pak.exe 二进制（UTF-8 全文搜索「长连接/节点超时/切换出口线路」全 0 命中）→ 由作者中转云 `cmdc-pak.ljj233.top` 生成，单号是中转云工单号。
- **实测完整流量路径**（netstat 飞行采样实证）：cmdc-pak(8787) → **127.0.0.1:10808 = FlClashCore 混合口**（ALL_PROXY 环境变量与 WinINET 系统代理双双指向它；请求飞行中网关持有约 140 条回环连接，无任何直连外网 socket）→ FlClash 机场节点 → 中转云 → 中转自己的 Google 出口 → Gemini API。二进制内唯一 Google 域名是 oauth2.googleapis.com（账号 OAuth 用），Gemini 数据面确认走中转。
- **发病证据**（用户日志 01:09–01:12 段）：3 条即时空响应（ttfb≈0.8s、in=0 out=0 无 finish = 中转秒回错误信封）+ 6 条 59.9~115.8s 滞留（59.93/60.03/62.18/63.52 + 110.59/115.78，**60s 整点聚集** → 出口链路存在 ~60s 空闲超时/断流）。网关侧不重试（全部 attempt=1/4），错误信封直接透传客户端。
- **修复归属**：作者侧三处——①摘除/更换该时段 Google 出口抖动节点 ②SSE 流加 15~30s 心跳注释帧或上调 60s 空闲超时 ③放弃前内部换出口重试一次。本机 FlClash 无罪（错误文本成功送达 = 本机→中转段当时是通的）。附网关小修：中转错误信封应记 ERR 而非 GEMINI OK in=0 out=0（假 200）。
- **单点提醒**：ALL_PROXY=127.0.0.1:10808 全局生效，FlClashCore 一挂，整条 cmdc 网关（cc/gemini/opencode/muse）全灭。
- **10-11 01:48 追加事件**：cmdc-pak 网关进程在无崩溃日志、无 WER 记录下静默退出（换节点后、探针全绿两分钟后），8787 拒连；按 SOP 从 D:\cmdc-pak 拉起（Start-Process 最小化）后 12/12 并发全绿、15s 存活。死因不明，若复现「全线连接拒绝」优先查网关进程存活。
- **10-11 02:00 机制层根因（最终版）**：①单号真相=msg_ 是中转给每条响应编的消息 ID（抓包实证：正常响应也带），「单号」即失败请求的编号，文本+单号都出自中转；②60s 整点聚集（59.9/60.0/62.2/63.5s）= 出口链路约 60s 空闲超时掐静默连接，Gemini 思考期无字节正好踩中；③中转无保活无重试（本地 /api/metrics：rate_limit_retry=0、transient_retry=0，网关日志全部 attempt=1/4）；④网关自带「换端点」机制（endpoint_switch 90s 跳 48 次）在抗抖；⑤本地管理接口：/api/gemini/quota（5h/weekly 配额桶）、/api/gemini/accounts/switch（换号）、/api/logs/export（内存日志导出，重启即清）；⑥high 模型 + max_tokens<思考预算=空响应假阳性（测试设计坑，非故障）；⑦PROHIBITED_CONTENT 占 28% 属内容过滤正常现象与超时无关。

**✅ 10-13 第十三更（v0.9.12，现役 MD5 `f61e00ce796f5bcee147c1ce83cc53c5`，15,493,120B 双份校验一致；官网 last-modified 10-13 18:25 北京时间；用户口令「更新了 老一套走起」免确认直执）**：
- **本次更新的意义=修复 10-13 上午 OpenCode FreeTierError 403 全球封**（OpenCode 新政"free 层仅限官方客户端"，判别因子=x-session-id 时间戳编码，GitHub 9router#4780 已给出解法，见 [[meta-muse-code-terminal-agent]]）。升级后 muse-free /v1/responses **实测 200 'OK' 复活**，space-bunny 同步恢复。changelog 官方话术="全面提升多轮长程对话与工具调用稳定性/连接机制优化保障日常编码持续在线"（商家不会明说破限适配）+弱网握手优化+第三方 Coding Agent 插件兼容增强。
- 执行链：HEAD 双路探测（10808 出口在洛杉矶美节点时打国内阿里云源首次卡住、后台重试即通=海外节点访问国内站的新慢点）→ 双份下载 → 热替换 → Stop-Process **未被 GateGuard 拦**（同哈希授权跨天仍有效=新观察，此前记录说"当晚有效"）→ PID 7812 面板自报 0.9.12 → 验收全绿（37 模型零漂移、muse-code/models 200、space-bunny 'OK'）→ Desktop\cmdc 落盘 16s 存活 MD5 一致 → .prev+verify 件已删，D 盘单文件态。

**✅ 10-15 第十四更（v0.9.13，现役 MD5 `738ffb816fecb1e8f1345d7c6afaf14e`，15,715,328B 双份校验一致；官网 last-modified 10-15 03:22 北京时间；用户口令「又更新了 例行公事」）**：
- **changelog 原话（商家罕见地直白）**：OpenCode Free 线="**可能是首个在 opencode 大幅加密后，成功破解的应用**"——即 OpenCode 在 10-13 session-id 判别之后又上了"大幅加密"，6haha 宣称已破。**模型目录 37→39**：新增 `big-pickle`、`cat-jam-free`（零消失）。
- 验收：面板 200 自报 0.9.13、space-bunny 'OK'、muse-code/models 39、**muse-free 首探 502 unexpected EOF → 二探 200 'OK'**（瞬抖型，按分型复测即愈；新破解机制下偶发 EOF 需列入观察）。
- 执行链：HEAD（新加坡出口打国内源慢，后台约 2 分钟才回）→ 双份下载 → 热替换 → **Stop-Process 再吃 GateGuard 首拒**（三件套交付+原样重试放行——"同哈希跨天授权仍有效"的昨日观察作废，授权窗口按次/按天不稳定，一律备好三件套）→ PID 36916 → Desktop\cmdc 落盘 16s 存活 MD5 一致 → .prev+verify 已删。
- 网关进程无声换血观察项再更新：7812→20820（10-14~15 间某时），本次是我们自己的例行重启，此前 20368→35144 那次仍死因不明。
- 观察项延续：10-13 白天发现网关曾无声换血（PID 20368→35144 非本人操作，死因不明，与前"无声暴毙"案同款待抓现行）。

**✅ 10-16 第十五更（v0.9.14，现役 MD5 `95b1847b2d9900412a6b0cd139cb5673`，16,148,992B 双份校验一致；官网 last-modified 10-16 14:49 北京时间；用户口令「cmdc更新了 老样子」）**：
- **白名单大换血（39→33）**：下架 7 个=`big-pickle`、`cat-jam-free`（10-15 刚上的俩）、`ling-3.0-flash-fin-free`（上游早已 502 挂）、`longcat-2.5-preview-free`、`muse-spark-1.2-contributor-free`、`nemotron-3-ultra-free`、`nemotron-3.5-lightning-free`；**新增 `deepseek-v4.1-flash-free`**（探针 200 活，空正文=思考吃光小 max_tokens 老分型，给足即出字）；**`exo-free` 恢复上架**（10-10 曾 410 ModelDeprecated）。付费 9 模型零漂移；muse-free/space-bunny/step-5 三件套健在。
- **changelog 要点**：free 线=思考开关全模型通用（开思考顺畅出字/关思考秒回纯净正文）、Mimo 系不再频繁重试卡住、新增 DeepSeek V4.1 Flash Free+Exo Free 恢复；**全产品线=上游增删模型不再需要重新下载（服务端配置下发自动生效）**、配置下发全程加密、报错指引更清楚、双开稳定性。
- 验收：面板 200 自报 0.9.14、space-bunny 'OK'、**muse-free 流式三连 3/3 通过**（延续 10-15 结论：Muse 实际路径=流式，稳）。
- 执行链：HEAD（新加坡出口打国内源约 2 分钟）→ 双份下载 → 热替换 → **本轮 GateGuard 未拦（三件套仍照交，授权窗口行为不稳定，坚持备好）** → PID 6644 → Desktop\cmdc 落盘 16s 存活 MD5 一致 → .prev+verify 已删，D 盘单文件态。
- 影响面提示：客户端（ZCode2/Qoder/Cherry）里登记过被下架 7 模型的条目现在选必 400；但"服务端配置下发"机制上线后，未来模型增删不再依赖换版本。

**✅ 10-17 凌晨第十六更（v0.9.15，现役 MD5 `cd00315391fc8af5288ccaf1d83874a1`，16,419,840B 双份校验一致；官网 last-modified 10-16 22:05 北京时间；用户口令「老样子 更新了」）**：
- **白名单再漂移（33→33）**：新增 `glm-5.3-flash-free`（免费版 GLM-5.3 Flash！）、`ll-alpha-free`；下架 `claude-fable-5`（fable-5-1 保留）、`step-5-preview-free`。付费 9 模型零漂移。
- **changelog 要点**：全产品线=授权页升级（没买也能看每线模型清单）、**"写入 Muse 配置前弹窗确认+显示端口，不会误改你的开发工具"**（官方开始正视 Muse 集成）、free 线=模型测试逐行刷新不再卡；Gemini 线=移除两个连不上的模型。
- **验收遇新病**：space-bunny 首枪 502 EOF → 补枪变 **429 RateLimit**（"当前网络出口用量已达上限"），glm-5.3-flash-free/ll-alpha-free 同报 429——**新加坡出口的 OpenCode 免费桶又满了**（10-12 同款病）；但 **muse-free 流式 3/3 全过**——商家破解路径与 chat 线走不同上游路径/桶，互不影响。处置：要恢复 chat 线 free 模型=FlClash 换节点（换 IP 即换桶）；只用 Muse 则无需动。
- 执行链：HEAD → 双份下载 → 热替换 → **GateGuard 未拦** → PID 7864 → Desktop\cmdc 落盘 16s 存活 MD5 一致 → .prev+verify 已删，D 盘单文件态。

**✅ 10-17 凌晨第十七回合：ZCode 侧模型清单全量同步（用户令「记得帮我更新一下最新的模型状态 把新的安装 不能用的就去掉」）**：
- **执行**：改 **4 个文件**、各留 `.bak-modelsync-20261017-033043` 备份——`cli/provider_config.json` + `v2/provider_config.json`（providerRules.personalModelIds/modelOrder + modelConfigRules.providerModelRules）+ `cli/config.json` + `v2/config.json`（provider 段 models 字典）。
- **变更**：①`opencode-free` 组 9→6——删死模型 `longcat-2.5-preview-free`/`ling-3.0-flash-fin-free`/`nemotron-3-ultra-free`/`nemotron-3.5-lightning-free`/`fledge-alpha-free`/`step-5-preview-free`，**装入 3 个新的** `deepseek-v4.1-flash-free`(200K/32K)、`glm-5.3-flash-free`(1M/131K)、`ll-alpha-free`(200K/131K)；②`claude-fable-5` 从 `new-provider-2`（cli+v2 双份）、`zhen-hajimi-gemini`（v2）移除（上游下架，fable-5-1 保留）；③顺手修正 space-bunny-free 输出上限 8192→**524288**（旧值是缩水错误值）；④providerModelRules 清 5 条死模型规格 + 补 3 条新规格。
- **规格权威源=网关 `/muse-code/models?channel=public`**（返回 `{context_window, max_tokens}`，字段名是 `data` 不是 `models`——10-12 栽过）。交叉审计：9 个指向 8787 的 provider 条目死条目归零 ✓。
- **生效需重启 ZCode**（配置=启动快照）。遗留观察：`new-provider-2` 在 cli/v2 两份里模型数不一致（6 vs 9，v2 多 opus/sonnet/haiku 三条）=历史遗留未拉齐。

---

**（并入自 cmdc-muse-handoff-20261010 归档交接卷）**

# 交接快照：cmdc + Muse 战线（sess_f1465313，10-12 归档，本卡 10-12 终更新）

本会话从 sess_6fc7b573 接手，运行 4 天后因体量（54 万 token/轮，撞阿里云 TPM 限流）由用户下令交接。

## 已完成并验证（细节见 [[command-code-go-gateway-topology]] [[meta-muse-code-terminal-agent]]）
- **cmdc-pak 四连更至 v0.9.10**（MD5 2bdfc02b，双副本 D:\cmdc-pak + Desktop\cmdc，六步 SOP 定型）；白名单 9 模型含 GLM-5.3；Muse 路由 37 模型目录。
- **Muse Code 全链路打通**：F:\AI\muse 安装+配置+实测（写文件/跑命令闭环）；目录 37 模型是橱窗，**仅 muse 系可跑**（--model deepseek 实测 10 连败）。
- **ZCode 新模型四批**：Claude4.6 协议修复、gemini-3.1-pro-high、GLM-5.3（1M/131K）、step-5-preview-free（1M/65K）、claude-fable-5-1/5（1M/64K），重启复查全在位。
- **/muse 技能卡 v4**：派活铁律 + `/muse goal` 对话版目标模式 + **--reasoning-effort max 显式钉死**（CLI 默认 high、settings 消费无法证实）+ 指令冲突裁决 + 派单凭据硬闸。
- **685 案完整周期**：死刑(09-21)→半复活(09-28)→"永久退役"判词(10-11 晨)→**平反(10-11 晚)**：用户把它加入 cmdc Gemini 池（卡 G--UEZ，07:58 入池 08:07 真实处理请求）——生成通道静养一周自愈；Antigravity 额度面板仍空（不影响生成）。教训：Google 静默旗有衰减期，禁说"永久"。
- **10-11 浏览器全挂案**：真凶=10808 死+系统代理指它+TUN 活（半猝死新变体），端口复活即愈；指纹入 [[flclash-tun-topology-20260920]]。
- **限流诊断（10-12 凌晨）**：本对话 54 万 token/轮轰穿阿里云 TPM（分钟级，等 60s 自愈）；发布准备2 打穿 Z.ai GLM 计划总量额度（周期级，等不了）；cmdc deepseek 瞬断=重发。三家三病。
- **Muse 与柠檬思考**：Muse 拒收 156 个中文名技能（含柠檬思考，invalid skill name）；用法=让 Muse 读 SKILL.md 文件，或用其原生 grill/plan 平替。

## 未闭环事项（新会话按此接续）
1. **「发布准备2」(sess_3d54c231-2f5e-4e8d-9ce8-befa9ac5c9c8)**：任务=全技能柜跨系统脱敏、优化与发布（接手自 sess_b86707e5）；该会话 /muse 被 GLM 静默接管（114 轮全 GLM、零 muse 痕迹，v4 卡就是为此打的补丁）；**Z.ai 额度已打穿**——续跑换线（建议真哈基米 gemini-high 或新会话正版千问）。
   - **✅10-12 续跑已落地**：新会话从会话库逐字节提取工单全文 4557 字（读法见 [[zcode-db-lock-diagnosis]]），落 `_muse_发布准备2_工单.md` 后以 `muse.cmd exec --yolo --trust-workspace --reasoning-effort max --prompt-file …工单.md`（cwd/workspace=F:\AI，后台+run log `_muse_发布准备2_run.log`）正式派单。**用户说「继续 muse 没完成的事」= 这条派单本身兼作 v4 卡实弹验证**（max 钉死是否真生效、有无 GLM 静默接管复发）——第一理解成做发布准备2被用户打回过一次，两层是一体的。启动证据：muse-bin-1.4.4 双进程活着、8787 见 mode=chat deepseek-v4.1-flash 流式往返、28 技能加载+134 中文名拒绝警告（已知不阻塞）。现场校准：维护树 HEAD f346561 与工单声明一致；**run03 目录（verification+release 两处）已被当年被劫持的 GLM 会话建过**，工单自带规则=已存在则 Muse 另取新 run 号不得覆盖。三份工单/设计文档在 `Desktop\自制skill\文档\柠檬\工单|设计\2026-10-11-*.md`。
   - **✅10-12 09:49 第二派进行中**：OpenCode 出口冷却自愈（实弹 1+1 回「1+1等于2。」）→ 整本重派（Muse 已自升级 1.4.6；后台 task `exec_769cee52` 绑旧会话 sess_ef986e12，会话退役若任务死则按交接 Prompt 内命令原样重派——重派安全，工单第一步就是冻结现场）。派单 6 分钟即提交 `b005743 feat(q02+q03)`、工作区干净、正从 Q04 续跑——**进度连续模型=会话层不续、产物层续**（详 [[meta-muse-code-terminal-agent]] §4.7，含 --yolo 自动提交边界与监督三层法）。用户已索要 /jiaojie 交接 Prompt（七段结构、含全部现场锚点），本人将新开对话接手。
   - **10-12 上午第二派终态**：09:49 派单→10:46 死于 OpenCode 出口 RateLimit 10 连败（跑满 57 分钟、会话 12MB；成果安全，b005743=q02+q03 已提交在前）。**接手正解=先换出口再原样重派**：换出口当时与 everchild 机场修线联动（FlClash profile 文件已换新订阅、每日 09:00 cron automation-36c8cc7a 自动追更、重启 FlClash 待用户回「重启」，详 [[flclash-tun-topology-20260920]] 10-12 段）；重派命令与续跑模型见 [[meta-muse-code-terminal-agent]] §4.7/§10。
2. **exo-free 死条目**：上游 410 永久弃用，ZCode 内条目未删，等用户口令。
3. **UMH F01 总控**：sess_d2bb1ef 线（工作树 umh-v1），多日未提，状态以该会话实况为准。
4. **技能卡 v4 生效**：需新会话加载；老 /muse 会话仍是旧卡。
5. **685 维护条款**：cmdc 池现役，禁批量探测/warmup；日志再现 VALIDATION_REQUIRED 即摘出静养。

**Why:** 用户原话「交接对话」；54 万字对话每轮重烧+TPM 限流，必须瘦身重启。
**How to apply:** 新会话读本卡+三张详卡（gateway-topology / meta-muse / 403-validation-block）即全量续命。
