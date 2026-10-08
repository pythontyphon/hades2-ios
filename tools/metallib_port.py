#!/usr/bin/env python3
"""Fallback: rebuild the game's macOS metallibs as iOS metallibs.

Each shipped shader file is a metallib whose MODULE_LIST holds one or more AIR bitcode
modules (bitcode wrapper magic 0x0B17C0DE). Extract every module, recompile it with an iOS
AIR triple at the same AIR version (2.3), and relink with the iOS `metallib`.

  metallib_port.py <src_dir> <out_dir>

Only needed if the device refuses the originals (milestone 3 probe). Output then goes to
build/content_overlay/Content/Shaders/Metal/bin and is pushed by sync_content.py --only Shaders.
"""
import shutil, struct, subprocess, sys, tempfile
from pathlib import Path

TARGET = "air64_v23-apple-ios26.0"
WRAPPER = bytes.fromhex("dec0170b")


def modules(data):
    i = data.find(WRAPPER)
    while i >= 0:
        _, _, off, size, _ = struct.unpack_from("<5I", data, i)
        yield data[i:i + off + size]
        i = data.find(WRAPPER, i + off + size)


def port(src, dst):
    with tempfile.TemporaryDirectory() as td:
        airs = []
        for n, bc in enumerate(modules(src.read_bytes())):
            b = Path(td, f"{n}.bc"); b.write_bytes(bc)
            a = Path(td, f"{n}.air")
            subprocess.run(["xcrun", "-sdk", "iphoneos", "metal", "-c", "-x", "ir", str(b), "-target", TARGET,
                            "-Wno-override-module", "-o", str(a)], check=True, capture_output=True)
            airs.append(str(a))
        if not airs:
            raise RuntimeError("no AIR modules found")
        subprocess.run(["xcrun", "-sdk", "iphoneos", "metallib", *airs, "-o", str(dst)], check=True, capture_output=True)
        return len(airs)


def main(src_dir, out_dir):
    src_dir, out_dir = Path(src_dir), Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ok = fail = 0
    for f in sorted(src_dir.iterdir()):
        if not f.is_file():
            continue
        if f.read_bytes()[:4] != b"MTLB":          # .shader files are text vert/frag pairings
            shutil.copy2(f, out_dir / f.name)
            continue
        try:
            n = port(f, out_dir / f.name)
            ok += 1
        except (subprocess.CalledProcessError, RuntimeError) as e:
            fail += 1
            err = e.stderr.decode()[:200] if hasattr(e, "stderr") and e.stderr else str(e)
            print(f"FAIL {f.name}: {err}")
    print(f"{ok} converted, {fail} failed -> {out_dir}")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
