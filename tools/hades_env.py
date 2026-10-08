"""Shared settings for the Python tools: local.env (git-ignored) overlaid by the environment."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _load():
    env = {}
    f = ROOT / "local.env"
    if f.exists():
        for line in f.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = os.path.expandvars(v.strip().strip('"'))
    env.update({k: v for k, v in os.environ.items() if k.startswith("HADES_")})
    env.setdefault("HADES_SRC", str(Path.home() / "Library/Application Support/Steam/steamapps/common/Hades II/Hades II.app"))
    return env


ENV = _load()


def require(name):
    if not ENV.get(name):
        raise SystemExit(f"error: {name} is not set - copy local.env.example to local.env")
    return ENV[name]
