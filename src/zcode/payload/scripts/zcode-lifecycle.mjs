// ZCode renderer lifecycle state machine. Pure orchestration over injected
// dependencies (discover/inject/remove/check) so the CDP details live in the
// injector and every transition is unit-testable.
//
// States: disconnected -> discovering -> injecting -> active, with removing as
// the explicit teardown state and failed as the terminal recoverable state.
// A lost renderer rediscovers with exponential backoff (base 500ms, cap 10s).
// A paused lifecycle may keep discovering but never reinjects; pause() removes
// the live theme and stops the loop; resume() clears the pause lock (and the
// failed state) so the caller can start()/step() again.

export const ZCODE_LIFECYCLE_STATES = Object.freeze([
  "disconnected",
  "discovering",
  "injecting",
  "active",
  "removing",
  "failed",
]);

export const ZCODE_REDISCOVER_BASE_MS = 500;
export const ZCODE_REDISCOVER_MAX_MS = 10000;

export function nextBackoffDelay(currentDelayMs) {
  const current = Number(currentDelayMs) || 0;
  if (current <= 0) return ZCODE_REDISCOVER_BASE_MS;
  return Math.min(current * 2, ZCODE_REDISCOVER_MAX_MS);
}

const defaultSleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export function createZCodeThemeLifecycle({
  discover,
  inject,
  remove,
  check,
  isPaused = async () => false,
  onState = () => {},
  onError = () => {},
  sleep = defaultSleep,
  rediscoverDelayMs = 0,
  activePollMs = 1000,
}) {
  if (typeof discover !== "function") throw new TypeError("discover dependency is required");
  if (typeof inject !== "function") throw new TypeError("inject dependency is required");
  if (typeof remove !== "function") throw new TypeError("remove dependency is required");
  if (typeof check !== "function") throw new TypeError("check dependency is required");

  const lifecycle = {
    state: "disconnected",
    paused: false,
    running: false,
    rediscoverDelayMs: Number(rediscoverDelayMs) || 0,
    target: null,
    lastError: null,
    runPromise: null,
    stopRequested: false,
    // Dependencies live on the object (not in closures) so callers and tests
    // can swap them between steps.
    discover,
    inject,
    remove,
    check,
    isPaused,
  };

  function transition(state) {
    if (lifecycle.state === state) return;
    lifecycle.state = state;
    try { onState(state, { target: lifecycle.target }); } catch { /* logging must not break the loop */ }
  }

  // One deterministic loop step. `run()` calls this until stopped, so tests
  // drive every transition without timers.
  lifecycle.step = async function step() {
    if (lifecycle.state === "failed" || lifecycle.stopRequested) return;

    if (lifecycle.state === "active") {
      let alive = false;
      try { alive = Boolean(await lifecycle.check(lifecycle.target)); } catch (error) { alive = false; lifecycle.lastError = error; onError(error); }
      if (!alive) {
        lifecycle.target = null;
        transition("disconnected");
        lifecycle.rediscoverDelayMs = nextBackoffDelay(lifecycle.rediscoverDelayMs);
        transition("discovering");
      }
      return;
    }

    if (lifecycle.state === "removing") {
      try {
        await lifecycle.remove(lifecycle.target);
        lifecycle.lastError = null;
      } catch (error) {
        transition("failed");
        lifecycle.lastError = error;
        onError(error);
        lifecycle.running = false;
        return;
      }
      lifecycle.target = null;
      lifecycle.rediscoverDelayMs = 0;
      transition("disconnected");
      return;
    }

    // disconnected / discovering: find a renderer to inject into.
    transition("discovering");
    let target = null;
    try { target = await lifecycle.discover(); } catch (error) { target = null; lifecycle.lastError = error; onError(error); }
    if (lifecycle.stopRequested) return;
    if (!target) {
      lifecycle.target = null;
      lifecycle.rediscoverDelayMs = nextBackoffDelay(lifecycle.rediscoverDelayMs);
      return;
    }
    lifecycle.target = target;

    if (await lifecycle.isPaused()) {
      // A paused lifecycle may keep discovering but must never reinject.
      lifecycle.rediscoverDelayMs = nextBackoffDelay(lifecycle.rediscoverDelayMs);
      return;
    }

    transition("injecting");
    try {
      await lifecycle.inject(lifecycle.target);
      lifecycle.lastError = null;
    } catch (error) {
      transition("failed");
      lifecycle.lastError = error;
      onError(error);
      lifecycle.running = false;
      return;
    }
    lifecycle.rediscoverDelayMs = 0;
    transition("active");
  };

  async function run() {
    while (lifecycle.running && !lifecycle.stopRequested && lifecycle.state !== "failed") {
      await lifecycle.step();
      if (!lifecycle.running || lifecycle.stopRequested || lifecycle.state === "failed") break;
      if (lifecycle.rediscoverDelayMs > 0) await sleep(lifecycle.rediscoverDelayMs);
      else if (lifecycle.state === "active") await sleep(Math.max(0, Number(activePollMs)));
    }
  }

  lifecycle.start = function start() {
    if (lifecycle.running) throw new Error("lifecycle is already running");
    lifecycle.running = true;
    lifecycle.stopRequested = false;
    transition("disconnected");
    lifecycle.runPromise = run();
    return lifecycle.runPromise;
  };

  // Explicit user pause: remove the live theme and make sure no automatic
  // reinjection happens until resume(). Safe to call from any state.
  lifecycle.pause = async function pause() {
    lifecycle.paused = true;
    if (lifecycle.state === "active" || lifecycle.state === "injecting") {
      transition("removing");
      try {
        await lifecycle.remove(lifecycle.target);
        lifecycle.lastError = null;
      } catch (error) {
        transition("failed");
        lifecycle.lastError = error;
        onError(error);
        lifecycle.running = false;
        lifecycle.stopRequested = true;
        return;
      }
      lifecycle.target = null;
      transition("disconnected");
    }
    lifecycle.running = false;
    lifecycle.stopRequested = true;
  };

  // Clears the pause lock (and a failed state). It does not start the loop by
  // itself; the caller owns start()/step() afterwards.
  lifecycle.resume = function resume() {
    lifecycle.paused = false;
    lifecycle.stopRequested = false;
    if (lifecycle.state === "failed") transition("disconnected");
  };

  lifecycle.stop = async function stop() {
    lifecycle.stopRequested = true;
    lifecycle.running = false;
    if (lifecycle.runPromise) {
      try { await lifecycle.runPromise; } catch { /* the loop never throws out here */ }
      lifecycle.runPromise = null;
    }
  };

  return lifecycle;
}
