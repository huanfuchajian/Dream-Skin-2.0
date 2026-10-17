// 由预设配色 + 可选壁纸生成 Cherry 自定义 CSS。GUI 下拉框的 5 个 key 都在这里。
import { readFileSync, statSync } from 'node:fs';
import { extname } from 'node:path';

export const CHERRY_PRESETS = {
  'dark-gold':    { name: '黑金磨砂',     dark: true,  bg: '#0e0e12', panel: '16,16,20',   bubble: '22,22,28',   accent: '#c8a55a', accentText: '#111111', text: '#f0f0f0' },
  'cyber-blue':   { name: '赛博霓虹蓝',   dark: true,  bg: '#070b18', panel: '10,16,34',   bubble: '14,22,44',   accent: '#3fa9ff', accentText: '#05101f', text: '#e6f2ff' },
  'teal-tech':    { name: '极客蓝绿',     dark: true,  bg: '#05201f', panel: '8,40,38',    bubble: '10,50,48',   accent: '#2fd3b5', accentText: '#04211d', text: '#e2fbf6' },
  'anime-purple': { name: '二次元柔紫',   dark: true,  bg: '#1a1325', panel: '38,26,52',   bubble: '48,34,66',   accent: '#c59bff', accentText: '#1a0f2a', text: '#f6eeff' },
  'warm-cream':   { name: '淡雅护眼奶白', dark: false, bg: '#f3e7d3', panel: '250,244,232', bubble: '255,251,243', accent: '#a07a3c', accentText: '#ffffff', text: '#3a2f22' },
};
CHERRY_PRESETS['soft-cream'] = CHERRY_PRESETS['warm-cream'];

// CM6 编辑器通过 UIA ValuePattern 一次写入，读回时整份比 hash；壁纸太大写入和读回都会很慢甚至截断。
export const MAX_IMAGE_BYTES = 1.5 * 1024 * 1024;
const MIME = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.webp': 'image/webp' };

export function imageDataUri(path) {
  const mime = MIME[extname(path).toLowerCase()];
  if (!mime) throw new Error('壁纸只支持 JPG / PNG / WebP：' + path);
  const size = statSync(path).size;
  if (size > MAX_IMAGE_BYTES) {
    throw new Error(`壁纸 ${(size / 1048576).toFixed(1)} MB 太大，请压到 1.5 MB 以内再试（建议 1920 宽的 JPG/WebP）。`);
  }
  return `data:${mime};base64,${readFileSync(path).toString('base64')}`;
}

export function buildCherryCss(presetKey = 'dark-gold', imageUri = '') {
  const p = CHERRY_PRESETS[presetKey];
  if (!p) throw new Error('未知预设：' + presetKey + '，可选：' + Object.keys(CHERRY_PRESETS).join(', '));
  const a = (rgb, alpha) => `rgba(${rgb}, ${alpha})`;
  const shade = p.dark ? '0,0,0' : '255,255,255';
  const line = p.dark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.08)';
  const wallpaper = imageUri
    ? `linear-gradient(${a(shade, p.dark ? 0.35 : 0.25)}, ${a(shade, p.dark ? 0.35 : 0.25)}), url("${imageUri}") center / cover no-repeat fixed`
    : p.bg;

  return `/* ===== Cherry Dream Skin 2.0 · ${p.name} (${presetKey}) ===== */
body {
  background: ${wallpaper} !important;
  color: ${p.text};
}

/* 1. 打通主布局与聊天区的不透明底色，让壁纸贯穿（只针对布局容器，不碰弹窗和代码块） */
#root, #app, #root > div, .ant-layout, .ant-layout-has-sider, .ant-layout-content, main,
[class*="chat-container"], [class*="conversation-container"], [class*="message-list"], [class*="chat-main"],
#root .bg-background, #root .bg-card {
  background: transparent !important;
  background-color: transparent !important;
}

/* 2. 侧边栏 / 会话列表：半透明磨砂 */
.ant-layout-sider, [class*="sidebar"], [class*="sider"] {
  background-color: ${a(p.panel, 0.65)} !important;
  backdrop-filter: blur(16px) !important;
  -webkit-backdrop-filter: blur(16px) !important;
  border-right: 1px solid ${line} !important;
}

/* 3. 主聊天区：轻遮罩 */
.ant-layout-content, main {
  background-color: ${a(p.panel, 0.30)} !important;
  backdrop-filter: blur(8px) !important;
  -webkit-backdrop-filter: blur(8px) !important;
}

/* 4. 消息气泡：浮岛 */
[class*="message-item"], [class*="chat-bubble"], [class*="message-card"] {
  background-color: ${a(p.bubble, 0.75)} !important;
  backdrop-filter: blur(12px) !important;
  -webkit-backdrop-filter: blur(12px) !important;
  border: 1px solid ${line} !important;
  border-radius: 12px !important;
}

/* 5. 输入框 */
[class*="input-container"], [class*="chat-input"], [class*="inputbar"] {
  background-color: ${a(p.bubble, 0.82)} !important;
  backdrop-filter: blur(20px) !important;
  -webkit-backdrop-filter: blur(20px) !important;
  border: 1px solid ${line} !important;
  border-radius: 14px !important;
}

/* 6. 顶栏 */
.ant-layout-header, [class*="navbar"], [class*="title-bar"] {
  background-color: ${a(p.panel, 0.50)} !important;
  backdrop-filter: blur(10px) !important;
  border-bottom: 1px solid ${line} !important;
}

/* 7. 主按钮强调色 */
.ant-btn-primary, [class*="btn-primary"] {
  background-color: ${p.accent} !important;
  border-color: ${p.accent} !important;
  color: ${p.accentText} !important;
  font-weight: 600 !important;
  border-radius: 8px !important;
}
`;
}
