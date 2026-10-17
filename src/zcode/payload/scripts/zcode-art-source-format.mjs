// ZCode Dream Skin 2.0: artwork source units.
//
// The upstream presets carry focus as a 0-1 ratio while the ZCode library has always
// stored a 0-100 percent. Reading one as the other silently moves the composition by a
// factor of 100, so a value's unit is never inferred from how small it looks: every
// conversion names the format it came from, and anything unrecognised is refused
// instead of guessed.

export const ZCODE_ART_SOURCE_FORMATS = Object.freeze([
  "dream-skin-v1-normalized",
  "zcode-percent-v1",
]);

const NUMERIC_FIELDS = Object.freeze(["focusX", "focusY"]);

function requireFiniteNumber(value, field) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new Error(`ZCODE_ART_INVALID: ${field} must be a finite number, got ${JSON.stringify(value)}`);
  }
  return value;
}

export function normalizeZCodeArt(art, { sourceFormat } = {}) {
  if (art === null || typeof art !== "object" || Array.isArray(art)) {
    throw new Error("ZCODE_ART_INVALID: the artwork configuration must be an object");
  }
  if (!ZCODE_ART_SOURCE_FORMATS.includes(sourceFormat)) {
    throw new Error(`ZCODE_ART_SOURCE_UNKNOWN: ${JSON.stringify(sourceFormat)}`);
  }
  const converted = { ...art };
  for (const field of NUMERIC_FIELDS) {
    if (!(field in converted) || converted[field] === null || converted[field] === undefined) {
      continue;
    }
    const value = requireFiniteNumber(converted[field], field);
    if (sourceFormat === "dream-skin-v1-normalized") {
      if (value < 0 || value > 1) {
        throw new Error(`ZCODE_ART_OUT_OF_RANGE: a normalized ${field} must sit in 0..1, got ${value}`);
      }
      // Rounded to whole percent because the renderer emits a background-position
      // percentage; 0.76 means 76%, not 0.76%.
      converted[field] = Math.round(value * 100);
      continue;
    }
    if (value < 0 || value > 100) {
      throw new Error(`ZCODE_ART_OUT_OF_RANGE: a percent ${field} must sit in 0..100, got ${value}`);
    }
    // Already in the client's own unit: passed through untouched, never re-scaled.
    converted[field] = value;
  }
  return converted;
}

export function describeZCodeArtSource(sourceFormat) {
  if (sourceFormat === "dream-skin-v1-normalized") {
    return "upstream 0-1 ratio, converted to ZCode percent";
  }
  if (sourceFormat === "zcode-percent-v1") {
    return "ZCode native 0-100 percent, kept as written";
  }
  return "unknown source format";
}

/**
 * What the ZCode renderer is allowed to receive.
 *
 * The renderer writes `background-position: <focusX>% <focusY>%` (zcode-renderer-inject.js),
 * so it needs percent. A package accepted by the shipped payload gate carries a 0-1 ratio
 * (injector.mjs normalizedUnit), and the private library that predates 2.0 stores percent
 * directly. The two are told apart by a declared source, never by looking at how small the
 * number is: an undeclared value is passed through untouched.
 */
export function resolveZCodeArtForRenderer(art, sourceFormat) {
  if (art === null || art === undefined || typeof art !== "object") {
    return { art: art ?? null, converted: false, sourceFormat: null };
  }
  if (!sourceFormat || sourceFormat === "zcode-percent-v1") {
    return { art: { ...art }, converted: false, sourceFormat: sourceFormat || "zcode-percent-v1" };
  }
  return { art: normalizeZCodeArt(art, { sourceFormat }), converted: true, sourceFormat };
}
