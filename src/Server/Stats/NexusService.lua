--[[
	NexusService (ModuleScript, Server)
	Place inside: ServerScriptService

	The Aetheric Nexus Level (see NexusConfig). The saved data is `_Nexus` in the skills profile:
	  { xp = total XP, sources = { skills = n, collections = n, misc = n }, awarded = { [key] = true }, claimedLevel = n }
	`awarded` holds one key per paid task ("s.Farming.7", "c.Farming.wheat.3"), so a task can never pay twice (a level that is lowered
	and gained again, a replayed reward, a rejoin). The level is derived from `xp`, nothing else is stored.

	  NexusService.award(player, category, key, amount)   pay a task once (key = nil: no dedupe, server-only callers like the admin grant)
	  NexusService.onSkillLevel(player, skill, level)     a skill reached `level` (SkillRewardService)
	  NexusService.onCollectionTier(player, skill, key, tier)   a collection tier was granted (CollectionService)
	  NexusService.backfillCollections(player, claimed)   pay the tiers claimed before this system existed (once per session)
	  NexusService.get(player)                            { level, progress, total, sources }

	It publishes Player attributes (NexusConfig.attributes) after every change and when the profile loads; clients only read them.
	Tasks done before this system existed are paid on load (skills here, collections through CollectionService), each once.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local NexusConfig = require(Modules:WaitForChild("Config"):WaitForChild("NexusConfig")) :: any
local SkillsConfig = require(Modules:WaitForChild("SkillsConfig")) :: any
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any

local ATTR = NexusConfig.attributes

local NexusService = {}

local backfilledSkills: { [Player]: boolean } = {}
local backfilledCollections: { [Player]: boolean } = {}
local derivedFor: { [Player]: boolean } = {} -- the level rewards were built at least once this session
local pendingRewards: { [Player]: any } = {} -- reward entries waiting for the attribute profile
local ATTRIBUTE_WAIT = 60 -- seconds to wait for the attribute profile before giving up

--- The saved table, repaired if it is missing a field (an old profile, a hand-edited one).
local function nexusOf(data)
	local nexus = data._Nexus
	if type(nexus) ~= "table" then
		nexus = {}
		data._Nexus = nexus
	end
	nexus.xp = type(nexus.xp) == "number" and nexus.xp or 0
	nexus.sources = type(nexus.sources) == "table" and nexus.sources or {}
	nexus.awarded = type(nexus.awarded) == "table" and nexus.awarded or {}
	nexus.claimedLevel = type(nexus.claimedLevel) == "number" and nexus.claimedLevel or 0
	return nexus
end

local function publish(player: Player)
	local data = SkillsDataManager.GetData(player)
	if not data then
		return
	end
	local nexus = nexusOf(data)
	local level, progress = NexusConfig.levelFromXp(nexus.xp)
	player:SetAttribute(ATTR.level, level)
	player:SetAttribute(ATTR.progress, progress)
	player:SetAttribute(ATTR.total, nexus.xp)
	for id in pairs(NexusConfig.categories) do
		player:SetAttribute(ATTR.categoryPrefix .. id, nexus.sources[id] or 0)
	end
end


-- ===================== LEVEL REWARDS =====================
-- A permanent stat bonus per level (NexusConfig.rewardsFor). `claimedLevel` is a high-water mark: a level is marked paid FIRST, and the
-- boosts are rebuilt from the WHOLE claimed range every time (AttributeStatManager.ApplySource replaces everything with the "nexus:" prefix),
-- so a rejoin, a restore or a lowered total can never double a reward or take one back.
local function applyAttributes(player: Player, entries)
	pendingRewards[player] = entries
	local function apply()
		pendingRewards[player] = nil
		AttributeStatManager.ApplySource(player, "nexus:", entries, "nexus")
		SkillsDataManager.MarkDirty(player) -- the stats shown on the pages may have changed
	end
	if AttributeStatManager.IsLoaded(player) then
		apply()
		return
	end
	task.spawn(function()
		local waited = 0
		while player.Parent and waited < ATTRIBUTE_WAIT and pendingRewards[player] == entries do
			if AttributeStatManager.IsLoaded(player) then
				apply()
				return
			end
			waited += task.wait(0.5)
		end
	end)
end

local function syncRewards(player: Player)
	local data = SkillsDataManager.GetData(player)
	if not data then
		return
	end
	local nexus = nexusOf(data)
	local level = NexusConfig.levelFromXp(nexus.xp)
	local grew = level > nexus.claimedLevel
	if grew then
		nexus.claimedLevel = level -- high-water mark first: a level is never paid twice
	end
	if not (grew or not derivedFor[player]) then
		return
	end
	derivedFor[player] = true
	local entries = {}
	for l = 1, nexus.claimedLevel do
		for index, reward in ipairs(NexusConfig.rewardsFor(l)) do
			local stat = NexusConfig.rewards.stats[reward.stat]
			table.insert(entries, {
				id = string.format("%d.%d", l, index),
				label = string.format("Nexus Level %d", l),
				color = stat and stat.color or "#FF55FF",
				attr = reward.stat,
				flat = reward.amount,
			})
		end
	end
	applyAttributes(player, entries)
end

function NexusService.claimedLevel(player: Player): number
	local data = SkillsDataManager.GetData(player)
	return data and nexusOf(data).claimedLevel or 0
end

--- Pay `amount` XP of `category` once per `key`. Returns the XP actually added (0 when already paid, capped, or invalid).
function NexusService.award(player: Player, category: string, key: string?, amount: number): number
	if type(category) ~= "string" or not NexusConfig.categories[category] then
		warn("[NexusService] unknown category " .. tostring(category))
		return 0
	end
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return 0
	end
	if key ~= nil and type(key) ~= "string" then
		return 0
	end
	local data = SkillsDataManager.GetData(player)
	if not data then
		return 0
	end
	local nexus = nexusOf(data)
	if key and nexus.awarded[key] then
		return 0
	end
	if key then
		nexus.awarded[key] = true -- recorded first: whatever happens below, a task is never paid twice
	end
	local gain = math.min(math.floor(amount), math.max(NexusConfig.maxXp() - nexus.xp, 0))
	if gain <= 0 then
		return 0
	end
	nexus.xp += gain
	nexus.sources[category] = (nexus.sources[category] or 0) + gain
	publish(player)
	syncRewards(player)
	return gain
end

function NexusService.onSkillLevel(player: Player, skill: string, level: number)
	local amount = NexusConfig.skillLevelXp(skill, level)
	if amount > 0 then
		NexusService.award(player, NexusConfig.categoryOf("skillLevel"), string.format("s.%s.%d", skill, level), amount)
	end
end

function NexusService.onCollectionTier(player: Player, skill: string, key: string, tier: number)
	local amount = NexusConfig.collectionTierXp(skill, key, tier)
	if amount > 0 then
		NexusService.award(player, NexusConfig.categoryOf("collectionTier"), string.format("c.%s.%s.%d", skill, key, tier), amount)
	end
end

--- Pay every tier already claimed ({ [skill] = { [statKey] = highestTier } }), once per session; the saved keys make it safe to repeat.
function NexusService.backfillCollections(player: Player, claimed: any)
	if backfilledCollections[player] or type(claimed) ~= "table" or not SkillsDataManager.GetData(player) then
		return -- (no skills profile yet: the next sync pays it)
	end
	backfilledCollections[player] = true
	for skill, byStat in pairs(claimed) do
		if type(byStat) == "table" then
			for key, tier in pairs(byStat) do
				for t = 1, math.floor(tonumber(tier) or 0) do
					NexusService.onCollectionTier(player, skill, key, t)
				end
			end
		end
	end
end

local function backfillSkills(player: Player)
	if backfilledSkills[player] then
		return
	end
	local data = SkillsDataManager.GetData(player)
	if not data then
		return
	end
	backfilledSkills[player] = true
	for _, skill in ipairs(SkillsConfig.ORDER) do
		local level = data[skill] and data[skill].level or 1
		for l = 2, level do
			NexusService.onSkillLevel(player, skill, l)
		end
	end
end

function NexusService.get(player: Player)
	local data = SkillsDataManager.GetData(player)
	if not data then
		return nil
	end
	local nexus = nexusOf(data)
	local level, progress = NexusConfig.levelFromXp(nexus.xp)
	return { level = level, progress = progress, total = nexus.xp, sources = nexus.sources }
end

--- Admin tools only: set the TOTAL by changing the Misc category (never below what the other categories hold). Returns the new total.
function NexusService.adminSetTotal(player: Player, total: number): number?
	local data = SkillsDataManager.GetData(player)
	if not data then
		return nil
	end
	local nexus = nexusOf(data)
	local others = nexus.xp - (nexus.sources.misc or 0)
	local misc = math.clamp(math.floor(total) - others, 0, math.max(NexusConfig.maxXp() - others, 0))
	nexus.sources.misc = misc
	nexus.xp = others + misc
	publish(player)
	syncRewards(player)
	return nexus.xp
end

SkillsDataManager.OnChanged(function(player)
	if player.Parent then
		backfillSkills(player)
		publish(player)
		syncRewards(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	backfilledSkills[player] = nil
	backfilledCollections[player] = nil
	derivedFor[player] = nil
	pendingRewards[player] = nil
end)

return NexusService
