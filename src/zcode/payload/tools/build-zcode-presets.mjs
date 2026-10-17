#!/usr/bin/env node
// ZCode Dream Skin 2.0: complete-skin preset builder.
//
// Colours are read from the vendored @catppuccin/palette package (MIT, pinned by the
// upstream VSCode extension's lockfile), never retyped here: a hand-copied hex is a
// claim nobody can trace. A tiny PNG encoder writes the derived backgrounds so the
// build needs no newly installed image software.
//
//   node windows/tools/build-zcode-presets.mjs --output <dir> [--personal-image <png|jpg|webp>]
//
// --output is a generated root, not a distribution directory; public presets go to
// <out>/public, the character skin to <out>/personal (never staged), and the preview
// index to <out>/catalog.json outside every theme package.

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import zlib from "node:zlib";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";
import { zcodeThemeRevision } from "../scripts/injector.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const windowsRoot = path.resolve(here, "..");
const require = createRequire(import.meta.url);

const PALETTE_VERSION = "1.7.1";
const palettePath = path.join(windowsRoot, "vendor", "catppuccin-palette-1.7.1", "script", "palette.js");

function loadPalette() {
  if (!fs.existsSync(palettePath)) {
    throw new Error(`PRESET_PALETTE_MISSING: vendored palette not found at ${palettePath}`);
  }
  const palette = require(palettePath).default;
  if (String(palette.version) !== PALETTE_VERSION) {
    throw new Error(`PRESET_PALETTE_VERSION: expected ${PALETTE_VERSION}, found ${palette.version}`);
  }
  return palette;
}

function hex(palette, variant, role) {
  const colours = palette[variant] && palette[variant].colors;
  const colour = colours && colours[role];
  if (!colour || typeof colour.hex !== "string") {
    throw new Error(`PRESET_PALETTE_ROLE_MISSING: ${variant}.${role}`);
  }
  return colour.hex;
}

// Surface layers are expressed as rgba so the existing base CSS keeps its own alpha
// hierarchy instead of being painted over with an opaque block.
function rgba(hexValue, alpha) {
  const value = hexValue.replace("#", "");
  const num = Number.parseInt(value, 16);
  const r = (num >> 16) & 255;
  const g = (num >> 8) & 255;
  const b = num & 255;
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

const MAPPING_VERSION = "zds2-palette-mapping/1";

// Which palette role paints which surface, per preset. Only parts this product has
// registered as themeable are touched, and the composer shell is left out until its
// selector is verified on a live window (see the caution allowlist).
const PRESETS = [
  {
    id: "zds2-cream",
    name: "Soft Cream",
    description: "Warm latte palette, low-contrast borders, light surfaces",
    variant: "latte",
    appearance: "light",
    accent: "mauve",
    emphasis: "blue",
    surfaceAlpha: 0.72,
    panelAlpha: 0.55,
    border: "surface1",
    shadow: "overlay0",
  },
  {
    id: "zds2-glass",
    name: "Deep Glass",
    description: "Mocha palette with purple accents and layered translucent surfaces",
    variant: "mocha",
    appearance: "dark",
    accent: "mauve",
    emphasis: "lavender",
    surfaceAlpha: 0.42,
    panelAlpha: 0.3,
    border: "surface2",
    shadow: "crust",
  },
  {
    id: "zds2-tech",
    name: "Blue-Green Tech",
    description: "Dark base with teal and sky accents and readable state borders",
    variant: "mocha",
    appearance: "dark",
    accent: "teal",
    emphasis: "sky",
    surfaceAlpha: 0.5,
    panelAlpha: 0.34,
    border: "surface1",
    shadow: "mantle",
  },
];

const THEMEABLE_PARTS = [
  "zcode-sidebar", "zcode-sidebar-panel", "zcode-panel", "zcode-main",
  "zcode-conversation", "zcode-header", "zcode-footer", "zcode-surface",
  "zcode-shell", "zcode-window-frame", "zcode-tabs", "zcode-tabs-list",
  "zcode-tabs-trigger", "zcode-composer-content", "zcode-composer-actions",
];

function buildThemeCss(palette, preset) {
  const v = preset.variant;
  const base = hex(palette, v, "base");
  const mantle = hex(palette, v, "mantle");
  const text = hex(palette, v, "text");
  const subtext = hex(palette, v, "subtext0");
  const accent = hex(palette, v, preset.accent);
  const emphasis = hex(palette, v, preset.emphasis);
  const border = hex(palette, v, preset.border);
  const shadow = hex(palette, v, preset.shadow);
  const surface = rgba(preset.surfaceAlpha >= 1 ? base : mantle, preset.surfaceAlpha);
  const panel = rgba(mantle, preset.panelAlpha);

  // The Safe CSS gate forbids comments, so the provenance of these values lives in
  // catalog.json instead of being written into the stylesheet.
  const lines = [
    ...THEMEABLE_PARTS.map((part) => `[data-ds-part="${part}"] { color: ${text}; }`),
    `[data-ds-part="zcode-shell"] { background-color: ${base}; }`,
    `[data-ds-part="zcode-window-frame"] { background-color: ${base}; }`,
    `[data-ds-part="zcode-surface"] { background-color: ${surface}; border-color: ${rgba(border, 0.45)}; }`,
    `[data-ds-part="zcode-sidebar"] { background-color: ${panel}; border-right-color: ${rgba(border, 0.5)}; }`,
    `[data-ds-part="zcode-sidebar-panel"] { background-color: ${panel}; border-color: ${rgba(border, 0.45)}; }`,
    `[data-ds-part="zcode-panel"] { background-color: ${panel}; border-color: ${rgba(border, 0.45)}; box-shadow: 0 10px 26px ${rgba(shadow, 0.42)}; }`,
    `[data-ds-part="zcode-main"] { background-color: ${rgba(base, 0.35)}; }`,
    `[data-ds-part="zcode-conversation"] { background-color: ${rgba(base, 0.5)}; }`,
    `[data-ds-part="zcode-header"] { background-color: ${panel}; border-bottom-color: ${rgba(border, 0.5)}; }`,
    `[data-ds-part="zcode-footer"] { background-color: ${panel}; border-top-color: ${rgba(border, 0.5)}; }`,
    `[data-ds-part="zcode-tabs"] { background-color: ${panel}; border-color: ${rgba(border, 0.45)}; border-radius: 12px; }`,
    `[data-ds-part="zcode-tabs-list"] { background-color: ${rgba(mantle, 0.5)}; border-color: ${rgba(border, 0.4)}; }`,
    `[data-ds-part="zcode-tabs-trigger"] { color: ${subtext}; border-radius: 9px; }`,
    `[data-ds-part="zcode-tabs-trigger"]:hover { color: ${text}; background-color: ${rgba(border, 0.35)}; }`,
    `[data-ds-part="zcode-tabs-trigger"]:focus-visible { color: ${text}; background-color: ${rgba(accent, 0.28)}; border-color: ${rgba(accent, 0.55)}; }`,
    `[data-ds-part="zcode-composer-content"] { background-color: ${rgba(base, 0.62)}; border-color: ${rgba(border, 0.5)}; border-radius: 14px; }`,
    `[data-ds-part="zcode-composer-actions"] { background-color: ${rgba(mantle, 0.55)}; border-color: ${rgba(border, 0.45)}; }`,
    `[data-ds-part="zcode-action-new-task"] { background-color: ${rgba(accent, 0.3)}; border-color: ${rgba(accent, 0.6)}; color: ${text}; }`,
    `[data-ds-part="zcode-action-task-list"] { background-color: ${rgba(emphasis, 0.26)}; border-color: ${rgba(emphasis, 0.55)}; color: ${text}; }`,
    `[data-ds-part="zcode-action-project-add"] { background-color: ${rgba(accent, 0.22)}; border-color: ${rgba(accent, 0.5)}; color: ${text}; }`,
    `[data-ds-part="zcode-action-automations"] { background-color: ${rgba(emphasis, 0.2)}; border-color: ${rgba(emphasis, 0.45)}; color: ${text}; }`,
    `[data-ds-part="zcode-action-plugin-store"] { background-color: ${rgba(accent, 0.18)}; border-color: ${rgba(accent, 0.42)}; color: ${text}; }`,
    `[data-ds-part="zcode-action-workspace-list"] { background-color: ${rgba(emphasis, 0.18)}; border-color: ${rgba(emphasis, 0.42)}; color: ${text}; }`,
    `[data-ds-part="zcode-section-list"] { background-color: ${panel}; border-color: ${rgba(border, 0.4)}; }`,
    `[data-ds-part="zcode-dialog-header"] { background-color: ${panel}; border-bottom-color: ${rgba(border, 0.5)}; }`,
    `[data-ds-part="zcode-dialog-title"] { color: ${text}; }`,
    `[data-ds-part="zcode-task-metadata"] { color: ${subtext}; }`,
    `[data-ds-part="zcode-drag-handle"] { background-color: ${rgba(accent, 0.4)}; border-radius: 8px; }`,
  ];
  return `${lines.join("\n")}\n`;
}

function buildThemeJson(palette, preset) {
  const v = preset.variant;
  return {
    schemaVersion: 1,
    id: preset.id,
    name: preset.name,
    image: "background.png",
    appearance: preset.appearance,
    // The shipped payload gate requires focus as a 0-1 ratio (injector.mjs
    // normalizedUnit), while the ZCode renderer consumes 0-100 percent. Packages are
    // authored in the ratio the gate accepts; the target bridge converts them
    // explicitly on the way to the renderer, and the origin record says so.
    art: { focusX: 0.5, focusY: 0.45, safeArea: "left", taskMode: "ambient" },
    colors: {
      background: hex(palette, v, "base"),
      panel: hex(palette, v, "mantle"),
      panelAlt: hex(palette, v, "crust"),
      accent: hex(palette, v, preset.accent),
      accentAlt: hex(palette, v, preset.emphasis),
      secondary: hex(palette, v, "overlay0"),
      highlight: hex(palette, v, "peach"),
      text: hex(palette, v, "text"),
      muted: hex(palette, v, "subtext0"),
      line: rgba(hex(palette, v, "surface1"), 0.45),
    },
  };
}

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (const byte of buffer) c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([length, body, crc]);
}

// A vertical layered gradient: base at the bottom, the accent band near the top-left
// where the ambient artwork is meant to sit behind the sidebar.
function derivedBackgroundPng(palette, preset, width = 2560, height = 1440) {
  const v = preset.variant;
  const top = hex(palette, v, "crust");
  const mid = hex(palette, v, "base");
  const low = hex(palette, v, "mantle");
  const accent = hex(palette, v, preset.accent);
  const toRgb = (value) => {
    const n = Number.parseInt(value.replace("#", ""), 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  };
  const [tr, tg, tb] = toRgb(top);
  const [mr, mg, mb] = toRgb(mid);
  const [lr, lg, lb] = toRgb(low);
  const [ar, ag, ab] = toRgb(accent);

  const stride = width * 3 + 1;
  const raw = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    const row = y * stride;
    raw[row] = 0; // filter: none
    const t = y / (height - 1);
    const from = t < 0.5 ? [tr, tg, tb] : [mr, mg, mb];
    const to = t < 0.5 ? [mr, mg, mb] : [lr, lg, lb];
    const local = t < 0.5 ? t / 0.5 : (t - 0.5) / 0.5;
    for (let x = 0; x < width; x++) {
      const cx = x / (width - 1);
      const halo = Math.max(0, 1 - Math.hypot((cx - 0.18) * 1.6, (t - 0.22) * 2.2));
      const blend = halo * halo * 0.34;
      const offset = row + 1 + x * 3;
      raw[offset] = Math.round(from[0] + (to[0] - from[0]) * local + (ar - from[0]) * blend);
      raw[offset + 1] = Math.round(from[1] + (to[1] - from[1]) * local + (ag - from[1]) * blend);
      raw[offset + 2] = Math.round(from[2] + (to[2] - from[2]) * local + (ab - from[2]) * blend);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // colour type: truecolour
  const idat = zlib.deflateSync(raw, { level: 9 });
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", idat),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function writeThemeDirectory(root, preset, palette, { imageBuffer, imageName }) {
  const directory = path.join(root, preset.id);
  fs.rmSync(directory, { recursive: true, force: true });
  fs.mkdirSync(directory, { recursive: true });
  const theme = buildThemeJson(palette, preset);
  theme.image = imageName;
  const css = buildThemeCss(palette, preset);
  fs.writeFileSync(path.join(directory, "theme.json"), `${JSON.stringify(theme, null, 2)}\n`, "utf8");
  fs.writeFileSync(path.join(directory, "theme.css"), css, "utf8");
  fs.writeFileSync(path.join(directory, imageName), imageBuffer);
  return { directory, theme, css };
}

function parseArguments(argv) {
  const options = { output: "", personalImage: "", personalOnly: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--output") options.output = path.resolve(argv[++i] ?? "");
    else if (arg === "--personal-image") options.personalImage = path.resolve(argv[++i] ?? "");
    else if (arg === "--personal-only") options.personalOnly = true;
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!options.output) throw new Error("--output is required and must be a generated root");
  if (options.personalOnly && !options.personalImage) {
    throw new Error("--personal-only requires --personal-image: there is nothing left to build without it");
  }
  return options;
}

export function buildPresets({ output, personalImage = "", personalOnly = false }) {
  const palette = loadPalette();
  const publicRoot = path.join(output, "public");
  const personalRoot = path.join(output, "personal");
  fs.mkdirSync(publicRoot, { recursive: true });

  const entries = [];
  // Deriving the three shipped backgrounds is a build-time job: on a user's machine the
  // only thing left to compose is their own artwork, and redrawing three 2560x1440
  // canvases per skin change would make an ordinary click do unbounded work.
  if (!personalOnly) for (const preset of PRESETS) {
    const imageBuffer = derivedBackgroundPng(palette, preset);
    const written = writeThemeDirectory(publicRoot, preset, palette, { imageBuffer, imageName: "background.png" });
    entries.push({
      id: preset.id,
      kind: "public",
      directory: path.relative(output, written.directory).split(path.sep).join("/"),
      imageSource: `derived from @catppuccin/palette ${PALETTE_VERSION} (${preset.variant})`,
      name: preset.name,
      description: preset.description,
      appearance: preset.appearance,
      revision: zcodeThemeRevision({ cssText: written.css, artDataUrl: null, art: written.theme.art }),
      paletteProvenance: `@catppuccin/palette ${PALETTE_VERSION} (${preset.variant}) via ${MAPPING_VERSION}`,
      artSourceFormat: "dream-skin-v1-normalized",
      targetArtPercent: { focusX: 50, focusY: 45 },
    });
  }

  let characterState = "awaiting-image";
  if (personalImage) {
    if (!fs.existsSync(personalImage)) throw new Error(`PRESET_PERSONAL_IMAGE_MISSING: ${personalImage}`);
    const buffer = fs.readFileSync(personalImage);
    if (buffer.length === 0 || buffer.length > 10 * 1024 * 1024) {
      throw new Error("PRESET_PERSONAL_IMAGE_SIZE: the referenced image must be a non-empty file up to 10 MiB");
    }
    const preset = {
      id: "zds2-character",
      name: "Character Ambience",
      description: "Your own artwork, kept to the machine: composed to the right, text over the darkest area",
      variant: "mocha",
      appearance: "dark",
      accent: "mauve",
      emphasis: "lavender",
      surfaceAlpha: 0.45,
      panelAlpha: 0.32,
      border: "surface2",
      shadow: "crust",
    };
    const written = writeThemeDirectory(personalRoot, preset, palette, {
      imageBuffer: buffer,
      imageName: `character${path.extname(personalImage).toLowerCase() || ".png"}`,
    });
    written.theme.art = { focusX: 1, focusY: 0.5, safeArea: "right", taskMode: "ambient" };
    fs.writeFileSync(path.join(written.directory, "theme.json"), `${JSON.stringify(written.theme, null, 2)}\n`, "utf8");
    entries.push({
      id: preset.id,
      kind: "personal",
      directory: path.relative(output, written.directory).split(path.sep).join("/"),
      imageSource: "local copy of the authorised active reference image; never staged",
      name: preset.name,
      description: preset.description,
      appearance: preset.appearance,
      revision: zcodeThemeRevision({ cssText: written.css, artDataUrl: null, art: written.theme.art }),
    });
    characterState = "built";
  }

  const catalog = {
    schemaVersion: "zcode-dream-skin-preset-catalog/1",
    mappingVersion: MAPPING_VERSION,
    paletteVersion: PALETTE_VERSION,
    generatedAtUtc: "deterministic: derived only from the pinned palette and mapping",
    presets: entries,
    character: characterState,
    stagedKinds: ["public"],
  };
  fs.writeFileSync(path.join(output, "catalog.json"), `${JSON.stringify(catalog, null, 2)}\n`, "utf8");
  // The tree that ships beside the presets describes itself with bare directory
  // names, so a preset root can be copied anywhere and still be seedable.
  const stagedCatalog = {
    ...catalog,
    presets: catalog.presets
      .filter((entry) => entry.kind === "public")
      .map((entry) => ({ ...entry, directory: entry.id })),
  };
  fs.writeFileSync(path.join(publicRoot, "catalog.json"), `${JSON.stringify(stagedCatalog, null, 2)}\n`, "utf8");
  return catalog;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArguments(process.argv.slice(2));
    const catalog = buildPresets(options);
    process.stdout.write(`${JSON.stringify({ ok: true, presets: catalog.presets.length, character: catalog.character })}\n`);
    process.exitCode = 0;
  } catch (error) {
    process.stderr.write(`${String(error && error.message ? error.message : error)}\n`);
    process.exitCode = 1;
  }
}

export { PRESETS, MAPPING_VERSION, PALETTE_VERSION, THEMEABLE_PARTS };
export default buildPresets;
void os;
