---
name: studio-build
description: Create or change Studio GUI, templates, markers or rigs through the Studio MCP and save the builder script. Use for any new UI, billboard, template, spawn marker or dummy; never build GUI with Instance.new in game scripts.
argument-hint: <what to build>
---

# studio-build $ARGUMENTS

GUI lives in the Studio place, not Rojo (Team Create autosaves). Scripts look instances up by name.

1. **Inspect first:** `search_game_tree` / `inspect_instance` for an existing frame or template. Reuse or clone before inventing; a rename breaks every `WaitForChild` that names it (`/fia:gui-audit`).
2. **Style:** pixel font `rbxassetid://12187371840`, Minecraft colors (gold `#FFAA00`, green `#55FF55`, red `#FF5555`, yellow `#FFFF55`, aqua `#55FFFF`, gray `#AAAAAA`), theme numbers from `Config/HudTheme`. Check `ReplicatedStorage.GUI` for the nearest template.
3. **Build:** `execute_luau` on the **Edit** datamodel. It fails during Play: `start_stop_play(false)` first. Builders `require(module:Clone())` (require is cached across calls).
4. **Save the builder in the same turn:** `tools/studio/build_<name>.luau`, idempotent, refuses to overwrite unless `local FORCE = true`, capturing real property values (inspect hand-tweaked instances; his hand-made GUI is his, don't record it). Add a row to `tools/studio/README.md`.
5. Scripts clone the template and fill text/colors only. Rebind on `PlayerGui.ChildAdded` (ResetOnSpawn).
6. Verify with a text assertion (`inspect_instance`); screenshot only if layout is the question.
