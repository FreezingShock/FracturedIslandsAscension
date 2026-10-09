--[[
	NexusConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The Aetheric Nexus Level: ONE account level fed by tasks (Hypixel SkyBlock Level style). Every task pays XP ONCE; 100 XP is one level.
	The level is derived from the saved total XP (NexusService), so changing the curve here re-levels everybody without migrating anything.

	LAYERS, each overriding the one before:
	  1. library.<sourceId>        what a kind of task pays:  { category, amount | base + perTen, minLevel? }
	  2. categories.<categoryId>   where the XP is counted (name + colour on the page, saved under _Nexus.sources.<categoryId>)
	  3. overrides.<sourceId>[<scope>]   per skill / per statistic tweaks:  overrides.skillLevel.Farming = { base = 8 }
	                                     overrides.collectionTier["Farming.wheat"] = { amount = 6 }

	RECIPES
	  New task type:        library.quest = { category = "misc", amount = 10 }, then NexusService.award(player, NexusConfig.categoryOf("quest"), "quest.intro", NexusConfig.library.quest.amount)
	  New category:         categories.exploration = { name = "Exploration", color = "#55FF55" } (the page lists every category by order)
	  Skill pays more:      overrides.skillLevel.Mining = { base = 8, perTen = 2 }
	  Longer / shorter life: curve.maxLevel, curve.xpPerLevel
	  Level colours:        tiers (the colour of the level number applies from `from` upwards)

	The client only reads: NexusService publishes Player attributes (attributes below) and the HUD badge + the Nexus Level page render them.
]]

local NexusConfig = {}

NexusConfig.curve = {
	xpPerLevel = 100, -- flat, like SkyBlock (100 XP per level)
	maxLevel = 100,
}

-- Player attributes published by NexusService. The level and the 0..1 progress inside it (1 at the cap) are named in ResourceConfig
-- (nexusLevelAttribute / nexusXpAttribute: the HUD badge reads them), so they are filled in below from there.
local ResourceConfig = require(script.Parent.Parent:WaitForChild("ResourceConfig")) :: any -- (Config is a real folder inside Modules; the rest is flat)
NexusConfig.attributes = {
	level = ResourceConfig.nexusLevelAttribute,
	progress = ResourceConfig.nexusXpAttribute,
	total = "NexusXpTotal",
	categoryPrefix = "NexusXpFrom_", -- + category id: the XP counted in that category
}

NexusConfig.library = {
	skillLevel = { category = "skills", base = 5, perTen = 1, minLevel = 2 }, -- a skill level L pays base + floor(L / 10) * perTen (level 1 pays nothing)
	collectionTier = { category = "collections", amount = 3 },
}

NexusConfig.categories = {
	skills = { name = "Skill level-ups", color = "#55FFFF", order = 1 },
	collections = { name = "Collections", color = "#FFAA00", order = 2 },
	misc = { name = "Misc", color = "#AAAAAA", order = 3 },
}

NexusConfig.overrides = {
	skillLevel = {},
	collectionTier = {},
}

-- The level number colour from `from` upwards (Minecraft palette, SkyBlock-style prefix tiers): placeholder palette
NexusConfig.tiers = {
	{ from = 0, color = "#FFFFFF" }, -- (white, not SkyBlock's gray: gray reads dark on the yellow face)
	{ from = 10, color = "#E6E6E6" },
	{ from = 20, color = "#FFFF55" },
	{ from = 30, color = "#55FF55" },
	{ from = 40, color = "#00AA00" },
	{ from = 50, color = "#55FFFF" },
	{ from = 60, color = "#5555FF" },
	{ from = 70, color = "#FF55FF" },
	{ from = 80, color = "#FFAA00" },
	{ from = 90, color = "#FF5555" },
	{ from = 100, color = "#AA0000" },
}

-- ===================== LEVEL REWARDS =====================
-- What reaching a level gives, GRANTED by NexusService (a permanent stat bonus per level, rebuilt from the saved claimedLevel) and
-- SHOWN by the page tooltips: one pure helper, NexusConfig.rewardsFor(level), feeds both.
--   library.level        every level;  library.milestone  every `milestoneEvery`-th level on top of it
--   overrides[<level>]   REPLACES the list of that one level (e.g. overrides[50] = { { stat = "Health", amount = 50 } })
--   stats[<attribute>]   how a reward line is shown: name + colour (the attribute keys of Attributes)
NexusConfig.rewards = {
	milestoneEvery = 10,
	library = {
		level = { { stat = "Health", amount = 5 } },
		milestone = { { stat = "Defense", amount = 2 }, { stat = "Intelligence", amount = 3 } },
	},
	overrides = {},
	stats = {
		Health = { name = "Health", color = "#FF5555" },
		Defense = { name = "Defense", color = "#55FF55" },
		Intelligence = { name = "Intelligence", color = "#55FFFF" },
	},
}

-- ===================== THE NEXUS LEVEL PAGE (NexusLevelPageModule): a copy of SkyBlock's Levels menu =====================
-- A 9 x 6 grid of slots (row / col, 0-based). `icon` = a key of ItemIconData (assets/icons, tools/fetch_icons.py); `tooltip` = an id of
-- NexusConfig.tooltips. Moving a slot or adding one is data: add an entry (kind picks what it shows) and a tooltip.
NexusConfig.page = {
	preview = { row = 2, cols = { 2, 3, 4, 5, 6 } }, -- two levels back, one back, the CURRENT level (the middle one), then two ahead
	panes = {
		done = { icon = "green_stained_glass_pane", color = "#55FF55" }, -- finished level
		current = { icon = "yellow_stained_glass_pane", color = "#FFFF55" }, -- the level being progressed
		todo = { icon = "red_stained_glass_pane", color = "#FF5555" }, -- not finished
	},
	slots = {
		ranking = { row = 0, col = 4, icon = "item_frame", tooltip = "ranking" },
		comingSoon = { row = 1, col = 7, icon = "redstone_torch", tooltip = "comingSoon" },
		milestone = { row = 3, col = 4, icon = "nether_star", tooltip = "milestone" }, -- directly below the middle preview slot
		rewards = { row = 2, col = 7, icon = "filled_map", tooltip = "rewards" },
		sources = { row = 3, col = 7, icon = "chest", tooltip = "sources" },
		emblems = { row = 4, col = 7, icon = "name_tag", tooltip = "emblems" },
	},
}

-- Tooltip text (Minecraft colour codes). title / lines are rich text; tokens in braces are filled by the page:
-- {level} {xp} {total} {pct} {max} {bar} {done} {milestones} {milestone} {reward}. The page adds the dynamic blocks (reward lines, sources) itself.
NexusConfig.tooltips = {
	ranking = {
		title = '<font color="#55FF55">Your Nexus Level Ranking</font>',
		lines = {
			'<font color="#555555">Classic Mode</font>',
			"",
			'<font color="#FFFFFF">Your level: </font><font color="#FFFF55">{level}</font>',
			'<font color="#FFFFFF">You have: </font><font color="#55FFFF">{total} XP</font>',
			"",
			'<font color="#AAAAAA">You have completed </font><font color="#55FFFF">{pct}%</font><font color="#AAAAAA"> of the total Nexus XP Tasks.</font>',
			"",
			'<font color="#AAAAAA">Ranking information requires Nexus Level 10 or higher.</font>',
			'<font color="#555555">Level rankings may take time to refresh.</font>',
		},
	},
	comingSoon = { title = '<font color="#FF5555">Coming Soon</font>', lines = {} },
	rewards = {
		title = '<font color="#55FF55">Leveling Rewards</font>',
		lines = {
			'<font color="#AAAAAA">View all the rewards you can unlock by leveling up your Nexus Level.</font>',
			"",
			'<font color="#AAAAAA">Progress to Max: </font><font color="#55FFFF">{pct}%</font>',
			"{bar}",
			"",
			'<font color="#FFFF55">Click to view rewards!</font>',
		},
	},
	sources = {
		title = '<font color="#FFAA00">XP Sources</font>',
		lines = { '<font color="#AAAAAA">Where your Nexus XP came from.</font>', "", "{sources}", "", '<font color="#FFFFFF">Total: </font><font color="#FFFF55">{total} XP</font>' },
	},
	emblems = {
		title = '<font color="#55FF55">Prefix Emblems</font>',
		lines = {
			'<font color="#AAAAAA">Add some spice by having an emblem next to your name in chat and in tab!</font>',
			"",
			'<font color="#AAAAAA">Emblems are unlocked through various activities such as leveling up or completing achievements!</font>',
			"",
			'<font color="#FF5555">Coming Soon</font>',
		},
	},
	milestone = {
		title = '<font color="#FFAA00">Next Milestone: Level {milestone}</font>',
		lines = { '<font color="#AAAAAA">Reward:</font>', "{reward}", "", '<font color="#FFFF55">Click to preview!</font>' },
	},
	pane = {
		title = '<font color="#55FF55">Level {level}</font>',
		lines = { '<font color="#AAAAAA">Reward:</font>', "{reward}", "", "{xp}", '<font color="#FFFF55">Click to view rewards!</font>' },
	},
}

-- ===================== HELPERS (pure, shared by the server and the client) =====================
--- XP of the whole curve (the cap).
function NexusConfig.maxXp(): number
	return NexusConfig.curve.maxLevel * NexusConfig.curve.xpPerLevel
end

--- Level, 0..1 progress inside the level, XP into the level and XP the level needs, from a total.
function NexusConfig.levelFromXp(total: number): (number, number, number, number)
	local per, maxLevel = NexusConfig.curve.xpPerLevel, NexusConfig.curve.maxLevel
	total = math.clamp(math.floor(tonumber(total) or 0), 0, per * maxLevel)
	local level = math.min(total // per, maxLevel)
	if level >= maxLevel then
		return maxLevel, 1, per, per
	end
	local into = total - level * per
	return level, into / per, into, per
end

--- The colour (hex string) the level number has.
function NexusConfig.colorFor(level: number): string
	local color = NexusConfig.tiers[1].color
	for _, tier in ipairs(NexusConfig.tiers) do
		if level >= tier.from then
			color = tier.color
		end
	end
	return color
end

--- Category ids in display order.
function NexusConfig.categoryOrder(): { string }
	local ids = {}
	for id in pairs(NexusConfig.categories) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ao, bo = NexusConfig.categories[a].order or 99, NexusConfig.categories[b].order or 99
		if ao ~= bo then
			return ao < bo
		end
		return a < b
	end)
	return ids
end

local function merged(source: string, scope: string?)
	local def = NexusConfig.library[source]
	local override = scope and NexusConfig.overrides[source] and NexusConfig.overrides[source][scope]
	if not override then
		return def
	end
	local out = table.clone(def)
	for key, value in pairs(override) do
		out[key] = value
	end
	return out
end

--- XP a skill level-up pays (0 below minLevel).
function NexusConfig.skillLevelXp(skill: string, level: number): number
	local def = merged("skillLevel", skill)
	if not def or level < (def.minLevel or 1) then
		return 0
	end
	return math.floor((def.base or 0) + (level // 10) * (def.perTen or 0))
end

--- XP a collection tier pays.
function NexusConfig.collectionTierXp(skill: string, key: string, tier: number): number
	local def = merged("collectionTier", skill .. "." .. key)
	return def and math.floor(def.amount or 0) or 0
end

--- The category a task kind counts in.
function NexusConfig.categoryOf(source: string): string
	local def = NexusConfig.library[source]
	return def and def.category or "misc"
end

--- The rewards of one level: a list of { stat, amount } (the library level reward, plus the milestone one on every milestoneEvery-th level).
function NexusConfig.rewardsFor(level: number): { { stat: string, amount: number } }
	local out = {}
	level = math.floor(tonumber(level) or 0)
	if level < 1 or level > NexusConfig.curve.maxLevel then
		return out
	end
	local config = NexusConfig.rewards
	local override = config.overrides[level]
	local source = override
	if not source then
		source = table.clone(config.library.level)
		if level % config.milestoneEvery == 0 then
			for _, reward in ipairs(config.library.milestone) do
				table.insert(source, reward)
			end
		end
	end
	for _, reward in ipairs(source) do
		table.insert(out, { stat = reward.stat, amount = reward.amount })
	end
	return out
end

--- The next milestone level above `level` (nil at the cap).
function NexusConfig.nextMilestone(level: number): number?
	local every = NexusConfig.rewards.milestoneEvery
	local nextLevel = (math.floor(level / every) + 1) * every
	return nextLevel <= NexusConfig.curve.maxLevel and nextLevel or nil
end

--- Milestones reached / in total (for the "Progress to Max" bar of the rewards slot).
function NexusConfig.milestoneCount(level: number): (number, number)
	local every = NexusConfig.rewards.milestoneEvery
	return math.floor(level / every), math.floor(NexusConfig.curve.maxLevel / every)
end

return NexusConfig
