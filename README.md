# Dream Skin 2.0 (双端无侵入式换肤总控系统)

> **优雅、沉浸、绝对可逆的 AI 客户端视觉增强套件**  
> 专为 **Cherry Studio** 与 **ZCode (Codex)** 打造的非侵入式毛玻璃主题与自定义壁纸管理引擎。

[![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11%20x64-blue.svg)](https://github.com/ningmengningmeng233-sys/Dream-Skin-2.0)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Architecture](https://img.shields.io/badge/Architecture-Non--Invasive%20CDP%20%2F%20UIA-orange.svg)](#)

---

## 一、 项目设计目的与初衷

在日常高强度的研发与长文本创作中，AI 客户端已成为工程师与创作者打开时间最长的核心生产力工具。然而，当前主流客户端的原生视觉体验普遍存在显著痛点：

1. **视觉割裂与死板暗沉**：
   官方默认的深色模式普遍偏向生硬的暗灰与死黑色调，长时间注视容易引起视觉疲劳；同时主视口背景被多层带有不透明背景的容器死死遮挡，无法展现壁纸与透光质感。
2. **传统换肤方案的破坏性隐患**：
   社区现存的很多美化方案通常采取“暴力解包篡改 ASAR 核心文件”、“劫持/覆写动态链接库 (DLL)”等侵入式手段。这种方式具有极高的风险：
   - 破坏官方代码签名，极易引发杀毒软件拦截；
   - 客户端一旦自动更新，修改过的文件被覆写，往往直接引发主进程崩溃或白屏（White Screen of Death）；
   - 难以安全无损地还原，导致用户聊天历史与模型配置面临丢失风险。

**Dream Skin 2.0 的诞生目的，就是为了提供一套兼具“极致通透视觉美学”与“工业级运行安全性”的完美解决方案。**

---

## 二、 核心架构设计理念

本套件严格贯彻四大工程铁律：

### 1. 绝对零文件篡改（Non-Invasive）
- **Cherry Studio 侧**：走官方正规的“外观 → 自定义 CSS”通道，通过专研的 Windows UI Automation (UIA) 桥实现精确输入，原汁原味保全官方二进制与签名。
- **ZCode 侧**：基于 Chromium/Electron 标准的 Chrome DevTools Protocol (CDP) 远程调试端口进行动态样式热挂载，零改包、不碰 ASAR，随开随关。

### 2. 全通透沉浸式毛玻璃美学（Aesthetic Immersion）
- 彻底击碎传统客户端中内部容器（`main`, `chat-container`, `.ant-layout-content`）对背景的死黑遮挡；
- 实现全屏级壁纸纵向贯穿透视，配合 `backdrop-filter: blur(16px)` 高品质毛玻璃与高质感浮岛消息气泡，既保证壁纸的通透展现，又确保文字的清晰对比度。

### 3. 严格 CAS 与字节级可逆安全（Fail-Safe & Reversible）
- 引入 **Compare-And-Swap (CAS)** 状态比对机制：每次注入前必须比对当前编辑框的实测 SHA-256 校验和，只有在基线状态一致时才放行写入；
- 配备 D 盘全量只增备份系统与桌面一键还原开关，任何时候只需双击即可秒级还原回官方初始状态。

### 4. 单一原生 GUI 整合（Unified Desktop Experience）
- 告别零散的批处理文件与晦涩的终端脚本；
- 采用 C# 开发并编译为单一原生的 64 位 Windows GUI 总控程序（`DreamSkinMaster.exe`），将双端换肤、预设挑选、自定义壁纸选择与一键还原完全收拢在同一个精致的窗口中。

---

## 三、 重大技术攻坚：CodeMirror 6 投影失真破案

在项目推进过程中，团队成功攻克了 Electron 复杂文本编辑器的回环形变难题：

1. **架构定案**：
   通过无侵入 DOM 探针逐级探测，确凿证实 Cherry Studio 自定义 CSS 框是由现代化的 **CodeMirror 6 (CM6)** 构建（祖先链 `.cm-content.cm-lineWrapping` $\to$ `.cm-scroller` $\to$ `.cm-editor` $\to$ `#setting-appearance-custom-css`），彻底排除了传统的原生 textarea 假说。
2. **读侧投影失真定理 (T-READ-PROJ)**：
   团队实测证实：CM6 内存文档在空白时真实逻辑字节为 0B（Hash `e3b0c442…`）；而 Windows UIA TextPattern 抓取时由于 CM6 内部空行的虚拟排版机制，系统性地附加了换行符投影为 1B（`0x0A`，Hash `01ba4719…`）。此前观察到的“跨行空格颠倒与末尾换行丢失”实为 UIA 跨虚拟行提取的排版失真，并非数据底层损坏。这一发现为现代富文本客户端的自动化无损换肤提供了权威理论依据。

---

## 四、 功能特性清单

- 🍒 **Cherry Studio 换肤**：
  - **5 套精选风格预设**：黑金磨砂 (Dark Gold)、赛博霓虹蓝 (Cyber Blue)、极客蓝绿 (Teal Tech)、二次元柔紫 (Anime Purple)、淡雅护眼奶白 (Soft Cream)；
  - **自定义壁纸背景**：支持用户任意选择本地图片（JPG/PNG/WebP），自动转为自适应 Base64 Data URI 并融合毛玻璃暗色遮罩；
  - **全通透穿透规则**：消除右侧聊天视口的死黑遮挡，壁纸全屏透出。
- ⚡ **ZCode 换肤**：
  - CDP 远程调试热注入模式；
  - D 盘全量增量数据备份机制（`D:\ZCodeDreamSkin-backup`）；
  - 系统托盘驻留管理与随时一键卸载还原。
- 🛡️ **安全与恢复**：
  - 桌面一键还原开关，无视任何版本差异，1 秒彻底清除注入样式。

---

## 五、 项目结构

```
Dream-Skin-2.0/
├── src/
│   ├── DreamSkinMaster/       # 原生 Windows Forms 64位总控台源码 (C#)
│   │   ├── DreamSkinForm.cs   # GUI 窗口主代码 (多预设+自定义壁纸，相对路径自适应)
│   │   └── build.bat          # csc 编译构建脚本
│   ├── cherry/                # Cherry Studio 换肤核心
│   │   ├── CherryUiBridge/    # 核心自动化桥源码与 Release 产物 (.NET 8.0)
│   │   │   ├── Program.cs
│   │   │   ├── CssEditorAccess.cs
│   │   │   ├── CherryUiBridge.csproj
│   │   │   └── bin/Release/net8.0-windows/
│   │   ├── host-bridge.mjs    # 生产级自动化 IPC 桥与 CAS 校验层
│   │   ├── apply-cherry.mjs   # 样式注入驱动
│   │   ├── restore-cherry.mjs # 初始基线还原驱动
│   │   ├── preset-themes.mjs  # 50 组预设色彩算法底座
│   │   └── presets/           # 主题预设算法依赖
│   │       ├── theme-project.mjs
│   │       ├── composition.mjs
│   │       └── colorUtils.js
│   └── zcode/                 # ZCode 客户端换肤核心
│       ├── payload/           # ZCode Dream Skin 完整受管运行载荷
│       │   ├── scripts/       # 启动/还原/托盘控制 (common/theme/zcode-product/startup/store 等)
│       │   └── assets/        # 验证器 (theme-package-validator, safe-css-validator)
│       ├── injector.mjs       # 基于 CDP 调试端口的无侵入热挂载器
│       ├── start-zcode.ps1    # 受管启动引导
│       └── restore-zcode.ps1  # 恢复引导
├── docs/                      # 架构设计、全景交接白皮书与取证档案
│   ├── specs/                 # 实施计划与总工程台账 (IMPLEMENTATION-PLAN, TASK_PROGRESS)
│   ├── evidence/              # 物理证据 (PAIR-VERDICT, VALID_PAIR)
│   ├── memory-vault/          # 关键架构记忆 (网关拓扑, 桌面整洁铁律, 终端调度契约)
│   └── CODE-MIRROR-6-BREAKTHROUGH.md # CodeMirror 6 内部虚拟 DOM 与 UIA 投影失真破案记录
├── HANDOVER.md                # 外部接手全景交接与问题排障指南
├── LICENSE                    # MIT License
└── README.md                  # 项目说明与技术文档
```

---

## 六、 运行环境要求 (实机验证基准)

- **Node.js**：推荐 `v24.x` / `v22.x`（实测基准版本：`v24.19.0`）；
- **.NET 运行时**：需安装 **.NET 8.0 Windows Desktop Runtime**（实测环境包含 `Microsoft.WindowsDesktop.App 8.0.28` 与 .NET 9 SDK）；
- **操作系统**：Windows 10 / Windows 11 x64。

---

## 七、 开源协议

本项目采用 [MIT License](LICENSE) 开源协议，欢迎广大二次元与极客开发者贡献预设样式与优化建议！

## 快速运行（Windows 10/11 x64）

**前置**：Node.js 22+（官方签名版，加入 PATH）；.NET 8 Desktop Runtime（Cherry 的 UIA 桥需要）；Windows PowerShell 5.1（系统自带）。

1. 编译总控台：双击 `src/DreamSkinMaster/build.bat`，生成 `DreamSkinMaster.exe`（放在原目录即可，它会自动向上找到 `src/`）。
2. **Cherry Studio**：先打开 Cherry，进入 设置 → 外观（自定义 CSS 所在页），窗口不要最小化；再在总控台选预设/壁纸，点「应用」。
   - 命令行等价：`node src/cherry/apply-cherry.mjs --preset cyber-blue --image D:\wall.jpg`
   - 还原：`node src/cherry/restore-cherry.mjs`
   - 预设：`dark-gold` `cyber-blue` `teal-tech` `anime-purple` `warm-cream`；壁纸 ≤ 1.5 MB（JPG/PNG/WebP）
   - 首次换肤前的原 CSS 会备份到 `%LOCALAPPDATA%\DreamSkin\cherry\original-before-dream-skin.css`
3. **ZCode**：总控台点「启动 ZCode 换肤」，实际调用 `src/zcode/payload/scripts/start-zcode-dream-skin.ps1`；还原调用 `restore-zcode-dream-skin.ps1`。

**可选环境变量**：`DREAMSKIN_DATA_DIR`（Cherry 工件目录）、`DREAMSKIN_CHERRY_BRIDGE`（自编译的 CherryUiBridge.exe 路径）、`DREAMSKIN_CHERRY_VERSION`（强制指定 Cherry 版本前缀）。

**重新编译 UIA 桥**：`dotnet build src/cherry/CherryUiBridge -c Release`（FlaUI 依赖已放在 `src/cherry/vendor/flaui/lib`）。

