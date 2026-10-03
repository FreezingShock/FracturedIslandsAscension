---
name: fia-ship
description: Wrap up a work session - commit with the repo's version-title convention, update the vault registry and session log, and push to `main`. Manual only. Use at the end of a feature or session.
disable-model-invocation: true
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
   - `obsidian_replace_text` to insert a new `### Session:` entry at the top of the Session Log in
     `8 - Claude/agents/game-dev.md` using its template (Topic, Work Completed, Blockers, Decisions, Next Steps).
   - Durable lessons only -> `8 - Claude/memory/projects/fractured-islands.md` (append).
   - A correction or preference the user stated -> also save it to memory (capture every correction).
4. **Push** straight to `main`: `git push origin main`. No feature branches and no PRs (the user's call, 2026-10-03).
   Never force-push.
5. **Report in <=8 lines:** commits (hashes+titles), pushed yes/no, vault updated yes/no, user to-dos
   (save the place with Ctrl+S, restart Rojo, etc.).
