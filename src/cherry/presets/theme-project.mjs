import { createHash } from 'node:crypto';
import { validateComposition } from './composition.mjs';
import { InputError } from './input-error.mjs';

const SCHEMA = 'dream-skin-theme-project/1';
const SCHEMA_V2 = 'dream-skin-theme-project/2';
const SOURCES = ['dream-skin-v1-normalized', 'editor-v1-normalized'];
const HEX = /^#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/;
const RGBA = /^rgba\((\d{1,3}), ?(\d{1,3}), ?(\d{1,3}), ?(0|1|0?\.\d+|1\.0+)\)$/;
const SHA = /^[0-9a-f]{64}$/;
const COLOR_KEY = /^[a-z][a-zA-Z0-9-]{0,31}$/; // 原版合同用 camelCase（panelAlt/accentAlt）
const TARGET = /^[a-z0-9._-]{1,64}$/;
const NAME = /^[\p{L}\p{N}][\p{L}\p{N} \-.()]{0,119}$/u;
// Path rule mirrors the frozen upstream stack (vendor/dream-skin-v1.5.18/windows/scripts/
// theme-windows.ps1: Assert-DreamSkinZipPathComponent, Test-DreamSkinWindowsReservedPathStem).
const PATH_UNSAFE = /[\u0000-\u001f<>:"|?*#\\]/;
const RESERVED_STEM = /^(?:CON|PRN|AUX|NUL|COM[1-9\u00B9\u00B2\u00B3]|LPT[1-9\u00B9\u00B2\u00B3])$/i;
const UPSTREAM_META_KEYS = ['schemaVersion', 'id', 'name', 'art', 'colors', 'image', 'appearance'];
const UPSTREAM_COLOR_KEYS = ['background', 'panel', 'panelAlt', 'accent', 'accentAlt',
  'secondary', 'highlight', 'text', 'muted', 'line'];
const NOT_PORTABLE = { css: 'upstream_css_not_portable', scripts: 'upstream_scripts_not_executed' };

const fail = (code, field) => { throw new InputError(code, field); };
const plainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const num = (v, lo, hi, field) => {
  if (typeof v !== 'number' || !Number.isFinite(v)) fail('bad_number', field);
  if (v < lo || v > hi) fail('out_of_range', field);
  return v;
};

function color(v, field) {
  if (typeof v !== 'string') fail('bad_color', field);
  const s = v.toLowerCase();
  if (HEX.test(s)) return s;
  const m = RGBA.exec(s);
  if (!m) fail('bad_color', field);
  const rgb = [m[1], m[2], m[3]].map(Number);
  if (rgb.some((n) => n > 255)) fail('bad_color', field);
  const a = Number(m[4]);
  if (a < 0 || a > 1) fail('bad_color', field);
  return 'rgba(' + rgb.join(', ') + ', ' + a + ')';
}

function relativePath(v) {
  if (typeof v !== 'string' || v.length === 0 || v.length > 200) fail('bad_path', 'image.path');
  if (PATH_UNSAFE.test(v)) fail('bad_path', 'image.path');
  if (v.startsWith('/')) fail('bad_path', 'image.path');
  if (/^[a-zA-Z]:/.test(v)) fail('bad_path', 'image.path');
  for (const part of v.split('/')) {
    if (part === '' || part === '.' || part === '..') fail('bad_path', 'image.path');
    if (part.endsWith(' ') || part.endsWith('.')) fail('bad_path', 'image.path');
    if (RESERVED_STEM.test(part.split('.')[0])) fail('reserved_path', 'image.path');
  }
  return v;
}

function image(v) {
  if (!plainObject(v)) fail('bad_image', 'image');
  const path = relativePath(v.path);
  if (typeof v.sha256 !== 'string' || !SHA.test(v.sha256)) fail('bad_sha256', 'image.sha256');
  return { path, sha256: v.sha256 };
}

const art = (v) => {
  if (!plainObject(v)) fail('bad_art', 'normalizedArt');
  return {
    focusX: num(v.focusX, 0, 1, 'normalizedArt.focusX'),
    focusY: num(v.focusY, 0, 1, 'normalizedArt.focusY'),
    zoom: num(v.zoom, 50, 200, 'normalizedArt.zoom'),
    dim: num(v.dim, 0, 0.85, 'normalizedArt.dim'),
    blur: num(v.blur, 0, 30, 'normalizedArt.blur')
  };
};

const surfaces = (v) => {
  if (!plainObject(v)) fail('bad_surfaces', 'surfaces');
  return { opacity: num(v.opacity, 0, 1, 'surfaces.opacity'), radius: num(v.radius, 0, 24, 'surfaces.radius') };
};

function colors(v) {
  if (!plainObject(v)) fail('bad_colors', 'colors');
  const out = {};
  for (const [k, raw] of Object.entries(v)) {
    if (!COLOR_KEY.test(k)) fail('bad_color_key', 'colors.' + k);
    out[k] = color(raw, 'colors.' + k);
  }
  return out;
}

function derivedAsset(v) {
  if (!plainObject(v)) fail('bad_derived', 'derived');
  const path = relativePath(v.path);
  if (typeof v.sha256 !== 'string' || !SHA.test(v.sha256)) fail('bad_sha256', 'derived.sha256');
  return { path, sha256: v.sha256 };
}

function stringList(v, pattern, code, field) {
  if (!Array.isArray(v) || v.length > 64) fail(code, field);
  return v.map((s) => { if (typeof s !== 'string' || !pattern.test(s)) fail(code, field); return s; });
}

const nameOf = (v, field) => {
  if (typeof v !== 'string' || !NAME.test(v)) fail('bad_name', field);
  return v;
};

export function validateProject(value) {
  if (!plainObject(value)) fail('bad_project', 'root');
  if (value.schema !== SCHEMA && value.schema !== SCHEMA_V2) fail('unknown_schema', 'schema');
  if (!plainObject(value.source) || !SOURCES.includes(value.source.format)) fail('bad_source', 'source');
  const project = {
    schema: value.schema,
    id: nameOf(value.id, 'id'),
    name: nameOf(value.name, 'name'),
    source: { format: value.source.format,
      ref: typeof value.source.ref === 'string' ? value.source.ref.slice(0, 200) : null },
    image: image(value.image),
    normalizedArt: art(value.normalizedArt),
    colors: colors(value.colors),
    surfaces: surfaces(value.surfaces),
    targets: value.targets === undefined ? [] : stringList(value.targets, TARGET, 'bad_target', 'targets'),
    warnings: Array.isArray(value.warnings) ? value.warnings.filter((w) => plainObject(w)) : [],
    sourceManifest: plainObject(value.sourceManifest) ? value.sourceManifest : null
  };
  // 只供界面显示的版本号（2026-10-09 拍板：加展示字段，不进哈希）。
  // 两条约束是有原因的：缺省时**不多出这个键**，否则盘上既有记录与已导出包的 project.json
  // 字节会变；而它不进 projectRevision 的 visual 集，所以版本改动不会被 CAS 看见——
  // 这是明知故取的那根缺失的轴，写在原地而不是藏在注释里。
  if (value.version !== undefined && value.version !== null) {
    if (typeof value.version !== 'string' || value.version.length === 0 || value.version.length > 32) {
      fail('bad_version', 'version');
    }
    project.version = value.version;
  }
  // /2 才带构图；/1 的形状与含义保持原样，升格只发生在用户编辑保存时（设计 §5）。
  if (value.schema === SCHEMA_V2) {
    project.composition = validateComposition(value.composition);
    project.derived = value.derived === undefined || value.derived === null
      ? null : derivedAsset(value.derived);
    if (project.derived !== null) {
      if (project.derived.path === project.image.path) fail('derived_conflict', 'derived.path');
      if (project.derived.sha256 === project.image.sha256) fail('derived_conflict', 'derived.sha256');
    }
  }
  return structuredClone(project);
}

const UPSTREAM_ART_KEYS = ['focusX', 'focusY', 'zoom', 'dim', 'blur'];
const UPSTREAM_DEFAULTS = { zoom: 100, dim: 0, blur: 0 };

const warn = (field, reason, action) => ({ field, reason, action });

// One entry per unsupported field, generated independently: a later field must never
// replace or overwrite the record of an earlier one.
function upstreamWarnings(metadata) {
  const out = [];
  for (const k of Object.keys(metadata)) {
    if (UPSTREAM_META_KEYS.includes(k)) continue;
    if (NOT_PORTABLE[k]) out.push(warn(k, NOT_PORTABLE[k], 'not_executed_requires_review'));
    else out.push(warn(k, 'unknown_upstream_field', 'ignored_not_converted'));
  }
  if (metadata.appearance !== undefined && typeof metadata.appearance !== 'string') {
    out.push(warn('appearance', 'unsupported_appearance_shape', 'ignored_not_converted'));
  }
  if (plainObject(metadata.art)) {
    for (const k of Object.keys(metadata.art)) {
      if (!UPSTREAM_ART_KEYS.includes(k)) {
        out.push(warn('art.' + k, 'unsupported_art_parameter', 'not_converted'));
      }
    }
  }
  if (plainObject(metadata.colors)) {
    for (const k of Object.keys(metadata.colors)) {
      if (!UPSTREAM_COLOR_KEYS.includes(k)) {
        out.push(warn('colors.' + k, 'unknown_upstream_color_key', 'not_converted'));
      }
    }
  }
  return out;
}

export function importUpstreamMetadata(metadata, { sourceFormat, image: img } = {}) {
  if (!SOURCES.includes(sourceFormat)) fail('unknown_source_format', 'sourceFormat');
  if (!plainObject(metadata)) fail('bad_metadata', 'metadata');
  if (sourceFormat === 'editor-v1-normalized') {
    // Validate the incoming schema first; never paper over it by rewriting.
    if (metadata.schema !== SCHEMA) fail('unknown_schema', 'schema');
    const project = validateProject(metadata);
    if (project.source.format !== sourceFormat) fail('source_mismatch', 'source.format');
    if (img !== undefined) {
      const supplied = image(img);
      if (supplied.path !== project.image.path || supplied.sha256 !== project.image.sha256) {
        fail('image_conflict', 'image');
      }
    }
    return { project, warnings: project.warnings };
  }
  if (metadata.schemaVersion !== 1) fail('unknown_upstream_schema', 'schemaVersion');
  const parsedImage = image(img);
  // The declared image name is part of the upstream contract: it must agree with the
  // image identity supplied by the caller, so no second conflicting identity can exist.
  if (typeof metadata.image === 'string' && relativePath(metadata.image) !== parsedImage.path) {
    fail('image_conflict', 'image.path');
  }
  const artIn = plainObject(metadata.art) ? metadata.art : fail('bad_art', 'art');
  const project = validateProject({
    schema: SCHEMA,
    id: nameOf(metadata.id, 'id'),
    name: nameOf(metadata.name, 'name'),
    source: { format: sourceFormat, ref: 'dream-skin-v1' },
    image: parsedImage,
    normalizedArt: {
      focusX: artIn.focusX, focusY: artIn.focusY,
      zoom: artIn.zoom === undefined ? UPSTREAM_DEFAULTS.zoom : artIn.zoom,
      dim: artIn.dim === undefined ? UPSTREAM_DEFAULTS.dim : artIn.dim,
      blur: artIn.blur === undefined ? UPSTREAM_DEFAULTS.blur : artIn.blur
    },
    colors: plainObject(metadata.colors) ? metadata.colors : {},
    // Upstream metadata declares no surface geometry; inventing one here would be a silent edit.
    surfaces: { opacity: 1, radius: 0 },
    targets: [],
    sourceManifest: { origin: 'dream-skin-v1', schemaVersion: 1,
      appearance: typeof metadata.appearance === 'string' ? metadata.appearance : null }
  });
  project.warnings = upstreamWarnings(metadata);
  return { project, warnings: project.warnings };
}

const canonical = (v) => {
  if (Array.isArray(v)) return v.map(canonical);
  if (plainObject(v)) {
    const out = {};
    for (const k of Object.keys(v).sort()) out[k] = canonical(v[k]);
    return out;
  }
  return v === undefined ? null : v;
};

function digest(text) { return createHash('sha256').update(text).digest('hex'); };

// project.image.sha256 is the single trusted source; a contradicting argument is refused
// instead of silently winning over the project field.
export function projectRevision(project, { imageSha256, profileSha256 } = {}) {
  const p = validateProject(project);
  if (imageSha256 !== undefined && imageSha256 !== p.image.sha256) fail('image_conflict', 'imageSha256');
  if (typeof profileSha256 !== 'string' || !SHA.test(profileSha256)) fail('bad_sha256', 'profileSha256');
  const visual = {
    id: p.id, source: p.source.format, imageSha256: p.image.sha256, profileSha256,
    art: p.normalizedArt, colors: p.colors, surfaces: p.surfaces, targets: [...p.targets].sort()
  };
  // /1 的键集合一字不改，否则盘上既有库记录会集体变成 CORRUPT_RECORD。
  if (p.schema === SCHEMA_V2) {
    visual.composition = p.composition;
    visual.derived = p.derived === null ? null : p.derived.sha256;
  }
  return digest(JSON.stringify(canonical(visual)));
}

export const PROJECT_SCHEMA = SCHEMA;
export const PROJECT_SCHEMA_V2 = SCHEMA_V2;
export const SOURCE_FORMATS = SOURCES;
// /2 记录里那份生成副本的库内路径。写死一处，包侧与库侧才不会出现第二个名字。
export const DERIVED_ASSET_PATH = 'art-crop.png';
export const UPSTREAM_CONTRACT = { metaKeys: UPSTREAM_META_KEYS, artKeys: UPSTREAM_ART_KEYS,
  colorKeys: UPSTREAM_COLOR_KEYS };
