#!/usr/bin/env python3
"""Report which symbols a macOS Mach-O imports that the iOS SDK does not provide.

For every dependent library of each binary: map the macOS install path to its iOS
equivalent, then link a probe dylib that references every imported symbol against
the iOS SDK. Whatever the linker reports as undefined is the shim to-do list.
Output: shims/GAP_REPORT.md (+ shims/gap/<binary>/<lib>.txt raw symbol lists).
"""
import re, subprocess, sys, tempfile, collections
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SDK = Path(subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip())
TARGET = "arm64-apple-ios26.0"


def ios_path(mac_path):
    """macOS install name -> iOS install name (or None when the dylib is bundled / @rpath)."""
    m = re.match(r"/System/Library/(Frameworks|PrivateFrameworks)/(\w+)\.framework/Versions/\w+/(\w+)$", mac_path)
    if m:
        return f"/System/Library/{m[1]}/{m[2]}.framework/{m[3]}"
    if mac_path.startswith("/usr/lib/"):
        return mac_path
    return None


def sdk_tbd(ios):
    p = SDK / ios.lstrip("/")
    for c in (p.with_suffix(".tbd"), Path(str(p) + ".tbd")):
        if c.exists():
            return c
    return None


def sdk_has(ios):
    return sdk_tbd(ios) is not None


def dependents(binary):
    out = subprocess.check_output(["otool", "-L", binary], text=True).splitlines()[1:]
    return [l.strip().split(" (")[0] for l in out]


def imports(binary):
    """leaf name -> [symbols]"""
    res = collections.defaultdict(list)
    for line in subprocess.check_output(["dyld_info", "-imports", binary], text=True).splitlines():
        m = re.match(r"\s+(\S+)\s+\(from (\S+)\)", line)
        if m:
            res[m[2]].append(m[1])
    return res


def leaf(path):
    return Path(path).name.removesuffix(".dylib").split(".")[0]


def demangle_map(syms):
    """ld prints demangled names; map them back to the mangled originals."""
    back = {}
    for tool in (["xcrun", "swift-demangle"], ["xcrun", "c++filt"]):
        out = subprocess.run(tool, input="\n".join(syms), capture_output=True, text=True).stdout.splitlines()
        for orig, dem in zip(syms, out):
            back.setdefault(dem, orig)
            back.setdefault(dem.lstrip("_"), orig)
    return back


def missing_symbols(ios, syms):
    """Link a probe referencing syms against the iOS lib; return undefined ones."""
    with tempfile.TemporaryDirectory() as td:
        asm = Path(td, "probe.s")
        asm.write_text(".data\n.p2align 3\n" + "".join(f".quad {s}\n" for s in syms))
        tbd = sdk_tbd(ios)
        r = subprocess.run(["xcrun", "--sdk", "iphoneos", "clang", "-target", TARGET, "-dynamiclib",
                            "-nostdlib", "-o", str(Path(td, "probe.dylib")), str(asm), str(tbd),
                            "-Wl,-undefined,error", "-Wl,-w"], capture_output=True, text=True)
        if r.returncode == 0:
            return []
        missing = re.findall(r'^\s+"(.+?)", referenced from', r.stderr, re.M)
        if not missing:
            missing = re.findall(r"^\s+(_\S+)$", r.stderr, re.M)
        if missing:
            back = demangle_map(syms)
            return sorted({back.get(m, m) for m in missing})
        return ["<link failed: " + r.stderr.strip()[:300] + ">"]


def main(binaries):
    report = ["# Symbol gap report (macOS imports not provided by the iOS SDK)\n",
              f"SDK: `{SDK.name}`  target: `{TARGET}`\n"]
    for b in binaries:
        b = Path(b)
        imp = imports(str(b))
        rows, details = [], []
        gapdir = ROOT / "shims/gap" / b.name.replace(" ", "_")
        gapdir.mkdir(parents=True, exist_ok=True)
        for dep in dependents(str(b)):
            name = leaf(dep)
            syms = imp.get(name, [])
            ios = ios_path(dep)
            if ios is None:
                rows.append((dep, "bundled/@rpath", len(syms), "-"))
                (gapdir / f"{name}.txt").write_text("\n".join(syms) + "\n")
                continue
            if not sdk_has(ios):
                rows.append((dep, "**absent on iOS**", len(syms), len(syms)))
                (gapdir / f"{name}.txt").write_text("\n".join(syms) + "\n")
                details.append((name, syms))
                continue
            miss = missing_symbols(ios, syms) if syms else []
            rows.append((dep, ios, len(syms), len(miss)))
            if miss:
                (gapdir / f"{name}.txt").write_text("\n".join(miss) + "\n")
                details.append((name, miss))
        report.append(f"\n## `{b.name}`\n\n| macOS dependency | iOS path | imports | missing |\n|---|---|---|---|")
        report += [f"| `{d}` | {i if i.startswith('*') or i.startswith('b') else '`'+i+'`'} | {n} | {m} |" for d, i, n, m in rows]
        for name, miss in details:
            report.append(f"\n<details><summary>{name}: {len(miss)} missing</summary>\n\n```\n" + "\n".join(miss) + "\n```\n</details>")
    out = ROOT / "shims/GAP_REPORT.md"
    out.write_text("\n".join(report) + "\n")
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
