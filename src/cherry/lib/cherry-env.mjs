// Cherry 端运行环境：所有路径都相对仓库或由环境变量覆盖，不再写死任何本机目录。
import { existsSync, readFileSync, mkdirSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

export const CHERRY_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// UIA 桥：默认用仓库里自带的 Release 产物，可用 DREAMSKIN_CHERRY_BRIDGE 指向自己编译的版本。
export function bridgeExePath() {
  const p = process.env.DREAMSKIN_CHERRY_BRIDGE
    || join(CHERRY_DIR, 'CherryUiBridge', 'bin', 'Release', 'net8.0-windows', 'CherryUiBridge.exe');
  if (!existsSync(p)) {
    throw new Error('找不到 CherryUiBridge.exe：' + p + '（先编译 src/cherry/CherryUiBridge，或设置 DREAMSKIN_CHERRY_BRIDGE）');
  }
  return p;
}

// 工件目录（读回的 CSS、写入载荷）：默认 %LOCALAPPDATA%\DreamSkin\cherry，可用 DREAMSKIN_DATA_DIR 覆盖。
export function dataDir() {
  const base = process.env.DREAMSKIN_DATA_DIR
    || join(process.env.LOCALAPPDATA || join(homedir(), 'AppData', 'Local'), 'DreamSkin', 'cherry');
  mkdirSync(base, { recursive: true });
  return base;
}

// 正在运行的 Cherry Studio 的真实 exe 路径与版本：桥会拿运行中进程的 exe 做身份比对，
// 所以这里也必须取同一个进程，而不是猜安装目录。
function probeRunningCherry() {
  try {
    const script = "$p = Get-Process -Name 'Cherry Studio' -ErrorAction SilentlyContinue | " +
      "Where-Object { $_.Path } | Select-Object -First 1; " +
      "if ($p) { [Console]::Out.Write($p.Path + '|' + (Get-Item -LiteralPath $p.Path).VersionInfo.ProductVersion) }";
    const out = execFileSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', script],
      { encoding: 'utf8', windowsHide: true, timeout: 15000 }).trim();
    if (!out) return null;
    const [path, version] = out.split('|');
    return { path, version: (version || '').trim() };
  } catch {
    return null;
  }
}

export function cherryIdentity() {
  const running = probeRunningCherry();
  if (!running || !existsSync(running.path)) {
    throw new Error('Cherry Studio 没有在运行。请先打开 Cherry Studio，进入 设置 → 外观（自定义 CSS 所在页），窗口不要最小化。');
  }
  const sha = createHash('sha256').update(readFileSync(running.path)).digest('hex');
  // 版本优先用环境变量钉死，其次用运行中 exe 的 ProductVersion（桥按前缀比对）。
  const version = process.env.DREAMSKIN_CHERRY_VERSION || running.version || '2.1.4';
  return { expectedExeSha256: sha, clientVersion: version, cssEditorCount: 1, exePath: running.path };
}
