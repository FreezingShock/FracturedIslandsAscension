--[[
	SkillsConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Everything the Skills system reads: the six skills, level caps, the XP curve, level rewards and the Roman numerals.
	Used by SkillsDataManager (XP and levels), SkillRewardService (grants) and SkillsPageModule (display).

	LEVELS are 1-based (a new player is level 1). Level N -> N+1 needs XP_TABLE[N] (Hypixel's curve). A skill stops at its cap.

	XP WISDOM: gain = floor(base * (1 + (skillWisdom + Wisdom) / 100)); skillWisdom is the attribute named by skills[x].wisdom.

	REWARDS reach every level a player reaches (SkillRewardService grants each level once). They are layered like
	CollectionsConfig, each layer REPLACES the one below it. getRewards(skill, level) returns the first that has an entry:
	    4. overrides[skill][level]        one skill, one level
	    3. skillMilestones[skill][level]  one skill at its milestone levels
	    2. milestones[level]              every skill at the milestone levels (list, or function(skill) -> list)
	    1. defaultRewards(level, skill)   the formula all other levels use (built from DEFAULTS[skill])
	A reward is { type = <CollectionRewards type>, ... }:
	    { type = "gameStat",  attr = "FarmingFortune", flat = 4 }       (or pct = 5)
	    { type = "statGrant", skill = "General", key = "BronzeCoins", amount = 200 }
	    { type = "statGain",  skill = "Farming", key = "Wheat", pct = 5 }      +5% gain of that statistic
	    { type = "item", tool = "ToolName", count = 1 }  { type = "recipe", id = "..." }
	    { type = "unlock", id = "FarmingButtons2", label = "Farming Buttons 2 Unlocked", color = "#FFAA00" }   (recorded, stub)

	Recipes:  new reward on a level -> add it to overrides / skillMilestones / milestones. No code.
	          new skill            -> add it to ORDER and skills, and a Wisdom attribute in ProfileConfig.
--]]

local SkillsConfig = {}

SkillsConfig.ORDER = { "Farming", "Foraging", "Fishing", "Mining", "Combat", "Carpentry" }
SkillsConfig.PAGE_SIZE = 25 -- level slots on the breakdown strip (SkillLevels.ScrollingFrame Level1..Level25)

SkillsConfig.skills = {
	Farming = {
		name = "Farming",
		color = "#FFAA00",
		wisdom = "FarmingWisdom",
		cap = 60,
		description = "Farming skill increases your multipliers among all Farming buttons.",
	},
	Foraging = {
		name = "Foraging",
		color = "#00AA00",
		wisdom = "ForagingWisdom",
		cap = 50,
		description = "Foraging skill increases your multipliers among all Foraging buttons.",
	},
	Fishing = {
		name = "Fishing",
		color = "#00AAAA",
		wisdom = "FishingWisdom",
		cap = 50,
		description = "Fishing skill increases your multipliers among all Fishing buttons.",
	},
	Mining = {
		name = "Mining",
		color = "#5555FF",
		wisdom = "MiningWisdom",
		cap = 50,
		description = "Mining skill increases your multipliers among all Mining buttons.",
	},
	Combat = {
		name = "Combat",
		color = "#FF5555",
		wisdom = "CombatWisdom",
		cap = 60,
		description = "Combat skill increases your multipliers among all Combat buttons.",
	},
	Carpentry = {
		name = "Carpentry",
		color = "#55FF55",
		wisdom = "CarpentryWisdom",
		cap = 50,
		description = "Carpentry skill increases your multipliers when crafting Accessories, Armor, or other trinkets.",
	},
}

-- ===================== XP CURVE (Hypixel) =====================
-- XP_TABLE[N] = XP needed to go from level N to level N+1.
SkillsConfig.XP_TABLE = {
	50,
	125,
	200,
	300,
	500,
	750,
	1000,
	1500,
	2000,
	3500,
	5000,
	7500,
	10000,
	15000,
	20000,
	30000,
	50000,
	75000,
	100000,
	200000,
	300000,
	400000,
	500000,
	600000,
	700000,
	800000,
	900000,
	1000000,
	1100000,
	1200000,
	1300000,
	1400000,
	1500000,
	1600000,
	1700000,
	1800000,
	1900000,
	2000000,
	2100000,
	2200000,
	2300000,
	2400000,
	2500000,
	2600000,
	2750000,
	2900000,
	3100000,
	3400000,
	3700000,
	4000000,
	4300000,
	4600000,
	4900000,
	5200000,
	5500000,
	5800000,
	6100000,
	6400000,
	6700000,
	7000000,
}

function SkillsConfig.cap(skill: string): number
	local config = SkillsConfig.skills[skill]
	return config and config.cap or 50
end

--- XP to go from `level` to the next one; 0 at (or above) the cap.
function SkillsConfig.xpNeeded(skill: string, level: number): number
	if level >= SkillsConfig.cap(skill) then
		return 0
	end
	return SkillsConfig.XP_TABLE[level] or SkillsConfig.XP_TABLE[#SkillsConfig.XP_TABLE]
end

function SkillsConfig.pageCount(skill: string): number
	return math.ceil(SkillsConfig.cap(skill) / SkillsConfig.PAGE_SIZE)
end

-- ===================== LEVEL STRIP LAYOUT (the snake) =====================
-- The 25 slots of a page are placed by SkillsPageModule along a snake path (no UIGridLayout): first 3 down, then
-- repeat { 2 right, 2 up, 2 right, 2 down }. Change the path or sizes here; rows = how many rows the strip has.
SkillsConfig.SNAKE = {
	rows = 4,
	cell = 65, -- slot size in pixels
	gapX = 10,
	gapY = 7,
	pad = 10, -- space around the strip
	first = { "D", 3 },
	loop = { { "R", 2 }, { "U", 2 }, { "R", 2 }, { "D", 2 } },
}

local STEP = { R = { 1, 0 }, L = { -1, 0 }, D = { 0, 1 }, U = { 0, -1 } }

--- Grid cells ({ col, row }, 0-based) of the first `count` slots along the snake path.
function SkillsConfig.snakeCells(count: number): { { number } }
	local snake = SkillsConfig.SNAKE
	local cells = { { 0, 0 } }
	local col, row = 0, 0
	local function walk(direction: string, steps: number)
		local d = STEP[direction]
		for _ = 1, steps do
			if #cells >= count then
				return
			end
			col += d[1]
			row = math.clamp(row + d[2], 0, snake.rows - 1)
			table.insert(cells, { col, row })
		end
	end
	walk(snake.first[1], snake.first[2])
	while #cells < count do
		for _, segment in ipairs(snake.loop) do
			walk(segment[1], segment[2])
		end
	end
	return cells
end

-- ===================== ROMAN NUMERALS =====================
local ROMAN_PARTS = { { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" } }
local romanCache: { [number]: string } = {}

--- 1 -> "I" ... 60 -> "LX" (one shared helper; nothing else needs its own table).
function SkillsConfig.roman(n: number): string
	n = math.floor(n)
	if n < 1 then
		return "0"
	end
	local cached = romanCache[n]
	if cached then
		return cached
	end
	local left, text = n, ""
	for _, part in ipairs(ROMAN_PARTS) do
		while left >= part[1] do
			text ..= part[2]
			left -= part[1]
		end
	end
	romanCache[n] = text
	return text
end

-- ===================== REWARDS =====================
-- What every level of a skill gives (the old "general" rewards of the Skills page, now real).
local DEFAULTS = {
	Farming = { attr = "FarmingFortune", amount = 4, second = { attr = "Health", flat = 2 } },
	Foraging = { attr = "ForagingFortune", amount = 4, second = { attr = "CritChance", flat = 0.25 } },
	Fishing = { attr = "FishingFortune", amount = 4, second = { attr = "FishingSpeed", flat = 0.01 } },
	Mining = { attr = "MiningFortune", amount = 4, second = { attr = "MiningSpeed", flat = 0.01 } },
	Combat = { attr = "Defense", amount = 1, second = { attr = "Strength", flat = 0.5 } },
	Carpentry = { attr = "Refine", amount = 1, second = { attr = "Luck", flat = 0.01 } }, -- no crafting-quality attribute yet
}

local COINS = { type = "statGrant", skill = "General", key = "BronzeCoins", amount = 200 }
local NEXUS_XP = { type = "unlock", id = "NexusXP", label = "5 Aetheric Nexus XP", color = "#FF55FF" } -- stub: no Nexus XP system yet

function SkillsConfig.defaultRewards(level: number, skill: string)
	local d = DEFAULTS[skill]
	if not d then
		return {}
	end
	return {
		{ type = "gameStat", attr = d.attr, flat = d.amount },
		{ type = "gameStat", attr = d.second.attr, flat = d.second.flat },
		COINS,
		NEXUS_XP,
	}
end

--- The levels that count as milestones (bigger rewards, gold star on the strip).
SkillsConfig.MILESTONE_LEVELS = { 5, 10, 15, 20, 25, 30, 40, 50, 60 }

--- Layer 2: every skill at the milestone levels = the default level reward + 1 wisdom (2 at the last two).
local function withDefaults(skill: string, level: number, extra: { any }): { any }
	local list = SkillsConfig.defaultRewards(level, skill)
	for _, reward in ipairs(extra) do
		table.insert(list, reward)
	end
	return list
end

SkillsConfig.milestones = {} -- filled below (needs `skills` for the wisdom attribute)
for _, level in ipairs(SkillsConfig.MILESTONE_LEVELS) do
	SkillsConfig.milestones[level] = function(skill: string)
		local config = SkillsConfig.skills[skill]
		if level > config.cap then
			return nil
		end
		return withDefaults(
			skill,
			level,
			{ { type = "gameStat", attr = config.wisdom, flat = level >= 50 and 2 or 1 } }
		)
	end
end

--- Layer 3: skillMilestones[skill][level] - ported from the old Skills page. Plain display lines become `unlock` entries
--- (recorded in the profile, behaviour comes later) so nothing the old UI promised disappears.
local OLD_LINES = {
	Farming = {
		[5] = { { "Crop Storage +10", "#55FFFF" } },
		[10] = { { "Farming Buttons 2 Unlocked", "#FFAA00" }, { "+5% Crop Yield (Milestone)", "#55FF55" } },
		[15] = { { "Auto-Harvest Ability Unlocked", "#FF55FF" } },
		[20] = { { "Farming Buttons 3 Unlocked", "#FFAA00" }, { "+10% Harvest Speed (Milestone)", "#FFAA00" } },
		[25] = { { "Master Farmer Title", "#FFD700" }, { "Rare Seed Drop Chance +2%", "#FF55FF" } },
		[30] = { { "Farming Buttons 4 Unlocked", "#FFAA00" } },
		[40] = { { "Farming Buttons 5 Unlocked", "#FFAA00" }, { "Legendary Seed Access", "#FFD700" } },
		[50] = {
			{ "MAX LEVEL - Grandmaster Farmer", "#FFD700" },
			{ "Exclusive Farm Pet Unlocked", "#FF55FF" },
			{ "+25% All Farming Stats", "#55FF55" },
		},
	},
	Foraging = {
		[5] = { { "Forage Bag Slot +5", "#55FFFF" } },
		[10] = { { "Foraging Area 2 Unlocked", "#00AA00" }, { "+5% Rare Find Chance", "#55FF55" } },
		[15] = { { "Night Foraging Unlocked", "#FF55FF" } },
		[20] = { { "Foraging Area 3 Unlocked", "#00AA00" } },
		[25] = { { "Master Forager Title", "#FFD700" }, { "Legendary Herb Chance +1%", "#FF55FF" } },
		[50] = { { "MAX LEVEL - Grandmaster Forager", "#FFD700" }, { "+25% All Foraging Stats", "#55FF55" } },
	},
	Fishing = {
		[5] = { { "Fishing Rod Upgrade Slot", "#55FFFF" } },
		[10] = { { "Deep Sea Fishing Unlocked", "#00AAAA" }, { "+5% Rare Fish Chance", "#55FF55" } },
		[15] = { { "Night Fishing Unlocked", "#FF55FF" } },
		[20] = { { "Fishing Spot 3 Unlocked", "#00AAAA" } },
		[25] = { { "Master Angler Title", "#FFD700" }, { "Legendary Fish Chance +1%", "#FF55FF" } },
		[50] = { { "MAX LEVEL - Grandmaster Angler", "#FFD700" }, { "+25% All Fishing Stats", "#55FF55" } },
	},
	Mining = {
		[5] = { { "Ore Bag Slot +5", "#55FFFF" } },
		[10] = { { "Deep Mine Access Unlocked", "#5555FF" }, { "+5% Gem Find Chance", "#55FF55" } },
		[15] = { { "Dynamite Ability Unlocked", "#FF5555" } },
		[20] = { { "Mine Level 3 Unlocked", "#5555FF" }, { "+10% Ore Yield (Milestone)", "#FFAA00" } },
		[25] = { { "Master Miner Title", "#FFD700" }, { "Legendary Ore Chance +1%", "#FF55FF" } },
		[50] = {
			{ "MAX LEVEL - Grandmaster Miner", "#FFD700" },
			{ "Exclusive Mining Pet Unlocked", "#FF55FF" },
			{ "+25% All Mining Stats", "#55FF55" },
		},
	},
	Combat = {
		[5] = { { "Combo Multiplier Unlocked", "#55FFFF" } },
		[10] = { { "Dual Wield Unlocked", "#FF5555" }, { "+5% Critical Damage", "#55FF55" } },
		[15] = { { "Parry Ability Unlocked", "#FF55FF" } },
		[20] = { { "Combat Arena 3 Unlocked", "#FF5555" }, { "+10% All Damage (Milestone)", "#FFAA00" } },
		[25] = { { "Master Combatant Title", "#FFD700" }, { "Berserker Passive Unlocked", "#FF55FF" } },
		[50] = {
			{ "MAX LEVEL - Grandmaster Warrior", "#FFD700" },
			{ "Exclusive Combat Pet Unlocked", "#FF55FF" },
			{ "+25% All Combat Stats", "#55FF55" },
		},
	},
	Carpentry = {
		[5] = { { "Blueprint Slot +1", "#55FFFF" } },
		[10] = { { "Advanced Crafting Unlocked", "#55FF55" }, { "+5% Material Efficiency", "#55FF55" } },
		[15] = { { "Auto-Craft Ability Unlocked", "#FF55FF" } },
		[20] = { { "Master Workbench Unlocked", "#55FF55" }, { "+10% Craft Speed (Milestone)", "#FFAA00" } },
		[25] = { { "Master Carpenter Title", "#FFD700" }, { "Legendary Blueprint Access", "#FF55FF" } },
		[50] = {
			{ "MAX LEVEL - Grandmaster Crafter", "#FFD700" },
			{ "Exclusive Carpentry Pet", "#FF55FF" },
			{ "+25% All Carpentry Stats", "#55FF55" },
		},
	},
}

SkillsConfig.skillMilestones = {}
for skill, byLevel in pairs(OLD_LINES) do
	local out = {}
	local cap = SkillsConfig.skills[skill].cap
	for level, lines in pairs(byLevel) do
		-- the old "MAX LEVEL" lines belong on the real last level (60 for Farming and Combat)
		local target = (level == 50) and cap or level
		local milestone = SkillsConfig.milestones[target] and SkillsConfig.milestones[target](skill) or {}
		for index, line in ipairs(lines) do
			table.insert(milestone, {
				type = "unlock",
				id = string.format("%s%d.%d", skill, target, index),
				label = line[1],
				color = line[2],
			})
		end
		out[target] = milestone
	end
	SkillsConfig.skillMilestones[skill] = out
end

--- Layer 4: overrides[skill][level] = { rewards }, replaces everything below it.
SkillsConfig.overrides = {}

local function resolve(value: any, skill: string)
	if type(value) == "function" then
		return value(skill)
	end
	return value
end

--- The reward list of one level of one skill (never nil, may be empty).
function SkillsConfig.getRewards(skill: string, level: number): { any }
	if level < 1 or level > SkillsConfig.cap(skill) then
		return {}
	end
	local byOverride = SkillsConfig.overrides[skill]
	local bySkill = SkillsConfig.skillMilestones[skill]
	return (byOverride and byOverride[level])
		or (bySkill and bySkill[level])
		or resolve(SkillsConfig.milestones[level], skill)
		or SkillsConfig.defaultRewards(level, skill)
		or {}
end

function SkillsConfig.isMilestone(skill: string, level: number): boolean
	return level <= SkillsConfig.cap(skill) and SkillsConfig.milestones[level] ~= nil
end

return SkillsConfig
