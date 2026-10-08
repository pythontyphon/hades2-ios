#!/bin/zsh
# Build SDL 2.32.10 (same version the Mac build ships) as an iOS SDL2.framework.
# Patch: SDL_MAIN_NEEDED is iOS default, but the game owns main() (via our AppKit shim),
# so mark main as ready up front, otherwise SDL_Init fails with "did you include SDL_main.h".
set -euo pipefail
HERE="${0:A:h}"; ROOT="${HERE:h}"
VER=2.32.10
SRC="$HERE/SDL2-$VER"
OUT="$ROOT/build/shims"
[[ -d "$SRC" ]] || { curl -sL "https://github.com/libsdl-org/SDL/releases/download/release-$VER/SDL2-$VER.tar.gz" | tar -xz -C "$HERE"; }
grep -q 'HADES_IOS_PATCH' "$SRC/src/SDL.c" || \
  sed -i '' 's/^static SDL_bool SDL_MainIsReady = SDL_FALSE;/static SDL_bool SDL_MainIsReady = SDL_TRUE; \/\/ HADES_IOS_PATCH/' "$SRC/src/SDL.c"
grep -q 'HADES_IOS_PATCH' "$SRC/src/SDL.c" || { echo "SDL_MainIsReady patch failed"; exit 1; }
# Patch 2: generic MFi pads (e.g. Razer) come back as SDL_CONTROLLER_TYPE_UNKNOWN, which the game
# flags as "Possibly unsupported controller". They use the Xbox ABXY layout, so report them as Xbox One.
F="$SRC/src/joystick/SDL_gamecontroller.c"
grep -q 'HADES_IOS_PATCH_TYPE' "$F" || perl -0pi -e 's/(    SDL_UnlockJoysticks\(\);\n\n    return type;\n\}\n\nint SDL_GameControllerGetPlayerIndex)/    SDL_UnlockJoysticks();\n\n    if (type == SDL_CONTROLLER_TYPE_UNKNOWN || type == SDL_CONTROLLER_TYPE_VIRTUAL) { \/\/ HADES_IOS_PATCH_TYPE\n        type = SDL_CONTROLLER_TYPE_XBOXONE;\n    }\n    return type;\n}\n\nint SDL_GameControllerGetPlayerIndex/' "$F"
grep -q 'HADES_IOS_PATCH_TYPE' "$F" || { echo "controller type patch failed"; exit 1; }
cmake -S "$SRC" -B "$SRC/build-ios" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_BUILD_TYPE=Release -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF \
  -DSDL_FRAMEWORK=OFF >/dev/null
cmake --build "$SRC/build-ios"
# CMake emits a plain dylib for iOS; wrap it as the flat-layout framework the game links.
FW="$OUT/SDL2.framework"; rm -rf "$FW"; mkdir -p "$FW"
cp "$SRC/build-ios/libSDL2-2.0.0.dylib" "$FW/SDL2"
install_name_tool -id @rpath/SDL2.framework/SDL2 "$FW/SDL2"
"$ROOT/shims/fw_plist.sh" SDL2 org.libsdl.SDL2 "$VER" > "$FW/Info.plist"
otool -L "$OUT/SDL2.framework/SDL2" | head -3
