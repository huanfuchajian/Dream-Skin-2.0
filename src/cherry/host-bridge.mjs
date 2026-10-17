// 短时 UIA 桥的客户端合同：一条 UTF8 JSON 请求进 stdin，一条 JSON 答复出 stdout。
// 原文 CSS 只落在本地受限工件里，绝不上线；这里只搬 metadata 与哈希。
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, isAbsolute, join } from 'node:path';
import { createHash } from 'node:crypto';

export const REQUEST_TIMEOUT_MS = 30000;
export const HOST_STATUSES = ['verified', 'conflict', 'blocked', 'indeterminate'];
// 线协议两侧唯一的字段名清单：Node 按它发，C# 按它读，测试按它比。
// 这张表存在的理由是真实发生过的漂移——DoRead 要 cssFile，readCss 从来不发，而桥先 blocked
// 在找不到窗口上，「参数没给」这件事被盖住了。
export const WIRE_REQUEST_FIELDS = {
  readCss: ['action', 'requestId', 'cssFile'],
  compareAndSetCss: ['action', 'requestId', 'expectedCurrentSha256', 'newCssFile', 'newCssSha256'],
};
// 答复里客户端必须拿到的字段：少一件就没有可复算的证据。
export const WIRE_REPLY_FIELDS = {
  readCss: ['cssFile', 'lengthChars', 'utf8Bytes', 'sha256', 'readChannel', 'valuePatternChars',
    'identity'],
  compareAndSetCss: ['beforeSha256', 'afterSha256', 'readChannel', 'identity'],
};
// 读回的原文落在哪里由客户端定，并且把名字钉在 requestId 上：两次读不会互相覆盖。
export function artifactFor(dir, requestId) {
  if (typeof dir !== 'string' || dir.length === 0 || !isAbsolute(dir)) fail('artifact_file_required', 'dir');
  if (typeof requestId !== 'string' || requestId.length === 0) fail('bad_request_id', 'requestId');
  return join(dir, 'current-' + requestId.replace(/[^a-zA-Z0-9._-]/g, '_') + '.css');
}
// 读回通道由桥如实上报；只有保住全文形状的通道才算「原样」。ValuePattern 把换行压平，
// 它读回来的不是同一件东西，不能拿来当原样备份或完整回读证据。
export const VERBATIM_READ_CHANNELS = ['textpattern-gettext-minus1', 'textpattern-gettext-maxvalue'];
export const FLATTENED_READ_CHANNEL = 'valuepattern-flattens-newlines';

export class HostProtocolError extends Error {
  constructor(code, field) { super(code); this.code = code; this.field = field; this.name = 'HostProtocolError'; }
}

const fail = (code, field) => { throw new HostProtocolError(code, field); };
const plainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const shaOf = (bytes) => createHash('sha256').update(bytes).digest('hex');
const codePoints = (text) => [...text].length;

export function assertHostIdentity(expected, actual) {
  if (!plainObject(expected) || !plainObject(actual)) fail('bad_identity', 'identity');
  if (actual.exeSha256 !== expected.expectedExeSha256) fail('exe_identity', 'identity.exeSha256');
  if (actual.clientVersion !== expected.clientVersion) fail('version_mismatch', 'identity.clientVersion');
  // 「主窗恰好一个」在真实 Electron 宿主上不是真话：官方那份主窗之外还带一个有标题的隐藏辅助窗
  //（本机 2026-10-11 量到两个 Chrome_WidgetWin_1）。按窗口数判歧义会让正常宿主永远跑不起来，
  // 并把真正该判的事挡在门外。这里只要求「至少看得见一个窗」，唯一性由编辑器控件那一格裁决：
  // cssEditorCount 必须恰好等于期望的那一个（0 是没找到，多了是歧义），仍在任何输入之前退回。
  if (!(actual.mainWindowCount >= 1)) fail('window_not_found', 'identity.mainWindowCount');
  if (actual.cssEditorCount !== expected.cssEditorCount) {
    fail(actual.cssEditorCount === 0 ? 'control_not_found' : 'ambiguous_control', 'identity.cssEditorCount');
  }
  return { ok: true };
}

export function runBridge({ bridge, request, expectedClientIdentity, timeoutMs = REQUEST_TIMEOUT_MS } = {}) {
  if (!plainObject(bridge) || typeof bridge.exe !== 'string' || !Array.isArray(bridge.args)) {
    fail('bad_bridge_spec', 'bridge');
  }
  if (!plainObject(request) || typeof request.requestId !== 'string' || request.requestId.length === 0) {
    fail('bad_request_id', 'request.requestId');
  }
  if (Object.keys(request).some((k) => k === 'css' || k === 'cssText')) fail('css_on_wire', 'request');
  // 动作与字段名先按合同表核一遍：拼错一个字段，桥那边只会回「找不到窗口」，把参数漂移洗成环境不可得。
  const declared = WIRE_REQUEST_FIELDS[request.action];
  if (declared === undefined) fail('unknown_action', 'request.action');
  const extra = Object.keys(request).filter((k) => !declared.includes(k) && k !== 'expectedClientIdentity');
  if (extra.length > 0) fail('unknown_field', 'request.' + extra[0]);
  // 两个方向都要卡：少发一个字段，桥那边只会回「找不到窗口」，参数漂移就被洗成了环境问题。
  const absent = declared.filter((k) => typeof request[k] !== 'string' || request[k].length === 0);
  if (absent.length > 0) fail('incomplete_request', 'request.' + absent[0]);
  const line = JSON.stringify({ ...request, expectedClientIdentity });
  const child = spawnSync(bridge.exe, bridge.args, { input: line + '\n', encoding: 'utf8',
    timeout: timeoutMs, maxBuffer: 8 * 1024 * 1024, windowsVerbatimArguments: false });
  // 超时和「桥根本起不来」是两个不同结论：前者是不确定，后者才可以直接 blocked。
  if (child.error && child.error.code !== 'ETIMEDOUT') fail('bridge_unavailable', 'bridge');
  if (child.status === null) {
    fail(child.signal === 'SIGTERM' || (child.error && child.error.code === 'ETIMEDOUT')
      ? 'bridge_timeout' : 'bridge_interrupted', 'bridge');
  }
  if (child.status !== 0) fail('unexpected_exit', 'bridge');
  if (typeof child.stdout !== 'string' || child.stdout.trim() === '') fail('empty_stdout', 'bridge');
  let response;
  try {
    response = JSON.parse(child.stdout);
  } catch {
    fail('non_json_stdout', 'bridge');
  }
  if (!plainObject(response)) fail('non_json_stdout', 'bridge');
  if (response.requestId !== request.requestId) fail('request_id_mismatch', 'response.requestId');
  if (!HOST_STATUSES.includes(response.status)) fail('unknown_status', 'response.status');
  if (response.identity !== undefined) assertHostIdentity(expectedClientIdentity, response.identity);

  if (response.status === 'verified') {
    // UIA 说 settable、写入调用返回成功、甚至复制成功都不算数；必须有当次答复自带的身份与哈希，
    // 由调用方拿盘上字节复算。缺任何一件就退回 indeterminate。
    for (const key of ['beforeSha256', 'afterSha256', 'cssFile', 'sha256']) {
      if (response[key] !== undefined && typeof response[key] !== 'string') fail('bad_field_shape', key);
    }
  }
  return response;
}

function readArtifact(response) {
  if (typeof response.cssFile !== 'string' || response.cssFile.length === 0
    || typeof response.sha256 !== 'string' || !/^[0-9a-f]{64}$/.test(response.sha256)
    || !Number.isInteger(response.utf8Bytes) || !Number.isInteger(response.lengthChars)) {
    fail('artifact_missing', 'response.cssFile');
  }
  const witness = response.valuePatternChars;
  if (witness !== undefined && witness !== null && !Number.isInteger(witness)) {
    fail('bad_field_shape', 'response.valuePatternChars');
  }
  let bytes;
  try {
    bytes = readFileSync(response.cssFile);
  } catch {
    fail('artifact_missing', 'response.cssFile');
  }
  const text = bytes.toString('utf8');
  if (shaOf(bytes) !== response.sha256) fail('artifact_hash_mismatch', 'response.sha256');
  // 哈希对得上但字符数对不上，就是「读回来的不是全部」——这正是 240056 字节那次的形态。
  if (bytes.length !== response.utf8Bytes || codePoints(text) !== response.lengthChars) {
    fail('truncated_read', 'response.lengthChars');
  }
  // 上面全部成立只证明「片段与它自己的自报一致」。第二证人（ValuePattern 报的字符数，按同样
  // 去换行口径）对不上就一定没读全；对得上**也只是交叉检查**——两条 UIA 通道可能共享同一处
  // 读取限制，一致不等于完整。全文的正面证据是拿已知样本的完整 hash 比（见原生门的 6 例）。
  const crossChecked = Number.isInteger(witness);
  if (crossChecked && witness !== codePoints(text.replace(/[\r\n]/g, ''))) {
    fail('incomplete_read', 'response.valuePatternChars');
  }
  return { text, utf8Bytes: bytes.length, lengthChars: codePoints(text), sha256: response.sha256,
    readChannel: response.readChannel,
    verbatim: VERBATIM_READ_CHANNELS.includes(response.readChannel),
    valuePatternChars: crossChecked ? witness : null, crossChecked };
}

export function readCss({ bridge, readBridge, requestId, expectedClientIdentity, artifactFile,
  timeoutMs } = {}) {
  // 落盘位置由客户端定：桥只答应写到哪，不许自己挑一个文件让我们读。
  if (typeof artifactFile !== 'string' || artifactFile.length === 0 || !isAbsolute(artifactFile)) {
    fail('artifact_file_required', 'artifactFile');
  }
  if (artifactFile !== artifactFor(dirname(artifactFile), requestId)) {
    fail('artifact_name_mismatch', 'artifactFile');
  }
  mkdirSync(dirname(artifactFile), { recursive: true });
  const request = { action: 'readCss', requestId, cssFile: artifactFile };
  const response = runBridge({ bridge: readBridge || bridge, request, expectedClientIdentity, timeoutMs });
  if (response.status !== 'verified') {
    return { ok: false, status: response.status, stage: response.stage ?? null, reason: response.reason ?? null,
      beforeSha256: response.beforeSha256, requestId };
  }
  if (typeof response.cssFile !== 'string' || response.cssFile.length === 0) {
    fail('artifact_missing', 'response.cssFile');
  }
  if (response.cssFile !== artifactFile) fail('artifact_path_drift', 'response.cssFile');
  const read = readArtifact(response);
  return { ok: true, status: 'verified', requestId, cssFile: response.cssFile,
    identity: response.identity, ...read };
}

export function compareAndSetCss({ bridge, readBridge, requestId, expectedCurrentSha256, newCssFile,
  newCssSha256, expectedClientIdentity, readbackFile, timeoutMs } = {}) {
  if (typeof newCssFile !== 'string' || newCssFile.length === 0) fail('bad_new_css_file', 'newCssFile');
  if (typeof expectedCurrentSha256 !== 'string') fail('bad_expected_hash', 'expectedCurrentSha256');
  // 回读工件的名字跟着「那次回读自己的 requestId」钉，和 readCss 用同一条命名规则。
  const back = readbackFile === undefined
    ? artifactFor(dirname(newCssFile), requestId + '-readback') : readbackFile;
  // 回读工件与被写入的载荷不能是同一个文件：写完再读会把比对对象本身覆盖掉。
  if (back === newCssFile) fail('artifact_collides', 'readbackFile');
  const newBytes = readFileSync(newCssFile);
  if (shaOf(newBytes) !== newCssSha256) fail('new_css_hash_mismatch', 'newCssSha256');
  const response = runBridge({ bridge, request: { action: 'compareAndSetCss', requestId,
    expectedCurrentSha256, newCssFile, newCssSha256 }, expectedClientIdentity, timeoutMs });
  if (response.status !== 'verified') {
    return { ok: false, status: response.status, stage: response.stage ?? null,
      reason: response.reason ?? null, beforeSha256: response.beforeSha256, written: false, requestId };
  }
  if (response.afterSha256 !== newCssSha256) fail('readback_mismatch', 'response.afterSha256');
  // 「写完」不等于「宿主里就是这份」：写完必须再用同一把尺完整读回一次。
  // 回读桥的缺省值必须闭合——只给一个桥时复用同一个桥，而不是带着 undefined 去起进程。
  const again = readCss({ bridge, readBridge: readBridge || bridge, requestId: requestId + '-readback',
    expectedClientIdentity, artifactFile: back, timeoutMs });
  if (!again.ok) fail('readback_not_verified', 'readBridge');
  if (again.sha256 !== newCssSha256) fail('readback_mismatch', 'readback.sha256');

  return { ok: true, status: 'verified', written: true, requestId,
    beforeSha256: response.beforeSha256, afterSha256: response.afterSha256,
    identity: response.identity ?? null,
    readback: { sha256: again.sha256, utf8Bytes: again.utf8Bytes, lengthChars: again.lengthChars,
      readChannel: again.readChannel, verbatim: again.verbatim, crossChecked: again.crossChecked,
      cssFile: again.cssFile },
    lengthChars: again.lengthChars, utf8Bytes: again.utf8Bytes };
}

// 一份「能落 active」的回执必须带的字段：少一件就不是证据，completeApply 会当场拒。
export const CAS_RECEIPT_FIELDS = ['status', 'written', 'requestId', 'beforeSha256', 'afterSha256',
  'identity', 'readback', 'lengthChars', 'utf8Bytes'];

export const HOST_REQUEST_FIELDS = ['readCss', 'compareAndSetCss'];
