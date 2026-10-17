export const parseHex = (color) => {
  if (!color) return { r: 0, g: 0, b: 0 };
  if (color.startsWith('rgb')) {
    const m = color.match(/rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
    if (m) return { r: parseInt(m[1]), g: parseInt(m[2]), b: parseInt(m[3]) };
  }
  let hex = color.replace('#', '');
  if (hex.length === 3) hex = hex.split('').map(c => c + c).join('');
  return {
    r: parseInt(hex.slice(0, 2), 16) || 0,
    g: parseInt(hex.slice(2, 4), 16) || 0,
    b: parseInt(hex.slice(4, 6), 16) || 0,
  };
};

export const hexToRgba = (color, alpha) => { const { r, g, b } = parseHex(color); return `rgba(${r}, ${g}, ${b}, ${alpha})`; };
export const hexToRgbOnly = (color) => { const { r, g, b } = parseHex(color); return `${r}, ${g}, ${b}`; };

export const lightenHex = (hex, percent) => {
  let { r, g, b } = parseHex(hex);
  r = Math.min(255, Math.floor(r + (255 - r) * percent));
  g = Math.min(255, Math.floor(g + (255 - g) * percent));
  b = Math.min(255, Math.floor(b + (255 - b) * percent));
  return `#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
};

export const darkenHex = (hex, percent) => {
  let { r, g, b } = parseHex(hex);
  r = Math.max(0, Math.floor(r * (1 - percent)));
  g = Math.max(0, Math.floor(g * (1 - percent)));
  b = Math.max(0, Math.floor(b * (1 - percent)));
  return `#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
};

// Convert hex color + opacity to hex-with-alpha string (e.g. #ffffff + 0.1 → #ffffff19)
// Matches Cherry Studio's official border format exactly
export const hexWithAlpha = (hex, opacity) => {
  const alpha = Math.round(Math.max(0, Math.min(1, opacity)) * 255)
    .toString(16).padStart(2, '0');
  const base = hex.replace('#', '').slice(0, 6);
  return `#${base}${alpha}`;
};

// Round float to avoid 0.15000000000000002 style bugs
export const roundAlpha = (val, decimals = 2) =>
  Math.round(val * Math.pow(10, decimals)) / Math.pow(10, decimals);
