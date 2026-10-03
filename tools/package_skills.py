#!/usr/bin/env python3
"""Zip each skill in .claude/skills/ into dist/skills/<name>.zip for upload to claude.ai
(Settings > Capabilities > Skills > Upload). Each zip contains the skill folder at its root.

Note: skills that drive Roblox Studio (fia-verify, fia-feature) need the Studio MCP and a coding agent,
so they are only useful in Claude Code / Claude desktop with MCP. fia-ideate and fia-skill are the
claude.ai-friendly ones. Pass skill names to package a subset.

  python tools/package_skills.py [name ...]
"""
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
skills = os.path.join(ROOT, ".claude", "skills")
out_dir = os.path.join(ROOT, "dist", "skills")
os.makedirs(out_dir, exist_ok=True)
wanted = set(sys.argv[1:])

for name in sorted(os.listdir(skills)):
    folder = os.path.join(skills, name)
    if not os.path.isfile(os.path.join(folder, "SKILL.md")) or (wanted and name not in wanted):
        continue
    target = os.path.join(out_dir, name + ".zip")
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for dp, _, files in os.walk(folder):
            for f in files:
                full = os.path.join(dp, f)
                z.write(full, os.path.join(name, os.path.relpath(full, folder)))
    print("wrote", os.path.relpath(target, ROOT))
