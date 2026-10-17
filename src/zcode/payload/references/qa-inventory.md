# QA inventory

## User-visible claims

1. The home screen paints one UI-free wallpaper continuously across sidebar and main content, with a live native heading, the real project utility/composer surface, and any suggestion cards rendered by the current Codex host.
2. Sidebar, main area, header, and composer use coordinated readability layers; home remains expressive while normal task routes use a stronger quiet veil.
3. All real Codex controls remain interactive; the skin is not a screenshot overlay.
4. The skin survives route changes and renderer reloads while the injector daemon runs.
5. The official Store package and `app.asar` remain unchanged.
6. Restore removes the injected DOM/CSS and install/restore can be repeated.
7. Restore closes the saved CDP listener before reopening Codex normally.

## Functional checks

- Home feature card: click one card and confirm the real composer is populated or the normal action occurs.
- Project selector: click the real project chip under the "选择项目" label and confirm the native project menu opens.
- Sidebar: open a real task, then return to New Task.
- Task side panel: open and close the native thread panel twice, resize the window, and repeat; the toggle must remain visible and clickable.
- Composer: type text, verify caret/readability, then clear it without sending.
- Reload: use CDP `Page.reload`, wait, and confirm the injection marker returns.
- Pet overlay: open a desktop pet and confirm its auxiliary window stays transparent with no skin background or decoration layer behind it.
- Restore/reapply cycle: remove live skin, verify marker absent, apply again, verify marker present.
- Update resilience: resolve the current `OpenAI.Codex` Appx location dynamically for launch. A versioned path saved for cleanup must be revalidated against the registered package full/family identity before any process is stopped.
- Restart consent: an existing normal Codex window is never force-closed without explicit CLI authorization or shortcut confirmation.
- Shortcut policy: installed launch, restore, tray, and tray-child commands use `RemoteSigned` without `Bypass`; Internet-zone markers are removed only from hash-verified managed PowerShell copies.
- Config safety: Chinese project names, LF/CRLF choice, quoted target keys, table-header comments, and unrelated TOML sections survive install/selective restore; ambiguous target shapes fail unchanged, exact recovery keeps a copy of the replaced current file, and install refuses both registered and state-recorded old Codex processes.
- Theme safety: empty/over-10 MB images, over-16384px/50MP dimensions, path escapes, symlinks/junctions, malformed JSON, unsafe CSS, and unsupported formats are rejected before payload construction.
- Tray lifecycle: pause/resume reflects the clicked state, bundled Arina Hashimoto theme is present on first install, and complete restore terminates any separately launched tray before it can reapply the skin.

## Visual checks

- 1280x820 initial home: the declared focus stays in frame, the text-safe side remains readable, the real project utility row and composer form one coherent surface, and no horizontal scrolling appears.
- Narrower window: accept Codex's native responsive card reduction or omission; no essential control is covered and wallpaper cropping preserves the focus/safe-area contract.
- Normal task: the wallpaper is visibly quieter than home, messages keep high contrast, and composer does not overlap content.
- Inspect the sidebar, header, wallpaper edges, native card labels when present, project utility row, composer controls, scrollbar, dialogs, and menus.
- Reject black/transparent sidebar artifacts, clipped controls, duplicated/disconnected project labels, rasterized native controls, fake UI inside the wallpaper, weak contrast, or decorations intercepting clicks.

## Exploratory checks

- Start when the debug port is occupied: fail with a clear message or use a caller-selected port.
- Start after Codex updates: package discovery and injection still work without patching installed files.
- Tamper `state.json` with a reused PID: if the PID is still live but its identity differs, confirm cleanup fails closed and preserves `state.json`; if the PID is gone, confirm the stale record is replaced only after confirming no process is running, without stopping an unrelated process.
- Serve a fake `app://` CDP target or remote/mismatched WebSocket URL and confirm both launcher and injector reject it. Reuse the port with a new Browser ID and confirm the existing watcher exits without reconnecting.
- Force verification failure and confirm the injector, state file, and newly launched debug session are rolled back.
- Start two operations concurrently and confirm the second fails clearly without changing config, state, or processes.
- Close Codex without restore and confirm the Browser identity anchor closes and the watcher exits without reconnecting or rapidly growing logs.

## Automated checks

- `tests/run-tests.ps1`: strict UTF-8/no-BOM writes, UTF-16 rejection, LF/CRLF preservation, concurrent-write detection, exact backup/recovery, `[desktop]`-scoped restore, ambiguous TOML rejection, non-ASCII paths, Appx/state identity, argument quoting, theme seeding/import/save/switch/pause, canonical community-link and compatible-metadata rejection, fixed-origin download/apply boundaries, byte/dimension limits, junction rejection, payload construction, Browser ID, loopback URL rejection, and renderer isolation for transparent auxiliary windows.
- `node --check` for the injector and renderer payload.
- Live Windows signoff remains required for Store process ownership, restart consent, screenshot, and CDP closure.

## ZCode Dream Skin QA checklist（人工视觉验收）

前置：ZCode `3.14.4.7912` 已验证签名；ZCode 已完全退出。

1. 首页与正常工作区：背景壁纸在侧栏与主区连续可见；侧栏、主区、顶部、输入区可读性正常，文字对比度不低于原版。
2. 交互：输入、点击、滚动、菜单、弹窗全部可用；装饰层不拦截鼠标（`pointer-events:none`）。
3. 禁止区：Monaco 编辑器、终端（xterm）、WebView、iframe、canvas、SVG 图标几何不受影响；关键滚动容器行为不变。
4. 幂等与重载：连续应用两次无重复节点；renderer reload 后主题自动恢复；暂停后 reload 不重注入。
5. 暂停/恢复/完整恢复：暂停只移除主题且 ZCode 继续运行；恢复重新校验后再注入；完整恢复后 ZCode 正常重启、9335 释放、官方界面恢复。
6. 证据：原始截图保存到 Git 忽略的 `.lemon/evidence/acceptance/`；只有人工脱敏后的报告才可复制进仓库。

### 2026-10-02 本机候选记录

产品构建：`d65e0f1`。实机证据在 Git 忽略的 `.lemon/evidence/release-final/20261002-final-resume/`；前段安装/更新/卸载/保库/重装在 `20261002-task5-r9-external/`，后者构建是 `289176a`，不能冒充最终候选的全套实机结果。

- 已执行：首页壁纸实际可见；输入临时文本并撤销，未发送模型请求；帮助菜单与关于弹窗可读、弹窗正常关闭；侧栏滚动；900像素窄窗口；安装版Pause/Resume（full、监控重建）与reload恢复。
- 未完整执行：系统托盘换图/Apply/保存/切换/ZIP导入/取消/异常提示的原生点击链（工具未暴露托盘操作面）。
- 未创建实际场景：Monaco/xterm/WebView等保护区域；离线禁改区测试不等于这些区域的实机签收。
- 待用户确认：视觉偏好与日用签收。未核实其他ZCode版本，不外推兼容性。
