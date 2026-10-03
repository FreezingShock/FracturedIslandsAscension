# Tooltip System Changes - What's Actually Changed

## Three Files Modified

### 1. TooltipModule.lua
**Added: Tag badge rendering**

New functions added:
- `API.renderTags(tags)` — Renders tag badges to ItemTags frame
- `API.renderTitle(titleText, titleColor, titleIcon)` — Renders title to TitleFrame
- `API.clearTags()` — Clears all tag badges

What happens when you call `renderTags()`:
- Looks for `ItemTags` frame in TooltipFrame
- Destroys old tag badges
- Creates new Frame for each tag with:
  - Background color from `tag.color`
  - UIStroke outline from `tag.strokeColor`
  - TextLabel showing `tag.value`
  - UICorner for rounded corners
  - UIPadding for spacing

**Usage in InventoryController:**
```lua
TooltipModule.renderTags(tags)  -- Pass array of tag objects
TooltipModule.renderTitle(name, color)  -- Pass title text and color
```

---

### 2. ItemRegistry.lua
**Added: New optional fields for items**

All these fields are OPTIONAL. Add only what you need for each item.

#### Tags
```lua
coal_terrafruit = {
  -- existing fields...
  
  typeTag = "Resource",              -- Single Type badge
  skillTag = "Smithing",             -- Single Skill badge
  showRarityTag = false,             -- Control rarity badge visibility
  customTags = {                     -- Unlimited custom badges
    {
      label = "Status",
      value = "Cursed",
      color = "#FF5555",
      strokeColor = "#AA0000"
    },
  },
}
```

#### Stats
```lua
health_potion = {
  -- existing fields...
  
  showStatsSection = true,           -- Enable stats display
  stats = {
    {
      icon = {0, 0},                 -- {col, row} from spritesheet
      name = "Restore",
      value = "+50 HP",
      color = "#55FF55"
    },
  },
  clickHint = "Right-click to drink",
}
```

#### Equipment
```lua
iron_helmet = {
  -- existing fields...
  
  showEquipmentSection = true,       -- Enable equipment display
  equipSlot = "Helmet",              -- Which slot
}
```

#### Rewards
```lua
quest_item = {
  -- existing fields...
  
  showRewardsSection = true,         -- Enable rewards display
  rewards = {
    { name = "EXP", value = "1000" },
    { name = "Gold", value = "500" },
  },
}
```

**All Fields:**
- `typeTag` (string) — Item type badge
- `skillTag` (string) — Associated skill badge
- `showRarityTag` (bool) — Show rarity badge
- `customTags` (table array) — Custom badges
- `showStatsSection` (bool) — Show stats
- `stats` (table array) — Stat items
- `showEquipmentSection` (bool) — Show equipment
- `equipSlot` (string) — Equipment slot name
- `showRewardsSection` (bool) — Show rewards
- `rewards` (table array) — Reward items
- `clickHint` (string) — Action text

---

### 3. InventoryController.client.lua
**Added: Tag building and rendering**

New function added:
- `buildTooltipTags(toolInfo)` — Builds tag array from ItemRegistry data

How it works:
1. Looks up item in ItemRegistry via `toolInfo.name`
2. Reads `typeTag`, `skillTag`, `customTags` from item definition
3. Builds array of tag objects with label, value, color, strokeColor
4. Returns tag array

Updated function:
- `showItemTooltip(toolInfo)` — Now:
  1. Calls `buildTooltipTags()` to get tag array
  2. Calls `TooltipModule.renderTags(tags)` to render them
  3. Calls `TooltipModule.renderTitle()` to render title
  4. Still calls `TooltipModule.show()` for backward compatibility

**No other changes needed.** All slot hover handlers already call `showItemTooltip()`, so they automatically get the new tag system.

---

## How to Use It

### Step 1: Create UI Frames (Studio)
Your TooltipFrame needs:
- `TitleFrame` (contains TitleIcon + TitleLabel)
- `ItemTags` (empty, will hold tag badges)

If these don't exist, tags won't show (but no error).

### Step 2: Add Fields to Items
Open `ItemRegistry.lua` and add fields to any item:

```lua
coal_terrafruit = {
  id = "coal_terrafruit",
  displayName = "Coal Terrafruit",
  description = "A resource from farming.",
  rarity = 0,
  icon = "",
  maxStack = 999,
  toolName = "Coal Terrafruit",
  statBonuses = {},
  
  -- NEW: Just add these lines
  typeTag = "Resource",
  showRarityTag = false,
}
```

### Step 3: Hover an Item in-Game
When you hover, you should see:
- Title rendered to TitleFrame
- Tag badges rendered to ItemTags
- All existing tooltip behavior unchanged

---

## Examples

### Example 1: Resource Item
```lua
coal_terrafruit = {
  -- existing fields...
  description = "A resource from farming.",
  rarity = 0,
  
  typeTag = "Resource",
  showRarityTag = false,
}
```
Hover shows: Title | [Resource badge]

### Example 2: Consumable with Stats
```lua
health_potion = {
  -- existing fields...
  description = "Restores 50 HP.",
  rarity = 1,
  
  typeTag = "Consumable",
  skillTag = "Alchemy",
  showStatsSection = true,
  stats = {
    { icon = {0, 0}, name = "Restore", value = "+50 HP", color = "#55FF55" },
  },
  clickHint = "Right-click to use",
}
```
Hover shows: Title | [Rarity] [Consumable] [Alchemy] | Description | Stats | Click hint

### Example 3: Equipment
```lua
iron_helmet = {
  -- existing fields...
  rarity = 1,
  
  typeTag = "Armor",
  skillTag = "Smithing",
  showStatsSection = true,
  stats = {
    { icon = {1, 0}, name = "Defense", value = "+5", color = "#5555FF" },
  },
  clickHint = "Click to equip",
}
```
Hover shows: Title | [Uncommon] [Armor] [Smithing] | Stats | Click hint

### Example 4: Quest Item with Custom Tags
```lua
ancient_scroll = {
  -- existing fields...
  rarity = 3,
  
  showRarityTag = true,
  customTags = {
    { label = "Quest", value = "Active", color = "#FFFF55", strokeColor = "#AAAA00" },
    { label = "Bound", value = "Account", color = "#FF5555", strokeColor = "#AA0000" },
  },
  showRewardsSection = true,
  rewards = {
    { name = "EXP", value = "1000" },
    { name = "Gold", value = "500" },
  },
  clickHint = "Deliver to Elder",
}
```
Hover shows: Title | [Epic] [Quest: Active] [Bound: Account] | Description | Rewards | Click hint

---

## What Didn't Change

- ✓ Slot rendering (updateSlotVisual)
- ✓ Drag/drop system
- ✓ Hotbar/inventory layout
- ✓ Cursor following
- ✓ Tool instance system
- ✓ All existing tooltip behavior

## What You Can Control Per Item

### Boolean Toggles
- `showRarityTag` — Hide/show rarity badge
- `showStatsSection` — Hide/show stats
- `showEquipmentSection` — Hide/show equipment
- `showRewardsSection` — Hide/show rewards

### Text Fields
- `typeTag` — Shows as Type badge
- `skillTag` — Shows as Skill badge
- `clickHint` — Shows at bottom
- `equipSlot` — Which equipment slot

### Arrays
- `customTags` — Unlimited custom badges with colors
- `stats` — Multiple stats with icons
- `rewards` — Multiple rewards

---

## Testing Checklist

- [ ] Hover coal_terrafruit → See title + [Resource] badge
- [ ] Hover RarityTest1 → See title + [Uncommon] badge + [Crafting Material] badge + [Crafting] skill + stats
- [ ] Add `typeTag = "Weapon"` to any item → See badge on hover
- [ ] Add `customTags` to any item → See custom badge on hover
- [ ] Add `showStatsSection = true` + `stats = {...}` → See stats with icons
- [ ] Drag item → tooltip disappears
- [ ] Drop item → tooltip reappears on hover
- [ ] Verify all existing functionality still works

---

## That's It

You now have:
- Tag badge rendering in ItemTags frame
- Customizable tooltips per item via ItemRegistry fields
- Support for Type, Skill, custom tags, stats, equipment, rewards
- All fields optional (add only what you need)
- Full backward compatibility (old code still works)

Start by adding `typeTag` to 2-3 items and test hovering them.
