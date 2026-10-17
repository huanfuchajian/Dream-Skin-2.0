# K02pair-01 配对判定（VALID_PAIR 门逐项核验）

窗口：`k02pair-01-20261016`（`TOTAL/final-closeout-20261016/run-20261016-k01-01/k02pair-01-20261016/`）
规程：`READONLY-CORRELATION-PROTOCOL-20261016.md` §5。
证据：`W0W1-PRE-20261016.md`（W0/W1）、`w2-logic-raw.json`（W2 原文）、
`W3-POST-RESULT.md`（W3a/W3b）、`k02pair01-*.result.json` + `current-*.css`（UIA 工件）。
TOTAL=`C:\Users\Janson\Desktop\换皮\.lemon\dual-skin-closeout-20261015`

## 判定：`VALID_PAIR`——W0–W4 全部成立，正式签署

按规程 §5，`VALID_PAIR` 要求 W4 未触碰确认与全部技术门同时成立。
本文件初版编制时技术门已全过（§1）、W4 尚未收到，记为 `PENDING_W4`；
用户随后给出 §2 所示确认，W4 就位，故本对正式升格为
**`VALID_PAIR`**，无需重采。

- 签署时刻：2026-10-16 18:21:32 本地（Asia/Shanghai）= `2026-10-16T10:21:32Z`。
- 签署依据：用户对话确认原话（§2 逐字记录）+ `TOTAL/muse-prompt-w4-sign.txt` 书面指令。
- 判定闭环：W0 身份通过、W1 前置通过、W2 18 键通过且 `abort == null`
  且归属全 true、W3 后置通过且无漂移、W4 用户确认就位（§1–§2）。

---

## 1. 技术门逐项核验（全过）

| # | 规程门 | 核验结果 |
|---|---|---|
| 1 | 18 键齐全 | 过。`w2-logic-raw.json` 程序化验得 18 键，缺失=无；键序与规程一致 |
| 2 | `abort == null` | 过 |
| 3 | `ownsDom && ownsContent` | 过（均为 true） |
| 4 | `chainTruncated == false` + 链完整 | 过。`chain=["DocTile"]`，`chainLen=1`，`hasOwnCmTile=true` |
| 5 | W1/W3 UIA 逐字节相等 | 过。W1==W3a==W3b，均为 1B `0x0A`（`01ba4719…aca546b`），独立复算 MATCH |
| 6 | 时序 T_uia_pre ≤ T_logic ≤ T_uia_post | 过。`08:49:25.763Z` ≤ `10:04:24.774Z` ≤ `10:15:25.543Z` |
| 7 | 身份一致（W0 基线） | 过。桥当场量到 2.1.4 / `18c07435…aadda55` / 主窗 1 / 编辑器 1；宿主 10 进程无重启；r19 桥与 pin node 均验过冻结哈希 |

同期对照值（本次状态实录，不做成因解释）：

- 逻辑侧（W2）：`chars=0`，`utf8Bytes=0`，`lines=1`，
  `sha256=e3b0c442…b855`（= 空输入哈希，已独立复算核对）。
- UIA 侧（W1/W3a/W3b）：`lengthChars=1`，`utf8Bytes=1`（`0x0A`），
  `sha256=01ba4719…aca546b`；通道 `textpattern-gettext-minus1`，
  交叉证人 `valuePatternChars=0/crossChecked=true`。

## 2. W4 未触碰确认（已收到，用户原话逐字记录）

要求模板（初版时向用户发出，允许 DevTools Console 粘贴探针本身）：

> 自 W1（本地 2026-10-16 16:49:25）至 W3b（本地 2026-10-16 18:15:25）期间，
> 未编辑、未粘贴、未撤销/重做该自定义 CSS 编辑框（`#setting-appearance-custom-css`
> 内唯一 `.cm-editor`）；其余任何触碰一票否决。

用户确认原话（对话中正式给出，经 `TOTAL/muse-prompt-w4-sign.txt` 书面转达）：

> “自今日 16:49:25 至 18:15:25，我未对自定义 CSS 编辑框做任何编辑/粘贴/撤销”

核验：

- 覆盖窗口 16:49:25–18:15:25（本地，秒精度）与模板端点
  （W1 右端 16:49:25 / W3b 右端 18:15:25）逐字一致，覆盖 W1→W3b 全程。
- 确认事项“编辑/粘贴/撤销”与模板一致；“重做”未在原话中单列——
  无撤销即无有效重做，且“未做任何编辑”兜底内容无变更，不影响有效性。
- 判定：**W4 通过**。连同 §1 七门，本对闭环成立 → `VALID_PAIR`。
- （模板原备选分支“触碰/否认 → `INCOMPLETE（TOUCHED）/ VOID`”未触发。）

## 3. 红线遵守

- 结论只覆盖本次窗口状态（逻辑 0B 与 UIA 1B 同期有效对照）；
  绝不解释历史 9B→8B；绝不关闭 C05。W4 签署不改变本红线。
- `INCOMPLETE`/`BLOCKED` 不适用（无触发项）；三重自洽核验仅作算术 sanity，
  不替代归属与同期性证据。
- 全程零宿主写入（见 `W3-POST-RESULT.md` §5；W4 签署为纯纸面记账，
  未接触宿主）。
