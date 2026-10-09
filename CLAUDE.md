# Fractured Islands: Ascension (FIA) — Claude Code notes

Roblox incremental/progression game (Hypixel SkyBlock-style skills + stats). Solo dev. See `README.md` for design pillars and completed systems.

## Tooling
- Scripts are edited in `src/` and synced into Studio with **Rojo 7.7.0** (`rojo serve`). Sync is one-way: disk -> Studio.
- **Roblox_Studio MCP** (`mcp__Roblox_Studio__*`) is connected to the open place. Always call `list_roblox_studios` first and pass `studio_id`. Use it to inspect the live tree, read console output, run Luau, and playtest.
- Lint/format: `selene.toml`, `.luaurc` (nonstrict). Keep existing code style (tabs).

## Rojo mapping (`default.project.json`)
| Disk | Studio |
|---|---|
| `src/Server/**` | `ServerScriptService` (flat) |
| `src/Shared/Modules/**` | `ReplicatedStorage.Modules` (flat) |
| `src/Client/**` | `StarterPlayer.StarterPlayerScripts` (flat) |

**Layout:** each realm (`src/Server`, `src/Shared/Modules`, `src/Client`) is organised into **system folders** (`Data`, `Inventory`, `Buttons`, `Combat`, `World`, `Chat`, `Admin`; Shared also has `Menu`, `Stats`, `Config`, `Util`; Client also has `Menu`, `HUD`). The folders exist only on disk: in Studio every script is still flat (`ReplicatedStorage.Modules.StatisticsConfig`, `ServerScriptService.SkillsDataManager`), so `WaitForChild("Name")` lookups never change.
- `default.project.json` is **generated**. After adding, moving, renaming or deleting a script run `python tools/gen_project.py` (or `--check`), then restart `rojo serve` and reconnect the Studio plugin. Never hand-edit the project file.
- A folder containing `init.lua` / `init.meta.json` is ONE Studio instance (module with children, or a Folder). Plain folders are organisation only. Script instance names must be unique within a realm (the generator errors on duplicates).
- Folder instances that exist in Studio (`Modules.Config`, `Modules.Button`, client `Button`) are kept by an `init.meta.json` (`{"className":"Folder"}`).
- Verify a reorganisation with `rojo build default.project.json -o x.rbxlx` before and after and compare the instance trees.

**GUI is NOT in Rojo.** All ScreenGuis/Frames (SkillDescFrame, TemporaryMenus, tooltips, grids) live only in the Studio place file. Scripts reach into them by name with `WaitForChild`. To change UI structure, use the Studio MCP (`inspect_instance`, `execute_luau`, `multi_edit`) and verify with `screen_capture`; renaming an instance breaks the scripts that look it up by name.

Naming: `*.client.lua` = LocalScript, `*.server.lua` = Script, plain `.lua` = ModuleScript.

## Workflow automation (committed in `.claude/`, works on any machine after `git clone`)
- **Skills:** `/fia:fia-ideate <idea>` (idea -> spec) -> `/fia:fia-feature <idea>` (branch, build, verify, review) -> `/fia:fia-verify` (token-lean playtest) -> `/fia:fia-ship` (commit, vault log, push). `/fia:fia-skill <idea or restriction>` creates or changes skills, hooks, subagents, permissions and rules.
- **Subagent:** `lua-explorer` (read-only code search). Verification runs inline via `/fia:fia-verify`; large-feature reviews use the `fia-reviewer` subagent (haiku, low effort); `/code-review high` only with his explicit permission.
- **Review checklist:** async callbacks that mutate reused state check `PlaybackState`/generation (tween `Completed` fires on Cancel); saved-data changes backfill via `Reconcile`; server never trusts client values; new RemoteEvents type-check inputs; GUI is looked up by name, so renames break scripts; script names are unique per realm.
- **Hooks:** blocks hand edits to generated files; regenerates `default.project.json` when a script is added; Stop is blocked while the project file is stale; a small context pack loads at session start.
- **How Nate drives it:** `/fia:fia-ideate <topic list>` -> answers 3-4 questions -> pastes the `/fia:fia-feature` prompt -> "connected, verify it" (or tests it himself) -> small follow-ups. Once a change is verified, commit + push to `main` + vault session log happen automatically (his call, 2026-10-04); never ship unverified or failing code. Specs always state config shape (library -> type -> override), out of scope, and verification.
- **Token rules:** never call `get_console_output` (use `/fia:fia-verify`); `Grep`/partial reads instead of whole files; text assertions over screenshots; `/clear` between features.
- Install the skills user-wide with `python tools/install_skills.py`; validate with `python tools/check_skills.py`.

## Architecture
- **Server-authoritative.** Clients never compute final stats. Server modules own data; clients get state via RemoteEvents (e.g. `SkillUpdated`) and only render.
- **Persistence:** `ProfileService` (`src/Server/Data/ProfileService.luau`). One profile per player in `SkillsDataManager` (`PlayerSkills_v1`): skills at top level, inventory under `_Inventory`. `InventoryDataManager` reaches the profile through `SkillsDataManager.GetProfile` / `GetInventoryData`. New fields go in `PROFILE_TEMPLATE`; `Reconcile()` backfills existing players, so don't bump the store name.
- **Skills:** 6 skills (Farming, Foraging, Fishing, Mining, Combat, Carpentry), levels 1–50, `XP_THRESHOLDS` in `SkillsDataManager`. Client payload = `{level, xp, xpNeeded, roman, pct}` per skill.
- **HUD:** one `StarterGui.FIAHUD` (built by `tools/studio/build_fiahud.luau` + `build_fiahud_vines.luau`, all numbers/colours in `Config/HudTheme`) replaces StatsMenu and holds the hotbar: Health/Mana panels, the 16-segment Stamina strip, the Nexus Level badge (`NexusLevel` attribute), 9 hotbar slots with a sliding selector, vines. `ResourceBarsController` drives the bars, `InventoryController` the slots (`SlotLook` paints `ReplicatedStorage.SlotTemplate`; the grid and overflow slots use the same pixel template), `HeldItemNameController` the name label. The Studio place keeps the previous template as `SlotTemplate_Legacy` (delete when happy).
- **Enemy nameplate / levels / tags / death:** `EnemyNameplateController` clones `ReplicatedStorage.GUI.EnemyNameplate` (Stack: Title / BarGroup / Tags; builder `tools/studio/build_enemy_nameplate.luau`, behaviour numbers in `Config/NameplateConfig`). Levels: `EnemyConfig.levels` + `EnemyConfig.levelInfo` (computed from hp / attack dps / defense, or manual `level`; `scales = true` also scales stats), stamped as model attribute `EnemyLevel`. Tags: server `EnemyTags.add(model, id, {duration, stacks})` writes attribute `Tag_<id>` = "stacks|expiry"; icons from `tools/gen_tag_icons.py`. Deaths: `DeathService` (server) freezes every dying Humanoid and fires `EntityDeath`; `DeathFX` (client) glitches a light part copy then bursts triangles; all looks in `Config/DeathConfig`. Silkscreen font = `rbxassetid://12187371840`.
- **UI:** `CentralizedMenuController` (client) owns menu open/close/navigate and passes a `sharedRefs` table to page modules. Page modules in `Shared/Menu/Pages` expose `init(sharedRefs, frame)`, `open(arg)`, `close()` (animated), `reset()` (instant). `GridMenuModule` is config-driven grids with stack navigation; `TooltipModule` is a single shared tooltip keyed by source id (`showRaw(key)` / `hide(key)`) so page modules don't clobber each other. `LiquidGlassHandler` is the glass effect.
- **Stat formula:** `Final = (Base + Flat) x (1 + sum(Multipliers))`.

## UI conventions (from `SkillsPageModule`)
- Minecraft color-code palette: gold `#FFAA00`, green `#55FF55`, red `#FF5555`, yellow `#FFFF55`, aqua `#55FFFF`, light-purple `#FF55FF`, gray `#AAAAAA`/`#555555`, gold-title `#FFD700`. Per-skill colors live in `SKILL_CONFIG`.
- Rich text via `<font color='#...'>` in labels; Roman numerals toggle via `displayLevel`.
- Tweens: `Quint`/`Out`, ~0.3–0.5s. Fades use `CanvasGroup.GroupTransparency`.
- Sounds come from `workspace.UISounds` (`Click`, `Click3`).
- Wire event connections once in `init`, never in `open`.

## Known issues / cleanup
- Inventory = Tools: moving thousands of Tools freezes the server. `InventoryDataManager` parks the whole Backpack instance on death and coalesces updates (`scheduleUpdate`); never reparent Tools one by one in a loop with live Backpack listeners. Backpack is capped at `MAX_PAGES = 3`.
- A Clone keeps its CollectionService tags: strip them on effect clones. Shared modules are flat in Studio (`Modules:WaitForChild("DeathFX")`).
- Shared modules are flat in Studio: use `script.Parent` to reach siblings, never `script.Parent.Parent` (that is ReplicatedStorage). `Config` is a real Folder (`Modules.Config.HudTheme`). In the Studio MCP, `require` is cached across calls: builders `require(module:Clone())`. An `Infinite yield ... ReplicatedStorage:WaitForChild("Config")` warning is NOT harmless: it means some module looks for `Config` in the wrong place (one pre-existing source is still unidentified).
- Stray instances in the live place's Workspace: copies of `ProfileService` and `LiquidGlassHandler`, UI frames `Griffin`/`Boltrod`/`EmberFlare`/`MobRemains`, and several unnamed Models. Confirm with Nate before deleting.
- `ChangeSkill` RemoteEvent admin check is a hardcoded `ADMIN_IDS` list in `SkillsDataManager`.
- `SkillsPageModule` yields on `workspace:WaitForChild("UISounds")` at require time.

## Game memory vault (FracturedIslandsVault)
Game memory is the separate repo `FreezingShock/FracturedIslandsVault`, read through the `fia-vault` MCP (`mcpvault`, pinned in `.mcp.json`). It holds system cards, gotchas, decisions and the session log. It never holds personal notes.
- **Setup:** the server reads `$FIA_VAULT_PATH`, defaulting to `/home/user/fracturedislandsvault` (the cloud clone). On a Mac, clone the repo and set `FIA_VAULT_PATH` to that folder. The server doesn't start if the folder is missing.
- **Start of work:** read `Index.md` and `North Star.md` in the vault. Open only the cards the task needs (`read_note`, `search_notes`), not the code.
- **Cards describe code.** Each card lists `code_paths` and `verified_commit`. If you change a listed file, update its card in the same change. If the card and the code disagree, trust the code and fix the card.
- **End of work:** append a dated entry to `sessions/YYYY-MM.md` (oldest first, newest at the bottom), and add a gotcha or decision note when there is a durable lesson.
- The vault repo is separate from this one. Commit vault changes in the vault repo, not here.

## Vault memory workflow (Obsidian second brain, superseded)
Kept until `FracturedIslandsVault` is verified in a cloud session and on desktop; then delete this section. The `obsidian-second-brain` MCP (`mcp__plugin_obsidian-second-brain_vault__*`) is this project's long-term memory and log. Vault paths are relative to `FracturedVault`; use the real `✦`/`✷` characters, never copy-pasted ones.
- **Session start:** the SessionStart pack already shows the newest session entry; read `8 - Claude/agents/game-dev.md` (current focus) only if needed and the **Codebase & Systems Registry** section of `8 - Claude/projects/fractured-islands.md`. Design intent lives in `8 - Claude/projects/fractured-islands-master-hub.md`.
- **During work:** if the vault and the code disagree, trust the code for what exists and add the disagreement to the Registry's "Open conflicts" list. Do not rewrite design text or anything in `2 - Creations/` without Nate's explicit go-ahead.
- **Session end:** update only the Registry rows that changed (`obsidian_replace_text`), append a dated entry to the current month's log `8 - Claude/agents/game-dev-log-YYYY-MM.md` (`obsidian_update_note` with `append`, no heading, never read the note first; oldest first, newest at the bottom; a new month = a new note with the same header), and put durable lessons/blockers in `8 - Claude/memory/projects/fractured-islands.md`. Extend existing notes; do not create new vault documentation files.
- Main thread only; no subagents for vault writes.

## Working agreements
- Keybinds in use (check before binding a new key): Q = drop (`InventoryController`), F = dodge roll (`MovementConfig.dodge.key`).

- Commit and push to `main` automatically once a change is verified (standing instruction, 2026-10-04); otherwise don't. Commit messages follow the repo's style: `3.31.1 - Short description of changes`.
- Prefer editing existing modules over adding new ones; follow the `init/open/close/reset` page-module contract.
- Verify UI changes in a playtest (`start_stop_play`, `get_console_output`, `screen_capture`) before calling them done.
