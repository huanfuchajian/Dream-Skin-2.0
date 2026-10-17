// 用法：node restore-cherry.mjs
// 旧通道（UIA，保留作参考）。默认请用 skin-cherry.mjs（CDP 注入，壁纸无大小限制）。
// 把 Cherry 自定义 CSS 还原为空白（官方初始状态），同样走 CAS + 读回校验。
import { writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import * as cw from './host-bridge.mjs';
import { bridgeExePath, dataDir, cherryIdentity } from './lib/cherry-env.mjs';

try {
  const { exePath, ...expectedIdentity } = cherryIdentity();
  const bridge = { exe: bridgeExePath(), args: [] };
  const dir = dataDir();

  const probeId = 'pre-restore-' + Date.now();
  const probe = cw.readCss({ bridge, requestId: probeId, expectedClientIdentity: expectedIdentity,
    artifactFile: cw.artifactFor(dir, probeId), timeoutMs: 15000 });
  if (!probe.ok) {
    console.log(`FAILED: 读取当前 CSS 失败（${probe.status} / ${probe.reason ?? probe.stage ?? '未知'}）。`);
    process.exit(1);
  }

  // 与 2.0 版一致：空白基线写为单个换行（CM6 空文档经 UIA 读回即为 1 字节换行）。
  const cleanCss = '\n';
  const cleanFile = dir + '/clean-baseline.css';
  writeFileSync(cleanFile, cleanCss, 'utf8');
  const cleanSha = createHash('sha256').update(Buffer.from(cleanCss, 'utf8')).digest('hex');
  if (probe.sha256 === cleanSha) {
    console.log('SUCCESS: Cherry Studio 自定义 CSS 已经是空白，无需还原。');
    process.exit(0);
  }

  const id = 'restore-' + Date.now();
  const res = cw.compareAndSetCss({ bridge, requestId: id, expectedCurrentSha256: probe.sha256,
    newCssFile: cleanFile, newCssSha256: cleanSha, expectedClientIdentity: expectedIdentity,
    readbackFile: cw.artifactFor(dir, id + '-readback'), timeoutMs: 25000 });
  if (res.ok) {
    console.log('SUCCESS: Cherry Studio 自定义 CSS 已还原为空白基线。');
  } else {
    console.log(`FAILED: 还原未通过校验（${res.status} / ${res.reason ?? res.stage ?? '未知'}）。`);
    process.exit(1);
  }
} catch (e) {
  console.log('FAILED: ' + (e.code ? `${e.code} @ ${e.field}` : e.message));
  process.exit(1);
}
