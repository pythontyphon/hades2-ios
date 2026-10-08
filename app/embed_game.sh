#!/bin/zsh
# Xcode build phase: swap the placeholder executable for the ported game binary and embed
# the shims + ported dylibs, signing each nested binary (Xcode signs the app bundle after this).
set -euo pipefail
ROOT="${SRCROOT:h}"
APP="$TARGET_BUILD_DIR/$WRAPPER_NAME"
FW="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
for f in "$ROOT/build/ported/HadesII" "$ROOT/build/shims/AppKit.framework/AppKit" "$ROOT/build/shims/SDL2.framework/SDL2"; do
  [[ -f "$f" ]] || { echo "error: missing $f - run tools/build_all.sh first"; exit 1; }
done
cp "$ROOT/build/ported/HadesII" "$APP/$EXECUTABLE_NAME"   # tools/build_app.sh re-signs if Xcode skips CodeSign
mkdir -p "$FW"
rsync -a --delete --exclude '*.dSYM' "$ROOT/build/shims/" "$FW/"
cp "$ROOT"/build/ported/*.dylib "$FW/"
# Bundle bits the game reads from its own bundle (cursors, icons); Content lives in Documents.
rsync -a "$ROOT/build/staging/Hades II.app/Contents/Resources/"*.cur "$APP/" 2>/dev/null || true
ID="${EXPANDED_CODE_SIGN_IDENTITY:--}"
for f in "$FW"/*.dylib "$FW"/*.framework; do
  codesign --force --sign "$ID" --timestamp=none "$f"
done
