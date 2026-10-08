#!/bin/zsh
# Copy the Steam macOS build (minus the 11 GB Content dir) into build/staging and thin to arm64.
set -euo pipefail
source "${0:A:h}/env.sh"
[[ -d "$HADES_SRC" ]] || { echo "error: game not found at $HADES_SRC (set HADES_SRC in local.env)"; exit 1; }
DST="$HADES_ROOT/build/staging/Hades II.app"
rm -rf "$DST"; mkdir -p "$DST/Contents"
rsync -a --exclude 'Resources/Content' --exclude '_CodeSignature' "$HADES_SRC/Contents/" "$DST/Contents/"
find "$DST" -type f \( -perm +111 -o -name '*.dylib' \) -print0 | while IFS= read -r -d '' f; do
  if file "$f" | grep -q 'Mach-O universal'; then lipo "$f" -thin arm64 -output "$f.thin" && mv "$f.thin" "$f"; fi
done
find "$DST" -name _CodeSignature -type d -prune -exec rm -rf {} +
echo "staged: $DST"
