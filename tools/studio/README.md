# tools/studio: rebuild generated Studio content

GUI, templates and markers live in the Studio place (not in Rojo / git). Team Create autosaves the place, so there is
nothing to save by hand. Each `.luau` here is the recipe that created one generated piece, captured from the live
place, so a lost or reverted place can be rebuilt.

Run one with the Studio MCP: `execute_luau` on the **Edit** datamodel (stop Play first), pasting the file's contents.
Every script is idempotent and refuses to overwrite something that already exists (so it never clobbers hand
restyling) unless you set `local FORCE = true` at the top.

| File | Builds | Used by |
|---|---|---|
| `build_damage_number.luau` | `ReplicatedStorage.GUI.DamageNumber` (BillboardGui, Label, UIStroke, CritBadge) | `DamageNumberController` |
| `build_ability_menu.luau` | `ReplicatedStorage.GUI.AbilitySlot` template + `StarterGui.AbilityMenu.Slots` | `AbilityController` |
| `build_dummy.luau` | `ServerStorage.Dummy` (R6, straw coloured, 1000 hp) + `Workspace.DummySpawns` markers | `DummyService` |
| `build_fiahud.luau` | `StarterGui.FIAHUD` (Root: tray, Stamina strip, Health/Mana panels, badge, hotbar frames, selector, arrow, Name) + the pixel `ReplicatedStorage.SlotTemplate` (old one kept as `SlotTemplate_Legacy`); `REMOVE_STATSMENU` deletes the old HUD | `ResourceBarsController`, `InventoryController`, `HeldItemNameController` |
| `build_fiahud_vines.luau` | `FIAHUD.Root.Vines` (eight procedurally grown vines, differing per side) | none (decoration) |

Rule: whenever Claude generates anything (Studio GUI / template / marker / rig, a Blender model or animation, an
icon), the script that generated it is saved in `tools/` in the same turn (`tools/studio`, `tools/blender`, ...) and
listed here. Hand-made GUI by Nate is not recorded (he owns it).
