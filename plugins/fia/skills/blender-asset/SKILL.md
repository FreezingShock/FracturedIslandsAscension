---
name: blender-asset
description: Make a Blender model or animation for Roblox via the Blender MCP and get it into the game. Use for 3D item models, trees, props, or R6 combat animations.
argument-hint: <asset>
---

# blender-asset $ARGUMENTS

1. `get_addon_status` then `get_scene_info`. Look shader nodes up by type, never name; read enum identifiers, never hardcode.
2. Build with `execute_blender_code`; check with `look` (small `max_size`). Match the pixel/voxel Minecraft style: swords use the 3D pixel-sword models (rarity template as fallback).
3. **Save the generator** in the same turn: `tools/blender/gen_<name>.py` (keep prior versions only if asked). Output sources to `assets/blender/<area>/`.
4. **Static meshes:** export FBX/glTF, import in Studio, size via `world_bounding_box`, ground it. Missing ids stay placeholders; say which are pending.
5. **R6 animation:** Roblox FBX import of R6 rigs is wrong (Motor6D C0/C1 rotated). Bake per frame `T = C0^-1 * Part0pose^-1 * Part1pose * C1` (Blender->Roblox axes `(x,y,z)->(x,z,-y)`) into a `KeyframeSequence` in an `AnimSaves` folder. Clips start and end at the standing pose.
6. Register the asset in the owning config (library -> type -> override), not in code.
