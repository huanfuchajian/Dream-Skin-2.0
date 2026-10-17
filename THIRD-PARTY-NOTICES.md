# Third-Party Notices

本项目复用了以下开源项目的代码或设计，均为 MIT 协议。

## Fei-Away/Codex-Dream-Skin（MIT, Copyright (c) 2026 Codex Dream Skin Studio contributors）
https://github.com/Fei-Away/Codex-Dream-Skin
- `src/zcode/payload/` 整体源自其 Windows 版本。
- `src/cherry/cdp/cdp-core.mjs` 的 `CdpSession`、`validatedDebuggerUrl` 取自 `src/zcode/payload/scripts/injector.mjs`（同源）。
- `src/cherry/cdp/cherry-process.mjs` 的启动流程（优雅关闭 → 空闲端口 → 带调试端口启动 → 轮询主窗口）参照其 `start-dream-skin.ps1` / `common-windows.ps1`。
- `src/cherry/lib/cherry-skin-css.mjs` 的遮罩强度取自其 `assets/dream-skin.css` 的 immersive 档。

## boilcy/CherryCSS（MIT, Copyright (c) 2025 Caiyun Liu）
https://github.com/boilcy/CherryCSS
- Cherry Studio v2 的 `data-ui` 语义锚点清单与 Shadcn 变量配对规则（`lib/themes/v2Compatibility.ts`）用于核对 `cherry-skin-css.mjs` 的选择器与变量。

## CherryHQ/cherry-studio（AGPL-3.0，仅参考，未复制代码）
https://github.com/CherryHQ/cherry-studio
- 选择器、主窗口路径（`windows/main/index.html`）、CSP 与 `--remote-debugging-port` 用法均按 v2.1.4 源码核对。
