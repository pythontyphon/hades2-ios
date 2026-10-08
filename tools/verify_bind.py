#!/usr/bin/env python3
"""Offline dyld check: every import of every ported binary must resolve.

For each LC_LOAD_DYLIB of a ported binary, resolve the install name to either a file we
ship (build/shims, build/ported) or an iOS SDK .tbd, then probe-link all symbols imported
from that ordinal against it. Prints unresolved symbols; exit 1 if any (weak imports and
weak dylibs are reported but don't fail).
"""
import re, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from symbol_gap import SDK, TARGET, sdk_tbd, demangle_map  # noqa: E402

SHIPPED = {}
for base in (ROOT / "build/shims", ROOT / "build/ported"):
    for f in base.rglob("*"):
        if f.is_file() and not f.suffix in (".plist", ".h") and "Headers" not in f.parts:
            SHIPPED.setdefault(f.name, f)
SHIPPED["HadesII"] = ROOT / "build/ported/HadesII"


def resolve(install_name):
    if install_name.startswith("@rpath/"):
        return SHIPPED.get(Path(install_name).name)
    return sdk_tbd(install_name)


def deps(binary):
    """[(install_name, weak)] in ordinal order (excluding LC_ID_DYLIB)."""
    out = subprocess.check_output(["otool", "-l", binary], text=True)
    res = []
    for block in out.split("Load command")[1:]:
        m = re.search(r"cmd (LC_LOAD_DYLIB|LC_LOAD_WEAK_DYLIB|LC_REEXPORT_DYLIB|LC_LOAD_UPWARD_DYLIB)\n.*?name (\S+)", block, re.S)
        if m:
            res.append((m[2], m[1] == "LC_LOAD_WEAK_DYLIB"))
    return res


def imports(binary):
    """leaf name -> [(symbol, weak)]"""
    res = {}
    for line in subprocess.check_output(["dyld_info", "-imports", binary], text=True).splitlines():
        m = re.match(r"\s+(\S+)\s+(\[weak-import\]\s+)?\(from (\S+)\)", line)
        if m:
            res.setdefault(m[3], []).append((m[1], bool(m[2])))
    return res


def unresolved(target, syms):
    with tempfile.TemporaryDirectory() as td:
        asm = Path(td, "p.s")
        asm.write_text(".data\n.p2align 3\n" + "".join(f'.quad "{s}"\n' for s in syms))
        r = subprocess.run(["xcrun", "--sdk", "iphoneos", "clang", "-target", TARGET, "-isysroot", str(SDK),
                            "-dynamiclib", "-nostdlib", "-o", str(Path(td, "p.dylib")), str(asm), str(target)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            return []
        missing = re.findall(r'^\s+"(.+?)", referenced from', r.stderr, re.M) or ["<" + r.stderr.strip()[:400] + ">"]
        back = demangle_map(syms)
        return sorted({back.get(m, m) for m in missing})


def main(binaries):
    bad = 0
    for b in binaries:
        imp = imports(b)
        print(f"== {Path(b).name}")
        for name, weak_dylib in deps(b):
            leaf = Path(name).name.removesuffix(".dylib").split(".")[0]
            syms = imp.get(leaf, [])
            target = resolve(name)
            if target is None:
                tag = "weak dylib, absent" if weak_dylib else "MISSING DYLIB"
                print(f"  {tag}: {name} ({len(syms)} imports)")
                bad += 0 if weak_dylib else 1
                continue
            if not syms:
                continue
            miss = unresolved(target, [s for s, _ in syms])
            weak = {s for s, w in syms if w}
            hard = [m for m in miss if m not in weak]
            if miss:
                print(f"  {name}: {len(hard)} unresolved, {len(miss) - len(hard)} weak-unresolved")
                for m in miss:
                    print(f"      {m}{' (weak)' if m in weak else ''}")
            bad += len(hard)
    print("OK: all imports bind" if not bad else f"FAIL: {bad} unresolved")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
