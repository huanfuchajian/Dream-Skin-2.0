// 由预设配色 + 可选壁纸生成 Cherry Studio v2 自定义 CSS。
//
// 设计目标对齐原型 Codex Dream Skin：一张 16:9 壁纸铺满整个窗口，原生控件全部保留，
// 只把“外壳层”变透明，再给需要读字的区域加渐变遮罩 / 磨砂，保证文字清楚。
//
// 选择器全部来自 Cherry Studio v2.1.4 源码（CherryHQ/cherry-studio tag v2.1.4）：
//   外壳根节点   div.h-screen.w-screen.bg-sidebar      (components/layout/AppShell.tsx)
//   图标栏       #app-sidebar / [data-ui="app.sidebar"]
//   标签栏       [data-ui="app.tab-bar"]
//   内容卡片     main[data-ui="app.content"]  (自带 bg-background + 圆角边框)
//   聊天页       #chat[data-ui="chat.view"]   (ConversationShell，自带 bg-background)
//   中间聊天区   [data-ui="part:conversation-main"]
//   消息列表     #messages / [data-ui="chat.message-list"]
//   助手/话题栏  [class*="resource-list-pane"] / [data-ui="chat.topic-list"]
//   输入框       #inputbar[data-ui="chat.composer"]  (自带 bg-card)
//   主题变量     :root / .dark 上的 Shadcn 变量 (--background --card --primary --chat-user ...)
// 不使用任何 V1 选择器（.ant-layout、#content-container 的旧写法、--color-background 等）。
import { readFileSync, statSync } from 'node:fs';
import { extname } from 'node:path';

export const CHERRY_PRESETS = {
  'dark-gold':    { name: '黑金磨砂',     dark: true,  bg: '#0e0d0c', panel: '20,18,16',    bubble: '28,25,21',    accent: '#c8a55a', accentText: '#141109', text: '#f3ead7', muted: '#b5a386' },
  'cyber-blue':   { name: '赛博霓虹蓝',   dark: true,  bg: '#070b18', panel: '10,16,34',    bubble: '15,24,48',    accent: '#3fa9ff', accentText: '#05101f', text: '#e6f2ff', muted: '#8fa8c8' },
  'teal-tech':    { name: '极客蓝绿',     dark: true,  bg: '#05201f', panel: '7,34,33',     bubble: '10,46,44',    accent: '#2fd3b5', accentText: '#04211d', text: '#e2fbf6', muted: '#86bdb2' },
  'anime-purple': { name: '二次元柔紫',   dark: true,  bg: '#1a1325', panel: '34,24,48',    bubble: '46,33,64',    accent: '#c59bff', accentText: '#1a0f2a', text: '#f6eeff', muted: '#b9a6d4' },
  'warm-cream':   { name: '淡雅护眼奶白', dark: false, bg: '#f3e7d3', panel: '250,244,232', bubble: '255,251,243', accent: '#a07a3c', accentText: '#ffffff', text: '#3a2f22', muted: '#7d6b55' },
};
CHERRY_PRESETS['soft-cream'] = CHERRY_PRESETS['warm-cream'];

// 旧 UIA 通道（apply-cherry.mjs）要把整份 CSS 塞进编辑框，壁纸只能很小；
// 新 CDP 通道（skin-cherry.mjs）走 WebSocket 直接注入 <style>，可以用原图。
export const MAX_IMAGE_BYTES = 1.5 * 1024 * 1024;
export const MAX_IMAGE_BYTES_CDP = 25 * 1024 * 1024;
const MIME = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp' };

// 按文件头判断真实格式，防止把改了后缀的别的文件当壁纸。
function sniffMime(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length >= 8 && buf.readUInt32BE(0) === 0x89504e47) return 'image/png';
  if (buf.length >= 12 && buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  return '';
}

export function imageDataUri(path, maxBytes = MAX_IMAGE_BYTES) {
  if (!MIME[extname(path).toLowerCase()]) throw new Error('壁纸只支持 JPG / PNG / WebP：' + path);
  const size = statSync(path).size;
  if (size > maxBytes) {
    throw new Error(`壁纸 ${(size / 1048576).toFixed(1)} MB 太大，上限 ${(maxBytes / 1048576).toFixed(1)} MB。`);
  }
  const buf = readFileSync(path);
  const mime = sniffMime(buf);
  if (!mime) throw new Error('这个文件不是有效的 JPG / PNG / WebP 图片：' + path);
  return `data:${mime};base64,${buf.toString('base64')}`;
}

function hexToRgb(hex) {
  const h = hex.replace('#', '');
  const n = parseInt(h.length === 3 ? h.split('').map((c) => c + c).join('') : h, 16);
  return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
}

const clampPct = (v, d) => (Number.isFinite(v) ? Math.min(100, Math.max(0, v)) : d);

/**
 * @param {string} presetKey
 * @param {string} imageUri  data: URI，空串 = 只用配色
 * @param {{focusX?: number, focusY?: number}} [opts] 壁纸焦点（百分比，默认居中偏上 50/40）
 */
export function buildCherryCss(presetKey = 'dark-gold', imageUri = '', opts = {}) {
  const p = CHERRY_PRESETS[presetKey];
  if (!p) throw new Error('未知预设：' + presetKey + '，可选：' + Object.keys(CHERRY_PRESETS).join(', '));
  const a = (rgb, alpha) => `rgba(${rgb}, ${alpha})`;
  const accent = hexToRgb(p.accent);
  const shade = p.dark ? '0,0,0' : '255,255,255';
  const line = p.dark ? 'rgba(255,255,255,0.10)' : 'rgba(60,40,10,0.12)';
  const focus = `${clampPct(opts.focusX, 50)}% ${clampPct(opts.focusY, 40)}%`;

  // 遮罩强度直接取原型 Codex Dream Skin 的 immersive 档（dream-skin.css: edge .40 / mid .26 / far .16，
  // 侧栏 .46，输入框 .44）。只叠一层：body 上一道横向渐变，其他层要么透明要么是磨砂卡片，避免层层压暗。
  const base = p.dark ? hexToRgb(p.bg) : p.panel;
  const edge = p.dark ? 0.40 : 0.44, mid = p.dark ? 0.26 : 0.28, far = p.dark ? 0.16 : 0.18;
  const scrim = `linear-gradient(90deg, ${a(base, edge)} 0%, ${a(base, mid)} 30%, ${a(base, far)} 65%, ${a(base, mid)} 100%)`;
  const wallpaper = imageUri
    ? `${scrim}, url("${imageUri}") ${focus} / cover no-repeat fixed, ${p.bg}`
    : `radial-gradient(1200px 700px at 85% 10%, ${a(accent, p.dark ? 0.16 : 0.12)}, transparent 60%), radial-gradient(900px 600px at 0% 100%, ${a(accent, p.dark ? 0.10 : 0.08)}, transparent 60%), ${p.bg}`;

  // 读字区：有图时只在底部（输入框附近）加一点渐暗，无图时稍实。
  const mainTop = imageUri ? 0.06 : 0.30, mainBottom = imageUri ? mid : 0.40;
  const paneTint = p.dark ? 0.46 : 0.50;

  return `/* ===== Cherry Dream Skin 2.0 · ${p.name} (${presetKey}) · for Cherry Studio v2 ===== */

/* 0. 主题变量：亮/暗模式都套同一套配色，弹窗、卡片、菜单保持实心不透明 */
:root:root, :root.dark {
  --background: ${p.bg};
  --foreground: ${p.text};
  --card: rgb(${p.bubble});
  --card-foreground: ${p.text};
  --popover: rgb(${p.bubble});
  --popover-foreground: ${p.text};
  --primary: ${p.accent};
  --primary-foreground: ${p.accentText};
  --secondary: ${a(p.bubble, 0.9)};
  --secondary-foreground: ${p.text};
  --muted: ${a(p.bubble, 0.85)};
  --muted-foreground: ${p.muted};
  --accent: ${a(accent, p.dark ? 0.16 : 0.14)};
  --accent-foreground: ${p.text};
  --border: ${line};
  --input: ${line};
  --ring: ${a(accent, 0.55)};
  --sidebar: ${a(p.panel, 0.55)};
  --sidebar-foreground: ${p.text};
  --sidebar-primary: ${p.accent};
  --sidebar-primary-foreground: ${p.accentText};
  --sidebar-accent: ${a(accent, p.dark ? 0.16 : 0.14)};
  --sidebar-accent-foreground: ${p.text};
  --sidebar-border: ${line};
  --sidebar-ring: ${a(accent, 0.55)};
  --chat-user: ${a(accent, p.dark ? 0.16 : 0.12)};
  --code-block: ${p.dark ? 'rgba(0,0,0,0.45)' : 'rgba(255,255,255,0.75)'};
  --inline-code: ${p.dark ? 'rgba(0,0,0,0.35)' : 'rgba(60,40,10,0.08)'};
  --resource-list-row-active: ${a(accent, p.dark ? 0.20 : 0.16)};
  --resource-list-row-selected: ${a(accent, p.dark ? 0.20 : 0.16)};
  --resource-list-row-hover: ${a(shade, p.dark ? 0.18 : 0.35)};
}

/* 1. 整窗壁纸：只给主窗口（有 #app-sidebar 的窗口），划词工具条 / 快捷助手等小窗不受影响 */
body:has(#app-sidebar) {
  background: ${wallpaper} !important;
  color: ${p.text};
}

/* 2. 外壳层全部透明，让壁纸从图标栏一直贯穿到聊天区 */
body:has(#app-sidebar) .h-screen.w-screen,
#app-sidebar,
[data-ui="app.sidebar"],
[data-ui="app.tab-bar"],
[data-ui="chat.view"],
#chat,
#home-page,
[data-ui="chat.message-list"],
[data-ui="chat.topic-list"],
#messages {
  background: transparent !important;
  background-color: transparent !important;
}

/* 3. 内容卡片：保留原生圆角边框，只留一层很薄的底色 */
[data-ui="app.content"] {
  background: ${imageUri ? 'transparent' : a(p.panel, 0.20)} !important;
  border-color: ${line} !important;
  box-shadow: 0 10px 40px -12px rgba(0,0,0,${p.dark ? 0.55 : 0.18}) !important;
}

/* 4. 助手 / 话题栏：磨砂玻璃 */
[class*="resource-list-pane"] {
  background: ${a(p.panel, paneTint)} !important;
  backdrop-filter: blur(18px) saturate(1.15);
  -webkit-backdrop-filter: blur(18px) saturate(1.15);
  border-right: 1px solid ${line};
}

/* 5. 中间聊天区：上浅下深的渐变遮罩，露出壁纸又保证正文清楚 */
[data-ui="part:conversation-main"] {
  background: linear-gradient(180deg, ${a(p.panel, mainTop)} 0%, ${a(p.panel, mainTop)} 55%, ${a(p.panel, mainBottom)} 100%) !important;
}
/* 正文压一层很淡的阴影，浅色壁纸上也看得清 */
[data-ui="chat.message-list"] {
  text-shadow: ${p.dark ? '0 1px 2px rgba(0,0,0,0.55)' : '0 1px 1px rgba(255,255,255,0.6)'};
}

/* 6. 用户消息气泡 */
.message-user .message-content-container {
  border: 1px solid ${a(accent, 0.22)};
}

/* 7. 输入框：浮起的磨砂卡片 */
#inputbar,
[data-ui="chat.composer"] {
  background: ${a(p.bubble, imageUri ? 0.44 : 0.80)} !important;
  backdrop-filter: blur(18px) saturate(1.2);
  -webkit-backdrop-filter: blur(18px) saturate(1.2);
  border: 1px solid ${a(accent, 0.28)} !important;
  box-shadow: 0 8px 30px -10px rgba(0,0,0,${p.dark ? 0.6 : 0.2}) !important;
}
#inputbar:focus-within,
[data-ui="chat.composer"]:focus-within {
  border-color: ${a(accent, 0.55)} !important;
}

/* 8. 代码块别被壁纸干扰 */
[data-ui="part:code-block"] {
  background: ${p.dark ? 'rgba(0,0,0,0.55)' : 'rgba(255,255,255,0.85)'} !important;
}

/* 9. 文字选中 */
::selection { background: ${a(accent, 0.35)}; }
`;
}
