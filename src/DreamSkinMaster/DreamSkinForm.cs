// Dream Skin 2.0 总控台（单文件 WinForms，C# 5 / .NET Framework 4.5+，Windows 10/11 自带运行时）。
// 打包方式：build.bat 把 src\cherry 与 src\zcode\payload 压成 payload.zip 嵌进 exe；
// 首次运行释放到 %LOCALAPPDATA%\DreamSkin\app\<内容哈希>\，之后直接复用。
// 在仓库里运行时（能向上找到 src\cherry\skin-cherry.mjs）优先用仓库源码，方便开发。
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace DreamSkin
{
    // ---------------------------------------------------------------- 配色与预设
    internal static class Theme
    {
        public static readonly Color Bg = Color.FromArgb(14, 14, 18);
        public static readonly Color Nav = Color.FromArgb(19, 19, 24);
        public static readonly Color Card = Color.FromArgb(24, 24, 30);
        public static readonly Color CardHover = Color.FromArgb(32, 32, 40);
        public static readonly Color Line = Color.FromArgb(44, 44, 54);
        public static readonly Color Text = Color.FromArgb(236, 236, 242);
        public static readonly Color Muted = Color.FromArgb(150, 150, 165);
        public static readonly Color Gold = Color.FromArgb(214, 178, 102);
        public static readonly Color Blue = Color.FromArgb(88, 140, 255);
        public static readonly Color Green = Color.FromArgb(92, 200, 140);
        public static readonly Color Red = Color.FromArgb(240, 100, 100);
        public static readonly Color Yellow = Color.FromArgb(240, 196, 90);
        public static Font F(float size, FontStyle style = FontStyle.Regular)
        {
            return new Font("Microsoft YaHei UI", size, style, GraphicsUnit.Point);
        }
    }

    internal class CherryPreset
    {
        public string Key, Name;
        public bool Dark;
        public Color Bg, Panel, Bubble, Accent, Text;
        public CherryPreset(string key, string name, bool dark, string bg, string panel, string bubble, string accent, string text)
        {
            Key = key; Name = name; Dark = dark;
            Bg = ColorTranslator.FromHtml(bg); Panel = ColorTranslator.FromHtml(panel);
            Bubble = ColorTranslator.FromHtml(bubble); Accent = ColorTranslator.FromHtml(accent); Text = ColorTranslator.FromHtml(text);
        }
        // 与 src/cherry/lib/cherry-skin-css.mjs 的 CHERRY_PRESETS 保持一致。
        public static readonly CherryPreset[] All = new CherryPreset[]
        {
            new CherryPreset("dark-gold",    "黑金磨砂",   true,  "#0e0d0c", "#141210", "#1c1915", "#c8a55a", "#f3ead7"),
            new CherryPreset("cyber-blue",   "赛博霓虹蓝", true,  "#070b18", "#0a1022", "#0f1830", "#3fa9ff", "#e6f2ff"),
            new CherryPreset("teal-tech",    "极客蓝绿",   true,  "#05201f", "#072221", "#0a2e2c", "#2fd3b5", "#e2fbf6"),
            new CherryPreset("anime-purple", "二次元柔紫", true,  "#1a1325", "#221830", "#2e2140", "#c59bff", "#f6eeff"),
            new CherryPreset("warm-cream",   "淡雅护眼奶白", false, "#f3e7d3", "#faf4e8", "#fffbf3", "#a07a3c", "#3a2f22"),
        };
    }

    internal class ZCodePreset
    {
        public string Id, Name, Dir, Image;
    }

    // ---------------------------------------------------------------- 自绘控件
    internal class FlatButton : Button
    {
        public Color Fill = Theme.Card, Fore = Theme.Text, Border = Theme.Line;
        private bool hover;
        public FlatButton(string text, Color fill, Color fore)
        {
            Text = text; Fill = fill; Fore = fore; Border = fill;
            FlatStyle = FlatStyle.Flat; FlatAppearance.BorderSize = 0;
            Font = Theme.F(10f, FontStyle.Bold); Cursor = Cursors.Hand; Height = 40;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Bg);
            Color c = Enabled ? (hover ? ControlPaint.Light(Fill, 0.15f) : Fill) : Color.FromArgb(40, 40, 48);
            using (GraphicsPath p = Ui.Round(new Rectangle(0, 0, Width - 1, Height - 1), 8))
            using (SolidBrush b = new SolidBrush(c))
            using (Pen pen = new Pen(Enabled ? Border : Theme.Line))
            { g.FillPath(b, p); g.DrawPath(pen, p); }
            bool nav = (Tag as string) == "nav";
            Rectangle tr = nav ? new Rectangle(18, 0, Width - 18, Height) : ClientRectangle;
            TextRenderer.DrawText(g, Text, Font, tr, Enabled ? Fore : Theme.Muted,
                (nav ? TextFormatFlags.Left : TextFormatFlags.HorizontalCenter) | TextFormatFlags.VerticalCenter);
        }
    }

    internal class Card : Panel
    {
        public string Title = "";
        public Card() { BackColor = Theme.Card; DoubleBuffered = true; Padding = new Padding(16, 44, 16, 16); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen pen = new Pen(Theme.Line)) g.DrawRectangle(pen, 0, 0, Width - 1, Height - 1);
            TextRenderer.DrawText(g, Title, Theme.F(11f, FontStyle.Bold), new Point(16, 14), Theme.Text);
        }
    }

    // 预设色卡：选中时描金边。
    internal class SwatchTile : Control
    {
        public bool Selected;
        public string Caption = "";
        public Color[] Colors = new Color[0];
        public Image Thumb;
        private bool hover;
        public SwatchTile()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand; Size = new Size(118, 92); Font = Theme.F(9f);
        }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Parent != null ? Parent.BackColor : Theme.Card);
            Rectangle r = new Rectangle(1, 1, Width - 3, Height - 3);
            using (GraphicsPath p = Ui.Round(r, 8))
            using (SolidBrush b = new SolidBrush(hover ? Theme.CardHover : Color.FromArgb(30, 30, 37)))
                g.FillPath(b, p);
            Rectangle top = new Rectangle(8, 8, Width - 17, Height - 36);
            using (GraphicsPath tp = Ui.Round(top, 6))
            {
                g.SetClip(tp);
                if (Thumb != null) Ui.DrawCover(g, Thumb, top, 0.5f, 0.45f);
                else if (Colors.Length > 0)
                {
                    int w = top.Width / Colors.Length + 1;
                    for (int i = 0; i < Colors.Length; i++)
                        using (SolidBrush sb = new SolidBrush(Colors[i])) g.FillRectangle(sb, top.X + i * w, top.Y, w, top.Height);
                }
                g.ResetClip();
            }
            TextRenderer.DrawText(g, Caption, Font, new Rectangle(4, Height - 27, Width - 8, 22), Selected ? Theme.Gold : Theme.Text,
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            if (Selected)
                using (GraphicsPath p = Ui.Round(r, 8))
                using (Pen pen = new Pen(Theme.Gold, 2f)) g.DrawPath(pen, p);
        }
    }

    // Cherry 预览：按 cherry-skin-css.mjs 的同一套遮罩参数画一个缩略界面。
    internal class CherryPreview : Control
    {
        public CherryPreset Preset = CherryPreset.All[0];
        public Image Wallpaper;
        public float FocusX = 0.5f, FocusY = 0.4f;
        public CherryPreview()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }
        private static Color A(Color c, double a) { return Color.FromArgb((int)(Math.Max(0, Math.Min(1, a)) * 255), c); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics; g.SmoothingMode = SmoothingMode.AntiAlias;
            CherryPreset p = Preset;
            Rectangle all = ClientRectangle;
            using (SolidBrush b = new SolidBrush(p.Bg)) g.FillRectangle(b, all);
            if (Wallpaper != null) Ui.DrawCover(g, Wallpaper, all, FocusX, FocusY);
            else
                using (GraphicsPath gp = new GraphicsPath())
                {
                    gp.AddEllipse(all.Width * 0.55f, -all.Height * 0.4f, all.Width * 0.8f, all.Height * 1.1f);
                    using (PathGradientBrush pg = new PathGradientBrush(gp))
                    { pg.CenterColor = A(p.Accent, p.Dark ? 0.22 : 0.16); pg.SurroundColors = new[] { A(p.Accent, 0) }; g.FillPath(pg, gp); }
                }
            Color baseC = p.Dark ? p.Bg : p.Panel;
            double edge = p.Dark ? 0.40 : 0.44, mid = p.Dark ? 0.26 : 0.28, far = p.Dark ? 0.16 : 0.18;
            if (Wallpaper != null)
                using (LinearGradientBrush lg = new LinearGradientBrush(all, Color.Black, Color.Black, 0f))
                {
                    ColorBlend cb = new ColorBlend();
                    cb.Colors = new[] { A(baseC, edge), A(baseC, mid), A(baseC, far), A(baseC, mid) };
                    cb.Positions = new[] { 0f, 0.30f, 0.65f, 1f };
                    lg.InterpolationColors = cb; g.FillRectangle(lg, all);
                }
            float s = all.Width / 760f;
            Color line = p.Dark ? Color.FromArgb(26, 255, 255, 255) : Color.FromArgb(30, 60, 40, 10);
            Rectangle content = new Rectangle((int)(46 * s), (int)(8 * s), all.Width - (int)(54 * s), all.Height - (int)(16 * s));
            using (GraphicsPath cp = Ui.Round(content, (int)(10 * s)))
            using (Pen pen = new Pen(line)) g.DrawPath(pen, cp);
            // 图标栏
            for (int i = 0; i < 5; i++)
                using (SolidBrush b = new SolidBrush(A(p.Text, i == 0 ? 0.75 : 0.30)))
                    g.FillEllipse(b, 16 * s, (20 + i * 34) * s, 14 * s, 14 * s);
            // 话题栏
            Rectangle pane = new Rectangle(content.X + 1, content.Y + 1, (int)(170 * s), content.Height - 2);
            using (SolidBrush b = new SolidBrush(A(p.Panel, p.Dark ? 0.46 : 0.50))) g.FillRectangle(b, pane);
            for (int i = 0; i < 6; i++)
            {
                Rectangle row = new Rectangle(pane.X + (int)(12 * s), pane.Y + (int)((16 + i * 30) * s), pane.Width - (int)(24 * s), (int)(20 * s));
                using (GraphicsPath rp = Ui.Round(row, (int)(5 * s)))
                using (SolidBrush b = new SolidBrush(i == 1 ? A(p.Accent, p.Dark ? 0.20 : 0.16) : A(p.Text, 0.06))) g.FillPath(b, rp);
            }
            // 聊天区
            int cx = pane.Right + (int)(22 * s), cw = content.Right - cx - (int)(22 * s);
            int[] widths = { 92, 70, 84, 40 };
            for (int i = 0; i < widths.Length; i++)
                using (SolidBrush b = new SolidBrush(A(p.Text, 0.55)))
                    g.FillRectangle(b, cx, content.Y + (int)((26 + i * 16) * s), cw * widths[i] / 100, (int)(6 * s));
            Rectangle user = new Rectangle(cx + cw / 3, content.Y + (int)(104 * s), cw * 2 / 3, (int)(34 * s));
            using (GraphicsPath up = Ui.Round(user, (int)(8 * s)))
            using (SolidBrush b = new SolidBrush(A(p.Accent, p.Dark ? 0.16 : 0.12)))
            using (Pen pen = new Pen(A(p.Accent, 0.30))) { g.FillPath(b, up); g.DrawPath(pen, up); }
            Rectangle code = new Rectangle(cx, content.Y + (int)(152 * s), cw, (int)(46 * s));
            using (SolidBrush b = new SolidBrush(p.Dark ? Color.FromArgb(140, 0, 0, 0) : Color.FromArgb(215, 255, 255, 255))) g.FillRectangle(b, code);
            Rectangle comp = new Rectangle(cx - (int)(8 * s), content.Bottom - (int)(60 * s), cw + (int)(16 * s), (int)(44 * s));
            using (GraphicsPath pp = Ui.Round(comp, (int)(12 * s)))
            using (SolidBrush b = new SolidBrush(A(p.Bubble, Wallpaper != null ? 0.44 : 0.80)))
            using (Pen pen = new Pen(A(p.Accent, 0.35))) { g.FillPath(b, pp); g.DrawPath(pen, pp); }
            TextRenderer.DrawText(g, "预览（示意图，实际效果以 Cherry 窗口为准）", Theme.F(8f), new Point(cx, content.Bottom - (int)(48 * s) + 6), A(p.Text, 0.6));
        }
    }

    internal static class Ui
    {
        public static GraphicsPath Round(Rectangle r, int radius)
        {
            GraphicsPath p = new GraphicsPath();
            int d = Math.Max(1, radius * 2);
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
        public static void DrawCover(Graphics g, Image img, Rectangle dst, float fx, float fy)
        {
            float scale = Math.Max((float)dst.Width / img.Width, (float)dst.Height / img.Height);
            float w = dst.Width / scale, h = dst.Height / scale;
            float x = (img.Width - w) * fx, y = (img.Height - h) * fy;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(img, dst, new RectangleF(x, y, w, h), GraphicsUnit.Pixel);
        }
        // 读图不锁文件，并缩到 1280 宽以内，避免预览吃内存。
        public static Image LoadThumb(string path, int maxW)
        {
            byte[] bytes = File.ReadAllBytes(path);
            using (MemoryStream ms = new MemoryStream(bytes))
            using (Image src = Image.FromStream(ms))
            {
                float k = Math.Min(1f, (float)maxW / src.Width);
                Bitmap bmp = new Bitmap(Math.Max(1, (int)(src.Width * k)), Math.Max(1, (int)(src.Height * k)));
                using (Graphics g = Graphics.FromImage(bmp))
                { g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.DrawImage(src, 0, 0, bmp.Width, bmp.Height); }
                return bmp;
            }
        }
    }

    // ---------------------------------------------------------------- 主窗口
    public class MainForm : Form
    {
        private string appRoot;           // 含 src\cherry 的根目录（仓库或释放目录）
        private string pathSource = "";
        private string cherryDir, zcodeDir;
        private readonly string dataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DreamSkin");

        private Panel navPanel, pageCherry, pageZCode, pageEnv;
        private readonly List<FlatButton> navButtons = new List<FlatButton>();
        private RichTextBox log;
        private Label lblNode, lblCherryState, lblZCodeState, lblWallpaper, lblZWallpaper, lblFocus;

        private CherryPreview preview;
        private readonly List<SwatchTile> cherryTiles = new List<SwatchTile>();
        private readonly List<SwatchTile> zcodeTiles = new List<SwatchTile>();
        private TrackBar trkX, trkY;
        private string wallpaperPath = "", zWallpaperPath = "";
        private int cherryPresetIndex = 0, zcodePresetIndex = 0;
        private readonly List<ZCodePreset> zcodePresets = new List<ZCodePreset>();
        private readonly List<Control> busyControls = new List<Control>();

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        public MainForm()
        {
            Text = "Dream Skin 2.0";
            BackColor = Theme.Bg; ForeColor = Theme.Text; Font = Theme.F(9.5f);
            ClientSize = new Size(1120, 740); MinimumSize = new Size(1000, 700);
            StartPosition = FormStartPosition.CenterScreen; DoubleBuffered = true;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            BuildLayout();
            Shown += async (s, e) => await StartupAsync();
            // 把图片直接拖进窗口 = 选壁纸（作用于当前页）。
            AllowDrop = true;
            DragEnter += (s, e) => { if (DroppedImage(e) != null) e.Effect = DragDropEffects.Copy; };
            DragDrop += (s, e) =>
            {
                string f = DroppedImage(e);
                if (f == null) return;
                if (pageZCode.Visible) SetZWallpaper(f); else { ShowPage(0); SetCherryWallpaper(f); }
            };
        }

        private static readonly string[] ImageExts = { ".jpg", ".jpeg", ".png", ".webp" };

        private static bool IsImage(string f)
        {
            return File.Exists(f) && Array.IndexOf(ImageExts, Path.GetExtension(f).ToLowerInvariant()) >= 0;
        }

        private static string DroppedImage(DragEventArgs e)
        {
            string[] files = e.Data.GetData(DataFormats.FileDrop) as string[];
            return files != null && files.Length > 0 && IsImage(files[0]) ? files[0] : null;
        }

        // 命令行：DreamSkin.exe [图片路径] [--page cherry|zcode|env]，也支持把图片拖到 exe 图标上打开。
        public void ApplyArgs(string[] args)
        {
            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--page" && i + 1 < args.Length)
                {
                    string pg = args[++i];
                    ShowPage(pg == "zcode" ? 1 : pg == "env" ? 2 : 0);
                }
                else if (IsImage(args[i])) SetCherryWallpaper(args[i]);
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try { int on = 1; DwmSetWindowAttribute(Handle, 20, ref on, 4); } catch { } // Win11 深色标题栏
        }

        // ------------------------------------------------------------ 布局
        private void BuildLayout()
        {
            navPanel = new Panel { Dock = DockStyle.Left, Width = 210, BackColor = Theme.Nav };
            Controls.Add(navPanel);

            Panel main = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Bg, Padding = new Padding(24, 20, 24, 16) };
            Controls.Add(main);
            main.BringToFront();

            Label brand = new Label { Text = "Dream Skin", Font = Theme.F(17f, FontStyle.Bold), ForeColor = Theme.Gold, AutoSize = true, Location = new Point(22, 22) };
            Label ver = new Label { Text = "2.0 · 双端换肤", Font = Theme.F(9f), ForeColor = Theme.Muted, AutoSize = true, Location = new Point(24, 58) };
            navPanel.Controls.Add(brand); navPanel.Controls.Add(ver);
            string[] names = { "Cherry Studio", "ZCode", "环境与日志" };
            for (int i = 0; i < names.Length; i++)
            {
                int idx = i;
                FlatButton b = new FlatButton(names[i], Theme.Nav, Theme.Text) { Width = 178, Height = 42, Location = new Point(16, 100 + i * 50) };
                b.Tag = "nav";
                b.Click += (s, e) => ShowPage(idx);
                navButtons.Add(b); navPanel.Controls.Add(b);
            }
            lblNode = StatusLabel(navPanel, 560);
            lblCherryState = StatusLabel(navPanel, 588);
            lblZCodeState = StatusLabel(navPanel, 616);
            Label foot = new Label { Text = "不改官方文件 · 随时一键还原", ForeColor = Theme.Muted, Font = Theme.F(8f), AutoSize = true, Location = new Point(22, 680), Anchor = AnchorStyles.Left | AnchorStyles.Bottom };
            navPanel.Controls.Add(foot);

            // 日志固定在底部
            Panel logWrap = new Panel { Dock = DockStyle.Bottom, Height = 150, BackColor = Theme.Bg, Padding = new Padding(0, 10, 0, 0) };
            log = new RichTextBox
            {
                Dock = DockStyle.Fill, ReadOnly = true, BorderStyle = BorderStyle.None, BackColor = Color.FromArgb(10, 10, 13),
                ForeColor = Theme.Muted, Font = new Font("Consolas", 9f), DetectUrls = false, WordWrap = true
            };
            logWrap.Controls.Add(log);
            main.Controls.Add(logWrap);

            pageCherry = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Bg };
            pageZCode = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Bg, Visible = false };
            pageEnv = new Panel { Dock = DockStyle.Fill, BackColor = Theme.Bg, Visible = false };
            main.Controls.Add(pageCherry); main.Controls.Add(pageZCode); main.Controls.Add(pageEnv);
            pageCherry.BringToFront(); pageZCode.BringToFront(); pageEnv.BringToFront();

            BuildCherryPage();
            BuildZCodePage();
            BuildEnvPage();
            ShowPage(0);
        }

        private Label StatusLabel(Control parent, int y)
        {
            Label l = new Label { Text = "", AutoSize = false, Width = 190, Height = 24, Location = new Point(16, y), ForeColor = Theme.Muted, Font = Theme.F(8.5f), Anchor = AnchorStyles.Left | AnchorStyles.Bottom };
            parent.Controls.Add(l);
            return l;
        }

        private void ShowPage(int i)
        {
            pageCherry.Visible = i == 0; pageZCode.Visible = i == 1; pageEnv.Visible = i == 2;
            for (int k = 0; k < navButtons.Count; k++)
            {
                navButtons[k].Fill = k == i ? Theme.CardHover : Theme.Nav;
                navButtons[k].Fore = k == i ? Theme.Gold : Theme.Text;
                navButtons[k].Border = navButtons[k].Fill;
                navButtons[k].Invalidate();
            }
        }

        private Label Heading(Control parent, string title, string sub)
        {
            parent.Controls.Add(new Label { Text = title, Font = Theme.F(15f, FontStyle.Bold), ForeColor = Theme.Text, AutoSize = true, Location = new Point(0, 0) });
            Label l = new Label { Text = sub, Font = Theme.F(9f), ForeColor = Theme.Muted, AutoSize = true, Location = new Point(2, 34) };
            parent.Controls.Add(l);
            return l;
        }

        private FlatButton AddButton(Control parent, string text, Color fill, Color fore, Rectangle r, Func<Task> onClick)
        {
            FlatButton b = new FlatButton(text, fill, fore) { Bounds = r };
            if (fill == Theme.Card) b.Border = Theme.Line;
            b.Click += async (s, e) => { await RunBusy(onClick); };
            parent.Controls.Add(b);
            busyControls.Add(b);
            return b;
        }

        private void BuildCherryPage()
        {
            Heading(pageCherry, "Cherry Studio 换肤", "整窗壁纸 + 磨砂玻璃，原生控件全部保留。由 Dream Skin 启动 Cherry 时生效，关掉即恢复原版。");

            preview = new CherryPreview { Location = new Point(0, 70), Size = new Size(520, 292) };
            pageCherry.Controls.Add(preview);

            lblFocus = new Label { Text = "壁纸焦点", ForeColor = Theme.Muted, AutoSize = true, Location = new Point(0, 376) };
            pageCherry.Controls.Add(lblFocus);
            pageCherry.Controls.Add(new Label { Text = "左右", ForeColor = Theme.Muted, AutoSize = true, Location = new Point(76, 376) });
            trkX = Slider(pageCherry, new Point(110, 370), 50);
            pageCherry.Controls.Add(new Label { Text = "上下", ForeColor = Theme.Muted, AutoSize = true, Location = new Point(300, 376) });
            trkY = Slider(pageCherry, new Point(334, 370), 40);

            Card presets = new Card { Title = "预设风格", Location = new Point(540, 70), Size = new Size(320, 236), Anchor = AnchorStyles.Top | AnchorStyles.Left };
            pageCherry.Controls.Add(presets);
            for (int i = 0; i < CherryPreset.All.Length; i++)
            {
                CherryPreset p = CherryPreset.All[i];
                int idx = i;
                SwatchTile t = new SwatchTile
                {
                    Caption = p.Name, Colors = new[] { p.Bg, p.Panel, p.Bubble, p.Accent }, Size = new Size(92, 84),
                    Location = new Point(14 + (i % 3) * 98, 42 + (i / 3) * 92)
                };
                t.Click += (s, e) => SelectCherryPreset(idx);
                cherryTiles.Add(t); presets.Controls.Add(t);
            }

            Card wp = new Card { Title = "背景壁纸", Location = new Point(540, 316), Size = new Size(320, 96) };
            pageCherry.Controls.Add(wp);
            lblWallpaper = new Label { Text = "未选择（只用配色）· 也可以把图片直接拖进窗口", ForeColor = Theme.Muted, AutoSize = false, Size = new Size(290, 20), Location = new Point(16, 40), AutoEllipsis = true };
            wp.Controls.Add(lblWallpaper);
            FlatButton pick = new FlatButton("选择图片…", Theme.CardHover, Theme.Text) { Bounds = new Rectangle(16, 62, 140, 28) };
            pick.Font = Theme.F(9f); pick.Click += (s, e) => PickCherryWallpaper();
            FlatButton clear = new FlatButton("清除", Theme.CardHover, Theme.Muted) { Bounds = new Rectangle(164, 62, 70, 28) };
            clear.Font = Theme.F(9f); clear.Click += (s, e) => { SetCherryWallpaper(""); };
            wp.Controls.Add(pick); wp.Controls.Add(clear);

            AddButton(pageCherry, "应用皮肤", Theme.Gold, Color.FromArgb(25, 20, 10), new Rectangle(0, 424, 200, 46), ApplyCherry);
            AddButton(pageCherry, "用皮肤启动 Cherry", Theme.Card, Theme.Text, new Rectangle(212, 424, 180, 46), LaunchCherry);
            AddButton(pageCherry, "还原原版外观", Theme.Card, Theme.Text, new Rectangle(404, 424, 150, 46), RestoreCherry);
            AddButton(pageCherry, "创建桌面快捷方式", Theme.Card, Theme.Text, new Rectangle(566, 424, 170, 46), () => RunCherry("shortcut", ""));
            pageCherry.Controls.Add(new Label
            {
                Text = "Cherry 已经开着时会先问你要不要重启一次，聊天记录不受影响。以前在 设置 → 外观 → 自定义 CSS 里写过旧皮肤的，请清空。",
                ForeColor = Theme.Muted, Font = Theme.F(8.5f), AutoSize = false, Size = new Size(860, 22), Location = new Point(0, 480)
            });
            SelectCherryPreset(0);
        }

        private TrackBar Slider(Control parent, Point at, int value)
        {
            TrackBar t = new TrackBar { Minimum = 0, Maximum = 100, Value = value, TickStyle = TickStyle.None, Location = at, Width = 180, BackColor = Theme.Bg };
            t.ValueChanged += (s, e) => { preview.FocusX = trkX.Value / 100f; preview.FocusY = trkY.Value / 100f; preview.Invalidate(); };
            parent.Controls.Add(t);
            return t;
        }

        private void SelectCherryPreset(int i)
        {
            cherryPresetIndex = i;
            for (int k = 0; k < cherryTiles.Count; k++) { cherryTiles[k].Selected = k == i; cherryTiles[k].Invalidate(); }
            preview.Preset = CherryPreset.All[i]; preview.Invalidate();
        }

        private void PickCherryWallpaper()
        {
            using (OpenFileDialog ofd = new OpenFileDialog())
            {
                ofd.Title = "选择背景壁纸"; ofd.Filter = "图片 (*.jpg;*.jpeg;*.png;*.webp)|*.jpg;*.jpeg;*.png;*.webp";
                if (ofd.ShowDialog(this) == DialogResult.OK) SetCherryWallpaper(ofd.FileName);
            }
        }

        private void SetCherryWallpaper(string path)
        {
            wallpaperPath = path;
            Image old = preview.Wallpaper; preview.Wallpaper = null;
            if (old != null) old.Dispose();
            if (path.Length > 0)
            {
                lblWallpaper.Text = Path.GetFileName(path); lblWallpaper.ForeColor = Theme.Gold;
                try { preview.Wallpaper = Ui.LoadThumb(path, 1280); }
                catch { Log("WARN: 这张图预览不了（WebP 需要系统支持），换肤时仍会使用它。"); }
            }
            else { lblWallpaper.Text = "未选择（只用配色）· 也可以把图片直接拖进窗口"; lblWallpaper.ForeColor = Theme.Muted; }
            preview.Invalidate();
        }

        private void BuildZCodePage()
        {
            Heading(pageZCode, "ZCode 换肤", "通过本机调试通道注入，托盘可随时切换或暂停。ZCode 正在运行时需要先正常关闭。");
            Card presets = new Card { Title = "预设风格", Location = new Point(0, 70), Size = new Size(540, 230) };
            pageZCode.Controls.Add(presets);
            presets.Tag = "zpresets";

            Card wp = new Card { Title = "自定义壁纸（可选，覆盖预设图片）", Location = new Point(0, 312), Size = new Size(540, 96), Tag = "zwall" };
            pageZCode.Controls.Add(wp);
            lblZWallpaper = new Label { Text = "未选择（使用预设图片）", ForeColor = Theme.Muted, AutoSize = false, Size = new Size(500, 20), Location = new Point(16, 40), AutoEllipsis = true };
            wp.Controls.Add(lblZWallpaper);
            FlatButton pick = new FlatButton("选择图片…", Theme.CardHover, Theme.Text) { Bounds = new Rectangle(16, 62, 140, 28) };
            pick.Font = Theme.F(9f);
            pick.Click += (s, e) =>
            {
                using (OpenFileDialog ofd = new OpenFileDialog())
                {
                    ofd.Filter = "图片 (*.jpg;*.jpeg;*.png;*.webp)|*.jpg;*.jpeg;*.png;*.webp";
                    if (ofd.ShowDialog(this) == DialogResult.OK) SetZWallpaper(ofd.FileName);
                }
            };
            FlatButton clear = new FlatButton("清除", Theme.CardHover, Theme.Muted) { Bounds = new Rectangle(164, 62, 70, 28) };
            clear.Font = Theme.F(9f);
            clear.Click += (s, e) => { zWallpaperPath = ""; lblZWallpaper.Text = "未选择（使用预设图片）"; lblZWallpaper.ForeColor = Theme.Muted; };
            wp.Controls.Add(pick); wp.Controls.Add(clear);

            AddButton(pageZCode, "启动 ZCode 换肤", Theme.Blue, Color.White, new Rectangle(560, 70, 200, 48), LaunchZCode);
            AddButton(pageZCode, "还原 ZCode 原版", Theme.Card, Theme.Text, new Rectangle(560, 128, 200, 40), RestoreZCode);
            AddButton(pageZCode, "打开 ZCode 状态目录", Theme.Card, Theme.Text, new Rectangle(560, 178, 200, 40), () =>
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ZCodeDreamSkin");
                if (Directory.Exists(dir)) Process.Start("explorer.exe", "\"" + dir + "\"");
                else Log("还没有 ZCode 状态目录（还没启动过 ZCode 换肤）。");
                return Task.FromResult(0);
            });
        }

        private void SetZWallpaper(string f)
        {
            zWallpaperPath = f; lblZWallpaper.Text = Path.GetFileName(f); lblZWallpaper.ForeColor = Theme.Gold;
        }

        private static readonly Dictionary<string, string> ZhNames = new Dictionary<string, string>
        {
            { "zds2-tech", "蓝绿科技" }, { "zds2-glass", "深邃玻璃" }, { "zds2-cream", "柔和奶油" }, { "preset-gothic-void-crusade", "哥特虚空" }
        };

        private void LoadZCodePresets()
        {
            zcodePresets.Clear();
            Control host = null;
            foreach (Control c in pageZCode.Controls) if ((c.Tag as string) == "zpresets") host = c;
            if (host == null || zcodeDir == null) return;
            foreach (Control c in new List<Control>(zcodeTiles)) { host.Controls.Remove(c); c.Dispose(); }
            zcodeTiles.Clear();
            string presetRoot = Path.Combine(Path.GetDirectoryName(zcodeDir), "presets");
            if (!Directory.Exists(presetRoot)) return;
            foreach (string dir in Directory.GetDirectories(presetRoot))
            {
                string json = Path.Combine(dir, "theme.json");
                if (!File.Exists(json)) continue;
                string text = File.ReadAllText(json);
                ZCodePreset p = new ZCodePreset { Dir = dir, Id = Path.GetFileName(dir) };
                Match m = Regex.Match(text, "\"name\"\\s*:\\s*\"([^\"]+)\"");
                p.Name = m.Success ? m.Groups[1].Value : p.Id;
                string zh;
                if (ZhNames.TryGetValue(p.Id, out zh)) p.Name = zh;
                Match im = Regex.Match(text, "\"image\"\\s*:\\s*\"([^\"]+)\"");
                p.Image = Path.Combine(dir, im.Success ? im.Groups[1].Value : "background.png");
                zcodePresets.Add(p);
            }
            for (int i = 0; i < zcodePresets.Count; i++)
            {
                int idx = i;
                SwatchTile t = new SwatchTile { Caption = zcodePresets[i].Name, Size = new Size(124, 110), Location = new Point(14 + (i % 4) * 128, 42 + (i / 4) * 118) };
                string img = zcodePresets[i].Image;
                if (File.Exists(img)) { try { t.Thumb = Ui.LoadThumb(img, 320); } catch { } }
                t.Click += (s, e) => SelectZCodePreset(idx);
                zcodeTiles.Add(t); host.Controls.Add(t);
            }
            host.Height = 42 + Math.Max(1, (zcodePresets.Count + 3) / 4) * 118 + 8;
            foreach (Control c in pageZCode.Controls) if ((c.Tag as string) == "zwall") c.Top = host.Bottom + 12;
            if (zcodePresets.Count > 0) SelectZCodePreset(0);
        }

        private void SelectZCodePreset(int i)
        {
            zcodePresetIndex = i;
            for (int k = 0; k < zcodeTiles.Count; k++) { zcodeTiles[k].Selected = k == i; zcodeTiles[k].Invalidate(); }
        }

        private void BuildEnvPage()
        {
            Heading(pageEnv, "环境与日志", "检查运行环境、打开数据目录、导出日志。");
            AddButton(pageEnv, "安装 / 修复 Node.js 22", Theme.Card, Theme.Text, new Rectangle(0, 70, 240, 40), InstallNode);
            AddButton(pageEnv, "重新检测环境", Theme.Card, Theme.Text, new Rectangle(0, 120, 240, 40), RefreshStatus);
            AddButton(pageEnv, "打开 Dream Skin 数据目录", Theme.Card, Theme.Text, new Rectangle(0, 170, 240, 40), () =>
            {
                Directory.CreateDirectory(dataRoot);
                Process.Start("explorer.exe", "\"" + dataRoot + "\"");
                return Task.FromResult(0);
            });
            AddButton(pageEnv, "复制日志", Theme.Card, Theme.Text, new Rectangle(260, 70, 160, 40), () =>
            {
                if (log.TextLength > 0) Clipboard.SetText(log.Text);
                Log("日志已复制到剪贴板。");
                return Task.FromResult(0);
            });
            AddButton(pageEnv, "清空日志", Theme.Card, Theme.Text, new Rectangle(260, 120, 160, 40), () => { log.Clear(); return Task.FromResult(0); });
            pageEnv.Controls.Add(new Label
            {
                Text = "说明：\n· Node.js 22+ 是运行换肤脚本必需的；没装的话点上面的按钮，会从 nodejs.org 下载官方版本并校验 SHA-256，装在 Dream Skin 自己的目录里，不影响系统。\n· 数据目录里有当前皮肤、上次选择和会话状态，删掉等于重置。",
                ForeColor = Theme.Muted, AutoSize = false, Size = new Size(640, 120), Location = new Point(0, 230)
            });
        }

        // ------------------------------------------------------------ 日志与忙碌状态
        private void Log(string msg)
        {
            if (log.InvokeRequired) { log.BeginInvoke(new Action(() => Log(msg))); return; }
            foreach (string raw in msg.Replace("\r", "").Split('\n'))
            {
                if (raw.Trim().Length == 0) continue;
                Color c = Theme.Muted;
                if (raw.StartsWith("SUCCESS")) c = Theme.Green;
                else if (raw.StartsWith("FAILED") || raw.StartsWith("ERROR")) c = Theme.Red;
                else if (raw.StartsWith("UNCERTAIN") || raw.StartsWith("NEEDS_RESTART") || raw.StartsWith("WARN")) c = Theme.Yellow;
                log.SelectionStart = log.TextLength; log.SelectionColor = Color.FromArgb(90, 90, 100);
                log.AppendText(DateTime.Now.ToString("HH:mm:ss") + "  ");
                log.SelectionStart = log.TextLength; log.SelectionColor = c;
                log.AppendText(raw + "\n");
            }
            log.ScrollToCaret();
        }

        private async Task RunBusy(Func<Task> work)
        {
            foreach (Control c in busyControls) c.Enabled = false;
            UseWaitCursor = true;
            try { await work(); }
            catch (Exception ex)
            {
                Log("ERROR: " + ex.Message);
                try { Directory.CreateDirectory(dataRoot); File.AppendAllText(Path.Combine(dataRoot, "gui-error.log"), DateTime.Now.ToString("o") + " " + ex + "\r\n"); } catch { }
            }
            finally
            {
                foreach (Control c in busyControls) c.Enabled = true;
                UseWaitCursor = false;
            }
        }

        // ------------------------------------------------------------ 启动：定位/释放脚本、检测环境
        private async Task StartupAsync()
        {
            await RunBusy(async () =>
            {
                await Task.Run(() => ResolveAppRoot());
                if (appRoot == null) { Log("ERROR: 找不到换肤脚本，也没有内置资源。请重新下载 DreamSkin.exe。"); return; }
                cherryDir = Path.Combine(appRoot, "src", "cherry");
                zcodeDir = Path.Combine(appRoot, "src", "zcode", "payload", "scripts");
                Log("脚本目录：" + appRoot + "（" + pathSource + "）");
                LoadZCodePresets();
                await RefreshStatus();
            });
        }

        // 顺序：DREAMSKIN_ROOT → exe 所在位置向上找仓库 → 内置 payload.zip 释放。
        private void ResolveAppRoot()
        {
            string env = Environment.GetEnvironmentVariable("DREAMSKIN_ROOT");
            if (!string.IsNullOrEmpty(env) && File.Exists(Path.Combine(env, "src", "cherry", "skin-cherry.mjs"))) { appRoot = env; pathSource = "环境变量 DREAMSKIN_ROOT"; return; }
            DirectoryInfo dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            for (int i = 0; i < 6 && dir != null; i++)
            {
                if (File.Exists(Path.Combine(dir.FullName, "src", "cherry", "skin-cherry.mjs"))) { appRoot = dir.FullName; pathSource = "仓库源码"; return; }
                dir = dir.Parent;
            }
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("DreamSkin.payload.zip"))
            {
                if (s == null) return;
                byte[] bytes;
                using (MemoryStream ms = new MemoryStream()) { s.CopyTo(ms); bytes = ms.ToArray(); }
                string hash;
                using (SHA256 sha = SHA256.Create()) hash = BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").Substring(0, 12).ToLowerInvariant();
                string target = Path.Combine(dataRoot, "app", hash);
                string marker = Path.Combine(target, ".complete");
                if (!File.Exists(marker))
                {
                    Log("首次运行，正在释放内置文件…");
                    string tmp = target + ".tmp";
                    if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
                    Directory.CreateDirectory(tmp);
                    using (MemoryStream ms = new MemoryStream(bytes))
                    using (ZipArchive zip = new ZipArchive(ms, ZipArchiveMode.Read))
                    {
                        string full = Path.GetFullPath(tmp) + Path.DirectorySeparatorChar;
                        foreach (ZipArchiveEntry entry in zip.Entries)
                        {
                            string dest = Path.GetFullPath(Path.Combine(tmp, entry.FullName.Replace('/', Path.DirectorySeparatorChar)));
                            if (!dest.StartsWith(full, StringComparison.OrdinalIgnoreCase)) continue; // 防路径穿越
                            if (entry.FullName.EndsWith("/")) { Directory.CreateDirectory(dest); continue; }
                            Directory.CreateDirectory(Path.GetDirectoryName(dest));
                            entry.ExtractToFile(dest, true);
                        }
                    }
                    if (Directory.Exists(target)) Directory.Delete(target, true);
                    Directory.Move(tmp, target);
                    File.WriteAllText(marker, DateTime.Now.ToString("o"));
                }
                appRoot = target; pathSource = "内置资源";
            }
        }

        private string NodeRuntimeDir { get { return Path.Combine(dataRoot, "runtime", "node"); } }

        private string ResolveNode()
        {
            string local = Path.Combine(NodeRuntimeDir, "node.exe");
            return File.Exists(local) ? local : "node.exe";
        }

        private async Task<int> NodeMajor()
        {
            ProcResult r = await RunProcess(ResolveNode(), "-v", 15000);
            Match m = Regex.Match(r.Output, @"v(\d+)\.");
            return m.Success ? int.Parse(m.Groups[1].Value) : 0;
        }

        private async Task RefreshStatus()
        {
            int major = await NodeMajor();
            SetState(lblNode, major >= 22 ? "● Node.js v" + major : (major > 0 ? "● Node.js 版本太旧" : "● 未找到 Node.js"), major >= 22 ? Theme.Green : Theme.Red);
            if (major < 22) { Log("WARN: 需要 Node.js 22 或更新版本。到「环境与日志」点「安装 / 修复 Node.js 22」即可。"); return; }
            if (cherryDir == null) return;
            ProcResult st = await RunProcess(ResolveNode(), Q(Path.Combine(cherryDir, "skin-cherry.mjs")) + " status", 30000);
            bool running = st.Output.Contains("\"cherryRunning\": true");
            bool skin = running && st.Output.Contains("\"skinActive\": true") && Regex.IsMatch(st.Output, "\"debugPort\": [1-9]");
            bool found = !st.Output.Contains("\"cherryExe\": null");
            SetState(lblCherryState, !found ? "● Cherry 未安装/未找到" : (skin ? "● Cherry 皮肤生效中" : (running ? "● Cherry 运行中（原版）" : "● Cherry 未运行")),
                !found ? Theme.Red : (skin ? Theme.Gold : Theme.Muted));
            bool zcode = Process.GetProcessesByName("ZCode").Length > 0;
            SetState(lblZCodeState, zcode ? "● ZCode 运行中" : "● ZCode 未运行", Theme.Muted);
        }

        private void SetState(Label l, string text, Color c)
        {
            if (l.InvokeRequired) { l.BeginInvoke(new Action(() => SetState(l, text, c))); return; }
            l.Text = text; l.ForeColor = c;
        }

        private static string Q(string s) { return "\"" + s + "\""; }

        // ------------------------------------------------------------ Cherry 动作
        private Task ApplyCherry()
        {
            string args = "--preset " + CherryPreset.All[cherryPresetIndex].Key + " --focus-x " + trkX.Value + " --focus-y " + trkY.Value;
            if (wallpaperPath.Length > 0 && File.Exists(wallpaperPath)) args += " --image " + Q(wallpaperPath);
            Log("应用 [" + CherryPreset.All[cherryPresetIndex].Name + "]" + (wallpaperPath.Length > 0 ? " + 壁纸" : "") + " …");
            return RunCherry("apply", args);
        }

        private Task LaunchCherry() { Log("用上次的皮肤启动 Cherry…"); return RunCherry("launch", ""); }

        private async Task RestoreCherry() { Log("还原 Cherry 原版外观…"); await RunCherry("restore", ""); }

        private async Task RunCherry(string cmd, string args)
        {
            if (cherryDir == null) { Log("ERROR: 脚本目录未就绪。"); return; }
            if (await NodeMajor() < 22) { Log("FAILED: 需要 Node.js 22+，请先在「环境与日志」里安装。"); return; }
            string script = Q(Path.Combine(cherryDir, "skin-cherry.mjs"));
            ProcResult r = await RunProcess(ResolveNode(), script + " " + cmd + " " + args, 180000);
            Log(r.Output);
            if (r.ExitCode == 3)
            {
                DialogResult ok = MessageBox.Show(this,
                    "Cherry Studio 正在运行，需要由 Dream Skin 重新启动一次才能换肤。\n\n聊天记录不受影响，但输入框里没发出去的文字会丢失。\n\n现在重启 Cherry Studio 吗？",
                    "需要重启 Cherry Studio", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (ok != DialogResult.Yes) { Log("已取消。"); return; }
                Log("正在重启 Cherry 并应用皮肤（约 10–30 秒）…");
                r = await RunProcess(ResolveNode(), script + " " + cmd + " " + args + " --restart", 180000);
                Log(r.Output);
            }
            if (r.ExitCode == 0 && cmd == "apply") OfferShortcut(script);
            await RefreshStatus();
        }

        private async void OfferShortcut(string script)
        {
            string lnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Cherry Studio (Dream Skin).lnk");
            if (File.Exists(lnk)) return;
            if (MessageBox.Show(this, "要在桌面创建「Cherry Studio (Dream Skin)」快捷方式吗？\n\n以后用它打开 Cherry 会自动带上皮肤；用原来的图标打开就是原版。",
                "创建快捷方式", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return;
            ProcResult r = await RunProcess(ResolveNode(), script + " shortcut", 30000);
            Log(r.Output);
        }

        // ------------------------------------------------------------ ZCode 动作
        private async Task LaunchZCode()
        {
            if (zcodeDir == null) return;
            string ps1 = Path.Combine(zcodeDir, "start-zcode-dream-skin.ps1");
            if (!File.Exists(ps1)) { Log("ERROR: 未找到 " + ps1); return; }
            string extra = "";
            if (zcodePresets.Count > 0)
            {
                ZCodePreset p = zcodePresets[zcodePresetIndex];
                string art = zWallpaperPath.Length > 0 ? zWallpaperPath : p.Image;
                extra = " -ThemePath " + PsQ(Path.Combine(p.Dir, "theme.json")) + " -ArtPath " + PsQ(art);
                Log("启动 ZCode 换肤 [" + p.Name + "]" + (zWallpaperPath.Length > 0 ? " + 自定义壁纸" : "") + "，约 10–60 秒…");
            }
            ProcResult r = await RunProcess("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[Text.Encoding]::UTF8; & " + PsQ(ps1) + extra + "; exit $LASTEXITCODE\"", 300000);
            Log(r.Output);
            Log(r.ExitCode == 0 ? "SUCCESS: ZCode 换肤已启动，托盘区有 Dream Skin 图标可切换/暂停。" : "FAILED: ZCode 换肤没有完成（exit " + r.ExitCode + "）。详情见 ZCode 状态目录里的 last-startup-report.json。");
            await RefreshStatus();
        }

        private async Task RestoreZCode()
        {
            if (zcodeDir == null) return;
            string ps1 = Path.Combine(zcodeDir, "restore-zcode-dream-skin.ps1");
            if (!File.Exists(ps1)) { Log("ERROR: 未找到 " + ps1); return; }
            Log("还原 ZCode 原版外观…");
            ProcResult r = await RunProcess("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -Command \"[Console]::OutputEncoding=[Text.Encoding]::UTF8; & " + PsQ(ps1) + "; exit $LASTEXITCODE\"", 180000);
            Log(r.Output);
            Log(r.ExitCode == 0 ? "SUCCESS: ZCode 已还原。" : "FAILED: ZCode 还原未完成（exit " + r.ExitCode + "）。");
        }

        private static string PsQ(string s) { return "'" + s.Replace("'", "''") + "'"; }

        // ------------------------------------------------------------ Node 安装（官方 zip + SHA-256 校验）
        private async Task InstallNode()
        {
            Log("从 nodejs.org 获取 Node.js 22 最新版本信息…");
            await Task.Run(() =>
            {
                ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; // TLS 1.2
                string baseUrl = "https://nodejs.org/dist/latest-v22.x/";
                using (WebClient wc = new WebClient())
                {
                    string sums = wc.DownloadString(baseUrl + "SHASUMS256.txt");
                    Match m = Regex.Match(sums, @"([0-9a-f]{64})\s+(node-v22\.[0-9.]+-win-x64\.zip)");
                    if (!m.Success) throw new Exception("没在 SHASUMS256.txt 里找到 win-x64 安装包。");
                    string file = m.Groups[2].Value, expected = m.Groups[1].Value;
                    Log("下载 " + file + " …");
                    string tmpZip = Path.Combine(Path.GetTempPath(), file);
                    wc.DownloadFile(baseUrl + file, tmpZip);
                    string actual;
                    using (FileStream fs = File.OpenRead(tmpZip)) using (SHA256 sha = SHA256.Create())
                        actual = BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "").ToLowerInvariant();
                    if (actual != expected) { File.Delete(tmpZip); throw new Exception("SHA-256 校验失败，已删除下载文件。"); }
                    string runtimeRoot = Path.GetDirectoryName(NodeRuntimeDir);
                    Directory.CreateDirectory(runtimeRoot);
                    string extractTo = Path.Combine(runtimeRoot, "extract-tmp");
                    if (Directory.Exists(extractTo)) Directory.Delete(extractTo, true);
                    ZipFile.ExtractToDirectory(tmpZip, extractTo);
                    string inner = Directory.GetDirectories(extractTo)[0];
                    if (Directory.Exists(NodeRuntimeDir)) Directory.Delete(NodeRuntimeDir, true);
                    Directory.Move(inner, NodeRuntimeDir);
                    Directory.Delete(extractTo, true);
                    File.Delete(tmpZip);
                    Log("SUCCESS: Node.js 已安装到 " + NodeRuntimeDir + "（SHA-256 校验通过）。");
                }
            });
            await RefreshStatus();
        }

        // ------------------------------------------------------------ 子进程
        private class ProcResult { public string Output = ""; public int ExitCode = -1; }

        private Task<ProcResult> RunProcess(string exe, string args, int timeoutMs)
        {
            return Task.Run(() =>
            {
                ProcResult res = new ProcResult();
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = exe, Arguments = args, UseShellExecute = false, CreateNoWindow = true,
                        RedirectStandardOutput = true, RedirectStandardError = true,
                        StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
                    };
                    // 让 ZCode 脚本（按 PATH 找 node，并校验官方签名）也能用到我们装的 Node。
                    if (File.Exists(Path.Combine(NodeRuntimeDir, "node.exe")))
                        psi.EnvironmentVariables["PATH"] = NodeRuntimeDir + ";" + psi.EnvironmentVariables["PATH"];
                    using (Process p = new Process())
                    {
                        p.StartInfo = psi;
                        StringBuilder outBuf = new StringBuilder(), errBuf = new StringBuilder();
                        p.OutputDataReceived += (s, e) => { if (e.Data != null) lock (outBuf) outBuf.AppendLine(e.Data); };
                        p.ErrorDataReceived += (s, e) => { if (e.Data != null) lock (errBuf) errBuf.AppendLine(e.Data); };
                        p.Start(); p.BeginOutputReadLine(); p.BeginErrorReadLine();
                        if (!p.WaitForExit(timeoutMs))
                        {
                            try { p.Kill(); } catch { }
                            res.Output = "UNCERTAIN: 子进程超时被终止。\n" + outBuf + errBuf;
                            return res;
                        }
                        p.WaitForExit();
                        res.ExitCode = p.ExitCode;
                        res.Output = outBuf.ToString() + (errBuf.Length > 0 ? "\n" + errBuf : "");
                    }
                }
                catch (System.ComponentModel.Win32Exception)
                {
                    res.Output = exe == "node.exe" ? "" : "ERROR: 无法启动 " + exe;
                }
                catch (Exception ex) { res.Output = "ERROR: " + ex.Message; }
                return res;
            });
        }

        [STAThread]
        public static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            MainForm f = new MainForm();
            f.Load += (s, e) => f.ApplyArgs(args);
            Application.Run(f);
        }
    }
}
