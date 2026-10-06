--[[
	CollectionsConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Everything the Collections system reads: tiers, rewards, status colours and the grid layout.
	Tier math lives in CollectionMath, reward behaviour in CollectionRewards, the server grant in CollectionService.

	Every statistic of every skill (StatisticsConfig.STAT_CHAINS) has its own collection of TIER_COUNT tiers.
	Tier N needs threshold(N) = 10^(N+1) lifetime of that stat (100, 1K, 10K, ...).

	REWARDS are layered like CombatConfig (library -> type -> override). getRewards(skill, statKey, tier) returns the
	first layer that has an entry, each layer REPLACES the one below it:
	    1. stats[skill][statKey][tier]     one statistic's own tier
	    2. skills[skill][tier]             every statistic of a skill at that tier
	    3. milestones[tier]                every statistic at that tier (5, 10, 15, ...)
	    4. defaultRewards(tier, skill, statKey)   the formula every other tier uses

	A reward entry is { type = <registered type>, ... }; the types are in CollectionRewards:
	    { type = "statGain",      pct = 5 }                          +5% gain of the collected statistic
	    { type = "statGain",      pct = 5, skill = "General", key = "BronzeCoins" }   (or another one: crossStatGain)
	    { type = "crossStatGain", skill = "General", key = "BronzeCoins", pct = 10 }
	    { type = "gameStat",      attr = "Defense", flat = 2 }      flat bonus (or pct = 5 for +5%)
	    { type = "item",          tool = "ToolName", count = 1 }    stub: granted only if the tool exists in ServerStorage
	    { type = "recipe",        id = "IronSword" }                stub: recorded in the profile, recipes come later

	Recipes (what a new reward takes):
	    new reward on one tier   -> add it to milestones / skills / stats below. No code.
	    new kind of reward       -> CollectionRewards.register("myType", { describe = ..., derive/apply = ... }).
	    new statistic            -> add it to StatisticsConfig; it gets 28 tiers and the default reward automatically.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any

local CollectionsConfig = {}

-- ===================== RE-EXPORTS FROM STATISTICS =====================
CollectionsConfig.STAT_CHAINS = StatisticsConfig.STAT_CHAINS
CollectionsConfig.SKILL_COLORS = StatisticsConfig.SKILL_COLORS
CollectionsConfig.statConfigLookup = StatisticsConfig.statConfigLookup
CollectionsConfig.SKILL_NAMES = StatisticsConfig.SKILL_NAMES

-- ===================== TIERS =====================
CollectionsConfig.TIER_COUNT = 28

--- Lifetime a statistic needs for tier `tier` (100, 1K, 10K, ... exact powers of ten so MoneyLib formats them).
function CollectionsConfig.threshold(tier: number): number
	return 10 ^ (tier + 1)
end

CollectionsConfig.COLLECTION_TIERS = {}
for i = 1, CollectionsConfig.TIER_COUNT do
	CollectionsConfig.COLLECTION_TIERS[i] = { level = i, threshold = CollectionsConfig.threshold(i) }
end

CollectionsConfig.TIER_COLORS = {
	locked = "#FF5555",
	inProgress = "#FFFF55",
	completed = "#55FF55",
}

local ROMAN_PARTS = {
	{ 10, "X" },
	{ 9, "IX" },
	{ 5, "V" },
	{ 4, "IV" },
	{ 1, "I" },
}
CollectionsConfig.ROMAN_NUMERALS = {}
for tier = 1, CollectionsConfig.TIER_COUNT do
	local left, text = tier, ""
	for _, part in ipairs(ROMAN_PARTS) do
		while left >= part[1] do
			text ..= part[2]
			left -= part[1]
		end
	end
	CollectionsConfig.ROMAN_NUMERALS[tier] = text
end

-- ===================== REWARDS =====================
--- Layer 4: the formula every tier without a milestone / override uses.
function CollectionsConfig.defaultRewards(tier: number, skill: string, statKey: string)
	return { { type = "statGain", pct = 5 } }
end

--- Layer 3: every statistic at these tiers (replaces the default).
CollectionsConfig.milestones = {
	[5] = {
		{ type = "statGain", pct = 15 },
		{ type = "gameStat", attr = "Defense", flat = 2 },
	},
	[10] = {
		{ type = "statGain", pct = 25 },
		{ type = "gameStat", attr = "Health", flat = 10 },
		{ type = "item", tool = "CollectionToken", count = 1 }, -- stub until the tool exists
	},
	[15] = {
		{ type = "statGain", pct = 35 },
		{ type = "gameStat", attr = "Intelligence", flat = 5 },
		{ type = "recipe", id = "CollectionRecipe15" }, -- stub: recorded only
	},
	[20] = {
		{ type = "statGain", pct = 50 },
		{ type = "gameStat", attr = "Strength", flat = 5 },
	},
	[25] = {
		{ type = "statGain", pct = 75 },
		{ type = "gameStat", attr = "Defense", pct = 2 },
	},
	[28] = {
		{ type = "statGain", pct = 100 },
		{ type = "gameStat", attr = "Health", pct = 5 },
		{ type = "gameStat", attr = "Intelligence", pct = 5 },
	},
}

--- Layer 2: skills[skill][tier] = { rewards } (every statistic of the skill at that tier).
CollectionsConfig.skills = {
	Farming = {
		[10] = {
			{ type = "statGain", pct = 25 },
			{ type = "crossStatGain", skill = "General", key = "BronzeCoins", pct = 10 },
			{ type = "gameStat", attr = "Health", flat = 10 },
		},
	},
}

--- Layer 1: stats[skill][statKey][tier] = { rewards } (one statistic only).
CollectionsConfig.stats = {}

--- The reward list of one tier of one statistic (never nil, may be empty).
function CollectionsConfig.getRewards(skill: string, statKey: string, tier: number): { any }
	local byStat = CollectionsConfig.stats[skill]
	local list = byStat and byStat[statKey] and byStat[statKey][tier]
		or CollectionsConfig.skills[skill] and CollectionsConfig.skills[skill][tier]
		or CollectionsConfig.milestones[tier]
		or CollectionsConfig.defaultRewards(tier, skill, statKey)
	return list or {}
end

-- ===================== GRID LAYOUT =====================
-- All collection grids are 9 columns x 6 rows (cell = row * columns + column, which is the LayoutOrder).
--   Menu2  header: skill in column 4              rows 1-4: up to 28 statistics (7 per row, 1 blank column on each side)
--   Menu3  header: statistic in column 4          rows 1-4: the 28 tier slots (7 per row)
--   Menu4  header: tier title in column 4         rewardRow: the rewards, evenly spaced (CollectionMath.rewardColumns)
--   footer (row 5): Back in column 4, Close in column 5
CollectionsConfig.LAYOUT = {
	columns = 9,
	rows = 6,
	headerCol = 4,
	contentRows = { 1, 4 },
	contentFirstCol = 1, -- one blank cell before and one after the 7 slots of a row
	contentPerRow = 7,
	rewardRow = 2,
	maxRewards = 7,
	footerRow = 5,
	backCol = 4,
	closeCol = 5,
}

return CollectionsConfig
