---
name: connect
description: Start-of-session bring-up for Fractured Islands Ascension. Use on "connect and load", "start up", "load everything", or when opening a session on the desktop or MacBook; pulls main, regenerates the Rojo project, serves, and checks Studio and the vault.
---

# connect

Run the independent steps in parallel, then report one short status block.

1. **Machine:** `python` on Windows (desktop), `python3` on macOS (MacBook). Use whichever exists for every `tools/*.py` call.
2. **Pull:** `git pull --ff-only origin main` (he works from several machines/sessions). Dirty tree: say so, do not stash.
3. **Rojo:** if scripts were added/moved/removed (check the pull output), run `tools/gen_project.py`, then `tools/restart_rojo.py` (kills the old rojo by PID, restarts, waits for the port). Otherwise start `rojo serve` in the background if nothing listens. Never hand-edit `default.project.json`.
4. **Studio:** `list_roblox_studios`; pass the id on every later call (ids change per Studio restart). Zero studios: say Studio is closed and skip that branch. On macOS the bundled `.mcp.json` Roblox_Studio entry is Windows-only; if the tool is missing there, tell him to add the Mac Studio MCP path to his user config instead of guessing one.
5. **Vault:** load the obsidian tools (`ToolSearch obsidian`). If the MCP is down, the vault is a plain folder: Grep/Read it directly.
6. **Context:** `/fia:recall` for the area he names, if any. Do not read the whole month log (~50k chars).
7. **Report:** branch + commits pulled, rojo up, Studio id, vault reachable, and one line: "press Connect in the Rojo plugin" (that part is his).

Never ask him to Ctrl+S (Team Create autosaves).
