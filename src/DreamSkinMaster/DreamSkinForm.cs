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

        private readonly string nodeExe = @"C:\Users\Janson\Desktop\换皮\.lemon\dual-skin-closeout-20261015\wt-closeout-cherry\runtime\node\node.exe";
        private readonly string coreDir = @"F:\AI\DreamSkin\core";
        private string customImagePath = "";

        public MainForm()
        {
            InitializeComponent();
        }

        private void InitializeComponent()
        {
            this.Text = "Dream Skin 2.0 - 双端换肤总控台";
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
                Text = "Cherry Studio 与 ZCode 本机零侵入换肤、多预设与自定义背景管理",
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
                Text = "基于 CDP 远程调试热注入，系统托盘常驻管理\r\n已在 D 盘建立全量只增数据备份",
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

            Log("就绪：双端换肤控制套件已就绪。D盘全量数据备份安全生效。");
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

            string script = Path.Combine(coreDir, "apply-cherry.mjs");
            string args = "\"" + script + "\" --preset " + presetKey;
            if (!string.IsNullOrEmpty(customImagePath) && File.Exists(customImagePath))
            {
                args += " --image \"" + customImagePath + "\"";
            }

            string output = await RunProcessAsync(nodeExe, args);
            Log(output.Trim());
            btnCherryApply.Enabled = true;
        }

        private async Task RestoreCherrySkin()
        {
            Log("正在还原 Cherry Studio 为默认初始空白...");
            btnCherryRestore.Enabled = false;
            string script = Path.Combine(coreDir, "restore-cherry.mjs");
            string output = await RunProcessAsync(nodeExe, "\"" + script + "\"");
            Log(output.Trim());
            btnCherryRestore.Enabled = true;
        }

        private async Task LaunchZCodeSkin()
        {
            Log("正在启动 ZCode 增强换肤模式及托盘管理器...");
            string psScript = @"C:\Users\Janson\AppData\Local\Programs\ZCodeDreamSkin\payload\scripts\start-zcode-dream-skin.ps1";
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
            Log("SUCCESS: ZCode 增强换肤已唤起，皮肤管理服务已在系统托盘启动！");
        }

        private async Task RestoreZCodeSkin()
        {
            Log("正在还原 ZCode 为默认纯净初始状态...");
            string psScript = @"C:\Users\Janson\AppData\Local\Programs\ZCodeDreamSkin\payload\scripts\restore-zcode-dream-skin.ps1";
            string output = await RunProcessAsync("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + psScript + "\"");
            Log("SUCCESS: ZCode 皮肤配置已还原回官方默认。");
        }

        private Task<string> RunProcessAsync(string exe, string args)
        {
            return Task.Run(() =>
            {
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
                    using (Process p = Process.Start(psi))
                    {
                        string stdout = p.StandardOutput.ReadToEnd();
                        string stderr = p.StandardError.ReadToEnd();
                        p.WaitForExit(30000);
                        return string.IsNullOrWhiteSpace(stdout) ? stderr : stdout;
                    }
                }
                catch (Exception ex)
                {
                    return "ERROR: " + ex.Message;
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
