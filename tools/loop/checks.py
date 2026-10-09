#!/usr/bin/env python3
"""
Static checks for the autonomous loop (/fia-loop). Stdlib only, no Studio, no network.

Runs every check it can and reports each one as pass / fail / skip, so a missing tool
never hides the rest. Output is JSON on stdout (the loop reads it) and a summary on stderr.

  python tools/loop/checks.py [--vault PATH] [--strict]

  --vault PATH   FracturedIslandsVault clone (default: $FIA_VAULT_PATH or /home/user/fracturedislandsvault)
  --strict       exit 1 when any check fails (default: always exit 0, the loop decides)

Checks:
  gen_project    default.project.json matches src/ (tools/gen_project.py --check)
  check_skills   skill files validate (tools/check_skills.py)
  rojo_build     `rojo build` succeeds (skipped when rojo is not installed)
  selene         `selene src` is clean (skipped when selene is not installed)
  card_paths     every card's code_paths exist in this repo
  card_stale     cards whose code_paths changed since verified_commit
  index_links    every [[link]] in Index.md resolves to a card
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
args = sys.argv[1:]
strict = "--strict" in args
vault = os.environ.get("FIA_VAULT_PATH") or "/home/user/fracturedislandsvault"
if "--vault" in args:
    vault = args[args.index("--vault") + 1]

results = []


def record(name, status, detail=""):
    results.append({"check": name, "status": status, "detail": detail[:600]})


def run(cmd, cwd=ROOT, timeout=300):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except FileNotFoundError:
        return None, "not installed"
    except subprocess.TimeoutExpired:
        return 124, "timed out"


# ---- project and tooling checks ----
code, out = run([sys.executable, os.path.join(ROOT, "tools", "gen_project.py"), "--check"])
record("gen_project", "pass" if code == 0 else "fail", out.splitlines()[-1] if out else "")

code, out = run([sys.executable, os.path.join(ROOT, "tools", "check_skills.py")])
record("check_skills", "pass" if code == 0 else "fail", out.splitlines()[-1] if out else "")

if shutil.which("rojo"):
    code, out = run(["rojo", "build", "default.project.json", "-o", os.path.join(tempfile.mkdtemp(), "check.rbxlx")])
    record("rojo_build", "pass" if code == 0 else "fail", out.splitlines()[-1] if out else "")
else:
    record("rojo_build", "skip", "rojo not installed")

if shutil.which("selene"):
    code, out = run(["selene", "src"])
    record("selene", "pass" if code == 0 else "fail", out.splitlines()[-1] if out else "")
else:
    record("selene", "skip", "selene not installed")


# ---- vault cards ----
def read_frontmatter(path):
    """Minimal frontmatter parser: `key: value` and `key:` followed by `  - item` lines."""
    text = open(path, encoding="utf-8").read()
    if not text.startswith("---"):
        return {}, text
    head, _, body = text[3:].partition("\n---")
    data, key = {}, None
    for line in head.splitlines():
        m = re.match(r"^([A-Za-z_]+):\s*(.*)$", line)
        if m:
            key, value = m.group(1), m.group(2).strip()
            data[key] = [] if value == "" else value
        elif key and re.match(r"^\s+-\s+", line):
            data[key].append(re.sub(r"^\s+-\s+", "", line).strip())
    return data, body


cards = []
if os.path.isdir(vault):
    for folder in ("systems", "weapons", "ui", "blender", "roblox-studio", "gotchas", "decisions"):
        d = os.path.join(vault, folder)
        if os.path.isdir(d):
            for name in sorted(os.listdir(d)):
                if name.endswith(".md"):
                    cards.append(os.path.join(d, name))

    if not cards:
        record("card_paths", "skip", "no cards found in vault")
        record("card_stale", "skip", "no cards found in vault")
    else:
        missing, stale, unknown = [], [], []
        for path in cards:
            fm, _ = read_frontmatter(path)
            rel = os.path.relpath(path, vault)
            paths = fm.get("code_paths")
            if not isinstance(paths, list) or not paths:
                continue  # gotchas and decisions have no code paths
            for p in paths:
                if not os.path.exists(os.path.join(ROOT, p)):
                    missing.append(f"{rel}: {p}")
            verified = fm.get("verified_commit", "")
            if not verified:
                unknown.append(rel)
                continue
            code, out = run(["git", "rev-list", "--count", f"{verified}..HEAD", "--", *paths])
            if code != 0:
                unknown.append(f"{rel} (commit {verified} not in clone)")
            elif out.strip() not in ("", "0"):
                stale.append(f"{rel}: {out.strip()} commit(s) since {verified}")
        record("card_paths", "pass" if not missing else "fail", "; ".join(missing) or "all code_paths exist")
        detail = "; ".join(stale) or "none"
        if unknown:
            detail += f" | unchecked: {', '.join(unknown)}"
        record("card_stale", "pass" if not stale else "fail", detail)

    index = os.path.join(vault, "Index.md")
    if os.path.exists(index):
        links = re.findall(r"\[\[([^\]|]+)", open(index, encoding="utf-8").read())
        broken = [l for l in links if not os.path.exists(os.path.join(vault, l + ".md"))]
        record("index_links", "pass" if not broken else "fail", "broken: " + ", ".join(broken) if broken else f"{len(links)} links ok")
    else:
        record("index_links", "skip", "Index.md not found")
else:
    for name in ("card_paths", "card_stale", "index_links"):
        record(name, "skip", f"vault not found at {vault}")

summary = {
    "pass": sum(r["status"] == "pass" for r in results),
    "fail": sum(r["status"] == "fail" for r in results),
    "skip": sum(r["status"] == "skip" for r in results),
    "checks": results,
}
print(json.dumps(summary, indent=2))
print(f"checks: {summary['pass']} pass, {summary['fail']} fail, {summary['skip']} skip", file=sys.stderr)
sys.exit(1 if strict and summary["fail"] else 0)
