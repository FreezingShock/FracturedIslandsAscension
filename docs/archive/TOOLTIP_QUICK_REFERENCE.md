# Tooltip System - Quick Reference Card

## The 5-Minute Rundown

### Before Integration
Your tooltip shows:
```
Title (generic rarity color)
Description (basic)
Click text (optional)
```

### After Integration
Your tooltip shows:
```
Title (with optional icon)
├── Rarity badge (if rarity > 0)
├── Type badge (e.g., "Consumable")
├── Skill badge (e.g., "Smithing")
└── Custom badges (unlimited)
Description (expanded)
Stats (with icons, if enabled)
Equipment comparison (if enabled)
Rewards (if enabled)
Click hint
```

---

## 3 Files to Know

| File | What | Where |
|------|------|-------|
| `TooltipDataBuilder.lua` | Builds rich config from toolInfo | `Shared/Modules/` |
| `TooltipModule.lua` | Renders config to UI | `Shared/Modules/` (replaces old) |
| `ItemRegistry.lua` | Define item fields | `Shared/Modules/` (extend existing) |

---

## Adding Tooltip Data to an Item

### Minimal (Just Add Type)
```lua
coal_terrafruit = {
  id = "coal_terrafruit",
  displayName = "Coal Terrafruit",
  rarity = 0,
  toolName = "Coal Terrafruit",
  
  -- NEW: Just this line!
  typeTag = "Resource",
}
```

### With Stats
```lua
health_potion = {
  ...,
  
  -- NEW: Multiple fields
  typeTag = "Consumable",
  showStatsSection = true,
  stats = {
    { icon = {0, 0}, name = "Restore", value = "+50 HP", color = "#55FF55" },
  },
  clickHint = "Right-click to use",
}
```

### With Equipment
```lua
iron_helmet = {
  ...,
  
  typeTag = "Armor",
  skillTag = "Smithing",
  showStatsSection = true,
  stats = {
    { icon = {1, 0}, name = "Defense", value = "+5", color = "#5555FF" },
  },
  clickHint = "Click to equip",
}
```

---

## All Item Fields (Optional)

```lua
item_id = {
  -- Existing (don't change)
  id = "item_id",
  displayName = "Item Name",
  description = "",
  rarity = 0,
  icon = "",
  maxStack = 999,
  toolName = "ToolName",
  statBonuses = {},
  
  -- NEW: Tooltip fields (all optional)
  typeTag = "Resource",              -- e.g., "Consumable", "Armor", "Weapon"
  skillTag = "Mining",                -- e.g., "Smithing", "Combat"
  showRarityTag = true,               -- Show rarity badge (default: true if rarity > 0)
  
  -- Custom tags (unlimited)
  customTags = {
    { label = "Status", value = "Cursed", color = "#FF5555", strokeColor = "#AA0000" },
  },
  
  -- Stats section
  showStatsSection = true,            -- Enable stats display
  stats = {
    { icon = {0, 0}, name = "Stat", value = "+5", color = "#FF5555" },
  },
  
  -- Equipment section
  showEquipmentSection = true,        -- Enable equipment display
  equipSlot = "Helmet",               -- Which slot
  
  -- Rewards section
  showRewardsSection = true,          -- Enable rewards
  rewards = {
    { name = "EXP", value = "100" },
  },
  
  -- Click hint
  clickHint = "Right-click to use",   -- Action text
}
```

---

## Integration Steps

### 1. Copy Files (5 min)
```
[ ] TooltipDataBuilder.lua → Shared/Modules/
[ ] TooltipModule.REFACTORED.lua → Shared/Modules/ (rename to TooltipModule.lua)
```

### 2. Update UI in Studio (5 min)
```
[ ] Create TitleFrame (children: TitleIcon, TitleLabel)
[ ] Create ItemTags frame (empty, badges created dynamically)
[ ] Both should be in TooltipFrame
```

### 3. Update InventoryController (5 min)
```lua
-- Add at top:
local TooltipDataBuilder = require(Modules:WaitForChild("TooltipDataBuilder"))

-- Replace buildTooltipData():
local function buildTooltipConfig(toolInfo)
  if not toolInfo then return nil end
  return TooltipDataBuilder.buildTooltipConfig(toolInfo, {source = TOOLTIP_SOURCE})
end

-- Replace showItemTooltip():
local function showItemTooltip(toolInfo)
  if suppressTooltip or not toolInfo then return end
  local config = buildTooltipConfig(toolInfo)
  if config then
    TooltipModule.showConfig(config, TOOLTIP_SOURCE)
  end
end
```

### 4. Test (5 min)
```
[ ] Hover coal_terrafruit → see title, count
[ ] Add typeTag → see Type badge
[ ] Add stats → see stats with icons
[ ] Drag → tooltip hides
[ ] Drop → tooltip reappears on hover
```

### 5. Expand (Ongoing)
```
[ ] Add fields to more items
[ ] Adjust colors/spacing in Studio
[ ] Create custom tooltips for special items
```

---

## Icon Coordinates (Spritesheet)

If using spritesheet, use `{col, row}` format:

```lua
stats = {
  { icon = {0, 0}, name = "Stat1", ... },  -- top-left
  { icon = {1, 0}, name = "Stat2", ... },  -- top-middle
  { icon = {2, 0}, name = "Stat3", ... },  -- top-right
  { icon = {0, 1}, name = "Stat4", ... },  -- bottom-left
  { icon = {1, 1}, name = "Stat5", ... },  -- bottom-middle
}
```

Module uses spritesheet asset ID and cell size from STAT_SPRITESHEET config.

---

## Color Codes (Hex)

```
Rarity:
  #AAAAAA = Common (gray)
  #55FF55 = Uncommon (green)
  #5555FF = Rare (blue)
  #FF55FF = Epic (purple)
  #FFAA00 = Legendary (gold)
  #FF5555 = Mythic (red)

Typical Stat Colors:
  #FF5555 = Attack/Damage (red)
  #55FF55 = Healing/Restore (green)
  #5555FF = Defense/Armor (blue)
  #FFAA00 = Speed/Special (gold)
  #AAAAAA = Neutral/Info (gray)
```

---

## Common Tasks

### Hide Rarity for Common Items
```lua
your_item = {
  ...,
  rarity = 0,
  showRarityTag = false,  -- Don't show gray "Common" badge
}
```

### Add Multiple Badges
```lua
your_item = {
  ...,
  typeTag = "Weapon",
  skillTag = "Swordsmanship",
  customTags = {
    { label = "Enchant", value = "Flaming", color = "#FF6600", strokeColor = "#AA3300" },
    { label = "Tier", value = "Rare", color = "#5555FF", strokeColor = "#0000AA" },
  },
}
```

### Show Only Stats (No Badges)
```lua
your_item = {
  ...,
  showRarityTag = false,
  typeTag = nil,
  skillTag = nil,
  customTags = {},
  showStatsSection = true,
  stats = { ... },
}
```

### Equipment with Comparison
```lua
your_item = {
  ...,
  typeTag = "Armor",
  showEquipmentSection = true,
  equipSlot = "Helmet",
  showStatsSection = true,
  stats = {
    { icon = {1, 0}, name = "Defense", value = "+5", color = "#5555FF" },
  },
  clickHint = "Click to equip",
}
```

---

## Debugging

### Tooltip Not Showing?
1. Check TooltipFrame exists in PlayerGui
2. Check TitleFrame and ItemTags created
3. Check item has toolInfo object (not nil)
4. Check InventoryController is calling showItemTooltip()

### Badges Not Showing?
1. Check ItemTags frame exists in TooltipFrame
2. Check item has typeTag, skillTag, or customTags defined
3. Check renderTags() is called in TooltipModule

### Stats Not Showing?
1. Check showStatsSection = true in item definition
2. Check stats array is not empty
3. Check icon format is {col, row} or valid asset ID
4. Check stat names and values are strings

---

## Quick Checklist

- [ ] Copied TooltipDataBuilder.lua
- [ ] Replaced TooltipModule.lua
- [ ] Created TitleFrame in Studio
- [ ] Created ItemTags in Studio
- [ ] Updated InventoryController (3 functions)
- [ ] Tested with 1 item
- [ ] Added fields to 2-3 more items
- [ ] Verified badges appear
- [ ] Verified stats display
- [ ] All hover/drag/drop working

**You're done!** 🎉

---

## Need More Help?

- **Full examples** → See `ItemRegistry.EXTENDED.lua`
- **Step-by-step** → See `TOOLTIP_OVERHAUL_GUIDE.md`
- **Architecture** → See `project_tooltip_system_overview.md`
- **API docs** → Read comments in `TooltipDataBuilder.lua` and `TooltipModule.REFACTORED.lua`
