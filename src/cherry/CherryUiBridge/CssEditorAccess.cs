using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace CherryUiBridge;

// 定位并读写官方外观编辑器。只有「安装身份可核对」且「窗口与控件唯一」才返回目标；
// 任何歧义都在动手输入之前退回分阶段的 blocked。
public static class CssEditorAccess
{
    public const int MaxGeneratedCssBytes = 2 * 1024 * 1024;
    private const int FullTextNoLimit = -1;

    // 首版候选线索。真实身份与控件名必须由 -Native 门现场量出来：
    // 对不上就 control_not_found，多了就 ambiguous_control，绝不猜一个用。
    private static readonly string[] ProcessNames = { "Cherry Studio" };
    private static readonly Regex EditorHint = new("custom.?css|自定义\\s*css|css", RegexOptions.IgnoreCase);

    public static Target? Locate(AutomationBase automation, JsonElement identity, out string stage, out string reason)
    {
        stage = "identity";
        reason = "";
        var expectedExeSha = Text(identity, "expectedExeSha256");
        var expectedVersion = Text(identity, "clientVersion");
        if (expectedExeSha.Length != 64 || expectedVersion.Length == 0)
        {
            reason = "expectedExeSha256 and clientVersion are required";
            return null;
        }

        // Electron 的一份实例会带一串同名同 exe 的子进程（渲染、GPU、工具进程），它们没有顶层窗口。
        // 按进程数判「多个主窗口」会把正常单实例读成歧义，所以裁决权交给「谁真的有命名顶层窗口」。
        var processes = ProcessNames
            .SelectMany((name) => Process.GetProcessesByName(name))
            .ToArray();
        if (processes.Length == 0)
        {
            stage = "find-window";
            reason = "window_not_found";
            return null;
        }
        var owners = new List<(Process Process, Window[] Windows)>();
        // 「找不到窗口」这一格在真实机器上有好几种成因：进程列表空、Attach 全抛、窗口有但名字空、
        // 或 UIA 树根本枚举不出顶层窗。以前它们全压成同一个词，只能靠猜。这里把计数带出来
        // （只报数量与不报标题内容，标题可能带用户输入），词首仍是原来那个令牌，比对不受影响。
        var topTotal = 0;
        var unnamed = 0;
        var attachErrors = 0;
        var errorKind = "";
        var errorMessage = "";
        foreach (var candidate in processes)
        {
            Window[] top;
            try
            {
                // 不用 FlaUI 的 Application.Attach()：它那一句调试日志走 WMI（WindowsApiTools
                // .GetMainModuleFilepath → ManagementObjectSearcher），需要 System.Management 装配，
                // 而桥不随件那枚依赖（也不该为了一句日志引它）。真窗口量到的就是每一次 Attach 都抛
                // FileNotFoundException，然后被这里盖成「找不到窗口」——一种成因伪装成另一种。
                // 改用 FlaUI 自己的桌面枚举：同一套 UIA 条件（ControlType.Window + 本进程 PID），
                // 不碰 WMI、不加依赖。
                top = automation.GetDesktop()
                    .FindAllChildren(cf => cf.ByControlType(ControlType.Window).And(cf.ByProcessId(candidate.Id)))
                    .Select((w) => w.AsWindow())
                    .ToArray();
            }
            catch (Exception e)
            {
                // 已退出、无权限、拿不到窗口：这些进程都不是主窗口的拥有者，不算歧义。
                attachErrors += 1;
                errorKind = e.GetType().Name;
                // 光有异常类型名定不了因：装配加载失败、访问被拒、UIA 树空 都叫同一个名字。
                if (errorMessage.Length == 0)
                {
                    errorMessage = (e.InnerException is null ? "" : e.InnerException.GetType().Name + ": ")
                        + (e.Message ?? "").Replace('\n', ' ').Replace('\r', ' ');
                    if (errorMessage.Length > 160) { errorMessage = errorMessage.Substring(0, 160); }
                }
                continue;
            }
            topTotal += top.Length;
            Window[] named;
            try
            {
                named = top.Where((w) =>
                {
                    try { return !string.IsNullOrWhiteSpace(w.Name); }
                    catch { return false; }
                }).ToArray();
            }
            catch (Exception e)
            {
                attachErrors += 1;
                errorKind = e.GetType().Name;
                continue;
            }
            unnamed += top.Length - named.Length;
            if (named.Length > 0) owners.Add((candidate, named));
        }
        stage = "find-window";
        if (owners.Count == 0)
        {
            reason = "window_not_found processes=" + processes.Length
                + " topWindows=" + topTotal + " unnamed=" + unnamed
                + " attachErrors=" + attachErrors + (errorKind.Length > 0 ? " firstError=" + errorKind : "")
                + (errorMessage.Length > 0 ? " detail=" + errorMessage : "");
            return null;
        }
        if (owners.Count > 1)
        {
            reason = "ambiguous_window";
            return null;
        }

        var (process2, namedWindows) = owners[0];
        // 「只有一个命名顶层窗」不是真话：官方那份是 Electron，主窗之外还带一个同样有标题的
        // 隐藏辅助窗（本机量到两个 Chrome_WidgetWin_1，一个 13 字符标题一个 9 字符）。按窗数量判歧义
        // 会让一台完全正常的宿主永远跑不起来，还把真正该判的那件事挡在前面。
        // 权威改成控件唯一：所有命名顶层窗里，对得上编辑器线索的控件必须恰好一个
        // ——0 个是 control_not_found，多了是 ambiguous_control，一律在动手输入之前退回。

        string exePath;
        try
        {
            exePath = process2.MainModule?.FileName ?? "";
        }
        catch (Exception)
        {
            reason = "exe_identity";
            return null;
        }
        if (exePath.Length == 0)
        {
            reason = "exe_identity";
            return null;
        }
        var exeSha = Sha256File(exePath);
        if (exeSha != expectedExeSha)
        {
            reason = "exe_identity";
            return null;
        }
        var productVersion = FileVersionInfo.GetVersionInfo(exePath).ProductVersion ?? "";
        if (!productVersion.StartsWith(expectedVersion, StringComparison.Ordinal))
        {
            reason = "version_mismatch";
            return null;
        }

        AutomationElement[] edits;
        AutomationElement[] documents;
        try
        {
            edits = namedWindows.SelectMany((w) => w.FindAllDescendants(cf => cf.ByControlType(ControlType.Edit))).ToArray();
            documents = namedWindows.SelectMany((w) => w.FindAllDescendants(cf => cf.ByControlType(ControlType.Document))).ToArray();
        }
        catch (Exception e)
        {
            stage = "find-control";
            reason = "control enumeration failed: " + e.GetType().Name;
            return null;
        }
        var matches = edits.Concat(documents).Where((e) =>
        {
            try { return EditorHint.IsMatch(e.Name ?? "") || EditorHint.IsMatch(e.AutomationId ?? ""); }
            catch { return false; }
        }).ToArray();
        stage = "find-control";
        if (matches.Length == 0)
        {
            reason = "control_not_found";
            return null;
        }
        if (matches.Length > 1)
        {
            reason = "ambiguous_control";
            return null;
        }
        return new Target(matches[0], new Dictionary<string, object?>
        {
            ["clientVersion"] = expectedVersion,
            ["exeSha256"] = exeSha,
            ["expectedExeSha256"] = expectedExeSha,
            ["mainWindowCount"] = namedWindows.Length,
            ["cssEditorCount"] = matches.Length,
        });
    }

    private static string Text(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() ?? "" : "";

    private static string Sha256File(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    public sealed record Snapshot(string Text, string Channel);

    public sealed class Target
    {
        private readonly AutomationElement _element;
        public IReadOnlyDictionary<string, object?> Identity { get; }

        public Target(AutomationElement element, Dictionary<string, object?> identity)
        {
            _element = element;
            Identity = identity;
        }

        // 完整原文优先 TextPattern.DocumentRange.GetText(-1)。ValuePattern 的 Value 会把换行压平，
        // 只当兜底，并把通道名如实写出来，绝不冒充「原样」。
        public Snapshot? ReadFullText()
        {
            if (TryText(FullTextNoLimit, out var minus1)) return new Snapshot(minus1!, "textpattern-gettext-minus1");
            if (TryText(int.MaxValue, out var max)) return new Snapshot(max!, "textpattern-gettext-maxvalue");
            try
            {
                if (_element.Patterns.Value.TryGetPattern(out var value))
                {
                    var text = value.Value.Value ?? "";
                    return new Snapshot(text, "valuepattern-flattens-newlines");
                }
            }
            catch (Exception)
            {
                // 通道不存在或读失败：交给上层按 blocked/indeterminate 处理，不编造空 CSS。
            }
            return null;
        }

        // 第二个证人：ValuePattern 报的字符数（换行会被它压平，所以同样按去掉换行计）。
        // TextPattern 只交出一片时这个数字对不上——自报自证证不了全文。
        public int? ValueTextChars()
        {
            try
            {
                if (!_element.Patterns.Value.TryGetPattern(out var value)) return null;
                var text = (value.Value.Value ?? "").Replace("\r", "").Replace("\n", "");
                return text.EnumerateRunes().Count();
            }
            catch (Exception)
            {
                return null;
            }
        }

        public bool TryWriteText(string text, out string error)
        {
            error = "";
            try
            {
                if (!_element.Patterns.Value.TryGetPattern(out var value))
                {
                    error = "valuepattern_unavailable";
                    return false;
                }
                if (value.IsReadOnly.Value)
                {
                    error = "valuepattern_readonly";
                    return false;
                }
                value.SetValue(text);
                return true;
            }
            catch (Exception e)
            {
                error = "write_failed: " + e.GetType().Name;
                return false;
            }
        }

        private bool TryText(int maxLength, out string? text)
        {
            text = null;
            try
            {
                if (!_element.Patterns.Text.TryGetPattern(out var pattern)) return false;
                text = pattern.DocumentRange.GetText(maxLength);
                return !string.IsNullOrEmpty(text);
            }
            catch (Exception)
            {
                return false;
            }
        }
    }
}
