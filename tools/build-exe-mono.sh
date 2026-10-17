#!/usr/bin/env bash
# 在 Linux/macOS 上用 mono 编译 DreamSkin.exe。必须引用 .NET 4.5 参考程序集，
# 否则 mcs 会绑定到 mono 独有的 API（例如 String.Split(char, StringSplitOptions)），Windows 上运行即崩。
set -euo pipefail
cd "$(dirname "$0")/.."
R=/usr/lib/mono/4.5-api
OUT=${1:-src/DreamSkinMaster/DreamSkin.exe}
ZIP=$(mktemp -d)/payload.zip
python3 - "$ZIP" <<'PY'
import zipfile,os,sys
z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED)
def add(base,arc,skip=()):
  for root,dirs,files in os.walk(base):
    dirs[:]=[d for d in dirs if d not in skip]
    for f in files:
      p=os.path.join(root,f); z.write(p, os.path.join(arc, os.path.relpath(p,base)).replace(os.sep,'/'))
add('src/cherry','src/cherry',('CherryUiBridge','vendor','node_modules'))
add('src/zcode/payload','src/zcode/payload',('node_modules',))
for f in ['LICENSE','THIRD-PARTY-NOTICES.md']: z.write(f,f)
PY
mcs -langversion:5 -nologo -nostdlib -noconfig -target:winexe -out:"$OUT" \
  -win32icon:src/zcode/payload/assets/codex-dream-skin.ico \
  -resource:"$ZIP",DreamSkin.payload.zip \
  -r:$R/mscorlib.dll -r:$R/System.dll -r:$R/System.Core.dll -r:$R/System.Windows.Forms.dll \
  -r:$R/System.Drawing.dll -r:$R/System.IO.Compression.dll -r:$R/System.IO.Compression.FileSystem.dll \
  src/DreamSkinMaster/DreamSkinForm.cs
echo "Built $OUT"
