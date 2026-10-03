--[[
	StatisticsConfig (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Shared configuration for the Statistics system.
	Both StatisticsDataManager (server) and StatisticsPageModule (client)
	require this module — single source of truth for all stat chains,
	skill names, and currency definitions.
--]]

local StatisticsConfig = {}

local ButtonConfig = require(script.Parent:WaitForChild("ButtonConfig")) :: any

-- Short constructors so a chain reads as data, not boilerplate.
local function cost(skill, id, amount)
	return { type = "stat", skill = skill, id = id, amount = amount }
end
local function boost(skill, target, pct)
	return { target = target, type = "stat", skill = skill, pct = pct }
end
local function attr(target, flat)
	return { target = target, type = "gameStat", flat = flat }
end

-- ===================== SKILL NAMES =====================
StatisticsConfig.SKILL_NAMES = { "Farming", "Foraging", "Mining", "Fishing", "Combat", "General" }

-- ===================== SKILL COLORS =====================
StatisticsConfig.SKILL_COLORS = {
	Farming = "#FFAA00",
	Foraging = "#00AA00",
	Fishing = "#00AAAA",
	Mining = "#5555FF",
	Combat = "#FF5555",
	General = "#FFFF55",
}

-- ===================== SKILL DESCRIPTIONS =====================
-- Shown on the skill's statistics button and as the default stat description.
StatisticsConfig.SKILL_BLURBS = {
	General = "Coins and currencies shared by every skill.",
	Farming = "Crops and animal goods from your farm.",
	Foraging = "Wood and plants from the forest.",
	Mining = "Ores and gems from deep underground.",
	Fishing = "Catches and treasures from the water.",
	Combat = "Drops from the creatures you defeat.",
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
			passiveGain = 10, -- per second, before multipliers
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

	-- ═══════════════════ FORAGING (12 items) ═══════════════════
	Foraging = {
		{
			key = "Stick", name = "Stick", color = "#C4A66A", icon = "rbxassetid://116855299256097",
			cost = { cost("General", "SilverCoins", 25) },
			rewards = { boost("General", "BronzeCoins", 50) },
		},
		{
			key = "Apple", name = "Apple", color = "#FF5555", icon = "rbxassetid://107765252153594",
			cost = { cost("General", "SilverCoins", 20) },
			rewards = { boost("Foraging", "Stick", 25) },
		},
		{
			key = "SweetBerries", name = "Sweet Berries", color = "#AA0000", icon = "rbxassetid://117700443235244",
			cost = { cost("Foraging", "Apple", 10) },
			rewards = { boost("Foraging", "Apple", 25), boost("General", "BronzeCoins", 75) },
		},
		{
			key = "GlowBerries", name = "Glow Berries", color = "#FFAA00", icon = "rbxassetid://88277848372569",
			cost = { cost("Foraging", "SweetBerries", 25) },
			rewards = { boost("Foraging", "SweetBerries", 50), boost("Foraging", "Stick", 100) },
		},
		{
			key = "Honeycomb", name = "Honeycomb", color = "#E8A33D", icon = "rbxassetid://88731096576162",
			cost = { cost("Foraging", "GlowBerries", 50) },
			rewards = { boost("Foraging", "GlowBerries", 25), boost("Foraging", "Apple", 75) },
		},
		{
			key = "HoneyBottle", name = "Honey Bottle", color = "#FFAA00", icon = "rbxassetid://89066758968476",
			cost = { cost("Foraging", "Honeycomb", 25) },
			rewards = { boost("Foraging", "Honeycomb", 50), boost("General", "BronzeCoins", 125) },
		},
		{
			key = "ChorusFruit", name = "Chorus Fruit", color = "#AA00AA", icon = "rbxassetid://100473905035310",
			cost = { cost("Foraging", "HoneyBottle", 50) },
			rewards = { boost("Foraging", "HoneyBottle", 50), boost("Foraging", "Stick", 125) },
		},
		{
			key = "MangrovePropagule", name = "Mangrove Propagule", color = "#7FD35C", icon = "rbxassetid://138393603550988",
			cost = { cost("Foraging", "ChorusFruit", 50) },
			rewards = { boost("Foraging", "ChorusFruit", 50), boost("General", "BronzeCoins", 150) },
		},
		{
			key = "MushroomStew", name = "Mushroom Stew", color = "#B5503C", icon = "rbxassetid://119301607730629",
			cost = { cost("Foraging", "MangrovePropagule", 75) },
			rewards = { boost("Foraging", "MangrovePropagule", 50), boost("Foraging", "HoneyBottle", 75) },
		},
		{
			key = "Bamboo", name = "Bamboo", color = "#55FF55", icon = "rbxassetid://107983384161693",
			cost = { cost("Foraging", "MushroomStew", 100) },
			rewards = { boost("Foraging", "MushroomStew", 75), attr("ForagingFortune", 0.05) },
		},
		{
			key = "GoldenApple", name = "Golden Apple", color = "#FFFF55", icon = "rbxassetid://75319868187414",
			cost = { cost("Foraging", "Bamboo", 100), cost("General", "GoldCoins", 50) },
			rewards = { boost("Foraging", "Bamboo", 75), boost("General", "BronzeCoins", 200) },
		},
		{
			key = "RabbitsFoot", name = "Rabbit's Foot", color = "#D9CDB8", icon = "rbxassetid://89726174367035",
			cost = { cost("Foraging", "GoldenApple", 100), cost("General", "GoldCoins", 100) },
			rewards = { boost("Foraging", "GoldenApple", 100), attr("ForagingFortune", 0.1), attr("ForagingSpeed", 1) },
		},
	},

	-- ═══════════════════ MINING (14 items) ═══════════════════
	-- No world buttons yet: obtain = "locked" until a ButtonConfig entry exists.
	Mining = {
		{
			key = "Flint", name = "Flint", color = "#AAAAAA", icon = "rbxassetid://122657331068842",
			cost = { cost("General", "SilverCoins", 25) },
			rewards = { boost("General", "BronzeCoins", 50) },
		},
		{
			key = "Coal", name = "Coal", color = "#808080", icon = "rbxassetid://94057449678241",
			cost = { cost("Mining", "Flint", 25) },
			rewards = { boost("Mining", "Flint", 100), boost("General", "BronzeCoins", 50) },
		},
		{
			key = "CopperIngot", name = "Copper Ingot", color = "#E07B39", icon = "rbxassetid://99441690334971",
			cost = { cost("Mining", "Coal", 25) },
			rewards = { boost("Mining", "Coal", 100) },
		},
		{
			key = "IronIngot", name = "Iron Ingot", color = "#FFFFFF", icon = "rbxassetid://137262771819579",
			cost = { cost("Mining", "CopperIngot", 25) },
			rewards = { boost("Mining", "CopperIngot", 150), boost("Mining", "Flint", 50) },
		},
		{
			key = "LapisLazuli", name = "Lapis Lazuli", color = "#5555FF", icon = "rbxassetid://81484950038697",
			cost = { cost("Mining", "IronIngot", 25) },
			rewards = { boost("Mining", "IronIngot", 150), attr("MiningFortune", 0.05) },
		},
		{
			key = "Redstone", name = "Redstone Dust", color = "#FF5555", icon = "rbxassetid://85093438958798",
			cost = { cost("Mining", "LapisLazuli", 50) },
			rewards = { boost("Mining", "LapisLazuli", 200), boost("General", "BronzeCoins", 75) },
		},
		{
			key = "GoldIngot", name = "Gold Ingot", color = "#FFAA00", icon = "rbxassetid://109009223465102",
			cost = { cost("Mining", "Redstone", 50), cost("General", "GoldCoins", 25) },
			rewards = { boost("Mining", "Redstone", 200), boost("Mining", "CopperIngot", 75) },
		},
		{
			key = "Quartz", name = "Nether Quartz", color = "#E8E0D0", icon = "rbxassetid://128178767162120",
			cost = { cost("Mining", "GoldIngot", 50), cost("General", "GoldCoins", 50) },
			rewards = { boost("Mining", "GoldIngot", 200), attr("MiningSpeed", 1) },
		},
		{
			key = "Amethyst", name = "Amethyst Shard", color = "#AA00AA", icon = "rbxassetid://82939227563063",
			cost = { cost("Mining", "Quartz", 75), cost("General", "GoldCoins", 100) },
			rewards = { boost("Mining", "Quartz", 250), boost("General", "BronzeCoins", 150) },
		},
		{
			key = "Diamond", name = "Diamond", color = "#55FFFF", icon = "rbxassetid://108812581339614",
			cost = { cost("Mining", "Amethyst", 75), cost("General", "PlatinumCoins", 25) },
			rewards = { boost("Mining", "Amethyst", 250), attr("MiningFortune", 0.1) },
		},
		{
			key = "Emerald", name = "Emerald", color = "#55FF55", icon = "rbxassetid://91741430115447",
			cost = { cost("Mining", "Diamond", 100), cost("General", "PlatinumCoins", 50) },
			rewards = { boost("Mining", "Diamond", 300), attr("MiningCritChance", 1) },
		},
		{
			key = "EchoShard", name = "Echo Shard", color = "#00AAAA", icon = "rbxassetid://124228840162421",
			cost = { cost("Mining", "Emerald", 100), cost("General", "PlatinumCoins", 100) },
			rewards = { boost("Mining", "Emerald", 300), attr("BreakingPower", 1) },
		},
		{
			key = "NetheriteScrap", name = "Netherite Scrap", color = "#A0522D", icon = "rbxassetid://97410266286268",
			cost = { cost("Mining", "EchoShard", 150), cost("General", "DiamondCoins", 25) },
			rewards = { boost("Mining", "EchoShard", 400), attr("MiningCritIncrease", 5) },
		},
		{
			key = "NetheriteIngot", name = "Netherite Ingot", color = "#C07A5A", icon = "rbxassetid://128800841410590",
			cost = { cost("Mining", "NetheriteScrap", 200), cost("General", "DiamondCoins", 75) },
			rewards = { boost("Mining", "NetheriteScrap", 500), attr("Pristine", 1) },
		},
	},

	-- ═══════════════════ FISHING (12 items) ═══════════════════
	Fishing = {
		{
			key = "Kelp", name = "Kelp", color = "#00AA00", icon = "rbxassetid://87185271442635",
			cost = { cost("General", "SilverCoins", 25) },
			rewards = { boost("General", "BronzeCoins", 50) },
		},
		{
			key = "RawCod", name = "Raw Cod", color = "#C4A66A", icon = "rbxassetid://75863940961102",
			cost = { cost("Fishing", "Kelp", 25) },
			rewards = { boost("Fishing", "Kelp", 100) },
		},
		{
			key = "RawSalmon", name = "Raw Salmon", color = "#FF7F7F", icon = "rbxassetid://134805199818583",
			cost = { cost("Fishing", "RawCod", 25) },
			rewards = { boost("Fishing", "RawCod", 100), boost("General", "BronzeCoins", 50) },
		},
		{
			key = "TropicalFish", name = "Tropical Fish", color = "#FFAA00", icon = "rbxassetid://104154383748835",
			cost = { cost("Fishing", "RawSalmon", 25) },
			rewards = { boost("Fishing", "RawSalmon", 150), attr("FishingFortune", 0.05) },
		},
		{
			key = "Pufferfish", name = "Pufferfish", color = "#FFFF55", icon = "rbxassetid://85630274775537",
			cost = { cost("Fishing", "TropicalFish", 50) },
			rewards = { boost("Fishing", "TropicalFish", 200) },
		},
		{
			key = "InkSac", name = "Ink Sac", color = "#5555FF", icon = "rbxassetid://140439050401114",
			cost = { cost("Fishing", "Pufferfish", 50), cost("General", "GoldCoins", 25) },
			rewards = { boost("Fishing", "Pufferfish", 200), boost("General", "BronzeCoins", 100) },
		},
		{
			key = "GlowInkSac", name = "Glow Ink Sac", color = "#55FFFF", icon = "rbxassetid://105118812851818",
			cost = { cost("Fishing", "InkSac", 50), cost("General", "GoldCoins", 50) },
			rewards = { boost("Fishing", "InkSac", 250), attr("FishingSpeed", 1) },
		},
		{
			key = "NautilusShell", name = "Nautilus Shell", color = "#FF55FF", icon = "rbxassetid://109219666934424",
			cost = { cost("Fishing", "GlowInkSac", 75), cost("General", "GoldCoins", 100) },
			rewards = { boost("Fishing", "GlowInkSac", 250), attr("FishingCritChance", 1) },
		},
		{
			key = "PrismarineShard", name = "Prismarine Shard", color = "#00AAAA", icon = "rbxassetid://137621299801980",
			cost = { cost("Fishing", "NautilusShell", 75), cost("General", "PlatinumCoins", 25) },
			rewards = { boost("Fishing", "NautilusShell", 300), boost("General", "BronzeCoins", 150) },
		},
		{
			key = "PrismarineCrystals", name = "Prismarine Crystals", color = "#55FFFF", icon = "rbxassetid://114717413675863",
			cost = { cost("Fishing", "PrismarineShard", 100), cost("General", "PlatinumCoins", 50) },
			rewards = { boost("Fishing", "PrismarineShard", 300), attr("FishingFortune", 0.1) },
		},
		{
			key = "SeaPickle", name = "Sea Pickle", color = "#7FD35C", icon = "rbxassetid://117035798463841",
			cost = { cost("Fishing", "PrismarineCrystals", 100), cost("General", "PlatinumCoins", 100) },
			rewards = { boost("Fishing", "PrismarineCrystals", 350), attr("FishingCritIncrease", 5) },
		},
		{
			key = "HeartOfTheSea", name = "Heart of the Sea", color = "#00AAAA", icon = "rbxassetid://109800696233866",
			cost = { cost("Fishing", "SeaPickle", 150), cost("General", "DiamondCoins", 25) },
			rewards = { boost("Fishing", "SeaPickle", 500), attr("MagicFind", 1) },
		},
	},

	-- ═══════════════════ COMBAT (12 items) ═══════════════════
	Combat = {
		{
			key = "RottenFlesh", name = "Rotten Flesh", color = "#8B6D3F", icon = "rbxassetid://128713086883307",
			cost = { cost("General", "SilverCoins", 50) },
			rewards = { boost("General", "BronzeCoins", 50) },
		},
		{
			key = "Bone", name = "Bone", color = "#FFFFFF", icon = "rbxassetid://73075268569850",
			cost = { cost("Combat", "RottenFlesh", 25) },
			rewards = { boost("Combat", "RottenFlesh", 100) },
		},
		{
			key = "String", name = "String", color = "#D9CDB8", icon = "rbxassetid://111677557501256",
			cost = { cost("Combat", "Bone", 25) },
			rewards = { boost("Combat", "Bone", 100), boost("General", "BronzeCoins", 50) },
		},
		{
			key = "SpiderEye", name = "Spider Eye", color = "#AA0000", icon = "rbxassetid://86306875259974",
			cost = { cost("Combat", "String", 25) },
			rewards = { boost("Combat", "String", 150), attr("Strength", 1) },
		},
		{
			key = "Gunpowder", name = "Gunpowder", color = "#AAAAAA", icon = "rbxassetid://84176229488966",
			cost = { cost("Combat", "SpiderEye", 50) },
			rewards = { boost("Combat", "SpiderEye", 200) },
		},
		{
			key = "Slimeball", name = "Slimeball", color = "#55FF55", icon = "rbxassetid://114697486919728",
			cost = { cost("Combat", "Gunpowder", 50), cost("General", "GoldCoins", 25) },
			rewards = { boost("Combat", "Gunpowder", 200), attr("Health", 5) },
		},
		{
			key = "EnderPearl", name = "Ender Pearl", color = "#00AA00", icon = "rbxassetid://101080065276737",
			cost = { cost("Combat", "Slimeball", 50), cost("General", "GoldCoins", 50) },
			rewards = { boost("Combat", "Slimeball", 250), attr("Speed", 1) },
		},
		{
			key = "BlazeRod", name = "Blaze Rod", color = "#FFAA00", icon = "rbxassetid://75033845248573",
			cost = { cost("Combat", "EnderPearl", 75), cost("General", "GoldCoins", 100) },
			rewards = { boost("Combat", "EnderPearl", 250), attr("Strength", 2) },
		},
		{
			key = "GhastTear", name = "Ghast Tear", color = "#E8E0D0", icon = "rbxassetid://110451764759721",
			cost = { cost("Combat", "BlazeRod", 75), cost("General", "PlatinumCoins", 25) },
			rewards = { boost("Combat", "BlazeRod", 300), attr("Defense", 2) },
		},
		{
			key = "MagmaCream", name = "Magma Cream", color = "#FF5555", icon = "rbxassetid://105013476058272",
			cost = { cost("Combat", "GhastTear", 100), cost("General", "PlatinumCoins", 50) },
			rewards = { boost("Combat", "GhastTear", 300), attr("CritChance", 1) },
		},
		{
			key = "ShulkerShell", name = "Shulker Shell", color = "#AA55FF", icon = "rbxassetid://120606850489063",
			cost = { cost("Combat", "MagmaCream", 100), cost("General", "PlatinumCoins", 100) },
			rewards = { boost("Combat", "MagmaCream", 350), attr("CritIncrease", 5) },
		},
		{
			key = "NetherStar", name = "Nether Star", color = "#FFFF55", icon = "rbxassetid://123291085202857",
			cost = { cost("Combat", "ShulkerShell", 150), cost("General", "DiamondCoins", 25) },
			rewards = { boost("Combat", "ShulkerShell", 500), attr("Strength", 5) },
		},
	},
}

-- ===================== PRECOMPUTED LOOKUPS =====================
-- statConfigLookup[skill][key] = stat definition
-- boostLookup[targetSkill][targetKey] = { { sourceSkill, sourceKey, pct }, ... }
--   Every "stat" reward lands here, including rewards that boost a stat in
--   ANOTHER skill (Seeds boosting General Bronze Coins), so the multiplier
--   matches what the tooltip promises.
-- buttonTiers[skill][key] = number of world-button tiers that grant the stat
StatisticsConfig.statConfigLookup = {}
StatisticsConfig.boostLookup = {}
StatisticsConfig.buttonTiers = {}

for _, skill in ipairs(StatisticsConfig.SKILL_NAMES) do
	StatisticsConfig.statConfigLookup[skill] = {}
	StatisticsConfig.boostLookup[skill] = {}
	StatisticsConfig.buttonTiers[skill] = {}
end

for skill, chain in pairs(StatisticsConfig.STAT_CHAINS) do
	for index, item in ipairs(chain) do
		item.skill = skill
		item.index = index
		StatisticsConfig.statConfigLookup[skill][item.key] = item
		for _, reward in ipairs(item.rewards or {}) do
			if reward.type == "stat" then
				local targetTable = StatisticsConfig.boostLookup[reward.skill or skill]
				if targetTable then
					targetTable[reward.target] = targetTable[reward.target] or {}
					table.insert(targetTable[reward.target], {
						sourceSkill = skill,
						sourceKey = item.key,
						pct = reward.pct,
					})
				end
			end
		end
	end
end

for _, def in pairs(ButtonConfig.BUTTONS) do
	local tiers = StatisticsConfig.buttonTiers[def.skill]
	if tiers then
		tiers[def.statKey] = (tiers[def.statKey] or 0) + #def.tiers
	end
end

--- How a stat is earned: "passive" | "button" | "locked" (no way to obtain it yet).
for skill, chain in pairs(StatisticsConfig.STAT_CHAINS) do
	for _, item in ipairs(chain) do
		if item.passive then
			item.obtain = "passive"
		elseif StatisticsConfig.buttonTiers[skill][item.key] then
			item.obtain = "button"
		else
			item.obtain = "locked"
		end
	end
end

-- ===================== GRID LAYOUT CONSTANTS =====================
-- 9 columns. Max 28 stat slots (4 rows x 7); unused positions = BlankSlot.
-- Row 0 header (SelectedSkill), rows 1-4 stats (2 pad + 7), row 5 footer.

StatisticsConfig.COLUMNS = 9
StatisticsConfig.STAT_ROWS = 4
StatisticsConfig.STATS_PER_ROW = 7
StatisticsConfig.MAX_STATS = 28

StatisticsConfig.LAYOUT = {
	-- Row 0: header
	headerBlanksBefore = 4, -- LO 0..3
	selectedSkillOrder = 4, -- LO 4
	headerBlanksAfter = 3, -- LO 5..7

	-- Rows 1-4: stat rows (row 1 starts at LO 9, then +9 per row)
	statRowBaseOrder = 9,
	statRowPadCount = 2,

	-- Row 5: footer
	footerRowStart = 45,
	footerBlanksBefore = 4,
	backButtonOrder = 49,
	closeSlotOrder = 50,
	footerBlanksAfter = 4,
}

-- Warn in Studio if a chain outgrows the page or a reference is misspelled.
for skill, chain in pairs(StatisticsConfig.STAT_CHAINS) do
	if #chain > StatisticsConfig.MAX_STATS then
		warn(("[StatisticsConfig] %s has %d stats, the page only fits %d"):format(skill, #chain, StatisticsConfig.MAX_STATS))
	end
	for _, item in ipairs(chain) do
		for _, c in ipairs(item.cost or {}) do
			if not (StatisticsConfig.statConfigLookup[c.skill] and StatisticsConfig.statConfigLookup[c.skill][c.id]) then
				warn(("[StatisticsConfig] %s.%s costs unknown stat %s.%s"):format(skill, item.key, tostring(c.skill), tostring(c.id)))
			end
		end
		for _, r in ipairs(item.rewards or {}) do
			if r.type == "stat" and not (StatisticsConfig.statConfigLookup[r.skill or skill] and StatisticsConfig.statConfigLookup[r.skill or skill][r.target]) then
				warn(("[StatisticsConfig] %s.%s rewards unknown stat %s.%s"):format(skill, item.key, tostring(r.skill), tostring(r.target)))
			end
		end
	end
end

print("StatisticsConfig: Loaded ✓")
return StatisticsConfig
