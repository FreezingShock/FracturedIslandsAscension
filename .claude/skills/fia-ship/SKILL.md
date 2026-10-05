---
name: fia-ship
description: Wrap up a work session - commit with the repo's version-title convention, update the vault registry and session log, and push to `main`. Runs automatically at the end of /fia-feature once the change is verified, or on request.
---

# /fia-ship

1. **Preflight:** `git status --short`, `python tools/gen_project.py --check`. Never commit `Blender/` renders or
   secrets; leave unrelated untracked files alone. Do not ship if the last `/fia-verify` was FAIL.
2. **Commit** in logical groups (not one giant commit). Title format: `3.xx.x - short description`
   (bump the last commit's version: patch for fixes, minor for features; check `git log -1 --oneline`).
   Body optional. End with the attribution line your system reminder specifies.
3. **Vault** (only if the vault path exists; use the MCP, never recreate notes):
   - `obsidian_replace_text` on the touched **registry rows** in `8 - Claude/projects/fractured-islands.md`
     (what changed, new modules, new gotchas).
   - `obsidian_update_note` (`append`, no heading) to add a `### Session:` entry to the current month's
     `8 - Claude/agents/game-dev-log-YYYY-MM.md` (Topic, Work Completed, Blockers, Decisions, Next Steps). Oldest first,
     newest at the bottom; never read the note first (~30k chars); append blind. Automatic (the user's call, 2026-10-04); skip only when
     the Obsidian MCP is disconnected and say the log is pending.
   - Durable lessons only -> `8 - Claude/memory/projects/fractured-islands.md` (append).
   - A correction or preference the user stated -> also save it to memory (capture every correction).
4. **Push** straight to `main`: `git push origin main`. No feature branches and no PRs (the user's call, 2026-10-03).
   Never force-push.
5. **Report in <=8 lines:** commits (hashes+titles), pushed yes/no, vault updated yes/no, user to-dos
   (restart Rojo, etc.).
