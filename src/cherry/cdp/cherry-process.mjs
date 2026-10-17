// 找到 / 关闭 / 带调试端口启动 Cherry Studio。思路取自 Fei-Away/Codex-Dream-Skin 的 Windows 启动流程
// （CloseMainWindow 优雅关闭 → 随机空闲端口 → --remote-debugging-port 启动 → 轮询 /json/list）。
// Cherry 官方回归测试也是这样驱动已安装版的（scripts/e2e/regression/lifecycle.ts:118-121）。
import { execFileSync, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { fetchCdpJson, listCherryMainTargets } from './cdp-core.mjs';

const EXE_NAME = 'Cherry Studio.exe';

function ps(script, timeout = 15000) {
  return execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
    '[Console]::OutputEncoding=[Text.Encoding]::UTF8;' + script],
  { encoding: 'utf8', windowsHide: true, timeout }).trim();
}

// 所有 Cherry 进程（Electron 一个实例有多个同名子进程，主进程的命令行里没有 --type=）。
export function listCherryProcesses() {
  try {
    const out = ps(`@(Get-CimInstance Win32_Process -Filter "Name='${EXE_NAME}'" | ` +
      `Select-Object ProcessId,ExecutablePath,CommandLine) | ConvertTo-Json -Compress`);
    if (!out) return [];
    const data = JSON.parse(out);
    return (Array.isArray(data) ? data : [data]).map((p) => ({
      pid: p.ProcessId, path: p.ExecutablePath || '', cmd: p.CommandLine || '',
      isMain: !/\s--type=/.test(p.CommandLine || ''),
    }));
  } catch {
    return [];
  }
}

export function debugPortOf(proc) {
  const m = /--remote-debugging-port=(\d{2,5})/.exec(proc?.cmd || '');
  return m ? Number(m[1]) : 0;
}

// exe 路径：环境变量 → 正在运行的进程 → 常见安装位置 → 卸载注册表。
export function findCherryExe(running = listCherryProcesses()) {
  const env = process.env.DREAMSKIN_CHERRY_EXE;
  if (env && existsSync(env)) return env;
  const live = running.find((p) => p.isMain && p.path && existsSync(p.path));
  if (live) return live.path;
  const local = process.env.LOCALAPPDATA || '';
  const candidates = [
    join(local, 'Programs', 'Cherry Studio', EXE_NAME),
    join(process.env.ProgramFiles || 'C:\\Program Files', 'Cherry Studio', EXE_NAME),
    join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Cherry Studio', EXE_NAME),
  ];
  for (const c of candidates) if (existsSync(c)) return c;
  try {
    const loc = ps("$k = Get-ItemProperty 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'," +
      "'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*' -ErrorAction SilentlyContinue | " +
      "Where-Object { $_.DisplayName -like 'Cherry Studio*' -and $_.InstallLocation } | Select-Object -First 1; " +
      "if ($k) { [Console]::Out.Write($k.InstallLocation) }");
    if (loc && existsSync(join(loc, EXE_NAME))) return join(loc, EXE_NAME);
  } catch {}
  return '';
}

export function freePort() {
  return new Promise((resolve, reject) => {
    const srv = createServer();
    srv.unref();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

export async function portAlive(port) {
  if (!port) return false;
  try { await fetchCdpJson(port, '/json/version', 1500); return true; } catch { return false; }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// 先发 WM_CLOSE（等同点窗口 ×），Cherry 开了「关闭时最小化到托盘」就关不掉，这时才 /F。
export async function stopCherry({ force = true, waitMs = 8000 } = {}) {
  if (listCherryProcesses().length === 0) return { stopped: true, forced: false };
  try { execFileSync('taskkill.exe', ['/IM', EXE_NAME, '/T'], { windowsHide: true, stdio: 'ignore' }); } catch {}
  for (let t = 0; t < waitMs; t += 500) {
    await sleep(500);
    if (listCherryProcesses().length === 0) return { stopped: true, forced: false };
  }
  if (!force) return { stopped: false, forced: false };
  try { execFileSync('taskkill.exe', ['/IM', EXE_NAME, '/T', '/F'], { windowsHide: true, stdio: 'ignore' }); } catch {}
  for (let t = 0; t < 5000; t += 500) {
    await sleep(500);
    if (listCherryProcesses().length === 0) return { stopped: true, forced: true };
  }
  return { stopped: false, forced: true };
}

export async function launchCherryWithPort(exe, port) {
  const child = spawn(exe, [`--remote-debugging-port=${port}`], { detached: true, stdio: 'ignore', windowsHide: false });
  child.unref();
  return child.pid;
}

// 等主窗口页面出现：最多 timeoutMs。
export async function waitForMainTargets(port, timeoutMs = 60000) {
  const until = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() < until) {
    try {
      const targets = await listCherryMainTargets(port);
      if (targets.length > 0) return targets;
    } catch (e) { last = e; }
    await sleep(500);
  }
  throw new Error('等待 Cherry 主窗口超时' + (last ? `（${last.message}）` : '') +
    '。如果 Cherry 已打开但一直超时，说明这版 Cherry 不接受调试端口参数，请把这行日志发给维护者。');
}
