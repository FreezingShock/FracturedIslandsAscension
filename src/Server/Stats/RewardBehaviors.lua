--[[
	RewardBehaviors (ModuleScript, Server)
	Place inside: ServerScriptService

	What each CollectionRewards type DOES on the server. Shared by CollectionService (collection tiers) and
	SkillRewardService (skill levels): require it once and the registry gets derive/apply for every built-in type.

	derive(reward, ctx, acc)  permanent buffs, rebuilt from the saved high-water mark every time (never saved themselves)
	apply(reward, ctx)        one-time grants, run exactly once when the tier / level is first reached

	ctx for derive = { where = "text for warnings", id = "unique id base", label = "boost label", skill?, key?, index }
	ctx for apply  = { player, recipes = {...}, unlocks = {...}, where }
	acc = { gain = { [skill] = { [statKey] = pct } }, attr = { entries for AttributeStatManager.ApplySource } }
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("CollectionsConfig")) :: any
local CollectionRewards = require(Modules:WaitForChild("CollectionRewards")) :: any
local Attributes = require(Modules:WaitForChild("Attributes")) :: any
local StatisticsDataManager = require(ServerScriptService:WaitForChild("StatisticsDataManager")) :: any

local RewardBehaviors = {}

local function finiteNumber(value: any): number?
	if type(value) == "number" and value == value and value > -1e9 and value < 1e9 then
		return value
	end
	return nil
end

local function gainDerive(reward, ctx, acc)
	local spec = CollectionRewards.get(reward.type)
	local skill, key = spec.target(reward, ctx)
	local pct = finiteNumber(reward.pct)
	if not (pct and skill and key and Config.statConfigLookup[skill] and Config.statConfigLookup[skill][key]) then
		warn("[RewardBehaviors] bad " .. reward.type .. " reward: " .. tostring(ctx.where))
		return
	end
	acc.gain[skill] = acc.gain[skill] or {}
	acc.gain[skill][key] = (acc.gain[skill][key] or 0) + pct
end

CollectionRewards.register("statGain", { derive = gainDerive })
CollectionRewards.register("crossStatGain", { derive = gainDerive })

CollectionRewards.register("gameStat", {
	derive = function(reward, ctx, acc)
		local def = Attributes.get(reward.attr)
		local entry = {
			id = string.format("%s.%d", ctx.id, ctx.index),
			label = ctx.label,
			-- the source the boost came from (statistic / skill) when given, else the attribute itself
			color = ctx.color or (def and def.color) or "#55FFFF",
			icon = ctx.icon or (def and def.icon),
			group = ctx.group, -- boosts with the same group stack into one breakdown slot
			groupLabel = ctx.groupLabel,
			attr = reward.attr,
		}
		if finiteNumber(reward.flat) then
			entry.flat = reward.flat
		elseif finiteNumber(reward.pct) then
			entry.mult = 1 + reward.pct / 100
		else
			warn("[RewardBehaviors] gameStat reward needs flat or pct: " .. tostring(ctx.where))
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
					"[RewardBehaviors] item reward stub: no tool '"
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
			ctx.recipes[reward.id] = true
		end
	end,
})

CollectionRewards.register("unlock", {
	apply = function(reward, ctx)
		if type(reward.id) == "string" then
			ctx.unlocks[reward.id] = true
		end
	end,
})

CollectionRewards.register("statGrant", {
	apply = function(reward, ctx)
		local amount = finiteNumber(reward.amount)
		if
			not (
				amount
				and amount > 0
				and Config.statConfigLookup[reward.skill]
				and Config.statConfigLookup[reward.skill][reward.key]
			)
		then
			warn("[RewardBehaviors] bad statGrant reward: " .. tostring(ctx.where))
			return
		end
		StatisticsDataManager.GrantStat(ctx.player, reward.skill, reward.key, amount)
	end,
})

return RewardBehaviors
