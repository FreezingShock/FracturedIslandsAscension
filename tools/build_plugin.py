#!/usr/bin/env python3
"""Sync the project-level fia-* skills and subagents into plugins/fia and validate the plugin.

The plugin's own skills (connect, recall, handoff, ...) are authored directly in plugins/fia/skills.
The legacy fia-* skills and agents are edited in .claude/ and copied here, so the repo keeps one source.

  python tools/build_plugin.py          # copy + validate
  python tools/build_plugin.py --check  # validate only
"""
import json
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = os.path.join(ROOT, "plugins", "fia")
check_only = "--check" in sys.argv

if not check_only:
    src = os.path.join(ROOT, ".claude", "skills")
    for name in sorted(os.listdir(src)):
        if os.path.isfile(os.path.join(src, name, "SKILL.md")):
            shutil.copytree(os.path.join(src, name), os.path.join(PLUGIN, "skills", name), dirs_exist_ok=True)
    agents = os.path.join(ROOT, ".claude", "agents")
    os.makedirs(os.path.join(PLUGIN, "agents"), exist_ok=True)
    for f in os.listdir(agents):
        shutil.copy2(os.path.join(agents, f), os.path.join(PLUGIN, "agents", f))

errors = []
for path in (os.path.join(PLUGIN, ".claude-plugin", "plugin.json"), os.path.join(PLUGIN, ".mcp.json"),
             os.path.join(ROOT, ".claude-plugin", "marketplace.json")):
    try:
        with open(path, encoding="utf-8") as fh:
            json.load(fh)
    except Exception as e:
        errors.append(f"{os.path.relpath(path, ROOT)}: {e}")

skills = os.path.join(PLUGIN, "skills")
for name in sorted(os.listdir(skills)):
    f = os.path.join(skills, name, "SKILL.md")
    if not os.path.isfile(f):
        errors.append(f"{name}: no SKILL.md")
        continue
    with open(f, encoding="utf-8") as fh:
        text = fh.read()
    m = re.match(r"---\r?\n(.*?)\r?\n---", text, re.S)
    if not m:
        errors.append(f"{name}: no frontmatter")
        continue
    fm = m.group(1)
    n = re.search(r"^name:\s*(.+)$", fm, re.M)
    d = re.search(r"^description:\s*(.+)$", fm, re.M)
    if not n or n.group(1).strip() != name:
        errors.append(f"{name}: name must equal folder")
    if not d or len(d.group(1)) > 330:
        errors.append(f"{name}: description missing or too long")

print("\n".join(errors) if errors else f"plugin ok: {len(os.listdir(skills))} skills")
sys.exit(1 if errors else 0)
