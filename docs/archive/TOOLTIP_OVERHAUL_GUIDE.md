# Tooltip System Overhaul - Implementation Guide

## Overview
This guide walks you through integrating the new **tag-based, data-driven tooltip system** into your existing codebase. The system is fully backward compatible while supporting rich visual tooltips with badges, stats, and customizable sections.

---

## What's New

### Before (Current System)
```lua
-- Tooltip output: bare-bones data
{
  title = "Coal Terrafruit",
  desc = "Common — 5x",
  click = ""
}
```

### After (New System)
```lua
-- Tooltip output: rich config object
{
  title = { text = "Coal Terrafruit", color = "#AAAAAA", icon = nil },
  tags = {
    { label = "Rarity", value = "Common", color = "#AAAAAA", strokeColor = "#555555" },
    { label = "Type", value = "Consumable", color = "#FFAA00", strokeColor = "#AA6600" }
  },
  description = { text = "...", color = "#AAAAAA", visible = true },
  sections = {
    stats = { visible = true, items = {...} },
    equipment = { visible = false },
    rewards = { visible = false },
    click = { visible = true, text = "..." }
  },
  metadata = { count = 5, itemId = "coal_terrafruit", ... }
}
```

---

## Step 1: Add New Modules to ReplicatedStorage/Modules

### 1.1 Copy TooltipDataBuilder.lua
**File:** `src/Shared/Modules/TooltipDataBuilder.lua` (already created)

**Purpose:** Builds rich tooltip config objects from toolInfo + ItemRegistry

**No changes needed** — this file is ready to use.

### 1.2 Copy ItemRegistry.EXTENDED.lua (Reference)
**File:** `src/Shared/Modules/ItemRegistry.EXTENDED.lua` (already created)

**Purpose:** Shows all available tooltip fields for items

**Usage:** Open this file to see examples of items with rich tooltip data. Copy the patterns into your main ItemRegistry.Items when you want items to have advanced tooltips.

### 1.3 Copy TooltipModule.REFACTORED.lua
**File:** `src/Shared/Modules/TooltipModule.REFACTORED.lua` (already created)

**Purpose:** Renders tooltipConfig objects to your new UI hierarchy

**Important:** 
- This **replaces** the current TooltipModule.lua
- It has both new API (`showConfig()`) and old API (`show()`) for compatibility
- Looks for `TitleFrame` and `ItemTags` frames in your TooltipFrame hierarchy

---

## Step 2: Update Your UI Hierarchy in Studio

The new system expects this hierarchy in your TooltipMenu:

```
TooltipMenu (ScreenGui)
└── TooltipFrame
    ├── TitleFrame (NEW - for title + icon)
    │   ├── TitleIcon (ImageLabel)
    │   └── TitleLabel (TextLabel)
    ├── ItemTags (NEW - for tag badges)
    │   (Tag badges created dynamically)
    ├── DescriptionLabel (TextLabel)
    ├── StatsLabel (TextLabel)
    ├── ClickLabel (TextLabel)
    ├── Divider1, Divider2, Divider3
    ├── ProgressBar (optional)
    └── ...
```

### What to Do in Studio:

1. **Create TitleFrame** (if it doesn't exist):
   - Parent: TooltipFrame
   - Size: UDim2.new(1, 0, 0, 30)
   - LayoutOrder: 1
   - Contains:
     - TitleIcon (ImageLabel) - for item icon
     - TitleLabel (TextLabel) - for title text

2. **Create ItemTags** (if it doesn't exist):
   - Parent: TooltipFrame
   - Size: UDim2.new(1, 0, 0, auto)
   - LayoutOrder: 2
   - Add UIListLayout with horizontal orientation
   - This frame will hold tag badges (created dynamically)

3. **Update DescriptionLabel**:
   - LayoutOrder: 3
   - This label now shows item description

4. **Keep existing layout** for Stats, Click, Dividers, etc.

---

## Step 3: Extend ItemRegistry with Tooltip Data

### Basic Items (No Changes Needed)
Items like `coal_terrafruit` work as-is. They'll show:
- Rarity badge (if rarity > 0)
- Name
- Count
- Description (if filled)

### Adding Tags to an Item

Open `src/Shared/Modules/ItemRegistry.lua` and add tooltip fields:

```lua
coal_terrafruit = {
  id = "coal_terrafruit",
  displayName = "Coal Terrafruit",
  description = "A resource gathered from farming.",
  rarity = 0,
  icon = "rbxassetid://123456",
  maxStack = 999,
  toolName = "Coal Terrafruit",
  statBonuses = {},
  
  -- NEW: Tooltip fields
  typeTag = "Resource",
  showRarityTag = false,  -- Don't show rarity for common items
  clickHint = "Use in crafting",
}
```

### Adding Stats to an Item

```lua
health_potion = {
  id = "health_potion",
  displayName = "Potion of Health",
  description = "Restores health when consumed.",
  rarity = 1,
  
  -- NEW: Stats section
  showStatsSection = true,
  stats = {
    { icon = {0, 0}, name = "Restore", value = "+50 HP", color = "#55FF55" },
    { icon = {1, 0}, name = "Speed", value = "Instant", color = "#FFAA00" },
  },
  
  clickHint = "Right-click to drink",
}
```

### Adding Equipment to an Item

```lua
iron_helmet = {
  id = "iron_helmet",
  displayName = "Iron Helmet",
  rarity = 1,
  
  -- NEW: Equipment section
  showEquipmentSection = true,
  equipSlot = "Helmet",
  showStatsSection = true,
  stats = {
    { icon = {1, 0}, name = "Defense", value = "+5", color = "#5555FF" },
  },
  
  typeTag = "Armor",
  skillTag = "Smithing",
  clickHint = "Click to equip",
}
```

**See ItemRegistry.EXTENDED.lua for more examples.**

---

## Step 4: Update InventoryController

### Option A: Full Integration (Recommended)

1. Open `src/Client/InventoryController.client.lua`

2. At the top with other requires, add:
```lua
local TooltipDataBuilder = require(Modules:WaitForChild("TooltipDataBuilder"))
```

3. Replace the entire `buildTooltipData()` function (around line 286) with:
```lua
local function buildTooltipConfig(toolInfo)
  if not toolInfo then
    return nil
  end
  return TooltipDataBuilder.buildTooltipConfig(toolInfo, { source = TOOLTIP_SOURCE })
end
```

4. Replace `showItemTooltip()` function (around line 301) with:
```lua
local function showItemTooltip(toolInfo)
  if suppressTooltip or not toolInfo then
    return
  end
  local config = buildTooltipConfig(toolInfo)
  if config then
    TooltipModule.showConfig(config, TOOLTIP_SOURCE)
  end
end
```

5. **No other changes needed** — all the slot hover handlers already call `showItemTooltip()`.

### Option B: Backward Compatible (If Not Ready to Update TooltipModule)

Keep using the old `TooltipModule.show()` API:

```lua
local function buildTooltipData(toolInfo)
  if not toolInfo then
    return nil
  end
  return TooltipDataBuilder.buildLegacyTooltipData(toolInfo)
end

local function showItemTooltip(toolInfo)
  if suppressTooltip or not toolInfo then
    return
  end
  local data = buildTooltipData(toolInfo)
  if data then
    TooltipModule.show(data, TOOLTIP_SOURCE)
  end
end
```

This still works with your current TooltipModule until you're ready to upgrade.

---

## Step 5: Replace TooltipModule.lua

1. **Backup your current file**:
   ```
   src/Shared/Modules/TooltipModule.lua → TooltipModule.ORIGINAL.lua
   ```

2. **Replace with refactored version**:
   - Copy `TooltipModule.REFACTORED.lua` → `TooltipModule.lua`

3. **The new module maintains backward compatibility**:
   - Old code using `TooltipModule.show()` still works
   - New code using `TooltipModule.showConfig()` uses full features
   - You can migrate gradually

---

## Step 6: Testing

### Test 1: Basic Item (No Extra Data)
1. Hover over Coal Terrafruit
2. Should see:
   - ✓ Title in TitleFrame
   - ✓ Rarity badge (if rarity > 0)
   - ✓ Description
   - ✓ Count in description

### Test 2: Item with Tags
After adding `typeTag` to an item:
1. Hover over the item
2. Should see:
   - ✓ Title
   - ✓ Rarity badge
   - ✓ Type badge ("Resource", "Consumable", etc.)
   - ✓ Each badge has colored stroke

### Test 3: Item with Stats
After adding `showStatsSection = true` and `stats` array:
1. Hover over the item
2. Should see:
   - ✓ All tags
   - ✓ Stats block with icons
   - ✓ Stat names and values

### Test 4: Equipment Item
After adding equipment fields:
1. Hover over equipment
2. Should see:
   - ✓ Tags including Type ("Armor") and Skill ("Smithing")
   - ✓ Stats with defense/attack values
   - ✓ Click hint

### Test 5: Tooltip Visibility
- Hover: tooltip appears
- Leave: tooltip disappears
- Drag: tooltip hidden
- Drop: tooltip reappears on hover

---

## Common Questions

### Q: Can I use this with my current UI?
**A:** Yes! If you haven't created TitleFrame and ItemTags yet, the system falls back to the old labels. But you'll get the most out of the new system by adding those frames.

### Q: How do I add custom tags?
**A:** In ItemRegistry, use the `customTags` field:
```lua
customTags = {
  { label = "Status", value = "Cursed", color = "#FF5555", strokeColor = "#AA0000" },
}
```

### Q: Can I hide the rarity badge for common items?
**A:** Yes:
```lua
showRarityTag = false,
```

### Q: How do I use spritesheet icons for stats?
**A:** Use `{col, row}` table format:
```lua
stats = {
  { icon = {0, 0}, name = "Defense", value = "+5", color = "#5555FF" },  -- top-left
  { icon = {1, 0}, name = "Attack", value = "+3", color = "#FF5555" },    -- top-middle
}
```

### Q: What if I want to keep the old system?
**A:** Keep your old TooltipModule.lua and don't require TooltipDataBuilder. The old system will continue to work unchanged.

---

## File Checklist

- [ ] `TooltipDataBuilder.lua` copied to `Shared/Modules/`
- [ ] `ItemRegistry.EXTENDED.lua` copied to `Shared/Modules/` (reference)
- [ ] `TooltipModule.REFACTORED.lua` copied to `Shared/Modules/` and renamed to `TooltipModule.lua`
- [ ] TitleFrame and ItemTags created in Studio (TooltipMenu)
- [ ] `ItemRegistry.Items` updated with tooltip fields (start with 1-2 items)
- [ ] `InventoryController.lua` updated with new buildTooltipConfig()
- [ ] Test hovering items in-game

---

## Next Steps

1. **Start small**: Add tooltip fields to 2-3 items first
2. **Test**: Hover and verify badges/stats appear
3. **Iterate**: Add fields to more items as you refine the look
4. **Polish**: Adjust colors, spacing, and icon positions

---

## Reference: Data Structure

### tooltipConfig Object
```lua
{
  -- Title section
  title = {
    text = "Item Name",
    color = "#FFFFFF",
    icon = "rbxassetid://..." or nil,
  },
  
  -- Tag badges (Rarity, Type, Skill, Custom)
  tags = {
    {
      label = "Rarity",
      value = "Common",
      color = "#AAAAAA",
      strokeColor = "#555555",
    },
    -- ... more tags
  },
  
  -- Description
  description = {
    text = "Item description...",
    color = "#AAAAAA",
    visible = true,
  },
  
  -- Dynamic sections
  sections = {
    stats = {
      visible = true,
      items = {
        { icon = {0, 0}, name = "Stat", value = "+5", color = "#FF5555" },
      }
    },
    equipment = { visible = false, ... },
    rewards = { visible = false, ... },
    click = { visible = true, text = "Click to use" },
  },
  
  -- Metadata (internal use)
  metadata = {
    count = 5,
    itemId = "item_id",
    name = "Item Name",
    rarity = 0,
    tooltipSource = "inventory",
  }
}
```

---

**Status**: Ready for integration. Start with Step 1-3, test, then proceed to full integration.
