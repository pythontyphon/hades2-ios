#!/bin/zsh
# Install the built app on the iPhone and launch it with its stdout/stderr streamed here.
#   tools/run.sh                         install + launch
#   tools/run.sh --hud                   also enable the Metal performance HUD
#   tools/run.sh --no-install
#   tools/run.sh -- -HadesTargetFPS 90   pass settings (NSUserDefaults launch arguments)
# Never uninstall the app: that deletes the pushed Content in its data container.
set -euo pipefail
source "${0:A:h}/env.sh"
hades_require HADES_DEVICE HADES_BUNDLE_ID
cd "$HADES_ROOT"
APP=build/DerivedData/Build/Products/Debug-iphoneos/HadesII.app
ENV='{}'; INSTALL=1; ARGS=()
while (( $# )); do
  case $1 in
    --hud) ENV='{"MTL_HUD_ENABLED":"1"}' ;;
    --no-install) INSTALL=0 ;;
    --) shift; ARGS=("$@"); break ;;
  esac
  shift
done
(( INSTALL )) && xcrun devicectl device install app --device "$HADES_DEVICE" "$APP"
xcrun devicectl device process launch --device "$HADES_DEVICE" --terminate-existing --console \
  --environment-variables "$ENV" "$HADES_BUNDLE_ID" -- "${ARGS[@]}"
