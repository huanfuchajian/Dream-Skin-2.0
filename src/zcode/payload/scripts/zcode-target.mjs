/**
 * ZCode renderer target selection.
 *
 * CDP exposes every page in the browser, including login, updater, settings and
 * hidden helper surfaces. Injecting into the wrong one would either do nothing
 * visible or touch a surface the design excludes, so selection is explicit,
 * scored, and fails closed when two candidates are equally plausible.
 */

// Title words that disqualify a surface outright: these are never the workspace.
const TITLE_REJECT = /(?:^|\s)(?:login|log-in|sign[-_ ]?in|auth|updat\w*|settings?|splash|welcome)(?:\s|$)/i;
// URL route segments with the same meaning, so a query value alone cannot match.
const URL_ROUTE_REJECT = /(?:^|[/#?&=])(?:login|signin|sign-in|auth|update|updater|settings|splash)(?:[/#?&=]|$)/i;
const URL_SCHEME_REJECT = /^(?:devtools|chrome|chrome-extension):/i;
/**
 * The schemes a local application surface can be served from. Codex serves its
 * renderer from `app://`; the ZCode renderer was measured as `file://…/index.html`.
 * Every consumer that filters CDP page targets before selection must use this one
 * definition, or a valid ZCode renderer is filtered out before it can be scored.
 */
export const ZCODE_LOCAL_APP_SCHEME = /^(?:zcode|app|file):/i;

function targetText(target) {
  return `${String(target.title ?? '')} ${String(target.url ?? '')}`;
}

/**
 * Explainable score for one CDP target. `hardReject` means the surface may never
 * receive the theme, regardless of how it scores elsewhere.
 */
export function scoreZCodeTarget(target) {
  const reasons = [];
  if (!target || typeof target !== 'object') {
    return { score: 0, reasons: ['not-an-object'], hardReject: true };
  }
  if (target.type !== 'page') {
    reasons.push(`type-rejected:${String(target.type)}`);
    return { score: 0, reasons, hardReject: true };
  }
  const webSocketDebuggerUrl = String(target.webSocketDebuggerUrl ?? '');
  if (!webSocketDebuggerUrl) {
    reasons.push('missing-webSocketDebuggerUrl');
    return { score: 0, reasons, hardReject: true };
  }
  const title = String(target.title ?? '');
  const url = String(target.url ?? '');
  if (TITLE_REJECT.test(title) || URL_ROUTE_REJECT.test(url)) {
    reasons.push('excluded-surface:login-or-update-or-settings');
    return { score: 0, reasons, hardReject: true };
  }
  if (URL_SCHEME_REJECT.test(url)) {
    reasons.push('excluded-scheme');
    return { score: 0, reasons, hardReject: true };
  }
  if (!title.trim() && !url.trim()) {
    reasons.push('blank-surface');
    return { score: 0, reasons, hardReject: true };
  }

  let score = 0;
  if (/workspace/i.test(targetText(target))) { score += 3; reasons.push('+3 workspace-hint'); }
  if (/(?:^|[/#?&=])main(?:[/#?&=]|$)/i.test(url)) { score += 2; reasons.push('+2 main-route'); }
  if (/zcode/i.test(targetText(target))) { score += 2; reasons.push('+2 zcode-hint'); }
  if (/index\.html?/i.test(url)) { score += 1; reasons.push('+1 index-html'); }
  if (ZCODE_LOCAL_APP_SCHEME.test(url)) { score += 1; reasons.push('+1 local-app-scheme'); }
  return { score, reasons, hardReject: false };
}

/**
 * Returns the single highest-scoring renderer, or throws E07/E08. A tie is
 * refused rather than broken: two equally plausible windows mean the DOM map is
 * not trustworthy for this session.
 */
export function selectZCodeMainTarget(targets, log = () => {}) {
  const list = Array.isArray(targets) ? targets : [];
  const scored = list.map((target) => ({ target, ...scoreZCodeTarget(target) }));
  for (const entry of scored) {
    log(`candidate ${String(entry.target?.url ?? '')} score=${entry.score}` +
      `${entry.hardReject ? ' hardReject' : ''} [${entry.reasons.join(', ')}]`);
  }
  const eligible = scored.filter((entry) => !entry.hardReject && entry.score > 0);
  if (eligible.length === 0) {
    const detail = list.length === 0
      ? 'no CDP page targets were reported'
      : 'every reported target was excluded or unscorable';
    throw new Error(`E07_NO_RENDERER_TARGET: ${detail}`);
  }
  const best = Math.max(...eligible.map((entry) => entry.score));
  const winners = eligible.filter((entry) => entry.score === best);
  if (winners.length > 1) {
    throw new Error(
      `E08_TARGET_AMBIGUOUS: ${winners.length} targets scored ${best}` +
      ` (${winners.map((entry) => String(entry.target.url)).join(', ')})`
    );
  }
  log(`selected ${String(winners[0].target.url)} score=${best} [${winners[0].reasons.join(', ')}]`);
  return winners[0].target;
}
