---
name: content
description: Add an item, weapon, ability, enemy, or similar content to Fractured Islands as data. Use for "add a sword/mob/ability/material" requests; follows the layered config recipes instead of writing code.
argument-hint: <content to add>
---

# content $ARGUMENTS

Content is data: library -> type/item -> per-weapon override; the server reads the config, the client sends intent only.

1. Find the owning config with `Grep` (`CombatConfig`, `AbilityConfig`, `ResourceConfig`, item/enemy/loot configs, `ItemIconData`). Read the **file header recipe** ("new ability: add an entry here") and one neighbouring entry. Match it.
2. Add the entry. Reuse pipelines: icons `tools/fetch_icons.py` -> upload -> `tools/gen_icon_data.py`; stat icons from the ProfileConfig spritesheet; swords get a 3D model entry or a rarity template.
3. Wire it: mob drops, collections and tooltips read the same data. No hardcoded ids in behavior code.
4. Missing animation/sound/icon id = silent placeholder slot; list the pending ids for him.
5. Keybinds: avoid Q (drop), R (camera), T (cursor lock), E (menu); pick a free key or ask.
6. New saved fields go in `PROFILE_TEMPLATE` (`Reconcile` backfills); never bump the store name.
7. Static checks, then `/fia-verify`, then `/fia-ship`. Small additions skip spec and review.
