#!/bin/zsh
# Build the iOS app icon from the user's own copy of the game (Supergiant's artwork is not in this
# repo): extract the 1024 px AppIcon from the macOS bundle and centre it on a dark backdrop so
# iOS's rounded mask doesn't clip it.
set -euo pipefail
source "${0:A:h}/env.sh"
OUT="$HADES_ROOT/app/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
TMP="$HADES_ROOT/build/icon_mac_1024.png"
mkdir -p "$HADES_ROOT/build"
swift "$HADES_ROOT/tools/extract_icon.swift" "$HADES_SRC" "$TMP"
"$HADES_ROOT/tools/venv/bin/python" - "$TMP" "$OUT" <<'PY'
import sys
from PIL import Image
src = Image.open(sys.argv[1]).convert("RGBA")
bg = Image.new("RGBA", (1024, 1024), (10, 14, 26, 255))
size = int(1024 * 0.82)
off = (1024 - size) // 2
bg.alpha_composite(src.resize((size, size), Image.LANCZOS), (off, off))
bg.convert("RGB").save(sys.argv[2])
print("icon ->", sys.argv[2])
PY
