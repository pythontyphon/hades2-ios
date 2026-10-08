#!/bin/zsh
# Full pipeline from the user's own Steam copy to a signed iOS app. No device needed.
#   stage + thin the macOS build -> retag/rewrite its Mach-Os -> build SDL + shims -> verify every
#   import binds -> convert shaders (pushed with the content) -> build + sign the app.
set -euo pipefail
source "${0:A:h}/env.sh"
cd "$HADES_ROOT"
[[ -x tools/venv/bin/python ]] || { python3 -m venv tools/venv && tools/venv/bin/pip install -q -r tools/requirements.txt; }
PY=tools/venv/bin/python

tools/import_macos_app.sh
S="build/staging/Hades II.app/Contents"
mkdir -p build/ported
$PY tools/macho_port.py "$S/MacOS/Hades II" build/ported/HadesII
for l in libfmod libfmodstudio libBink2MacArm64; do
  $PY tools/macho_port.py "$S/Frameworks/$l.dylib" "build/ported/$l.dylib"
done
[[ -f build/shims/SDL2.framework/SDL2 ]] || third_party/build_sdl.sh
shims/build.sh
$PY tools/verify_bind.py build/ported/HadesII build/ported/*.dylib build/shims/AppKit.framework/AppKit

# iOS rejects the macOS metallibs; the converted ones ride along with the content push.
$PY tools/metallib_port.py "$HADES_SRC/Contents/Resources/Content/Shaders/Metal/bin" \
  build/content_overlay/Content/Shaders/Metal/bin

tools/build_app.sh
