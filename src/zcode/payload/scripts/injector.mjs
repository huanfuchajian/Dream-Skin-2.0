import fs from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readImageMetadata } from "./image-metadata.mjs";
import {
  normalizeThemeColor,
  normalizeThemeText,
} from "../assets/theme-package-validator.mjs";
import { decodeAndValidateSafeCss } from "../assets/safe-css-validator.mjs";
import { selectZCodeMainTarget, scoreZCodeTarget, ZCODE_LOCAL_APP_SCHEME } from "./zcode-target.mjs";
import { zcodeSemanticFingerprint } from "./zcode-compatibility.mjs";
import { evaluateCompatibility } from "./zcode-compatibility.mjs";
import {
  buildZCodeRendererConfig,
  resolveCautionAllowlist,
  zcodeThemeSummary,
  ZCODE_COMPATIBILITY_MODES,
  ZCODE_SKIN_IDS,
} from "./zcode-theme-contract.mjs";
import { resolveZCodeArtForRenderer } from "./zcode-art-source-format.mjs";
import { createZCodeThemeLifecycle } from "./zcode-lifecycle.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const here = path.dirname(scriptPath);
const root = path.resolve(here, "..");
const SELECTOR_CONTRACT = JSON.parse(await fs.readFile(
  path.join(root, "assets", "selectors.json"), "utf8",
));
if (SELECTOR_CONTRACT.schema !== "codex-dream-skin-selectors/1" ||
  !Array.isArray(SELECTOR_CONTRACT.selectors)) {
  throw new Error("assets/selectors.json has an unsupported schema");
}
const SELECTOR_MAP = new Map();
for (const entry of SELECTOR_CONTRACT.selectors) {
  if (!entry?.key || !entry.selector || SELECTOR_MAP.has(entry.key)) {
    throw new Error(`assets/selectors.json has an invalid selector key: ${entry?.key || "<missing>"}`);
  }
  SELECTOR_MAP.set(entry.key, entry.selector);
}
const selectorFor = (key) => {
  const selector = SELECTOR_MAP.get(key);
  if (!selector) throw new Error(`Selector contract is missing ${key}`);
  return selector;
};
const selectorLiteral = (key) => JSON.stringify(selectorFor(key));
const stableTestidLiteral = (testid) => {
  if (!SELECTOR_CONTRACT.stableTestids?.includes(testid)) {
    throw new Error(`Selector contract is missing stable testid ${testid}`);
  }
  return JSON.stringify(`[data-testid="${testid}"]`);
};
const SKIN_VERSION = "1.5.18";
// .github/workflows/ci.yml's version-consistency check greps this file for a
// literal `const SKIN_VERSION = "...";` line, so the export stays a separate
// statement rather than an inline `export const`.
export { SKIN_VERSION };
const MAX_ART_BYTES = 10 * 1024 * 1024;
const MAX_SAFE_CSS_BYTES = 256 * 1024;
const STRONG_THEME_AUDIT_MS = 30000;
const MIN_RENDERER_VIEWPORT_WIDTH = 320;
const MIN_RENDERER_VIEWPORT_HEIGHT = 240;
const VISIBLE_WINDOW_STATES = new Set(["normal", "maximized", "fullscreen"]);
const LOOPBACK_HOSTS = new Set(["127.0.0.1", "localhost", "[::1]", "::1"]);
const BROWSER_ID_PATTERN = /^[A-Za-z0-9._-]{1,200}$/;
const OPERATION_UI_HOST_ID = "chatgpt-dream-skin-operation";
const OPERATION_UI_REGISTRY_KEY = "__CHATGPT_DREAM_SKIN_OPERATION_UI__";
const OPERATION_KINDS = new Set(["apply", "pause", "switch"]);
const OPERATION_UI_STATES = new Set(["success", "error", "cancelled"]);
// Shared with macOS: in-renderer progress for pause/apply so both platforms feel the same.
const OPERATION_UI_CSS = `
  :host {
    all: initial;
    position: fixed;
    top: var(--dream-skin-operation-top, 0px);
    left: var(--dream-skin-operation-left, 0px);
    width: var(--dream-skin-operation-width, 100vw);
    height: var(--dream-skin-operation-height, 100vh);
    z-index: 2147483647;
    pointer-events: none;
    opacity: 0;
    display: grid;
    place-items: center;
    transition: opacity 180ms cubic-bezier(0.16, 1, 0.3, 1);
    font-family: "Segoe UI Variable Text", "Segoe UI", "Microsoft YaHei UI", system-ui, sans-serif;
  }
  :host([data-visible="true"]) { opacity: 1; }
  .status {
    box-sizing: border-box;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 12px;
    width: min(220px, calc(100% - 32px));
    min-height: 112px;
    padding: 18px 20px;
    border: 1px solid rgba(238, 239, 244, 0.16);
    border-radius: 8px;
    background: rgba(32, 33, 38, 0.94);
    color: #f3f3f6;
    box-shadow: 0 8px 24px rgba(12, 14, 19, 0.22);
    font-size: 13px;
    font-weight: 550;
    line-height: 1.35;
    text-align: center;
    transform: translateY(-4px) scale(0.98);
    transition: transform 180ms cubic-bezier(0.16, 1, 0.3, 1);
  }
  :host([data-visible="true"]) .status { transform: translateY(0) scale(1); }
  :host([data-tone="light"]) .status {
    border-color: #d9dbe3;
    background: rgba(248, 248, 251, 0.96);
    color: #25262c;
    box-shadow: 0 8px 24px rgba(31, 35, 48, 0.14);
  }
  .indicator {
    box-sizing: border-box;
    flex: 0 0 22px;
    width: 22px;
    height: 22px;
    color: #78a8f5;
  }
  :host([data-state="loading"]) .indicator {
    border: 2px solid currentColor;
    border-top-color: transparent;
    border-radius: 50%;
    animation: dream-skin-operation-spin 720ms linear infinite;
  }
  :host([data-state="success"]) .indicator,
  :host([data-state="error"]) .indicator,
  :host([data-state="cancelled"]) .indicator {
    display: grid;
    place-items: center;
    border-radius: 50%;
    font-size: 16px;
    font-weight: 750;
  }
  :host([data-state="success"]) .indicator { color: #53b77b; }
  :host([data-state="success"]) .indicator::before { content: "✓"; }
  :host([data-state="error"]) .indicator { color: #e26d7e; }
  :host([data-state="error"]) .indicator::before { content: "!"; }
  :host([data-state="cancelled"]) .indicator { color: #a5a7b0; }
  :host([data-state="cancelled"]) .indicator::before { content: "×"; }
  .message { min-width: 0; overflow-wrap: anywhere; }
  @keyframes dream-skin-operation-spin { to { transform: rotate(360deg); } }
  @media (prefers-reduced-motion: reduce) {
    :host, .status { transition: none; }
    :host([data-state="loading"]) .indicator {
      animation: none;
      border-top-color: currentColor;
      opacity: 0.65;
    }
  }
`;
let operationSequence = 0;

class CdpIdentityMismatchError extends Error {}

function parseArgs(argv) {
  const options = {
    port: 9335,
    mode: "watch",
    timeoutMs: 30000,
    startupTimeoutMs: 120000,
    screenshot: null,
    reload: false,
    browserId: null,
    themeDir: path.join(root, "assets"),
    pauseFile: null,
    operationKind: null,
    operationUiState: null,
    operationMessage: null,
    operationToken: null,
    report: null,
    screenshotInjected: null,
    screenshotRemoved: null,
    closeBrowser: false,
    minElements: 100,
    zcodeVersion: "",
    zcodeProfile: null,
    zcodeCss: null,
    zcodeArt: null,
    zcodeTheme: null,
    zcodeStateFile: null,
    zcodeCautionFile: null,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--port") options.port = Number(argv[++i]);
    else if (arg === "--mode") options.mode = argv[++i];
    else if (arg === "--once") options.mode = "once";
    else if (arg === "--watch") options.mode = "watch";
    else if (arg === "--verify") options.mode = "verify";
    else if (arg === "--remove") options.mode = "remove";
    else if (arg === "--begin-operation") options.mode = "begin-operation";
    else if (arg === "--finish-operation") options.mode = "finish-operation";
    else if (arg === "--timeout-ms") options.timeoutMs = Number(argv[++i]);
    else if (arg === "--startup-timeout-ms") options.startupTimeoutMs = Number(argv[++i]);
    else if (arg === "--browser-id") options.browserId = argv[++i];
    else if (arg === "--theme-dir") options.themeDir = path.resolve(argv[++i]);
    else if (arg === "--pause-file") options.pauseFile = path.resolve(argv[++i]);
    else if (arg === "--screenshot") options.screenshot = path.resolve(argv[++i]);
    else if (arg === "--operation-kind") options.operationKind = argv[++i];
    else if (arg === "--operation-ui-state") options.operationUiState = argv[++i];
    else if (arg === "--operation-message") options.operationMessage = argv[++i];
    else if (arg === "--operation-token") options.operationToken = argv[++i];
    else if (arg === "--reload") options.reload = true;
    else if (arg === "--report") options.report = path.resolve(argv[++i]);
    else if (arg === "--screenshot-injected") options.screenshotInjected = path.resolve(argv[++i]);
    else if (arg === "--screenshot-removed") options.screenshotRemoved = path.resolve(argv[++i]);
    else if (arg === "--close-browser") options.closeBrowser = true;
    else if (arg === "--min-elements") options.minElements = Number(argv[++i]);
    else if (arg === "--zcode-version") options.zcodeVersion = argv[++i];
    else if (arg === "--zcode-apply") options.mode = "zcode-apply";
    else if (arg === "--zcode-remove") options.mode = "zcode-remove";
    else if (arg === "--zcode-verify") options.mode = "zcode-verify";
    else if (arg === "--zcode-watch") options.mode = "zcode-watch";
    else if (arg === "--zcode-profile") options.zcodeProfile = path.resolve(argv[++i]);
    else if (arg === "--zcode-css") options.zcodeCss = path.resolve(argv[++i]);
    else if (arg === "--zcode-user-css") options.zcodeUserCss = path.resolve(argv[++i]);
    else if (arg === "--zcode-art") options.zcodeArt = path.resolve(argv[++i]);
    else if (arg === "--zcode-theme") options.zcodeTheme = path.resolve(argv[++i]);
    else if (arg === "--zcode-state-file") options.zcodeStateFile = path.resolve(argv[++i]);
    else if (arg === "--zcode-caution-file") options.zcodeCautionFile = path.resolve(argv[++i]);
    else if (arg === "--zcode-pause") options.mode = "zcode-pause";
    else if (arg === "--zcode-resume") options.mode = "zcode-resume";
    else if (arg === "--zcode-close") options.mode = "zcode-close";
    else if (arg === "--zcode-reload") options.mode = "zcode-reload";
    else if (arg === "--expect-appearance") options.expectAppearance = argv[++i];
    else if (arg === "--zcode-art-source") options.zcodeArtSource = argv[++i];
    else if (arg === "--self-test") options.mode = "self-test";
    else if (arg === "--check-payload") options.mode = "check-payload";
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (options.mode === "zcode-poc") {
    // Only the Phase 1 probe is reachable through --mode; every other mode keeps
    // its own dedicated switch so a typo cannot silently change behaviour.
    if (!options.report) throw new Error("--report is required in zcode-poc mode");
    if (!options.browserId) throw new Error("--browser-id is required in zcode-poc mode");
  }
  if (options.mode === "zcode-dom-inventory") {
    if (!options.report) throw new Error("--report is required in zcode-dom-inventory mode");
    if (!options.browserId) throw new Error("--browser-id is required in zcode-dom-inventory mode");
    if (!Number.isInteger(options.minElements) || options.minElements < 1) {
      throw new Error(`Invalid --min-elements: ${options.minElements}`);
    }
  }
  if (options.mode === "zcode-apply") {
    if (!options.report) throw new Error("--report is required in zcode-apply mode");
    if (!options.browserId) throw new Error("--browser-id is required in zcode-apply mode");
  }
  if (options.mode === "zcode-remove" || options.mode === "zcode-verify"
    || options.mode === "zcode-pause" || options.mode === "zcode-resume"
    || options.mode === "zcode-close" || options.mode === "zcode-reload") {
    if (!options.browserId) throw new Error(`--browser-id is required in ${options.mode} mode`);
  }
  if (options.mode === "zcode-watch") {
    if (!options.zcodeStateFile) throw new Error("--zcode-state-file is required in zcode-watch mode");
    if (!options.report) throw new Error("--report is required in zcode-watch mode");
  }
  // An unknown expectation is refused rather than quietly treated as the default:
  // a typo here would make a paused session look verified.
  if (options.expectAppearance !== undefined && options.expectAppearance !== null && options.expectAppearance !== "") {
    if (options.mode !== "zcode-verify") throw new Error("--expect-appearance is only accepted in zcode-verify mode");
    if (options.expectAppearance !== "native" && options.expectAppearance !== "theme") {
      throw new Error(`--expect-appearance must be native or theme, got ${options.expectAppearance}`);
    }
  }
  const declaredModes = new Set([
    "self-test", "check-payload", "begin-operation", "finish-operation",
    "watch", "once", "verify", "remove", "zcode-poc", "zcode-dom-inventory",
    "zcode-apply", "zcode-remove", "zcode-verify", "zcode-watch",
    "zcode-pause", "zcode-resume", "zcode-close", "zcode-reload",
  ]);
  if (!declaredModes.has(options.mode)) {
    throw new Error(`Unknown mode: ${options.mode}`);
  }
  if (!Number.isInteger(options.port) || options.port < 1024 || options.port > 65535) {
    throw new Error(`Invalid port: ${options.port}`);
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 250 || options.timeoutMs > 120000) {
    throw new Error(`Invalid timeout: ${options.timeoutMs}`);
  }
  if (!Number.isInteger(options.startupTimeoutMs)
    || options.startupTimeoutMs < 250 || options.startupTimeoutMs > 600000) {
    throw new Error(`Invalid startup timeout: ${options.startupTimeoutMs}`);
  }
  if (options.browserId !== null && !BROWSER_ID_PATTERN.test(options.browserId)) {
    throw new Error(`Invalid browser ID: ${options.browserId}`);
  }
  if (options.operationToken !== null && !/^\d{1,12}:\d{13}:\d{1,8}$/.test(options.operationToken)) {
    throw new Error("Invalid operation token");
  }
  if (options.mode === "begin-operation") {
    if (!OPERATION_KINDS.has(options.operationKind)) {
      throw new Error("Begin operation requires --operation-kind apply, pause, or switch");
    }
    if (!options.browserId) throw new Error("--browser-id is required in begin-operation mode");
  }
  if (options.mode === "finish-operation") {
    if (!OPERATION_UI_STATES.has(options.operationUiState)) {
      throw new Error("Finish operation requires --operation-ui-state success, error, or cancelled");
    }
    if (!options.operationToken) throw new Error("Finish operation requires --operation-token");
    if (typeof options.operationMessage !== "string" || options.operationMessage.length > 240
      || /[\r\n]/.test(options.operationMessage)) {
      throw new Error("Finish operation requires a single-line --operation-message up to 240 characters");
    }
    if (!options.browserId) throw new Error("--browser-id is required in finish-operation mode");
  }
  if (["watch", "once", "verify", "remove"].includes(options.mode) && !options.browserId) {
    throw new Error(`--browser-id is required in ${options.mode} mode`);
  }
  return options;
}

function validatedDebuggerUrl(target, port) {
  const url = new URL(target.webSocketDebuggerUrl);
  const pathIsValid = /^\/devtools\/(?:page|browser)\/[A-Za-z0-9._-]{1,200}$/.test(url.pathname);
  if (url.protocol !== "ws:" || !LOOPBACK_HOSTS.has(url.hostname) || Number(url.port) !== port ||
      url.username || url.password || url.search || url.hash || !pathIsValid) {
    throw new Error("Rejected a CDP WebSocket URL outside the allowed loopback endpoint shape");
  }
  return url.href;
}

function parseCdpMessage(data) {
  try {
    const message = JSON.parse(String(data));
    return message && typeof message === "object" ? message : null;
  } catch {
    return null;
  }
}

function browserIdFromVersion(version, port) {
  const url = validatedDebuggerUrl(version, port);
  const parsed = new URL(url);
  const match = parsed.pathname.match(/^\/devtools\/browser\/([A-Za-z0-9._-]{1,200})$/);
  if (!match || parsed.search || parsed.hash || !BROWSER_ID_PATTERN.test(match[1])) {
    throw new Error("Rejected an invalid CDP browser identity URL");
  }
  return match[1];
}

function isValidCdpPageTarget(item, port) {
  if (item?.type !== "page" || !ZCODE_LOCAL_APP_SCHEME.test(String(item.url ?? "")) || typeof item.id !== "string" ||
      !BROWSER_ID_PATTERN.test(item.id) || !item.webSocketDebuggerUrl) return false;
  try {
    const debuggerUrl = new URL(validatedDebuggerUrl(item, port));
    return debuggerUrl.pathname === `/devtools/page/${item.id}`;
  } catch {
    return false;
  }
}

class CdpSession {
  constructor(target, port) {
    this.target = target;
    this.ws = new WebSocket(validatedDebuggerUrl(target, port));
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    this.closed = false;
  }

  async open() {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        try { this.ws.close(); } catch {}
        reject(new Error("CDP WebSocket open timed out"));
      }, 5000);
      this.ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      this.ws.addEventListener("error", () => { clearTimeout(timeout); reject(new Error("CDP WebSocket open failed")); }, { once: true });
    });
    this.ws.addEventListener("message", (event) => this.onMessage(event));
    this.ws.addEventListener("error", () => this.close());
    this.ws.addEventListener("close", () => {
      this.closed = true;
      for (const waiter of this.pending.values()) {
        clearTimeout(waiter.timeout);
        waiter.reject(new Error("CDP socket closed"));
      }
      this.pending.clear();
    });
    await this.send("Runtime.enable");
    await this.send("Page.enable");
    return this;
  }

  onMessage(event) {
    const message = parseCdpMessage(event.data);
    if (!message) {
      this.close();
      return;
    }
    if (message.id) {
      const waiter = this.pending.get(message.id);
      if (!waiter) return;
      clearTimeout(waiter.timeout);
      this.pending.delete(message.id);
      if (message.error) {
        // Keep the numeric CDP code on the rejection: classifyNativeWindowError
        // reads it directly instead of re-parsing the human-readable message,
        // which Codex builds are free to reword at any time.
        const error = new Error(`${message.error.message} (${message.error.code})`);
        error.cdpCode = message.error.code;
        waiter.reject(error);
      } else waiter.resolve(message.result);
      return;
    }
    for (const listener of this.listeners.get(message.method) ?? []) listener(message.params ?? {});
  }

  on(method, listener) {
    const listeners = this.listeners.get(method) ?? [];
    listeners.push(listener);
    this.listeners.set(method, listeners);
  }

  send(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("CDP session is closed"));
    return new Promise((resolve, reject) => {
      const id = this.nextId++;
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`CDP command timed out: ${method}`));
      }, 10000);
      this.pending.set(id, { resolve, reject, timeout });
      try {
        this.ws.send(JSON.stringify({ id, method, params }));
      } catch (error) {
        clearTimeout(timeout);
        this.pending.delete(id);
        reject(error);
      }
    });
  }

  async evaluate(expression) {
    const result = await this.send("Runtime.evaluate", {
      expression,
      awaitPromise: true,
      returnByValue: true,
      userGesture: false,
    });
    if (result.exceptionDetails) {
      const detail = result.exceptionDetails.exception?.description ?? result.exceptionDetails.text;
      throw new Error(`Renderer evaluation failed: ${detail}`);
    }
    return result.result?.value;
  }

  close() {
    for (const waiter of this.pending.values()) {
      clearTimeout(waiter.timeout);
      waiter.reject(new Error("CDP session closed"));
    }
    this.pending.clear();
    if (!this.closed) {
      try { this.ws.close(); } catch {}
    }
    this.closed = true;
  }
}

class BrowserIdentityAnchor {
  constructor(url) {
    this.ws = new WebSocket(url);
    this.closed = false;
    this.ws.addEventListener("close", () => { this.closed = true; });
    this.ws.addEventListener("error", () => {
      this.closed = true;
      try { this.ws.close(); } catch {}
    });
  }

  async open() {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.close();
        reject(new Error("CDP browser identity WebSocket open timed out"));
      }, 5000);
      this.ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
      this.ws.addEventListener("error", () => {
        clearTimeout(timeout);
        reject(new Error("CDP browser identity WebSocket open failed"));
      }, { once: true });
      this.ws.addEventListener("close", () => {
        clearTimeout(timeout);
        reject(new Error("CDP browser identity WebSocket closed during startup"));
      }, { once: true });
    });
    if (this.closed) throw new Error("CDP browser identity WebSocket is already closed");
    return this;
  }

  close() {
    if (!this.closed) {
      try { this.ws.close(); } catch {}
    }
    this.closed = true;
  }
}

async function fetchCdpJson(port, resource) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2000);
  try {
    const response = await fetch(`http://127.0.0.1:${port}${resource}`, {
      redirect: "error",
      signal: controller.signal,
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function listAppTargets(port, expectedBrowserId = null) {
  const targets = await fetchCdpJson(port, "/json/list");
  if (!Array.isArray(targets)) throw new Error("CDP target list is not an array");
  if (expectedBrowserId) {
    const version = await fetchCdpJson(port, "/json/version");
    const actualBrowserId = browserIdFromVersion(version, port);
    if (actualBrowserId !== expectedBrowserId) {
      throw new CdpIdentityMismatchError(
        `CDP browser identity changed from ${expectedBrowserId} to ${actualBrowserId}`,
      );
    }
  }
  return targets.filter((item) => isValidCdpPageTarget(item, port));
}

async function connectBrowserIdentityAnchor(port, expectedBrowserId) {
  const version = await fetchCdpJson(port, "/json/version");
  const actualBrowserId = browserIdFromVersion(version, port);
  if (actualBrowserId !== expectedBrowserId) {
    throw new CdpIdentityMismatchError(
      `CDP browser identity changed from ${expectedBrowserId} to ${actualBrowserId}`,
    );
  }
  return new BrowserIdentityAnchor(validatedDebuggerUrl(version, port)).open();
}

const THEME_CHOICES = {
  appearance: new Set(["auto", "light", "dark"]),
  safeArea: new Set(["auto", "left", "right", "center", "none"]),
  taskMode: new Set(["auto", "ambient", "banner", "full", "off"]),
};

function normalizedUnit(value, name, upper = 1) {
  if (value === null || value === undefined || value === "") return null;
  const number = Number(value);
  if (!Number.isFinite(number) || number < 0 || number > upper) {
    throw new Error(`${name} must be null or a number between 0 and ${upper}`);
  }
  return number;
}

function normalizedChoice(value, name, choices, fallback) {
  if (value === null || value === undefined || value === "") return fallback;
  if (!choices.has(value)) throw new Error(`${name} has an unsupported value: ${value}`);
  return value;
}

function normalizedText(value, name, fallback, maxLength = 120) {
  if (value === null || value === undefined || value === "") return fallback;
  if (typeof value !== "string" || value.length > maxLength || /[\u0000-\u001f]/.test(value)) {
    throw new Error(`${name} must be a short single-line string`);
  }
  return value;
}

function sameFileStat(left, right) {
  return left.isFile() && right.isFile()
    && left.dev === right.dev
    && left.ino === right.ino
    && left.size === right.size
    && left.mtimeMs === right.mtimeMs
    && left.ctimeMs === right.ctimeMs;
}

function isContainedRelativePath(relativePath) {
  return relativePath !== ""
    && !path.isAbsolute(relativePath)
    && relativePath !== ".."
    && !relativePath.startsWith(`..${path.sep}`);
}

async function loadSafeCss(themeRoot) {
  const cssPath = path.join(themeRoot, "theme.css");
  let handle;
  try {
    handle = await fs.open(cssPath, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
  } catch (error) {
    if (error.code === "ENOENT") return null;
    if (error.code === "ELOOP") throw new Error("Theme Safe CSS must not be a symbolic link");
    throw error;
  }
  try {
    const before = await handle.stat();
    if (!before.isFile() || before.size < 1 || before.size > MAX_SAFE_CSS_BYTES) {
      throw new Error(`Theme Safe CSS must be a non-empty file no larger than ${MAX_SAFE_CSS_BYTES} bytes`);
    }
    const bytes = await handle.readFile();
    const after = await handle.stat();
    if (!sameFileStat(before, after) || bytes.length !== after.size) {
      throw new Error("Theme Safe CSS changed while being loaded");
    }
    const { source, runtimeSource, validation } = decodeAndValidateSafeCss(bytes);
    return { path: cssPath, runtimeSource, source, stat: after, validation };
  } finally {
    await handle.close();
  }
}

export async function loadTheme(themeDir, artUpper = 1) {
  const realThemeDir = await fs.realpath(themeDir);
  const themePath = path.join(realThemeDir, "theme.json");
  const themeText = await fs.readFile(themePath, "utf8");
  const raw = JSON.parse(themeText);
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("Theme root must be an object");
  }
  if (raw.schemaVersion !== 1) {
    throw new Error("Theme must use schemaVersion 1");
  }
  const image = normalizedText(raw.image, "image", null, 240);
  if (!image || path.isAbsolute(image)) throw new Error("Theme image must be a relative path");
  const imagePath = path.resolve(realThemeDir, image);
  const relativeImage = path.relative(realThemeDir, imagePath);
  if (!isContainedRelativePath(relativeImage)) {
    throw new Error("Theme image must remain inside the selected theme directory");
  }
  const extension = path.extname(imagePath).toLowerCase();
  if (![".png", ".jpg", ".jpeg", ".webp"].includes(extension)) {
    throw new Error(`Unsupported theme image format: ${extension || "missing"}`);
  }
  const realImagePath = await fs.realpath(imagePath);
  const realRelativeImage = path.relative(realThemeDir, realImagePath);
  if (!isContainedRelativePath(realRelativeImage)) {
    throw new Error("Theme image cannot escape through a link or junction");
  }
  const art = raw.art && typeof raw.art === "object" && !Array.isArray(raw.art) ? raw.art : {};
  const rawColors = raw.colors && typeof raw.colors === "object" && !Array.isArray(raw.colors)
    ? raw.colors : null;
  const colorKeys = [
    "background", "panel", "panelAlt", "accent", "accentAlt", "secondary",
    "highlight", "text", "muted", "line",
  ];
  const colors = {
    background: normalizeThemeColor(rawColors?.background, "#071116"),
    panel: normalizeThemeColor(rawColors?.panel, "#0b1a20"),
    panelAlt: normalizeThemeColor(rawColors?.panelAlt, "#10272c"),
    accent: normalizeThemeColor(rawColors?.accent, "#7cff46"),
    accentAlt: normalizeThemeColor(rawColors?.accentAlt, "#b8ff3d"),
    secondary: normalizeThemeColor(rawColors?.secondary, "#36d7e8"),
    highlight: normalizeThemeColor(rawColors?.highlight, "#642a8c"),
    text: normalizeThemeColor(rawColors?.text, "#e9fff1"),
    muted: normalizeThemeColor(rawColors?.muted, "#9ebdb3"),
    line: normalizeThemeColor(rawColors?.line, "rgba(124, 255, 70, .28)"),
  };
  const theme = {
    schemaVersion: 1,
    id: normalizeThemeText(raw.id, "custom", 80, "id", themePath),
    name: normalizeThemeText(raw.name, "Codex Dream Skin", 80, "name", themePath),
    brandSubtitle: normalizeThemeText(raw.brandSubtitle, "CODEX DREAM SKIN", 120, "brandSubtitle", themePath),
    tagline: normalizeThemeText(raw.tagline, "Make something wonderful.", 120, "tagline", themePath),
    projectPrefix: normalizeThemeText(raw.projectPrefix, "选择项目 · ", 120, "projectPrefix", themePath),
    projectLabel: normalizeThemeText(raw.projectLabel, "◉  选择项目", 120, "projectLabel", themePath),
    statusText: normalizeThemeText(raw.statusText, "DREAM SKIN ONLINE", 120, "statusText", themePath),
    quote: normalizeThemeText(raw.quote, "MAKE SOMETHING WONDERFUL", 120, "quote", themePath),
    image,
    appearance: normalizedChoice(raw.appearance, "appearance", THEME_CHOICES.appearance, "auto"),
    art: {
      focusX: normalizedUnit(art.focusX, "art.focusX", artUpper),
      focusY: normalizedUnit(art.focusY, "art.focusY", artUpper),
      safeArea: normalizedChoice(art.safeArea, "art.safeArea", THEME_CHOICES.safeArea, "auto"),
      taskMode: normalizedChoice(art.taskMode, "art.taskMode", THEME_CHOICES.taskMode, "auto"),
      // The personal skin lets the person set how dark the veil over their artwork is.
      // It is authored, so it has to survive normalization or the setting would silently
      // fall back to the renderer's default; themes that never set it keep the four-key
      // shape the shipped presets are checked against.
      ...(Number.isFinite(art.dim) ? { dim: Math.min(0.85, Math.max(0, art.dim)) } : {}),
    },
    colorMode: rawColors ? "explicit" : "auto",
    explicitColorKeys: rawColors ? colorKeys.filter((key) => Object.hasOwn(rawColors, key)) : [],
    colors,
  };
  const [themeStat, imageStat, safeCss] = await Promise.all([
    fs.stat(themePath),
    fs.stat(realImagePath),
    loadSafeCss(realThemeDir),
  ]);
  if (!imageStat.isFile()) throw new Error("Theme image is not a file");
  if (imageStat.size < 1) throw new Error("Theme image cannot be empty");
  if (imageStat.size > MAX_ART_BYTES) {
    throw new Error(`Theme image exceeds the ${MAX_ART_BYTES / 1024 / 1024} MB limit`);
  }
  const imageBytes = await fs.readFile(realImagePath);
  if (imageBytes.length < 1 || imageBytes.length > MAX_ART_BYTES) {
    throw new Error(`Theme image must be between 1 byte and ${MAX_ART_BYTES / 1024 / 1024} MB`);
  }
  const artMetadata = readImageMetadata(imageBytes, extension);
  if (!artMetadata) {
    throw new Error("Theme image metadata is invalid or exceeds the 16384px / 50MP safety limit");
  }
  theme.artMetadata = artMetadata;
  const fingerprint = createHash("sha256")
    .update(themeText, "utf8")
    .update("\0")
    .update(imageBytes)
    .update("\0")
    .update(safeCss?.source ?? "")
    .digest("hex");
  return {
    theme,
    themePath,
    imagePath: realImagePath,
    imageBytes,
    safeCss: safeCss?.source ?? "",
    safeCssRuntime: safeCss?.runtimeSource ?? "",
    safeCssPath: safeCss?.path ?? null,
    safeCssStatus: safeCss ? "validated" : "none",
    fingerprint,
    sourceStamp: `${themeStat.size}:${themeStat.mtimeMs}:${imageStat.size}:${imageStat.mtimeMs}:` +
      (safeCss ? `${safeCss.stat.size}:${safeCss.stat.mtimeMs}` : "none"),
  };
}

export function zcodeArtUpperBound(artSourceFormat) {
  // Only an explicit declaration widens the accepted range, and only to the units
  // the ZCode renderer contract already understands. An absent declaration keeps the
  // shared Codex bound of 0..1 untouched.
  if (artSourceFormat === "zcode-percent-v1") return 100;
  if (artSourceFormat === "" || artSourceFormat === null || artSourceFormat === undefined) return 1;
  if (artSourceFormat === "dream-skin-v1-normalized") return 1;
  throw new Error(`Unknown --zcode-art-source: ${artSourceFormat}`);
}

export async function loadPayload(themeDir = path.join(root, "assets"), candidateTheme = null, artSourceFormat = "") {
  const loadedTheme = candidateTheme ?? await loadTheme(themeDir, zcodeArtUpperBound(artSourceFormat));
  const [css, template] = await Promise.all([
    fs.readFile(path.join(root, "assets", "dream-skin.css"), "utf8"),
    fs.readFile(path.join(root, "assets", "renderer-inject.js"), "utf8"),
  ]);
  const combinedCss = loadedTheme.safeCssRuntime
    ? `${css}\n${loadedTheme.safeCssRuntime}\n` : css;
  const extension = path.extname(loadedTheme.imagePath).toLowerCase();
  const mime = extension === ".jpg" || extension === ".jpeg" ? "image/jpeg"
    : extension === ".webp" ? "image/webp" : "image/png";
  const artDataUrl = `data:${mime};base64,${loadedTheme.imageBytes.toString("base64")}`;
  const styleRevision = createHash("sha256").update(combinedCss).digest("hex").slice(0, 20);
  loadedTheme.theme.artKey = createHash("sha256")
    .update(loadedTheme.imageBytes).digest("hex").slice(0, 20);
  const revision = createHash("sha256")
    .update(SKIN_VERSION)
    .update(combinedCss)
    .update(template)
    .update(JSON.stringify(loadedTheme.theme))
    .digest("hex")
    .slice(0, 20);
  // Every replacement uses a function so String.prototype.replace never
  // interprets $$, $&, $` or $' inside the substituted JSON. Theme text is
  // user-controlled (theme.json legitimately allows "$"), and a literal-string
  // replacement would splice the template source back into the payload -- a
  // stray "$`" produced a SyntaxError, while "$&"/"$$" silently corrupted the
  // theme name.
  const payload = template
    .replace("__DREAM_SKIN_CSS_JSON__", () => JSON.stringify(combinedCss))
    .replace("__DREAM_SKIN_ART_JSON__", () => JSON.stringify(artDataUrl))
    .replace("__DREAM_SKIN_THEME_JSON__", () => JSON.stringify(loadedTheme.theme))
    .replace("__DREAM_SKIN_VERSION_JSON__", () => JSON.stringify(SKIN_VERSION))
    .replace("__DREAM_SKIN_STYLE_REVISION_JSON__", () => JSON.stringify(styleRevision))
    .replace("__DREAM_SKIN_PAYLOAD_REVISION_JSON__", () => JSON.stringify(revision));
  // Defence in depth for every caller, not just --check-payload: a template
  // splice leaves an unreplaced placeholder token behind and usually breaks the
  // syntax outright, so refuse to hand a corrupted script to the renderer.
  if (/__DREAM_SKIN_[A-Z0-9_]+_JSON__/.test(payload)) {
    throw new Error("Payload placeholders were not fully replaced");
  }
  try {
    // Compile-only: this parses the payload and discards the result. It never
    // runs the renderer script here.
    new Function(payload);
  } catch (error) {
    throw new Error(`Payload failed to parse as JavaScript: ${error.message}`);
  }
  const { imageBytes: _imageBytes, ...themeState } = loadedTheme;
  return { ...themeState, payload, revision };
}

async function fileExists(filePath) {
  if (!filePath) return false;
  try {
    return (await fs.stat(filePath)).isFile();
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

async function readThemeSourceStamp(loadedTheme) {
  const [themeStat, imageStat, cssStat] = await Promise.all([
    fs.stat(loadedTheme.themePath),
    fs.stat(loadedTheme.imagePath),
    fs.stat(path.join(path.dirname(loadedTheme.themePath), "theme.css")).catch((error) => {
      if (error.code === "ENOENT") return null;
      throw error;
    }),
  ]);
  return `${themeStat.size}:${themeStat.mtimeMs}:${imageStat.size}:${imageStat.mtimeMs}:` +
    (cssStat ? `${cssStat.size}:${cssStat.mtimeMs}` : "none");
}

async function probeSession(session) {
  return session.evaluate(`(() => {
    const initialRoute = new URLSearchParams(String(location.search || ''))
      .get('initialRoute') || '';
    const pathname = String(location.pathname || '');
    const excludedPetSurface = location.protocol === 'app:' && (
      pathname.endsWith('/avatar-overlay-composition-surface.html') ||
      initialRoute === '/avatar-overlay' || initialRoute.startsWith('/avatar-overlay/')
    );
    const genericCodexSurface = () => {
      if (location.protocol !== 'app:') return false;
      const main = document.querySelector('main, [role="main"]');
      const input = document.querySelector('textarea, [contenteditable="true"], [role="textbox"]');
      const branded = Boolean(document.querySelector(
        ${stableTestidLiteral("app-shell-header-context-menu-surface")},
      ));
      return Boolean(main && input && branded);
    };
    const markers = {
      shell: Boolean(document.querySelector(${selectorLiteral("shell-main")})),
      sidebar: Boolean(document.querySelector(${selectorLiteral("left-panel")})),
      composer: Boolean(document.querySelector(${selectorLiteral("composer-chrome")})),
      main: Boolean(document.querySelector(${selectorLiteral("home-route")})),
      generic: genericCodexSurface(),
    };
    const settings = Boolean(document.querySelector(${selectorLiteral("settings-panel")})) ||
      Boolean(document.querySelector(${selectorLiteral("appearance-radio")})) ||
      Boolean(document.querySelector(${stableTestidLiteral("theme-preview")}));
    return {
      markers,
      excludedPetSurface,
      codex: !excludedPetSurface && location.protocol === 'app:' &&
        ((markers.shell && markers.sidebar) || settings || markers.main || markers.generic),
    };
  })()`);
}

async function waitForCodexProbe(session, timeoutMs = 1800) {
  const deadline = Date.now() + timeoutMs;
  let probe = null;
  while (Date.now() < deadline) {
    try {
      probe = await probeSession(session);
      if (probe?.codex) return probe;
    } catch {
      // The renderer may be between documents while the early payload waits.
    }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  return probe;
}

async function connectTarget(target, port) {
  return new CdpSession(target, port).open();
}

function unavailableNativeWindow(error) {
  const message = String(error?.message ?? "");
  const cdpCode = Number(error?.cdpCode);
  const withoutCode = message.replace(/\s*\(-?\d+\)\s*$/, "").trim();
  const domainUnsupported = cdpCode === -32601
    || /\(-32601\)\s*$/.test(message)
    || /^method(?: ['"]Browser\.getWindowForTarget['"])? not found$/i.test(withoutCode)
    || /^['"]?Browser\.getWindowForTarget['"]? (?:wasn't|was not) found$/i.test(withoutCode);
  // Codex 26.721.x (Chrome/150) answers -32000 "Browser window not found" for
  // the app's real, focused, on-screen window -- verified live via CDP: the
  // error is identical before and after actually activating the window, while
  // documentVisibility correctly flips hidden -> visible. The domain exists but
  // this build never resolves a window for our target, so -32000 is exactly as
  // uninformative here as -32601 elsewhere. Treat both the same way and lean on
  // documentVisible, which stays a hard requirement in windowPass below, as the
  // real visibility signal. Matches macOS classifyNativeWindowError. See #256.
  const windowNotFound = cdpCode === -32000
    || /\(-32000\)\s*$/.test(message)
    || /^browser window not found$/i.test(withoutCode)
    || /^no window with given target found$/i.test(withoutCode);
  return {
    pass: false,
    bound: false,
    unsupported: domainUnsupported || windowNotFound,
    reason: domainUnsupported ? "browser-window-api-unavailable"
      : windowNotFound ? "browser-window-not-found"
      : "target-window-unavailable",
  };
}

export async function inspectTargetWindow(session, targetId) {
  if (typeof targetId !== "string" || !BROWSER_ID_PATTERN.test(targetId)) {
    return { pass: false, bound: false, reason: "invalid-target-id" };
  }

  let binding;
  try {
    binding = await session.send("Browser.getWindowForTarget", { targetId });
  } catch (error) {
    return unavailableNativeWindow(error);
  }
  if (!Number.isInteger(binding?.windowId) || binding.windowId <= 0) {
    return { pass: false, bound: false, reason: "invalid-window-binding" };
  }

  let latest;
  try {
    latest = await session.send("Browser.getWindowBounds", { windowId: binding.windowId });
  } catch (error) {
    return unavailableNativeWindow(error);
  }
  const bounds = { ...(binding.bounds ?? {}), ...(latest?.bounds ?? {}) };
  const state = typeof bounds.windowState === "string" ? bounds.windowState : null;
  const width = Number.isFinite(bounds.width) ? Number(bounds.width) : null;
  const height = Number.isFinite(bounds.height) ? Number(bounds.height) : null;
  const statePass = VISIBLE_WINDOW_STATES.has(state);
  const boundsPass = width !== null && height !== null &&
    width >= MIN_RENDERER_VIEWPORT_WIDTH && height >= MIN_RENDERER_VIEWPORT_HEIGHT;
  return {
    pass: statePass && boundsPass,
    bound: true,
    windowId: binding.windowId,
    state,
    width,
    height,
    reason: !statePass ? "window-not-visible" : !boundsPass ? "window-bounds-too-small" : null,
  };
}

async function connectCodexTargets(port, timeoutMs, expectedBrowserId) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const targets = await listAppTargets(port, expectedBrowserId);
      const connected = [];
      for (const target of targets) {
        let session;
        try {
          session = await connectTarget(target, port);
          const probe = await probeSession(session);
          if (probe?.codex) connected.push({ target, session, probe });
          else {
            if (probe?.excludedPetSurface && !await cleanupExcludedSurface(session)) {
              throw new Error("Excluded Pet surface cleanup did not verify");
            }
            session.close();
          }
        } catch (error) {
          session?.close();
          lastError = error;
        }
      }
      if (connected.length) return connected;
      lastError = new Error("No page matched the expected Codex shell markers");
    } catch (error) {
      if (error instanceof CdpIdentityMismatchError) throw error;
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 350));
  }
  throw new Error(`No verified Codex renderer on 127.0.0.1:${port}: ${lastError?.message ?? "timed out"}`);
}

async function applyToSession(session, payload) {
  return session.evaluate(payload);
}

export function earlyPayloadFor(payload, revision) {
  return `(() => {
    const generationKey = "__CODEX_DREAM_SKIN_EARLY_GENERATION__";
    const appliedKey = "__CODEX_DREAM_SKIN_EARLY_APPLIED__";
    const generation = ${JSON.stringify(revision)};
    window[generationKey] = generation;
    let bootstrapTimer = null;
    let timeout = null;
    const stop = () => {
      if (bootstrapTimer) clearInterval(bootstrapTimer);
      bootstrapTimer = null;
      if (timeout) clearTimeout(timeout);
      timeout = null;
    };
    const hasCodexSurface = () => {
      if (location.protocol !== "app:") return false;
      const shell = document.querySelector(${selectorLiteral("shell-main")});
      const sidebar = document.querySelector(${selectorLiteral("left-panel")});
      const main = document.querySelector(${selectorLiteral("home-route")});
      const settings = document.querySelector(${selectorLiteral("settings-panel")}) ||
        document.querySelector(${selectorLiteral("appearance-radio")}) ||
        document.querySelector(${stableTestidLiteral("theme-preview")});
      const genericMain = document.querySelector('main, [role="main"]');
      const genericInput = document.querySelector('textarea, [contenteditable="true"], [role="textbox"]');
      const branded = Boolean(document.querySelector(
        ${stableTestidLiteral("app-shell-header-context-menu-surface")},
      ));
      return Boolean((shell && sidebar) || settings || main ||
        (genericMain && genericInput && branded));
    };
    const install = () => {
      if (window[generationKey] !== generation) { stop(); return true; }
      const root = document.documentElement;
      // The shared renderer can install against documentElement before body is
      // committed; requiring body here would create a visible unskinned first
      // frame on cold navigation.
      if (!root || !hasCodexSurface()) return false;
      stop();
      ${payload};
      window[appliedKey] = generation;
      return true;
    };
    if (install()) return;
    document.addEventListener?.("DOMContentLoaded", install, { once: true });
    bootstrapTimer = setInterval(install, 250);
    timeout = setTimeout(stop, 10000);
  })()`;
}

async function registerEarlyPayload(session, payload, revision) {
  const result = await session.send("Page.addScriptToEvaluateOnNewDocument", {
    source: earlyPayloadFor(payload, revision),
  });
  return result.identifier ?? null;
}

async function removeEarlyPayload(session, identifier) {
  if (!identifier || session.closed) return;
  await session.send("Page.removeScriptToEvaluateOnNewDocument", { identifier }).catch(() => {});
}


function nextOperationToken() {
  operationSequence += 1;
  return `${process.pid}:${Date.now()}:${operationSequence}`;
}

function operationKindMessage(kind) {
  if (kind === "pause") return "正在暂停皮肤…";
  if (kind === "switch") return "正在切换主题…";
  return "正在应用皮肤…";
}

function operationUiExpression(action, token, state = "loading", message = "") {
  const config = { action, token, state, message };
  return `(() => {
    const config = ${JSON.stringify(config)};
    const hostId = ${JSON.stringify(OPERATION_UI_HOST_ID)};
    const registryKey = ${JSON.stringify(OPERATION_UI_REGISTRY_KEY)};
    const css = ${JSON.stringify(OPERATION_UI_CSS)};
    const revealDelayMs = 16;
    const minimumLoadingMs = 700;
    const stateTtl = (value) => value === "loading" ? 180000
      : value === "success" ? 1800 : value === "cancelled" ? 2400 : 6000;
    const issuedAt = (value) => Number(String(value).split(":")[1]) || 0;
    const positionInMainArea = (host) => {
      const main = document.querySelector(${selectorLiteral("shell-main")}) ||
        document.querySelector("main") ||
        document.querySelector('[role="main"]') || document.documentElement;
      const rect = main.getBoundingClientRect();
      const top = Math.max(0, rect.top);
      const left = Math.max(0, rect.left);
      const width = Math.max(1, Math.min(innerWidth - left, rect.width || innerWidth));
      const height = Math.max(1, Math.min(innerHeight - top, rect.height || innerHeight));
      host.style.setProperty("--dream-skin-operation-top", String(top) + "px");
      host.style.setProperty("--dream-skin-operation-left", String(left) + "px");
      host.style.setProperty("--dream-skin-operation-width", String(width) + "px");
      host.style.setProperty("--dream-skin-operation-height", String(height) + "px");
    };
    const clearTimer = (timer) => { if (timer) clearTimeout(timer); };
    const removeHost = (expectedToken, force = false) => {
      const host = document.getElementById(hostId);
      const registry = window[registryKey];
      if (!force && host?.dataset.operationToken !== expectedToken) return false;
      if (!force && registry?.token && registry.token !== expectedToken) return false;
      clearTimer(registry?.showTimer);
      clearTimer(registry?.expiryTimer);
      clearTimer(registry?.terminalTimer);
      host?.remove();
      if (force || registry?.token === expectedToken) delete window[registryKey];
      return true;
    };
    if (config.action === "clear") {
      removeHost("", true);
      return { visible: false, cleared: true };
    }
    if (config.action === "hide") {
      return { visible: false, removed: removeHost(config.token) };
    }
    let host = document.getElementById(hostId);
    if (config.action === "show") {
      const currentIssuedAt = Number(host?.dataset.operationIssuedAt || 0);
      if (host?.dataset.operationToken !== config.token && currentIssuedAt > issuedAt(config.token)) {
        return { visible: false, stale: true };
      }
      removeHost("", true);
      host = document.createElement("div");
      host.id = hostId;
      host.dataset.operationToken = config.token;
      host.dataset.operationIssuedAt = String(issuedAt(config.token));
      host.dataset.state = config.state;
      host.setAttribute("role", "status");
      host.setAttribute("aria-live", "polite");
      host.setAttribute("aria-atomic", "true");
      const rgb = getComputedStyle(document.body || document.documentElement).backgroundColor.match(/\\d+(?:\\.\\d+)?/g)?.map(Number);
      const light = rgb?.length >= 3
        ? (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) > 150
        : matchMedia("(prefers-color-scheme: light)").matches;
      host.dataset.tone = light ? "light" : "dark";
      positionInMainArea(host);
      const shadow = host.attachShadow({ mode: "open" });
      const styleNode = document.createElement("style");
      styleNode.textContent = css;
      const statusNode = document.createElement("div");
      statusNode.className = "status";
      const indicator = document.createElement("span");
      indicator.className = "indicator";
      indicator.setAttribute("aria-hidden", "true");
      const messageNode = document.createElement("span");
      messageNode.className = "message";
      messageNode.textContent = config.message;
      statusNode.append(indicator, messageNode);
      shadow.append(styleNode, statusNode);
      document.documentElement.append(host);
      const registry = {
        token: config.token,
        startedAt: Date.now(),
        showTimer: null,
        expiryTimer: null,
        terminalTimer: null,
      };
      registry.showTimer = setTimeout(() => {
        const current = document.getElementById(hostId);
        if (current?.dataset.operationToken === config.token) current.dataset.visible = "true";
      }, revealDelayMs);
      registry.expiryTimer = setTimeout(() => removeHost(config.token), stateTtl(config.state));
      window[registryKey] = registry;
      return { visible: true, state: config.state };
    }
    if (!host || host.dataset.operationToken !== config.token) {
      return { visible: false, stale: true };
    }
    const registry = window[registryKey];
    clearTimer(registry?.terminalTimer);
    clearTimer(registry?.expiryTimer);
    positionInMainArea(host);
    const terminal = config.state === "success" || config.state === "error" || config.state === "cancelled";
    const remainingLoadingMs = terminal && host.dataset.state === "loading" && registry?.startedAt
      ? Math.max(0, registry.startedAt + minimumLoadingMs - Date.now())
      : 0;
    if (remainingLoadingMs > 0 && registry?.token === config.token) {
      registry.terminalTimer = setTimeout(() => {
        const current = document.getElementById(hostId);
        const currentRegistry = window[registryKey];
        if (current?.dataset.operationToken !== config.token || currentRegistry?.token !== config.token) return;
        current.dataset.state = config.state;
        current.dataset.visible = "true";
        const currentMessage = current.shadowRoot?.querySelector(".message");
        if (currentMessage) currentMessage.textContent = config.message;
        clearTimer(currentRegistry.expiryTimer);
        currentRegistry.expiryTimer = setTimeout(() => removeHost(config.token), stateTtl(config.state));
      }, remainingLoadingMs);
      return { visible: true, state: "loading", deferred: true };
    }
    host.dataset.state = config.state;
    host.dataset.visible = "true";
    const messageNode = host.shadowRoot?.querySelector(".message");
    if (messageNode) messageNode.textContent = config.message;
    if (registry?.token === config.token) {
      registry.expiryTimer = setTimeout(() => removeHost(config.token), stateTtl(config.state));
    }
    return { visible: true, state: config.state };
  })()`;
}

async function updateOperationUi(session, action, token, state, message, timeoutMs = 10000) {
  if (session.closed) return false;
  const result = await session.evaluate(
    operationUiExpression(action, token, state, message),
    timeoutMs,
  );
  return Boolean(result?.visible || result?.cleared || result?.removed);
}

async function bestEffortOperationUi(session, action, token, state, message, timeoutMs = 10000) {
  try {
    return await updateOperationUi(session, action, token, state, message, timeoutMs);
  } catch (error) {
    console.error(`[dream-skin] client status unavailable: ${error.message}`);
    return false;
  }
}

async function presentOperationUi(session, token, state, message, timeoutMs = 10000) {
  const updated = await bestEffortOperationUi(
    session, "update", token, state, message, timeoutMs,
  );
  if (updated) return true;
  return bestEffortOperationUi(session, "show", token, state, message, timeoutMs);
}

async function removeFromSession(session) {
  return session.evaluate(`(() => {
    window.__CODEX_DREAM_SKIN_DISABLED__ = true;
    const state = window.__CODEX_DREAM_SKIN_STATE__;
    let cleaned = false;
    try { cleaned = Boolean(state?.cleanup && state.cleanup()); } catch {}
    if (cleaned) return true;
    const root = document.documentElement;
    for (const attribute of [...(root?.attributes || [])]) {
      if (attribute.name.startsWith('data-dream-')) root.removeAttribute(attribute.name);
    }
    for (const property of [...(root?.style || [])]) {
      if (property.startsWith('--dream-') || property.startsWith('--ds-')) {
        root.style.removeProperty(property);
      }
    }
    for (const node of document.querySelectorAll('[data-ds-part]')) {
      node.removeAttribute('data-ds-part');
    }
    const sheets = window.__CODEX_DREAM_SKIN_STYLE_SHEETS__;
    if (sheets && 'adoptedStyleSheets' in document) {
      document.adoptedStyleSheets = [...document.adoptedStyleSheets]
        .filter((sheet) => !sheets.has(sheet));
    }
    delete window.__CODEX_DREAM_SKIN_STYLE_SHEETS__;
    try { if (state?.artUrl) URL.revokeObjectURL(state.artUrl); } catch {}
    document.getElementById('codex-dream-skin-style')?.remove();
    delete window.__CODEX_DREAM_SKIN_STATE__;
    return true;
  })()`);
}

async function verifyRemovedSession(session) {
  return session.evaluate(`(() => {
    const root = document.documentElement;
    const hasAttributes = [...root.attributes].some((attribute) =>
      attribute.name.startsWith('data-dream-'));
    const hasVariables = [...root.style].some((property) =>
      property.startsWith('--dream-') || property.startsWith('--ds-'));
    const hasParts = Boolean(document.querySelector('[data-ds-part]'));
    const sheets = window.__CODEX_DREAM_SKIN_STYLE_SHEETS__;
    const hasSheets = Boolean(sheets?.size && 'adoptedStyleSheets' in document &&
      [...document.adoptedStyleSheets].some((sheet) => sheets.has(sheet)));
    return !hasAttributes && !hasVariables && !hasParts && !hasSheets &&
      !document.getElementById('codex-dream-skin-style') &&
      !window.__CODEX_DREAM_SKIN_STATE__;
  })()`);
}

export async function cleanupExcludedSurface(session) {
  if (!await removeFromSession(session)) return false;
  return verifyRemovedSession(session);
}

export async function verifySession(
  session,
  targetId,
  expectedThemeId = null,
  expectedRevision = null,
) {
  const nativeWindow = await inspectTargetWindow(session, targetId);
  return session.evaluate(`(() => {
    const box = (node) => {
      if (!node) return null;
      const r = node.getBoundingClientRect();
      const style = getComputedStyle(node);
      const opacity = Number.parseFloat(style.opacity);
      const right = Number.isFinite(r.right) ? r.right : r.x + r.width;
      const bottom = Number.isFinite(r.bottom) ? r.bottom : r.y + r.height;
      let cssVisible = r.width > 0 && r.height > 0 && style.display !== 'none' &&
        style.visibility !== 'hidden' && style.visibility !== 'collapse' &&
        style.contentVisibility !== 'hidden' && (!Number.isFinite(opacity) || opacity > 0);
      try {
        if (typeof node.checkVisibility === 'function') {
          cssVisible = cssVisible && node.checkVisibility({
            checkOpacity: true,
            checkVisibilityCSS: true,
          });
        }
      } catch {}
      const intersectsViewport = right > 0 && bottom > 0 && r.x < innerWidth && r.y < innerHeight;
      return {
        x: Math.round(r.x), y: Math.round(r.y),
        width: Math.round(r.width), height: Math.round(r.height),
        visible: Boolean(node.isConnected !== false && cssVisible && intersectsViewport),
      };
    };
    const homeIndicator = document.querySelector(${selectorLiteral("home-icon")});
    const homeSignal = homeIndicator ?? document.querySelector(${selectorLiteral("game-source")}) ??
      document.querySelector(${selectorLiteral("home-suggestions")});
    const homeRoute = homeSignal?.closest('[role="main"]') ?? null;
    // Codex 26.721.x can render the home content before home-icon. Reuse the
    // already-resolved semantic home container so a healthy home session is
    // not rejected solely because the stricter home-icon selector is late.
    const home = document.querySelector(${selectorLiteral("home-route")}) ?? homeRoute;
    const suggestions = home?.querySelector(${selectorLiteral("home-suggestions")}) ?? null;
    const cardButtons = suggestions ? [...suggestions.querySelectorAll('button')] : [];
    const cards = cardButtons.map(box);
    const visibleCards = cards.filter((item) => item?.visible);
    const suggestionLabels = cardButtons.flatMap((button) => {
      const expectedColor = getComputedStyle(button).color;
      return [...button.querySelectorAll('*')]
        .filter((node) => [...node.childNodes].some((child) =>
          child.nodeType === 3 && child.textContent.trim()))
        .map((node) => ({
          ...box(node),
          text: String(node.textContent ?? "").trim().slice(0, 80),
          color: getComputedStyle(node).color,
          expectedColor,
        }));
    });
    const visibleSuggestionLabels = suggestionLabels.filter((item) => item?.visible);
    const suggestionLabelColorsMatch = visibleSuggestionLabels.every((item) =>
      item.color === item.expectedColor);
    const settingsAnchor = document.querySelector(${selectorLiteral("settings-panel")}) ||
      document.querySelector(${selectorLiteral("appearance-radio")}) ||
      document.querySelector(${stableTestidLiteral("theme-preview")});
    const runtime = window.__CODEX_DREAM_SKIN_STATE__;
    const adopted = runtime?.styleMode === 'adopted' &&
      [...document.adoptedStyleSheets].includes(runtime.styleSheet);
    const fallback = runtime?.styleMode === 'style' &&
      document.getElementById('codex-dream-skin-style') === runtime.styleNode;
    // Codex 26.721+ moved the real home content out of home.firstElementChild's
    // descendant chain: that wrapper now only holds the (usually empty) native
    // .home-banners slot, and the actual content became its sibling instead
    // (see #244). Prefer a sibling of the banner-holding wrapper when present;
    // fall back to the pre-26.721 first-child chain (deepest visible node)
    // otherwise, so older Codex builds keep working unchanged.
    const homeChildren = home?.children ? Array.from(home.children) : [];
    const bannerHolder = homeChildren.find((el) => el.querySelector(${selectorLiteral("home-banners")}));
    const siblingCandidates = homeChildren.filter((el) => el !== bannerHolder).map(box);
    const heroChain = [];
    for (let node = home?.firstElementChild ?? null; node && heroChain.length < 3;
      node = node.firstElementChild) heroChain.push(node);
    const boxableChain = heroChain.filter((node) => typeof node?.getBoundingClientRect === "function");
    const chainCandidates = boxableChain.map(box);
    const hero = siblingCandidates.find((item) => item?.visible && item.width >= 280 && item.height >= 120)
      ?? chainCandidates.findLast((item) => item?.visible)
      ?? siblingCandidates.find((item) => item?.visible)
      ?? box(boxableChain[boxableChain.length - 1]);
    const result = {
      installed: document.documentElement.getAttribute('data-dream-skin') === 'active',
      version: runtime?.version ?? null,
      expectedVersion: ${JSON.stringify(SKIN_VERSION)},
      themeId: runtime?.themeId ?? null,
      revision: runtime?.revision ?? null,
      styleMode: runtime?.styleMode ?? null,
      stylePresent: Boolean(adopted || fallback),
      scope: runtime?.scope ?? null,
      businessClassPollution: [...document.querySelectorAll('[class]')].filter((node) =>
        [...node.classList].some((name) => /^(?:dream-|codex-dream-skin(?:-|$))/.test(name))
      ).length,
      homePresent: Boolean(home),
      suggestionsPresent: Boolean(suggestions),
      homeSurface: box(home),
      settingsAnchor: box(settingsAnchor),
      hero,
      cards,
      visibleCardCount: visibleCards.length,
      suggestionLabels,
      suggestionLabelColorsMatch,
      composer: box(document.querySelector(${selectorLiteral("composer-chrome")})),
      shell: box(document.querySelector(${selectorLiteral("shell-main")})),
      sidebar: box(document.querySelector(${selectorLiteral("left-panel")})),
      genericMain: box(document.querySelector('[data-ds-part="main"], [data-ds-part="home"]')),
      genericInput: box(document.querySelector('[data-ds-part="composer"]')),
      nativeWindow: ${JSON.stringify(nativeWindow)},
      documentVisibility: document.visibilityState ?? null,
      documentHidden: document.hidden === true,
      viewport: { width: innerWidth, height: innerHeight },
      documentOverflow: {
        x: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        y: document.documentElement.scrollHeight > document.documentElement.clientHeight,
      },
    };
    const homeScope = result.scope?.baseState === 'home' || result.homePresent;
    const l1ScopePass = result.scope?.level === 'L1' &&
      Array.isArray(result.scope?.missingL1) && result.scope.missingL1.length === 0;
    const genericStructurePass = l1ScopePass && Boolean(result.genericMain?.visible) &&
      Boolean(result.genericInput?.visible || (homeScope && result.homeSurface?.visible));
    const l0StructurePass = result.scope?.level === 'L0' &&
      result.scope?.baseState === 'settings' && Boolean(result.settingsAnchor?.visible);
    const structurePass = l0StructurePass || (l1ScopePass &&
      (Boolean(result.shell?.visible && result.sidebar?.visible) || genericStructurePass));
    const documentPass = result.documentVisibility === 'visible' && !result.documentHidden;
    const viewportPass = result.viewport.width >= ${MIN_RENDERER_VIEWPORT_WIDTH} &&
      result.viewport.height >= ${MIN_RENDERER_VIEWPORT_HEIGHT};
    const nativeWindowPass = result.nativeWindow?.pass === true;
    // Codex 26.721.x (Chrome/150) cannot resolve a native window for our target
    // even when that window is real, focused and on-screen (-32000), and older
    // builds omit the Browser domain outright (-32601). The injector classifies
    // both as unsupported; in that case fall back to the renderer's own
    // visibility evidence instead of failing every install. documentPass and
    // viewportPass below stay hard requirements, so a genuinely hidden or
    // collapsed window still fails closed. Mirrors the macOS
    // assessRendererVerification fallbackWindowPass. See #256.
    const fallbackWindowPass = result.nativeWindow?.unsupported === true;
    const windowPass = nativeWindowPass || fallbackWindowPass;
    const expectedThemeId = ${JSON.stringify(expectedThemeId)};
    const expectedRevision = ${JSON.stringify(expectedRevision)};
    const payloadPass = (!expectedThemeId || result.themeId === expectedThemeId) &&
      (!expectedRevision || result.revision === expectedRevision);
    result.expectedThemeId = expectedThemeId;
    result.expectedRevision = expectedRevision;
    result.readiness = {
      windowPass, documentPass, viewportPass, structurePass,
      nativeWindowPass, fallbackWindowPass,
    };
    const homePass = !homeScope || (
      result.homePresent && Boolean(result.homeSurface?.visible) &&
      ((result.hero?.visible && result.hero.width >= 280 && result.hero.height >= 120) ||
        Boolean(result.genericMain?.visible)) &&
      (!result.suggestionsPresent || result.visibleCardCount === 0 || (
        result.suggestionLabels.filter((item) => item?.visible).length >= result.visibleCardCount &&
        result.suggestionLabelColorsMatch
      ))
    );
    result.pass = result.installed && result.version === result.expectedVersion &&
      result.stylePresent && result.businessClassPollution === 0 && !result.documentOverflow.x &&
      windowPass && documentPass && viewportPass && structurePass &&
      payloadPass && homePass;
    return result;
  })()`);
}

async function waitForVerifiedSession(
  session,
  targetId,
  timeoutMs,
  expectedThemeId = null,
  expectedRevision = null,
) {
  const deadline = Date.now() + timeoutMs;
  let lastResult;
  let lastError;
  while (Date.now() < deadline) {
    try {
      lastResult = await verifySession(session, targetId, expectedThemeId, expectedRevision);
      lastError = null;
      if (lastResult.pass) return lastResult;
    } catch (error) {
      lastError = error;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  if (!lastResult && lastError) throw lastError;
  return lastResult;
}

async function capture(session, outputPath) {
  await fs.mkdir(path.dirname(outputPath), { recursive: true });
  const result = await session.send("Page.captureScreenshot", {
    format: "png",
    fromSurface: true,
    captureBeyondViewport: false,
  });
  await fs.writeFile(outputPath, Buffer.from(result.data, "base64"));
}

async function runBeginOperation(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs, options.browserId);
  const operationToken = options.operationToken ?? nextOperationToken();
  let shown = false;
  try {
    const results = await Promise.all(connected.map(({ session }) => presentOperationUi(
      session,
      operationToken,
      "loading",
      operationKindMessage(options.operationKind),
      Math.max(250, Math.floor(options.timeoutMs / 2)),
    )));
    shown = results.some(Boolean);
  } finally {
    for (const { session } of connected) session.close();
  }
  if (!shown) throw new Error("Could not show operation progress in the verified Codex renderer");
  process.stdout.write(`${operationToken}\n`);
}

async function runFinishOperation(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs, options.browserId);
  let shown = false;
  try {
    const results = await Promise.all(connected.map(({ session }) => presentOperationUi(
      session,
      options.operationToken,
      options.operationUiState,
      options.operationMessage,
      Math.max(250, Math.floor(options.timeoutMs / 2)),
    )));
    shown = results.some(Boolean);
  } finally {
    for (const { session } of connected) session.close();
  }
  if (!shown) throw new Error("Could not show the completed operation state in the verified Codex renderer");
}

async function runOneShot(options) {
  const connected = await connectCodexTargets(options.port, options.timeoutMs, options.browserId);
  const operationToken = options.mode === "once" || options.mode === "remove"
    ? options.operationToken ?? nextOperationToken()
    : null;
  if (operationToken) {
    const message = options.mode === "remove" ? "正在暂停皮肤…" : "正在准备皮肤…";
    const action = options.operationToken ? presentOperationUi : (session, token, state, text) =>
      bestEffortOperationUi(session, "show", token, state, text);
    await Promise.all(connected.map(({ session }) => action(
      session, operationToken, "loading", message,
    )));
  }
  let loadedPayload = null;
  try {
    loadedPayload = (options.mode === "once" || options.mode === "verify" || options.reload)
      ? await loadPayload(options.themeDir) : null;
  } catch (error) {
    if (operationToken) {
      await Promise.all(connected.map(({ session }) => presentOperationUi(
        session, operationToken, "error", "皮肤准备失败",
      )));
    }
    for (const { session } of connected) session.close();
    throw error;
  }
  const payload = loadedPayload?.payload ?? null;
  const results = [];
  let screenshotCaptured = false;
  try {
    for (const { target, session, probe } of connected) {
      try {
        if (options.mode === "remove") await removeFromSession(session);
        else if (options.mode === "once") {
          if (operationToken) {
            await bestEffortOperationUi(
              session, "update", operationToken, "loading",
              `正在应用「${loadedPayload.theme.name}」…`,
            );
          }
          await applyToSession(session, payload);
          await new Promise((resolve) => setTimeout(resolve, 850));
        }
        if (options.reload) {
          await session.send("Page.reload", { ignoreCache: true });
          await new Promise((resolve) => setTimeout(resolve, 1600));
          if (options.mode !== "remove") {
            if (operationToken) {
              await presentOperationUi(
                session, operationToken, "loading",
                `正在应用「${loadedPayload.theme.name}」…`,
              );
            }
            await applyToSession(session, payload);
          }
        }
        if (operationToken) {
          await presentOperationUi(
            session,
            operationToken,
            "loading",
            options.mode === "remove" ? "正在确认皮肤已暂停…" : "正在检查显示效果…",
          );
        }
        const verified = options.mode === "remove"
          ? await verifyRemovedSession(session)
          : (options.reload || options.mode === "once" || options.mode === "verify")
            ? await waitForVerifiedSession(
              session,
              target.id,
              options.timeoutMs,
              loadedPayload?.theme.id ?? null,
              loadedPayload?.revision ?? null,
            )
            : await verifySession(session, target.id);
        results.push({ targetId: target.id, markers: probe.markers, result: verified });
        if (operationToken) {
          const passed = options.mode === "remove" ? verified === true : verified?.pass;
          await presentOperationUi(
            session,
            operationToken,
            passed ? "success" : "error",
            passed
              ? options.mode === "remove" ? "皮肤已暂停" : `已应用「${loadedPayload.theme.name}」`
              : options.mode === "remove" ? "暂停校验失败" : "显示校验失败",
          );
        }
        if (options.screenshot && !screenshotCaptured) {
          if (operationToken) {
            await bestEffortOperationUi(session, "hide", operationToken, "loading", "");
          }
          await capture(session, options.screenshot);
          screenshotCaptured = true;
        }
      } catch (error) {
        if (operationToken) {
          await presentOperationUi(
            session,
            operationToken,
            "error",
            options.mode === "remove" ? "暂停失败，请重试" : "应用失败，请重试",
          );
        }
        results.push({ targetId: target.id, markers: probe?.markers, error: error.message });
      } finally {
        session.close();
      }
    }
  } finally {
    for (const { session } of connected) session.close();
  }
  console.log(JSON.stringify({ mode: options.mode, port: options.port, targets: results }, null, 2));
  const failed = results.length === 0 || results.some((item) =>
    item.error || (options.mode === "remove" ? item.result !== true : !item.result?.pass));
  if (failed) process.exitCode = 2;
}

async function runWatch(options) {
  const identityAnchor = await connectBrowserIdentityAnchor(options.port, options.browserId);
  const sessions = new Map();
  const earlyScripts = new Map();
  const fallbackTargets = new Map();
  const fallbackListeners = new Set();
  const targetFailures = new Map();
  let stopping = false;
  let listFailures = 0;
  let lastListErrorLogAt = 0;
  let lastThemeErrorLogAt = 0;
  let lastStrongThemeAuditAt = 0;
  let loadedPayload = null;
  let paused = false;
  const stop = () => { stopping = true; };
  const rejectTarget = (target, baseDelayMs, error = null) => {
    const previous = targetFailures.get(target.id) ?? { failures: 0, lastLogAt: 0 };
    const failures = previous.failures + 1;
    const delayMs = Math.min(30000, baseDelayMs * (2 ** Math.min(failures - 1, 4)));
    const now = Date.now();
    if (error && (failures === 1 || now - previous.lastLogAt >= 30000)) {
      console.error(`[dream-skin] inject failed for ${target.id}: ${error.message}; retrying in ${delayMs}ms`);
      previous.lastLogAt = now;
    }
    targetFailures.set(target.id, { failures, lastLogAt: previous.lastLogAt, until: now + delayMs });
  };
  const attachLoadFallback = (id, target, session) => {
    if (fallbackListeners.has(id)) return;
    fallbackListeners.add(id);
    let lastReinjectErrorLogAt = 0;
    session.on("Page.loadEventFired", () => {
      if (!fallbackTargets.get(id)) return;
      setTimeout(() => {
        const operation = paused ? removeFromSession(session) : applyToSession(session, loadedPayload.payload);
        operation.catch((error) => {
          if (Date.now() - lastReinjectErrorLogAt >= 30000) {
            console.error(`[dream-skin] reinject failed for ${target.id}: ${error.message}`);
            lastReinjectErrorLogAt = Date.now();
          }
        });
      }, 250);
    });
  };
  process.on("SIGINT", stop);
  process.on("SIGTERM", stop);

  try {
    loadedPayload = await loadPayload(options.themeDir);
    lastStrongThemeAuditAt = Date.now();
    paused = await fileExists(options.pauseFile);
    while (!stopping) {
      if (identityAnchor.closed) {
        console.error("[dream-skin] original CDP browser identity closed; watcher is stopping instead of reconnecting");
        process.exitCode = 3;
        break;
      }
      let targets = [];
      try {
        targets = await listAppTargets(options.port);
        listFailures = 0;
      } catch (error) {
        listFailures += 1;
        const retryMs = Math.min(10000, 1000 * (2 ** Math.min(listFailures - 1, 4)));
        if (listFailures === 1 || Date.now() - lastListErrorLogAt >= 30000) {
          console.error(`[dream-skin] ${new Date().toISOString()} ${error.message}; retrying in ${retryMs}ms`);
          lastListErrorLogAt = Date.now();
        }
        await new Promise((resolve) => setTimeout(resolve, retryMs));
        continue;
      }

      const nextPaused = await fileExists(options.pauseFile);
      let nextPayload = loadedPayload;
      if (!nextPaused) {
        try {
          const now = Date.now();
          let shouldAudit = !loadedPayload || now - lastStrongThemeAuditAt >= STRONG_THEME_AUDIT_MS;
          if (!shouldAudit) {
            try {
              shouldAudit = await readThemeSourceStamp(loadedPayload) !== loadedPayload.sourceStamp;
            } catch {
              shouldAudit = true;
            }
          }
          if (shouldAudit) {
            const candidateTheme = await loadTheme(options.themeDir);
            lastStrongThemeAuditAt = now;
            if (!loadedPayload || candidateTheme.fingerprint !== loadedPayload.fingerprint) {
              nextPayload = await loadPayload(options.themeDir, candidateTheme);
            } else {
              loadedPayload.sourceStamp = candidateTheme.sourceStamp;
            }
          }
        } catch (error) {
          if (Date.now() - lastThemeErrorLogAt >= 30000) {
            console.error(`[dream-skin] theme update rejected: ${error.message}; keeping the active theme`);
            lastThemeErrorLogAt = Date.now();
          }
        }
      }
      const pauseChanged = nextPaused !== paused;
      const payloadChanged = !nextPaused && nextPayload !== loadedPayload;
      loadedPayload = nextPayload;
      paused = nextPaused;

      if (pauseChanged || payloadChanged) {
        for (const [id, session] of sessions) {
          try {
            const previousEarlyScript = earlyScripts.get(id);
            if (paused) {
              await removeFromSession(session);
              await removeEarlyPayload(session, previousEarlyScript);
              earlyScripts.delete(id);
              fallbackTargets.delete(id);
              fallbackListeners.delete(id);
            } else {
              let nextEarlyScript = null;
              try {
                nextEarlyScript = await registerEarlyPayload(
                  session,
                  loadedPayload.payload,
                  loadedPayload.fingerprint,
                );
                if (!nextEarlyScript) throw new Error("CDP did not return an early-script identifier");
                fallbackTargets.set(id, false);
              } catch (error) {
                fallbackTargets.set(id, true);
                console.error(`[dream-skin] early theme refresh unavailable for ${id}: ${error.message}`);
                attachLoadFallback(id, { id }, session);
              }
              if (nextEarlyScript) earlyScripts.set(id, nextEarlyScript);
              else earlyScripts.delete(id);
              await removeEarlyPayload(session, previousEarlyScript);
              await applyToSession(session, loadedPayload.payload);
            }
          } catch (error) {
            console.error(`[dream-skin] live theme update failed for ${id}: ${error.message}`);
            await removeEarlyPayload(session, earlyScripts.get(id));
            earlyScripts.delete(id);
            fallbackTargets.delete(id);
            fallbackListeners.delete(id);
            session.close();
            sessions.delete(id);
          }
        }
        console.log(paused ? "[dream-skin] paused" : `[dream-skin] active theme ${loadedPayload.theme.id}`);
      }

      const activeIds = new Set(targets.map((target) => target.id));
      for (const id of targetFailures.keys()) {
        if (!activeIds.has(id)) targetFailures.delete(id);
      }
      for (const [id, session] of sessions) {
        if (!activeIds.has(id) || session.closed) {
          await removeEarlyPayload(session, earlyScripts.get(id));
          earlyScripts.delete(id);
          fallbackTargets.delete(id);
          fallbackListeners.delete(id);
          session.close();
          sessions.delete(id);
          targetFailures.delete(id);
        }
      }

      for (const target of targets) {
        if (identityAnchor.closed) break;
        if (sessions.has(target.id)) continue;
        if ((targetFailures.get(target.id)?.until ?? 0) > Date.now()) continue;
        let session;
        let earlyScriptId = null;
        try {
          session = await connectTarget(target, options.port);
          if (identityAnchor.closed) throw new CdpIdentityMismatchError("Original CDP browser identity closed");
          let earlyInjectionFallback = false;
          if (!paused) {
            try {
              earlyScriptId = await registerEarlyPayload(
                session,
                loadedPayload.payload,
                loadedPayload.fingerprint,
              );
              if (!earlyScriptId) throw new Error("CDP did not return an early-script identifier");
              await session.evaluate(earlyPayloadFor(loadedPayload.payload, loadedPayload.fingerprint));
            } catch (error) {
              await removeEarlyPayload(session, earlyScriptId);
              earlyScriptId = null;
              earlyInjectionFallback = true;
              console.error(`[dream-skin] early injection unavailable for ${target.id}: ${error.message}`);
            }
          }
          const probe = await waitForCodexProbe(session);
          if (!probe?.codex) {
            await removeEarlyPayload(session, earlyScriptId);
            if (probe?.excludedPetSurface && !await cleanupExcludedSurface(session)) {
              throw new Error("Excluded Pet surface cleanup did not verify");
            }
            rejectTarget(target, 5000);
            session.close();
            continue;
          }
          fallbackTargets.set(target.id, earlyInjectionFallback);
          if (earlyInjectionFallback) attachLoadFallback(target.id, target, session);
          if (identityAnchor.closed) throw new CdpIdentityMismatchError("Original CDP browser identity closed");
          let earlyApplied = false;
          if (!paused && !earlyInjectionFallback) {
            earlyApplied = await session.evaluate(
              `window.__CODEX_DREAM_SKIN_EARLY_APPLIED__ === ${JSON.stringify(loadedPayload.fingerprint)}`,
            ).catch(() => false);
          }
          if (paused) await removeFromSession(session);
          else if (!earlyApplied) await applyToSession(session, loadedPayload.payload);
          sessions.set(target.id, session);
          if (earlyScriptId) earlyScripts.set(target.id, earlyScriptId);
          targetFailures.delete(target.id);
          console.log(`[dream-skin] injected target ${target.id}`);
        } catch (error) {
          await removeEarlyPayload(session, earlyScriptId);
          fallbackTargets.delete(target.id);
          fallbackListeners.delete(target.id);
          session?.close();
          if (identityAnchor.closed || error instanceof CdpIdentityMismatchError) break;
          rejectTarget(target, 2500, error);
        }
      }
      await new Promise((resolve) => setTimeout(resolve, 1200));
    }
  } finally {
    identityAnchor.close();
    for (const [id, session] of sessions) {
      await removeEarlyPayload(session, earlyScripts.get(id));
      session.close();
    }
    earlyScripts.clear();
    fallbackTargets.clear();
    fallbackListeners.clear();
  }
}

// --- ZCode Phase 1 proof of concept -----------------------------------------
// The PoC deliberately touches nothing but its own two fixed nodes: it exists to
// prove that a real ZCode renderer can be identified, written to, and cleaned up
// again without restarting the app. It never loads a background image or the
// theme CSS.

const ZCODE_POC_ID = "zcode-dream-skin-poc";
const ZCODE_POC_STYLE_ID = "zcode-dream-skin-poc-style";

function zcodePoCProbeExpression() {
  // Reports shape and stability only: no titles, URLs, or page text leave the
  // renderer, so the evidence cannot carry user content.
  return `(() => ({
  readyState: document.readyState,
  protocol: String(location.protocol || ""),
  bodyPresent: Boolean(document.body),
  rootChildCount: document.documentElement ? document.documentElement.childElementCount : 0,
  titleLength: String(document.title || "").length,
  urlLength: String(location.href || "").length,
  existingSkinNodes: document.querySelectorAll('[id^="codex-dream-skin-"], [id^="zcode-dream-skin-"]').length
}))()`;
}

function zcodePoCInjectExpression() {
  return `(() => {
  const ID = ${JSON.stringify(ZCODE_POC_ID)};
  const STYLE_ID = ${JSON.stringify(ZCODE_POC_STYLE_ID)};
  for (const stale of document.querySelectorAll('[id^="zcode-dream-skin-"]')) stale.remove();
  const style = document.createElement("style");
  style.id = STYLE_ID;
  style.textContent = "#" + ID + "{position:fixed;top:10px;right:10px;z-index:2147483647;"
    + "pointer-events:none;padding:6px 10px;border-radius:8px;color:#fff;"
    + "font:600 12px/1.4 system-ui,'Segoe UI',sans-serif;background:rgba(20,20,26,.86);"
    + "border:1px solid rgba(255,255,255,.32)}";
  (document.head || document.documentElement).appendChild(style);
  const badge = document.createElement("div");
  badge.id = ID;
  badge.setAttribute("data-zcode-dream-skin-poc", "phase1");
  badge.textContent = "ZCode Dream Skin PoC";
  (document.body || document.documentElement).appendChild(badge);
  return {
    pocCount: document.querySelectorAll("#" + ID).length,
    styleCount: document.querySelectorAll("#" + STYLE_ID).length,
    pointerEvents: String(getComputedStyle(badge).pointerEvents || "")
  };
})()`;
}

function zcodePoCRemoveExpression() {
  return `(() => {
  for (const node of document.querySelectorAll('[id^="zcode-dream-skin-"]')) node.remove();
  return {
    remainingSkinNodes: document.querySelectorAll('[id^="zcode-dream-skin-"]').length,
    pocCount: document.querySelectorAll('#${ZCODE_POC_ID}').length,
    styleCount: document.querySelectorAll('#${ZCODE_POC_STYLE_ID}').length,
    badgeTextPresent: document.body
      ? String(document.body.innerText || "").includes("ZCode Dream Skin PoC") : false,
    readyState: document.readyState
  };
})()`;
}

function sanitizeTargetUrl(value) {
  try {
    const url = new URL(String(value ?? ""));
    url.search = "";
    url.hash = "";
    return url.href.slice(0, 200);
  } catch {
    return String(value ?? "").slice(0, 200);
  }
}

async function closeBrowserGracefully(port, expectedBrowserId) {
  const version = await fetchCdpJson(port, "/json/version");
  const browserId = browserIdFromVersion(version, port);
  if (expectedBrowserId && browserId !== expectedBrowserId) {
    throw new CdpIdentityMismatchError(
      `CDP browser identity mismatch before close: expected ${expectedBrowserId}, found ${browserId}`,
    );
  }
  const ws = new WebSocket(validatedDebuggerUrl(
    { webSocketDebuggerUrl: version.webSocketDebuggerUrl }, port,
  ));
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      try { ws.close(); } catch {}
      reject(new Error("CDP browser WebSocket open timed out"));
    }, 5000);
    ws.addEventListener("open", () => { clearTimeout(timeout); resolve(); }, { once: true });
    ws.addEventListener("error", () => {
      clearTimeout(timeout);
      reject(new Error("CDP browser WebSocket open failed"));
    }, { once: true });
  });
  ws.send(JSON.stringify({ id: 1, method: "Browser.close" }));
  await new Promise((resolve) => setTimeout(resolve, 1500));
  try { ws.close(); } catch {}
  return true;
}

async function runZCodePoc(options) {
  const reportPath = path.resolve(options.report);
  const report = {
    mode: "zcode-poc",
    port: options.port,
    browserId: null,
    browser: "",
    targetCount: 0,
    pass2CdpEndpoint: false,
    pass3MainRenderer: false,
    pass4RuntimeEvaluate: false,
    pass5RemoveTheme: false,
    selectedTarget: {},
    targetDiagnostics: [],
    renderer: {},
    injection: {},
    removal: {},
    screenshots: {},
    browserClosed: false,
    errors: [],
  };
  let session = null;
  const screenshot = async (target) => {
    if (!target) return "";
    try {
      await capture(session, target);
      return target;
    } catch (error) {
      report.errors.push(`screenshot failed: ${String(error?.message ?? error).slice(0, 200)}`);
      return "";
    }
  };
  try {
    const version = await fetchCdpJson(options.port, "/json/version");
    const browserId = browserIdFromVersion(version, options.port);
    if (options.browserId && browserId !== options.browserId) {
      throw new CdpIdentityMismatchError(
        `CDP browser identity mismatch: expected ${options.browserId}, found ${browserId}`,
      );
    }
    report.browserId = browserId;
    report.browser = String(version?.Browser ?? "").slice(0, 120);
    report.pass2CdpEndpoint = true;
    console.log(`[CDP] /json/version ok on 127.0.0.1:${options.port} browser=${report.browser}`);

    const listed = await fetchCdpJson(options.port, "/json/list");
    const targets = Array.isArray(listed) ? listed : [];
    report.targetCount = targets.length;
    report.targetDiagnostics = targets.map((item) => ({
      type: String(item?.type ?? ""),
      url: sanitizeTargetUrl(item?.url),
      hasDebuggerUrl: Boolean(item?.webSocketDebuggerUrl),
    }));
    const selected = selectZCodeMainTarget(targets, (line) => console.log(`[TARGET] ${line}`));
    const scored = scoreZCodeTarget(selected);
    report.selectedTarget = {
      id: String(selected.id ?? ""),
      type: String(selected.type ?? ""),
      url: sanitizeTargetUrl(selected.url),
      score: scored.score,
      reasons: scored.reasons,
    };

    session = new CdpSession(selected, options.port);
    await session.open();
    const deadline = Date.now() + Math.max(1000, options.timeoutMs);
    let probe = null;
    while (Date.now() < deadline) {
      probe = await session.evaluate(zcodePoCProbeExpression());
      if (probe && probe.bodyPresent && probe.readyState !== "loading") break;
      await new Promise((resolve) => setTimeout(resolve, 300));
    }
    report.renderer = probe ?? {};
    report.pass3MainRenderer = Boolean(probe && probe.bodyPresent && probe.readyState !== "loading");
    if (!report.pass3MainRenderer) {
      throw new Error(
        "E07_NO_RENDERER_TARGET: the selected target never reached a usable document state",
      );
    }
    console.log(`[RENDERER] ${report.selectedTarget.url} readyState=${probe.readyState}`);

    const first = await session.evaluate(zcodePoCInjectExpression());
    const second = await session.evaluate(zcodePoCInjectExpression());
    report.injection = { first, second };
    report.pass4RuntimeEvaluate = Boolean(
      first && first.pocCount === 1 && first.styleCount === 1 && first.pointerEvents === "none" &&
      second && second.pocCount === 1 && second.styleCount === 1,
    );
    if (!report.pass4RuntimeEvaluate) {
      throw new Error("E09_RUNTIME_EVALUATE_FAILED: the PoC marker was not injected exactly once");
    }
    console.log("[INJECT] PoC marker present exactly once after two applications");
    report.screenshots.injected = await screenshot(options.screenshotInjected);

    const removal = await session.evaluate(zcodePoCRemoveExpression());
    const alive = await session.evaluate("({ ok: true, readyState: document.readyState })");
    const afterRemoval = await fetchCdpJson(options.port, "/json/list");
    const stillListed = Array.isArray(afterRemoval)
      && afterRemoval.some((item) => String(item?.id) === String(selected.id));
    report.removal = { ...removal, sessionAlive: Boolean(alive?.ok), targetStillListed: stillListed };
    report.pass5RemoveTheme = Boolean(
      removal && removal.remainingSkinNodes === 0 && removal.pocCount === 0 &&
      removal.styleCount === 0 && removal.badgeTextPresent === false &&
      alive?.ok === true && stillListed,
    );
    if (!report.pass5RemoveTheme) {
      throw new Error("E10_REMOVE_THEME_FAILED: a PoC node or effect survived removal");
    }
    console.log("[REMOVE] PoC marker and style gone; renderer still alive and listed");
    report.screenshots.removed = await screenshot(options.screenshotRemoved);
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.closeBrowser) {
      try {
        report.browserClosed = await closeBrowserGracefully(options.port, report.browserId);
      } catch (error) {
        report.errors.push(`browser close: ${String(error?.message ?? error).slice(0, 200)}`);
      }
    }
    await fs.mkdir(path.dirname(reportPath), { recursive: true });
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2), "utf8");
    console.log(JSON.stringify({
      mode: "zcode-poc",
      pass2CdpEndpoint: report.pass2CdpEndpoint,
      pass3MainRenderer: report.pass3MainRenderer,
      pass4RuntimeEvaluate: report.pass4RuntimeEvaluate,
      pass5RemoveTheme: report.pass5RemoveTheme,
      browserClosed: report.browserClosed,
      errors: report.errors,
    }));
    if (!(report.pass2CdpEndpoint && report.pass3MainRenderer &&
      report.pass4RuntimeEvaluate && report.pass5RemoveTheme)) {
      process.exitCode = 2;
    }
  }
}

// --- ZCode DOM inventory -----------------------------------------------------
// Read-only. Collects the shapes a DOM map needs: an element histogram, stable
// attribute names with pattern-safe sample values, class-fragment names, a bounded
// hierarchy summary, and presence counts for the surfaces that must never be
// themed. Page text, input values, titles and user paths are never read, and the
// URL is reduced to a protocol-plus-basename family so no install path leaks into
// the fingerprint.

const INVENTORY_CANDIDATE_SELECTORS = {
  html: "html",
  body: "body",
  rootId: "#root",
  roleMain: "[role=\"main\"]",
  roleNavigation: "[role=\"navigation\"]",
  roleDialog: "[role=\"dialog\"]",
  roleMenu: "[role=\"menu\"]",
  roleListbox: "[role=\"listbox\"]",
  aside: "aside",
  header: "header",
  footer: "footer",
  nav: "nav",
  main: "main",
  section: "section",
  textarea: "textarea",
  input: "input",
  button: "button",
  contenteditable: "[contenteditable=\"true\"]",
  monaco: ".monaco-editor",
  xterm: ".xterm",
  iframe: "iframe",
  canvas: "canvas",
  svg: "svg",
  video: "video",
  img: "img",
  testid: "[data-testid]",
};

function urlFamilyOf(value) {
  try {
    const url = new URL(String(value ?? ""));
    const base = url.pathname.split("/").filter(Boolean).pop() ?? "";
    return `${url.protocol}//…/${base}`;
  } catch {
    return "";
  }
}

// Attribute values are read for selector material, so names that commonly carry
// user or session state are refused outright — a real field inventory sampled
// `data-model-current-value`, which held the session's selected model, and
// `data-provider`, which held the account plan. The NAME is still reported; only
// the value is withheld.
export const ZCODE_ATTRIBUTE_VALUE_DENY_SOURCE =
  '(^|[-_])(value|model|label|title|session|user|account|email|path|url|href|src|content|prompt|message|query|text|name|draft|key|lexical|editor|greeting|logo|bridge|placeholder|provider)([-_]|$)|[-_]ids?$';
// Second, blunt gate: a long value is never sampled, whatever its name.
export const ZCODE_MAX_SAMPLED_VALUE_LENGTH = 48;
// Third, blunt gate: at most this many distinct values are kept per attribute
// name, so a full sample list is a truncation and "the value is not in the list"
// is no proof that the value is absent from the renderer.
export const ZCODE_MAX_SAMPLED_VALUES = 8;

export function zcodeInventoryExpression(maxElements) {
  return `(() => {
  const MAX_ELEMENTS = ${JSON.stringify(maxElements)};
  const CANDIDATES = ${JSON.stringify(INVENTORY_CANDIDATE_SELECTORS)};
  const SAFE_ID = /^[A-Za-z][-A-Za-z0-9_]{0,63}$/;
  const SAFE_VALUE = /^[A-Za-z0-9_.:\\/-]{1,64}$/;
  const VALUE_DENY_SOURCE = ${JSON.stringify(ZCODE_ATTRIBUTE_VALUE_DENY_SOURCE)};
  const VALUE_DENY = new RegExp(VALUE_DENY_SOURCE, "i");
  const MAX_SAMPLED_VALUE_LENGTH = ${JSON.stringify(ZCODE_MAX_SAMPLED_VALUE_LENGTH)};
  const MAX_SAMPLED_VALUES = ${JSON.stringify(ZCODE_MAX_SAMPLED_VALUES)};
  const count = (target, key) => { target[key] = (target[key] || 0) + 1; };
  const rank = (source, limit) => Object.fromEntries(
    Object.entries(source).sort((left, right) => right[1] - left[1]).slice(0, limit));
  const all = Array.from(document.querySelectorAll("*"));
  const scanned = all.slice(0, MAX_ELEMENTS);
  const tags = {}; const attributeNames = {}; const attributeSamples = {};
  const classFragments = {}; const utilityTokens = {}; const ids = {};
  let scrollContainers = 0;
  let deepest = 0;
  for (const element of scanned) {
    count(tags, element.tagName.toLowerCase());
    for (const attribute of element.attributes) {
      const name = attribute.name.toLowerCase();
      if (!(name.startsWith("data-") || name.startsWith("aria-") || name === "role" || name === "id")) continue;
      count(attributeNames, name);
      const value = String(element.getAttribute(attribute.name) == null ? "" : element.getAttribute(attribute.name));
      if (SAFE_VALUE.test(value) && value.length <= MAX_SAMPLED_VALUE_LENGTH &&
        !VALUE_DENY.test(name)) {
        const samples = attributeSamples[name] || (attributeSamples[name] = []);
        if (samples.length < MAX_SAMPLED_VALUES && samples.indexOf(value) === -1) samples.push(value);
      }
    }
    if (element.id && SAFE_ID.test(element.id)) count(ids, element.id);
    for (const token of element.classList) {
      const fragment = /^_([A-Za-z][A-Za-z0-9]{2,40})_/.exec(token);
      if (fragment) { count(classFragments, fragment[1]); continue; }
      if (/^[a-z][a-z0-9-]{2,40}$/.test(token)) count(utilityTokens, token);
    }
    let depth = 0;
    for (let node = element; node && node.parentElement; node = node.parentElement) depth += 1;
    if (depth > deepest) deepest = depth;
    const style = window.getComputedStyle(element);
    if (style && (style.overflowY === "auto" || style.overflowY === "scroll")) scrollContainers += 1;
  }
  const presence = {};
  for (const key of Object.keys(CANDIDATES)) {
    try { presence[key] = document.querySelectorAll(CANDIDATES[key]).length; }
    catch (error) { presence[key] = -1; }
  }
  return {
    readyState: document.readyState,
    protocol: String(location.protocol || ""),
    totalElements: all.length,
    scannedElements: scanned.length,
    deepestNesting: deepest,
    scrollContainers: scrollContainers,
    tags: rank(tags, 80),
    attributeNames: rank(attributeNames, 80),
    attributeSamples: attributeSamples,
    classFragments: rank(classFragments, 200),
    utilityTokens: rank(utilityTokens, 120),
    ids: rank(ids, 40),
    presence: presence
  };
})()`;
}

export function zcodeHierarchyExpression(maxDepth, maxChildren) {
  return `(() => {
  const MAX_DEPTH = ${JSON.stringify(maxDepth)};
  const MAX_CHILDREN = ${JSON.stringify(maxChildren)};
  const SAFE_ID = /^[A-Za-z][-A-Za-z0-9_]{0,63}$/;
  const SAFE_VALUE = /^[A-Za-z0-9_.:\\/-]{1,64}$/;
  const VALUE_DENY_SOURCE = ${JSON.stringify(ZCODE_ATTRIBUTE_VALUE_DENY_SOURCE)};
  const VALUE_DENY = new RegExp(VALUE_DENY_SOURCE, "i");
  const MAX_SAMPLED_VALUE_LENGTH = ${JSON.stringify(ZCODE_MAX_SAMPLED_VALUE_LENGTH)};
  const describe = (element, depth) => {
    const node = { tag: element.tagName.toLowerCase(), children: [] };
    const markers = [];
    if (element.id && SAFE_ID.test(element.id)) markers.push("#" + element.id);
    for (const attribute of element.attributes) {
      const name = attribute.name.toLowerCase();
      const value = String(element.getAttribute(attribute.name) == null ? "" : element.getAttribute(attribute.name));
      const sampleable = SAFE_VALUE.test(value) && value.length <= MAX_SAMPLED_VALUE_LENGTH &&
        !VALUE_DENY.test(name);
      if (name === "role" && sampleable) markers.push("[role=" + value + "]");
      else if (name === "data-testid" && sampleable) markers.push("[data-testid=" + value + "]");
      else if (name.startsWith("data-")) markers.push("[" + name + "]");
    }
    for (const token of element.classList) {
      const fragment = /^_([A-Za-z][A-Za-z0-9]{2,40})_/.exec(token);
      if (fragment) markers.push("." + fragment[1]);
    }
    if (markers.length) node.markers = markers.slice(0, 8);
    node.childElementCount = element.childElementCount;
    if (depth < MAX_DEPTH) {
      for (const child of Array.from(element.children).slice(0, MAX_CHILDREN)) {
        node.children.push(describe(child, depth + 1));
      }
    }
    return node;
  };
  return document.documentElement ? describe(document.documentElement, 0) : null;
})()`;
}

export function zcodeReadinessProbeExpression() {
  // One readiness sample. Only body descendants count toward the workspace
  // threshold: the boot shell carries hundreds of <link> tags in <head>, which is
  // exactly what made an earlier field run mistake the loading screen for a
  // workspace. Startup markers and workspace evidence are collected alongside.
  return `(() => {
  const body = document.body;
  const bodyElements = body ? body.querySelectorAll("*") : [];
  const workspaceEvidence = {
    roleMain: document.querySelectorAll('[role="main"]').length,
    roleNavigation: document.querySelectorAll('[role="navigation"]').length,
    main: document.querySelectorAll("main").length,
    nav: document.querySelectorAll("nav").length,
    button: document.querySelectorAll("button").length,
    input: document.querySelectorAll("input").length,
    textarea: document.querySelectorAll("textarea").length,
    contenteditable: document.querySelectorAll('[contenteditable="true"]').length,
    monaco: document.querySelectorAll(".monaco-editor").length,
    xterm: document.querySelectorAll(".xterm").length
  };
  const startupMarkers = [];
  if (document.querySelector('[data-testid="root-startup-loading"]')) {
    startupMarkers.push("data-testid=root-startup-loading");
  }
  if (document.querySelector('[aria-busy="true"]')) {
    startupMarkers.push("aria-busy=true");
  }
  for (const node of document.querySelectorAll("[data-testid]")) {
    const testid = String(node.getAttribute("data-testid") || "");
    if (/(^|-)(startup|boot|loading)(-|$)/i.test(testid)) {
      const marker = "data-testid=" + testid;
      if (startupMarkers.indexOf(marker) === -1) startupMarkers.push(marker);
    }
  }
  for (const node of document.querySelectorAll("[data-phase]")) {
    const phase = String(node.getAttribute("data-phase") || "");
    if (/preparing|loading|initializ|boot|startup/i.test(phase)) {
      startupMarkers.push("data-phase=" + phase);
    }
  }
  const suspiciousTestids = [];
  for (const node of document.querySelectorAll("[data-testid]")) {
    const testid = String(node.getAttribute("data-testid") || "");
    if (/login|sign-?in|onboard|welcome|updat/i.test(testid)) suspiciousTestids.push(testid);
  }
  return {
    readyState: document.readyState,
    totalElementCount: document.querySelectorAll("*").length,
    bodyElementCount: bodyElements.length,
    headElementCount: document.head ? document.head.querySelectorAll("*").length : 0,
    startupMarkers: startupMarkers,
    workspaceEvidence: workspaceEvidence,
    suspiciousTestids: suspiciousTestids.slice(0, 12)
  };
})()`;
}

/**
 * Decides whether a sample history shows a rendered workspace. It fails closed:
 * a startup marker on the newest sample, a body below the threshold, no workspace
 * evidence at all, or a body count that has not held steady for the required
 * number of consecutive marker-free samples each keep it not ready.
 */
/**
 * Terminal summary for one inventory run, derived from the report so the numbers
 * printed can never drift from the numbers written to the file: an earlier
 * revision renamed the readiness fields but kept printing a stale
 * `elementCount: 0` while the file held body 796 / total 1087.
 */
export function zcodeInventorySummary(report) {
  const readiness = report?.readiness && typeof report.readiness === "object" ? report.readiness : {};
  return {
    mode: "zcode-dom-inventory",
    ready: Boolean(readiness.ready),
    bodyElementCount: Number(readiness.bodyElementCount ?? 0),
    totalElementCount: Number(readiness.totalElementCount ?? 0),
    workspaceEvidenceTotal: Number(readiness.workspaceEvidenceTotal ?? 0),
    settledSamples: Number(readiness.settledSamples ?? 0),
    startupMarkers: Array.isArray(readiness.startupMarkers) ? readiness.startupMarkers : [],
    browserClosed: Boolean(report?.browserClosed),
    errors: Array.isArray(report?.errors) ? report.errors : [],
  };
}

export function evaluateWorkspaceReadiness(samples, options = {}) {
  const threshold = Math.max(1, Number(options.minBodyElements ?? 100));
  const requiredStable = Math.max(1, Number(options.requiredStableSamples ?? 2));
  const history = Array.isArray(samples) ? samples : [];
  if (history.length === 0) {
    return {
      ready: false,
      reasons: ["no-samples"],
      bodyElementCount: 0,
      totalElementCount: 0,
      workspaceEvidenceTotal: 0,
      startupMarkers: [],
      settledSamples: 0,
      lastSample: null,
    };
  }
  const last = history[history.length - 1] ?? {};
  const reasons = [];
  const startupMarkers = Array.isArray(last.startupMarkers) ? last.startupMarkers : [];
  const bodyElementCount = Number(last.bodyElementCount ?? 0);
  const evidence = last.workspaceEvidence && typeof last.workspaceEvidence === "object"
    ? last.workspaceEvidence : {};
  const workspaceEvidenceTotal = Object.values(evidence)
    .reduce((total, value) => total + (Number(value) || 0), 0);
  if (startupMarkers.length > 0) reasons.push(`startup-markers:${startupMarkers.join("|")}`);
  if (bodyElementCount < threshold) {
    reasons.push(`body-elements:${bodyElementCount}<${threshold}`);
  }
  if (workspaceEvidenceTotal < 1) reasons.push("no-workspace-evidence");

  let settledSamples = 0;
  for (let index = history.length - 1; index >= 0; index -= 1) {
    const sample = history[index] ?? {};
    const sampleMarkers = Array.isArray(sample.startupMarkers) ? sample.startupMarkers.length : 0;
    if (sampleMarkers > 0) break;
    if (Number(sample.bodyElementCount ?? 0) < threshold) break;
    if (index === history.length - 1) {
      settledSamples = 1;
      continue;
    }
    if (Number(history[index + 1]?.bodyElementCount ?? 0) === Number(sample.bodyElementCount ?? 0)) {
      settledSamples += 1;
    } else {
      break;
    }
  }
  if (settledSamples < requiredStable) {
    reasons.push(`unstable:${settledSamples}<${requiredStable}`);
  }
  return {
    ready: reasons.length === 0,
    reasons,
    bodyElementCount,
    totalElementCount: Number(last.totalElementCount ?? 0),
    workspaceEvidenceTotal,
    startupMarkers,
    settledSamples,
    lastSample: last,
  };
}

async function waitForWorkspaceReadiness(session, options) {
  // Readiness is a body count above the threshold, real workspace evidence, no
  // startup markers, and a steady count — never a raw element total, which the
  // boot shell can inflate with hundreds of <head> links.
  const deadline = Date.now() + Math.max(1000, options.timeoutMs);
  const startedAt = Date.now();
  const history = [];
  let decision = evaluateWorkspaceReadiness([], {});
  while (Date.now() < deadline) {
    let sample = null;
    try {
      sample = await session.evaluate(zcodeReadinessProbeExpression());
    } catch {
      sample = null;
    }
    if (sample) {
      history.push(sample);
      decision = evaluateWorkspaceReadiness(history, {
        minBodyElements: options.minElements,
        requiredStableSamples: options.requiredStableSamples,
      });
      if (decision.ready) break;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return {
    ...decision,
    waitedMs: Date.now() - startedAt,
    totalSamples: history.length,
    samples: history.slice(-24).map((entry) => Number(entry.bodyElementCount ?? 0)),
  };
}
async function runZCodeDomInventory(options) {
  const reportPath = path.resolve(options.report);
  const report = {
    mode: "zcode-dom-inventory",
    port: options.port,
    browserId: null,
    zcodeVersion: String(options.zcodeVersion ?? ""),
    target: {},
    readiness: {},
    surfaceDiagnostics: {},
    browserClosed: false,
    fingerprint: null,
    inventory: null,
    hierarchy: null,
    errors: [],
  };
  let session = null;
  try {
    const version = await fetchCdpJson(options.port, "/json/version");
    const browserId = browserIdFromVersion(version, options.port);
    if (options.browserId && browserId !== options.browserId) {
      throw new CdpIdentityMismatchError(
        `CDP browser identity mismatch: expected ${options.browserId}, found ${browserId}`,
      );
    }
    report.browserId = browserId;
    const listed = await fetchCdpJson(options.port, "/json/list");
    const targets = Array.isArray(listed) ? listed : [];
    const selected = selectZCodeMainTarget(targets, (line) => console.log(`[TARGET] ${line}`));
    const scored = scoreZCodeTarget(selected);
    report.target = {
      id: String(selected.id ?? ""),
      type: String(selected.type ?? ""),
      urlFamily: urlFamilyOf(selected.url),
      score: scored.score,
      reasons: scored.reasons,
    };
    session = new CdpSession(selected, options.port);
    await session.open();
    report.readiness = await waitForWorkspaceReadiness(session, options);
    console.log(`[READINESS] body=${report.readiness.bodyElementCount} ` +
      `total=${report.readiness.totalElementCount} evidence=${report.readiness.workspaceEvidenceTotal} ` +
      `settled=${report.readiness.settledSamples} markers=${report.readiness.startupMarkers.join("|") || "none"}`);
    report.surfaceDiagnostics = {
      suspiciousTestids: Array.isArray(report.readiness.lastSample?.suspiciousTestids)
        ? report.readiness.lastSample.suspiciousTestids : [],
    };
    if (!report.readiness.ready) {
      throw new Error(
        `E11_WORKSPACE_NOT_READY: ${report.readiness.reasons.join("; ")} ` +
        `(body=${report.readiness.bodyElementCount}, total=${report.readiness.totalElementCount}, ` +
        `evidence=${report.readiness.workspaceEvidenceTotal}, ` +
        `markers=${report.readiness.startupMarkers.join("|") || "none"}, ` +
        `waitedMs=${report.readiness.waitedMs})`,
      );
    }
    report.inventory = await session.evaluate(zcodeInventoryExpression(options.maxElements));
    report.hierarchy = await session.evaluate(zcodeHierarchyExpression(10, 10));
    const { digest, features } = zcodeSemanticFingerprint({
      version: report.zcodeVersion,
      selectors: Object.keys(report.inventory.presence)
        .filter((key) => report.inventory.presence[key] > 0),
      rootTags: [String(report.hierarchy?.tag ?? "")],
      stableAttributes: Object.keys(report.inventory.attributeNames)
        .filter((name) => name.startsWith("data-") || name === "role"),
      urlFamily: report.target.urlFamily,
    });
    report.fingerprint = { digest, features };
    console.log(`[INVENTORY] ${report.inventory.totalElements} elements, ` +
      `${Object.keys(report.inventory.attributeNames).length} attribute names, ` +
      `${Object.keys(report.inventory.classFragments).length} class fragments, ` +
      `fingerprint ${digest}`);
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.closeBrowser) {
      // Same graceful shutdown the Phase 1 probe uses. Without it the app keeps
      // running with the debug port bound, which the caller reports as exit 4.
      try {
        report.browserClosed = await closeBrowserGracefully(options.port, report.browserId);
      } catch (error) {
        report.errors.push(`browser close: ${String(error?.message ?? error).slice(0, 200)}`);
      }
    }
    await fs.mkdir(path.dirname(reportPath), { recursive: true });
    await fs.writeFile(reportPath, JSON.stringify(report, null, 2), "utf8");
    if (report.errors.length > 0) process.exitCode = 2;
    console.log(JSON.stringify(zcodeInventorySummary(report)));
  }
}

// --- ZCode theme application -------------------------------------------------
// Product-grade theme flow: read the profile, probe the live renderer, let the
// compatibility probe decide full/safe/deny, build the payload from the part
// contract, and keep it alive across renderer reloads with the lifecycle state
// machine. Every report quotes measured numbers only — no page text, no URLs
// beyond the sanitized family, no user content.

function zcodePresenceProbeExpression(profile, version = "") {
  const selectors = [...new Set([
    ...(profile.requiredSelectors ?? []),
    ...(profile.safeModeSelectors ?? []),
  ])].map((selector) => JSON.stringify(selector));
  return `(() => {
  const selectors = [${selectors.join(",")}];
  const present = [];
  for (const selector of selectors) {
    try { if (document.querySelector(selector)) present.push(selector); } catch (invalid) {}
  }
  return {
    version: ${JSON.stringify(String(version ?? ""))},
    selectors: present,
    rootTags: [document.documentElement ? document.documentElement.tagName.toLowerCase() : ""],
    readyState: document.readyState,
  };
})()`;
}

function zcodeStandaloneRemoveExpression() {
  // Works with or without the runtime API: after a renderer reload the API is
  // gone but the fixed IDs may survive only if the document survived, which a
  // reload never does. data-ds-part values are namespaced (zcode-*), so a
  // standalone sweep can restore them without a snapshot.
  return `(() => {
  var removed = 0;
  var nodes = document.querySelectorAll('[id^="zcode-dream-skin-"]');
  for (var i = nodes.length - 1; i >= 0; i -= 1) { nodes[i].remove(); removed += 1; }
  var tagged = document.querySelectorAll('[data-ds-part^="zcode-"]');
  for (var j = tagged.length - 1; j >= 0; j -= 1) tagged[j].removeAttribute("data-ds-part");
  if (document.documentElement) document.documentElement.removeAttribute("data-zcode-dream-skin");
  return {
    removedNodes: removed,
    remainingSkinNodes: document.querySelectorAll('[id^="zcode-dream-skin-"]').length,
    remainingTagged: document.querySelectorAll('[data-ds-part^="zcode-"]').length,
    readyState: document.readyState
  };
})()`;
}

function zcodeStandaloneVerifyExpression() {
  return `(() => {
  var count = function (id) { return document.querySelectorAll("#" + id).length; };
  var background = document.getElementById(${JSON.stringify(ZCODE_SKIN_IDS.background)});
  var overlay = document.getElementById(${JSON.stringify(ZCODE_SKIN_IDS.overlay)});
  return {
    styleCount: count(${JSON.stringify(ZCODE_SKIN_IDS.style)}),
    backgroundCount: count(${JSON.stringify(ZCODE_SKIN_IDS.background)}),
    overlayCount: count(${JSON.stringify(ZCODE_SKIN_IDS.overlay)}),
    taggedParts: document.querySelectorAll('[data-ds-part^="zcode-"]').length,
    backgroundPointerEvents: background ? String(background.style.getPropertyValue("pointer-events") || "") : "",
    overlayPointerEvents: overlay ? String(overlay.style.getPropertyValue("pointer-events") || "") : "",
    mode: document.documentElement ? (document.documentElement.getAttribute("data-zcode-dream-skin") || "") : "",
    readyState: document.readyState
  };
})()`;
}

// The renderer payload publishes this runtime id. It is the handshake proving the
// API found in the page is this product's runtime rather than a leftover from an
// older injection, so it is checked before any apply call is attempted.
const ZCODE_RENDERER_RUNTIME = "zcode-dream-skin-renderer/1";

function zcodeInvokeApplyExpression() {
  // The API handshake is returned as data rather than thrown: the failure stage
  // then comes from the returned shape instead of from CDP's error text, which
  // is free to change wording between builds.
  return `(() => {
  var api = window.__ZCODE_DREAM_SKIN__;
  if (!api || api.runtime !== ${JSON.stringify(ZCODE_RENDERER_RUNTIME)} || typeof api.apply !== "function")
    return { apiMissing: true, runtime: api && typeof api.runtime === "string" ? api.runtime : "" };
  return api.apply();
})()`;
}

const zcodeErrorSummary = (error) => String(error?.message ?? error).replace(/\s+/g, " ").slice(0, 200);

/**
 * The revision the live renderer reports about itself, read as data rather than
 * thrown. It is kept out of the verification object on purpose: the theme and native
 * rulers enumerate that object's keys, while this value is a cross-check the caller
 * compares against what the state records and what was asked for.
 */
export function zcodeRuntimeRevisionExpression() {
  return `(() => {
  var api = window.__ZCODE_DREAM_SKIN__;
  if (!api || api.runtime !== ${JSON.stringify(ZCODE_RENDERER_RUNTIME)} || typeof api.verify !== "function") return "";
  try {
    var state = api.verify() || {};
    return typeof state.revision === "string" ? state.revision : "";
  } catch (error) { return ""; }
})()`;
}

// The three fixed nodes must each exist exactly once, the decoration layers must
// never intercept input, the document must carry the mode that was asked for, and
// the registered surfaces must be tagged (full) or untouched (safe).
export function zcodeThemeVerificationProblems(verify, mode) {
  const problems = [];
  const observed = verify ?? {};
  for (const id of ["style", "background", "overlay"]) {
    const count = observed[`${id}Count`];
    if (count !== 1) problems.push(`${id}Count=${count} (expected exactly 1)`);
  }
  for (const layer of ["background", "overlay"]) {
    const value = String(observed[`${layer}PointerEvents`] ?? "");
    if (value !== "none") problems.push(`${layer} pointer-events=${value || "(unset)"} (expected none)`);
  }
  if (String(observed.mode ?? "") !== mode) {
    problems.push(`document mode=${observed.mode || "(unset)"} (expected ${mode})`);
  }
  if (mode === "full" && !(Number(observed.taggedParts) > 0)) {
    problems.push("full mode tagged no registered surface");
  }
  if (mode === "safe" && Number(observed.taggedParts) !== 0) {
    problems.push(`safe mode tagged ${observed.taggedParts} full-theme part(s)`);
  }
  return problems;
}

/**
 * The native (no-skin) contract, kept deliberately separate from the theme one:
 * "default appearance" is a managed session that is paused with a pending resume
 * reference, so a missing renderer API is legal and any leftover skin node is a
 * defect. Reusing the theme ruler would demand 1/1/1 and report a clean native
 * window as broken; loosening it would weaken the theme gate.
 */
export function zcodeNativeVerificationProblems(observed) {
  const problems = [];
  const value = observed ?? {};
  for (const id of ["style", "background", "overlay"]) {
    const count = Number(value[`${id}Count`]);
    if (!Number.isInteger(count) || count !== 0) {
      problems.push(`${id}Count=${value[`${id}Count`]} (expected 0 for the native appearance)`);
    }
  }
  const tagged = Number(value.taggedParts);
  if (!Number.isInteger(tagged) || tagged !== 0) {
    problems.push(`taggedParts=${value.taggedParts} (expected 0 for the native appearance)`);
  }
  if (String(value.mode ?? "") !== "") {
    problems.push(`document mode=${value.mode} (expected no dream-skin attribute while native)`);
  }
  return problems;
}

/**
 * Register the real renderer payload, then drive and verify its apply API.
 *
 * Evaluating the payload only installs `window.__ZCODE_DREAM_SKIN__` and returns
 * nothing, so a caller that reads `applied` off that evaluate result reports
 * success over an untouched document. Registration, the explicit apply call and
 * the independent DOM verification all happen here, and the one-shot apply and
 * every watcher re-injection share this path so the two cannot drift apart.
 *
 * Throws `E09_RUNTIME_EVALUATE_FAILED` with `failureStage` set to register, apply
 * or verify. The pause lock is never cleared to make an apply succeed.
 */
export async function registerAndApplyZCodeTheme(session, payload, expectedMode = "full") {
  if (!session || typeof session.evaluate !== "function") {
    throw new Error("E09_RUNTIME_EVALUATE_FAILED: registerAndApplyZCodeTheme requires a session");
  }
  if (!ZCODE_COMPATIBILITY_MODES.includes(expectedMode)) {
    throw new Error(`E09_RUNTIME_EVALUATE_FAILED: unknown expected mode ${expectedMode}`);
  }
  const failure = (failureStage, detail) => {
    const error = new Error(`E09_RUNTIME_EVALUATE_FAILED: ${detail}`);
    error.failureStage = failureStage;
    return error;
  };

  const evaluate = async (expression, failureStage, detail) => {
    try {
      return await session.evaluate(expression);
    } catch (error) {
      throw failure(failureStage, `${detail}: ${zcodeErrorSummary(error)}`);
    }
  };

  await evaluate(payload, "register", "the renderer payload could not be evaluated");

  // Deny ships nothing: the API is registered so pause and remove keep working,
  // but the apply call is never entered.
  if (expectedMode === "deny") {
    return {
      applyResult: { applied: false, mode: "deny" },
      verify: await evaluate(zcodeStandaloneVerifyExpression(), "verify", "the standalone verification could not run"),
    };
  }

  const applyResult = await evaluate(zcodeInvokeApplyExpression(), "apply", "the renderer refused the apply call");
  if (!applyResult || typeof applyResult !== "object") {
    // The payload installs the API and returns nothing, so an apply call that
    // answers with no object at all means the registration never took.
    throw failure(
      "register",
      `the payload did not register the renderer API (result=${applyResult === undefined ? "undefined" : typeof applyResult})`,
    );
  }
  if (applyResult.apiMissing === true) {
    throw failure("register", `the payload did not register the renderer API (runtime=${applyResult.runtime || "(none)"})`);
  }
  if (applyResult.applied !== true) {
    // The observed fields are quoted so a refusal is diagnosable from the report
    // alone; `reason` comes from the payload, never from user content.
    const observed = `applied=${applyResult.applied === undefined ? "(no result)" : applyResult.applied}` +
      (applyResult.mode ? ` mode=${applyResult.mode}` : "") +
      (applyResult.reason ? ` reason=${zcodeErrorSummary(applyResult.reason)}` : "");
    throw failure("apply", `the renderer did not apply the theme (${observed})`);
  }
  if (applyResult.mode !== expectedMode) {
    throw failure("apply", `the renderer applied mode ${applyResult.mode || "(none)"} while ${expectedMode} was expected`);
  }

  const verify = await evaluate(zcodeStandaloneVerifyExpression(), "verify", "the standalone verification could not run");
  const problems = zcodeThemeVerificationProblems(verify, expectedMode);
  if (problems.length > 0) throw failure("verify", problems.join("; "));
  return { applyResult, verify };
}

/**
 * A user theme sheet, validated with the same policy as the built-in one.
 *
 * The sheet is COMPOSED after the base layer, never substituted for it: a user
 * theme may restyle the registered parts and nothing else, so it can neither drop
 * the base decoration contract nor widen doNotTouch. The load mirrors the Codex
 * path (no symlink, bounded size, stable read) because the file is user-writable.
 */
async function loadZCodeUserCss(userCssPath) {
  if (!userCssPath) return null;
  let handle;
  try {
    handle = await fs.open(userCssPath, fsConstants.O_RDONLY | (fsConstants.O_NOFOLLOW ?? 0));
  } catch (error) {
    if (error.code === "ENOENT") throw new Error("ZCode user CSS does not exist");
    if (error.code === "ELOOP") throw new Error("ZCode user CSS must not be a symbolic link");
    throw error;
  }
  try {
    const before = await handle.stat();
    if (!before.isFile() || before.size < 1 || before.size > MAX_SAFE_CSS_BYTES) {
      throw new Error(`ZCode user CSS must be a non-empty file no larger than ${MAX_SAFE_CSS_BYTES} bytes`);
    }
    const bytes = await handle.readFile();
    const after = await handle.stat();
    if (!sameFileStat(before, after) || bytes.length !== after.size) {
      throw new Error("ZCode user CSS changed while being loaded");
    }
    const { runtimeSource } = decodeAndValidateSafeCss(bytes);
    return { runtimeSource, bytes: after.size };
  } finally {
    await handle.close();
  }
}

/**
 * The theme revision the renderer reports and the state records.
 *
 * It covers every input that changes what the user sees - the composed sheet, the
 * artwork bytes and the framing - so swapping only the background image produces a
 * new revision instead of silently keeping the old one.
 */
export function zcodeThemeRevision({ cssText = "", artDataUrl = null, art = null } = {}) {
  return createHash("sha256")
    .update(String(cssText), "utf8").update("\u0000")
    .update(artDataUrl ?? "", "utf8").update("\u0000")
    .update(JSON.stringify(art ?? null), "utf8")
    .digest("hex")
    .slice(0, 20);
}

async function loadZCodeThemeInputs(options) {
  const profilePath = options.zcodeProfile ?? path.join(root, "assets", "zcode-profile.json");
  const cssPath = options.zcodeCss ?? path.join(root, "assets", "zcode-dream-skin.css");
  const profile = JSON.parse(await fs.readFile(profilePath, "utf8"));
  const baseCss = await fs.readFile(cssPath, "utf8");
  const userCss = await loadZCodeUserCss(options.zcodeUserCss);
  // The base layer stays first: a user sheet can only add to it.
  const cssText = userCss ? `${baseCss}\n${userCss.runtimeSource}` : baseCss;
  let artDataUrl = null;
  if (options.zcodeArt) {
    const imageBytes = await fs.readFile(options.zcodeArt);
    if (imageBytes.length > MAX_ART_BYTES) {
      throw new Error("ZCode theme art exceeds the 10 MiB safety limit");
    }
    const extension = path.extname(options.zcodeArt).toLowerCase();
    const mime = extension === ".jpg" || extension === ".jpeg" ? "image/jpeg"
      : extension === ".webp" ? "image/webp" : extension === ".png" ? "image/png" : null;
    if (!mime) throw new Error(`Unsupported art format: ${extension || "(none)"}`);
    artDataUrl = `data:${mime};base64,${imageBytes.toString("base64")}`;
  }
  let theme = {};
  if (options.zcodeTheme) {
    theme = JSON.parse(await fs.readFile(options.zcodeTheme, "utf8"));
  }
  const rawArt = theme.art ?? { focusX: 50, focusY: 50, zoom: 100, dim: 0.3, blur: 0 };
  // A package accepted by the payload gate carries a 0-1 focus while the renderer needs
  // percent. The source is declared by the caller, never inferred from the magnitude:
  // the private library predates 2.0 and legitimately stores percent already.
  const resolvedArt = resolveZCodeArtForRenderer(rawArt, options.zcodeArtSource);
  const art = resolvedArt.art;
  return { profile, cssText, artDataUrl, art, baseCssBytes: Buffer.byteLength(baseCss), artSourceFormat: resolvedArt.sourceFormat, artConverted: resolvedArt.converted };
}

export async function loadZCodePayload({ profile, cssText, artDataUrl, art, compatibilityMode, cautionEnabled, revision }) {
  const config = buildZCodeRendererConfig({
    profile,
    compatibilityMode,
    cautionEnabled,
    art,
    revision,
  });
  if (config.unmatched.length > 0) {
    throw new Error(`ZCode profile selectors without a part assignment: ${config.unmatched.join(", ")}`);
  }
  const template = await fs.readFile(path.join(root, "assets", "zcode-renderer-inject.js"), "utf8");
  const payload = template
    .replace("__ZCODE_CSS_JSON__", () => JSON.stringify(cssText))
    .replace("__ZCODE_ART_JSON__", () => JSON.stringify(artDataUrl))
    .replace("__ZCODE_CONFIG_JSON__", () => JSON.stringify(config));
  if (/__ZCODE_[A-Z0-9_]+_JSON__/.test(payload)) {
    throw new Error("ZCode payload placeholders were not fully replaced");
  }
  try {
    new Function(payload);
  } catch (error) {
    throw new Error(`ZCode payload failed to parse as JavaScript: ${error.message}`);
  }
  return { payload, config };
}

/**
 * Wait for the ZCode main renderer on an already-verified CDP endpoint.
 *
 * `/json/version` answering proves the browser endpoint is up, not that a page
 * exists: a fresh launch reports an empty `/json/list` until the renderer window
 * is created. Only E07 (nothing usable yet) is retried; ambiguity and every
 * identity error are final, because retrying those would end up on the wrong
 * renderer or on a second ZCode instance.
 */
export async function waitForZCodeMainTarget({
  listTargets,
  selectTarget,
  now = () => Date.now(),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  timeoutMs = 120000,
  intervalMs = 500,
} = {}) {
  if (typeof listTargets !== "function") throw new Error("waitForZCodeMainTarget requires listTargets");
  if (typeof selectTarget !== "function") throw new Error("waitForZCodeMainTarget requires selectTarget");
  if (!Number.isFinite(timeoutMs) || timeoutMs < 0) throw new Error(`Invalid timeoutMs: ${timeoutMs}`);
  if (!Number.isFinite(intervalMs) || intervalMs <= 0) throw new Error(`Invalid intervalMs: ${intervalMs}`);
  const startedAt = now();
  const deadline = startedAt + timeoutMs;
  let attempts = 0;
  let lastTargetCount = 0;
  for (;;) {
    attempts += 1;
    const targets = await listTargets();
    lastTargetCount = Array.isArray(targets) ? targets.length : 0;
    try {
      return { target: selectTarget(targets), attempts, elapsedMs: now() - startedAt };
    } catch (error) {
      if (!String(error?.message ?? error).startsWith("E07_NO_RENDERER_TARGET")) throw error;
    }
    if (now() >= deadline) {
      throw new Error(
        `E07_NO_RENDERER_TARGET: no ZCode main renderer after attempts=${attempts} ` +
        `elapsedMs=${now() - startedAt} targets=${lastTargetCount}`,
      );
    }
    await sleep(Math.min(intervalMs, Math.max(0, deadline - now())));
  }
}

async function connectZCodeTarget(options, log = (line) => console.log(line)) {
  const waited = await waitForZCodeMainTarget({
    listTargets: () => listAppTargets(options.port, options.browserId),
    selectTarget: (targets) => selectZCodeMainTarget(targets, (line) => log(`[TARGET] ${line}`)),
    timeoutMs: options.startupTimeoutMs,
  });
  log(`[TARGET] main renderer after attempts=${waited.attempts} elapsedMs=${waited.elapsedMs}`);
  const session = new CdpSession(waited.target, options.port);
  await session.open();
  return { session, target: waited.target, attempts: waited.attempts, elapsedMs: waited.elapsedMs };
}

async function readZCodeCautionAllowlist(options) {
  if (!options.zcodeCautionFile) return [];
  const list = JSON.parse(await fs.readFile(options.zcodeCautionFile, "utf8"));
  if (!Array.isArray(list)) throw new Error("caution allowlist file must hold a JSON array of selectors");
  return resolveCautionAllowlist(list).accepted;
}

async function runZCodeApply(options) {
  const report = {
    mode: "zcode-apply",
    port: options.port,
    browserId: options.browserId,
    compatibilityMode: null,
    compatibilityReason: "",
    fingerprint: "",
    applied: false,
    failureStage: "",
    revision: "",
    verify: {},
    errors: [],
  };
  let session = null;
  try {
    const { profile, cssText, artDataUrl, art } = await loadZCodeThemeInputs(options);
    const connected = await connectZCodeTarget(options);
    session = connected.session;
    // A renderer that exists is not yet a hydrated workspace: the boot shell has
    // none of the workspace selectors, so a compatibility probe run against it
    // would decide on the wrong DOM and could apply Safe Mode to a healthy build.
    const readiness = await waitForWorkspaceReadiness(session, {
      timeoutMs: options.startupTimeoutMs,
      minElements: options.minElements,
      requiredStableSamples: options.requiredStableSamples,
    });
    report.readiness = {
      ready: readiness.ready,
      reasons: readiness.reasons,
      bodyElementCount: readiness.bodyElementCount,
      totalElementCount: readiness.totalElementCount,
      workspaceEvidenceTotal: readiness.workspaceEvidenceTotal,
      settledSamples: readiness.settledSamples,
      startupMarkers: readiness.startupMarkers,
      waitedMs: readiness.waitedMs,
      totalSamples: readiness.totalSamples,
    };
    console.log(`[READINESS] body=${readiness.bodyElementCount} total=${readiness.totalElementCount} ` +
      `evidence=${readiness.workspaceEvidenceTotal} settled=${readiness.settledSamples} ` +
      `markers=${readiness.startupMarkers.join("|") || "none"}`);
    if (!readiness.ready) {
      throw new Error(
        `E11_WORKSPACE_NOT_READY: ${readiness.reasons.join("; ")} ` +
        `(body=${readiness.bodyElementCount}, total=${readiness.totalElementCount}, ` +
        `evidence=${readiness.workspaceEvidenceTotal}, ` +
        `markers=${readiness.startupMarkers.join("|") || "none"}, waitedMs=${readiness.waitedMs})`,
      );
    }
    const observed = await session.evaluate(zcodePresenceProbeExpression(profile, options.zcodeVersion));
    observed.version = options.zcodeVersion || observed.version || "";
    const compatibility = evaluateCompatibility(profile, observed);
    report.compatibilityMode = compatibility.mode;
    report.compatibilityReason = compatibility.reason;
    report.fingerprint = compatibility.fingerprint;
    if (compatibility.mode === "deny") {
      throw new Error("E11_COMPATIBILITY_DENIED: the renderer does not match the verified profile");
    }
    const caution = { accepted: await readZCodeCautionAllowlist(options) };
    const revision = zcodeThemeRevision({ cssText, artDataUrl, art });
    report.revision = revision;
    const { payload } = await loadZCodePayload({
      profile, cssText, artDataUrl, art,
      compatibilityMode: compatibility.mode,
      cautionEnabled: caution.accepted,
      revision,
    });
    const applied = await registerAndApplyZCodeTheme(session, payload, compatibility.mode);
    report.applied = applied.applyResult.applied;
    report.verify = applied.verify;
    console.log(JSON.stringify(zcodeThemeSummary({ ...report, verify: report.verify })));
  } catch (error) {
    report.failureStage = String(error?.failureStage ?? "");
    report.errors.push(String(error?.message ?? error).slice(0, 400));
    process.exitCode = 2;
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

async function runZCodeRemove(options) {
  const report = {
    mode: "zcode-remove",
    port: options.port,
    browserId: options.browserId,
    removed: false,
    verify: {},
    errors: [],
  };
  let session = null;
  try {
    const connected = await connectZCodeTarget(options);
    session = connected.session;
    const removal = await session.evaluate(zcodeStandaloneRemoveExpression());
    report.removed = Boolean(removal && removal.remainingSkinNodes === 0 && removal.remainingTagged === 0);
    report.removal = removal;
    report.verify = await session.evaluate(zcodeStandaloneVerifyExpression());
    if (!report.removed) throw new Error("E10_REMOVE_THEME_FAILED: skin nodes or part tags survived removal");
    console.log(JSON.stringify(zcodeThemeSummary({ ...report, applied: report.removed })));
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
    process.exitCode = 2;
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

async function runZCodeVerify(options) {
  const expectedAppearance = options.expectAppearance === "native" ? "native" : "theme";
  const report = {
    mode: "zcode-verify",
    port: options.port,
    browserId: options.browserId,
    reportedAt: new Date().toISOString(),
    expectedAppearance,
    rendererRevision: "",
    verify: {},
    screenshots: {},
    errors: [],
  };
  let session = null;
  try {
    const connected = await connectZCodeTarget(options);
    session = connected.session;
    report.verify = await session.evaluate(zcodeStandaloneVerifyExpression());
    // Read-only second look: what the page itself claims it is running. A missing
    // API is legal here (a native window has none) and reports an empty string.
    report.rendererRevision = await session.evaluate(zcodeRuntimeRevisionExpression());
    if (expectedAppearance === "native") {
      // The native contract is enforced here, in one place, rather than being
      // recomputed by every caller from the report's numbers.
      report.nativeProblems = zcodeNativeVerificationProblems(report.verify);
      if (report.nativeProblems.length > 0) {
        throw new Error(`E13_STATE_SCHEMA_INVALID: the native appearance still carries skin nodes: ${report.nativeProblems.join("; ")}`);
      }
    }
    if (options.screenshot) {
      report.screenshots.viewport = await capture(session, options.screenshot);
    }
    console.log(JSON.stringify(zcodeThemeSummary({ ...report, applied: report.verify.styleCount === 1 })));
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
    process.exitCode = 2;
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

function zcodePauseExpression() {
  // Belt and braces: the renderer-level lock survives independent of the watch
  // process, so a reload during a pause can never be re-skinned by a stray
  // injector run. Falls back to a plain sweep when the API is gone.
  return `(() => {
  var api = window.__ZCODE_DREAM_SKIN__;
  if (api && typeof api.pause === "function") return api.pause();
  window.__ZCODE_DREAM_SKIN_DISABLED__ = true;
  var removed = 0;
  var nodes = document.querySelectorAll('[id^="zcode-dream-skin-"]');
  for (var i = nodes.length - 1; i >= 0; i -= 1) { nodes[i].remove(); removed += 1; }
  return { paused: true, removedNodes: removed, viaApi: false };
})()`;
}

function zcodeResumeExpression() {
  return `(() => {
  var api = window.__ZCODE_DREAM_SKIN__;
  if (api && typeof api.resume === "function") return api.resume();
  window.__ZCODE_DREAM_SKIN_DISABLED__ = false;
  return { paused: false, viaApi: false };
})()`;
}

async function runZCodePause(options) {
  const report = { mode: "zcode-pause", port: options.port, browserId: options.browserId, paused: false, errors: [] };
  let session = null;
  try {
    const connected = await connectZCodeTarget(options);
    session = connected.session;
    report.pause = await session.evaluate(zcodePauseExpression());
    report.paused = Boolean(report.pause?.paused);
    if (!report.paused) throw new Error("E10_REMOVE_THEME_FAILED: the renderer refused the pause");
    console.log(JSON.stringify({ mode: report.mode, paused: report.paused }));
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
    process.exitCode = 2;
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

async function runZCodeResume(options) {
  const report = { mode: "zcode-resume", port: options.port, browserId: options.browserId, resumed: false, errors: [] };
  let session = null;
  try {
    const connected = await connectZCodeTarget(options);
    session = connected.session;
    report.resume = await session.evaluate(zcodeResumeExpression());
    report.resumed = report.resume?.paused === false;
    console.log(JSON.stringify({ mode: report.mode, resumed: report.resumed }));
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
    process.exitCode = 2;
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

async function runZCodeReload(options) {
  // Page.reload through CDP: the sanctioned way to simulate a renderer reload
  // without touching the user's session. The lifecycle watch must restore the
  // theme afterwards, unless the renderer is paused.
  const report = { mode: "zcode-reload", port: options.port, browserId: options.browserId, reloaded: false, errors: [] };
  let session = null;
  try {
    const connected = await connectZCodeTarget(options);
    session = connected.session;
    await session.send("Page.reload", { ignoreCache: false });
    await new Promise((resolve) => setTimeout(resolve, 1500));
    report.reloaded = true;
    console.log(JSON.stringify({ mode: report.mode, reloaded: report.reloaded }));
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
    process.exitCode = 2;
  } finally {
    if (session) { try { session.close(); } catch {} }
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

async function runZCodeClose(options) {
  // Graceful Browser.close of a managed session: ZCode shuts down normally and
  // the caller waits for the process tree to drain. No process is ever killed.
  const report = { mode: "zcode-close", port: options.port, browserId: options.browserId, browserClosed: false, errors: [] };
  try {
    report.browserClosed = await closeBrowserGracefully(options.port, options.browserId);
    console.log(JSON.stringify({ mode: report.mode, browserClosed: report.browserClosed }));
  } catch (error) {
    report.errors.push(String(error?.message ?? error).slice(0, 400));
    process.exitCode = 2;
  } finally {
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

async function readZCodeWatchState(stateFile) {  try {
    const state = JSON.parse(await fs.readFile(stateFile, "utf8"));
    return {
      paused: Boolean(state.paused),
      stopped: Boolean(state.stopped),
    };
  } catch {
    return { paused: false, stopped: false };
  }
}

async function runZCodeWatch(options) {
  const report = {
    mode: "zcode-watch",
    port: options.port,
    browserId: options.browserId,
    transitions: [],
    reinjections: 0,
    backoffMaxMs: 10000,
    errors: [],
  };
  const { profile, cssText, artDataUrl, art } = await loadZCodeThemeInputs(options);
  const caution = { accepted: await readZCodeCautionAllowlist(options) };
  const revision = zcodeThemeRevision({ cssText, artDataUrl, art });
  const { payload } = await loadZCodePayload({
    profile, cssText, artDataUrl, art,
    compatibilityMode: "full",
    cautionEnabled: caution.accepted,
    revision,
  });
  // The watcher owns exactly one live CDP connection at a time. Releasing it is
  // not optional: an open socket keeps the Node event loop alive, so a watcher
  // that never closes it can never honour the stop flag, and a rediscovery that
  // never closes the previous one accumulates sockets in a long-lived watcher.
  let liveConnection = null;
  const releaseLiveConnection = () => {
    const connection = liveConnection;
    liveConnection = null;
    if (connection?.session && !connection.session.closed) {
      try { connection.session.close(); } catch { /* the stop path must not throw */ }
    }
  };
  // Compatibility is re-checked on every discovery: an upgraded renderer must
  // never receive the full theme again.
  const discover = async () => {
    releaseLiveConnection();
    const connected = await connectZCodeTarget(options, () => {});
    const observed = await connected.session.evaluate(zcodePresenceProbeExpression(profile, options.zcodeVersion));
    observed.version = options.zcodeVersion || observed.version || "";
    const compatibility = evaluateCompatibility(profile, observed);
    if (compatibility.mode !== "full") {
      connected.session.close();
      throw new Error(`compatibility downgraded to ${compatibility.mode}: ${compatibility.reason}`);
    }
    liveConnection = connected;
    return connected;
  };
  const inject = async (connected) => {
    // The same real register + apply + verify path as a one-shot apply: a reload
    // is only re-injected when the document actually verifies.
    await registerAndApplyZCodeTheme(connected.session, payload, "full");
    report.reinjections += 1;
  };
  const check = async (connected) => {
    if (!connected.session || connected.session.closed) return false;
    const verification = await connected.session.evaluate(zcodeStandaloneVerifyExpression());
    return Boolean(verification && verification.styleCount === 1 && verification.backgroundCount === 1);
  };
  const remove = async (connected) => {
    if (connected.session && !connected.session.closed) {
      await connected.session.evaluate(zcodeStandaloneRemoveExpression());
    }
  };
  const lifecycle = createZCodeThemeLifecycle({
    discover,
    inject,
    remove,
    check,
    isPaused: async () => (await readZCodeWatchState(options.zcodeStateFile)).paused,
    onState: (state) => {
      if (report.transitions.length < 500) {
        report.transitions.push({ state, at: new Date().toISOString() });
      }
      console.log(`[LIFECYCLE] ${state}`);
    },
    onError: (error) => console.log(`[LIFECYCLE] error: ${String(error?.message ?? error).slice(0, 200)}`),
    activePollMs: 2000,
  });
  let lastStopped = false;
  lifecycle.start();
  try {
    while (lifecycle.running) {
      const state = await readZCodeWatchState(options.zcodeStateFile);
      if (state.stopped && !lastStopped) {
        console.log("[LIFECYCLE] stop requested");
        break;
      }
      if (state.paused && !lifecycle.paused && lifecycle.state === "active") {
        await lifecycle.pause();
        console.log("[LIFECYCLE] paused by state file");
      }
      if (!state.paused && lifecycle.paused) {
        lifecycle.resume();
        // start() resolves only when the loop ends, so it must not be awaited here:
        // awaiting it would block this state-file poll and the watcher would stop
        // reacting to pause, resume and stop.
        lifecycle.start().catch((error) => {
          console.log(`[LIFECYCLE] error: ${String(error?.message ?? error).slice(0, 200)}`);
        });
        console.log("[LIFECYCLE] resumed by state file");
      }
      lastStopped = state.stopped;
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  } finally {
    await lifecycle.stop();
    // Releasing the session is what lets the process exit: an open CDP socket keeps
    // the Node event loop alive, so without it the stop flag is logged and then
    // ignored, and the product has to force-stop the watcher it owns.
    releaseLiveConnection();
    if (options.report) {
      await fs.mkdir(path.dirname(options.report), { recursive: true });
      await fs.writeFile(options.report, JSON.stringify(report, null, 2), "utf8");
    }
  }
}

if (path.resolve(process.argv[1] || "") === path.resolve(scriptPath)) {
  const options = parseArgs(process.argv.slice(2));
  if (options.mode === "self-test") {
  const valid = validatedDebuggerUrl({ webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/page/test` }, options.port);
  const browserId = browserIdFromVersion({
    webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/browser/test-browser`,
  }, options.port);
  const invalid = [
    "ws://example.com/devtools/page/test",
    `ws://127.0.0.1:${options.port + 1}/devtools/page/test`,
    `wss://127.0.0.1:${options.port}/devtools/page/test`,
    `ws://user@127.0.0.1:${options.port}/devtools/page/test`,
    `ws://127.0.0.1:${options.port}/unexpected/test`,
    `ws://127.0.0.1:${options.port}/devtools/page/test?query=1`,
  ];
  for (const value of invalid) {
    let rejected = false;
    try { validatedDebuggerUrl({ webSocketDebuggerUrl: value }, options.port); } catch { rejected = true; }
    if (!rejected) throw new Error(`CDP URL validation accepted an unsafe URL: ${value}`);
  }
  const invalidBrowserUrls = [
    `ws://127.0.0.1:${options.port}/devtools/page/not-a-browser`,
    `ws://127.0.0.1:${options.port}/devtools/browser/bad%20id`,
    `ws://127.0.0.1:${options.port}/devtools/browser/test?query=1`,
  ];
  for (const value of invalidBrowserUrls) {
    let rejected = false;
    try { browserIdFromVersion({ webSocketDebuggerUrl: value }, options.port); } catch { rejected = true; }
    if (!rejected) throw new Error(`Browser identity validation accepted an unsafe URL: ${value}`);
  }
  const validPageTarget = {
    id: "page-test",
    type: "page",
    url: "app://codex/",
    webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/page/page-test`,
  };
  const invalidPageTargets = [
    { ...validPageTarget, webSocketDebuggerUrl: `ws://127.0.0.1:${options.port}/devtools/browser/page-test` },
    { ...validPageTarget, id: "other-page" },
    { ...validPageTarget, id: 123 },
    { ...validPageTarget, type: "other" },
  ];
  if (!valid || browserId !== "test-browser" || !isValidCdpPageTarget(validPageTarget, options.port) ||
      invalidPageTargets.some((item) => isValidCdpPageTarget(item, options.port))) {
    throw new Error("CDP URL and target validation self-test failed");
  }
  const validMessage = parseCdpMessage('{"id":7,"result":{"ok":true}}');
  const invalidMessages = ["{not-json", "null", '"text"', "42", "true"];
  if (validMessage?.id !== 7 || validMessage.result?.ok !== true ||
      invalidMessages.some((value) => parseCdpMessage(value) !== null)) {
    throw new Error("CDP message validation self-test failed");
  }
  if (/dispatchKeyEvent|dispatchMouseEvent/.test(capture.toString())) {
    throw new Error("Screenshot capture must not dispatch renderer input events");
  }
  console.log(JSON.stringify({ pass: true, version: SKIN_VERSION, test: "loopback-cdp-validation" }));
  } else if (options.mode === "check-payload") {
    const loaded = await loadPayload(options.themeDir, null, options.zcodeArtSource ?? "");
    const unresolved = /__DREAM_SKIN_[A-Z0-9_]+_JSON__/.test(loaded.payload);
    if (unresolved) {
      throw new Error("Payload placeholders were not fully replaced");
    }
    console.log(JSON.stringify({
      pass: true,
      version: SKIN_VERSION,
      payloadBytes: Buffer.byteLength(loaded.payload),
      themeId: loaded.theme.id,
      appearance: loaded.theme.appearance,
      colorMode: loaded.theme.colorMode,
      explicitColorKeys: loaded.theme.explicitColorKeys,
      hasColors: !!loaded.theme.colors && typeof loaded.theme.colors === "object",
      hasPalette: Object.hasOwn(loaded.theme, "palette"),
      art: loaded.theme.art,
      artMetadata: loaded.theme.artMetadata ?? null,
      safeCssStatus: loaded.safeCssStatus,
    }));
  } else if (options.mode === "begin-operation") await runBeginOperation(options);
  else if (options.mode === "finish-operation") await runFinishOperation(options);
  else if (options.mode === "zcode-poc") await runZCodePoc(options);
  else if (options.mode === "zcode-dom-inventory") await runZCodeDomInventory(options);
  else if (options.mode === "zcode-apply") await runZCodeApply(options);
  else if (options.mode === "zcode-remove") await runZCodeRemove(options);
  else if (options.mode === "zcode-verify") await runZCodeVerify(options);
  else if (options.mode === "zcode-watch") await runZCodeWatch(options);
  else if (options.mode === "zcode-pause") await runZCodePause(options);
  else if (options.mode === "zcode-resume") await runZCodeResume(options);
  else if (options.mode === "zcode-close") await runZCodeClose(options);
  else if (options.mode === "zcode-reload") await runZCodeReload(options);
  else if (options.mode === "watch") await runWatch(options);
  else await runOneShot(options);
}
