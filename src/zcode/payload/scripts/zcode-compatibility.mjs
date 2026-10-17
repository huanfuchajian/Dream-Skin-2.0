/**
 * ZCode DOM compatibility probe.
 *
 * Decides whether an observed ZCode renderer still matches the DOM contract this
 * project was built and verified against. Three outcomes, and the unsafe one is
 * never reachable by accident: an unknown version or a missing anchor drops to
 * Safe Mode, and a page with no usable anchor at all is refused.
 *
 * The fingerprint deliberately covers only stable semantic features - selector
 * presence, root tag names, stable data- and ARIA attributes, and the renderer
 * URL family. Random class names, page text, user paths and conversation content
 * are excluded, because the fingerprint is written to logs and state files.
 */

import { createHash } from "node:crypto";

function sortedUnique(values) {
  const list = Array.isArray(values) ? values : [];
  return [...new Set(list.map((value) => String(value)))].filter((value) => value.length > 0).sort();
}

/**
 * Canonical, order-independent feature set plus its digest. Two runs against the
 * same DOM contract produce the same digest; any change to the set changes it.
 */
export function zcodeSemanticFingerprint(observed) {
  const features = {
    version: String(observed?.version ?? ""),
    selectors: sortedUnique(observed?.selectors),
    rootTags: sortedUnique(observed?.rootTags),
    stableAttributes: sortedUnique(observed?.stableAttributes),
    urlFamily: String(observed?.urlFamily ?? ""),
  };
  const digest = createHash("sha256").update(JSON.stringify(features)).digest("hex").slice(0, 32);
  return { digest, features };
}

/**
 * @returns {{mode: 'full'|'safe'|'deny', matched: string[], missing: string[],
 *   fingerprint: string, features: object, supportedVersion: boolean,
 *   safeModeAvailable: boolean, reason: string}}
 */
export function evaluateCompatibility(profile, observed) {
  const required = sortedUnique(profile?.requiredSelectors);
  const safeModeSelectors = sortedUnique(profile?.safeModeSelectors);
  const supportedVersions = sortedUnique(profile?.supportedVersions);
  const present = new Set(sortedUnique(observed?.selectors));
  const version = String(observed?.version ?? "");
  const supportedVersion = supportedVersions.includes(version);
  const matched = required.filter((selector) => present.has(selector));
  const missing = required.filter((selector) => !present.has(selector));
  const safeModeAvailable = safeModeSelectors.length > 0
    && safeModeSelectors.every((selector) => present.has(selector));
  const { digest, features } = zcodeSemanticFingerprint(observed);

  let mode = "deny";
  let reason = `version ${version} is not verified and no safe-mode anchor matched`;
  if (supportedVersion && required.length > 0 && missing.length === 0) {
    mode = "full";
    reason = `version ${version} with all ${required.length} required selector(s) present`;
  } else if (safeModeAvailable) {
    mode = "safe";
    reason = supportedVersion
      ? `version ${version} is verified but ${missing.length} required selector(s) are missing`
      : `version ${version} is not in the verified version list`;
  }
  return {
    mode,
    matched,
    missing,
    fingerprint: digest,
    features,
    supportedVersion,
    safeModeAvailable,
    reason,
  };
}
