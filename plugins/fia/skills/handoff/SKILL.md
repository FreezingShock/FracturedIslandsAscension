---
name: handoff
description: End-of-session save to the Obsidian vault so the next session (desktop or MacBook) resumes cleanly. Use when wrapping up, switching machines, or when the user says "log this", "save progress", or "hand off".
---

# handoff

For a shipped, verified change `/fia-ship` already logs; use this when work is **unshipped, partial, or switching machines**, or to add lessons.

1. **Repo state:** `git status --short`, `git log --oneline -3`, any unpushed commits. If the work is verified, ship it (`/fia-ship`) rather than hand off. Unverified code is not pushed.
2. **Session entry:** append to `8 - Claude/agents/game-dev-log-YYYY-MM.md` with `obsidian_update_note` (`append`, no heading, never read the note first, newest at the bottom; new month = new note with the same header). Fields: title + version, what changed (files), verified vs not, **Where I stopped / next step**, blockers/lessons.
3. **Registry:** update only changed rows in the Codebase & Systems Registry with `obsidian_replace_text`. Code-vs-vault disagreements go to "Open conflicts".
4. **Lessons:** durable rules/blockers go to `8 - Claude/memory/projects/fractured-islands.md` (see `/fia:lesson`).
5. Wikilinks never end in `.md`. No Ctrl+S reminders, no "Studio-only manifest". Extend existing notes; create no new vault docs.
6. Vault MCP down: write the entry as a short note in the reply and say the vault log is pending.

Main thread only; no subagents for vault writes.
