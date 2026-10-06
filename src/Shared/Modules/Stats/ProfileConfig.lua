--[[
	ProfileConfig (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Shared configuration for the Profile system.
	NOW INCLUDES: BASE_STATS (Health 100, Speed 16, etc.)
	PLACEHOLDER: EQUIPPED_ACCESSORIES (wired later), ATTRIBUTE_BONUSES (wired later)
--]]

local ProfileConfig = {}

-- ===================== BASE STATS =====================
-- These are the starting attribute values all players receive.
-- Format: { key = string, baseValue = number, description = string }
--
-- All players begin with these values. Flat boosts and multipliers are
-- applied on top of these base amounts. Server-side computation in
-- AttributeStatManager combines: (baseValue + flatBoosts) × (1 + multipliers)

ProfileConfig.BASE_STATS = {
	-- Combat-related
	Health = 100,
	HealthRegen = 0,
	Defense = 0,
	TrueDefense = 0,
	Strength = 0,
	Intelligence = 0,
	CritChance = 0,
	CritIncrease = 0,

	-- Gathering-related
	FarmingFortune = 0,
	FarmingSpeed = 0,
	FarmingCritChance = 0,
	FarmingCritIncrease = 0,

	ForagingFortune = 0,
	ForagingSpeed = 0,
	ForagingCritChance = 0,
	ForagingCritIncrease = 0,

	MiningFortune = 0,
	MiningSpeed = 0,
	MiningCritChance = 0,
	MiningCritIncrease = 0,
	Pristine = 0,

	FishingFortune = 0,
	FishingSpeed = 0,
	FishingCritChance = 0,
	FishingCritIncrease = 0,

	-- Misc / General
	Speed = 16, -- Roblox default is 16
	Vitality = 5, -- stamina regenerated per second (ResourceConfig: Stamina regen)
	JumpHeight = 0, -- Roblox default; overridden by Humanoid.JumpHeight (7.2 studs base)
	MagicFind = 0,
	PetLuck = 0,
	Wisdom = 0, -- global: adds to every skill's wisdom
	FarmingWisdom = 0, -- skill wisdom: +1 = +1% XP in that skill (SkillsDataManager.AddXP)
	ForagingWisdom = 0,
	FishingWisdom = 0,
	MiningWisdom = 0,
	CombatWisdom = 0,
	CarpentryWisdom = 0,
	BreakingPower = 0,

	-- General skills
	PressSpeed = 0,
	Luck = 0,
	Refine = 0,
}

-- ===================== SKILL COLORS =====================
-- Mirrors StatisticsConfig.SKILL_COLORS with General added.
ProfileConfig.SKILL_COLORS = {
	Farming = "#FFAA00",
	Foraging = "#00AA00",
	Fishing = "#00AAAA",
	Mining = "#5555FF",
	Misc = "#FFFF55",
	General = "#FFFFFF",
}

-- ===================== SKILL DISPLAY ORDER =====================
-- Controls iteration order for tooltip summaries and sub-grid lists.
ProfileConfig.SKILL_DISPLAY_ORDER = { "General", "Farming", "Foraging", "Mining", "Fishing", "Misc" }

-- ===================== ATTRIBUTE CATEGORIES =====================
-- Each skill maps to an ordered array of attribute definitions.
-- Fields:
--   key         : unique string identifier (data key / ProfileService key)
--   name        : display name shown in UI
--   color       : hex color for per-attribute theming
--   icon        : {col, row} spritesheet coordinates (see header comment)
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
			icon = { 0, 2 }, -- Diamond
			description = "Increases bonus crop yield per harvest.",
		},
		{
			key = "FarmingSpeed",
			name = "Farming Speed",
			color = "#FFFF55",
			icon = { 2, 0 }, -- SmallStar
			description = "Increases farming action speed.",
		},
		{
			key = "FarmingCritChance",
			name = "Farming Crit Chance",
			color = "#5555FF",
			icon = { 4, 1 }, -- Starburst
			description = "Chance to trigger a critical harvest.",
		},
		{
			key = "FarmingCritIncrease",
			name = "Farming Crit Increase",
			color = "#5555FF",
			icon = { 3, 0 },
			description = "Increases critical harvest amount.",
		},
	},

	-- ═════════════════ FORAGING ═════════════════
	Foraging = {
		{
			key = "ForagingFortune",
			name = "Foraging Fortune",
			color = "#FFAA00",
			icon = { 0, 2 }, -- Diamond
			description = "Increases bonus log yield per chop.",
		},
		{
			key = "ForagingSpeed",
			name = "Foraging Speed",
			color = "#FFFF55",
			icon = { 2, 0 }, -- SmallStar
			description = "Increases foraging action speed.",
		},
		{
			key = "ForagingCritChance",
			name = "Foraging Crit Chance",
			color = "#5555FF",
			icon = { 4, 1 }, -- Starburst
			description = "Chance to trigger a critical chop.",
		},
		{
			key = "ForagingCritIncrease",
			name = "Foraging Crit Increase",
			color = "#5555FF",
			icon = { 3, 0 },
			description = "Increases critical chop amount.",
		},
	},

	-- ═════════════════ MINING ═════════════════
	Mining = {
		{
			key = "MiningFortune",
			name = "Mining Fortune",
			color = "#FFAA00",
			icon = { 0, 2 }, -- Diamond
			description = "Increases bonus ore yield per break.",
		},
		{
			key = "MiningSpeed",
			name = "Mining Speed",
			color = "#FFFF55",
			icon = { 2, 0 }, -- SmallStar
			description = "Increases mining action speed.",
		},
		{
			key = "MiningCritChance",
			name = "Mining Crit Chance",
			color = "#5555FF",
			icon = { 4, 1 }, -- Starburst
			description = "Chance to trigger a critical break.",
		},
		{
			key = "MiningCritIncrease",
			name = "Mining Crit Increase",
			color = "#5555FF",
			icon = { 3, 0 },
			description = "Increases critical mining amount.",
		},
		{
			key = "Pristine",
			name = "Pristine",
			color = "#AA00AA",
			icon = { 1, 0 },
			description = "Increases mining base amount.",
		},
	},

	-- ═════════════════ FISHING ═════════════════
	Fishing = {
		{
			key = "FishingFortune",
			name = "Fishing Fortune",
			color = "#FFAA00",
			icon = { 0, 2 }, -- Diamond
			description = "Increases bonus catch yield per cast.",
		},
		{
			key = "FishingSpeed",
			name = "Fishing Speed",
			color = "#FFFF55",
			icon = { 2, 0 }, -- SmallStar
			description = "Reduces cast and reel time.",
		},
		{
			key = "FishingCritChance",
			name = "Fishing Crit Chance",
			color = "#5555FF",
			icon = { 4, 1 }, -- Starburst
			description = "Chance to trigger a critical catch.",
		},
		{
			key = "FishingCritIncrease",
			name = "Fishing Crit Increase",
			color = "#5555FF",
			icon = { 3, 0 },
			description = "Increases critical catch amount.",
		},
	},

	-- ═════════════════ COMBAT ═════════════════
	Misc = {
		{
			key = "Speed",
			name = "Speed",
			color = "#FFFFFF",
			icon = { 2, 0 }, -- SmallStar
			description = "Increases movement speed.",
		},
		{
			key = "Vitality",
			name = "Vitality",
			color = "#FFAA00",
			icon = { 4, 3 }, -- Starburst
			description = "Stamina regenerated per second.\n\n<font weight='900' color='#FFAA00'>Each point:</font> +1 stamina per second.",
		},
		{
			key = "JumpHeight",
			name = "Jump Height",
			color = "#55FF55",
			icon = { 0, 0 }, -- ArrowUp
			description = "Increases jump height.",
		},
		{
			key = "MagicFind",
			name = "Magic Find",
			color = "#55FFFF",
			icon = { 2, 1 }, -- Swirl
			description = "Boosts rare drop chance across all skills.",
		},
		{
			key = "PetLuck",
			name = "Pet Luck",
			color = "#FF55FF",
			icon = { 1, 2 }, -- Swirl
			description = "Boosts rare drop chance for pet items.",
		},
		{
			key = "Wisdom",
			name = "Wisdom",
			color = "#00AAAA",
			icon = { 2, 2 }, -- Swirl
			description = "Increases the XP you gain in every skill.",
		},
		{
			key = "FarmingWisdom",
			name = "Farming Wisdom",
			color = "#FFAA00",
			icon = { 2, 2 }, -- placeholder until the wisdom icons exist
			description = "Increases the Farming XP you gain.",
		},
		{
			key = "ForagingWisdom",
			name = "Foraging Wisdom",
			color = "#00AA00",
			icon = { 2, 2 }, -- placeholder until the wisdom icons exist
			description = "Increases the Foraging XP you gain.",
		},
		{
			key = "FishingWisdom",
			name = "Fishing Wisdom",
			color = "#00AAAA",
			icon = { 2, 2 }, -- placeholder until the wisdom icons exist
			description = "Increases the Fishing XP you gain.",
		},
		{
			key = "MiningWisdom",
			name = "Mining Wisdom",
			color = "#5555FF",
			icon = { 2, 2 }, -- placeholder until the wisdom icons exist
			description = "Increases the Mining XP you gain.",
		},
		{
			key = "CombatWisdom",
			name = "Combat Wisdom",
			color = "#FF5555",
			icon = { 2, 2 }, -- placeholder until the wisdom icons exist
			description = "Increases the Combat XP you gain.",
		},
		{
			key = "CarpentryWisdom",
			name = "Carpentry Wisdom",
			color = "#55FF55",
			icon = { 2, 2 }, -- placeholder until the wisdom icons exist
			description = "Increases the Carpentry XP you gain.",
		},
		{
			key = "BreakingPower",
			name = "Breaking Power",
			color = "#00AA00",
			icon = { 3, 2 }, -- Diamond
			description = "Increases the damage of breaking actions.",
		},
	},

	-- ═════════════════ GENERAL ═════════════════
	General = {
		{
			key = "Health",
			name = "Health",
			color = "#FF5555",
			icon = { 0, 1 }, -- Heart
			description = "Increases maximum health.",
		},
		{
			key = "HealthRegen",
			name = "Health Regen",
			color = "#FF5555",
			icon = { 4, 2 }, -- Heart
			description = "Increases maximum health regen.",
		},
		{
			key = "Defense",
			name = "Defense",
			color = "#55FF55",
			icon = { 1, 1 }, -- Shield
			description = "Increases maximum defense.",
		},
		{
			key = "TrueDefense",
			name = "True Defense",
			color = "#FFFFFF",
			icon = { 5, 0 }, -- Shield
			description = "Increases true defense.",
		},
		{
			key = "Strength",
			name = "Strength",
			color = "#FF5555",
			icon = { 4, 0 }, -- Heart
			description = "Increases maximum strength.",
		},
		{
			key = "Intelligence",
			name = "Intelligence",
			color = "#55FFFF",
			icon = { 5, 1 }, -- Starburst
			description = "Increases maximum intelligence.",
		},
		{
			key = "CritChance",
			name = "Crit Chance",
			color = "#5555FF",
			icon = { 4, 1 }, -- Starburst
			description = "Chance to land a critical hit.\n\n<font weight='900' color='#FFAA00'>Ability: Critical Hit</font>\nIncreases button press rewards by <font color='#5555FF'>Crit Increase %</font>.",
		},
		{
			key = "CritIncrease",
			name = "Crit Increase",
			color = "#5555FF",
			icon = { 3, 0 }, -- Starburst
			description = "Increases critical hit damage.\n\n<font weight='900' color='#FFAA00'>Ability: Critical Hit</font>\nIncreases button press rewards by <font color='#5555FF'>Crit Increase %</font>.",
		},
		{
			key = "PressSpeed",
			name = "Bonus Press Speed",
			color = "#FFFF55",
			icon = { 3, 1 }, -- Cross
			description = "<font weight='900' color='#FFAA00'>Passive Ability: Fast Finger</font>\nIncreases button presses per second.",
		},
		{
			key = "Luck",
			name = "Luck",
			color = "#55FF55",
			icon = { 0, 2 }, -- Cross
			description = "<font weight='900' color='#FFAA00'>Passive Ability: Clover</font>\nIncreases base luck for all buttons.",
		},
		{
			key = "Refine",
			name = "Refine",
			color = "#FF55FF",
			icon = { 0, 3 }, -- Cross
			description = "<font weight='900' color='#FFAA00'>Ability: Refinement</font>\nThe incoming stat's grade is increased by <font color='#55FF55'>+1</font>.",
		},
		{
			key = "Pristine",
			name = "Pristine",
			color = "#AA00AA",
			icon = { 1, 0 }, -- Cross
			description = "<font weight='900' color='#FFAA00'>Ability: Mint</font>\n<font color='#55FF55'>2x</font> any incoming stat.",
		},
	},
}

-- ===================== EQUIPMENT SLOT BUTTONS =====================
-- Buttons in ProfileMenu1 that show/accept equipped armor + accessories.
-- Names match Modules/Items/Slots ids; ArmorAccessoriesController drives them.
ProfileConfig.EQUIPMENT_BUTTONS = {
	"Helmet",
	"Chestplate",
	"Leggings",
	"Boots", -- armor column
	"Cloak",
	"Gloves",
	"Necklace",
	"Belt", -- accessory column
}

-- ===================== ATTRIBUTE BONUSES (PLACEHOLDER) =====================
-- Will store milestone rewards: { [skill] = { [level] = { [key] = { flatBoost = N, multiplierBoost = N } } } }
-- Wired in later when MilestoneManager is built.
ProfileConfig.ATTRIBUTE_BONUSES = {}

-- ===================== GRID LAYOUT CONSTANTS =====================
-- 9 columns × 6 rows = 54 cells
--
-- Row 0: [B][B][B][B][MyProfile][B][B][B][B]
-- Row 1: [B][Helmet][Cloak][B][B][B][B][B][B]
-- Row 2: [B][Chestplate][Gloves][B][AethericNexus][General][Farming][Foraging][B]
-- Row 3: [B][Leggings][Necklace][B][Milestones][Misc][Mining][Fishing][B]
-- Row 4: [B][Boots][Belt][B][B][B][B][B][B]
-- Row 5: [B][B][B][BackButton][CloseSlot][Bank][B][B][B]
--
-- Named slots: 20     Blanks: 34     Total: 54

ProfileConfig.COLUMNS = 9
ProfileConfig.ROWS = 6

-- Maps every named GuiButton child in ProfileMenu1 to its LayoutOrder.
-- These names must match the instances you create in Studio.
ProfileConfig.PROFILE_ITEM_ORDERS = {
	-- Row 0: header
	MyProfile = 4,

	-- Row 1: armor + accessory columns start
	Helmet = 10,
	Cloak = 11,

	-- Row 2: armor/accessories + skills top row
	Chestplate = 19,
	Gloves = 20,
	AethericNexus = 22,
	GeneralAttributes = 23,
	FarmingAttributes = 24,
	ForagingAttributes = 25,

	-- Row 3: armor/accessories + skills bottom row
	Leggings = 28,
	Necklace = 29,
	Milestones = 31,
	MiningAttributes = 33,
	MiscAttributes = 32,
	FishingAttributes = 34,

	-- Row 4: armor/accessories end
	Boots = 37,
	Belt = 38,

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

	-- Row 1  (1 before Helmet, 6 after Cloak)
	{ layoutOrder = 9, count = 1 },
	{ layoutOrder = 12, count = 6 },

	-- Row 2  (1 before Chestplate, 1 gap after Gloves, 1 trailing)
	{ layoutOrder = 18, count = 1 },
	{ layoutOrder = 21, count = 1 },
	{ layoutOrder = 26, count = 1 },

	-- Row 3  (1 before Leggings, 1 gap after Necklace, 1 trailing)
	{ layoutOrder = 27, count = 1 },
	{ layoutOrder = 30, count = 1 },
	{ layoutOrder = 35, count = 1 },

	-- Row 4  (1 before Boots, 6 after Belt)
	{ layoutOrder = 36, count = 1 },
	{ layoutOrder = 39, count = 6 },

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
	Misc = "MiscAttributes",
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
	muted = "#AAAAAA", -- was #555555 (too dark to read on the tooltip)
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

-- ===================== STAT CAPS =====================
-- Only stats with a hard cap are listed.  If a key is absent,
-- no cap line appears in the tooltip.  Add new entries as needed.
ProfileConfig.STAT_CAPS = {
	Speed = 500,
	JumpHeight = 100,
}

-- ===================== TOOLTIP BREAKDOWN CONFIG =====================
-- Max number of flat / multiplier sources shown before truncation.
ProfileConfig.BREAKDOWN_MAX_FLAT = 3
ProfileConfig.BREAKDOWN_MAX_MULT = 3

-- ===================== PROFILE MENU 2 LAYOUT =====================
-- 9 columns × 6 rows = 54 cells
--
-- Row 0: [B][B][B][B][Category][B][B][B][B]
-- Row 1: [B][S1][S2][S3][S4][S5][S6][S7][B]
-- Row 2: [B][S8][S9][S10][S11][S12][S13][S14][B]
-- Row 3: [B][S15][S16][S17][S18][S19][S20][S21][B]
-- Row 4: [B][S22][S23][S24][S25][S26][S27][S28][B]
-- Row 5: [B][B][B][BackButton][CloseSlot][B][B][B][B]
--
-- Named static slots: 3 (Category, BackButton, CloseSlot)
-- Dynamic stat slots:  up to 28 (7 per content row × 4 rows)
-- Static border blanks: 20
-- Dynamic fill blanks:  28 - #attrs (per skill)

ProfileConfig.PROFILE_MENU2_COLUMNS = 9
ProfileConfig.PROFILE_MENU2_ROWS = 6

-- Static named slots — must match Studio instance names.
ProfileConfig.PROFILE_MENU2_ITEM_ORDERS = {
	Category = 4,
	BackButton = 48,
	CloseSlot = 49,
}

-- Ordered LayoutOrders for content positions (rows 1-4, columns 1-7).
-- Stats fill these left-to-right, top-to-bottom.
-- Remaining positions get dynamic BlankSlots.
ProfileConfig.PROFILE_MENU2_CONTENT_SLOTS = {
	-- Row 1
	10,
	11,
	12,
	13,
	14,
	15,
	16,
	-- Row 2
	19,
	20,
	21,
	22,
	23,
	24,
	25,
	-- Row 3
	28,
	29,
	30,
	31,
	32,
	33,
	34,
	-- Row 4
	37,
	38,
	39,
	40,
	41,
	42,
	43,
}

-- Static border blanks only.
-- Content-area blanks are spawned dynamically per skill in ProfilePageModule.
ProfileConfig.PROFILE_MENU2_BLANK_GROUPS = {
	-- Row 0: 4 before Category, 4 after
	{ layoutOrder = 0, count = 4 },
	{ layoutOrder = 5, count = 4 },
	-- Row 1: left + right borders
	{ layoutOrder = 9, count = 1 },
	{ layoutOrder = 17, count = 1 },
	-- Row 2: left + right borders
	{ layoutOrder = 18, count = 1 },
	{ layoutOrder = 26, count = 1 },
	-- Row 3: left + right borders
	{ layoutOrder = 27, count = 1 },
	{ layoutOrder = 35, count = 1 },
	-- Row 4: left + right borders
	{ layoutOrder = 36, count = 1 },
	{ layoutOrder = 44, count = 1 },
	-- Row 5: 3 before BackButton, 4 after CloseSlot
	{ layoutOrder = 45, count = 3 },
	{ layoutOrder = 50, count = 4 },
}

-- ===================== PROFILE MENU 3 — ATTRIBUTE BREAKDOWN =====================
-- Third layer: opened by clicking an attribute in ProfileMenu2.
--
-- Row 0: [B][B][B][B][ATTRIBUTE][B][B][B][B]      (row 1, slot 5)
-- Row 1: [B][src1][src2][src3][src4][src5][src6][src7][B]   (row 2, slots 2-8)
-- Row 2-4: same, 7 sources per row, up to 28 sources
-- Row 5: [B][B][B][BackButton][CloseSlot][B][B][B][B]
--
-- Sources are the attribute's base value plus every equipped item (or other
-- boost) that adds to it. Same cell positions as ProfileMenu2's content area.
ProfileConfig.PROFILE_MENU3_ATTRIBUTE_ORDER = 4
ProfileConfig.PROFILE_MENU3_ITEM_ORDERS = {
	BackButton = 48,
	CloseSlot = 49,
}
ProfileConfig.PROFILE_MENU3_CONTENT_SLOTS = ProfileConfig.PROFILE_MENU2_CONTENT_SLOTS
-- Static blanks: row 0 (all but the attribute cell) + borders + footer.
ProfileConfig.PROFILE_MENU3_BLANK_GROUPS = ProfileConfig.PROFILE_MENU2_BLANK_GROUPS

-- Skill name → top bar title shown when ProfileMenu2 is active.
ProfileConfig.PROFILE_MENU2_TITLES = {
	General = "General Attributes",
	Farming = "Farming Attributes",
	Foraging = "Foraging Attributes",
	Mining = "Mining Attributes",
	Fishing = "Fishing Attributes",
	Misc = "Misc Attributes",
}

-- Skill name → Category button label color (reuses SKILL_COLORS).
-- Category button text is set dynamically in ProfilePageModule.

print("ProfileConfig: Loaded ✓")
return ProfileConfig
