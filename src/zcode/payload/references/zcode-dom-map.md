# ZCode DOM Map（实机实测）

- 采集方式：`zcode-poc.ps1 -DomInventory`（只读，CDP `Runtime.evaluate`，不注入任何东西）
- 采集时间：2026-09-29
- 采集目标：`file:///…/out/renderer/index.html`（ZCode 主 renderer，唯一 page target，评分 4）
- ZCode 版本：`3.14.4.7912`（`F:\AI\ZCode\ZCode.exe`，SHA-256 `2cd9f067…`，签名指纹 `6F7B147D…`）
- 水合证据：`waitedMs=7442`，body 元素数采样 `[9,9,…,12,12,337,613,796,796]`，`startupMarkers=[]`，`workspaceEvidenceTotal=38`，`settledSamples=2`
- 原始证据（不进仓库）：`.lemon/evidence/zcode-dom-inventory.json`、`zcode-dom-inventory-run.json`、`zcode-dom-inventory.log`
- 语义指纹基线：`ddc4dee432144a1c6974df23d6e1392e`
- 语义指纹历史（同版本两次实测，均记录在 profile 的 `fingerprint.observedDigests`）：`ddc4dee432144a1c6974df23d6e1392e`（首采，body 796 / 共 1087）、`60be535b4d32a2e0d438da925a915e33`（复采，body 744 / 共 1035）。两次仅差一个可选表面属性对（`data-cron-task-icon` ↔ `data-composer-trailing-actions`），因此指纹漂移只是审计 warning，不是失败：兼容身份由 `supportedVersions` + `requiredSelectors` + 渲染器 URL 族承载。

## 采集覆盖范围（重要）

本次只采到**一个**工作区状态（侧栏 + 主区 + 输入区，未打开文件、未开终端、无弹窗）。因此：

- 标注「实测」的选择器 = 本机本次确实存在并计数（见下表计数）。
- 标注「未实测」的选择器 = 设计上属于禁止区，但**本次未出现**，其选择器来自通用命名而非实测：`.monaco-editor`、`.xterm`、`iframe`、`canvas`、`webview`、`[role="dialog"]`、`[role="menu"]`、`[role="tooltip"]`、`[data-radix-popper-content-wrapper]`。其中前五项是设计明令禁止区，**必须常驻 profile 的 `doNotTouch`**，不因单次采集未见而缺席。
- **不声称跨版本稳定**：稳定性由 `supportedVersions` + Compatibility Probe 三态判定兜底，而不是靠"看起来稳定"。

## 选择器清单

计数 = 本次采集的 `querySelectorAll` 命中数（0 表示本次未出现）。

### SAFE（可换肤：背景、表面、边框、圆角、阴影、透明度）

| 选择器 | 计数 | 实测 | 稳定性 | 修改风险 |
|---|---|---|---|---|
| `[data-workspace-shell]` | 1 | 是 | 语义锚点，最外层工作区外壳 | 低：只改背景/表面色 |
| `[data-root-workspace-surface]` | 1 | 是 | 语义锚点（值 `interactive`） | 低 |
| `[data-desktop-window-frame]` | 1 | 是 | 语义锚点 | 中：windows 窗框，只允许背景/边框色 |
| `#sidebar` / `[data-testid="sidebar"]` | 1 / 1 | 是 | 双锚点（id + testid 同时命中） | 低 |
| `[data-workspace-sidebar-panel]` | 1 | 是 | 语义锚点 | 低 |
| `[data-purpose-section-list]` | 1 | 是 | 语义锚点 | 低 |
| `[data-purpose-section-drag-handle]` | 2 | 是 | 语义锚点（值 `projects`/`conversations`） | 低：拖拽把手只改颜色，不改尺寸 |
| `[data-task-row-metadata]` | 20 | 是 | 语义锚点 | 低 |
| `[data-task-title-marquee-track]` | 20 | 是 | 语义锚点 | 中：跑马灯轨道，不得改宽度/溢出 |
| `main` | 1 | 是 | 原生语义 | 低：主区背景 |
| `[data-workspace-conversation-frame]` | 1 | 是 | 语义锚点 | 低 |
| `[data-panel]` | 6 | 是 | 语义锚点 | 低 |
| `header` | 1 | 是 | 原生语义 | 低 |
| `[data-workspace-header-variant]` | 1 | 是 | 语义锚点 | 低 |
| `footer` | 1 | 是 | 原生语义 | 低 |

### CAUTION（逐项验证：输入区、菜单、弹窗、提示框、按钮状态）

| 选择器 | 计数 | 实测 | 稳定性 | 修改风险 |
|---|---|---|---|---|
| `[data-v4-composer-dock]` | 1 | 是 | `v4` 前缀暗示 schema 版本，可能随版本变 | 中：输入区停靠容器，只改表面 |
| `[data-v4-composer-dock-content]` | 1 | 是 | 同上 | 中 |
| `[data-composer-leading-actions]` | 1 | 是 | 语义锚点 | 中：只是动作区外观 |
| `[data-composer-collapse-priority]` | 2 | 是 | 语义锚点 | 中：不得改布局行为 |
| `[data-chat-toolbar-popover-trigger]` | 2 | 是 | 语义锚点 | 中：触发器只改颜色 |
| `[data-slot="dialog-header"]`、`[data-slot="dialog-title"]` | 1 / 1 | 是 | Radix slot 命名 | 中：弹窗标题区，需验对比度 |
| `[data-slot="tabs"]`、`[data-slot="tabs-list"]`、`[data-slot="tabs-trigger"]` | 1 / 1 / 1 | 是 | Radix slot 命名 | 中 |
| `[data-slot="tooltip-trigger"]` | 1 | 是 | Radix slot 命名 | 中 |
| `[data-state]`（`open`/`closed`/`active`/`inactive`） | 80 | 是 | 语义锚点，值集合已实测 | 中：状态色需逐项验证 |
| `[data-variant]`、`[data-size]`、`[data-disabled]`、`[aria-disabled]` | 29 / 29 / 2 / 19 | 是 | 语义锚点 | 中：按钮状态 |
| `[aria-haspopup]`、`[aria-expanded]`、`[aria-selected]`、`[aria-pressed]` | 9 / 28 / 2 / 2 | 是 | ARIA 语义 | 中 |
| `[data-testid="task-new-button"]` | 1 | 是 | 开发者命名 testid | 低：可安全点名的部件 |
| `[data-testid="automations-open"]` | 1 | 是 | 开发者命名 testid | 低 |
| `[data-testid="plugin-store-sidebar-open"]` | 1 | 是 | 开发者命名 testid | 低 |
| `[data-testid="project-add"]` | 1 | 是 | 开发者命名 testid | 低 |
| `[data-testid="project-section"]` | 1 | 是 | 开发者命名 testid | 低 |
| `[data-testid="workspace-list"]` | 1 | 是 | 开发者命名 testid | 低 |
| `[data-testid="task-list"]` | 1 | 是 | 开发者命名 testid | 低 |
| `[role="dialog"]`、`[role="menu"]`、`[role="tooltip"]`、`[data-radix-popper-content-wrapper]` | 0 | **未实测** | 通用 ARIA/Radix 命名 | 高：必须等实测再纳入 |

### DO NOT TOUCH（禁止换肤）

| 选择器 / 结构 | 计数 | 实测 | 原因 |
|---|---|---|---|
| `[data-lexical-editor]`、`[contenteditable="true"]`、`[role="textbox"]`、`[data-e2e-lexical-bridge]` | 1 / 1 / 1 / 1 | 是 | 输入区的富文本编辑器根节点：只允许改外围容器，绝不改编辑器本体 |
| `[data-v4-timeline-scroll]`、`[data-v4-timeline-scroll-locked]`、`[data-v4-back-to-bottom-anchor]` | 1 / 1 / 1 | 是 | 关键滚动容器（本次共 6 个滚动容器） |
| `[data-pane-id]` | 1 | 是 | 分栏布局容器，尺寸归原生布局 |
| `svg` 及其几何子节点（`path`/`circle`/`rect`/`line`/`polyline`） | 55 / 89 / 17 / 6 / 4 / 1 | 是 | SVG 几何不得重绘 |
| `[data-icon]`、`[data-cron-task-icon]` | 3 / 1 | 是 | 图标几何 |
| `img` | 3 | 是 | 位图内容，不改尺寸/滤镜 |
| `.monaco-editor` | 0 | **未实测** | 编辑器（设计明令禁止；本次未打开文件） |
| `.xterm` | 0 | **未实测** | 终端（设计明令禁止；本次未开终端） |
| `iframe`、`canvas`、`webview` | 0 / 0 / 0 | **未实测** | 嵌入页 / canvas / WebView（设计明令禁止） |
| `[data-markdown-table-layout-root]` | 1 | 是 | 表格布局根，尺寸归原生 |
| `[data-radix-collection-item]`、`[data-group]`、`[data-orientation]` | 2 / 2 / 4 | 是 | 交互集合与方向语义，改色即可能影响可读性 → 归入禁止区保守处理 |

## 类名不可用（实测结论）

- `classFragments`（CSS-module 片段，形如 `_MainContentSurface_hash`）本次为 **0 个**；上游 Codex 那种 `[class*="_MainContentSurface_"]` 选择器在 ZCode 上不存在。
- 类名是 Tailwind 风格工具类（`flex` 315、`items-center` 302、`text-ui-base` 68…），无语义、可被重构删除。
- **结论：选择器一律锚定 `data-*` / `data-testid` / `role` / `id`，禁止使用类名。**

## 状态类属性（只记名，永不采值）

这些属性的值携带用户或会话状态，采集器按名称拒采（`ZCODE_ATTRIBUTE_VALUE_DENY_SOURCE`），后续任何新增采集也不得采其值：

`data-model-current-value`、`data-initial-draft-model`、`data-initial-draft-provider`、`data-session-id`、`data-title`、`data-task-item-key`、`data-running-subagent-ids`、`data-running-subagent-work-ids`、`data-v4-draft-logo`、`data-v4-draft-greeting`、`data-lexical-editor`、`data-e2e-lexical-bridge`、`aria-placeholder`、`data-input-routing`、`data-restored-unvalidated`、`data-pane-id`、`data-projection-seq`、`data-row-count`、`data-window-row-count`、`data-render-unit-count`、`data-total-row-count`、`aria-valuenow`、`aria-valuemin`。

## 环境指纹（用于版本/兼容判定）

- `urlFamily`：`file://…/index.html`
- `rootTags`：`html`
- `stableAttributes`：本次实测的 80 个 `data-*` / `role` 属性名（见 `zcode-dom-inventory.json` 的 `attributeNames`）
- `selectors`：本次命中的 presence 探针键名
- 指纹算法：以上四类稳定语义特征排序后取 SHA-256 前 32 位（`zcode-compatibility.mjs` 的 `zcodeSemanticFingerprint`），**不含**类名、文本、用户路径或对话内容
