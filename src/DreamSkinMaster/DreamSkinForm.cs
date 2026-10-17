using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace DreamSkin
{
    public class MainForm : Form
    {
        private Label lblTitle;
        private Label lblSubtitle;
        private Panel panelCherry;
        private Panel panelZCode;

        // Cherry Controls
        private Label lblCherryTitle;
        private Label lblPreset;
        private ComboBox cboPresets;
        private Button btnSelectImage;
        private Label lblSelectedImage;
        private Button btnCherryApply;
        private Button btnCherryRestore;

        // ZCode Controls
        private Label lblZCodeTitle;
        private Label lblZCodeStatus;
        private Button btnZCodeLaunch;
        private Button btnZCodeRestore;

        private TextBox txtLog;

        private string baseDir;
        private string cherryDir;
        private string zcodeDir;
        private string customImagePath = "";

        public MainForm()
        {
            InitializePaths();
            InitializeComponent();
        }

        private string pathSource = "";

        // 查找顺序：DREAMSKIN_ROOT → 向上找仓库（src\cherry\skin-cherry.mjs）→ 旧发布目录 core\。
        // 以前 core\ 优先，导致旧部署目录里的老脚本一直被执行，修复版根本没跑到。
        private void InitializePaths()
        {
            baseDir = AppDomain.CurrentDomain.BaseDirectory;
            cherryDir = null;
            zcodeDir = null;

            string env = Environment.GetEnvironmentVariable("DREAMSKIN_ROOT");
            if (!string.IsNullOrEmpty(env) && File.Exists(Path.Combine(env, "src", "cherry", "skin-cherry.mjs")))
            {
                UseRepoRoot(env, "环境变量 DREAMSKIN_ROOT");
                return;
            }

            string root = baseDir;
            for (int i = 0; i < 5 && root != null; i++)
            {
                if (File.Exists(Path.Combine(root, "src", "cherry", "skin-cherry.mjs")))
                {
                    UseRepoRoot(root, "仓库");
                    return;
                }
                DirectoryInfo parent = Directory.GetParent(root.TrimEnd(Path.DirectorySeparatorChar));
                root = parent == null ? null : parent.FullName;
            }

            root = baseDir;
            for (int i = 0; i < 5 && root != null; i++)
            {
                if (File.Exists(Path.Combine(root, "core", "skin-cherry.mjs")))
                {
                    cherryDir = Path.Combine(root, "core");
                    zcodeDir = Directory.Exists(Path.Combine(root, "core", "zcode", "scripts"))
                        ? Path.Combine(root, "core", "zcode", "scripts") : Path.Combine(root, "core");
                    pathSource = "发布目录 core";
                    return;
                }
                DirectoryInfo parent = Directory.GetParent(root.TrimEnd(Path.DirectorySeparatorChar));
                root = parent == null ? null : parent.FullName;
            }
            pathSource = "";
        }

        private void UseRepoRoot(string root, string source)
        {
            cherryDir = Path.Combine(root, "src", "cherry");
            zcodeDir = Path.Combine(root, "src", "zcode", "payload", "scripts");
            pathSource = source;
        }

        private string ResolveNodeExe()
        {
            // 1. 优先使用本地相对路径打包的可信 node
            string localNode = Path.Combine(baseDir, "runtime", "node", "node.exe");
            if (File.Exists(localNode)) return localNode;

            string parentNode = Path.Combine(baseDir, "..", "runtime", "node", "node.exe");
            if (File.Exists(parentNode)) return Path.GetFullPath(parentNode);

            // 2. 其次使用系统 PATH 中的 node
            return "node.exe";
        }

        private void InitializeComponent()
        {
            this.Text = "Dream Skin 2.0 - 双端换肤总控台 (开源自适应版)";
            this.Size = new Size(720, 530);
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(20, 20, 24);
            this.ForeColor = Color.FromArgb(240, 240, 240);
            this.Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Regular);

            // Title
            lblTitle = new Label
            {
                Text = "Dream Skin 2.0 双端换肤总控台",
                Font = new Font("Microsoft YaHei UI", 15f, FontStyle.Bold),
                ForeColor = Color.FromArgb(200, 165, 90),
                Location = new Point(24, 16),
                AutoSize = true
            };
            this.Controls.Add(lblTitle);

            lblSubtitle = new Label
            {
                Text = "Cherry Studio 与 ZCode 本机零侵入换肤、多预设与全通透壁纸管理（路径完全解耦）",
                Font = new Font("Microsoft YaHei UI", 9f, FontStyle.Regular),
                ForeColor = Color.FromArgb(150, 150, 160),
                Location = new Point(26, 46),
                AutoSize = true
            };
            this.Controls.Add(lblSubtitle);

            // ================== Panel Cherry ==================
            panelCherry = new Panel
            {
                Location = new Point(24, 76),
                Size = new Size(325, 285),
                BackColor = Color.FromArgb(28, 28, 34)
            };
            panelCherry.Paint += (s, e) =>
            {
                ControlPaint.DrawBorder(e.Graphics, panelCherry.ClientRectangle, Color.FromArgb(50, 50, 60), ButtonBorderStyle.Solid);
            };
            this.Controls.Add(panelCherry);

            lblCherryTitle = new Label
            {
                Text = "🍒 Cherry Studio 换肤",
                Font = new Font("Microsoft YaHei UI", 11.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(230, 230, 230),
                Location = new Point(14, 12),
                AutoSize = true
            };
            panelCherry.Controls.Add(lblCherryTitle);

            lblPreset = new Label
            {
                Text = "选择预设风格：",
                ForeColor = Color.FromArgb(180, 180, 190),
                Font = new Font("Microsoft YaHei UI", 8.5f),
                Location = new Point(14, 40),
                AutoSize = true
            };
            panelCherry.Controls.Add(lblPreset);

            cboPresets = new ComboBox
            {
                Location = new Point(14, 62),
                Size = new Size(295, 28),
                DropDownStyle = ComboBoxStyle.DropDownList,
                BackColor = Color.FromArgb(40, 40, 48),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 9f)
            };
            cboPresets.Items.Add("黑金磨砂 (Dark Gold) - 官方经典");
            cboPresets.Items.Add("赛博霓虹蓝 (Cyber Blue) - 极客炫酷");
            cboPresets.Items.Add("极客蓝绿 (Teal Tech) - 科技深翠");
            cboPresets.Items.Add("二次元柔紫 (Anime Purple) - 柔光氛围");
            cboPresets.Items.Add("淡雅护眼奶白 (Soft Cream) - 浅色纸白");
            cboPresets.SelectedIndex = 0;
            panelCherry.Controls.Add(cboPresets);

            btnSelectImage = new Button
            {
                Text = "🖼️ 自定义背景壁纸 (可选)...",
                Location = new Point(14, 100),
                Size = new Size(295, 32),
                BackColor = Color.FromArgb(45, 45, 55),
                ForeColor = Color.FromArgb(210, 210, 220),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 8.5f),
                Cursor = Cursors.Hand
            };
            btnSelectImage.FlatAppearance.BorderSize = 0;
            btnSelectImage.Click += SelectCustomImage;
            panelCherry.Controls.Add(btnSelectImage);

            lblSelectedImage = new Label
            {
                Text = "当前未选择背景图 (纯色磨砂玻璃)",
                ForeColor = Color.FromArgb(130, 130, 140),
                Font = new Font("Microsoft YaHei UI", 8f),
                Location = new Point(14, 136),
                Size = new Size(295, 20),
                AutoEllipsis = true
            };
            panelCherry.Controls.Add(lblSelectedImage);

            btnCherryApply = new Button
            {
                Text = "✨ 立即应用所选皮肤",
                Location = new Point(14, 168),
                Size = new Size(295, 46),
                BackColor = Color.FromArgb(200, 165, 90),
                ForeColor = Color.FromArgb(15, 15, 15),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 10f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnCherryApply.FlatAppearance.BorderSize = 0;
            btnCherryApply.Click += async (s, e) => await ApplyCherrySkin();
            panelCherry.Controls.Add(btnCherryApply);

            btnCherryRestore = new Button
            {
                Text = "🔄 一键还原默认初始样式",
                Location = new Point(14, 224),
                Size = new Size(295, 40),
                BackColor = Color.FromArgb(42, 42, 50),
                ForeColor = Color.FromArgb(220, 220, 220),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 9f),
                Cursor = Cursors.Hand
            };
            btnCherryRestore.FlatAppearance.BorderSize = 0;
            btnCherryRestore.Click += async (s, e) => await RestoreCherrySkin();
            panelCherry.Controls.Add(btnCherryRestore);

            // ================== Panel ZCode ==================
            panelZCode = new Panel
            {
                Location = new Point(365, 76),
                Size = new Size(325, 285),
                BackColor = Color.FromArgb(28, 28, 34)
            };
            panelZCode.Paint += (s, e) =>
            {
                ControlPaint.DrawBorder(e.Graphics, panelZCode.ClientRectangle, Color.FromArgb(50, 50, 60), ButtonBorderStyle.Solid);
            };
            this.Controls.Add(panelZCode);

            lblZCodeTitle = new Label
            {
                Text = "⚡ ZCode 客户端换肤",
                Font = new Font("Microsoft YaHei UI", 11.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(230, 230, 230),
                Location = new Point(14, 12),
                AutoSize = true
            };
            panelZCode.Controls.Add(lblZCodeTitle);

            lblZCodeStatus = new Label
            {
                Text = "基于 CDP 远程调试热注入，系统托盘常驻管理\r\n全套配置支持跨端安全备份与一键无损还原",
                ForeColor = Color.FromArgb(140, 140, 150),
                Font = new Font("Microsoft YaHei UI", 8.5f),
                Location = new Point(14, 42),
                Size = new Size(295, 48)
            };
            panelZCode.Controls.Add(lblZCodeStatus);

            btnZCodeLaunch = new Button
            {
                Text = "✨ 启动 ZCode 增强换肤模式",
                Location = new Point(14, 168),
                Size = new Size(295, 46),
                BackColor = Color.FromArgb(80, 130, 220),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 10f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            btnZCodeLaunch.FlatAppearance.BorderSize = 0;
            btnZCodeLaunch.Click += async (s, e) => await LaunchZCodeSkin();
            panelZCode.Controls.Add(btnZCodeLaunch);

            btnZCodeRestore = new Button
            {
                Text = "🔄 一键还原 ZCode 默认外观",
                Location = new Point(14, 224),
                Size = new Size(295, 40),
                BackColor = Color.FromArgb(42, 42, 50),
                ForeColor = Color.FromArgb(220, 220, 220),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 9f),
                Cursor = Cursors.Hand
            };
            btnZCodeRestore.FlatAppearance.BorderSize = 0;
            btnZCodeRestore.Click += async (s, e) => await RestoreZCodeSkin();
            panelZCode.Controls.Add(btnZCodeRestore);

            // ================== Log ==================
            txtLog = new TextBox
            {
                Location = new Point(24, 375),
                Size = new Size(666, 95),
                Multiline = true,
                ReadOnly = true,
                ScrollBars = ScrollBars.Vertical,
                BackColor = Color.FromArgb(15, 15, 18),
                ForeColor = Color.FromArgb(170, 170, 180),
                BorderStyle = BorderStyle.FixedSingle,
                Font = new Font("Consolas", 9f)
            };
            this.Controls.Add(txtLog);

            if (cherryDir == null)
            {
                Log("ERROR: 找不到 Dream Skin 脚本（src\\cherry\\skin-cherry.mjs）。请把本程序放在仓库目录里运行，或设置环境变量 DREAMSKIN_ROOT 指向仓库根目录。");
                btnCherryApply.Enabled = false;
                btnCherryRestore.Enabled = false;
                btnZCodeLaunch.Enabled = false;
                btnZCodeRestore.Enabled = false;
            }
            else
            {
                Log("脚本目录：" + cherryDir + "（来源：" + pathSource + "）");
            }
        }

        private void Log(string msg)
        {
            if (txtLog.InvokeRequired)
            {
                txtLog.Invoke(new Action(() => Log(msg)));
                return;
            }
            txtLog.AppendText(string.Format("[{0:HH:mm:ss}] {1}\r\n", DateTime.Now, msg));
        }

        private void SelectCustomImage(object sender, EventArgs e)
        {
            using (OpenFileDialog ofd = new OpenFileDialog())
            {
                ofd.Title = "选择背景壁纸图片";
                ofd.Filter = "图片文件 (*.jpg;*.jpeg;*.png;*.webp)|*.jpg;*.jpeg;*.png;*.webp|所有文件 (*.*)|*.*";
                if (ofd.ShowDialog() == DialogResult.OK)
                {
                    customImagePath = ofd.FileName;
                    lblSelectedImage.Text = "壁纸: " + Path.GetFileName(customImagePath);
                    lblSelectedImage.ForeColor = Color.FromArgb(200, 165, 90);
                    Log("已选择背景图片：" + customImagePath);
                }
            }
        }

        private string GetSelectedPresetKey()
        {
            switch (cboPresets.SelectedIndex)
            {
                case 1: return "cyber-blue";
                case 2: return "teal-tech";
                case 3: return "anime-purple";
                case 4: return "warm-cream";
                default: return "dark-gold";
            }
        }

        private async Task ApplyCherrySkin()
        {
            string presetKey = GetSelectedPresetKey();
            Log(string.Format("正在应用 [{0}] 皮肤到 Cherry Studio...", cboPresets.SelectedItem));
            btnCherryApply.Enabled = false;
            try
            {
                string script = Path.Combine(cherryDir, "skin-cherry.mjs");
                if (!File.Exists(script))
                {
                    Log("ERROR: 未找到换肤脚本 " + script);
                    return;
                }
                string args = "\"" + script + "\" apply --preset " + presetKey;
                if (!string.IsNullOrEmpty(customImagePath) && File.Exists(customImagePath))
                {
                    args += " --image \"" + customImagePath + "\"";
                }

                ProcResult r = await RunProcessExAsync(ResolveNodeExe(), args);
                Log(r.Output.Trim());
                if (r.ExitCode == 3)
                {
                    DialogResult ok = MessageBox.Show(this,
                        "Cherry Studio 正在运行，需要由 Dream Skin 重新启动一次才能换肤。\n\n聊天记录不受影响，但输入框里没发出去的文字会丢失。\n\n现在重启 Cherry Studio 吗？",
                        "需要重启 Cherry Studio", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                    if (ok != DialogResult.Yes)
                    {
                        Log("已取消。");
                        return;
                    }
                    Log("正在重启 Cherry Studio 并应用皮肤（约 10-30 秒）...");
                    r = await RunProcessExAsync(ResolveNodeExe(), args + " --restart");
                    Log(r.Output.Trim());
                }
                if (r.ExitCode == 0) OfferDesktopShortcut(script);
            }
            finally
            {
                btnCherryApply.Enabled = true;
            }
        }

        // 皮肤只在「由 Dream Skin 启动的 Cherry」上生效，所以第一次成功后提供一个桌面快捷方式。
        private async void OfferDesktopShortcut(string script)
        {
            string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Cherry Studio (Dream Skin).lnk");
            if (File.Exists(lnk)) return;
            DialogResult ok = MessageBox.Show(this,
                "要在桌面创建「Cherry Studio (Dream Skin)」快捷方式吗？\n\n以后用它打开 Cherry，会自动带上当前皮肤；用原来的图标打开就是原版。",
                "创建快捷方式", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
            if (ok != DialogResult.Yes) return;
            ProcResult r = await RunProcessExAsync(ResolveNodeExe(), "\"" + script + "\" shortcut");
            Log(r.Output.Trim());
        }

        private async Task RestoreCherrySkin()
        {
            Log("正在还原 Cherry Studio 原版外观...");
            btnCherryRestore.Enabled = false;
            try
            {
                string script = Path.Combine(cherryDir, "skin-cherry.mjs");
                if (!File.Exists(script))
                {
                    Log("ERROR: 未找到还原脚本 " + script);
                    return;
                }
                ProcResult r = await RunProcessExAsync(ResolveNodeExe(), "\"" + script + "\" restore");
                Log(r.Output.Trim());
            }
            finally
            {
                btnCherryRestore.Enabled = true;
            }
        }

        private async Task LaunchZCodeSkin()
        {
            Log("正在启动 ZCode 增强换肤模式及托盘管理器...");
            string psScript = Path.Combine(zcodeDir, "start-zcode-dream-skin.ps1");
            if (!File.Exists(psScript))
            {
                // 兼容官方安装目录位置
                string appDataPs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Programs", "ZCodeDreamSkin", "payload", "scripts", "start-zcode-dream-skin.ps1");
                if (File.Exists(appDataPs)) psScript = appDataPs;
            }
            if (!File.Exists(psScript))
            {
                Log("ERROR: 未找到 ZCode 启动脚本 " + psScript);
                return;
            }

            await Task.Run(() =>
            {
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + psScript + "\"",
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                Process.Start(psi);
            });
            Log("已发起 ZCode 换肤启动（脚本在后台运行，约 10-60 秒后 ZCode 窗口出现皮肤、托盘出现图标）。若失败，详情见 %LOCALAPPDATA% 下 ZCodeDreamSkin 状态目录的 last-apply-report.json。");
        }

        private async Task RestoreZCodeSkin()
        {
            Log("正在还原 ZCode 为默认纯净初始状态...");
            string psScript = Path.Combine(zcodeDir, "restore-zcode-dream-skin.ps1");
            if (!File.Exists(psScript))
            {
                string appDataPs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Programs", "ZCodeDreamSkin", "payload", "scripts", "restore-zcode-dream-skin.ps1");
                if (File.Exists(appDataPs)) psScript = appDataPs;
            }

            if (!File.Exists(psScript))
            {
                Log("ERROR: 未找到 ZCode 还原脚本 " + psScript);
                return;
            }
            string output = await RunProcessAsync("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[Text.Encoding]::UTF8; & '" + psScript.Replace("'", "''") + "'; exit $LASTEXITCODE\"");
            Log(output.Trim());
        }

        private class ProcResult
        {
            public string Output = "";
            public int ExitCode = -1;
        }

        private async Task<string> RunProcessAsync(string exe, string args)
        {
            ProcResult r = await RunProcessExAsync(exe, args);
            return r.Output;
        }

        private Task<ProcResult> RunProcessExAsync(string exe, string args)
        {
            return Task.Run(() =>
            {
                ProcResult res = new ProcResult();
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = exe,
                        Arguments = args,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        StandardOutputEncoding = Encoding.UTF8,
                        StandardErrorEncoding = Encoding.UTF8
                    };
                    using (Process p = new Process())
                    {
                        p.StartInfo = psi;
                        StringBuilder outBuf = new StringBuilder();
                        StringBuilder errBuf = new StringBuilder();
                        p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (outBuf) outBuf.AppendLine(e.Data); };
                        p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (errBuf) errBuf.AppendLine(e.Data); };
                        p.Start();
                        p.BeginOutputReadLine();
                        p.BeginErrorReadLine();
                        if (!p.WaitForExit(180000))
                        {
                            try { p.Kill(); } catch { }
                            res.Output = "ERROR: 子进程 3 分钟未结束，已终止。\n" + outBuf + errBuf;
                            return res;
                        }
                        p.WaitForExit();
                        string result = outBuf.ToString();
                        if (errBuf.Length > 0) result += (result.Length > 0 ? "\n" : "") + errBuf;
                        res.ExitCode = p.ExitCode;
                        if (p.ExitCode != 0 && p.ExitCode != 3 && result.IndexOf("FAILED", StringComparison.Ordinal) < 0
                            && result.IndexOf("UNCERTAIN", StringComparison.Ordinal) < 0)
                            result = "FAILED (exit " + p.ExitCode + "):\n" + result;
                        res.Output = result;
                        return res;
                    }
                }
                catch (Exception ex)
                {
                    res.Output = "ERROR: " + ex.Message + "（如果提示找不到 node.exe，请安装 Node.js 22 或更新版本）";
                    return res;
                }
            });
        }

        [STAThread]
        public static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
