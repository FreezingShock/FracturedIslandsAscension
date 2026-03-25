--[[
	ProfileConfig (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Shared configuration for the Profile system.
	Defines attribute categories per skill, armor slot definitions,
	tooltip color constants, and grid layout for ProfileMenu1.

	EXPANDING:
	  • New attribute  → append to ATTRIBUTE_CATEGORIES[skill]
	  • New skill      → add key + array to ATTRIBUTE_CATEGORIES,
	                      add color to SKILL_COLORS,
	                      add to SKILL_DISPLAY_ORDER,
	                      add grid button to CentralizedMenuController
	  • New armor slot → append to ARMOR_SLOTS + update grid layout
--]]

local ProfileConfig = {}

-- ===================== SKILL COLORS =====================
-- Mirrors StatisticsConfig.SKILL_COLORS with General added.
ProfileConfig.SKILL_COLORS = {
	Farming = "#FFAA00",
	Foraging = "#00AA00",
	Fishing = "#00AAAA",
	Mining = "#5555FF",
	Combat = "#FF5555",
	General = "#FFFF55",
}

-- ===================== SKILL DISPLAY ORDER =====================
-- Controls iteration order for tooltip summaries and sub-grid lists.
ProfileConfig.SKILL_DISPLAY_ORDER = { "Farming", "Foraging", "Mining", "Fishing", "Combat", "General" }

-- ===================== ATTRIBUTE CATEGORIES =====================
-- Each skill maps to an ordered array of attribute definitions.
-- Fields:
--   key         : unique string identifier (data key / ProfileService key)
--   name        : display name shown in UI
--   color       : hex color for per-attribute theming
--   icon        : rbxassetid string (empty = placeholder)
--   description : one-line tooltip description
--
-- To add a new attribute: append an entry to the skill's array.
-- To add a new skill category: add a new key here + wire in CMC.

ProfileConfig.ATTRIBUTE_CATEGORIES = {

	-- ═════════════════ FARMING ═════════════════
	Farming = {
		{
			key = "FarmingFortune",
			name = "Farming Fortune",
			color = "#FFAA00",
			icon = "",
			description = "Increases bonus crop yield per harvest.",
		},
		{
			key = "FarmingSpeed",
			name = "Farming Speed",
			color = "#55FF55",
			icon = "",
			description = "Increases farming action speed.",
		},
		{
			key = "FarmingCritChance",
			name = "Farming Crit Chance",
			color = "#5555FF",
			icon = "",
			description = "Chance to trigger a critical harvest.",
		},
	},

	-- ═════════════════ FORAGING ═════════════════
	Foraging = {
		{
			key = "ForagingFortune",
			name = "Foraging Fortune",
			color = "#00AA00",
			icon = "",
			description = "Increases bonus log yield per chop.",
		},
		{
			key = "ForagingSpeed",
			name = "Foraging Speed",
			color = "#55FF55",
			icon = "",
			description = "Increases foraging action speed.",
		},
		{
			key = "ForagingCritChance",
			name = "Foraging Crit Chance",
			color = "#5555FF",
			icon = "",
			description = "Chance to trigger a critical chop.",
		},
	},

	-- ═════════════════ MINING ═════════════════
	Mining = {
		{
			key = "MiningFortune",
			name = "Mining Fortune",
			color = "#5555FF",
			icon = "",
			description = "Increases bonus ore yield per break.",
		},
		{
			key = "MiningSpeed",
			name = "Mining Speed",
			color = "#55FF55",
			icon = "",
			description = "Increases mining action speed.",
		},
		{
			key = "MiningCritChance",
			name = "Mining Crit Chance",
			color = "#55FFFF",
			icon = "",
			description = "Chance to trigger a critical break.",
		},
	},

	-- ═════════════════ FISHING ═════════════════
	Fishing = {
		{
			key = "FishingFortune",
			name = "Fishing Fortune",
			color = "#00AAAA",
			icon = "",
			description = "Increases bonus catch yield per cast.",
		},
		{
			key = "FishingSpeed",
			name = "Fishing Speed",
			color = "#55FF55",
			icon = "",
			description = "Reduces cast and reel time.",
		},
		{
			key = "FishingCritChance",
			name = "Fishing Crit Chance",
			color = "#5555FF",
			icon = "",
			description = "Chance to trigger a critical catch.",
		},
	},

	-- ═════════════════ COMBAT ═════════════════
	Combat = {
		{
			key = "CombatFortune",
			name = "Combat Fortune",
			color = "#FF5555",
			icon = "",
			description = "Increases bonus loot from combat encounters.",
		},
		{
			key = "CombatSpeed",
			name = "Combat Speed",
			color = "#55FF55",
			icon = "",
			description = "Increases attack speed in combat.",
		},
		{
			key = "CombatCritChance",
			name = "Combat Crit Chance",
			color = "#5555FF",
			icon = "",
			description = "Chance to land a critical hit.",
		},
	},

	-- ═════════════════ GENERAL ═════════════════
	General = {
		{
			key = "PressSpeed",
			name = "Press Speed",
			color = "#FFAA00",
			icon = "",
			description = "Increases button presses per second.",
		},
		{
			key = "Walkspeed",
			name = "Walkspeed",
			color = "#FFFFFF",
			icon = "",
			description = "Increases movement speed.",
		},
		{
			key = "JumpHeight",
			name = "Jump Height",
			color = "#55FF55",
			icon = "",
			description = "Increases jump height.",
		},
		{
			key = "MagicFind",
			name = "Magic Find",
			color = "#55FFFF",
			icon = "",
			description = "Boosts rare drop chance across all skills.",
		},
		{
			key = "Health",
			name = "Health",
			color = "#FF5555",
			icon = "",
			description = "Increases maximum health.",
		},
		{
			key = "Stamina",
			name = "Stamina",
			color = "#FFFF55",
			icon = "",
			description = "Increases maximum stamina for sustained actions.",
		},
	},
}

-- ===================== ARMOR SLOTS =====================
-- Display-only for now. Interactive equip/swap coming later.
-- layoutOrder matches PROFILE_ITEM_ORDERS for the grid position.
ProfileConfig.ARMOR_SLOTS = {
	{ key = "Helmet", name = "Helmet", layoutOrder = 10, icon = "", emptyLabel = "Helmet" },
	{ key = "Chestplate", name = "Chestplate", layoutOrder = 19, icon = "", emptyLabel = "Chestplate" },
	{ key = "Leggings", name = "Leggings", layoutOrder = 28, icon = "", emptyLabel = "Leggings" },
	{ key = "Boots", name = "Boots", layoutOrder = 37, icon = "", emptyLabel = "Boots" },
}

-- ===================== ACCESSORY SLOTS (planned) =====================
-- Not in the current grid layout. Will be added once armor interactivity
-- is complete.  Placeholder for future expansion.
-- ProfileConfig.ACCESSORY_SLOTS = {}

-- ===================== GRID LAYOUT CONSTANTS =====================
-- 9 columns × 6 rows = 54 cells
--
-- Row 0: [B][B][B][B][MyProfile][B][B][B][B]
-- Row 1: [B][Helmet][B][B][B][B][B][B][B]
-- Row 2: [B][Chestplate][B][B][AethericNexus][Farming][Foraging][Mining][B]
-- Row 3: [B][Leggings][B][B][Milestones][Combat][Fishing][General][B]
-- Row 4: [B][Boots][B][B][B][B][B][B][B]
-- Row 5: [B][B][B][BackButton][CloseSlot][Bank][B][B][B]
--
-- Named slots: 16     Blanks: 38     Total: 54

ProfileConfig.COLUMNS = 9
ProfileConfig.ROWS = 6

-- Maps every named GuiButton child in ProfileMenu1 to its LayoutOrder.
-- These names must match the instances you create in Studio.
ProfileConfig.PROFILE_ITEM_ORDERS = {
	-- Row 0: header
	MyProfile = 4,

	-- Row 1: armor start
	Helmet = 10,

	-- Row 2: armor + skills top row
	Chestplate = 19,
	AethericNexus = 22,
	FarmingAttributes = 23,
	ForagingAttributes = 24,
	MiningAttributes = 25,

	-- Row 3: armor + skills bottom row
	Leggings = 28,
	Milestones = 31,
	CombatAttributes = 32,
	FishingAttributes = 33,
	GeneralAttributes = 34,

	-- Row 4: armor end
	Boots = 37,

	-- Row 5: footer
	BackButton = 48,
	CloseSlot = 49,
	Bank = 50,
}

-- Blank slot groups.  Each group clones `count` BlankSlots at the
-- given layoutOrder.  UIGridLayout sorts by LayoutOrder; ties
-- resolve by insertion order.
ProfileConfig.PROFILE_BLANK_GROUPS = {
	-- Row 0  (4 before MyProfile, 4 after)
	{ layoutOrder = 0, count = 4 },
	{ layoutOrder = 5, count = 4 },

	-- Row 1  (1 before Helmet, 7 after)
	{ layoutOrder = 9, count = 1 },
	{ layoutOrder = 11, count = 7 },

	-- Row 2  (1 before Chestplate, 2 gap, 1 trailing)
	{ layoutOrder = 18, count = 1 },
	{ layoutOrder = 20, count = 2 },
	{ layoutOrder = 26, count = 1 },

	-- Row 3  (1 before Leggings, 2 gap, 1 trailing)
	{ layoutOrder = 27, count = 1 },
	{ layoutOrder = 29, count = 2 },
	{ layoutOrder = 35, count = 1 },

	-- Row 4  (1 before Boots, 7 after)
	{ layoutOrder = 36, count = 1 },
	{ layoutOrder = 38, count = 7 },

	-- Row 5  (3 before BackButton, 3 after Bank)
	{ layoutOrder = 45, count = 3 },
	{ layoutOrder = 51, count = 3 },
}

-- ===================== SKILL → GRID BUTTON MAP =====================
-- Maps skill name to the GuiButton name in ProfileMenu1.
-- Used by CentralizedMenuController to wire dynamic tooltips.
ProfileConfig.SKILL_BUTTON_MAP = {
	Farming = "FarmingAttributes",
	Foraging = "ForagingAttributes",
	Mining = "MiningAttributes",
	Fishing = "FishingAttributes",
	Combat = "CombatAttributes",
	General = "GeneralAttributes",
}

-- ===================== TOOLTIP COLORS =====================
-- Shared color constants for tooltip rich-text building.
ProfileConfig.TOOLTIP_COLORS = {
	label = "#AAAAAA",
	value = "#FFFFFF",
	positive = "#55FF55",
	negative = "#FF5555",
	accent = "#FFFF55",
	muted = "#555555",
	comingSoon = "#555555",
}

-- ===================== PRECOMPUTED LOOKUPS =====================
-- attrLookup[skill][key] → attribute config entry
-- Avoids repeated iteration when building tooltips or sub-grids.
ProfileConfig.attrLookup = {}

for skill, attrs in pairs(ProfileConfig.ATTRIBUTE_CATEGORIES) do
	ProfileConfig.attrLookup[skill] = {}
	for _, attr in ipairs(attrs) do
		ProfileConfig.attrLookup[skill][attr.key] = attr
	end
end

-- Flat list of all attribute keys across all skills (for data template).
ProfileConfig.ALL_ATTRIBUTE_KEYS = {}
for _, skill in ipairs(ProfileConfig.SKILL_DISPLAY_ORDER) do
	local attrs = ProfileConfig.ATTRIBUTE_CATEGORIES[skill]
	if attrs then
		for _, attr in ipairs(attrs) do
			table.insert(ProfileConfig.ALL_ATTRIBUTE_KEYS, {
				skill = skill,
				key = attr.key,
			})
		end
	end
end

print("ProfileConfig: Loaded ✓")
return ProfileConfig
