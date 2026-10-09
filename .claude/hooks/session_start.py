#!/usr/bin/env python3
"""SessionStart: inject a SMALL context pack instead of re-reading big notes.

Prints (stdout becomes session context): branch, dirty count, recent commits, script counts, the
latest vault session-log entry (if the vault is reachable), and the available workflow skills.
Keep this under ~30 lines - every line costs tokens on every session.
"""
import glob
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def run(*cmd):
    try:
        return subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=8).stdout.strip()
    except Exception:
        return ""


lines = ["## FIA session pack"]
branch = run("git", "branch", "--show-current")
dirty = len([l for l in run("git", "status", "--short").splitlines() if l.strip()])
lines.append(f"Branch `{branch or '?'}`, {dirty} uncommitted change(s). Recent commits:")
for l in run("git", "log", "--oneline", "-3").splitlines():
    lines.append(f"  {l[:110]}")

counts = run(sys.executable, os.path.join(root, "tools", "gen_project.py"), "--counts")
if counts:
    lines.append(f"Scripts (expected in Studio): {counts}")

# Latest session-log entry from the vault, if reachable on this machine.
vault = os.environ.get("OBSIDIAN_VAULT_PATH") or os.path.expanduser(r"~\Documents\Obsidian\FracturedVault")
logs = sorted(glob.glob(os.path.join(vault, "8 - Claude", "agents", "game-dev-log-*.md")))
if logs:
    text = open(logs[-1], encoding="utf-8").read()
    entries = re.findall(r"### Session: .*?(?=\n### Session: |\Z)", text, re.S)  # oldest first: the newest entry is last
    if entries:
        entry = entries[-1].splitlines()
        lines.append(f"Last vault session entry ({os.path.basename(logs[-1])}):")
        lines.append("  " + entry[0][:120])
        for l in entry[1:]:
            if l.startswith("- **Next Steps:**") or l.startswith("- **Blockers"):
                lines.append("  " + l[:220])
else:
    lines.append("Vault not found on this machine (set OBSIDIAN_VAULT_PATH) - skip vault steps.")

lines.append("Workflow skills: /fia:fia-ideate (idea -> spec) /fia:fia-feature (build) /fia:fia-verify (playtest) "
             "/fia:fia-ship (commit+log) /fia:fia-skill (create or change skills/hooks/rules).")
lines.append("Rules: default.project.json is generated (python tools/gen_project.py); "
             "Studio GUI is not in Rojo; verify with /fia:fia-verify, never paste full console logs.")
print("\n".join(lines))
