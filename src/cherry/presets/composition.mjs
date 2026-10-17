// T2 v2 构图合同（纯函数，不碰磁盘、不碰宿主）。
// 设计 §5：内部一律 0–1；组件回调的 0–100 百分比必须经显式换算点进来，不靠猜数量级。
import { InputError } from './input-error.mjs';

const COORD_SPACE = 'oriented-source-normalized';
const ORIENTATION_POLICY = 'exif-applied-once';
const FITS = ['cover', 'contain'];

const fail = (code, field) => { throw new InputError(code, field); };
const plainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

// 0–1 且有限；越界只拒绝，绝不夹取——静默夹取会把坏输入变成另一个视觉真值。
function unit(value, field) {
  if (typeof value !== 'number' || !Number.isFinite(value)) fail('bad_number', field);
  if (value < 0 || value > 1) fail('out_of_range', field);
  return value;
}

function strictKeys(value, allowed, field) {
  for (const k of Object.keys(value)) if (!allowed.includes(k)) fail('unknown_field', field + '.' + k);
}

export function validateComposition(value) {
  if (!plainObject(value)) fail('bad_composition', 'composition');
  strictKeys(value, ['version', 'coordinateSpace', 'orientationPolicy', 'crop', 'fit', 'focal'], 'composition');
  if (value.version !== 1) fail('unknown_composition_version', 'composition.version');
  if (value.coordinateSpace !== COORD_SPACE) fail('unknown_coordinate_space', 'composition.coordinateSpace');
  if (value.orientationPolicy !== ORIENTATION_POLICY) fail('unknown_orientation_policy', 'composition.orientationPolicy');
  if (!FITS.includes(value.fit)) fail('bad_fit', 'composition.fit');

  if (!plainObject(value.crop)) fail('bad_crop', 'composition.crop');
  strictKeys(value.crop, ['x', 'y', 'width', 'height'], 'composition.crop');
  const x = unit(value.crop.x, 'composition.crop.x');
  const y = unit(value.crop.y, 'composition.crop.y');
  const width = unit(value.crop.width, 'composition.crop.width');
  const height = unit(value.crop.height, 'composition.crop.height');
  // 面积为 0 会让 cover 的除法产出 NaN 或退化矩形，NaN 比越界更难查。
  if (!(width > 0) || !(height > 0)) fail('empty_crop', 'composition.crop');
  if (x + width > 1 + 1e-9 || y + height > 1 + 1e-9) fail('crop_out_of_bounds', 'composition.crop');

  if (!plainObject(value.focal)) fail('bad_focal', 'composition.focal');
  strictKeys(value.focal, ['x', 'y'], 'composition.focal');
  const fx = unit(value.focal.x, 'composition.focal.x');
  const fy = unit(value.focal.y, 'composition.focal.y');

  return { version: 1, coordinateSpace: COORD_SPACE, orientationPolicy: ORIENTATION_POLICY,
    crop: { x, y, width, height }, fit: value.fit, focal: { x: fx, y: fy } };
}

// 没有裁剪时的构图：全图 + 中心焦点。显式构造，不给旧 /1 塞未知字段。
export const fullFrameComposition = () => validateComposition({
  version: 1, coordinateSpace: COORD_SPACE, orientationPolicy: ORIENTATION_POLICY,
  crop: { x: 0, y: 0, width: 1, height: 1 }, fit: 'cover', focal: { x: 0.5, y: 0.5 },
});

// 上游组件回调给的是 0–100 百分比；这一处是唯一的换算入口。
// 漏掉它，76 就会被当成 0.76%；反过来做则把 0.76 变成 76%。
export function cropFromPercent(percent) {
  if (!plainObject(percent)) fail('bad_percent_area', 'percent');
  strictKeys(percent, ['x', 'y', 'width', 'height'], 'percent');
  const out = {};
  for (const k of ['x', 'y', 'width', 'height']) {
    const v = percent[k];
    if (typeof v !== 'number' || !Number.isFinite(v)) fail('bad_number', 'percent.' + k);
    if (v < 0 || v > 100) fail('out_of_range', 'percent.' + k);
    out[k] = v / 100;
  }
  return out;
}

// ROI（0–1）→ 组件要的百分比区域（0–100）：上面那一处的反向，同样只在这一点换算。
// 取景框要能被恢复（设计点名复用上游的 getInitialCropFromCroppedAreaPercentages），
// 而那块 helper 收的是百分比；在这里换算一次，界面就不自己乘第二遍。
export function cropToPercent(crop) {
  if (!plainObject(crop)) fail('bad_crop_percent', 'crop');
  strictKeys(crop, ['x', 'y', 'width', 'height'], 'crop');
  const out = {};
  for (const k of ['x', 'y', 'width', 'height']) out[k] = unit(crop[k], 'crop.' + k) * 100;
  return out;
}

// ROI（0–1）↔ 像素坐标：取景件换成 react-advanced-cropper 之后，它对外说的是「相对那张图
// 转向后那一帧的像素坐标」，而库里仍然只存 0–1 的 ROI。换算只在这一对函数里发生，
// 界面与副本都不许自己再乘一次或除一次 —— 分母永远是 orientedFrame 报出的同一帧宽高。
const frameOf = (frame, field) => {
  if (!plainObject(frame)) fail('bad_frame', field);
  for (const key of ['width', 'height']) {
    const v = frame[key];
    if (typeof v !== 'number' || !Number.isFinite(v) || v <= 0) fail('bad_frame', field + '.' + key);
  }
  return { width: frame.width, height: frame.height };
};

export function cropToCoordinates(crop, frame) {
  if (!plainObject(crop)) fail('bad_crop_percent', 'crop');
  strictKeys(crop, ['x', 'y', 'width', 'height'], 'crop');
  const box = frameOf(frame, 'frame');
  const unitOf = (key) => unit(crop[key], 'crop.' + key);
  return {
    left: unitOf('x') * box.width,
    top: unitOf('y') * box.height,
    width: unitOf('width') * box.width,
    height: unitOf('height') * box.height,
  };
}

// 坐标 → 百分比区域（再交给 cropFromPercent 收成 0–1）。越界就是越界：
// 这里不夹取、不四舍五入到框内，因为那会把「取景件给的数与帧不符」这件事悄悄抹平。
export function cropFromCoordinates(coordinates, frame) {
  if (!plainObject(coordinates)) fail('bad_coordinates', 'coordinates');
  strictKeys(coordinates, ['left', 'top', 'width', 'height'], 'coordinates');
  const box = frameOf(frame, 'frame');
  const px = {};
  for (const key of ['left', 'top', 'width', 'height']) {
    const v = coordinates[key];
    if (typeof v !== 'number' || !Number.isFinite(v)) fail('bad_coordinates', 'coordinates.' + key);
    px[key] = v;
  }
  if (px.width <= 0 || px.height <= 0) fail('bad_coordinates', 'coordinates.size');
  if (px.left < 0 || px.top < 0 || px.left + px.width > box.width + 1e-6
    || px.top + px.height > box.height + 1e-6) fail('crop_out_of_bounds', 'coordinates');
  return cropFromPercent({
    x: (px.left / box.width) * 100,
    y: (px.top / box.height) * 100,
    width: (px.width / box.width) * 100,
    height: (px.height / box.height) * 100,
  });
}

// 选了一档比例之后要落库的那一块：保中心、面积守恒（装不下就等比缩到装得下），并且
// 一定落在整数像素格上——取景件对外只报整数像素，给它非整数它必然四舍五入，
// 屏幕上的一块与库里的一块就会永久差上一格（真窗口量到过这种差）。
// 比例是像素比，不是 ROI 比：同一块 ROI 在 64×48 与 48×64 两帧上收出来的结果不同，
// 所以帧必须进来，且仍然只按 orientedFrame 那一帧算。
export function fitCropToRatio(crop, ratio, frame) {
  if (!plainObject(crop)) fail('bad_crop_percent', 'crop');
  strictKeys(crop, ['x', 'y', 'width', 'height'], 'crop');
  if (typeof ratio !== 'number' || !Number.isFinite(ratio) || ratio <= 0) fail('bad_ratio', 'ratio');
  const box = frameOf(frame, 'frame');
  const now = cropToCoordinates(crop, box);
  const center = { x: now.left + now.width / 2, y: now.top + now.height / 2 };
  let width = Math.sqrt(now.width * now.height * ratio);
  let height = width / ratio;
  const over = Math.max(width / box.width, height / box.height);
  if (over > 1) { width /= over; height /= over; }
  width = Math.min(box.width, Math.max(1, Math.round(width)));
  height = Math.min(box.height, Math.max(1, Math.round(height)));
  const clamp = (value, size, limit) => Math.min(Math.max(0, Math.round(value - size / 2)), limit - size);
  return cropFromCoordinates({
    left: clamp(center.x, width, box.width),
    top: clamp(center.y, height, box.height),
    width,
    height,
  }, box);
}

// /1 只在新代码保存时显式升格。原 /1 仍可读；导入不会因为认出版本就悄悄改单位。
export function upgradeProjectV1(project, { fit = 'cover' } = {}) {
  if (!plainObject(project)) fail('bad_project', 'project');
  if (project.schema === 'dream-skin-theme-project/2') fail('already_v2', 'schema');
  if (project.schema !== 'dream-skin-theme-project/1') fail('unknown_schema', 'schema');
  const art = plainObject(project.normalizedArt) ? project.normalizedArt : null;
  const focal = art && typeof art.focusX === 'number' && typeof art.focusY === 'number'
    ? { x: art.focusX, y: art.focusY } : { x: 0.5, y: 0.5 };
  const out = structuredClone(project);
  // normalizedArt.zoom 是 50–200 的视觉缩放，界面取景倍率是 1–3；两者在此不互换。
  out.schema = 'dream-skin-theme-project/2';
  out.composition = validateComposition({
    version: 1, coordinateSpace: COORD_SPACE, orientationPolicy: ORIENTATION_POLICY,
    crop: { x: 0, y: 0, width: 1, height: 1 }, fit, focal,
  });
  return out;
}

const intPositive = (v, field) => {
  if (typeof v !== 'number' || !Number.isInteger(v) || v <= 0) fail('bad_dimension', field);
  return v;
};

// 取景框本身（源像素）只在这一处推导：`resolveComposition` 用它算 CSS，生成副本也用它算矩形。
// 视口拟合是 CSS 显示层的事，副本存的是用户框住的那块区域，所以这里不看视口——
// 换窗口尺寸不该改变入库的那份图。
export function sourceCropRect(project, sourceMetadata) {
  if (!plainObject(project) || project.schema !== 'dream-skin-theme-project/2') fail('unknown_schema', 'schema');
  const comp = validateComposition(project.composition);
  if (!plainObject(sourceMetadata)) fail('bad_source_metadata', 'sourceMetadata');
  // EXIF 只在规范化时施加一次；解码器没声明「已施加」就不猜方向（设计 §5）。
  if (sourceMetadata.orientationApplied !== true) fail('orientation_not_normalized', 'sourceMetadata.orientationApplied');
  const sw = intPositive(sourceMetadata.width, 'sourceMetadata.width');
  const sh = intPositive(sourceMetadata.height, 'sourceMetadata.height');
  const roi = {
    x: Math.floor(comp.crop.x * sw),
    y: Math.floor(comp.crop.y * sh),
    width: Math.max(1, Math.round(comp.crop.width * sw)),
    height: Math.max(1, Math.round(comp.crop.height * sh)),
  };
  if (roi.x + roi.width > sw) roi.width = sw - roi.x;
  if (roi.y + roi.height > sh) roi.height = sh - roi.y;
  return roi;
}

// 「源像素矩形」只在这一处推导，预览与实际 CSS 共用，两边因此不可能各算一次缩放。
export function resolveComposition(project, sourceMetadata, viewport) {
  const roi = sourceCropRect(project, sourceMetadata);
  const comp = validateComposition(project.composition);
  const sw = sourceMetadata.width;
  const sh = sourceMetadata.height;
  if (!plainObject(viewport)) fail('bad_viewport', 'viewport');
  const vw = intPositive(viewport.width, 'viewport.width');
  const vh = intPositive(viewport.height, 'viewport.height');

  const roiAspect = roi.width / roi.height;
  const vpAspect = vw / vh;
  let rect = { ...roi };
  let slackX = 0;
  let slackY = 0;
  if (comp.fit === 'cover' && roiAspect !== vpAspect) {
    if (roiAspect > vpAspect) {
      const keep = Math.max(1, Math.round(roi.height * vpAspect));
      slackX = Math.max(0, roi.width - keep);
      rect = { x: roi.x + Math.round(slackX * comp.focal.x), y: roi.y, width: keep, height: roi.height };
    } else {
      const keep = Math.max(1, Math.round(roi.width / vpAspect));
      slackY = Math.max(0, roi.height - keep);
      rect = { x: roi.x, y: roi.y + Math.round(slackY * comp.focal.y), width: roi.width, height: keep };
    }
  }
  // contain：整块 ROI 都要可见，留空由主题背景色填；这里不放大也不裁。

  // CSS background-position 用的是「可见窗在 ROI 内的位移比例」，不等于源焦点。
  const percent = (slack, offset) => slack <= 0 ? 50 : Number(((offset / slack) * 100).toFixed(6));
  const positionX = percent(slackX, rect.x - roi.x);
  const positionY = percent(slackY, rect.y - roi.y);

  return {
    sourcePixelRect: rect,
    targetSize: { width: vw, height: vh },
    fit: comp.fit,
    focal: { x: comp.focal.x, y: comp.focal.y },
    sourceROI: roi,
    css: { backgroundSize: comp.fit === 'cover' ? 'cover' : 'contain',
      positionXPercent: positionX, positionYPercent: positionY },
  };
}

export const COMPOSITION_CONTRACT = { version: 1, coordinateSpace: COORD_SPACE,
  orientationPolicy: ORIENTATION_POLICY, fits: FITS };
