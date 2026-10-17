# Dream Skin 2.0 双端统一收口：全工程交接与问题排障白皮书

> **为外部开源接手开发者准备的快速定位与全景工程指南**  
> 本文档所有路径已全部解耦为仓库相对路径，任何开发者克隆本仓库后即可直接研读与编译复现。

---

## 1. 一句话项目全貌
本项目旨在为 **Cherry Studio (v2.1.4)** 与 **ZCode (v3.15.3)** 交付一套本机日常可用、零文件篡改、具备绝对可逆恢复能力的无侵入式主题换肤系统（Dream Skin 2.0）；当前底层工程与离线测试已 100% 全绿，Cherry 实机注入已打通并处于换肤生效态，桌面已收拢为单一原生 GUI 工具，核心待解决的是上游模型协议变动导致的 Agent 挂起，以及右侧聊天视口的死黑透明度层级收尾。

---

## 2. 仓库核心依赖文件映射索引（接手先读）

| 依赖分类 | 原始本地路径 | 仓库内相对路径 | 核心作用与阅读重点 |
|---|---|---|---|
| **技能与调度准则** | `~/.agents/skills/muse/SKILL.md` | [`docs/memory-vault/muse-terminal-agent-skill.md`](docs/memory-vault/muse-terminal-agent-skill.md) | Meta Muse 终端调度契约，防管道破裂与死等纪律 |
| **网关拓扑定案** | `~/.zcode/.../command-code-go-gateway-topology.md` | [`docs/memory-vault/cmdc-gateway-topology.md`](docs/memory-vault/cmdc-gateway-topology.md) | 8787 本地网关协议转换、Responses 接口与模型白名单 |
| **桌面整洁纪律** | `~/.zcode/.../desktop-clean-single-exe-preference.md` | [`docs/memory-vault/desktop-clean-discipline.md`](docs/memory-vault/desktop-clean-discipline.md) | 严禁散落 .bat，必须打包单一 exe 归类收拢铁律 |
| **权威只读定案** | `.../PAIR-VERDICT-k02pair-01.md` | [`docs/evidence/PAIR-VERDICT.md`](docs/evidence/PAIR-VERDICT.md) | 权威只读对照 VALID_PAIR 签署证据 |
| **最终实施计划** | `.../Dream-Skin剩余任务一次性结项-实施计划.md` | [`docs/specs/IMPLEMENTATION-PLAN.md`](docs/specs/IMPLEMENTATION-PLAN.md) | Q00–Q17 端到端全量结项流水线工单 |
| **总工程台账** | `.../TASK_PROGRESS.md` | [`docs/specs/TASK_PROGRESS.md`](docs/specs/TASK_PROGRESS.md) | 项目完整的历史里程碑与测试台账 |
| **技术突破论文** | `.../CODE-MIRROR-6-BREAKTHROUGH.md` | [`docs/CODE-MIRROR-6-BREAKTHROUGH.md`](docs/CODE-MIRROR-6-BREAKTHROUGH.md) | CodeMirror 6 内部虚拟 DOM 与 UIA 投影失真破案记录 |

---

## 3. 重大技术定案与时间线（已定案切勿重推重查）
- **2026-10-16 架构真相大白**：现场 B2ce 探针 100% 证实 Cherry Studio 的自定义 CSS 编辑器为 **CodeMirror 6 (CM6)**（祖先链 `.cm-content.cm-lineWrapping` -> `.cm-scroller` -> `.cm-editor` -> `#setting-appearance-custom-css`），彻底推翻原生 textarea 与 Monaco 假说。
- **2026-10-16 读侧失真定理签发**：证实 CM6 内存文档在空内容时逻辑值为 0 字节（Hash `e3b0c442…`），而 Windows UIA TextPattern 抓取时会自动追加换行读为 1 字节（Hash `01ba4719…`）。此前观察到的“换行丢失与空格颠倒”本质是 UIA 跨虚拟行抓取的投影失真，底层数据完好。
- **2026-10-16 18:21 完成 `VALID_PAIR` 签署**：W0–W3 五门全过，时序闭环且窗口内零漂移，获用户 W4 未触碰确认，正式晋级为 `VALID_PAIR`。
- **2026-10-17 离线全量测试全绿**：Cherry 官方 45 门 + 474 离线全通，桌面 19/231 全通；ZCode 跑通 17 门 + 27 项回归，无一报错。
- **2026-10-17 桌面整洁治理收尾**：清除所有散乱批处理，用 C# 编译出单一 64 位 GUI 工具 `DreamSkinMaster.exe`。
- **2026-10-17 实机注入与当前状态**：Cherry Studio 实机已成功注入 Dream Skin（Hash `8c6dafbe…`，975 字节）；ZCode 状态根 22 个文件已在 D 盘完成全量只增备份。

---

## 4. 关键源码与可执行入口速查（仓库相对路径）
- **统一 GUI 总控台**：
  - 源码：[`src/DreamSkinMaster/DreamSkinForm.cs`](src/DreamSkinMaster/DreamSkinForm.cs)
  - 编译脚本：[`src/DreamSkinMaster/build.bat`](src/DreamSkinMaster/build.bat)（直接双击即可调用系统 csc 编译生成 `DreamSkinMaster.exe`）
- **Cherry Studio 换肤核心**：
  - 样式注入驱动：[`src/cherry/apply-cherry.mjs`](src/cherry/apply-cherry.mjs)
  - 基线还原驱动：[`src/cherry/restore-cherry.mjs`](src/cherry/restore-cherry.mjs)
  - 生产级自动化 IPC 桥：[`src/cherry/host-bridge.mjs`](src/cherry/host-bridge.mjs)
  - 50 组配色算法底座：[`src/cherry/preset-themes.mjs`](src/cherry/preset-themes.mjs)
- **ZCode 客户端换肤核心**：
  - CDP 远程调试热挂载器：[`src/zcode/injector.mjs`](src/zcode/injector.mjs)
  - 受管启动引导：[`src/zcode/start-zcode.ps1`](src/zcode/start-zcode.ps1)
  - 一键还原引导：[`src/zcode/restore-zcode.ps1`](src/zcode/restore-zcode.ps1)

---

## 5. 纪律与红线
1. **桌面绝对整洁铁律**：严禁在桌面散落多个临时批处理或散装脚本，必须打包为单一 exe，桌面仅保留唯一干净的快捷方式。
2. **放手全自动原则**：除不可避免的退出重开与肉眼视觉验收外，严禁让用户频繁开 DevTools 贴代码，一切内部桥调用必须通过自动化管道自主闭环。
3. **零文件破坏与真实可逆**：绝不修改两款官方软件的原始二进制及签名；所有写入必须是外部无侵入的；恢复必须通过 CAS 条件严格执行。
4. **测试不造假、不虚报全绿**：未执行项目必须在总账本中严格保持 `NOT_RUN`。

---

## 6. 当前阻塞与未闭环清单（按优先级接手推进）

### P0 · 上游模型废弃引发的 Agent 协议适配
- **现状**：上游服务商将 `muse-spark-1.3-contributor-free` 标记为 HTTP 410 Deprecated。
- **解法**：在配置文件中切换与网关完全兼容的模型，或直接在总控层调用本地生产级脚本（`host-bridge.mjs`）驱动，避免因大模型接口故障阻塞宿主任务。

### P1 · Cherry Studio 右侧主聊天区死黑遮挡（视觉穿透规则已就绪）
- **现状**：左侧列表栏已成功透出半透明白发动漫壁纸，但右侧主视口受暗色子容器（`bg-background`, `bg-card`）遮挡。
- **解法**：已在 `src/cherry/apply-cherry.mjs` 中更新全通透规则，将 `main` 与 `chat-container` 强制透明化，执行一次刷新即可实现壁纸全屏贯穿。

### P2 · ZCode 客户端实机换肤与九步视觉签收
- **解法**：通过 `src/zcode/start-zcode.ps1` 带 CDP 调试端口拉起带皮肤的 ZCode 并激活托盘，协助用户进行九步 14 格的视觉体验验收。

### P3 · 全量 50 组预设主题打包
- **解法**：将 `src/cherry/preset-themes.mjs` 与 ZCode 的 50 组配色规范做最终的一体化集合固化，结束全部开发任务。
