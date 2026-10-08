#!/usr/bin/env python3
"""Fetch the newest HadesII crash/jetsam report from the phone and print the useful parts."""
import json, re, subprocess, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hades_env import require  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
DEVICE = require("HADES_DEVICE")
out = subprocess.run(["xcrun", "devicectl", "device", "info", "files", "--device", DEVICE,
                      "--domain-type", "systemCrashLogs"], capture_output=True, text=True).stdout
names = sorted(set(re.findall(r"^((?:HadesII|JetsamEvent)[^\s]*\.ips)", out, re.M)))
pick = [n for n in names if n.startswith("HadesII")][-1:] + [n for n in names if n.startswith("JetsamEvent")][-1:]
dest = ROOT / "build/crashes"; dest.mkdir(parents=True, exist_ok=True)
for n in pick:
    p = dest / n
    if not p.exists():
        subprocess.run(["xcrun", "devicectl", "device", "copy", "from", "--device", DEVICE, "--domain-type",
                        "systemCrashLogs", "--source", n, "--destination", str(p)], capture_output=True)
    head, body = p.read_text().split("\n", 1)
    b = json.loads(body)
    print(f"== {n}")
    if n.startswith("JetsamEvent"):
        for proc in b.get("processes", []):
            if proc.get("name", "").startswith("HadesII"):
                print("  jetsam:", {k: proc.get(k) for k in ("reason", "rpages", "lifetimeMax", "states")},
                      "pageSize", b.get("pageSize"), "memLimit?", proc.get("memoryLimit"))
        continue
    print("  termination:", json.dumps(b.get("termination"))[:500])
    print("  exception:", b.get("exception"))
    imgs = b["usedImages"]
    for t in b["threads"]:
        if t.get("triggered"):
            print("  thread", t.get("name"), t.get("queue"))
            for fr in t["frames"][:25]:
                print("     ", imgs[fr["imageIndex"]].get("name", "?")[:26].ljust(26), fr.get("symbol", hex(fr["imageOffset"])))
