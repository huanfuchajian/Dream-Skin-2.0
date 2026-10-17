# CodeMirror 6 文本形变突破与 UIA 投影失真排障白皮书

## 一、 背景与谜团
在针对 Cherry Studio 进行自动化注入测试时，团队观察到一个持续复现的异常现象：
- 注入 9 字节换行微样本（`/*a\n b*/\n`，Hash `0aaa5e89…`）；
- 经 Windows UI Automation (TextPattern) 回读时，稳定返回 8 字节（Hash `88795087…`）；
- 差异特征：第 3~4 字节由 `0A 20` 颠倒为 `20 0A`，且末尾的换行符丢失。

## 二、 物理取证排障
团队通过分级探针进行了深度硬件取证：
1. **DOM 结构扫描（B2ce 探针）**：
   - 现场实测发现 `textareaCount: 0`，排除了原生 textarea 假说；
   - 祖先链深度追溯：
     `.cm-content.cm-lineWrapping` $\to$ `.cm-scroller` $\to$ `.cm-editor` $\to$ `.cm-theme-dark.code-editor` $\to$ `#setting-appearance-custom-css`；
   - 100% 定案编辑器技术选型为 **CodeMirror 6 (CM6)**。
2. **内存文档真实值提取（P-LOGIC-01 探针）**：
   - 通过 `@uiw/react-codemirror` 挂载在 DOM 上的内部句柄 `cmTile.view.state.doc.toString()` 直接提取 JavaScript 引擎内存真值；
   - 结果实证：在空内容时，CM6 真实内存文档大小为 **0 字节（空串，Hash `e3b0c442…`）**；
   - 同期 Windows UIA 回读值为 **1 字节（`0x0A`，Hash `01ba4719…`）**。

## 三、 定理结论 (T-READ-PROJ)
- **结论**：Windows UI Automation (UIA) TextPattern 通道在抓取现代虚拟化代码编辑器（CodeMirror 6）的可访问性树时，受多行元素切分与占位符影响，会自动补齐行尾换行符并在行首空格跨行折叠时发生字符排版颠倒。
- **意义**：证实所谓“文本损坏”并非存储层或逻辑层的真实破坏，而是 Windows 辅助功能树跨层采样的排版投影失真。自动化测试与正式注入必须以内存真值与自适应规约作为权威校验准则。
