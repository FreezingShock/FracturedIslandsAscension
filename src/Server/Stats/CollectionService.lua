--[[
	CollectionService (ModuleScript, Server)
	Place inside: ServerScriptService

	Server-authoritative collection rewards. The client never asks for a reward; it only shows them.

	  1. After every StatisticsDataManager snapshot flush, sync(player) compares the highest tier of every statistic's
	     OWN lifetime (CollectionMath.highestTier) with the saved claimedTier ([profile]._Collections.claimed).
	  2. A higher tier moves claimedTier up FIRST (a high-water mark), then runs the "grant" rewards of every newly
	     reached tier once. Tiers crossed offline or in one jump are all granted, in order.
	  3. The permanent buffs ("derived" rewards) are NOT added step by step: they are rebuilt from the whole claimedTier
	     table every time it changes (and on join), so an admin restore, a lifetime clamp or a rejoin can never double them.
	       statGain / crossStatGain -> StatisticsDataManager.SetCollectionBonus (read by GetMultiplier)
	       gameStat                 -> AttributeStatManager.ApplyCollection (source type "collection" in the breakdown)
	  4. CollectionTierUnlocked (RemoteEvent, server -> client) carries { skill, key, tier, count } for the toast.

	New reward type: CollectionRewards.register(...) in the shared module and, for behaviour, derive/apply below.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("CollectionsConfig")) :: any
local CollectionMath = require(Modules:WaitForChild("CollectionMath")) :: any
local CollectionRewards = require(Modules:WaitForChild("CollectionRewards")) :: any
local StatisticsDataManager = require(ServerScriptService:WaitForChild("StatisticsDataManager")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any

local CollectionService = {}

local ATTRIBUTE_WAIT = 60 -- seconds to wait for the attribute profile before giving up

-- ===================== REMOTE =====================
local TierUnlocked = ReplicatedStorage:FindFirstChild("CollectionTierUnlocked")
if not TierUnlocked then
	TierUnlocked = Instance.new("RemoteEvent")
	TierUnlocked.Name = "CollectionTierUnlocked"
	TierUnlocked.Parent = ReplicatedStorage
end

-- ===================== REWARD BEHAVIOUR =====================
local function finitePct(value: any): number?
	if type(value) == "number" and value == value and value > -1e6 and value < 1e6 then
		return value
	end
	return nil
end

local function gainDerive(reward, ctx, acc)
	local spec = CollectionRewards.get(reward.type)
	local skill, key = spec.target(reward, ctx)
	local pct = finitePct(reward.pct)
	if not (pct and skill and key and Config.statConfigLookup[skill] and Config.statConfigLookup[skill][key]) then
		warn(
			"[CollectionService] bad "
				.. reward.type
				.. " reward on "
				.. ctx.skill
				.. "."
				.. ctx.key
				.. " tier "
				.. ctx.tier
		)
		return
	end
	acc.gain[skill] = acc.gain[skill] or {}
	acc.gain[skill][key] = (acc.gain[skill][key] or 0) + pct
end

CollectionRewards.register("statGain", { derive = gainDerive })
CollectionRewards.register("crossStatGain", { derive = gainDerive })

CollectionRewards.register("gameStat", {
	derive = function(reward, ctx, acc)
		local statConfig = Config.statConfigLookup[ctx.skill][ctx.key]
		local entry = {
			id = string.format("%s.%s.%d.%d", ctx.skill, ctx.key, ctx.tier, ctx.index),
			label = string.format(
				"%s collection %s",
				statConfig and statConfig.name or ctx.key,
				Config.ROMAN_NUMERALS[ctx.tier]
			),
			color = "#55FFFF",
			attr = reward.attr,
		}
		if finitePct(reward.flat) then
			entry.flat = reward.flat
		elseif finitePct(reward.pct) then
			entry.mult = 1 + reward.pct / 100
		else
			warn("[CollectionService] gameStat reward needs flat or pct (" .. ctx.skill .. "." .. ctx.key .. ")")
			return
		end
		table.insert(acc.attr, entry)
	end,
})

local warnedTools: { [string]: boolean } = {}
CollectionRewards.register("item", {
	apply = function(reward, ctx)
		local tool = reward.tool
		if type(tool) ~= "string" or not ServerStorage:FindFirstChild(tool) then
			if not warnedTools[tostring(tool)] then
				warnedTools[tostring(tool)] = true
				warn(
					"[CollectionService] item reward stub: no tool '"
						.. tostring(tool)
						.. "' in ServerStorage (not granted)"
				)
			end
			return
		end
		local InventoryDataManager = require(ServerScriptService:WaitForChild("InventoryDataManager")) :: any
		InventoryDataManager.AddItem(ctx.player, tool, math.clamp(math.floor(tonumber(reward.count) or 1), 1, 100))
	end,
})

CollectionRewards.register("recipe", {
	apply = function(reward, ctx)
		if type(reward.id) == "string" then
			ctx.collections.recipes[reward.id] = true
		end
	end,
})

-- ===================== STATE =====================
local building: { [Player]: boolean } = {} -- sync is running for this player
local again: { [Player]: boolean } = {} -- a flush arrived meanwhile
local derivedFor: { [Player]: boolean } = {} -- buffs were built at least once this session
local pendingAttr: { [Player]: any } = {} -- attribute entries waiting for the attribute profile

local function collectionsOf(data)
	local collections = data._Collections
	if type(collections) ~= "table" then
		collections = { claimed = {}, recipes = {} }
		data._Collections = collections
	end
	collections.claimed = collections.claimed or {}
	collections.recipes = collections.recipes or {}
	return collections
end

local function applyAttributes(player: Player, entries)
	pendingAttr[player] = entries
	if AttributeStatManager.IsLoaded(player) then
		pendingAttr[player] = nil
		AttributeStatManager.ApplyCollection(player, entries)
		return
	end
	task.spawn(function()
		local waited = 0
		while player.Parent and waited < ATTRIBUTE_WAIT and pendingAttr[player] == entries do
			if AttributeStatManager.IsLoaded(player) then
				pendingAttr[player] = nil
				AttributeStatManager.ApplyCollection(player, entries)
				return
			end
			waited += task.wait(0.5)
		end
	end)
end

--- Rebuild every permanent buff from the saved claimedTier table.
local function rebuild(player: Player, collections)
	local acc = { gain = {}, attr = {} }
	for skill, byStat in pairs(collections.claimed) do
		for key, claimed in pairs(byStat) do
			if Config.statConfigLookup[skill] and Config.statConfigLookup[skill][key] then
				for tier = 1, math.min(claimed, Config.TIER_COUNT) do
					for index, reward in ipairs(Config.getRewards(skill, key, tier)) do
						local spec = CollectionRewards.get(reward.type)
						if spec and spec.derive then
							spec.derive(reward, { skill = skill, key = key, tier = tier, index = index }, acc)
						end
					end
				end
			end
		end
	end
	StatisticsDataManager.SetCollectionBonus(player, acc.gain)
	applyAttributes(player, acc.attr)
	derivedFor[player] = true
end

--- Grant every tier a statistic newly reached. Returns the highest tier granted (0 if none).
local function grantTiers(player: Player, data, collections, skill: string, key: string, from: number, to: number)
	local byStat = collections.claimed[skill]
	if not byStat then
		byStat = {}
		collections.claimed[skill] = byStat
	end
	byStat[key] = to -- high-water mark first: whatever happens below, a tier is never paid twice
	for tier = from + 1, to do
		for index, reward in ipairs(Config.getRewards(skill, key, tier)) do
			local spec = CollectionRewards.get(reward.type)
			if spec and spec.apply then
				local ok, err = pcall(spec.apply, reward, {
					player = player,
					data = data,
					collections = collections,
					skill = skill,
					key = key,
					tier = tier,
					index = index,
				})
				if not ok then
					warn("[CollectionService] reward failed: " .. tostring(err))
				end
			end
		end
	end
end

function CollectionService.sync(player: Player)
	if building[player] then
		again[player] = true
		return
	end
	local data = StatisticsDataManager.GetData(player)
	if not data then
		return
	end
	building[player] = true

	local collections = collectionsOf(data)
	local unlocked = {}
	for _, skill in ipairs(Config.SKILL_NAMES) do
		local saved = data[skill]
		for _, item in ipairs(Config.STAT_CHAINS[skill] or {}) do
			local entry = saved and saved[item.key]
			local highest = CollectionMath.highestTier(entry and entry.lifetime or 0)
			local claimedTier = collections.claimed[skill] and collections.claimed[skill][item.key] or 0
			if highest > claimedTier then
				grantTiers(player, data, collections, skill, item.key, claimedTier, highest)
				table.insert(unlocked, { skill = skill, key = item.key, tier = highest, count = highest - claimedTier })
			end
		end
	end

	if #unlocked > 0 or not derivedFor[player] then
		rebuild(player, collections)
	end
	building[player] = nil

	for _, info in ipairs(unlocked) do
		TierUnlocked:FireClient(player, info)
	end
	if again[player] then
		again[player] = nil
		CollectionService.sync(player)
	end
end

--- Highest claimed tier of one statistic (for other server systems / tests).
function CollectionService.getClaimedTier(player: Player, skill: string, key: string): number
	local data = StatisticsDataManager.GetData(player)
	local claimed = data and data._Collections and data._Collections.claimed
	return claimed and claimed[skill] and claimed[skill][key] or 0
end

-- ===================== WIRING =====================
StatisticsDataManager.OnFlush(function(player)
	if player.Parent then
		CollectionService.sync(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	building[player] = nil
	again[player] = nil
	derivedFor[player] = nil
	pendingAttr[player] = nil
end)

return CollectionService
