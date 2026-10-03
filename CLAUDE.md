# Fractured Islands: Ascension (FIA) — Claude Code notes

Roblox incremental/progression game (Hypixel SkyBlock-style skills + stats). Solo dev. See `README.md` for design pillars and completed systems.

## Tooling
- Scripts are edited in `src/` and synced into Studio with **Rojo 7.7.0** (`rojo serve`). Sync is one-way: disk -> Studio.
- **Roblox_Studio MCP** (`mcp__Roblox_Studio__*`) is connected to the open place. Always call `list_roblox_studios` first and pass `studio_id`. Use it to inspect the live tree, read console output, run Luau, and playtest.
- Lint/format: `selene.toml`, `.luaurc` (nonstrict). Keep existing code style (tabs).

## Rojo mapping (`default.project.json`)
| Disk | Studio |
|---|---|
| `src/Server` | `ServerScriptService` |
| `src/Shared/Modules` | `ReplicatedStorage.Modules` |
| `src/Client` | `StarterPlayer.StarterPlayerScripts` |

**GUI is NOT in Rojo.** All ScreenGuis/Frames (SkillDescFrame, TemporaryMenus, tooltips, grids) live only in the Studio place file. Scripts reach into them by name with `WaitForChild`. To change UI structure, use the Studio MCP (`inspect_instance`, `execute_luau`, `multi_edit`) and verify with `screen_capture`; renaming an instance breaks the scripts that look it up by name.

Naming: `*.client.lua` = LocalScript, `*.server.lua` = Script, plain `.lua` = ModuleScript.

## Architecture
- **Server-authoritative.** Clients never compute final stats. Server modules own data; clients get state via RemoteEvents (e.g. `SkillUpdated`) and only render.
- **Persistence:** `ProfileService` (`src/Server/ProfileService.luau`). One profile per player in `SkillsDataManager` (`PlayerSkills_v1`): skills at top level, inventory under `_Inventory`. `InventoryDataManager` reaches the profile through `SkillsDataManager.GetProfile` / `GetInventoryData`. New fields go in `PROFILE_TEMPLATE`; `Reconcile()` backfills existing players, so don't bump the store name.
- **Skills:** 6 skills (Farming, Foraging, Fishing, Mining, Combat, Carpentry), levels 1–50, `XP_THRESHOLDS` in `SkillsDataManager`. Client payload = `{level, xp, xpNeeded, roman, pct}` per skill.
- **UI:** `CentralizedMenuController` (client) owns menu open/close/navigate and passes a `sharedRefs` table to page modules. Page modules in `Shared/Modules` expose `init(sharedRefs, frame)`, `open(arg)`, `close()` (animated), `reset()` (instant). `GridMenuModule` is config-driven grids with stack navigation; `TooltipModule` is a single shared tooltip keyed by source id (`showRaw(key)` / `hide(key)`) so page modules don't clobber each other. `LiquidGlassHandler` is the glass effect.
- **Stat formula:** `Final = (Base + Flat) x (1 + sum(Multipliers))`.

## UI conventions (from `SkillsPageModule`)
- Minecraft color-code palette: gold `#FFAA00`, green `#55FF55`, red `#FF5555`, yellow `#FFFF55`, aqua `#55FFFF`, light-purple `#FF55FF`, gray `#AAAAAA`/`#555555`, gold-title `#FFD700`. Per-skill colors live in `SKILL_CONFIG`.
- Rich text via `<font color='#...'>` in labels; Roman numerals toggle via `displayLevel`.
- Tweens: `Quint`/`Out`, ~0.3–0.5s. Fades use `CanvasGroup.GroupTransparency`.
- Sounds come from `workspace.UISounds` (`Click`, `Click3`).
- Wire event connections once in `init`, never in `open`.

## Known issues / cleanup
- Stray instances in the live place's Workspace: copies of `ProfileService` and `LiquidGlassHandler`, UI frames `Griffin`/`Boltrod`/`EmberFlare`/`MobRemains`, and several unnamed Models. Confirm with Nate before deleting.
- `ChangeSkill` RemoteEvent admin check is a hardcoded `ADMIN_IDS` list in `SkillsDataManager`.
- `SkillsPageModule` yields on `workspace:WaitForChild("UISounds")` at require time.

## Vault memory workflow (Obsidian second brain)
The `obsidian-second-brain` MCP (`mcp__plugin_obsidian-second-brain_vault__*`) is this project's long-term memory and log. Vault paths are relative to `FracturedVault`; use the real `✦`/`✷` characters, never copy-pasted ones.
- **Session start:** `obsidian_read_note` on `8 - Claude/agents/game-dev.md` (current focus + newest session entry) and the **Codebase & Systems Registry** section of `8 - Claude/projects/fractured-islands.md`. Design intent lives in `8 - Claude/projects/fractured-islands-master-hub.md`.
- **During work:** if the vault and the code disagree, trust the code for what exists and add the disagreement to the Registry's "Open conflicts" list. Do not rewrite design text or anything in `2 - Creations/` without Nate's explicit go-ahead.
- **Session end:** update only the Registry rows that changed (`obsidian_replace_text`), append a dated entry to `game-dev.md` (`obsidian_update_note`, heading `Session Log`), and put durable lessons/blockers in `8 - Claude/memory/projects/fractured-islands.md`. Extend existing notes; do not create new vault documentation files.
- Main thread only; no subagents for vault writes.

## Working agreements
- Don't commit or push unless asked. Commit messages follow the repo's style: `3.31.1 - Short description of changes`.
- Prefer editing existing modules over adding new ones; follow the `init/open/close/reset` page-module contract.
- Verify UI changes in a playtest (`start_stop_play`, `get_console_output`, `screen_capture`) before calling them done.
