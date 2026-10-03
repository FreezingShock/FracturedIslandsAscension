#!/usr/bin/env python3
"""Copy this repo's skills and subagents to your USER-level Claude Code folders so they work in every project
on this machine (the repo's own .claude/ already works when you open the repo).

  python tools/install_skills.py            # skills -> ~/.claude/skills, agents -> ~/.claude/agents
  python tools/install_skills.py --dry-run  # show what would be copied

New machine: git clone the repo, run this once, done. Re-run after `git pull` to update.
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
dry = "--dry-run" in sys.argv


def copy_tree(src, dst):
    print(("would copy " if dry else "copy ") + os.path.relpath(src, ROOT) + " -> " + dst)
    if not dry:
        shutil.copytree(src, dst, dirs_exist_ok=True)


skills = os.path.join(ROOT, ".claude", "skills")
for name in sorted(os.listdir(skills)):
    if os.path.isfile(os.path.join(skills, name, "SKILL.md")):
        copy_tree(os.path.join(skills, name), os.path.join(HOME, ".claude", "skills", name))

agents = os.path.join(ROOT, ".claude", "agents")
for fn in sorted(os.listdir(agents)):
    if fn.endswith(".md"):
        dst = os.path.join(HOME, ".claude", "agents", fn)
        print(("would copy " if dry else "copy ") + f".claude/agents/{fn} -> {dst}")
        if not dry:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(os.path.join(agents, fn), dst)
