#!/usr/bin/env python3
"""Retag macOS arm64 Mach-Os as iOS and rewrite their dylib load paths.

usage: macho_port.py <in> <out>

Load commands are rewritten in place (never removed) so two-level-namespace
library ordinals stay valid. Mapping rules live in REDIRECT/remap() below.
"""
import argparse, os, re, shutil, struct, subprocess, sys
from pathlib import Path

IOS_MINOS = (26, 0, 0)
IOS_SDK = (27, 0, 0)

# macOS framework -> our shim (re-exports the iOS framework where one exists)
REDIRECT = {
    "AppKit": "@rpath/AppKit.framework/AppKit",
    "Cocoa": "@rpath/AppKit.framework/AppKit",
    "Carbon": "@rpath/Carbon.framework/Carbon",
    "CoreGraphics": "@rpath/CoreGraphicsMac.framework/CoreGraphicsMac",
    "CoreServices": "@rpath/CoreServicesMac.framework/CoreServicesMac",
    "SwiftUI": "@rpath/SwiftUIMac.framework/SwiftUIMac",
    "AudioUnit": "@rpath/AudioUnitMac.framework/AudioUnitMac",
    "CoreAudio": "@rpath/CoreAudioMac.framework/CoreAudioMac",
    "ForceFeedback": "@rpath/Carbon.framework/Carbon",
}


def remap(path):
    m = re.match(r"/System/Library/Frameworks/(\w+)\.framework/Versions/\w+/(\w+)$", path)
    if m:
        return REDIRECT.get(m[1], f"/System/Library/Frameworks/{m[1]}.framework/{m[2]}")
    m = re.match(r"@rpath/(\w+)\.framework/Versions/\w+/(\w+)$", path)
    if m:  # bundled macOS-layout frameworks -> flat iOS layout
        return f"@rpath/{m[1]}.framework/{m[2]}"
    return path


def fix_strtab_alignment(path):
    """iOS dyld rejects a string pool that is not 8-byte aligned (macOS tolerates it;
    Bink2 ships like that). Pad in front of the pool, which must sit last in __LINKEDIT."""
    data = bytearray(Path(path).read_bytes())
    ncmds = struct.unpack_from("<I", data, 16)[0]
    off, symtab, linkedit = 32, None, None
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", data, off)
        if cmd == 0x2:                                   # LC_SYMTAB
            symtab = off
        elif cmd == 0x19 and data[off + 8:off + 18] == b"__LINKEDIT":   # LC_SEGMENT_64
            linkedit = off
        off += size
    stroff, strsize = struct.unpack_from("<II", data, symtab + 16)
    pad = (-stroff) % 8
    if not pad:
        return
    le_fileoff, le_filesize = struct.unpack_from("<QQ", data, linkedit + 40)
    if stroff + strsize != le_fileoff + le_filesize or le_fileoff + le_filesize != len(data):
        sys.exit(f"{path}: string pool is not last in __LINKEDIT; cannot realign")
    data[stroff:stroff] = b"\0" * pad
    struct.pack_into("<I", data, symtab + 16, stroff + pad)
    struct.pack_into("<Q", data, linkedit + 40 + 8, le_filesize + pad)            # filesize
    vmsize = struct.unpack_from("<Q", data, linkedit + 24 + 8)[0]
    if vmsize < le_filesize + pad:
        struct.pack_into("<Q", data, linkedit + 24 + 8, (le_filesize + pad + 0x3FFF) & ~0x3FFF)
    Path(path).write_bytes(data)
    print(f"  realigned string pool +{pad}")


def run(*cmd):
    subprocess.run(cmd, check=True)


def port(src, dst):
    """Use Apple's tools only: they keep __LINKEDIT valid (LIEF rebuilds broke alignment)."""
    shutil.copyfile(src, dst)
    os.chmod(dst, 0o755)
    if "arm64" in subprocess.check_output(["lipo", "-archs", dst], text=True).split() and \
            len(subprocess.check_output(["lipo", "-archs", dst], text=True).split()) > 1:
        run("lipo", dst, "-thin", "arm64", "-output", dst)
    subprocess.run(["codesign", "--remove-signature", dst], check=False, capture_output=True)
    fix_strtab_alignment(dst)
    v = lambda t: ".".join(map(str, t[:2]))
    run("vtool", "-set-build-version", "ios", v(IOS_MINOS), v(IOS_SDK), "-replace", "-output", dst, dst)

    deps = subprocess.check_output(["otool", "-L", dst], text=True).splitlines()[1:]
    args = []
    is_dylib = "MH_DYLIB" in subprocess.check_output(["otool", "-hv", dst], text=True)
    for i, line in enumerate(deps):
        name = line.strip().split(" (")[0]
        new = remap(name)
        if i == 0 and is_dylib:      # first entry of a dylib is its own LC_ID_DYLIB
            if new != name:
                args += ["-id", new]
            continue
        if new != name:
            print(f"  {name}\n    -> {new}")
            args += ["-change", name, new]
    if not is_dylib:
        rpaths = subprocess.check_output(["otool", "-l", dst], text=True)
        if "@executable_path/Frameworks " not in rpaths:
            args += ["-add_rpath", "@executable_path/Frameworks"]
    if args:
        run("install_name_tool", *args, dst)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("dst")
    a = ap.parse_args()
    print(f"port {a.src}")
    port(a.src, a.dst)
