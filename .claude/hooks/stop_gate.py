#!/usr/bin/env python3
"""Stop hook: don't let a turn end while the Rojo project file is stale.

Cheap deterministic check (about 50 ms): `tools/gen_project.py --check`. Blocks at most once per
stop (stop_hook_active guard) so it can never loop.
"""
import json
import os
import subprocess
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if data.get("stop_hook_active"):
    sys.exit(0)

root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
gen = os.path.join(root, "tools", "gen_project.py")
if not os.path.exists(gen):
    sys.exit(0)

result = subprocess.run([sys.executable, gen, "--check"], cwd=root, capture_output=True, text=True)
if result.returncode != 0:
    print(json.dumps({
        "decision": "block",
        "reason": "default.project.json is out of date with src/. Run `python tools/gen_project.py`, "
                  "then tell the user to restart `rojo serve` and reconnect the Studio plugin.",
    }))
sys.exit(0)
