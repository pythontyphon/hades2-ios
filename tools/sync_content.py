#!/usr/bin/env python3
"""Push the game's Content/ to the app's data container (Documents/Content), separately from the app.

  sync_content.py                 # stage + push everything that changed since the last push
  sync_content.py --only Shaders  # push one subtree (fast iteration on converted shaders etc.)
  sync_content.py --dry-run       # show what would be pushed
  sync_content.py --verify        # compare the device's file list against the manifest

Staging mirrors the Steam Content dir into build/content/Content with APFS clones (no extra
disk), including the 720p package/movie sets the game uses on low-memory devices, then overlays build/content_overlay/Content
(files we convert, e.g. retargeted metallibs). The manifest (build/content_manifest.json)
records what reached the device, so re-runs only send new/changed files. Reinstalling the app
keeps this data; deleting the app from the phone wipes it.
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hades_env import ENV, require  # noqa: E402

STEAM = Path(ENV["HADES_SRC"]) / "Contents/Resources/Content"
STAGE = ROOT / "build/content/Content"
OVERLAY = ROOT / "build/content_overlay/Content"
MANIFEST = ROOT / "build/content_manifest.json"
BUNDLE_ID = require("HADES_BUNDLE_ID")
DEVICE = require("HADES_DEVICE")
EXCLUDE_DIRS = set()   # both 720p (low-memory path) and 1080p sets are pushed


def stage():
    """Mirror Steam Content (+ overlay, which wins) into STAGE with clones; returns {rel: (size, mtime)}."""
    sources = {}
    for src_root in (STEAM, OVERLAY):          # later roots override earlier ones
        if not src_root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(src_root):
            rel_dir = Path(dirpath).relative_to(src_root)
            dirnames[:] = [d for d in dirnames if str(rel_dir / d) not in EXCLUDE_DIRS]
            for fn in filenames:
                sources[str(rel_dir / fn)] = Path(dirpath, fn)
    files = {}
    for rel, src in sources.items():
        dst = STAGE / rel
        st = src.stat()
        if not dst.exists() or dst.stat().st_size != st.st_size or int(dst.stat().st_mtime) != int(st.st_mtime):
            dst.parent.mkdir(parents=True, exist_ok=True)
            if dst.exists():
                dst.unlink()
            subprocess.run(["cp", "-c", "-p", str(src), str(dst)], check=True)   # APFS clone
        files[rel] = (st.st_size, int(st.st_mtime))
    return files


def devicectl(*args):
    return subprocess.run(["xcrun", "devicectl", *args], check=True)


def push(changed_rel, only):
    """Push changed files. Group them into a temp tree of clones so it's one devicectl call."""
    with tempfile.TemporaryDirectory(dir=ROOT / "build") as td:
        tree = Path(td, "Content")
        for rel in changed_rel:
            d = tree / rel
            d.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["cp", "-c", "-p", str(STAGE / rel), str(d)], check=True)
        dest = "Documents/Content"
        src = tree
        if only:
            src, dest = tree / only, f"Documents/Content/{only}"
        devicectl("device", "copy", "to", "--device", DEVICE, "--domain-type", "appDataContainer",
                  "--domain-identifier", BUNDLE_ID, "--source", str(src), "--destination", dest)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="subtree of Content to push, e.g. Shaders")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--force", action="store_true", help="ignore the manifest and push everything")
    a = ap.parse_args()

    if a.verify:
        out = subprocess.run(["xcrun", "devicectl", "device", "info", "files", "--device", DEVICE,
                              "--domain-type", "appDataContainer", "--domain-identifier", BUNDLE_ID,
                              "--subdirectory", "Documents/Content", "--recurse", "-j", "-"],
                             capture_output=True, text=True, check=True).stdout
        remote = {f["relativePath"]: f.get("size") for f in json.loads(out)["result"]["files"]
                  if f.get("type") != "directory" and "size" in f}
        manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
        bad = [r for r, (size, _) in manifest.items() if remote.get(r) != size]
        print(f"{len(manifest)} files in manifest, {len(remote)} on device, {len(bad)} missing/mismatched")
        for r in bad[:20]:
            print("  ", r)
        sys.exit(1 if bad else 0)

    print("staging (APFS clones)...")
    files = stage()
    manifest = {} if a.force or not MANIFEST.exists() else json.loads(MANIFEST.read_text())
    changed = [r for r, meta in files.items() if manifest.get(r) != list(meta)
               and (not a.only or r.startswith(a.only.rstrip("/") + "/"))]
    size = sum(files[r][0] for r in changed)
    print(f"{len(files)} files staged, {len(changed)} to push ({size / 1e9:.2f} GB)")
    if a.dry_run or not changed:
        return
    push(changed, a.only)
    for r in changed:
        manifest[r] = list(files[r])
    MANIFEST.write_text(json.dumps(manifest, indent=0, sort_keys=True))
    print("pushed; manifest updated")


if __name__ == "__main__":
    main()
