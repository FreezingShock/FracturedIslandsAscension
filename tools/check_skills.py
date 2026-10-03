#!/usr/bin/env python3
"""Validate .claude/skills/*/SKILL.md and .claude/agents/*.md.

Checks: frontmatter present, `name` matches the folder (skills) or filename (agents), `description` present and
not bloated (it is loaded into every session), no stray non-skill folders. Exit 1 on any error.
Usage: python tools/check_skills.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_DESC = 400
errors = []


def frontmatter(path):
    text = open(path, encoding="utf-8").read().replace("\r\n", "\n")
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    fields = {}
    for line in m.group(1).splitlines():
        if ":" in line and not line.lstrip().startswith("#") and not line.startswith(" "):
            k, v = line.split(":", 1)
            fields[k.strip()] = v.strip()
    return fields


skills_dir = os.path.join(ROOT, ".claude", "skills")
for name in sorted(os.listdir(skills_dir)) if os.path.isdir(skills_dir) else []:
    folder = os.path.join(skills_dir, name)
    if not os.path.isdir(folder):
        continue
    md = os.path.join(folder, "SKILL.md")
    if not os.path.exists(md):
        errors.append(f"skills/{name}: missing SKILL.md (non-skill folders belong outside .claude/skills)")
        continue
    fm = frontmatter(md)
    if fm is None:
        errors.append(f"skills/{name}: no frontmatter")
        continue
    if fm.get("name") != name:
        errors.append(f"skills/{name}: frontmatter name '{fm.get('name')}' must equal the folder name")
    desc = fm.get("description", "")
    if not desc:
        errors.append(f"skills/{name}: missing description")
    elif len(desc) > MAX_DESC:
        errors.append(f"skills/{name}: description is {len(desc)} chars (max {MAX_DESC}); it loads every session")

agents_dir = os.path.join(ROOT, ".claude", "agents")
for fn in sorted(os.listdir(agents_dir)) if os.path.isdir(agents_dir) else []:
    if not fn.endswith(".md"):
        continue
    fm = frontmatter(os.path.join(agents_dir, fn))
    if fm is None:
        errors.append(f"agents/{fn}: no frontmatter")
        continue
    if fm.get("name") != fn[:-3]:
        errors.append(f"agents/{fn}: frontmatter name '{fm.get('name')}' must equal the filename")
    if not fm.get("description"):
        errors.append(f"agents/{fn}: missing description")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print("skills and agents OK")
