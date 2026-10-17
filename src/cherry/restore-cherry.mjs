import { writeFileSync } from 'node:fs';

(async () => {
  const cw = await import('file:///C:/Users/Janson/Desktop/换皮/.lemon/dual-skin-closeout-20261015/wt-closeout-cherry/src/host-bridge.mjs');
  const dir = 'F:/AI/DreamSkin/core';
  const bridgeExe = 'C:/Users/Janson/Desktop/换皮/.lemon/dual-skin-closeout-20261015/wt-cherry/.lemon/payload-candidate-r19/host/CherryUiBridge/bin/Release/net8.0-windows/CherryUiBridge.exe';
  const expectedIdentity = {
    expectedExeSha256: '18c07435ad386dee820c39598d667b6f769498398ada8e7bc1623cd23aadda55',
    clientVersion: '2.1.4',
    cssEditorCount: 1
  };

  const probeReqId = 'pre-restore-' + Date.now();
  const probeArtFile = cw.artifactFor(dir, probeReqId);
  const probeRes = await cw.readCss({
    bridge: { exe: bridgeExe, args: [] },
    requestId: probeReqId,
    expectedClientIdentity: expectedIdentity,
    artifactFile: probeArtFile,
    timeoutMs: 15000
  });

  if (!probeRes.ok) {
    console.log('FAILED: 无法连接到 Cherry Studio。');
    process.exit(1);
  }

  const currentSha = probeRes.sha256;
  const cleanCss = '\n';
  const cleanFile = dir + '/clean-baseline.css';
  writeFileSync(cleanFile, cleanCss, 'utf8');

  const { createHash } = await import('node:crypto');
  const cleanSha = createHash('sha256').update(Buffer.from(cleanCss, 'utf8')).digest('hex');

  const res = await cw.compareAndSetCss({
    bridge: { exe: bridgeExe, args: [] },
    requestId: 'restore-' + Date.now(),
    expectedCurrentSha256: currentSha,
    newCssFile: cleanFile,
    newCssSha256: cleanSha,
    expectedClientIdentity: expectedIdentity,
    readbackFile: dir + '/readback-clean.css',
    timeoutMs: 25000
  });

  if (res.beforeSha256) {
    console.log('SUCCESS: Cherry Studio 自定义 CSS 已彻底还原为空白基线！');
  } else {
    console.log('FAILED: 还原失败。');
  }
})();
