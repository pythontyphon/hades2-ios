#!/bin/zsh
# Build the iOS wrapper app with Xcode, then make sure the final bundle is signed: Xcode skips its
# CodeSign step when it thinks nothing changed, even though the embed phase swapped binaries.
set -euo pipefail
source "${0:A:h}/env.sh"
hades_require HADES_TEAM HADES_BUNDLE_ID
cd "$HADES_ROOT"
APP=build/DerivedData/Build/Products/Debug-iphoneos/HadesII.app
[[ -f app/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png ]] || tools/make_icon.sh
xcodebuild -project app/HadesII.xcodeproj -scheme HadesII -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$HADES_TEAM" HADES_BUNDLE_ID="$HADES_BUNDLE_ID" \
  build -quiet 2>&1 | grep -v 'Supported platforms for the buildables' || true
if ! codesign --verify --deep --strict "$APP" 2>/dev/null; then
  XCENT=$(find build/DerivedData/Build/Intermediates.noindex -name 'HadesII.app.xcent' | head -1)
  ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')
  codesign --force --sign "$ID" --entitlements "$XCENT" --generate-entitlement-der "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "built + signed: $APP"
