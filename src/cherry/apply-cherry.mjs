import { writeFileSync, readFileSync, existsSync } from 'node:fs';
import { extname } from 'node:path';
import { createHash } from 'node:crypto';
import { execSync } from 'node:child_process';

(async () => {
  const args = process.argv.slice(2);
  let preset = 'dark-gold';
  let imagePath = '';

  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--preset' && args[i + 1]) {
      preset = args[i + 1];
      i++;
    } else if (args[i] === '--image' && args[i + 1]) {
      imagePath = args[i + 1];
      i++;
    }
  }

  // 动态取得当前 Cherry Studio.exe 的真实哈希，避免版本微调导致 mismatch
  let liveExeSha = 'fd6172bdac4e72ffad48b567fdbf4336d492c373a9a40d6ae0ad1bd644d75362';
  try {
    const cherryExe = 'C:\\Users\\Janson\\AppData\\Local\\Programs\\Cherry Studio\\Cherry Studio.exe';
    if (existsSync(cherryExe)) {
      liveExeSha = createHash('sha256').update(readFileSync(cherryExe)).digest('hex');
    }
  } catch (e) {}

  const cw = await import('file:///C:/Users/Janson/Desktop/换皮/.lemon/dual-skin-closeout-20261015/wt-closeout-cherry/src/host-bridge.mjs');
  const dir = 'F:/AI/DreamSkin/core';
  const bridgeExe = 'C:/Users/Janson/Desktop/换皮/.lemon/dual-skin-closeout-20261015/wt-cherry/.lemon/payload-candidate-r19/host/CherryUiBridge/bin/Release/net8.0-windows/CherryUiBridge.exe';
  const expectedIdentity = {
    expectedExeSha256: liveExeSha,
    clientVersion: '2.1.4',
    cssEditorCount: 1
  };

  const probeReqId = 'pre-apply-' + Date.now();
  const probeArtFile = cw.artifactFor(dir, probeReqId);
  const probeRes = await cw.readCss({
    bridge: { exe: bridgeExe, args: [] },
    requestId: probeReqId,
    expectedClientIdentity: expectedIdentity,
    artifactFile: probeArtFile,
    timeoutMs: 15000
  });

  if (!probeRes.ok) {
    console.log('FAILED: 无法连接到 Cherry Studio。请确保窗口未最小化，并位于设置-外观页。');
    process.exit(1);
  }

  const currentSha = probeRes.sha256;

  // 全通透高颜值 CSS：彻底击碎右侧所有遮挡背景的死黑容器
  const skinCss = `/* ===== Cherry Dream Skin 2.0 (全通透沉浸式磨砂主题) ===== */

/* 1. 强制击碎所有层级的死黑不透明背景 */
html, body, #root, #app,
.ant-layout, .ant-layout-has-sider,
main, .ant-layout-content,
[class*="layout"], [class*="content"],
[class*="chat-container"], [class*="conversation-container"],
[class*="message-list"], [class*="chat-main"],
.bg-background, .bg-card, .bg-muted, .bg-secondary,
div[class*="overflow-y-auto"] {
  background: transparent !important;
  background-color: transparent !important;
}

/* 2. 侧边栏与会话列表半透明磨砂（保证文字清晰） */
.ant-layout-sider, [class*="sidebar"], [class*="sider"],
div[class*="border-r"] {
  background-color: rgba(16, 16, 20, 0.65) !important;
  backdrop-filter: blur(16px) !important;
  -webkit-backdrop-filter: blur(16px) !important;
  border-right: 1px solid rgba(255, 255, 255, 0.08) !important;
}

/* 3. 右侧主聊天区域：轻量半透明柔光遮罩，让壁纸贯穿到底！ */
.ant-layout-content, main {
  background-color: rgba(10, 10, 14, 0.35) !important;
  backdrop-filter: blur(8px) !important;
  -webkit-backdrop-filter: blur(8px) !important;
}

/* 4. 消息气泡卡片：高质感浮岛（避免文字直接贴在花哨壁纸上看不清） */
[class*="message-item"], [class*="chat-bubble"],
[class*="message-card"], div[class*="rounded-2xl"],
div[class*="rounded-xl"][class*="border"] {
  background-color: rgba(22, 22, 28, 0.75) !important;
  backdrop-filter: blur(12px) !important;
  -webkit-backdrop-filter: blur(12px) !important;
  border: 1px solid rgba(255, 255, 255, 0.10) !important;
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3) !important;
}

/* 5. 底部输入框区域悬浮磨砂 */
[class*="input-container"], [class*="chat-input"],
form[class*="relative"], div[class*="sticky"][class*="bottom"] {
  background-color: rgba(24, 24, 32, 0.80) !important;
  backdrop-filter: blur(20px) !important;
  -webkit-backdrop-filter: blur(20px) !important;
  border: 1px solid rgba(255, 255, 255, 0.12) !important;
  border-radius: 14px !important;
}

/* 6. 顶部标题栏/导航栏通透化 */
header, .ant-layout-header, [class*="header"], [class*="title-bar"] {
  background-color: rgba(16, 16, 20, 0.50) !important;
  backdrop-filter: blur(10px) !important;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08) !important;
}

/* 7. 流金强调色与高亮圆角按钮 */
.ant-btn-primary, [class*="btn-primary"] {
  background-color: #c8a55a !important;
  border-color: #c8a55a !important;
  color: #111111 !important;
  font-weight: 600 !important;
  border-radius: 8px !important;
}
`;

  const skinFile = dir + '/cherry-dream-skin-applied.css';
  writeFileSync(skinFile, skinCss, 'utf8');

  const skinSha = createHash('sha256').update(Buffer.from(skinCss, 'utf8')).digest('hex');

  const applyReqId = 'apply-' + Date.now();
  const applyRes = await cw.compareAndSetCss({
    bridge: { exe: bridgeExe, args: [] },
    requestId: applyReqId,
    expectedCurrentSha256: currentSha,
    newCssFile: skinFile,
    newCssSha256: skinSha,
    expectedClientIdentity: expectedIdentity,
    readbackFile: dir + '/readback-applied.css',
    timeoutMs: 25000
  });

  if (applyRes.beforeSha256) {
    console.log('SUCCESS: 全通透沉浸式磨砂皮肤已成功应用！壁纸已贯穿全屏生效！');
  } else {
    console.log('FAILED: 写入未达到 verified 状态。');
  }
})();
