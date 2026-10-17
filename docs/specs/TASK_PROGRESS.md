# Dream Skin 双端统一收口总台账

日期：2026-10-15（Asia/Shanghai）。本文件只保留本地，不入Git。

## 当前阶段与授权

- 当前阶段：用户已批准实施并授权执行全部工单；Cherry 支线 C01/C02/C03 已提交，C04 工程终验进行中。
- 用户已授权：读取两个对话状态；编写统一方案、工单及给其它Agent的交接材料；按实施计划执行
  C01–C05、Z01–Z03、A00、X01–X06/F00 与 V00–V05（含离线代码/测试/构建/只读采证；真实宿主写操作
  按既有 A1–A3 授权与本次具体窗口执行，用户亲手做重启/退出/视觉签收）。
- 后续授权以用户实际消息为准，不由工单的checkbox或本台账推定。已有历史授权逐项核对，不重复索要，也不扩大。
- Cherry 执行现场：隔离工作树 `C:/Users/Janson/Desktop/换皮/.lemon/dual-skin-closeout-20261015/wt-cherry`，
  分支 `codex/dual-skin-cherry-20261015`；原仓工作目录不动，不推送不合并。

## 本轮文档产物

- 设计：`C:\Users\Janson\Desktop\换皮\文档\柠檬\设计\2026-10-15-Dream-Skin双端统一收口-设计方案.md`
- 工单：`C:\Users\Janson\Desktop\换皮\文档\柠檬\工单\2026-10-15-Dream-Skin双端统一收口-实施计划.md`
- 入口：`C:\Users\Janson\Desktop\qoder对话\2026-10-15-Dream-Skin双端统一收口-交接提示词.md`
- 最终校验：`C:\Users\Janson\Desktop\换皮\文档\柠檬\设计\2026-10-15-Dream-Skin双端最终校验与返工-设计方案.md`
- 校验/返工工单：`C:\Users\Janson\Desktop\换皮\文档\柠檬\工单\2026-10-15-Dream-Skin双端最终校验与返工-实施计划.md`

## 基线（易变项接手重查）

| 仓库 | 分支/源码HEAD | 本轮编写时工作树 |
|---|---|---|
| ZCode-Dream-Skin-2.0 | feat/zcode-dream-skin-2 / 01fdb07824cbaab021f6677578bf7f3aad720477 | 干净 |
| Cherry-Dream-Skin-2.0 | feat/cherry-2.0 / 9bfce851316e8b56421084645f9a5700679b924a | 干净 |

本轮未新建分支/worktree、未提交、未改两个仓库文件；只在仓外新增上述文档和此台账。安装/宿主/测试事实来自今天核验报告，当前编写未重新跑产品测试或操作宿主。

## 任务状态

| 批次 | 工单 | 状态 | 开始条件 |
|---|---|---|---|
| 接管 | P00 | 已完成（现场核对+隔离工作树认领，2026-10-15） | 用户实施确认与现场核对 |
| A-Cherry | C01 | 已完成并提交 `57fb8d7`（子进程 PSModulePath 隔离） | P00 |
| A-Cherry | C02 | 已完成并提交 `23ce184`（桥集合身份；BOM 修后定向 29/29、五文件 91/91） | C01 |
| A-Cherry | C03 | 已完成并提交 `5c5e6c3`（/3 证词+应用门绑定集合；Node 72/72，桌面门 10/10，tsc 0） | C02 |
| A-Cherry | C04 | 已完成并提交 `f0bbe86`（r19：122 件/manifest `ddd4a7b8…`，起窗＋回环 PASS；全量 45 门 474/474） | C03 |
| A-Cherry | C05 | 已执行未通过（G1首例conflict，宿主已恢复验证；报告 `TOTAL/C05-acceptance-20261015.md`；返工待R1–R3裁决） | C04；真实宿主段按现有授权/具体窗口 |
| A-ZCode | Z01 | 已完成（只读诊断，报告 `TOTAL/Z01-readonly-diagnosis-20261015.md`；宿主/候选/载荷与核验一致；私人根现为 22 文件无 state——与核验 28 文件矛盾未解，待问用户） | P00 |
| A-ZCode | Z02/Z03 | 未执行（Z02 受控方案已就绪，待用户窗口＋§5 澄清） | Z01；真实动作须具体可审窗口 |
| A基线 | A00 | 未执行 | 两端现有产品实际签收或用户明确接受限制 |
| B双目标 | X01/X02/X03/X04/X05/X06 | 未执行 | A00；X01只读/纯合同可提前 |
| 总交付 | F00 | 未执行 | A/B证据矩阵齐全 |
| 独立终验/返工 | V00–V05 | 未执行 | 最终工件可核、真实层按具体窗口；F00成功必须引用V05 PASS |

C04 完成明细（2026-10-15，工作树 `wt-cherry @ f0bbe86`，干净）：
- 桥来源：C01–C03 未改 `host/`（`git diff 9bfce85..HEAD -- host/` 为空）。先核实现桥字节与主仓 10-11
  钉定构建逐字节一致（FlaUI pin `fd7cc64…`、interop `10.19041.0`、SDK `9.0.314`）并冻结一版；
  后为让 wire 测试真跑（原 skip：缺 `host/build/flaui-lib`），把主仓已验钉定库
  （三 DLL 哈希与 `build-manifest.json` 记录一致）复制进工作树 `host/build/`（gitignored），
  wire 测试 9/9 真跑通过。副作用：该测试每次运行都用 dotnet 重编桥（SDK 9.0.314，csproj 无
  PackageReference，离线可编），故冻结改为“全套件之后最后重发清单”：10-11 字节备份于
  `wt-cherry/.lemon/c04-bridge-orig/`，最终冻结以套件后重发的那版为准。
- 冻结集合（ interim，重编后）：set `d430f30407ed5b8bd2dae19535ba0cf3cca9973b223ebbb0af49da3f697523ef`，
  manifest `5c39c098f8d831ed22c4d8a96a0e21f0b007f866d03941a8bc1f20288985b5d2`，BOMFREE=true，
  7 件同名同尺寸，bin 内三 FlaUI 与钉定库一致；证据 `wt-cherry/.lemon/c04-bridge-freeze.json`。
  最终版待全套件后再重发（wire 测试每次重编会换字节，清单必须最后发）。
- 桌面：vite 构建×3 exit 0（dist 含 /3 串），`tsc --noEmit` exit 0，vitest 全套 19 文件 231 用例 exit 0，
  证据 `wt-cherry/.lemon/c04-desktop-full.log`。
- 当前宿主（只读）：Cherry 2.1.4.0，exe `18c07435…da55`（246206976 B），
  asar `1f66ef79…68c9b7`（301070637 B），与设计钉一致；RunB 239438 OK。
- 全量门修复（已随 C04 提交）：① `window_not_found` 出口分类缺失（基线即红，
  非本轮引入）：`src/cli.mjs` CODES 加 `window_not_found: 4`，`tests/exit-codes.test.mjs` CLASSES[4] 同加；
  ② `tests/desktop-toolchain.tests.ps1` 钉死数 229→231（C03 新增两条门用例；payload-layout 两条随冻结恢复执行）。
- 最终全量（冻结后）：`SUITE_PASS registered=45`，`.mjs` 474/474 fail 0 skipped 0（含 wire 真跑 9/9），
  `.ps1` 九门双模式全过；原生六例 `HOST_UIA_NATIVE_SKIPPED cases=6`（待 C05）；证据 `.lemon/c04-node-final.log`。
- 最终冻结（套件后重发，与 interim 同值，dotnet 输出确定）：set `d430f304…23ef`、
  manifest `5c39c098…85b5d2`，BOMFREE=true；r19 载荷 `bridgeRuntime` 与之逐字一致。
- r19：`.lemon/payload-candidate-r19`（主仓已有 r2–r14/r16–r18，r19 全局未占用；r18 不动），
  122 成员/123 文件/421831667 B，manifest `ddd4a7b841e0f1bcfa5559680c19f1d93611d09b1c656905878574112655aea8`，
  roles 9/9 closure 31 external 0 electronPacked=true，起窗 PASS＋回环 PASS（拒篡改）。
- C04 报告：候选工程通过；真实宿主六例/profile/重启/视觉尚未跑（C05）。
- 操作包：`docs/live-roundtrip-operations.md` 追更 r19 节（含 2.1.4 身份、冻结集合、G1 命令、停止条件）。

C05 执行明细（2026-10-15，工作树 `wt-cherry @ f0bbe86`，零源码改动，干净）：
- 前置全绿：宿主 2.1.4.0（exe `18c07435…`/asar `1f66ef79…`/301070637 B/9 进程）与 C04 钉一致；
  r19 只读复算 manifest `ddd4a7b8…`/122 件/problems 空/桥集合一致；身份刷新 exit 0。
- G1：`HOST_UIA_NATIVE_INCOMPLETE cn-multiline-65=conflict(host_holds_a_third_value) stopped_at`
  首例、后 5 例 not_run（驱动/外层 exit 1）；证词按设计未写。基线备份 1 B（`0A`，`01ba4719…`）。
- 根因（实证）：UIA 回环非字节精确——163 B 样本稳定读回 162 B（3×`0A 20`→`20 0A` @0x12/0x8B/0x9E
  ＋尾 `0A` 丢，`80c323e4…`，15 分钟复读不变）；另发现 read-after-write 竞态（恢复 CAS 即时回读
  indeterminate、稍后 RESTORED）。settle 重试可修时序类、修不好首例（已钉死防误修）。
- 恢复：CAS 写回基线后驱动 `--verify-only` exit 0 `HOST_CSS_RESTORED`，
  官方 `-VerifyOnly` 门 `HOST_UIA_NATIVE_VERIFY_STATUS RESTORED` exit 0；备份未覆盖，无残留。
- G2/G3/G4 NOT_RUN（G1 前置红＋需用户探针/重启/视觉动作）；profile 保持 `supported:false` 未晋级（正确）。
- 离线退出码终验：6 文件 102/102 exit 0；全量套件未重跑（wire 测试重编桥，C04 结论仍有效）。
- 返工提案 R1–R4（桥 settle 重试/H2a-H2b 区分实验/设计裁决/重跑 G1）见 C05 报告 §5，待用户裁决。

用户后续要求已补齐：50个必测用例组/分支断言、成功/失败/未验判定、最小根因实验、失败返工单、失效证据与复验规则。新增6项校验工单不改原17项开发工单计数。本轮仍只写文档，没有运行产品校验，也没有实际发现并修复新故障。

## 下一个接手点

其它Agent完整读取设计、工单、交接入口及今天两份报告，先P00核对授权/HEAD/dirty/在途执行者；若用户已明确批准，连续推进可独立离线任务。旧稿里的r18、1.x根目录、旧PID和无state条件不可直接执行。

## 文档自检

- 总工单17项、77个待执行步骤，无预填完成项；任务ID唯一，A/B依赖与停止条件已检查。
- 已核对引用的本地绝对路径存在、代码围栏成对、没有TBD/TODO占位；拟新增源码与既有路径分开标记。
- 已复核实际payload核验参数、桌面API/preload位置、native六例入口；导出动作固定到现有白名单新增项，不留下两套并行实现选择。
- 再次核对两个业务仓工作树干净，未发生源码或安装变更。此处仅为文档检查，不是任何产品测试通过记录。

## 遗留与明确未做

- ZCode新官方版本兼容、旧state与活体关系、九步14格待记录。
- Cherry子进程环境、完整桥集合身份、新候选、真实G1–G4/profile。
- 跨端编辑/导出/入口与最终安装版QA尚未完成。
- localization继承红、Get-FileHash未复现差异、GPU未定因、公开许可材料缺件继续分立留账。
- 全部旧包/备份/证据/失败中间目录保留；不推送合并公开发布。

---

## 2026-10-16 一次性结项 Q00–Q17（本批追加，只记新账，不改旧结论）

- 入口：设计 `文档/柠檬/设计/2026-10-16-Dream-Skin剩余任务一次性结项-设计方案.md`；
  工单 `文档/柠檬/工单/2026-10-16-Dream-Skin剩余任务一次性结项-实施计划.md`；
  矩阵 `文档/柠檬/工单/2026-10-16-Dream-Skin剩余任务一次性结项-验收矩阵.md`。
- 本批 Q→原任务映射：Q00→P00/K00；Q01/Q02→K03；Q03→K04路线；Q04→N03/N04/K04；
  Q05→C03/K04；Q06→C04/K05；Q07→C05；Q08→Z02；Q09→Z03；Q10→A00；
  Q11→X01/X02；Q12→X03；Q13→X04；Q14→X05；Q15→X06；Q16→V00–V05；Q17→F00。
- Q00 接管（2026-10-16）：三树新鲜复核与工单快照一致且干净
  （wt-cherry f0bbe861…19ff / wt-c05-roundtrip 3df6451f…a4ab / wt-zcode 01fdb078…0477，
  stash 均空）；PAIR 复算 VALID_PAIR（逻辑 0B e3b0…/UIA 三份 1B 0A 01ba…，18 键齐全）；
  C05 首例 FAIL 保留、其余 NOT_RUN。
- 执行树（自有隔离，不占原树）：CW=`TOTAL/wt-closeout-cherry`（codex/closeout-cherry-20261016 @ f0bbe86）；
  ZW=`TOTAL/wt-closeout-zcode`（codex/closeout-zcode-20261016 @ 01fdb07）；
  RUN=`TOTAL/closeout-20261016-q00q17/run-20261016-01`（输入见 RUN/EXECUTION-INPUT.md）。
- 旧末尾“下一步”（P00/旧排程）不是当前状态；当前按 Q00–Q17 推进。
- Q01 完成（2026-10-16）：K03 执行包冻结于 RUN（k03-runner.mjs + k03-input.json +
  k03-operations.md + D 样本 9B/0aaa… + 诊断桥 7/7 复核）；20/20 stub 测试 GREEN
  （RED 已观察）；stub 双路径演练通过（R1→恢复 verified 写2次 / 写前拒绝零写）。
  Q02 待 W-A 窗口授权（申请文本见 k03-operations.md §10），不阻塞独立支线。
- Q03 先行只读结论（RUN/reader-decision.md，PRELIMINARY）：持久化库读源因铁律否决
  （cherrystudio.sqlite 为数据库禁读）；主进程无调试端口；cmTile 诊断可用、产品否决；
  正式路线待 Q02（R1→读侧投影/Cherry阻塞候选；R2→写侧修复/UIA沿用）。
- Q08 离线部分：ZW 修基线红 `zcode-upstream-pin`（2ea8811：theme-gallery 钉 LF +
  注册表 13 项重算为 blob 哈希；根因为 CRLF/LF 混记，零内容漂移；聚焦测试 PASS）；
  私人根新鲜清单 22 递归文件/4877918B/无 state（与 Z01 一致；11/14/22/28 口径已说明，
  见 RUN/q08-inventory.md）；宿主 3.15.3.8237 身份无漂移；ZW 全量套件重跑中。
  Q08 窗口动作（退出/备份/受管采证）与 Q09 待 W-C。
- Q00 接手复核（2026-10-17 凌晨，新会话，见 RUN/session-20261017-q00-note.md）：
  三树 HEAD/dirty 与快照一致且干净；PAIR 复算 VALID（逻辑 18 键 0B e3b0…/UIA 三份 1B
  01ba…）；D 样本 9B/0aaa…；r19 manifest ddd4a7b8…/桥集合 d430f304…/诊断桥 7bd45f9e…
  均一致；Cherry 2.1.4.0（exe 18c07435…/asar 1f66ef79…，10 进程连续运行）与
  ZCode 3.15.3.8237（exe b0acafed…，PID 13056 连续运行）无漂移；可信 Node v22.23.1。
  CW=`codex/closeout-cherry-20261016 @ 2c456a2`、ZW=`codex/closeout-zcode-20261016 @ 10b53f3`，
  干净，无并发执行者。C05 首例 FAIL 保留，其余 NOT_RUN。
- Q01 复验：k03 stub 测试可信 Node 重跑 20/20 exit 0；k03-input.json 9 路径全存在；
  W-A 包预检全绿（D/PAIR/双桥集合/宿主身份/连续运行期），待窗口授权与用户三次逻辑粘贴。
- CW 桌面链打通：npm ci（lockfile 钉定 227 包 exit 0）→ tsc 0 → vite×3 构建 0 →
  vitest 初跑 18/19（payload-layout 缺桥清单，系新鲜树未编桥，非回归）→
  按 build-bridge.ps1 -EmitRuntimeManifestOnly 补发 CW 桥清单（7 件）→ payload-layout 2/2。
  CW 桥 exe/dll 与 CBASE 字节不同（嵌入路径差异，预期内；FlaUI×3/deps/runtimeconfig 全 MATCH），
  CW 候选集合待 Q06 独立冻结。CW 全量 `cherry-baseline-suite-3.log` 已绿：
  SUITE_PASS registered=45，SUITE_EXIT=0（25 分钟；node 474/474 fail 0 skip 0；
  桌面 19 specs/231 tests；真窗 proof 双模式；原生六例 SKIP 待 W-B）。
  套件后重发 CW 桥清单（7 件，自有集合 `d88c75a4…90f3d`）。
- Q08 离线收官：ZW 全量 `zcode-baseline-suite-5.log` SUITE_EXIT=0（20.5 分钟，
  17 命名门 + 27 静默 2.0 回归 + 同步/注入器/个人皮肤载荷检查全过；唯一 SKIP 为
  STAGE_BUILD_SKIPPED 离线声明）。ZW 三笔提交均为非装船字节（测试/开发工具/上游记录），
  不重建；冻结候选 e7b0853 ↔ Setup-v1.5.18（116428582 B，8916fa4b…，SHA256SUMS 一致，已复算）。
  W-C 操作包见 RUN/q08-wc-operations.md（P1–P6 + 受管采证 + 九步 14 格 + 回滚预案）。
- Q11 只读前置：ZCode 目标合同草案见 RUN/zcode-target-contract-DRAFT.md
  （focus/dim direct、zoom/blur/ROI/EXIF 烘焙、colors 部分键 direct+缺键省略、
  opacity/radius 待 SafeCSS 验证、appearance/safeArea/taskMode 默认；产品代码待 A00）。
- Q16 脚手架：RUN/ACCEPTANCE_INPUT.md（输入冻结索引）+ RUN/RESULTS.md（50 组 NOT_RUN 表）
  + RUN/FAILURES/（空）已备；判决定待实机。
- 当前阻塞（外部窗口）：W-A（Q02 单次 D 写+恢复）、W-B（Q07，待 Q02→Q06）、
  W-C（Q08/Q09）、W-D（Q15，待 Q14）。离线支线均已推至窗口前最后一步。
