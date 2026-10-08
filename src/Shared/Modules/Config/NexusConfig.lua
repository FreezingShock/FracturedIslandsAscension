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

-- The Nexus Level page (NexusLevelPageModule): which cells of its 9 x 6 grid the big badge and the info panel span (row / column, 0-based)
NexusConfig.page = {
	badgeCells = { rows = { 0, 4 }, cols = { 0, 3 } },
	infoCells = { rows = { 0, 4 }, cols = { 4, 8 } },
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

return NexusConfig
