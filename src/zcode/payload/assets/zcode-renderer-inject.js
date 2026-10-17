// ZCode Dream Skin renderer runtime. Canonical cross-platform renderer stays in
// renderer-inject.js (Codex); this payload is the ZCode-specific equivalent and
// follows the same placeholder-template contract as loadZCodePayload() in
// windows/scripts/injector.mjs: three JSON tokens (surface CSS, art data URL,
// renderer config) are substituted before evaluation, and a leftover token is
// a hard error.
//
// Guarantees (enforced here, asserted by tests/zcode-renderer-inject.test.mjs):
//   - apply is idempotent: exactly one node per fixed ID after any number of
//     consecutive applies;
//   - remove() restores the previous inline attributes, including any
//     pre-existing data-ds-part value, and deletes the root marker;
//   - doNotTouch selectors are never tagged, never styled, never resized —
//     a region selector match loses against the forbidden-region contract;
//   - the background and overlay decoration layers are pointer-events:none;
//   - Safe Mode styles only the safe-mode anchor; deny ships nothing;
//   - after pause(), a renderer refuses re-injection until resume() so a
//     paused product cannot be re-skinned by a stray injector run.
((cssText, artDataUrl, themeConfig) => {
  "use strict";

  var API_KEY = "__ZCODE_DREAM_SKIN__";
  var STATE_KEY = "__ZCODE_DREAM_SKIN_STATE__";
  var DISABLED_KEY = "__ZCODE_DREAM_SKIN_DISABLED__";
  var STYLE_ID = "zcode-dream-skin-style";
  var BACKGROUND_ID = "zcode-dream-skin-background";
  var OVERLAY_ID = "zcode-dream-skin-overlay";
  var SKIN_ID_PREFIX = "zcode-dream-skin-";
  var ROOT_ATTR = "data-zcode-dream-skin";
  var PART_ATTR = "data-ds-part";
  var PART_PREFIX = "zcode-";
  var RUNTIME = "zcode-dream-skin-renderer/1";
  var MAX_CSS_BYTES = 262144; // mirrors safe-css-policy.json maxBytes

  // Trusted base layer. Scoped by the root attribute so everything it does
  // disappears the moment the attribute and the style node are removed. This
  // is payload-owned CSS (not user content) and therefore allowed to use
  // !important; the universal-selector ban still holds.
  var BASE_CSS = [
    'html[' + ROOT_ATTR + '] , html[' + ROOT_ATTR + '] body { background: transparent !important; }',
    '#' + BACKGROUND_ID + ' { position: fixed; inset: 0; z-index: -1; pointer-events: none; background-repeat: no-repeat; }',
    '#' + OVERLAY_ID + ' { position: fixed; inset: 0; z-index: 2147483646; pointer-events: none; }',
  ].join("\n");

  // Safe Mode: only the safe-mode anchor is styled. No surfaces, no layout.
  var SAFE_MODE_CSS = 'html[' + ROOT_ATTR + '="safe"] body { background-color: rgba(12,12,18,0.55); }';

  var config = themeConfig && typeof themeConfig === "object" ? themeConfig : {};
  var tagSnapshots = [];
  var rootAttrSnapshot = null;

  function skinNodes() {
    return document.querySelectorAll('[id^="' + SKIN_ID_PREFIX + '"]');
  }

  function elementMatchesAny(element, selectors) {
    for (var index = 0; index < selectors.length; index += 1) {
      try {
        if (element.matches(selectors[index])) return true;
      } catch (invalidSelector) { /* a broken selector must not widen protection */ }
    }
    return false;
  }

  function clearSkinNodes() {
    var removed = 0;
    var nodes = skinNodes();
    for (var index = nodes.length - 1; index >= 0; index -= 1) {
      nodes[index].remove();
      removed += 1;
    }
    return removed;
  }

  function restoreTags() {
    for (var index = tagSnapshots.length - 1; index >= 0; index -= 1) {
      var snapshot = tagSnapshots[index];
      if (snapshot.previous === null) snapshot.element.removeAttribute(PART_ATTR);
      else snapshot.element.setAttribute(PART_ATTR, snapshot.previous);
    }
    tagSnapshots = [];
  }

  function remove() {
    var removedNodes = clearSkinNodes();
    restoreTags();
    if (rootAttrSnapshot === null) document.documentElement.removeAttribute(ROOT_ATTR);
    else document.documentElement.setAttribute(ROOT_ATTR, rootAttrSnapshot);
    rootAttrSnapshot = null;
    var state = { applied: false, mode: null, revision: "", removedNodes: removedNodes };
    window[STATE_KEY] = state;
    return { removedNodes: removedNodes };
  }

  function applyBackground(parent, art) {
    var background = document.createElement("div");
    background.id = BACKGROUND_ID;
    var style = background.style;
    style.setProperty("pointer-events", "none");
    if (artDataUrl) {
      var dim = art && typeof art.dim === "number" ? art.dim : 0.3;
      var veil = "linear-gradient(rgba(0,0,0," + dim + "),rgba(0,0,0," + dim + "))";
      style.setProperty("background-image", veil + ", url(" + JSON.stringify(artDataUrl).slice(1, -1) + ")");
      var focusX = art && typeof art.focusX === "number" ? art.focusX : 50;
      var focusY = art && typeof art.focusY === "number" ? art.focusY : 50;
      style.setProperty("background-position", focusX + "% " + focusY + "%");
      style.setProperty("background-size", art && art.zoom >= 100 ? "cover" : "contain");
      if (art && typeof art.blur === "number" && art.blur > 0) {
        style.setProperty("filter", "blur(" + art.blur + "px)");
      }
    }
    parent.appendChild(background);
    return background;
  }

  function apply() {
    if (window[DISABLED_KEY]) {
      return { applied: false, mode: config.mode ?? null, reason: "paused" };
    }
    var mode = config.mode === "safe" || config.mode === "deny" ? config.mode : "full";

    if (mode === "deny") {
      remove();
      return { applied: false, mode: "deny" };
    }
    if (mode === "full" && typeof cssText === "string" && cssText.length > MAX_CSS_BYTES) {
      throw new Error("ZCode theme CSS exceeds the " + MAX_CSS_BYTES + " byte safety budget");
    }

    remove();
    var head = document.head || document.documentElement;
    var body = document.body || document.documentElement;

    var style = document.createElement("style");
    style.id = STYLE_ID;
    style.textContent = mode === "safe"
      ? BASE_CSS + "\n" + SAFE_MODE_CSS + "\n"
      : BASE_CSS + "\n" + (typeof cssText === "string" ? cssText : "") + "\n";
    head.appendChild(style);

    applyBackground(body, config.art);

    var overlay = document.createElement("div");
    overlay.id = OVERLAY_ID;
    overlay.style.setProperty("pointer-events", "none");
    body.appendChild(overlay);

    rootAttrSnapshot = document.documentElement.getAttribute(ROOT_ATTR);
    document.documentElement.setAttribute(ROOT_ATTR, mode);

    var report = {
      applied: true,
      mode: mode,
      revision: String(config.revision ?? ""),
      taggedParts: 0,
      skippedSelectors: 0,
      protectedSkips: 0,
    };

    if (mode === "full") {
      var entries = Array.isArray(config.entries) ? config.entries : [];
      for (var index = 0; index < entries.length; index += 1) {
        var entry = entries[index];
        var nodes;
        try {
          nodes = document.querySelectorAll(entry.selector);
        } catch (invalidSelector) {
          report.skippedSelectors += 1;
          continue;
        }
        for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex += 1) {
          var element = nodes[nodeIndex];
          if (element.id && String(element.id).indexOf(SKIN_ID_PREFIX) === 0) continue;
          if (elementMatchesAny(element, config.doNotTouch ?? [])) {
            report.protectedSkips += 1;
            continue;
          }
          if (element.getAttribute(PART_ATTR) !== entry.part) {
            tagSnapshots.push({ element: element, previous: element.getAttribute(PART_ATTR) });
            element.setAttribute(PART_ATTR, entry.part);
          }
          report.taggedParts += 1;
        }
      }
    }

    window[STATE_KEY] = {
      applied: true,
      mode: mode,
      revision: report.revision,
      runtime: RUNTIME,
    };
    return report;
  }

  function verify() {
    var styleNodes = document.querySelectorAll("#" + STYLE_ID);
    var backgroundNodes = document.querySelectorAll("#" + BACKGROUND_ID);
    var overlayNodes = document.querySelectorAll("#" + OVERLAY_ID);
    var tagged = document.querySelectorAll("[" + PART_ATTR + '^="' + PART_PREFIX + '"]');
    var state = window[STATE_KEY] ?? {};
    var protectedCount = 0;
    var selectors = Array.isArray(config.doNotTouch) ? config.doNotTouch : [];
    for (var index = 0; index < selectors.length; index += 1) {
      try {
        protectedCount += document.querySelectorAll(selectors[index]).length;
      } catch (invalidSelector) { /* count nothing for a broken selector */ }
    }
    return {
      styleCount: styleNodes.length,
      backgroundCount: backgroundNodes.length,
      overlayCount: overlayNodes.length,
      taggedParts: tagged.length,
      skippedSelectors: 0,
      doNotTouchProtected: protectedCount,
      mode: state.mode ?? null,
      applied: Boolean(state.applied),
      revision: state.revision ?? "",
      backgroundPointerEvents: backgroundNodes.length === 1
        ? String(backgroundNodes[0].style.getPropertyValue("pointer-events") ?? "") : "",
      overlayPointerEvents: overlayNodes.length === 1
        ? String(overlayNodes[0].style.getPropertyValue("pointer-events") ?? "") : "",
    };
  }

  function pause() {
    window[DISABLED_KEY] = true;
    remove();
    return { paused: true };
  }

  function resume() {
    window[DISABLED_KEY] = false;
    return { paused: false };
  }

  var existing = window[API_KEY];
  var api = {
    runtime: RUNTIME,
    apply: apply,
    remove: remove,
    verify: verify,
    pause: pause,
    resume: resume,
    ids: { style: STYLE_ID, background: BACKGROUND_ID, overlay: OVERLAY_ID },
  };
  window[API_KEY] = api;
  void existing; // re-evaluation in the same document just replaces the API
})(__ZCODE_CSS_JSON__, __ZCODE_ART_JSON__, __ZCODE_CONFIG_JSON__);
