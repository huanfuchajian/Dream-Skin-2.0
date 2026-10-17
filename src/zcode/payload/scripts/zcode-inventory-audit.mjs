// Post-collection audit for the ZCode DOM inventory. The audit is a CLI over
// exactly four absolute paths the caller names: it never guesses a repository
// root and never borrows a same-named file from another directory.
//
// The hard gates carry the compatibility identity: the run finished and closed
// its browser, the evidence carries no user state values, the version is
// supported, the renderer URL family is the verified one, and every profile
// required selector is evidenced by the captured census. A digest that drifted
// from the recorded history is a WARNING, not a failure: the semantic
// fingerprint also covers optional surface attributes, so it moves between
// captures of the same build while the contract does not.
//
// Exit 0 = evidence is safe and consistent; exit 2 = one or more checks failed.

import fs from 'node:fs';
import path from 'node:path';
import { zcodeSemanticFingerprint } from './zcode-compatibility.mjs';
import {
  ZCODE_ATTRIBUTE_VALUE_DENY_SOURCE,
  ZCODE_MAX_SAMPLED_VALUES,
  zcodeInventorySummary,
} from './injector.mjs';

const OPTIONS = ['inventory', 'run-report', 'profile', 'dom-map'];

function parseArguments(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index += 1) {
    const name = argv[index].startsWith('--') ? argv[index].slice(2) : '';
    const value = argv[index + 1];
    if (OPTIONS.includes(name) && typeof value === 'string' && !value.startsWith('--')) {
      options[name] = value;
      index += 1;
    }
  }
  return options;
}

function emit(report, exitCode) {
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = exitCode;
}

function record(checks, name, pass, detail) {
  checks.push({ check: name, pass: Boolean(pass), detail: String(detail) });
}

// The census arrives as {name: count} from the collector and as a plain
// presence list from fixtures; both shapes answer the same "is it there?".
function counter(collection, key) {
  if (Array.isArray(collection)) return collection.map(String).includes(key) ? 1 : 0;
  if (collection && typeof collection === 'object') return Number(collection[key] ?? 0) || 0;
  return 0;
}

// A selector is proven only by the inventory fact that carries it: attribute
// selectors by the attribute census, quoted attribute selectors by the sampled
// values, id selectors by the id census, tag selectors by the tag census.
// Class and compound selectors have no measured evidence in this capture.
//
// A full sample list is a truncation (the collector keeps at most
// ZCODE_MAX_SAMPLED_VALUES per name), so a value missing from a saturated list
// proves nothing about the renderer: that case degrades to the name census and
// says so, instead of failing a healthy build.
function provedBy(inventory, selector) {
  const attribute = /^\[([\w-]+)(?:=["']?([^"'\]]+)["']?)?\]$/.exec(selector);
  if (attribute) {
    const [, name, value] = attribute;
    if (!value) return counter(inventory?.attributeNames, name) > 0 ? `${name} present` : null;
    const samples = inventory?.attributeSamples?.[name];
    if (!Array.isArray(samples)) return null;
    if (samples.map(String).includes(value)) return `${name}="${value}" sampled`;
    if (samples.length >= ZCODE_MAX_SAMPLED_VALUES && counter(inventory?.attributeNames, name) > 0) {
      return `${name} present, "${value}" beyond the sample truncation`;
    }
    return null;
  }
  if (selector.startsWith('#')) {
    return counter(inventory?.ids, selector.slice(1)) > 0 ? `${selector} present` : null;
  }
  if (/^[\w-]+$/.test(selector)) {
    return counter(inventory?.tags, selector) > 0 ? `<${selector}> present` : null;
  }
  return null;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const checks = [];
  const absent = OPTIONS.filter((name) => !options[name]);
  if (absent.length > 0) {
    record(checks, 'arguments', false, `missing required argument(s): ${absent.map((name) => `--${name}`).join(', ')}`);
    emit({ verdict: 'fail', checks }, 2);
    return;
  }
  const relative = OPTIONS.filter((name) => !path.isAbsolute(options[name]));
  if (relative.length > 0) {
    // A relative path means the caller never resolved its own contract; refusing
    // loudly beats resolving against an arbitrary working directory.
    throw new Error(`audit paths must be absolute: ${relative.map((name) => `--${name} ${options[name]}`).join(', ')}`);
  }

  const audited = {
    inventory: options.inventory,
    runReport: options['run-report'],
    profile: options.profile,
    domMap: options['dom-map'],
  };
  const files = {
    'inventory-file': options.inventory,
    'run-report-file': options['run-report'],
    'profile-file': options.profile,
    'dom-map-file': options['dom-map'],
  };
  for (const [name, filePath] of Object.entries(files)) {
    if (!fs.existsSync(filePath)) record(checks, name, false, `missing: ${filePath}`);
  }
  if (checks.some((check) => !check.pass)) {
    emit({ verdict: 'fail', audited, checks }, 2);
    return;
  }

  let inventory;
  let runReport;
  let profile;
  let domMap;
  try {
    inventory = JSON.parse(fs.readFileSync(options.inventory, 'utf8'));
    runReport = JSON.parse(fs.readFileSync(options['run-report'], 'utf8'));
    profile = JSON.parse(fs.readFileSync(options.profile, 'utf8'));
    domMap = fs.readFileSync(options['dom-map'], 'utf8');
  } catch (error) {
    record(checks, 'readable-evidence', false, error.message);
    emit({ verdict: 'fail', audited, checks }, 2);
    return;
  }

  const readiness = inventory?.readiness ?? {};
  const inner = inventory?.inventory ?? {};
  const features = inventory?.fingerprint?.features ?? {};
  const digest = String(inventory?.fingerprint?.digest ?? '');
  const summary = zcodeInventorySummary(inventory);

  // --- run facts ----------------------------------------------------------------
  record(checks, 'inventory-exit-zero', runReport?.inventory?.exitCode === 0, `inventory.exitCode=${runReport?.inventory?.exitCode}`);
  record(checks, 'cleanup-complete', runReport?.cleanupComplete === true, `cleanupComplete=${runReport?.cleanupComplete}`);
  record(checks, 'no-run-errors', Array.isArray(runReport?.errors) && runReport.errors.length === 0, `errors=${JSON.stringify(runReport?.errors ?? null)}`);
  record(checks, 'workspace-ready', readiness.ready === true, `ready=${readiness.ready} reasons=${JSON.stringify(readiness.reasons ?? [])}`);
  record(checks, 'browser-closed', inventory?.browserClosed === true, `browserClosed=${inventory?.browserClosed}`);

  // --- safety: the evidence must not carry user state values ---------------------
  const samples = inner.attributeSamples ?? {};
  const denySource = new RegExp(ZCODE_ATTRIBUTE_VALUE_DENY_SOURCE, 'i');
  const leaked = Object.keys(samples).filter((name) => denySource.test(name));
  record(checks, 'no-denied-attribute-values', leaked.length === 0,
    leaked.length === 0 ? 'attributeSamples carry no state-carrying attribute values' : `denied names present: ${leaked.join(',')}`);
  const neverSampled = Array.isArray(profile.neverSampledAttributes) ? profile.neverSampledAttributes : [];
  const banned = neverSampled.filter((name) => Array.isArray(samples[name]) && samples[name].length > 0);
  record(checks, 'profile-never-sampled-honoured', banned.length === 0,
    banned.length === 0 ? 'every profile neverSampledAttributes entry is value-free' : `sampled despite profile ban: ${banned.join(',')}`);
  let oversized = 0;
  for (const values of Object.values(samples)) {
    if (!Array.isArray(values)) continue;
    for (const value of values) {
      if (String(value).length > 48) oversized += 1;
    }
  }
  record(checks, 'value-length-cap', oversized === 0, `values over 48 chars: ${oversized}`);

  // --- identity: version, renderer family, required selectors --------------------
  const supported = (Array.isArray(profile.supportedVersions) ? profile.supportedVersions : []).map(String);
  const version = String(features.version ?? inventory?.zcodeVersion ?? '');
  record(checks, 'supported-version', supported.includes(version), `version=${version} supported=${supported.join(',') || '(none)'}`);

  const urlFamily = String(features.urlFamily ?? '');
  const recordedFamily = profile.verifiedAgainst?.rendererUrlFamily;
  record(checks, 'renderer-identity',
    urlFamily.length > 0 && (recordedFamily === undefined || String(recordedFamily) === urlFamily),
    `urlFamily=${urlFamily || '(missing)'} profile=${recordedFamily ?? '(unrecorded)'}`);

  const required = (Array.isArray(profile.requiredSelectors) ? profile.requiredSelectors : []).map(String);
  const proofs = required.map((selector) => provedBy(inner, selector));
  const unproven = required.filter((selector, index) => !proofs[index]);
  record(checks, 'required-selectors-present', required.length > 0 && unproven.length === 0,
    unproven.length === 0
      ? `all ${required.length} required selector(s) are evidenced: ${proofs.join('; ')}`
      : `not evidenced by the inventory: ${unproven.join(', ')}`);

  const profileVerified = profile.verifiedAgainst ?? {};
  record(checks, 'element-counts-recorded', summary.bodyElementCount > 0 && summary.totalElementCount > 0,
    `body=${summary.bodyElementCount} (profile ${profileVerified.bodyElementCount}, drift is diagnostic) total=${summary.totalElementCount} (profile ${profileVerified.totalElementCount})`);

  // --- fingerprint: self-consistency is hard, drift is a recorded warning -------
  record(checks, 'fingerprint-format', /^[0-9a-f]{32}$/.test(digest), `digest=${digest}`);
  const recomputed = zcodeSemanticFingerprint(features).digest;
  record(checks, 'fingerprint-self-consistent', recomputed === digest,
    recomputed === digest ? 'recomputed from the recorded features matches' : `recomputed=${recomputed}`);

  const history = [
    profile.fingerprint?.digest,
    ...(Array.isArray(profile.fingerprint?.observedDigests) ? profile.fingerprint.observedDigests : []),
  ].filter((value) => typeof value === 'string' && value.length > 0);
  const warnings = [];
  if (digest && !history.includes(digest)) {
    warnings.push({ check: 'fingerprintDrift', digest, detail: `digest is not part of the recorded history: ${history.join(', ') || '(none recorded)'}` });
  }
  if (digest && !domMap.includes(digest)) {
    warnings.push({ check: 'fingerprintDrift', digest, detail: `digest is not documented in ${options['dom-map']}` });
  }

  const passed = checks.every((check) => check.pass);
  emit({
    verdict: passed ? 'pass' : 'fail',
    audited,
    summary: {
      ready: readiness.ready === true,
      bodyElementCount: summary.bodyElementCount,
      totalElementCount: summary.totalElementCount,
      workspaceEvidenceTotal: summary.workspaceEvidenceTotal,
      fingerprint: digest,
    },
    warnings,
    checks,
  }, passed ? 0 : 2);
}

main();
