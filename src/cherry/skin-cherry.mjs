// Cherry Studio 换肤（CDP 通道，推荐）。做法与 Codex Dream Skin 原型一致：
// 带本机调试端口启动 Cherry → 往主窗口注入一个 <style>，壁纸任意大小、可还原、不碰官方文件和设置。
//
// 用法：
//   node skin-cherry.mjs apply   [--preset dark-gold] [--image 壁纸路径] [--focus-x 50] [--focus-y 40] [--restart]
//   node skin-cherry.mjs restore
//   node skin-cherry.mjs launch     用上次的皮肤启动 Cherry（桌面快捷方式就调它）
//   node skin-cherry.mjs shortcut   在桌面创建「Cherry Studio (Dream Skin)」快捷方式
//   node skin-cherry.mjs status
// 退出码：0 成功 / 1 失败且未改动 / 2 结果不确定 / 3 需要重启 Cherry（加 --restart 重试）
// 内部：node skin-cherry.mjs watch --port N   （常驻守护，Cherry 刷新或重开窗口时自动补上皮肤）
import { existsSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { spawn, execFileSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dataDir } from './lib/cherry-env.mjs';
import { buildCherryCss, imageDataUri, MAX_IMAGE_BYTES_CDP } from './lib/cherry-skin-css.mjs';
import { CdpSession, listCherryMainTargets } from './cdp/cdp-core.mjs';
import {
  listCherryProcesses, debugPortOf, findCherryExe, freePort, portAlive,
  stopCherry, launchCherryWithPort, waitForMainTargets,
} from './cdp/cherry-process.mjs';

const STYLE_ID = 'dream-skin-2-cherry';
const EXIT = { OK: 0, FAILED: 1, UNCERTAIN: 2, NEEDS_RESTART: 3 };

const dir = dataDir();
const SKIN_FILE = join(dir, 'active-skin.css');
const STATE_FILE = join(dir, 'cdp-session.json');
const CHOICE_FILE = join(dir, 'last-choice.json');

function parseArgs(argv) {
  const o = { cmd: argv[0] || 'status', preset: 'dark-gold', image: '', restart: false, port: 0, focusX: NaN, focusY: NaN };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i], v = argv[i + 1];
    if (a === '--preset' && v) { o.preset = v; i++; }
    else if (a === '--image' && v) { o.image = v; i++; }
    else if (a === '--focus-x' && v) { o.focusX = Number(v); i++; }
    else if (a === '--focus-y' && v) { o.focusY = Number(v); i++; }
    else if (a === '--port' && v) { o.port = Number(v); i++; }
    else if (a === '--restart') o.restart = true;
  }
  return o;
}

const readState = () => { try { return JSON.parse(readFileSync(STATE_FILE, 'utf8')); } catch { return null; } };
const writeState = (s) => writeFileSync(STATE_FILE, JSON.stringify(s, null, 2), 'utf8');
const say = (word, msg) => console.log(`${word}: ${msg}`);

// 注入 / 移除脚本。appendChild 每次都把我们的 <style> 挪到 <head> 最后，压过 Cherry 自己的自定义 CSS。
const injectExpr = (css) => `(() => {
  const put = () => {
    let s = document.getElementById(${JSON.stringify(STYLE_ID)});
    if (!s) { s = document.createElement('style'); s.id = ${JSON.stringify(STYLE_ID)}; }
    s.textContent = ${JSON.stringify(css)};
    const head = document.head || document.documentElement;
    head.appendChild(s);
    // Cherry 自己的 <style id="user-defined-custom-css"> 可能之后才插入；始终把皮肤挪回最后。
    if (!window.__dreamSkinObserver) {
      window.__dreamSkinObserver = new MutationObserver(() => {
        const el = document.getElementById(${JSON.stringify(STYLE_ID)});
        if (el && el !== head.lastElementChild) head.appendChild(el);
      });
      window.__dreamSkinObserver.observe(head, { childList: true });
    }
    return s.textContent.length;
  };
  if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', put, { once: true }); return -1; }
  return put();
})()`;
const removeExpr = `(() => { if (window.__dreamSkinObserver) { window.__dreamSkinObserver.disconnect(); window.__dreamSkinObserver = null; } const s = document.getElementById(${JSON.stringify(STYLE_ID)}); if (s) s.remove(); return !document.getElementById(${JSON.stringify(STYLE_ID)}); })()`;
const verifyExpr = `(() => {
  const s = document.getElementById(${JSON.stringify(STYLE_ID)});
  const bg = getComputedStyle(document.body).backgroundImage || '';
  const user = document.getElementById('user-defined-custom-css');
  return { len: s ? s.textContent.length : 0, last: !!s && s === document.head.lastElementChild,
           userCss: user ? user.textContent.length : 0,
           sidebar: !!document.querySelector('#app-sidebar'), wallpaper: bg.includes('url(') };
})()`;

async function withSession(target, port, fn) {
  const session = await new CdpSession(target, port).open();
  try { return await fn(session); } finally { session.close(); }
}

// 找一个能用的调试端口：已有会话 → 正在跑且带端口的 Cherry → 0。
async function currentPort() {
  const st = readState();
  if (st?.port && await portAlive(st.port)) return st.port;
  const main = listCherryProcesses().find((p) => p.isMain && debugPortOf(p));
  if (main && await portAlive(debugPortOf(main))) return debugPortOf(main);
  return 0;
}

function stopWatcher() {
  const st = readState();
  if (st?.watcherPid) { try { process.kill(st.watcherPid); } catch {} }
}

function startWatcher(port) {
  stopWatcher();
  const child = spawn(process.execPath, [fileURLToPath(import.meta.url), 'watch', '--port', String(port)],
    { detached: true, stdio: 'ignore', windowsHide: true });
  child.unref();
  return child.pid;
}

async function apply(o) {
  if (o.image) o.image = resolve(o.image);
  const imageUri = o.image ? imageDataUri(o.image, MAX_IMAGE_BYTES_CDP) : '';
  const css = buildCherryCss(o.preset, imageUri, { focusX: o.focusX, focusY: o.focusY });

  let port = await currentPort();
  if (!port) {
    const running = listCherryProcesses();
    const exe = findCherryExe(running);
    if (!exe) { say('FAILED', '找不到 Cherry Studio 安装位置。可设置环境变量 DREAMSKIN_CHERRY_EXE 指向 Cherry Studio.exe。'); return EXIT.FAILED; }
    if (running.length > 0) {
      if (!o.restart) {
        say('NEEDS_RESTART', 'Cherry Studio 正在运行，需要由 Dream Skin 重新启动一次才能换肤（聊天记录不受影响，未发送的输入框内容会丢失）。');
        return EXIT.NEEDS_RESTART;
      }
      const stop = await stopCherry({ force: true });
      if (!stop.stopped) { say('FAILED', 'Cherry Studio 没能关闭，请手动退出（托盘图标右键 → 退出）后再试。'); return EXIT.FAILED; }
    }
    port = await freePort();
    await launchCherryWithPort(exe, port);
  }

  let targets;
  try { targets = await waitForMainTargets(port, 60000); }
  catch (e) { say('FAILED', e.message); return EXIT.FAILED; }

  // 先落盘，守护进程和后续刷新都读这一份。
  writeFileSync(SKIN_FILE, css, 'utf8');
  let verified = 0, leftoverUserCss = false;
  for (const t of targets) {
    try {
      const v = await withSession(t, port, async (s) => {
        // 等 React 把主界面画出来（#app-sidebar 出现），最多 20 秒。
        for (let i = 0; i < 40; i++) {
          if (await s.evaluate(`!!document.querySelector('#app-sidebar')`)) break;
          await new Promise((r) => setTimeout(r, 500));
        }
        await s.evaluate(injectExpr(css));
        return s.evaluate(verifyExpr);
      });
      if (v.len === css.length && v.sidebar && (!imageUri || v.wallpaper)) verified++;
      if (v.userCss > 0) leftoverUserCss = true;
    } catch {}
  }
  const watcherPid = startWatcher(port);
  writeState({ port, watcherPid, preset: o.preset, image: o.image || '', at: new Date().toISOString() });
  writeFileSync(CHOICE_FILE, JSON.stringify({ preset: o.preset, image: o.image || '', focusX: o.focusX, focusY: o.focusY }), 'utf8');

  const hint = leftoverUserCss ? '注意：Cherry 设置 → 外观 → 自定义 CSS 里还有内容（可能是旧版换肤写进去的），建议清空，免得和皮肤打架。' : '';
  if (verified === targets.length) {
    say('SUCCESS', `已应用 [${o.preset}]${o.image ? ' + 自定义壁纸' : ''}，主窗口校验通过。以后请用 Dream Skin 启动 Cherry，皮肤会自动带上。${hint}`);
    return EXIT.OK;
  }
  say('UNCERTAIN', `已注入，但 ${targets.length - verified}/${targets.length} 个主窗口没通过校验（可能还在加载）。看一眼 Cherry 窗口；不对就点「还原」。`);
  return EXIT.UNCERTAIN;
}

async function restore() {
  rmSync(SKIN_FILE, { force: true });
  stopWatcher();
  const port = await currentPort();
  if (!port) {
    rmSync(STATE_FILE, { force: true });
    say('SUCCESS', '皮肤已关闭。Dream Skin 不改 Cherry 的文件和设置，正常打开 Cherry 就是原版。');
    return EXIT.OK;
  }
  let removed = 0, total = 0;
  try {
    const targets = await listCherryMainTargets(port);
    total = targets.length;
    for (const t of targets) {
      try { if (await withSession(t, port, (s) => s.evaluate(removeExpr))) removed++; } catch {}
    }
  } catch {}
  rmSync(STATE_FILE, { force: true });
  if (removed === total) { say('SUCCESS', '已从正在运行的 Cherry 移除皮肤，立即恢复原版外观。'); return EXIT.OK; }
  say('UNCERTAIN', '部分窗口没确认移除。重启一次 Cherry 即可彻底恢复原版。');
  return EXIT.UNCERTAIN;
}

async function launch(o) {
  let c = null;
  try { c = JSON.parse(readFileSync(CHOICE_FILE, 'utf8')); } catch {}
  if (!c) { say('FAILED', '还没应用过皮肤，请先在 Dream Skin 里选预设并点「应用」。'); return EXIT.FAILED; }
  if (c.image && !existsSync(c.image)) c.image = '';
  return apply({ ...o, preset: c.preset, image: c.image, focusX: Number(c.focusX), focusY: Number(c.focusY) });
}

function shortcut() {
  const exe = findCherryExe();
  const script = fileURLToPath(import.meta.url);
  const psq = (v) => "'" + String(v).replace(/'/g, "''") + "'";
  execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
    `$s=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cherry Studio (Dream Skin).lnk'));` +
    `$s.TargetPath=${psq(process.execPath)};$s.Arguments=${psq('"' + script + '" launch --restart')};` +
    `$s.WindowStyle=7;${exe ? `$s.IconLocation=${psq(exe + ',0')};` : ''}$s.Save()`], { windowsHide: true });
  say('SUCCESS', '桌面已创建「Cherry Studio (Dream Skin)」快捷方式，以后用它打开 Cherry 就自动带皮肤。');
  return EXIT.OK;
}

async function status() {
  const port = await currentPort();
  const st = readState();
  console.log(JSON.stringify({ cherryRunning: listCherryProcesses().length > 0, debugPort: port,
    skinActive: existsSync(SKIN_FILE), preset: st?.preset ?? null, cherryExe: findCherryExe() || null }, null, 2));
  return EXIT.OK;
}

// 守护：保持连接，给每个主窗口注册 addScriptToEvaluateOnNewDocument（刷新后自动带皮肤），
// 每 3 秒看一次有没有新开的主窗口、皮肤文件有没有被换；Cherry 退出后自己结束。
async function watch(o) {
  const port = o.port;
  const sessions = new Map();
  let misses = 0;
  for (;;) {
    let css = null;
    try { css = readFileSync(SKIN_FILE, 'utf8'); } catch {}
    if (css === null) break; // 已还原
    let targets = [];
    try { targets = await listCherryMainTargets(port); misses = 0; }
    catch { if (++misses >= 3) break; }
    const live = new Set(targets.map((t) => t.id));
    for (const [id, entry] of sessions) {
      if (!live.has(id) || entry.session.closed) { entry.session.close(); sessions.delete(id); }
    }
    for (const t of targets) {
      let entry = sessions.get(t.id);
      try {
        if (!entry) {
          const session = await new CdpSession(t, port).open();
          entry = { session, scriptId: null, css: null };
          sessions.set(t.id, entry);
        }
        if (entry.css !== css) {
          if (entry.scriptId) await entry.session.send('Page.removeScriptToEvaluateOnNewDocument', { identifier: entry.scriptId });
          const r = await entry.session.send('Page.addScriptToEvaluateOnNewDocument', { source: injectExpr(css) });
          entry.scriptId = r.identifier;
          await entry.session.evaluate(injectExpr(css));
          entry.css = css;
        }
      } catch {
        if (entry) { entry.session.close(); sessions.delete(t.id); }
      }
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  for (const { session } of sessions.values()) session.close();
  return EXIT.OK;
}

const o = parseArgs(process.argv.slice(2));
const run = { apply, restore, status, watch, launch, shortcut: async () => shortcut() }[o.cmd];
if (!run) { say('FAILED', '未知命令：' + o.cmd + '（可用 apply / launch / restore / shortcut / status）'); process.exit(EXIT.FAILED); }
run(o).then((code) => process.exit(code), (e) => {
  say('FAILED', e?.message || String(e));
  process.exit(EXIT.FAILED);
});
