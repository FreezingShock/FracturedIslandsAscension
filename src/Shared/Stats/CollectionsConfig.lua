--[[
	CollectionsConfig (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Shared configuration for the Collections system.
	Defines collection tier thresholds, placeholder rewards,
	tier status colors, and grid layout constants for
	CollectionsMenu2 and CollectionsMenu3.

	References StatisticsConfig.STAT_CHAINS for the stat lists
	per skill — no duplication of stat definitions.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any

local CollectionsConfig = {}

-- ===================== RE-EXPORTS FROM STATISTICS =====================
CollectionsConfig.STAT_CHAINS = StatisticsConfig.STAT_CHAINS
CollectionsConfig.SKILL_COLORS = StatisticsConfig.SKILL_COLORS
CollectionsConfig.statConfigLookup = StatisticsConfig.statConfigLookup

-- ===================== COLLECTION TIERS =====================
-- 28 levels.  Each tier = 10× the previous, starting at 100.
-- Tier 1 = 10^2, Tier 2 = 10^3, ... Tier 28 = 10^29.
-- Thresholds are exact powers of 10 so MoneyLib formats them cleanly.
CollectionsConfig.COLLECTION_TIERS = {}
for i = 1, 28 do
	CollectionsConfig.COLLECTION_TIERS[i] = {
		level = i,
		threshold = 10 ^ (i + 1), -- i=1 → 100, i=2 → 1k, ... i=28 → 10^29
	}
end

-- ===================== COLLECTION REWARDS (placeholder) =====================
-- Keyed by tier level (1-28).  Each value is an array of reward entries.
-- Format matches StatisticsConfig reward entries:
--   { type = "stat", skill = "...", target = "...", pct = N }
--   { type = "gameStat", target = "...", flat = N }
-- Fill in later — for now all empty.
CollectionsConfig.COLLECTION_REWARDS = {}
for i = 1, 28 do
	CollectionsConfig.COLLECTION_REWARDS[i] = {}
end

-- ===================== TIER STATUS COLORS =====================
CollectionsConfig.TIER_COLORS = {
	locked = "#FF5555",
	inProgress = "#FFFF55",
	completed = "#55FF55",
}

-- ===================== ROMAN NUMERALS =====================
-- Pre-built lookup for tiers 1-28.  Used by CollectionsPageModule
-- for LevelLabel text on tier slots.
CollectionsConfig.ROMAN_NUMERALS = {
	"I",
	"II",
	"III",
	"IV",
	"V",
	"VI",
	"VII",
	"VIII",
	"IX",
	"X",
	"XI",
	"XII",
	"XIII",
	"XIV",
	"XV",
	"XVI",
	"XVII",
	"XVIII",
	"XIX",
	"XX",
	"XXI",
	"XXII",
	"XXIII",
	"XXIV",
	"XXV",
	"XXVI",
	"XXVII",
	"XXVIII",
}

-- ===================== SKILL NAMES (with collections) =====================
CollectionsConfig.SKILL_NAMES = { "Farming", "Foraging", "Mining", "Fishing", "Combat", "General" }

-- ===================== GRID LAYOUT CONSTANTS =====================
-- Both CollectionsMenu2 and CollectionsMenu3 use 9-column grids,
-- same structure as StatisticsMenu2.
--
-- ──── CollectionsMenu2 (stat slots for a skill) ────
-- Row 0: [B][B][B][B][SK][B][B][B][B]   SelectedSkill at col 4
-- Row 1: [B][B][S1][S2][S3][S4][S5][S6][S7]  2 pad + 7 stats
-- Row 2: [B][B][S8]...
-- Row 3: [B][B][S15]...
-- Row 4: [B][B][S22]...
-- Row 5: [B][B][B][B][Back][Close][B][B][B]  footer
--
-- Max 28 stat slots (4 rows × 7).

CollectionsConfig.COLUMNS = 9
CollectionsConfig.MENU2_STAT_ROWS = 4
CollectionsConfig.MENU2_STATS_PER_ROW = 7
CollectionsConfig.MENU2_MAX_STATS = 28

CollectionsConfig.MENU2_LAYOUT = {
	-- Row 0: header
	headerBlanksBefore = 4,
	selectedSkillOrder = 4,
	headerBlanksAfter = 4,

	-- Rows 1-4: stat rows
	statRowBaseOrder = 9,
	statRowPadCount = 2,

	-- Row 5: footer
	footerRowStart = 45,
	footerBlanksBefore = 4,
	backButtonOrder = 49,
	closeSlotOrder = 50,
	footerBlanksAfter = 4,
}

-- ──── CollectionsMenu3 (28 tier slots for one stat) ────
-- Row 0: [B][B][B][B][SS][B][B][B][B]          SelectedStatistic
-- Row 1: [B][B][T1][T2][T3][T4][T5][T6][T7]    2 pad + 7 tiers
-- Row 2: [B][B][T8][T9][T10][T11][T12][T13][T14]
-- Row 3: [B][B][T15][T16][T17][T18][T19][T20][T21]
-- Row 4: [B][B][T22][T23][T24][T25][T26][T27][T28]
-- Row 5: [B][B][B][B][Back][Close][B][B][B]     footer
--
-- 28 tiers = 4 rows × 7.  All rows full — no empty rows.

CollectionsConfig.MENU3_TIER_ROWS = 4
CollectionsConfig.MENU3_TIERS_PER_ROW = 7

CollectionsConfig.MENU3_LAYOUT = {
	-- Row 0: header
	-- 4 blanks at LO 0, SelectedStat at LO 1, 4 blanks at LO 2
	headerBlanksBeforeCount = 4,
	headerBlanksBeforeOrder = 0,
	selectedStatOrder = 1,
	headerBlanksAfterCount = 3,
	headerBlanksAfterOrder = 2,

	-- Rows 1-4: tier rows (all 4 rows filled)
	tierRowBaseOrder = 9,
	tierRowPadCount = 2,

	-- Row 5: footer
	footerRowStart = 45,
	footerBlanksBefore = 4,
	backButtonOrder = 49,
	closeSlotOrder = 50,
	footerBlanksAfter = 4,
}

print("CollectionsConfig: Loaded ✓")
return CollectionsConfig
