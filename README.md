# Hades II on iOS (native, from your own Steam copy)

Run the **macOS Steam build of Hades II** natively on an iPhone. The game's own arm64 binaries are
retagged as iOS executables, and small shim libraries stand in for the macOS-only APIs they use
(AppKit, CoreGraphics display queries, the CoreAudio HAL, Steam, Epic Online Services, …).
Nothing is emulated or recompiled: the game's original machine code runs on the phone's CPU and
renders through Metal.

> **This repository contains no Supergiant Games code, data or artwork.** Every build step reads
> from *your own* legally obtained copy of the game, and the result is for personal use on your
> own device. Don't share the resulting app, IPA, or anything in `build/`.

## Read this first: you're on your own, so bring an agent

**This is provided as is, with no support. Any problem you run into is yours to solve.** That
includes problems with your device, your Apple developer account, your game install and your save
files. It was built and tested on exactly one setup (below). Issues and pull requests may go
unanswered.

Your setup **will** differ: a different iPhone (and RAM limit), iOS or Xcode version, Apple account
type, or a game version after a Steam update. Expect at least one thing to break. A port like this
fails in ways that depend on the exact binaries and OS, such as a missing symbol, a new watchdog,
a memory limit or a changed shader format.

**You'll have a much better experience pointing a coding agent (e.g. Claude Code) at this repo on
your Mac than hoping it works out of the box.** The repo is set up for that:
- `docs/HOW_IT_WORKS.md` records every failure met so far, with its diagnosis and fix.
- The tools give an agent what it needs to investigate on its own:
  - an offline import gap report and dyld bind check
  - on-device session logs with fps/memory telemetry
  - a crash-report fetcher
  - instructions for reading the device syslog

A good starting prompt:

> Read README.md and docs/HOW_IT_WORKS.md, then port my Steam copy of Hades II to my iPhone with
> this repo. Run tools/build_all.sh, fix whatever breaks on my setup, and diagnose any on-device
> crash from the session logs, crash reports and device syslog before changing code.

## Results

Tested on an iPhone 18 Pro Max (A20 Pro, 12 GB) with the Steam build v1.143476, iOS 27, and Xcode 27:

| | |
|---|---|
| Frame rate | 120 fps on ProMotion: 115.9 average over an 11-minute run, 86% of 2-second windows at 110 fps or better |
| Resolution | Native 3× (2496×1320 inside the horizontal safe area), 1080p asset set |
| Memory | ~3.7 GB on the menu, 4.9 GB peak in combat (iOS per-app limit: 6 GB) |
| Thermals | Reaches the "fair" state after about 7 minutes at 120 fps (no throttling). 90 fps is a one-setting change. |
| Input | MFi/Bluetooth/USB-C controllers via the game's SDL path, plus an on-screen gamepad fallback |
| Audio | FMOD (the game's own macOS build) through a HAL emulation layer on RemoteIO |
| Not working | Steam/Epic online features: achievements, cloud saves (the stubs report the services as unavailable, so saves are local) |
| Known issue | 0.2–0.4 s hitches when a new room streams its assets |

## Requirements

- An Apple Silicon Mac with **Xcode 27** (including the Metal toolchain) and Homebrew `cmake` + `ninja`.
- **Hades II for macOS**, installed through Steam (or point `HADES_SRC` at the `.app`).
- An **Apple Developer account**. Tested with a paid account, which gives 1-year provisioning
  profiles. The app needs the *Increased Memory Limit* entitlement, which Xcode adds to the App ID
  automatically. A free "Personal Team" is untested: its profiles expire after 7 days, and it may
  not grant that entitlement.
- An iPhone running iOS 26+ with Developer Mode on. Only the iPhone 18 Pro Max (12 GB, 6 GB per-app
  limit) has been tested. On phones with less RAM the per-app limit is lower, so expect to need
  `HadesAssetSet=720p` and possibly a lower `HadesTargetFPS`.
- About 12 GB free on the phone for the game content, and about 25 GB on the Mac (the content
  mirror uses APFS clones, so it costs almost nothing).

## Quick start

```sh
cp local.env.example local.env      # fill in team ID, bundle ID, device UDID
tools/build_all.sh                  # stage + port the game, build SDL and the shims, build + sign the app
tools/run.sh                        # install and launch once (creates the app's data container)
tools/venv/bin/python tools/sync_content.py    # push ~11.6 GB of game content (once, over USB)
tools/run.sh                        # play
```

The content is copied **separately** from the app, into the app's own Documents folder. Rebuilding
and reinstalling the app only pushes about 20 MB. **Never delete the app from the phone**: that wipes
the pushed content, and you'd have to push it again. `sync_content.py` only sends files that changed,
for example after a Steam update.

After the first launch you can start the game from its home-screen icon like any other app.

## Configuration

These settings are standard iOS user defaults. Pass them as launch arguments for one run,
e.g. `tools/run.sh -- -HadesTargetFPS 90`.

| Setting | Default | Effect |
|---|---|---|
| `HadesTargetFPS` | `120` | Display refresh the app asks ProMotion for (e.g. `90` or `60` to run cooler) |
| `HadesAssetSet` | `1080p` | `720p` uses the game's low-memory asset set (~1 GB less RAM) |
| `HadesSafeArea` | `YES` | Keep the picture inside the horizontal safe area (`NO` = edge to edge, corners clip the HUD) |
| `HadesTouchControls` | `auto` | On-screen gamepad: `auto` (only while no controller is connected), `on`, `off` |
| `HadesRenderScale` | screen scale | Render below native resolution (e.g. `2.0`) |
| `HadesWorkingSetMB` | `3072` | GPU memory budget reported to the game |
| `HadesVerbose` | `NO` | Trace Metal heap/audio calls in the log |

## Tools

| | |
|---|---|
| `tools/build_all.sh` | Full pipeline (no device needed) |
| `tools/build_app.sh` | Rebuild and sign only the iOS app |
| `tools/run.sh [--hud] [--no-install] [-- args]` | Install, launch, and stream the console. `--hud` enables the Metal performance HUD |
| `tools/sync_content.py [--only Shaders] [--dry-run] [--verify]` | Push content incrementally |
| `tools/pull_logs.sh` | Fetch the last two session logs. They include `perf:` lines (fps, worst frame, memory, thermal state) every 2 s, so a session played untethered can be reviewed later |
| `tools/last_crash.py` | Fetch and summarise the newest crash report |
| `tools/symbol_gap.py <macho>…` | Report which imports the iOS SDK lacks (`shims/GAP_REPORT.md`) |
| `tools/verify_bind.py <macho>…` | Offline dyld check: every import of every ported binary must bind |
| `tools/metallib_port.py <src> <dst>` | Rebuild macOS metallibs as iOS metallibs |

Device system logs without sudo: `tools/venv/bin/pymobiledevice3 syslog live --udid <UDID>`.

## How it works

The short version:

1. **Port the Mach-Os.** `macho_port.py` uses Apple's own `vtool`, `install_name_tool` and
   `codesign`. It changes `LC_BUILD_VERSION` from macOS to iOS, strips the signature, and points
   each macOS framework path at either its iOS equivalent or a shim. Load commands are only
   rewritten, never removed, so symbol bindings stay valid.
2. **Shim what's missing.** The AppKit shim implements `NSApplication`/`NSWindow`/`NSView`/`NSScreen`
   on top of UIKit. The other shims cover CoreGraphics display modes, the CoreAudio HAL, SwiftUI's
   macOS-only types, and Steam/EOS/Backtrace stubs that report those services as unavailable. SDL 2.32.10 (the same version the game
   ships) is rebuilt for iOS with two small patches.
3. **Patch at runtime.** The shims also fix up macOS-only Metal usage, redirect the game's content
   path to the Documents folder, report memory figures that steer the game onto its
   lower-memory settings, and request 120 Hz from ProMotion.
4. **Wrap it as an app.** A minimal Xcode project provides signing, the provisioning profile and
   entitlements. A build phase swaps in the ported executable and embeds the shims.

The full write-up, including every problem found on the way and how it was solved, is in
[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md).

## Repository layout

```
app/          Xcode wrapper app (Info.plist, entitlements, embed build phase)
shims/        AppKit-on-UIKit + framework shims + Steam/EOS/Backtrace stubs; build.sh
third_party/  build_sdl.sh: downloads, patches and builds SDL 2.32.10 for iOS
tools/        porting, verification, build, deploy and diagnostics scripts
docs/         how it works
build/        (git-ignored) everything derived from the game
```

## License and legal

The code in this repository is MIT-licensed (see [LICENSE](LICENSE)). That covers only the
original shims, scripts and docs here. It grants no rights to Hades II or any other third-party
software.

**Use at your own risk.** You're responsible for what you build and run with this, and for
complying with the terms that apply to you (e.g. the game's EULA, Steam's subscriber agreement,
Apple's developer program agreement).

Hades II is © Supergiant Games, LLC. This project is unaffiliated with and not endorsed by
Supergiant Games, Valve, Epic Games, Firelight Technologies (FMOD), Epic Games Tools (Bink), or
Apple. It contains only original interoperability code and build scripts. You must own the game,
and the ported app must not be distributed. SDL is downloaded at build time under its zlib license.
