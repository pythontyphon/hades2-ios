# How it works

This document explains how the macOS build of Hades II is made to run natively on iOS, and records
each problem hit along the way, with its diagnosis and fix. Names of the game's classes, functions
and config options are given only where they're needed to explain an interoperability fix.

## 1. What the macOS build is made of

The Steam build (`Hades II.app`, v1.143476) is arm64 only, built with the macOS 26.5 SDK:

| Binary | Role | Treatment |
|---|---|---|
| `MacOS/Hades II` (6.5 MB) | The game: C++ engine ("The Forge" renderer, Lua, Granny3D) plus ObjC/Swift glue | Retagged to iOS, load paths rewritten |
| `SDL2.framework` 2.32.10 | Controller input | **Rebuilt from source for iOS**, same version |
| `libfmod` / `libfmodstudio` | Audio | Retagged; CoreAudio HAL emulated |
| `libBink2MacArm64` | Video | Retagged (with a `__LINKEDIT` fix, see §4) |
| `libsteam_api`, `libsdkencryptedappticket` | Steam | Replaced by offline stubs |
| `libEOSSDK-Mac-Shipping` | Epic Online Services | Replaced by a stub (platform create returns NULL) |
| `Backtrace.framework` | Crash reporting | Replaced by catch-all stub classes |

`Content/` (11.6 GB) is platform-neutral apart from the shaders: Lua/sjson scripts, FMOD banks,
Bink movies, `.pkg` texture packages in `720p/` and `1080p/` sets, and **macOS metallibs**.

## 2. Mach-O porting (`tools/macho_port.py`)

The iOS dynamic loader (dyld) refuses binaries built for the macOS platform. arm64 code is
identical on both platforms, so porting is mostly metadata work:

1. `codesign --remove-signature`.
2. `vtool -set-build-version ios 26.0 27.0 -replace`.
3. `install_name_tool -change` on every dependency. macOS framework paths
   (`…/AppKit.framework/Versions/C/AppKit`) become either the flat iOS path
   (`…/Foundation.framework/Foundation`) or a shim (`@rpath/AppKit.framework/AppKit`). Bundled
   frameworks are flattened (`@rpath/SDL2.framework/SDL2`).

The binaries use two-level namespaces: every imported symbol is bound to a *library ordinal*. So
load commands are only ever **rewritten in place**, never removed or reordered. A macOS framework
with no iOS equivalent and zero imports (Carbon, ForceFeedback) points at an empty shim instead of
being dropped. Each shim **re-exports** the real iOS framework (`-reexport_framework`) and adds only
what's missing, so every existing binding still resolves.

LIEF was tried first, but its rewrite left `__LINKEDIT` misaligned, so the tool only uses Apple's
own utilities.

### Knowing what's missing before touching the device

`tools/symbol_gap.py` takes every import of every binary, maps each dependency to its iOS SDK
`.tbd`, and **links a probe** that references all those symbols against it. Whatever the linker
reports as undefined is the shim to-do list. That's how the gap turned out to be small:

- AppKit: 23 symbols (11 classes, `NSApp`, `NSApplicationMain`, 7 notification names, …)
- CoreGraphics: 12 display-mode functions (`CGDisplayCopyAllDisplayModes`, `CGMainDisplayID`, …)
- SwiftUI: 3 macOS-only symbols (`NSHostingController`, `Image(nsImage:)`), used only by the bug reporter
- CoreServices: `LSOpenCFURLRef`
- AudioUnit: the whole framework is absent, but every function lives in AudioToolbox on iOS
- libSystem, libc++, the Swift runtime, Foundation, Metal, IOKit and even CoreAudio's `AudioObject*`: **0 missing**

`tools/verify_bind.py` then repeats the check against the *built* shims. Every import of every
ported binary must bind before anything is installed, which catches dyld failures offline.

## 3. The shims (`shims/`)

### AppKit on UIKit

The Forge's macOS layer subclasses AppKit: `ForgeApplication : NSApplication`,
`ForgeNSWindow : NSWindow`, `ForgeMTLView : NSView`. So the shim must export real ObjC classes.

- **`NSView` is an `NSObject` that owns a `UIView`**, not a `UIView` subclass. AppKit and UIKit
  share selector names with different meanings (`-window`, `-layer`), and UIKit calls them
  internally, so the two must never meet. `-setLayer:` (which the Forge view uses to install its own
  `CAMetalLayer`) adds that layer as a sublayer of the backing view, resized in `layoutSubviews`.
- **`NSWindow`** wraps the single full-screen root view controller. Window delegate callbacks
  (`windowDidResize:`, `windowDidBecomeMain:`) are sent to the game's delegate.
- **Unknown selectors** on shim classes resolve to a logged IMP that zeroes `x0`/`x1`/`d0`–`d3`, so
  object, integer, BOOL and NSRect returns all read as 0.
- **Lifecycle:** the game's `main` runs part of its engine setup, then calls `NSApplicationMain`, which the shim
  turns into `UIApplicationMain` with a scene delegate. The macOS nib normally creates the game's
  `AppDelegate`; the shim instantiates it by name. The game's `applicationDidFinishLaunching:`
  **never returns**: it runs the main loop `while (shouldRun) { drain [NSApp nextEventMatchingMask:…];
  [controller draw]; }`. The shim starts it from a run-loop timer after the scene connects (SDL's
  iOS trick), and `nextEventMatchingMask:` pumps the UIKit run loop and returns nil. While the app is
  in the background, that call blocks, so the game stops submitting GPU work, which iOS forbids for
  backgrounded apps.

### Others

| Shim | Purpose |
|---|---|
| `CoreGraphicsMac` | One display: the game area in pixels, at the panel's refresh rate |
| `CoreAudioMac` | A **fixed table** for the six HAL properties FMOD queries (default device, device list, UID, name, 48 kHz, stereo layout). It never calls the real iOS HAL (see §4) |
| `AudioUnitMac` | Re-exports AudioToolbox; maps the `HALOutput` unit to `RemoteIO` and ignores `CurrentDevice` |
| `SwiftUIMac` | Traps if the macOS-only bug-reporter UI is ever reached |
| `CoreServicesMac` | `LSOpenCFURLRef` → `UIApplication openURL:` |
| `Carbon` | Empty: satisfies load commands with zero imports |
| `stubs/steam_api` | `SteamAPI_Init` succeeds offline. Every interface is a fake C++ object whose vtable returns 0 |
| `stubs/EOSSDK` | `EOS_Platform_Create` returns NULL, so the game treats Epic services as unavailable |
| `stubs/Backtrace` | Catch-all classes under the Swift classes' runtime names |

### Runtime patches (`shims/AppKit/HadesPatches.m`)

- **Metal:**
  - `MTLStorageModeManaged` buffers/textures/heaps become `Shared`.
  - `isLowPower`, `isDepth24Stencil8PixelFormatSupported` and macOS `supportsFeatureSet:` values are answered.
- **Content path:** the game finds `Content/` via `[[NSBundle mainBundle] resourceURL]`. For calls
  *whose return address is inside the game binary*, that is redirected to Documents/, so UIKit's
  own bundle lookups are unaffected.
- **Settings sync:** before the game reads `GlobalSettingsmacOS.sjson`, the shim writes the
  resolution (X/Y = current game area), `ForceVoiceBankStreaming = true`, and the asset-set options.
- **Reported RAM:** `sysctl(hw.memsize)` is interposed (only for callers in the game binary), see §4.

### Telemetry (`Telemetry.m`)

stdout/stderr are tee'd to `Documents/Logs/session.log`. `-[CAMetalLayer nextDrawable]` is
counted, and every 2 s the shim logs fps, the worst frame, the average time spent waiting for a
drawable, memory footprint and thermal state. That made it possible to review sessions played
untethered: the controller in use plugs into the phone's only USB-C port.

### Touch controls (`TouchControls.m`)

A UIKit overlay drives an **SDL virtual joystick** (`SDL_JoystickAttachVirtualEx`) with the Xbox
button/axis layout, so the game sees an ordinary controller. It is shown only while no
`GCController` is connected. SDL's iOS default of exposing the accelerometer as a joystick is
disabled, so the virtual pad is device 0.

### SDL patches (`third_party/build_sdl.sh`)

1. `SDL_MainIsReady` defaults to true. On iOS, SDL expects to own `main()`, and otherwise
   `SDL_Init` fails.
2. Controllers SDL reports as `UNKNOWN`/`VIRTUAL` are reported as Xbox One, which removes the
   game's "Possibly unsupported controller" warning. Generic MFi pads use the Xbox ABXY layout.

## 4. Problems found on the device, in order

| # | Symptom | Diagnosis | Fix |
|---|---|---|---|
| 1 | dyld would reject Bink | Its string table isn't 8-byte aligned. macOS tolerates that; iOS dyld doesn't | Pad and realign it after removing the signature (`fix_strtab_alignment`) |
| 2 | SIGKILL 20 s after launch (`0x8BADF00D`) | The renderer finds the highest supported feature set by counting up from 9999 while `supportsFeatureSet:` returns YES. The first shim said YES to every macOS value, so the loop never ended | Answer YES only for 10000–10005 |
| 3 | Assert: `vertexFunction must not be nil` | `newLibraryWithData:` → "This library format is not supported on this platform" | `metallib_port.py`: extract each AIR bitcode module, recompile with `-target air64_v23-apple-ios26.0` (the files are AIR 2.3), relink with the iOS `metallib`. The converted files are pushed as a content overlay |
| 4 | `EXC_BREAKPOINT` in `BTAudioHALPlugin` / `_xpc_api_misuse` | Calling iOS CoreAudio's `AudioObjectGetPropertyData` boots an in-process macOS-style HAL that loads the Bluetooth audio plugin, which isn't allowed inside an app | Never forward to the real HAL; answer FMOD's queries from a fixed table. Audio itself flows through RemoteIO |
| 5 | SIGKILL with no crash report, about 3 s in | The device syslog showed `memorystatus … exceeded mem limit: ActiveHard 6144 MB`. On the "16 GB Mac" path the game loads its 1080p set and keeps every voice bank in RAM | Report RAM below the game's own 9000 MB "low memory" line (it then picks 720p and streams VO). Later: 9216 MB plus `ForceVoiceBankStreaming`, so 1080p fits (§5) |
| 6 | Memory grew 100 MB/s until killed | One Metal buffer per frame was never freed. The shim's own ARC wrappers around `new…` methods returned the result autoreleased, and the engine allocates on a pthread with no draining autorelease pool | Wrappers return the result as a raw pointer, so ARC adds no retain/autorelease. Footprint now stays flat |
| 7 | Picture pinned to the top-left third | The Forge sizes its window from display-mode **pixels** but passes that as a **point** frame, then sets `drawableSize = frame × scale`, which is 3× too big | Clamp view frames to the screen in points |
| 8 | Rounded corners clip the HUD | — | Lay out in the horizontal safe area (the game handles any aspect ratio) and cache the size for the next launch, since the game queries it before UIKit is up |
| 9 | Squeezed image after (8) | The game boots parts of its pipeline at the resolution stored in `GlobalSettingsmacOS.sjson` | The shim rewrites X/Y before the game reads them |
| 10 | Capped at 60 fps | The game waited about 14 ms per frame in `nextDrawable`, so the display was pacing it. `VSync`/`FpsLimit` had no effect. ProMotion keeps a Metal app at 60 Hz unless the app asks for more | A no-op `CADisplayLink` with `preferredFrameRateRange` 80–120 → 120 fps |

Useful techniques along the way:
- `tools/last_crash.py` fetches crash reports from the phone.
- `pymobiledevice3 syslog live` gives kernel `memorystatus`/RunningBoard messages without sudo.
- Logging a call stack from inside a swizzled allocator showed which engine code was allocating.

## 5. Memory and performance tuning

- **GPU budget:** the game sizes budgets from `recommendedMaxWorkingSetSize`, which reports 8 GB on
  this phone. The shim reports 3 GB.
- **Asset set:** the game switches to 720p packages and streamed voice-over when RAM < 9000 MB. The
  shim reports 9216 MB for 1080p (8192 MB for `HadesAssetSet=720p`) and forces voice streaming
  separately.
  - Result: about 3.7 GB on the menu and a 4.9 GB peak in combat, against a 6 GB limit (with the
    `increased-memory-limit` entitlement).
- **Frame pacing:** 120 Hz is requested via a display link (`HadesTargetFPS`). On the menu, about
  6.6 ms of each 8.3 ms frame is idle. In combat the average is about 116 fps, with dips while
  rooms load.
- **Remaining hitches:** room transitions stream textures through the engine's Vulkan-style
  allocator (VMA), which creates a Metal heap per allocation. That's the next thing to look at.

## 6. Content transfer

`tools/sync_content.py` mirrors `Content/` into `build/content/` with **APFS clones** (no extra
disk), adds the converted shaders from `build/content_overlay/`, and pushes everything to the app's
data container with `xcrun devicectl device copy to --domain-type appDataContainer`. A manifest
records what's on the device, so later runs only send changed files. The data container survives
reinstalls of the same bundle ID, but not deleting the app.
