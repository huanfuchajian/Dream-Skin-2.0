# DreamSkin.exe 启动崩溃诊断（2026-10-17）

## 现象
用户在 Windows（.NET Framework 4.8.1）双击 `DreamSkin.exe`，弹出未处理异常：

```
System.MissingMethodException: 找不到方法:“System.String[] System.String.Split(Char, System.StringSplitOptions)”。
   在 DreamSkin.MainForm.Log(String msg)
   在 DreamSkin.MainForm.<RunBusy>c__async0.MoveNext()
   在 DreamSkin.MainForm.<StartupAsync>c__async1.MoveNext()
```

## 根因（已复现确认）
交付的 exe 是在 Linux 上用 **mono `mcs`** 编译的，默认引用的是 mono 自己的 `mscorlib`。
mono 的 mscorlib 带有 .NET Core 2.0+ 才有的重载 `String.Split(char, StringSplitOptions = None)`，
而 .NET Framework 4.x **只有** `String.Split(params char[])`。

`DreamSkinForm.cs` 里 `msg.Replace("\r", "").Split('\n')` 被 mcs 绑定到了前者，
在真机 .NET Framework 上 JIT 时找不到方法 → 崩溃。最小复现：

| 编译方式 | IL 里的调用 |
|---|---|
| `mcs t.cs`（默认 mono 库） | `String::Split(char, StringSplitOptions)` ← 真机不存在 |
| `mcs -nostdlib -r:/usr/lib/mono/4.5-api/mscorlib.dll t.cs` | `String::Split(char[])` ← 正确 |

Windows 上用系统自带 csc（`build.bat` / GitHub Actions）编译**不会**有这个问题，因为它引用的就是 .NET Framework 自己的库。

## 修复（commit 见 git log）
1. 代码：`Split('\n')` → `Split(new char[] { '\n' })`，与编译器无关都安全。
2. 非 Windows 编译必须引用 .NET 4.5 **参考程序集**，脚本 `tools/build-exe-mono.sh` 已固化：
   `-nostdlib -noconfig -r:/usr/lib/mono/4.5-api/*.dll`。这样任何 .NET Framework 里没有的 API 都会直接编译报错，而不是到用户机器上才崩。
3. 交付 exe 用新方式重编。

## 给下一位 agent
- 状态：修复后 exe 在 mono/Xvfb 能启动；**Windows 真机 NOT_RUN**，需要用户再双击确认。
- 首选让用户从 GitHub Actions（`.github/workflows/build-exe.yml`，windows-latest + 系统 csc）下载 artifact，那是最接近真机的构建。
- 若还有 `MissingMethodException`/`TypeLoadException`：先看是否又用了 mono 默认库编译；用 `ikdasm DreamSkin.exe | grep <方法名>` 查 IL 绑定。
- GUI 内部异常会写到 `%LOCALAPPDATA%\DreamSkin\gui-error.log`；但这次崩在 `RunBusy` 的 catch 里调用 `Log()` 本身，所以没写进日志。后续可以考虑给 `Application.ThreadException` / `AppDomain.UnhandledException` 加全局兜底写日志。
