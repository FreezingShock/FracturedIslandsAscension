---
name: recall
description: Pull relevant project memory from the Obsidian vault before working on a system. Use when starting work on an area (combat, abilities, HUD, items, skills, data), when the user says "what did we decide about", or before a design change.
argument-hint: <system or topic>
---

# recall $ARGUMENTS

Goal: the few lines of memory that change what you will do, not a dump.

1. `obsidian_search` the topic (limit 6). Prefer these notes, in order:
   - `8 - Claude/projects/fractured-islands.md`: the **Codebase & Systems Registry** rows for that system (Grep the headings, read only that section).
   - `8 - Claude/memory/projects/fractured-islands.md`: "Lessons Learned" sections that match.
   - `8 - Claude/projects/fractured-islands-master-hub.md`: design intent.
   - `8 - Claude/agents/game-dev-log-YYYY-MM.md`: Grep `### Session:` titles for the topic, then read only that entry. Never read the log whole.
2. Also check the auto-memory index (`MEMORY.md` pointers: feedback_*, reference_tooling_pitfalls) for rules that apply (modular config first, no scripted UI, save generators).
3. If vault and code disagree, trust the code, and add the disagreement to the Registry's "Open conflicts" at session end (`/fia:handoff`).
4. Output <= 10 lines: what exists (files), decisions already made, pitfalls to avoid, open conflicts. Cite note paths.

Do not rewrite design text or anything in `2 - Creations/` without his go-ahead.
