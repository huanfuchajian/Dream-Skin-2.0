using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CherryUiBridge;

// 短时 UIA 桥：一条 UTF8 JSON 请求进 stdin，一条 JSON 答复出 stdout。
// 原文 CSS 只写进本地受限工件，stdout 只带 metadata / hash / 状态。
public static class Program
{
    public static void Main()
    {
        Console.InputEncoding = new UTF8Encoding(false);
        Console.OutputEncoding = new UTF8Encoding(false);
        var requestId = "";
        try
        {
            var line = Console.ReadLine();
            if (string.IsNullOrWhiteSpace(line))
            {
                Answer(requestId, "blocked", "read-request", "stdin carries no request");
                return;
            }
            using var doc = JsonDocument.Parse(line);
            var req = doc.RootElement;
            requestId = Text(req, "requestId");
            if (requestId.Length == 0)
            {
                Answer(requestId, "blocked", "read-request", "requestId is required");
                return;
            }
            Run(req, requestId);
        }
        catch (JsonException)
        {
            Answer(requestId, "blocked", "read-request", "request is not valid json");
        }
        catch (Exception e)
        {
            // 未预期异常是 indeterminate：既不能说「没改成」，也不能说「改好了」。
            Answer(requestId, "indeterminate", "unexpected", Cut(e.Message));
        }
    }

    // 每个动作必须带哪些字段写在这一张表上，并且在碰任何窗口之前校验：先 Locate 的话，
    // 「请求里少了一个参数」会被「找不到窗口」盖住，两种语言各说一套也照不出红。
    private static readonly Dictionary<string, (string[] Fields, string Stage)> RequestShape = new()
    {
        ["readCss"] = (new[] { "cssFile" }, "read-css"),
        ["compareAndSetCss"] = (new[] { "expectedCurrentSha256", "newCssFile", "newCssSha256" }, "compare"),
    };

    private static void Run(JsonElement req, string requestId)
    {
        var action = Text(req, "action");
        if (!RequestShape.TryGetValue(action, out var shape))
        {
            Answer(requestId, "blocked", "dispatch", "unknown action: " + Cut(action, 40));
            return;
        }
        var missing = shape.Fields.Where((f) => Text(req, f).Length == 0).ToArray();
        if (missing.Length > 0)
        {
            Answer(requestId, "blocked", shape.Stage, string.Join(", ", missing) + " is required");
            return;
        }
        if (!req.TryGetProperty("expectedClientIdentity", out var identity)
            || identity.ValueKind != JsonValueKind.Object)
        {
            Answer(requestId, "blocked", "identity", "expectedClientIdentity is required");
            return;
        }
        using var automation = new FlaUI.UIA3.UIA3Automation();
        var target = CssEditorAccess.Locate(automation, identity, out var stage, out var reason);
        if (target is null)
        {
            Answer(requestId, "blocked", stage, reason);
            return;
        }
        switch (action)
        {
            case "readCss":
                DoRead(target, requestId, Text(req, "cssFile"));
                return;
            case "compareAndSetCss":
                DoCompareAndSet(target, requestId, req);
                return;
        }
    }

    private static void DoRead(CssEditorAccess.Target target, string requestId, string cssFile)
    {
        var read = target.ReadFullText();
        if (read is null)
        {
            Answer(requestId, "blocked", "read-css", "no raw UIA text channel is available");
            return;
        }
        var bytes = new UTF8Encoding(false).GetBytes(read.Text);
        File.WriteAllBytes(cssFile, bytes);
        Answer(requestId, "verified", "read-css", null, new Dictionary<string, object?>
        {
            ["cssFile"] = cssFile,
            ["lengthChars"] = CodePoints(read.Text),
            ["utf8Bytes"] = bytes.Length,
            ["sha256"] = Hex(bytes),
            ["readChannel"] = read.Channel,
            ["valuePatternChars"] = target.ValueTextChars(),
            ["identity"] = target.Identity,
        });
    }

    private static void DoCompareAndSet(CssEditorAccess.Target target, string requestId, JsonElement req)
    {
        var expected = Text(req, "expectedCurrentSha256");
        var newFile = Text(req, "newCssFile");
        var newSha = Text(req, "newCssSha256");
        // 非空已由 RequestShape 把过关；这里只管「像不像哈希、文件在不在」这类形状之外的条件。
        if (expected.Length != 64 || newSha.Length != 64 || !File.Exists(newFile))
        {
            Answer(requestId, "blocked", "compare",
                "expectedCurrentSha256 and newCssSha256 must be 64 hex chars and newCssFile must exist");
            return;
        }
        var payload = File.ReadAllBytes(newFile);
        if (payload.Length > CssEditorAccess.MaxGeneratedCssBytes)
        {
            // 2MiB 是硬上限：在写宿主之前拒绝，用四态里的 blocked 表达，reason 说清是体积超限。
            Answer(requestId, "blocked", "compare", "oversize_generated_css", new Dictionary<string, object?>
            {
                ["bytes"] = payload.Length,
                ["limitBytes"] = CssEditorAccess.MaxGeneratedCssBytes,
                ["identity"] = target.Identity,
            });
            return;
        }
        var current = target.ReadFullText();
        if (current is null)
        {
            Answer(requestId, "blocked", "compare", "no raw UIA text channel is available");
            return;
        }
        var currentHash = Hex(new UTF8Encoding(false).GetBytes(current.Text));
        if (currentHash != expected)
        {
            Answer(requestId, "conflict", "compare", "current_hash_differs", new Dictionary<string, object?>
            {
                ["beforeSha256"] = currentHash,
                ["identity"] = target.Identity,
            });
            return;
        }
        if (!target.TryWriteText(new UTF8Encoding(false).GetString(payload), out var writeError))
        {
            Answer(requestId, "blocked", "write", Cut(writeError, 120));
            return;
        }
        var after = target.ReadFullText();
        if (after is null)
        {
            Answer(requestId, "indeterminate", "read-back", "the editor cannot be read back after the write");
            return;
        }
        var afterHash = Hex(new UTF8Encoding(false).GetBytes(after.Text));
        var verified = afterHash == newSha;
        Answer(requestId, verified ? "verified" : "indeterminate", verified ? "read-back" : "read-back-mismatch",
            verified ? null : "the value read back is not the value written", new Dictionary<string, object?>
            {
                ["beforeSha256"] = currentHash,
                ["afterSha256"] = afterHash,
                ["readChannel"] = after.Channel,
                ["identity"] = target.Identity,
            });
    }

    private static string Text(JsonElement el, string name) =>
        el.ValueKind == JsonValueKind.Object && el.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() ?? "" : "";

    private static int CodePoints(string text) => text.EnumerateRunes().Count();

    private static string Hex(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private static string Cut(string value, int max = 200) => value.Length <= max ? value : value.Substring(0, max);

    private static void Answer(string requestId, string status, string stage, string? reason,
        Dictionary<string, object?>? extra = null)
    {
        var payload = new Dictionary<string, object?>
        {
            ["requestId"] = requestId,
            ["status"] = status,
            ["stage"] = stage,
        };
        if (reason is not null) payload["reason"] = reason;
        if (extra is not null)
        {
            foreach (var pair in extra) payload[pair.Key] = pair.Value;
        }
        Console.Out.WriteLine(JsonSerializer.Serialize(payload));
        Console.Out.Flush();
    }
}
