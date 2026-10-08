---
name: gui-audit
description: Check that every GUI instance the scripts look up by name exists in the live Studio place. Use after renaming/moving GUI, after a Studio revert, or when a controller silently does nothing.
---

# gui-audit

1. `Grep` `src/` for `WaitForChild("...")` / `FindFirstChild("...")` chains rooted at `PlayerGui`, `StarterGui` or `ReplicatedStorage.GUI`; collect `ScreenGui -> path` pairs (skip dynamic names).
2. One `execute_luau` call (Edit datamodel, Play stopped) that walks the pairs and returns ONLY the missing paths as a JSON list.
3. For each missing path, `Grep tools/studio` for the builder that creates it; offer to re-run it (idempotent). Hand-made GUI with no builder: report it, do not recreate.
4. Report: `N checked, M missing`, then the missing list. Never dump the tree.

Known stray instances (copies of ProfileService/LiquidGlassHandler, Griffin/Boltrod/EmberFlare/MobRemains frames) are not findings; do not delete without his confirmation.
