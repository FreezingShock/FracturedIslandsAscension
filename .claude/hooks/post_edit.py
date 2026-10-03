#!/usr/bin/env python3
"""PostToolUse (Edit|Write|MultiEdit): keep default.project.json in sync with src/.

When a script under src/ is created, the project file needs a new mapping. This hook
runs tools/gen_project.py after every src/ edit. It is SILENT (zero tokens) unless the
project file actually changed or the generator failed.
"""
import json
import os
import subprocess
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

path = ((data.get("tool_input") or {}).get("file_path") or "").replace("\\", "/")
if "/src/" not in path or not path.endswith((".lua", ".luau", ".json")):
    sys.exit(0)

root = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
project = os.path.join(root, "default.project.json")
gen = os.path.join(root, "tools", "gen_project.py")
if not os.path.exists(gen):
    sys.exit(0)

before = open(project, "rb").read() if os.path.exists(project) else b""
result = subprocess.run([sys.executable, gen], cwd=root, capture_output=True, text=True)

if result.returncode != 0:
    # e.g. duplicate instance names in one realm
    print((result.stdout + result.stderr).strip(), file=sys.stderr)
    sys.exit(2)

after = open(project, "rb").read()
if before != after:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": (
                "default.project.json was regenerated because a script was added/removed. "
                "Restart `rojo serve` and press Connect in the Studio plugin before playtesting."
            ),
        }
    }))
sys.exit(0)
