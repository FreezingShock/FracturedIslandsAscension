---
name: fia-focus
description: Steer the next scheduled ideation run by editing reports/ideation/FOCUS.md and pushing it to main. Use when he says "add to focus", "focus on X next", "avoid X", "clear focus", or "what's my focus".
argument-hint: <topic> | avoid <topic> | done <text> | list | clear
disable-model-invocation: true
---

# /fia-focus $ARGUMENTS

Edits `reports/ideation/FOCUS.md`, which the ideation routine reads to weight its 4 ideas. Works from any machine or cloud session.

1. `git fetch origin main`, then `git checkout main && git pull --rebase origin main` (stop and say so if the tree has other uncommitted changes).
2. Read `reports/ideation/FOCUS.md`. Keep its 2-line header; the topics are the `- ` lines under it. Drop the `(example)` line the first time a real one is added.
3. Act on the argument:
   - `<topic>`: append one line `- <topic>`, rewritten as a gap or wish in one sentence (e.g. `- Fishing has no loop yet, weight toward it`). Skip if an equivalent line exists.
   - `avoid <topic>`: append `- Avoid: <topic>`.
   - `done <text>`: delete the line that best matches `<text>` (say which).
   - `list`: print the current lines and stop (no commit).
   - `clear`: remove all topic lines, keep the header.
   - Empty argument: ask what to focus on, offer 3 gaps found in `reports/ideation/INDEX.md` statuses (parked/proposed themes) and recent `git log -10`.
4. Only `reports/ideation/FOCUS.md` may change. Commit `reports: focus <short>` and `git push origin main` (pull --rebase and retry once if rejected).
5. Report in 2 lines: the file's lines now, and that the next routine run will use them.
