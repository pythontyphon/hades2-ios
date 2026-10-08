#!/bin/zsh
# Build every shim/stub as an iOS arm64 framework or dylib into build/shims/.
# Install names and compatibility versions match what the macOS binaries were linked against.
set -euo pipefail
HERE="${0:A:h}"; ROOT="${HERE:h}"; OUT="$ROOT/build/shims"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=(xcrun --sdk iphoneos clang -target arm64-apple-ios26.0 -isysroot "$SDK" -fobjc-arc -fmodules -O2 -g
    -Wall -Wno-unused-function -Wno-deprecated-declarations -dynamiclib -Wl,-headerpad_max_install_names)
mkdir -p "$OUT"

# fw <Name> <compat-version> <sources...> -- <extra link flags...>
fw() {
  local name=$1 compat=$2; shift 2
  local srcs=() flags=()
  while (( $# )) && [[ $1 != -- ]]; do srcs+=("$HERE/$1"); shift; done
  [[ ${1:-} == -- ]] && shift; flags=("$@")
  local dir="$OUT/$name.framework"; mkdir -p "$dir"
  "${CC[@]}" -install_name "@rpath/$name.framework/$name" -compatibility_version "$compat" \
    -o "$dir/$name" "${srcs[@]}" "${flags[@]}"
  "$HERE/fw_plist.sh" "$name" "org.hades2ios.shim.$name" > "$dir/Info.plist"
  echo "  $name.framework"
}

# lib <file.dylib> <compat-version> <sources...> -- <extra link flags...>
lib() {
  local file=$1 compat=$2; shift 2
  local srcs=() flags=()
  while (( $# )) && [[ $1 != -- ]]; do srcs+=("$HERE/$1"); shift; done
  [[ ${1:-} == -- ]] && shift; flags=("$@")
  "${CC[@]}" -install_name "@rpath/$file" -compatibility_version "$compat" -o "$OUT/$file" "${srcs[@]}" "${flags[@]}"
  echo "  $file"
}

fw AppKit 45.0.0 AppKit/CatchAll.m AppKit/NSApplication.m AppKit/NSWindowView.m AppKit/NSMisc.m AppKit/HadesPatches.m AppKit/Telemetry.m AppKit/TouchControls.m \
   -- -framework UIKit -framework Metal -framework QuartzCore -framework GameController \
      -I"$ROOT/third_party/SDL2-2.32.10/include" "$OUT/SDL2.framework/SDL2"
fw CoreGraphicsMac 64.0.0 CoreGraphicsMac/CoreGraphicsMac.m -- -Wl,-reexport_framework,CoreGraphics -framework UIKit -framework Metal
fw CoreServicesMac 1.0.0 CoreServicesMac/CoreServicesMac.m -- -Wl,-reexport_framework,CoreServices -framework UIKit
fw SwiftUIMac 1.0.0 SwiftUIMac/SwiftUIMac.s SwiftUIMac/trap.c -- -Wl,-reexport_framework,SwiftUI
fw AudioUnitMac 1.0.0 AudioUnitMac/AudioUnitMac.c -- -Wl,-reexport_framework,AudioToolbox
fw CoreAudioMac 1.0.0 CoreAudioMac/CoreAudioMac.c -- -Wl,-reexport_framework,CoreAudio
fw Carbon 2.0.0 Carbon/Carbon.c
fw Backtrace 1.0.0 stubs/Backtrace/BacktraceStub.m -- -framework Foundation
lib libsteam_api.dylib 1.0.0 stubs/steam_api/steam_api_stub.c
lib libsdkencryptedappticket.dylib 1.0.0 stubs/sdkencryptedappticket/stub.c
lib libEOSSDK-Mac-Shipping.dylib 4.28.0 stubs/EOSSDK/eos_stub.c
