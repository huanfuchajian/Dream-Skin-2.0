// 四套完整皮肤的参数底座。配色算法复用已许可的 Theme Station colorUtils（不另写一套）；
// 这里只负责把它们的结果接到本工具既有的项目合同与受限生成器上。
import { validateProject } from './theme-project.mjs';
import { upgradeProjectV1 } from './composition.mjs';
import { lightenHex, darkenHex, hexWithAlpha, roundAlpha }
  from '../desktop/vendor/theme-station/src/utils/colorUtils.js';

export const PRESET_GROUPS = ['氛围人物', '柔和', '深色', '科技'];

// 受限生成器当前真正消费的键（依据 src/cherry-css.mjs 的 surface 规则与壁纸/遮罩层）。
// 其余键保留在项目的 colors 合同里，但生成器不会输出它们——明写出来，不冒称已适配。
export const CONSUMED_COLOR_KEYS = ['panel', 'text', 'accent'];
export const NOT_CONSUMED_COLOR_KEYS = ['background', 'panelAlt', 'secondary', 'highlight',
  'muted', 'line', 'accentAlt'];

// vendor 的 lightenHex/darkenHex 第二参是 0~1 的比例（r + (255-r)*percent / r*(1-percent)），
// 不是百分数：早期这里写的是 12、78 这类数字，算出来一律是 #000000/#ffffff，
// 四套预设因此在生成器真正消费的那三个键上塌成两套。数值按同一语义改回比例。
function palette(base, { dark }) {
  const panel = dark ? darkenHex(base, 0.12) : lightenHex(base, 0.04);
  return {
    background: base,
    panel,
    panelAlt: dark ? lightenHex(panel, 0.06) : darkenHex(panel, 0.05),
    accent: dark ? lightenHex(base, 0.26) : darkenHex(base, 0.22),
    accentAlt: lightenHex(base, 0.18),
    secondary: hexWithAlpha(base, roundAlpha(dark ? 0.4 : 0.25, 2)),
    highlight: lightenHex(base, 0.34),
    text: dark ? lightenHex(base, 0.78) : darkenHex(base, 0.72),
    muted: hexWithAlpha(base, roundAlpha(dark ? 0.62 : 0.55, 2)),
    line: hexWithAlpha(base, roundAlpha(dark ? 0.3 : 0.2, 2)),
  };
}

export const PRESETS = [
  {
    id: 'skin-person-aura', name: '人物氛围', group: '氛围人物', requiresImage: true,
    base: '#2A1F2D', dark: true,
    surfaces: { opacity: 0.62, radius: 14 },
    art: { focusX: 0.5, focusY: 0.42, zoom: 110, dim: 0.34, blur: 2 },
  },
  {
    id: 'skin-soft-cream', name: '柔和奶油', group: '柔和', requiresImage: false,
    base: '#F3E7D3', dark: false,
    surfaces: { opacity: 0.86, radius: 10 },
    art: { focusX: 0.5, focusY: 0.5, zoom: 100, dim: 0.06, blur: 0 },
  },
  {
    id: 'skin-dark-glass', name: '深色玻璃', group: '深色', requiresImage: false,
    base: '#141A1E', dark: true,
    surfaces: { opacity: 0.44, radius: 18 },
    art: { focusX: 0.5, focusY: 0.5, zoom: 100, dim: 0.22, blur: 6 },
  },
  {
    id: 'skin-teal-tech', name: '蓝绿科技', group: '科技', requiresImage: false,
    base: '#08302E', dark: true,
    surfaces: { opacity: 0.52, radius: 6 },
    art: { focusX: 0.62, focusY: 0.38, zoom: 120, dim: 0.18, blur: 1 },
  },
];

export function presetOf(id) {
  const found = PRESETS.find((p) => p.id === id);
  if (!found) { const e = new Error('unknown_preset'); e.code = 'unknown_preset'; e.field = 'id'; throw e; }
  return found;
}

// 出一份可进既有事务库的项目。缺图的人物卡在这里就过不去，不产出「看似就绪」的主题。
export function buildPresetProject(id, { name, image, composition, imageFileMissing = false } = {}) {
  const preset = presetOf(id);
  if (preset.requiresImage && (image === undefined || image === null || imageFileMissing)) {
    const e = new Error('preset_image_required');
    e.code = 'preset_image_required';
    e.field = 'image';
    throw e;
  }
  const project = {
    schema: 'dream-skin-theme-project/1',
    id,
    name: name || preset.name,
    source: { format: 'editor-v1-normalized', ref: 'preset/' + preset.id },
    image: image ?? { path: 'wallpaper.png', sha256: '0'.repeat(64) },
    normalizedArt: { ...preset.art },
    colors: palette(preset.base, { dark: preset.dark }),
    surfaces: { ...preset.surfaces },
    targets: [],
    sourceManifest: { origin: 'cherry-2-presets', preset: preset.id, base: preset.base },
  };
  const validated = validateProject(project);
  if (!composition) return validated;
  // 界面只会递来「裁剪框 + 铺满方式」这类局部改动：升格后在完整构图上覆盖这些字段，
  // 再回到 validateProject 复验，而不是让半成品冒充一份构图。
  const upgraded = upgradeProjectV1(validated, { fit: composition.fit ?? 'cover' });
  upgraded.composition = { ...upgraded.composition, ...composition };
  return validateProject(upgraded);
}
