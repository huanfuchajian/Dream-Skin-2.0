// Pure ZCode theme contract: profile regions become validator-registered part
// assignments, the compatibility mode becomes a renderer config, and reports
// become terminal summaries. No DOM, no CDP, no I/O — everything here is
// unit-testable and shared by the injector, the product scripts and the tests.

export const ZCODE_SKIN_IDS = Object.freeze({
  style: "zcode-dream-skin-style",
  background: "zcode-dream-skin-background",
  overlay: "zcode-dream-skin-overlay",
});

export const ZCODE_COMPATIBILITY_MODES = Object.freeze(["full", "safe", "deny"]);

// Selector -> [data-ds-part] assignment. The part names are registered in the
// Safe CSS validator (SAFE_CSS_PARTS) so user themes can restyle exactly these
// surfaces and nothing else. Broad attribute selectors (data-state, aria-*)
// are deliberately registered without built-in CSS: they exist so a future
// verified pass can opt in per selector, never by default.
export const ZCODE_PART_ASSIGNMENTS = Object.freeze({
  // SAFE
  "[data-workspace-shell]": "zcode-shell",
  "[data-root-workspace-surface]": "zcode-surface",
  "[data-desktop-window-frame]": "zcode-window-frame",
  "#sidebar": "zcode-sidebar",
  '[data-testid="sidebar"]': "zcode-sidebar",
  "[data-workspace-sidebar-panel]": "zcode-sidebar-panel",
  "[data-purpose-section-list]": "zcode-section-list",
  "[data-purpose-section-drag-handle]": "zcode-drag-handle",
  "[data-task-row-metadata]": "zcode-task-metadata",
  "[data-task-title-marquee-track]": "zcode-marquee-track",
  "main": "zcode-main",
  "[data-workspace-conversation-frame]": "zcode-conversation",
  "[data-panel]": "zcode-panel",
  "header": "zcode-header",
  "[data-workspace-header-variant]": "zcode-header",
  "footer": "zcode-footer",
  // CAUTION (off unless explicitly allowed after per-selector verification)
  "[data-v4-composer-dock]": "zcode-composer",
  "[data-v4-composer-dock-content]": "zcode-composer-content",
  "[data-composer-leading-actions]": "zcode-composer-actions",
  "[data-composer-collapse-priority]": "zcode-composer-collapse",
  "[data-chat-toolbar-popover-trigger]": "zcode-toolbar-trigger",
  '[data-slot="dialog-header"]': "zcode-dialog-header",
  '[data-slot="dialog-title"]': "zcode-dialog-title",
  '[data-slot="tabs"]': "zcode-tabs",
  '[data-slot="tabs-list"]': "zcode-tabs-list",
  '[data-slot="tabs-trigger"]': "zcode-tabs-trigger",
  '[data-slot="tooltip-trigger"]': "zcode-tooltip-trigger",
  "[data-state]": "zcode-state",
  "[data-variant]": "zcode-variant",
  "[data-size]": "zcode-size",
  "[data-disabled]": "zcode-disabled",
  "[aria-disabled]": "zcode-aria-disabled",
  "[aria-haspopup]": "zcode-aria-haspopup",
  "[aria-expanded]": "zcode-aria-expanded",
  "[aria-selected]": "zcode-aria-selected",
  "[aria-pressed]": "zcode-aria-pressed",
  '[data-testid="task-new-button"]': "zcode-action-new-task",
  '[data-testid="automations-open"]': "zcode-action-automations",
  '[data-testid="plugin-store-sidebar-open"]': "zcode-action-plugin-store",
  '[data-testid="project-add"]': "zcode-action-project-add",
  '[data-testid="project-section"]': "zcode-action-project-section",
  '[data-testid="workspace-list"]': "zcode-action-workspace-list",
  '[data-testid="task-list"]': "zcode-action-task-list",
});

const clamp = (value, min, max, fallback) => {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return fallback;
  return Math.min(max, Math.max(min, numeric));
};

// CAUTION selectors are opt-in by name. Unknown names are ignored but reported
// so a typo can never silently widen the injection range.
export function resolveCautionAllowlist(requested = []) {
  const cautionNames = new Set(Object.keys(ZCODE_PART_ASSIGNMENTS));
  const accepted = [];
  const ignored = [];
  for (const selector of requested ?? []) {
    if (cautionNames.has(selector)) accepted.push(selector);
    else ignored.push(String(selector));
  }
  return { accepted: [...new Set(accepted)], ignored };
}

// Maps every profile selector onto its part. Selectors without an assignment
// are reported in `unmatched` — callers must treat a non-empty list as a
// contract break, not silently drop them.
export function assignZCodeParts(profile, cautionEnabled = []) {
  const regions = profile?.regions ?? {};
  const safe = regions.safe ?? [];
  const caution = regions.caution ?? [];
  const allowed = new Set(resolveCautionAllowlist(cautionEnabled).accepted);
  const entries = [];
  const unmatched = [];
  for (const [selector, region] of [
    ...safe.map((selector) => [selector, "safe"]),
    ...caution.map((selector) => [selector, "caution"]),
  ]) {
    const part = ZCODE_PART_ASSIGNMENTS[selector];
    if (!part) { unmatched.push(selector); continue; }
    if (region === "caution" && !allowed.has(selector)) continue;
    entries.push({ selector, part, region });
  }
  return { entries, unmatched };
}

// Builds the renderer-side config. Safe Mode ships no region entries at all:
// the payload then styles only the safe-mode anchor. Deny ships nothing.
export function buildZCodeRendererConfig({ profile, compatibilityMode, cautionEnabled = [], art = null, revision = "" }) {
  const mode = ZCODE_COMPATIBILITY_MODES.includes(compatibilityMode) ? compatibilityMode : "deny";
  const assigned = mode === "full" ? assignZCodeParts(profile, cautionEnabled) : { entries: [], unmatched: [] };
  const artConfig = art ? {
    focusX: clamp(art.focusX, 0, 100, 50),
    focusY: clamp(art.focusY, 0, 100, 50),
    zoom: clamp(art.zoom, 50, 200, 100),
    dim: clamp(art.dim, 0, 0.85, 0.3),
    blur: clamp(art.blur, 0, 30, 0),
  } : null;
  return {
    mode,
    entries: assigned.entries,
    unmatched: assigned.unmatched,
    doNotTouch: [...(profile?.regions?.doNotTouch ?? [])],
    safeModeSelectors: [...(profile?.safeModeSelectors ?? ["body"])],
    art: artConfig,
    revision: String(revision ?? ""),
  };
}

// Terminal summary for a zcode theme run. Fields are quoted from the report —
// the summary never invents or renames numbers, and stale fields from earlier
// schema drafts (elementCount, nodeCount, ...) must not reappear.
export function zcodeThemeSummary(report = {}) {
  const verify = report.verify ?? {};
  return {
    mode: report.mode ?? "",
    compatibilityMode: report.compatibilityMode ?? "",
    applied: Boolean(report.applied),
    revision: report.revision ?? "",
    styleCount: verify.styleCount ?? 0,
    backgroundCount: verify.backgroundCount ?? 0,
    overlayCount: verify.overlayCount ?? 0,
    taggedParts: verify.taggedParts ?? 0,
    skippedSelectors: verify.skippedSelectors ?? 0,
    doNotTouchProtected: verify.doNotTouchProtected ?? 0,
    errors: (report.errors ?? []).length,
  };
}
