# 打包 DreamSkin.exe：把 src\cherry（不含旧 UIA 桥）和 src\zcode\payload 压成 payload.zip 嵌进 exe。
# 只用 Windows 自带的 .NET Framework 4.x csc，无需安装 Visual Studio。
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Resolve-Path (Join-Path $here '..\..')
$stage = Join-Path $env:TEMP ("dreamskin-stage-" + [guid]::NewGuid().ToString('N'))
$zip = Join-Path $here 'payload.zip'
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'src\zcode') | Out-Null
robocopy (Join-Path $repo 'src\cherry') (Join-Path $stage 'src\cherry') /E /XD CherryUiBridge vendor node_modules /NFL /NDL /NJH /NJS | Out-Null
robocopy (Join-Path $repo 'src\zcode\payload') (Join-Path $stage 'src\zcode\payload') /E /XD node_modules /NFL /NDL /NJH /NJS | Out-Null
Copy-Item (Join-Path $repo 'LICENSE'), (Join-Path $repo 'THIRD-PARTY-NOTICES.md') $stage
if (Test-Path $zip) { Remove-Item $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Remove-Item -Recurse -Force $stage

$fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $fw 'csc.exe'
$out = Join-Path $here 'DreamSkin.exe'
& $csc -nologo -target:winexe -platform:anycpu "-out:$out" `
  "-win32icon:$(Join-Path $repo 'src\zcode\payload\assets\codex-dream-skin.ico')" `
  "-resource:$zip,DreamSkin.payload.zip" `
  -r:System.Windows.Forms.dll -r:System.Drawing.dll `
  "-r:$(Join-Path $fw 'System.IO.Compression.dll')" "-r:$(Join-Path $fw 'System.IO.Compression.FileSystem.dll')" `
  (Join-Path $here 'DreamSkinForm.cs')
if ($LASTEXITCODE -ne 0) { throw "csc 编译失败（exit $LASTEXITCODE）" }
Remove-Item $zip
Write-Host "Build completed: $out"
