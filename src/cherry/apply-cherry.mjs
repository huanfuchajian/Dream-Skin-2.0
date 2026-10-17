// 用法：node apply-cherry.mjs [--preset dark-gold|cyber-blue|teal-tech|anime-purple|warm-cream] [--image 壁纸路径]
// 走 Cherry 官方「自定义 CSS」通道，经 UIA 桥做 CAS 写入并完整读回校验。
import { writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import * as cw from './host-bridge.mjs';
import { bridgeExePath, dataDir, cherryIdentity } from './lib/cherry-env.mjs';
import { buildCherryCss, imageDataUri } from './lib/cherry-skin-css.mjs';

function parseArgs(argv) {
  const out = { preset: 'dark-gold', image: '' };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--preset' && argv[i + 1]) out.preset = argv[++i];
    else if (argv[i] === '--image' && argv[i + 1]) out.image = argv[++i];
  }
  return out;
}

try {
  const { preset, image } = parseArgs(process.argv.slice(2));
  const css = buildCherryCss(preset, image ? imageDataUri(image) : '');
  const identity = cherryIdentity();
  const { exePath, ...expectedIdentity } = identity;
  const bridge = { exe: bridgeExePath(), args: [] };
  const dir = dataDir();

  const probeId = 'pre-apply-' + Date.now();
  const probe = cw.readCss({ bridge, requestId: probeId, expectedClientIdentity: expectedIdentity,
    artifactFile: cw.artifactFor(dir, probeId), timeoutMs: 15000 });
  if (!probe.ok) {
    console.log(`FAILED: 读取当前 CSS 失败（${probe.status} / ${probe.reason ?? probe.stage ?? '未知'}）。请确认 Cherry 停在 设置 → 外观 页且窗口未最小化。`);
    process.exit(1);
  }
  // 第一次换肤前，把用户原来的 CSS 备份一份，方便手动找回。
  const backup = dir + '/original-before-dream-skin.css';
  try { writeFileSync(backup, probe.text, { flag: 'wx' }); } catch {}

  const skinFile = dir + '/cherry-dream-skin-applied.css';
  writeFileSync(skinFile, css, 'utf8');
  const skinSha = createHash('sha256').update(Buffer.from(css, 'utf8')).digest('hex');

  const applyId = 'apply-' + Date.now();
  const res = cw.compareAndSetCss({ bridge, requestId: applyId, expectedCurrentSha256: probe.sha256,
    newCssFile: skinFile, newCssSha256: skinSha, expectedClientIdentity: expectedIdentity,
    readbackFile: cw.artifactFor(dir, applyId + '-readback'), timeoutMs: 25000 });

  if (res.ok) {
    console.log(`SUCCESS: 已应用 [${preset}]${image ? ' + 自定义壁纸' : ''}，读回校验通过（${res.utf8Bytes} 字节，${res.afterSha256.slice(0, 8)}…）。`);
  } else {
    console.log(`FAILED: 写入未通过校验（${res.status} / ${res.reason ?? res.stage ?? '未知'}）。原 CSS 未被覆盖。`);
    process.exit(1);
  }
} catch (e) {
  console.log('FAILED: ' + (e.code ? `${e.code} @ ${e.field}` : e.message));
  process.exit(1);
}
