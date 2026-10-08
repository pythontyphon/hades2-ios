#!/bin/zsh
# Copy the shim session logs (current + previous run) off the phone into build/logs/.
set -euo pipefail
source "${0:A:h}/env.sh"
hades_require HADES_DEVICE HADES_BUNDLE_ID
mkdir -p "$HADES_ROOT/build/logs"
for f in session.log session.prev.log; do
  xcrun devicectl device copy from --device "$HADES_DEVICE" --domain-type appDataContainer \
    --domain-identifier "$HADES_BUNDLE_ID" --source "Documents/Logs/$f" \
    --destination "$HADES_ROOT/build/logs/$f" >/dev/null 2>&1 && echo "build/logs/$f" || echo "($f not found)"
done
