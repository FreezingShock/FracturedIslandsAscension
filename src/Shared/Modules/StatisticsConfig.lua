--[[
	StatisticsConfig (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Shared configuration for the Statistics system.
	Both StatisticsDataManager (server) and StatisticsPageModule (client)
	require this module — single source of truth for all stat chains,
	skill names, and currency definitions.
--]]

local StatisticsConfig = {}

-- ===================== SKILL NAMES =====================
StatisticsConfig.SKILL_NAMES = { "Farming", "Foraging", "Mining", "Fishing", "Combat", "General" }

-- ===================== SKILL COLORS =====================
StatisticsConfig.SKILL_COLORS = {
	Farming = "#FFAA00",
	Foraging = "#00AA00",
	Fishing = "#00AAAA",
	Mining = "#5555FF",
	Combat = "#FF5555",
}

StatisticsConfig.STAT_CHAINS = {
	-- ═══════════════════ GENERAL (4 items) ═══════════════════
	General = {
		{
			key = "BronzeCoins",
			name = "Bronze Coins",
			color = "#FF5555",
			icon = "rbxassetid://132882222034992",
			-- No cost — earned passively (10/sec)
			passive = true,
			rewards = {},
		},
		{
			key = "SilverCoins",
			name = "Silver Coins",
			color = "#FFFFFF",
			icon = "rbxassetid://96673607401438",
			cost = { { type = "stat", skill = "General", id = "BronzeCoins", amount = 100 } },
			rewards = {
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 100 },
			},
		},
		{
			key = "GoldCoins",
			name = "Gold Coins",
			color = "#FFAA00",
			icon = "rbxassetid://78863592452697",
			cost = { { type = "stat", skill = "General", id = "SilverCoins", amount = 100 } },
			rewards = {
				{ target = "SilverCoins", type = "stat", skill = "General", pct = 75 },
			},
		},
		{
			key = "PlatinumCoins",
			name = "Platinum Coins",
			color = "#00AAAA",
			icon = "rbxassetid://119243667232909",
			cost = { { type = "stat", skill = "General", id = "GoldCoins", amount = 100 } },
			rewards = {
				{ target = "GoldCoins", type = "stat", skill = "General", pct = 50 },
			},
		},
		{
			key = "DiamondCoins",
			name = "Diamond Coins",
			color = "#55FFFF",
			icon = "rbxassetid://127302899633188",
			cost = { { type = "stat", skill = "General", id = "PlatinumCoins", amount = 100 } },
			rewards = {
				{ target = "PlatinumCoins", type = "stat", skill = "General", pct = 250 },
			},
		},
		{
			key = "EmeraldCoins",
			name = "Emerald Coins",
			color = "#55FF55",
			icon = "rbxassetid://72528992991486",
			cost = { { type = "stat", skill = "General", id = "DiamondCoins", amount = 100 } },
			rewards = {
				{ target = "DiamondCoins", type = "stat", skill = "General", pct = 300 },
			},
		},
		{
			key = "ObsidianCoins",
			name = "Obsidian Coins",
			color = "#5555FF",
			icon = "rbxassetid://127257480378149",
			cost = { { type = "stat", skill = "General", id = "EmeraldCoins", amount = 100 } },
			rewards = {
				{ target = "EmeraldCoins", type = "stat", skill = "General", pct = 400 },
			},
		},
		{
			key = "CrystallizedCoins",
			name = "Crystallized Coins",
			color = "#FF55FF",
			icon = "rbxassetid://71606147283349",
			cost = { { type = "stat", skill = "General", id = "ObsidianCoins", amount = 100 } },
			rewards = {
				{ target = "ObsidianCoins", type = "stat", skill = "General", pct = 500 },
			},
		},
		{
			key = "ExoticCoins",
			name = "Exotic Coins",
			color = "#00AA00",
			icon = "rbxassetid://113738577403055",
			cost = { { type = "stat", skill = "General", id = "CrystallizedCoins", amount = 100 } },
			rewards = {
				{ target = "CrystallizedCoins", type = "stat", skill = "General", pct = 750 },
			},
		},
		{
			key = "CelestialCoins",
			name = "Celestial Coins",
			color = "#AA00AA",
			icon = "rbxassetid://139915240462518",
			cost = { { type = "stat", skill = "General", id = "ExoticCoins", amount = 100 } },
			rewards = {
				{ target = "ExoticCoins", type = "stat", skill = "General", pct = 1000 },
			},
		},
		{
			key = "VoidCoins",
			name = '<stroke color="#FFFFFF" thickness="2">Void Coins</stroke>',
			color = "#000000",
			icon = "rbxassetid://81224196742351",
			cost = { { type = "stat", skill = "General", id = "CelestialCoins", amount = 100 } },
			rewards = {
				{ target = "CelestialCoins", type = "stat", skill = "General", pct = 10000 },
			},
		},
	},
	-- ═══════════════════ FARMING (13 items) ═══════════════════
	Farming = {
		{
			key = "Seeds",
			name = "Seeds",
			color = "#55FF55",
			icon = "rbxassetid://90624939195857", -- rbxassetid://XXXXX
			cost = { { type = "stat", skill = "General", id = "SilverCoins", amount = 10 } },
			rewards = {
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 50 },
			},
		},
		{
			key = "Wheat",
			name = "Wheat",
			color = "#FFFF55",
			icon = "rbxassetid://120936671978934", -- rbxassetid://XXXXX
			cost = { { type = "stat", skill = "Farming", id = "Seeds", amount = 25 } },
			rewards = {
				{ target = "Seeds", type = "stat", skill = "Farming", pct = 100 },
			},
		},
		{
			key = "Carrots",
			name = "Carrots",
			color = "#FFAA00",
			icon = "rbxassetid://135562041684147",
			cost = { { type = "stat", skill = "Farming", id = "Wheat", amount = 10 } },
			rewards = {
				{ target = "Wheat", type = "stat", skill = "Farming", pct = 150 },
			},
		},
		{
			key = "Cactus",
			name = "Cactus",
			color = "#00AA00",
			icon = "rbxassetid://115058956954552",
			cost = { { type = "stat", skill = "Farming", id = "Carrots", amount = 25 } },
			rewards = {
				{ target = "Carrots", type = "stat", skill = "Farming", pct = 200 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 75 },
			},
		},
		{
			key = "SugarCane",
			name = "Sugar Cane",
			color = "#55FF55",
			icon = "rbxassetid://82105442689684", -- rbxassetid://XXXXX
			cost = { { type = "stat", skill = "Farming", id = "Cactus", amount = 50 } },
			rewards = {
				{ target = "Cactus", type = "stat", skill = "Farming", pct = 250 },
				{ target = "Wheat", type = "stat", skill = "Farming", pct = 100 },
			},
		},
		{
			key = "Pumpkin",
			name = "Pumpkin",
			color = "#FFAA00",
			icon = "rbxassetid://136413382269163",
			cost = { { type = "stat", skill = "Farming", id = "SugarCane", amount = 25 } },
			rewards = {
				{ target = "SugarCane", type = "stat", skill = "Farming", pct = 200 },
				{ target = "Carrots", type = "stat", skill = "Farming", pct = 75 },
			},
		},
		{
			key = "Watermelon",
			name = "Watermelon",
			color = "#00AA00",
			icon = "rbxassetid://89681644854013",
			cost = { { type = "stat", skill = "Farming", id = "Pumpkin", amount = 50 } },
			rewards = {
				{ target = "Pumpkin", type = "stat", skill = "Farming", pct = 250 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 125 },
			},
		},
		{
			key = "CocoaBeans",
			name = "Cocoa Beans",
			color = "#AA0000",
			icon = "rbxassetid://100638066989466",
			cost = { { type = "stat", skill = "Farming", id = "Watermelon", amount = 75 } },
			rewards = {
				{ target = "Watermelon", type = "stat", skill = "Farming", pct = 300 },
				{ target = "FarmingFortune", type = "gameStat", flat = 0.05 },
			},
		},
		{
			key = "Feather",
			name = "Feather",
			color = "#FFFFFF",
			icon = "rbxassetid://126647373325788",
			cost = {
				{ type = "stat", skill = "Farming", id = "CocoaBeans", amount = 50 },
				{ type = "stat", skill = "General", id = "GoldCoins", amount = 25 },
			},
			rewards = {
				{ target = "CocoaBeans", type = "stat", skill = "Farming", pct = 350 },
				{ target = "Carrots", type = "stat", skill = "Farming", pct = 50 },
			},
		},
		{
			key = "Leather",
			name = "Leather",
			color = "#FF5555",
			icon = "rbxassetid://111351208466156",
			cost = {
				{ type = "stat", skill = "Farming", id = "Feather", amount = 30 },
				{ type = "stat", skill = "General", id = "GoldCoins", amount = 75 },
			},
			rewards = {
				{ target = "Feather", type = "stat", skill = "Farming", pct = 400 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 150 },
			},
		},
		{
			key = "RawChicken",
			name = "Raw Chicken",
			color = "#FF5555",
			icon = "rbxassetid://75870056724940",
			cost = {
				{ type = "stat", skill = "Farming", id = "Leather", amount = 500 },
				{ type = "stat", skill = "General", id = "GoldCoins", amount = 150 },
			},
			rewards = {
				{ target = "Leather", type = "stat", skill = "Farming", pct = 50 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 200 },
			},
		},
		{
			key = "RawMutton",
			name = "Raw Mutton",
			color = "#FF5555",
			icon = "rbxassetid://112464467883084",
			cost = {
				{ type = "stat", skill = "Farming", id = "RawChicken", amount = 60 },
				{ type = "stat", skill = "General", id = "GoldCoins", amount = 300 },
			},
			rewards = {
				{ target = "RawChicken", type = "stat", skill = "Farming", pct = 50 },
				{ target = "Wheat", type = "stat", skill = "Farming", pct = 75 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 200 },
			},
		},
		{
			key = "RawPorkchop",
			name = "Raw Porkchop",
			color = "#FF5555",
			icon = "rbxassetid://126368179784910",
			cost = {
				{ type = "stat", skill = "Farming", id = "RawMutton", amount = 75 },
				{ type = "stat", skill = "General", id = "GoldCoins", amount = 500 },
			},
			rewards = {
				{ target = "RawMutton", type = "stat", skill = "Farming", pct = 50 },
				{ target = "Carrots", type = "stat", skill = "Farming", pct = 75 },
				{ target = "SugarCane", type = "stat", skill = "Farming", pct = 25 },
			},
		},
		{
			key = "RawBeef",
			name = "Raw Beef",
			color = "#FF5555",
			icon = "rbxassetid://91462596092079",
			cost = {
				{ type = "stat", skill = "Farming", id = "RawPorkchop", amount = 100 },
				{ type = "stat", skill = "General", id = "GoldCoins", amount = 750 },
			},
			rewards = {
				{ target = "RawPorkchop", type = "stat", skill = "Farming", pct = 50 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 500 },
				{ target = "Pumpkin", type = "stat", skill = "Farming", pct = 25 },
				{ target = "Watermelon", type = "stat", skill = "Farming", pct = 25 },
				{ target = "FarmingFortune", type = "gameStat", flat = 0.5 },
				{ target = "CritChance", type = "gameStat", flat = 1 },
			},
		},
	},

	-- ═══════════════════ FORAGING (7 items) ═══════════════════
	Foraging = {
		{
			key = "WoodenSticks",
			name = "Wooden Sticks",
			color = "#C4A66A",
			icon = "",
			cost = { { type = "stat", skill = "General", id = "SilverCoins", amount = 25 } },
			rewards = {
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 50 },
			},
		},
		{
			key = "OakWood",
			name = "Oak Wood",
			color = "#8B6D3F",
			icon = "",
			cost = { { type = "stat", skill = "General", id = "SilverCoins", amount = 20 } },
			rewards = {
				{ target = "WoodenSticks", type = "stat", skill = "Foraging", pct = 25 },
			},
		},
		{
			key = "BirchWood",
			name = "Birch Wood",
			color = "#D9CDB8",
			icon = "",
			cost = { { type = "stat", skill = "Foraging", id = "OakWood", amount = 10 } },
			rewards = {
				{ target = "OakWood", type = "stat", skill = "Foraging", pct = 25 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 75 },
			},
		},
		{
			key = "SpruceWood",
			name = "Spruce Wood",
			color = "#5C3A1E",
			icon = "",
			cost = { { type = "stat", skill = "Foraging", id = "BirchWood", amount = 25 } },
			rewards = {
				{ target = "BirchWood", type = "stat", skill = "Foraging", pct = 50 },
				{ target = "WoodenSticks", type = "stat", skill = "Foraging", pct = 100 },
			},
		},
		{
			key = "DarkOakWood",
			name = "Dark Oak Wood",
			color = "#3B2612",
			icon = "",
			cost = { { type = "stat", skill = "Foraging", id = "SpruceWood", amount = 50 } },
			rewards = {
				{ target = "SpruceWood", type = "stat", skill = "Foraging", pct = 25 },
				{ target = "OakWood", type = "stat", skill = "Foraging", pct = 75 },
			},
		},
		{
			key = "JungleWood",
			name = "Jungle Wood",
			color = "#6B4226",
			icon = "",
			cost = { { type = "stat", skill = "Foraging", id = "DarkOakWood", amount = 25 } },
			rewards = {
				{ target = "DarkOakWood", type = "stat", skill = "Foraging", pct = 50 },
				{ target = "BronzeCoins", type = "stat", skill = "General", pct = 125 },
			},
		},
		{
			key = "AcaciaWood",
			name = "Acacia Wood",
			color = "#A0522D",
			icon = "",
			cost = { { type = "stat", skill = "Foraging", id = "JungleWood", amount = 50 } },
			rewards = {
				{ target = "JungleWood", type = "stat", skill = "Foraging", pct = 50 },
				{ target = "WoodenSticks", type = "stat", skill = "Foraging", pct = 125 },
			},
		},
	},

	-- ═══════════════════ STUBS (fill later) ═══════════════════
	Mining = {},
	Fishing = {},
	Combat = {},
}

-- ===================== PRECOMPUTED LOOKUPS =====================
StatisticsConfig.boostLookup = {}
StatisticsConfig.statConfigLookup = {}

for skill, chain in pairs(StatisticsConfig.STAT_CHAINS) do
	StatisticsConfig.boostLookup[skill] = {}
	StatisticsConfig.statConfigLookup[skill] = {}
	for _, item in ipairs(chain) do
		StatisticsConfig.statConfigLookup[skill][item.key] = item
		for _, reward in ipairs(item.rewards or {}) do
			if reward.type == "stat" and reward.skill == skill then
				local tbl = StatisticsConfig.boostLookup[skill]
				if not tbl[reward.target] then
					tbl[reward.target] = {}
				end
				table.insert(tbl[reward.target], {
					sourceKey = item.key,
					pct = reward.pct,
				})
			end
		end
	end
end

-- ===================== GRID LAYOUT CONSTANTS =====================
-- 8 columns × 6 rows = 48 cells
--
-- Row 0: [B][B][B][SK][B][B][B][B]       SelectedSkill at col 3
-- Row 1: [B][S1][S2][S3][S4][S5][S6][S7] 1 pad + 7 stat slots
-- Row 2: [B][S8]...                       (empty = BlankSlot)
-- Row 3: [B][S15]...
-- Row 4: [B][S22]...
-- Row 5: [B][B][B][Back][Close][B][B][B]  centered footer
--
-- Max 28 stat slots (4 rows × 7).  Unused positions = BlankSlot.

StatisticsConfig.COLUMNS = 9
StatisticsConfig.STAT_ROWS = 4
StatisticsConfig.STATS_PER_ROW = 7
StatisticsConfig.MAX_STATS = 28

StatisticsConfig.LAYOUT = {
	-- Row 0: header (9 columns: 0-8)
	headerBlanksBefore = 4, -- LO 0, 1, 2, 3
	selectedSkillOrder = 4, -- LO 4
	headerBlanksAfter = 3, -- LO 5, 6, 7, 8

	-- Rows 1-4: stat rows (each row = 9 columns)
	-- Row 1 starts at LO 9, Row 2 at 18, Row 3 at 27, Row 4 at 36
	statRowBaseOrder = 9,
	statRowPadCount = 2,

	-- Row 5: footer (9 columns)
	footerRowStart = 45,
	footerBlanksBefore = 4, -- LO 45, 46, 47
	backButtonOrder = 49, -- LO 48
	closeSlotOrder = 50, -- LO 49
	footerBlanksAfter = 4, -- LO 50, 51, 52, 53
}

print("StatisticsConfig: Loaded ✓")
return StatisticsConfig
