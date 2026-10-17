# Dream Skin 剩余任务一次性结项 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: 使用「柠檬思考」的 `executing-plans` 逐项执行；修复按 `systematic-debugging` 与 `test-driven-development`，结项按 `verification-before-completion`。本单已覆盖所有后续阶段与返工；不要再把“生成下一张工单”当主要交付。

**Goal:** 从 K02 VALID_PAIR 接续，完成双端现有产品、双目标工具、最终安装件和 50 组验收，以本机严格 PASS 结项。

**Architecture:** Cherry 独立全文读源和精确 CAS/恢复；ZCode 独立兼容和生命周期；A00 后复用现有编辑器实现双目标导出。只增加已证明必要的适配，不重造框架。

**Tech Stack:** 既有 Node/.NET/FlaUI/PowerShell RemoteSigned、CM6 适配、Electron/React/TypeScript、ZCode 原有受管启动/导入/安装链。

**Spec:** `C:\Users\Janson\Desktop\换皮\文档\柠檬\设计\2026-10-16-Dream-Skin剩余任务一次性结项-设计方案.md`

## Global Constraints

- 本次仅交付计划。执行者核对实际实施授权；已有授权持续有效，不反复申请同一范围。写工单不等于本会话已启动宿主实验。
- 一个统筹 Agent 对总结果负责；默认顺序执行，允许独立离线工作交错推进。真实宿主串行。同一文件/工作树一个写入所有者。
- 复用 K02 VALID_PAIR；不再重做历史取证或因措辞润色要求用户重采。执行前新鲜基线用于防漂移，与推翻历史结论无关。
- 历史 C05 首例 FAIL 保留；后五例/G2–G4 为 NOT_RUN。不能将整项改成“从未执行”掩盖失败。
- 不修改旧 r19/证据原件/原始备份；使用独立 codex/ 分支及新候选目录，路径以接手时真实状态为准。
- 不降低完整文本、SafeCSS、ZIP、真解码、2MiB 边界、身份和恢复断言；不使用 AST/trim/逆投影刷绿。
- 不改官方 exe/asar、不读聊天/账户/数据库、不全局杀进程、不使用 ExecutionPolicy Bypass、不用裸 PATH Node。
- 一次实验写入与至多一次恢复写入是不同动作；恢复同样必须具备明确许可与状态条件，异常只停止新增实验写入，必要只读核验继续。
- 生产代码完成必须包括真实调用链、打包与安装运行。诊断通道、mock、源码测试、DevTools 结果都不能单独证明用户可用。
- 50 组是测试组数，内部参数分支全部保留；不预填未来 PASS、测试总数或退出码。
- 只在精确改动提交后构建，所有会重编桥的测试结束后冻结执行集合；新代码/provider/profile/包使相关证据失效。
- 分支等待窗口时继续其它安全独立任务；真正阻塞写明缺的条件与续接命令，不以反复补文档代替实施。

## Review Focus

1. 不同逻辑原文得到同一 UIA 投影，不能用 UIA 相等作为覆盖许可（Q01/Q04）。
2. 写入已发生但桥回 indeterminate/超时，必须继续只读取证与受限恢复，不能信 `written:false`（Q01/Q02/Q04）。
3. 诊断能读但安装版无法部署、没有来源身份或日用需 DevTools，必须阻止正式应用（Q03/Q05/Q06）。
4. normalized/percent、ROI/EXIF/zoom 和目标字段进入真实输出，而非只改 UI/元数据（Q11/Q12/Q16）。
5. 暂停导入、取消、并发编辑和升级/卸载恢复不能修改另一端状态或吞用户数据（Q04/Q09/Q13–Q16）。

## 入口、路径和状态

以下别名只用于阅读；命令和执行记录必须展开为绝对路径。

| 别名 | 路径 |
|---|---|
| ROOT | `C:\Users\Janson\Desktop\换皮` |
| TOTAL | `C:\Users\Janson\Desktop\换皮\.lemon\dual-skin-closeout-20261015` |
| CBASE | `C:\Users\Janson\Desktop\换皮\.lemon\dual-skin-closeout-20261015\wt-cherry` |
| CDIAG | `C:\Users\Janson\Desktop\换皮\.lemon\dual-skin-closeout-20261015\wt-c05-roundtrip` |
| ZBASE | `C:\Users\Janson\Desktop\换皮\.lemon\dual-skin-closeout-20261015\wt-zcode` |
| K | `C:\Users\Janson\Desktop\换皮\.lemon\dual-skin-closeout-20261015\final-closeout-20261016\run-20261016-k01-01` |
| PAIR | `K\k02pair-01-20261016`（展开 K） |
| RUN | Q00 在 TOTAL 新建的唯一结项证据目录；存在即另取新名，不覆盖 |
| CW / ZW | Q00 认领的执行工作树，保存完整绝对路径；不默认占用 CBASE/CDIAG/ZBASE |

前置参考固定为：

- `ROOT\文档\柠檬\工单\2026-10-15-Dream-Skin双端统一收口-实施计划.md`：原 17 项的具体接口和文件，以下映射保留全部范围。
- `ROOT\文档\柠檬\设计\2026-10-15-Dream-Skin双端最终校验与返工-设计方案.md`：50 组、M01–M05、证据失效规则。
- `ROOT\文档\柠檬\工单\2026-10-15-Dream-Skin双端最终校验与返工-实施计划.md`：V00–V05 执行与失败单格式。
- `ROOT\文档\柠檬\工单\2026-10-16-Dream-Skin剩余任务一次性结项-验收矩阵.md`：本单随附的完整 50 组断言快照与 Q 任务映射。
- `K\K03-CONTROLLED-EXPERIMENT-SHEET-REV3-20261016.md`：K03 基础流程；与本单冲突时，以 Q01/Q02 的明确收紧条款为准，不重复再写 REV4 总方案。

编写时 CBASE=`f0bbe861d562532100ed31c92c2d0cd4c32619ff`；CDIAG=`3df6451f5555f6615d1441c5d9e52053a5024ab4`；ZBASE=`01fdb07824cbaab021f6677578bf7f3aad720477`，均干净。r19 在 `CBASE\.lemon\payload-candidate-r19`。所有编写时状态均是快照。

## 总工单与依赖

| 工单 | 可验收交付 | 依赖 | 原范围 | 初始状态 |
|---|---|---|---|---|
| Q00 | 接管、路径/身份/授权和任务认领 | 无 | P00/K00 | NOT_RUN |
| Q01 | K03 可运行离线执行包与恢复预演 | Q00 | K03 准备 | NOT_RUN |
| Q02 | 一次 D 同期对照及恢复结果 | Q01、实际窗口 | K03 | NOT_RUN |
| Q03 | 可部署读源裁决与隔离原型 | Q00；正式裁决消费 Q02 | K04 路线 | NOT_RUN |
| Q04 | 正式全文/CAS/恢复最小修复 | Q02/Q03 | N03/N04/K04 | NOT_RUN |
| Q05 | 证词、应用门、载荷全链绑定 | Q04 | C03/K04 | NOT_RUN |
| Q06 | Cherry 新候选离线过门 | Q05 | C04/K05 | NOT_RUN |
| Q07 | Cherry G1–G4 原生签收 | Q06、实际窗口 | C05 | NOT_RUN |
| Q08 | ZCode 当前兼容、备份与候选 | Q00、实际窗口 | Z02 | NOT_RUN |
| Q09 | ZCode 九步/14格签收 | Q08 | Z03 | NOT_RUN |
| Q10 | 两端 A 基线冻结 | Q07/Q09 | A00 | NOT_RUN |
| Q11 | 双目标合同与 ZCode 导出器 | Q10；只读合同可提前 | X01/X02 | NOT_RUN |
| Q12 | 既有编辑器双目标 UI/IPC 接通 | Q11 | X03 | NOT_RUN |
| Q13 | ZCode 单一编辑入口与依赖安装 | Q12 | X04 | NOT_RUN |
| Q14 | 双端最终构建、隔离安装生命周期 | Q13 | X05 | NOT_RUN |
| Q15 | 最终安装版双端真实验收 | Q14、实际窗口 | X06 | NOT_RUN |
| Q16 | 50 组终验、失败返工与复验 | 贯穿；总判定依赖 Q15 | V00–V05 | NOT_RUN |
| Q17 | 本机交付与严格结项 | Q16 PASS | F00 | NOT_RUN |

Q03 只读可行性与 Q08 的离线准备不必等待 Q02。Q07 受阻时仍推进 Q08/Q09。A00 前不向产品候选加入 B 的实现。每个已授权任务通过即进入下一任务，不在每张工单末尾问“是否继续”。

## Q00 接管并固定一次性执行输入

**文件：** 读适用 AGENTS、各仓最新 handoff、PAIR 原件、三树 Git、原总台账；写 `RUN/EXECUTION-INPUT.md`，原 `TOTAL/TASK_PROGRESS.md` 只追加本批映射，不覆盖旧结论。

**接口：** 输出 `CW/ZW/RUN` 绝对路径、完整 SHA/dirty、所有者、证据复用清单、已授权范围及真正待用户配合的动作。

- [ ] 核对三个工作树与在途执行者；在自有 `codex/` 分支/隔离树实施，已有被认领树不抢写。诊断提交按所需变更复用，不把诊断 exe 自动当生产桥。
- [ ] 核验 PAIR 的 18 键、原件哈希与签收，不再重复历史窗口；把 K02 标为有效前置，把 C05 首例 FAIL 和其余 NOT_RUN 分开登记。
- [ ] 建立唯一 RUN，保存基准身份、旧候选路径、各任务负责人、备份/恢复位置与用户授权来源。不要完整转储环境变量或私人文件内容。
- [ ] 为四类实际窗口准备一个待办清单；实施、实机、安装、重启、用户视觉分别记录已有范围，缺项在可审操作包备齐后集中提出。

**通过：** 路径可读、所有权清楚、无覆盖并发改动，下一步能直接执行 Q01 与独立准备。缺文件只定位缺项，不重写项目历史。

## Q01 K03 执行包与离线恢复预演

**文件：** 读 `K/K03-...REV3...md`、CW 的 `src/host-bridge.mjs`、`host/CherryUiBridge/Program.cs`、CDIAG 诊断链；在 RUN 新建 `k03-operations.md`、`k03-runner.mjs`（仅当现有驱动不能复用）、`k03-runner.test.mjs`、`k03-input.json`，不改冻结生产包。

**接口：** 输入只允许实际桥/可信 Node/目标身份/证据目录/一次 D/原值文件。输出原始请求答复、各次采样、分诊、恢复结果。恢复执行权是独立显式字段；测试入口默认 stub，不连接宿主。

- [ ] 把 REV3 落成确实可执行的参数与命令；复用现有桥调用函数，所有命令绝对路径，生产读写执行体摘要固定，原始桥答复在客户端裁剪之前归档。
- [ ] RED：模拟写前 conflict 写次数=0；写后 indeterminate 写次数=1且仍读逻辑/UIA；超时不标未写；恢复写后 indeterminate 仍双读；恢复未知值/用户编辑/身份变更写次数=0；已有基线文件不覆盖。
- [ ] 补关键反例：不同逻辑文本但同一 UIA hash 不得恢复；T2 新值不能仅凭“已记录”收入可恢复集合；没有原文文件不可写实验；只拿 T1 hash 没有对应全文不得冒充逐字证据。
- [ ] 最小完善驱动并 GREEN。S 成员须有新鲜逻辑/UIA 对、身份、时间及未编辑条件；无法确认实验归属时停止恢复覆盖。不能再用任意新读值刷新 expected hash。
- [ ] 准备 D 文件并复算 9B/hash；准备恢复文件生成流程。本次新鲜逻辑仍为空时写零字节恢复文件并验空串 hash；非空则先完整本地导出并验 hash，探针只有 hash 不够。
- [ ] 写前门强制双读；采样时序明确为 UIA-pre→逻辑→UIA-post。settle 只做有界只读：优先使用已审现有配置，没有配置则离线定义间隔/次数/超时并保存实际时间，禁止套用历史 +52 秒空档。
- [ ] 对照用户参与路径做一次纯离线演练：T3/T5 都需要完整逻辑输出，不得实验后才发现用户已关 DevTools。将主流程、独立恢复命令、退出状态和窗口操作一起列出。

**通过：** 测试有 RED→GREEN，未连宿主；具体执行文件和恢复文件流程可审，无未知参数等待现场试错。控制流不满足即在 Q01 修复，不进入 Q02。

## Q02 一次 D 对照与双通道恢复

**文件：** Q01 操作包、PAIR、全新 `RUN/k03/<attempt-id>`；不重用旧采样目录。

**接口：** 输出 `input/logic/uia-pre/uia-post` 的身份、字节数、hash、时间与原件；`writePhase` 和 `restorationVerdict` 分开，实验归因成功不代表恢复成功。

- [ ] 在实际已授权窗口刷新宿主/目标身份；新鲜逻辑全文与 UIA 原件分别锁定，生成并核验恢复文件，确认期间用户不编辑。任一条件不符不写 D。
- [ ] 一次 CAS 写 D，保存原始 `status/stage/reason/before/after`、客户端返回及真实退出码。非 verified 不重写；区分写前拒绝和可能已写入。
- [ ] 紧接着完成双采夹逻辑，保留完整 18 键和未编辑确认；缺证不再写样本补机会。超时/不稳定/身份丢失记录具体原因。
- [ ] 恢复前再读逻辑/UIA：两端均已原值则无需写；确认仍为本轮实验对才执行至多一次恢复 CAS；未知/编辑/身份冲突停止自动覆盖。恢复之后即使桥不确定也继续双读核验。
- [ ] 判定：逻辑精确9B/UIA8B证明本次 D 的读通道差异；逻辑8B/UIA8B定位实参后至模型之间；两者9B说明本次未复现；其它结果保持未证。空态和 D 点不能外推所有长文。
- [ ] 保存恢复双端结果；实际不等记 RESTORE_FAIL，缺证记 RESTORE_UNVERIFIED，均不能报告零残留。安全冲突先保护现场，暂停此宿主；独立 Q08 可继续。

**通过：** 有可区分原因的真实对照且恢复已证。失败进入 Q16，不重复自动写 D。历史失败仍保留，新结果绑定本次 run。

## Q03 可部署全文读源裁决与原型

**文件：** 读当前组件/安装身份及 `K/CM6-ACCESS-CONTRACT.md`，CW `src/host-bridge.mjs`、`desktop/src/main/host-controller.ts`、`desktop/src/main/apply-gate.ts` 的实际接线；写 `RUN/reader-decision.md`；隔离原型与测试放自有工作树，不写官方安装。

**接口：** 明确选定来源、绑定目标、版本、访问方式、执行依赖、安装启动、撤销方式、编码边界。正式拟新增 `CW/src/host-text-provider.mjs`；若已有等价模块，记录映射后扩展原模块。

- [ ] 用当前源码/安装材料核实可复用公开能力；记录现有通道实际可达性，不猜全局对象，不把另导入的一份 CM6 当宿主实例。
- [ ] 先证明最小独立逻辑 reader 在隔离环境可读完整文本、拒绝错误目标/过期句柄/缺失文档。`?? ''` 不能把读取失败伪装成合法空文档。
- [ ] 结合 Q02 选择路线：可证明原 UIA 调用缺陷则修原桥；否则优先独立逻辑 provider。没有可行生产来源就明确 BLOCKED，不默认逆投影归一化，也不交付每天手动 Console 的假自动化。
- [ ] 明确运行权限和部署：若需新调试连接/启动参数/依赖，先完成隔离原型、实际命令、仅本机连接约束、生命周期和恢复验证，再一次提交具体范围；已获范围内直接推进。
- [ ] 输出可测试合同 `readLogicalCss({targetIdentity,requestId}) -> {status,textDomain,utf8Bytes,sha256,artifactFile,readerIdentity,sampledAt,reason}`；成功仅为 logical，全文字节文件必有，失败不得返回成功空串。
- [ ] 内部评审通过才进入 Q04；评审针对工程证据，无需用户逐个批准内部接口。权限/行为边界变化才要求用户审阅具体变化。

**通过：** 已选择且证明可部署的来源，有明确失败闭锁与完整字节输出。探索记录与产品实现分开，不能以“设计通过”代替接通。

## Q04 正式全文、CAS 与恢复最小修复

**文件：** CW `src/host-text-provider.mjs`（planned）、`src/host-bridge.mjs`、确需的 `host/CherryUiBridge/CssEditorAccess.cs`/`Program.cs`；测试 `tests/host-text-provider.test.mjs`（planned）、`tests/host-uia-contract.test.mjs`、`tests/host-bridge-wire.test.mjs`、`tests/host-native-recovery.test.mjs`、`tests/host-application.test.mjs`。

**接口：** 继续既有 readCss/compareAndSetCss 用户入口；新语义明确 `textDomain=logical` 与 readerIdentity。生产 `expectedCurrentSha256` 比较可信逻辑原文，UIA 投影仅作诊断。旧协议不得被悄然重新解释。

- [ ] RED 固化 Q02 最短复现，并测试空串、空文档读源失败、尾LF/空格、多行中文、非BMP、LF/CRLF/CR、长行、多短行、2MiB−1/2MiB/2MiB+1。大小用 UTF-8 字节，完整 bytes/hash 断言。
- [ ] RED 并发：备份后用户编辑、逻辑不同但 UIA 相同、过期实例、读后写前变化、重复请求/超时、写后 indeterminate；未知当前值绝不覆盖。超限在调用写入前拒绝。
- [ ] 实现最小来源适配并接生产入口；保证比较与写入不被并发逻辑变更绕过。优先在同一可信宿主执行上下文比较文档再写；无法提供该保证则保持冲突/不可用，不能宣称原子 CAS。
- [ ] 备份绑定逻辑来源/宿主/读源身份，原始 UIA 原件另存；恢复只从确认为本轮写入的当前逻辑值回到原件。恢复错误与读源不确定分开记录，不用 written:false 推断未写。
- [ ] 有界 settle 只解决真实未稳定读数，稳定错值必须 FAIL；错误来源不可自动降级成 UIA 真值。正式写入需验证应用保存路径，不能只改编辑器内存。
- [ ] GREEN 跑定向 Node/wire/恢复测试与可部署原型集成；源码 diff 只含必要适配，提交精确变更。官方签名文件、原候选与用户数据不进入提交。

**通过：** RED→GREEN、全链真实接线、并发/超限/恢复负向不退化。模型换行能力不满足原精确合同则报告具体失败，不自行改验收期望。

## Q05 证词、应用门与执行集合绑定

**文件：** CW `src/targets/cherry/evidence.mjs`、`desktop/src/main/apply-gate.ts`、`src/apply-gate-reasons.mjs`、`scripts/host-uia-roundtrip.mjs`、`tests/native-evidence.test.mjs`、`tests/native-proof.test.mjs`、对应 payload/桌面 gate 测试。

**接口：** 正式证词绑定源/构建、桥全集、provider全集、宿主、profile、目标、编码和文本域。/3 若容纳不了新含义，集中升级实际 schema 与全部消费者，旧来源证词不得冒充新来源。

- [ ] RED：旧/缺 readerIdentity、旧 UIA 文本域、错误目标/宿主、正确 EXE 但 DLL/provider 被换、缓存证词、诊断输出冒充正式输出，全部写前拒绝。
- [ ] 最小扩展生产验证器和消费者；清单覆盖实际运行的完整依赖，来源字段不能仅自报 true。schema 版本与错误分类同步更新。
- [ ] 更新驱动与恢复门，使原生证据用实际逻辑来源；UIA 比较保留独立诊断字段，不能通过同时归一化 expected/actual 产生假绿。
- [ ] GREEN 验证合法来源能到真实写入口，负向写次数=0；完成类型检查和定向测试，保存完整外层退出码并提交。

**通过：** 证据→gate→实际执行体→回读来源闭合；“诊断成功即 supported”路径不存在。

## Q06 Cherry 新候选构建与离线门

**文件：** CW 现有 `tests/run-tests.ps1`、`desktop/package.json`、`scripts/package-desktop.mjs`、payload 验证器、bridge manifest 生成链；新候选与 `RUN/cherry-candidate.md`。

- [ ] 跑实际注册的全量门、desktop test/typecheck/build；对照应执行/实际执行/skip。历史 474/495 不写死；失败真实保留，修复回所属 Q 单。
- [ ] 所有会重编桥的 wire 测试结束后重新冻结桥/provider 执行集合；源码提交与构建 SHA 对应，r19 保留，候选目录取未占用新名。
- [ ] 从新候选执行起窗与包往返；源码不可作依赖，PATH 不供 Node 仍用冻结 runtime。缺件/篡改/旧证词/未知执行依赖均在正确门拒。
- [ ] 保存最终完整文件清单/hash/体积/命令/日志/exit；准备含实际候选、身份、RunB、证据目录、备份恢复的 G1 命令，核对所有必需参数后再申请缺少的窗口动作。

**通过：** 候选工程有效通过；不能提前标 C05 或 profile 通过。构建后再改变执行字节必须重新冻结。

## Q07 Cherry G1–G4 真机签收

**文件：** 新候选的原生驱动、`tests/host-uia-native.tests.ps1`、原 DOM/live/profile 合同与 `RUN/cherry-native/`。

- [ ] 就绪窗口内确认新鲜逻辑原态、独立 UIA 读值、完整不可覆盖备份及新执行身份；实际原态是什么就测什么，不为凑空/非空基线覆盖私人 CSS。
- [ ] G1 按顺序执行 cn-multiline-65、longline-240056、many-short-240056、runb-239438、generated-2mib-minus-1、generated-2mib-plus-1。前五精确全量写读；最后写前拒绝。每例恢复验收完成才进下一例，首红后停后例。
- [ ] G2 记录 main scope、settings、辅助窗口策略、保护区和真实 data URL 渲染。不能用选择器存在或文本写成功替代视觉效果。
- [ ] G3 用户正常退出重开，验证保存与恢复；G4 四套/人物、浅深、宽窄、文字/输入/代码可读性由用户逐项签收。新崩溃停受影响支线，不代关程序、不清 state。
- [ ] 按实际证据链生成 profile 判定；supported 不手填。profile 字节变化需新候选并重验受影响层，最终证词绑定最终交付件。

**通过：** C05 G1–G4 全部要求有有效 PASS、恢复有证。归档实验完成不算 C05 成功；失败回 Q16。

## Q08 ZCode 当前兼容、备份和必要修复

**文件：** ZW `windows/assets/zcode-profile.json`、`windows/scripts/zcode-compatibility.mjs`、既有受管启动/恢复模块、`windows/tests/zcode-compatibility.test.mjs`、`windows/tests/zcode-native-warm-restore.tests.ps1`、`windows/installer/build-release.ps1`；原 Z01 报告作为历史参照。

- [ ] 刷新宿主版本/摘要、会话归属、私人根实际清单；22/28/14 的不同计数按递归文件/目录口径说明，不能猜丢数据原因。不重造 state.json，不套旧 PID。
- [ ] 用户保存并正常退出相关写入后，备份当次完整目录、逐文件 hash，并在沙箱还原证明 drift=0；备份有缺口不安装或恢复。
- [ ] 用原受管启动和语义探针取当前允许元数据，执行 full/safe/deny。ZCode 按其自身兼容机制，不照搬 Cherry CSS 控件/UIA 的验收逻辑。
- [ ] 需要修复时先 RED：未知版本不 full、缺锚点拒、旧会话/PID 不误认、保护区不扩大、CAUTION 未测仍关；最小修复后定向与适用全量 GREEN。
- [ ] 无源码变动不为凑进度重建；有 profile/源码变动则新 commit/候选，运行实际载荷校验和安装核验。localization 等继承失败属于必测时必须修复，不从计数剔除。
- [ ] 结束记录当前状态及可执行恢复路径；恢复条件不明或故障不能自删 state/重装碰运气，进入 Q16。私人库与官方文件保持原合同。

**通过：** 当前版本兼容判定有语义证据，实际候选可验、备份可恢复。safe/deny 如不能满足原功能即不能签全功能 PASS。

## Q09 ZCode 九步/14格

**文件：** `ROOT/文档/柠檬/工单/2026-10-04-S6-人物图片真实点击与视觉验收卡-九步.md`、新 `RUN/zcode-native/`；沿用原卡 14 个子格，不改为 9 个笼统结论。

- [ ] 按卡测试选图取消/选择、生成只保存、同图同参复用；机器状态和屏幕结果分别记录。
- [ ] 四套逐个明确应用，验证使用中标记/当前 snapshot/实际画面一致；换图、焦点、明暗必须实际消费。
- [ ] 默认与暂停分别恢复；人物态和默认态各由用户正常退出重开，不能偷偷贴回旧皮肤。
- [ ] percent/normalized 两来源各导入只保存，坏包/取消零发布；图库二次打开聚焦同窗，关图库不关皮肤，托盘退出行为正确。
- [ ] 宽窄布局、输入/编辑器/终端/图像/表格保护区由用户签收；逐格保存原话与时间。任何失败进入 Q16，余格真实 NOT_RUN。

**通过：** 九步/14格有效通过并保留用户最终选择；没有视觉反馈即 INCOMPLETE。

## Q10 冻结现有双端 A 基线

**文件：** `TOTAL/ACCEPTED_BASE.md`（已有则追加新版本引用）、原台账、Q07/Q09 证据索引。

- [ ] 核对两端源码→构建→候选→安装→宿主→证词与用户结果一致；历史日志只在对应层未变时复用。
- [ ] 确认现有产品必测失败关闭、恢复无缺口；用户接受限制另记 LIMITED_ACCEPTANCE，不能冒充严格 A PASS。
- [ ] 冻结两端 BASE 的完整身份和恢复入口；B 实现在其上另认领隔离树，保持 A 候选可回退。

**通过：** 两端 A 真正签收。未通过时继续 Q16 和另一安全支线，只读 X 合同可提前，B 产品代码不提前混入 A。

## Q11 双目标合同与 ZCode 真实导出器

**文件：** CW planned `docs/zcode-target-contract.md`、`src/targets/zcode/export.mjs`、`tests/zcode-target-contract.test.mjs`、`tests/zcode-export.test.mjs`；改 `src/cli.mjs` 和既有包接线；复用 ZW `windows/scripts/zcode-art-source-format.mjs` 与真实验证/导入器。

**接口：** `exportZCodeTheme({project,targetContract,outDir}) -> {themeDir,revision,sourceFormat,warnings}`；CLI `export-zcode`；默认 `sourceFormat=zcode-percent-v1` 走既有来源请求/catalog，不向 theme.json 塞未允许字段。

- [ ] 按冻结 BASE 列字段 `direct/baked/unsupported`，覆盖 dim/blur/颜色/opacity/radius/ROI/zoom；不新造项目 schema。原已完成来源转换复用。
- [ ] RED：normalized .76→76、.5→50；percent .76→.76；边界0/1/100，NaN/Infinity/未知来源拒；旧无来源 percent 库不改语义，断言生产 renderer 的实际值。
- [ ] RED：/1 与 /2 项目、EXIF1–8/ROI/连续 zoom、图hash、源项目不变、revision 稳定与变化、unsupported 可见拒绝；不能只检查 helper/metadata。
- [ ] 复用现有真解码/构图/ZIP/SafeCSS 生成三件套与受控副本；CLI 真接线，用冻结 ZCode 验证器和导入器往返，saved 新增且 active/偏好/暂停不变。
- [ ] GREEN 负向覆盖缺件/空CSS/坏hash/自洽清单坏图/路径攻击/重复链接嵌套/压缩与图像上限/ID冲突；登记现有测试 registry 并提交。

**通过：** 合同与真实输出一致，两端参数不串用，目标包被真实导入器接受且不应用。

## Q12 既有编辑器双目标 UI/IPC

**文件：** CW `desktop/src/main/cherry-service.ts`、`desktop/src/shared/cherry-api.ts`、`desktop/src/preload.ts`、既有 UI 组件、`desktop/tests/cherry-service.test.ts` 与 IPC/组件测试。

**接口：** 白名单新增 `exportZCodeTheme({themeId,revision})`；main 从保存项目加载冻结合同调用 Q11。原 `exportTheme` 继续导 Cherry，UI 不传任意路径/裸CSS/shell/任意 target。

- [ ] RED 从真实 UI 事件经 preload/main 到 Q11 生成文件；错 revision/未知动作/任意路径/取消拒绝且无发布；选择 ZCode 不得调用 Cherry 宿主写入。
- [ ] 接通目标选择与导出，复用草稿/预览/撤销/搜索/分组/复制/改名/归档和裁剪；预览标明模拟，目标不支持字段显示具体原因。
- [ ] 验证可编辑项目包保留原图/构图，目标主题包用途明确；保存项目不自动应用；两目标状态各自展示。
- [ ] GREEN 桌面 test/typecheck/build 和端到端输出回验，提交最小接线。M03 断开调用必须令测试失败。

**通过：** 安装工具可复用的真实调用链完成，非只有按钮或 mock 返回成功。

## Q13 ZCode 单一编辑入口与冻结依赖

**文件：** ZW planned `windows/scripts/edit-zcode-theme.ps1`、`windows/scripts/zcode-theme-editor-bridge.ps1`、`windows/tests/zcode-editor-bridge.tests.ps1`；改 `windows/scripts/tray-zcode-dream-skin.ps1`、`windows/installer/release-stage.ps1`、`windows/installer/zcode-dream-skin.iss`。

**接口：** `Invoke-ZCodeThemeEditor -EditorRoot -ProjectRoot` 仅启动冻结编辑器；`Import-ZCodeEditorExport -ArchivePath -StateRoot` 仅调用原导入器保存。编辑器 pin 记录源码/载荷完整身份。

- [ ] RED 单一菜单入口、缺件/错hash/不可信runtime拒、中文空格参数安全、任意 shell 输入拒；导入不应用、不启动宿主、不解除暂停。
- [ ] 复用 Q12 冻结工具与现有可信 runtime，依赖完整进入安装清单；不引用开发树，不另造编辑器或主题库。
- [ ] 在隔离安装布局且 PATH 无 Node 时由真实菜单 handler 起工具；关闭工具不停止皮肤，图库焦点/互斥合同不退化。
- [ ] GREEN 入口、取消、缺依赖、暂停与卸载保留项目/主题测试；提交精准脚本与安装 stage 改动。

**通过：** 从安装布局日用入口可编辑导出，依赖闭合，导入只保存。

## Q14 双端最终构建与隔离安装生命周期

**文件：** ZW planned `windows/tests/zcode-editor-roundtrip.tests.ps1`；两端现有 package/IPC/payload/installer 测试；新候选、编辑器 pin、Setup 与 SHA256SUMS。

- [ ] RED 同一项目两端导出，分别使用不同 state/project/restore 根；相同主题ID不串状态，取消/失败保留 active 与 last-known-good，暂停继续重新验兼容。
- [ ] GREEN 真 CLI/PS/IPC/导入器的文件往返，生产 renderer 消费字段，图hash/revision 一致；加入 M04/M05 等有效性断言。
- [ ] 在最终提交跑适用全量、typecheck/build 与打包负向门；所有会改执行字节的动作结束后冻结完整集合，按实际 builder 参数构建新包，保留 A 候选。
- [ ] 在代表性隔离安装布局运行真实安装/升级/卸载/重装执行体，验证库/项目/偏好保留、备份还原 drift=0；不能用 mock 代替，也不在私人日用库故意破坏。
- [ ] 无安全隔离能力则记录具体环境缺口，R02/R03 保持 BLOCKED；不得绕限制对日用实例强行卸载。
- [ ] 逐件复算包/编辑器pin/安装清单，源码不可依赖布局起窗与回环；生成 W-D 真实路径/备份/恢复/变化摘要，冻结后字节变动另出候选。

**通过：** 最终候选和安装生命周期证据有效，所有交付依赖在包内或明确可信依赖清单内。

## Q15 最终安装版双端真实验收

**文件：** 最终双端实际安装、`RUN/installed-acceptance/`、用户确认与恢复记录。消费 Q14 实际身份和就绪窗口。

- [ ] 用户保存退出后按已确认范围更新；完整当次备份并核对安装文件来自 Q14。不得从源码启动后冒充安装版通过。
- [ ] ZCode 菜单→选图→编辑/ROI/zoom/明暗/表面参数→保存/导出→原导入器只保存→明确应用；同项目分别导出 Cherry 并经正式入口应用。
- [ ] 暂停时编辑/导入不注入；继续先兼容校验；编辑器关闭不停止皮肤。两端分别恢复，另一端状态/偏好/恢复文件不变。
- [ ] 验证项目管理全部入口与可编辑包往返；焦点/构图/四套/人物/宽窄/保护区/正常重开由用户记录。Q07/Q09 同身份且未受变化影响的记录可复核复用。
- [ ] 新故障先保存证据及恢复状态，进 Q16；最终保留外观由用户选择，测试结束不擅自把用户喜欢的状态换回默认。

**通过：** 最终安装件的双端实际使用/隔离/恢复与用户视觉都成立。手工观察标“无退出码”，不伪造 exit 0。

## Q16 50 组终验与内置返工循环

**文件：** 随附验收矩阵、`RUN/ACCEPTANCE_INPUT.md`、`RUN/RESULTS.md`、`RUN/FAILURES/F-<case>-<n>.md`、`RUN/REWORK.md`、`RUN/VERDICT.md`。这些是运行记录，不是新一轮总体设计。

- [ ] 从最后工件冻结验收输入；建立 I01–I03、A01–A06、P01–P04、U01–U07、Z01–Z09、C01–C09、X01–X07、R01–R05 全部50组及参数分支记录。附加 provider/CAS 回归作为必需补充，不挤掉原项。
- [ ] 先离线/隔离，再载荷/安装，最后真实宿主/用户；复用同身份有效原始证据，变化影响层重验，不强迫重复无变化的长测和用户点击。
- [ ] M01–M05 在丢弃式副本验证断言真能抓错：子进程环境、执行依赖身份、UI实际导出接线、来源单位、导入不应用/暂停。已有同身份有效 RED 可复用；变异不能进入候选。
- [ ] FAIL 立即落问题单：期望/实际、原始命令/exit/输入hash、最后正确与第一错误边界、已证事实/假设、恢复状态、归属 Q 单及最短 RED。原失败不改写为 PASS。
- [ ] 分类 TEST/ENV/ARTIFACT/IDENTITY/CONTRACT/WIRING/COMPAT/RESTORE/CRASH；仅改变一个变量做区分实验。未知原因写未证实，不归咎模型/系统、不清缓存重装碰运气。
- [ ] 在对应 Q 单最小修复，跑“原失败→同类与反向→受影响集成→新候选/必要实机”，回本单复验；产品字节变化必登记新身份与旧证据失效范围。
- [ ] 三次同问题修复仍失败，停止第四次盲补；具体记录假设被哪些证据否定、缺哪个能力、下一最小判别动作。在原问题单内裁决，不另起一套总体方案。能独立推进的支线继续。
- [ ] 所有必测与恢复/身份/用户确认齐全且失败0才 PASS；任一实际 FAIL 总结论 FAIL；无FAIL但缺证/NOT_RUN/BLOCKED则 INCOMPLETE。不能用 LIMIT_ACCEPTED/预期通过替代严格 PASS。

**返工影响表：**

| 修改层 | 至少复验 |
|---|---|
| 文档/记录修正，产品字节未变 | 引用、原件hash、结论范围；不无故重跑宿主 |
| reader/CAS/桥/provider | Q04/Q05、A05/A06、C01–C03/C07/C09、执行集合与候选身份；所有受影响 G1–G4 |
| profile/宿主版本/选择器 | I03、对应端范围/保护区/重启/应用门，重新取得兼容证据 |
| 图像/来源/构图/导出/IPC | A04、U01–U07、X02/X03/X05/X07、受影响端视觉 |
| 安装依赖/生命周期 | I01、P01–P04、R01–R05、X01/X04/X06及真实更新启动 |
| 测试/验证器自身 | 原失败和相应 M 检查、所有依赖该验证器的通过记录 |

## Q17 本机交付与一次性结项

**文件：** `RUN/FINAL-DELIVERY.md`、使用/恢复说明、最终台账；实际包留既有输出根，不复制私人原件到公开目录。

- [ ] 核对 Q16 总 PASS、50组全部分支及新增读源必需回归，失败返工闭环；运行身份与交付身份逐件一致，不把 A 包的通过移给 B 包。
- [ ] 列最终两端源码 SHA、构建 SHA、payload/Setup/编辑器pin/bridge/provider/profile/宿主摘要，实际安装路径和可点击入口。
- [ ] 写最短日用步骤：选图编辑→保存→明确应用；默认/暂停/继续；两目标导入导出；独立恢复。正常使用不需源码、终端或手动 DevTools。
- [ ] 交付本次备份位置与实际可执行恢复命令、使用条件、已验哈希；记录用户保留外观、已测版本边界和未公开发布状态。旧包/证据/备份不擅自清理。
- [ ] 在总台账追加最终结果及所有 Q→原任务映射；仓内本地流水不提交，产品提交范围精确。只有严格 PASS 才写“本机双端结项完成”。否则交付一张剩余失败表与精确续接点，不报完成率。

## 命令合同与执行记录

以下为执行期已存在入口；RUN/CW/ZW 和最终候选路径在 Q00/Q06/Q14 后填入实际绝对值，不使用旧 PID/旧 r18 命令。

```powershell
# 在已认领 Cherry 工作树中，先取得项目可信 Node。
. .\scripts\trusted-runtime.ps1
$cherryTrustedNode = (Get-CherryTrustedNode).Path
& $cherryTrustedNode --test tests/host-uia-contract.test.mjs tests/host-application.test.mjs tests/native-evidence.test.mjs tests/native-proof.test.mjs
$focusedExit = $LASTEXITCODE
if ($focusedExit -ne 0) { throw "Cherry focused tests failed: $focusedExit" }
& powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\tests\run-tests.ps1
$suiteExit = $LASTEXITCODE
if ($suiteExit -ne 0) { throw "Cherry full suite failed: $suiteExit" }
```

Q04 新增测试须加入上述定向选择及原 registry。desktop 读取本地 package.json 的 test/typecheck/build，以项目钉定工具运行；不得下载最新工具替代锁定版本。ZCode 全量入口为 `windows/tests/run-tests.ps1`，先读脚本确认 fixture 与进程副作用，再以 RemoteSigned 运行。载荷验证复用 `scripts/verify-payload-launch.mjs --check-only --payload <实际路径>` 和 `scripts/verify-payload-roundtrip.mjs --payload <实际路径>`，由可信 Node 执行。

原生 VerifyOnly/六例必须绑定实际 BridgeExe、IdentityFile、RunBFile、EvidenceDir 与当前 provider 合同；新增来源后不能继续用只比较 UIA 的旧 VerifyOnly 给逻辑恢复签绿。驱动/验证器在 Q05 同步改好，命令在 Q06 填实验证。

每次执行保存：命令、cwd、解释器路径/版本、起止时间、stdout/stderr、外层exit、源码/构建/工件/宿主身份、输入与输出文件hash。未返回/中断/超时不虚填0；负向必须在正确门拒且副作用正确。

## 执行者的停止与继续规则

1. 已授权且输入齐全的任务按依赖连续做，内部实现取舍记录在原任务/问题单即可，不逐步请示。
2. 需要用户操作时一次列本窗口所有动作；可自动完成的准备先完成。窗口缺位不阻塞独立离线支线。
3. 用户编辑冲突、无法证明恢复、安全边界变化、不可用真实运行能力才停受影响动作；给具体原始证据和缺项。
4. 新故障使用 Q16 返工循环；不要每次交回“下一步可选方案”就结束。计划可以覆盖全部工作，但不得承诺未知外部条件一定满足。
5. 本单 checkbox 只有执行证据到位才勾选；本次编写未勾任何实施项。

## 编写交付自检

- Q00–Q17 共18项，编号唯一，93个待执行步骤；没有预填实施完成。
- 随附原矩阵50组编号唯一、断言原文完整保留；另列L01–L08读源/恢复必需回归，M01–M05沿原有效性合同执行。
- 本次已检查13个关键既有实现/执行入口存在；拟新增文件明确标planned，不把测试文件名误作生产模块。
- 三个既有工作树在文档交付检查时仍干净；本次只写本设计/工单/矩阵/交接，不运行产品测试或宿主操作。
- 覆盖原C05、Z02/Z03、A00、X01–X06、V00–V05和F00；已完成的C01–C04和K02按证据复用。
- 代码围栏配对、没有TODO/TBD设计占位；RUN/CW/ZW属于Q00必须产出的运行输入，不是留给用户猜测的命令参数。
