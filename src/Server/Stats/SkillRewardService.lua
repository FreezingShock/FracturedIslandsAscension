--[[
	SkillRewardService (ModuleScript, Server)
	Place inside: ServerScriptService

	Server-authoritative skill level rewards, the sibling of CollectionService. The client never asks for anything.

	  1. After every SkillsDataManager change (and when a profile loads) sync(player) compares each skill's level with the
	     saved claimed level ([profile]._Rewards.claimed[skill]), a high-water mark.
	  2. A higher level moves claimed UP FIRST, then runs the "grant" rewards (coins, items, recipes, unlocks) of every newly
	     reached level once, in order. Levels reached offline, by a jump or before this system existed are all granted.
	  3. Permanent buffs ("derived" rewards) are rebuilt from the whole claimed table every time it changes, so lowering a
	     level with SetLevel, a rejoin or a restore can never double them or take back a paid reward:
	       statGain / crossStatGain -> StatisticsDataManager.SetGainBonus(player, "skill", ...)
	       gameStat                 -> AttributeStatManager.ApplySource(player, "skill:", ...)  (source type "skill")
	  4. SkillLevelUp (RemoteEvent, server -> client) carries { skill, level, count } for the toast.

	What a reward type does is in RewardBehaviors; which rewards a level has is SkillsConfig.getRewards.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SkillsConfig = require(Modules:WaitForChild("SkillsConfig")) :: any
local CollectionRewards = require(Modules:WaitForChild("CollectionRewards")) :: any
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
local StatisticsDataManager = require(ServerScriptService:WaitForChild("StatisticsDataManager")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
require(ServerScriptService:WaitForChild("RewardBehaviors")) -- registers derive/apply on the shared reward types

local SkillRewardService = {}

local ATTRIBUTE_WAIT = 60 -- seconds to wait for the attribute profile before giving up

local LevelUp = ReplicatedStorage:FindFirstChild("SkillLevelUp")
if not LevelUp then
	LevelUp = Instance.new("RemoteEvent")
	LevelUp.Name = "SkillLevelUp"
	LevelUp.Parent = ReplicatedStorage
end

local building: { [Player]: boolean } = {}
local again: { [Player]: boolean } = {}
local derivedFor: { [Player]: boolean } = {}
local pendingAttr: { [Player]: any } = {}

local function rewardsOf(data)
	local rewards = data._Rewards
	if type(rewards) ~= "table" then
		rewards = {}
		data._Rewards = rewards
	end
	rewards.claimed = rewards.claimed or {}
	rewards.recipes = rewards.recipes or {}
	rewards.unlocks = rewards.unlocks or {}
	return rewards
end

local function applyAttributes(player: Player, entries)
	pendingAttr[player] = entries
	local function apply()
		pendingAttr[player] = nil
		AttributeStatManager.ApplySource(player, "skill:", entries, "skill")
		SkillsDataManager.MarkDirty(player) -- the wisdom shown on the page may have changed
	end
	if AttributeStatManager.IsLoaded(player) then
		apply()
		return
	end
	task.spawn(function()
		local waited = 0
		while player.Parent and waited < ATTRIBUTE_WAIT and pendingAttr[player] == entries do
			if AttributeStatManager.IsLoaded(player) then
				apply()
				return
			end
			waited += task.wait(0.5)
		end
	end)
end

--- Rebuild every permanent buff from the saved claimed levels.
local function rebuild(player: Player, rewards)
	local acc = { gain = {}, attr = {} }
	for skill, claimed in pairs(rewards.claimed) do
		local config = SkillsConfig.skills[skill]
		if config then
			for level = 1, math.min(claimed, config.cap) do
				for index, reward in ipairs(SkillsConfig.getRewards(skill, level)) do
					local spec = CollectionRewards.get(reward.type)
					if spec and spec.derive then
						spec.derive(reward, {
							skill = skill,
							level = level,
							index = index,
							where = string.format("%s level %d", skill, level),
							id = string.format("%s.%d", skill, level),
							label = string.format("%s level %s", config.name, SkillsConfig.roman(level)),
							color = config.color,
						}, acc)
					end
				end
			end
		end
	end
	StatisticsDataManager.SetGainBonus(player, "skill", acc.gain)
	applyAttributes(player, acc.attr)
	derivedFor[player] = true
end

local function grantLevels(player: Player, data, rewards, skill: string, from: number, to: number)
	rewards.claimed[skill] = to -- high-water mark first: a level is never paid twice
	for level = from + 1, to do
		for index, reward in ipairs(SkillsConfig.getRewards(skill, level)) do
			local spec = CollectionRewards.get(reward.type)
			if spec and spec.apply then
				local ok, err = pcall(spec.apply, reward, {
					player = player,
					data = data,
					recipes = rewards.recipes,
					unlocks = rewards.unlocks,
					where = string.format("%s level %d", skill, level),
					index = index,
				})
				if not ok then
					warn("[SkillRewardService] reward failed: " .. tostring(err))
				end
			end
		end
	end
end

function SkillRewardService.sync(player: Player)
	if building[player] then
		again[player] = true
		return
	end
	local data = SkillsDataManager.GetData(player)
	if not data then
		return
	end
	building[player] = true

	local rewards = rewardsOf(data)
	local reached = {}
	for _, skill in ipairs(SkillsConfig.ORDER) do
		local level = data[skill] and data[skill].level or 1
		local claimed = rewards.claimed[skill] or 0
		if level > claimed then
			grantLevels(player, data, rewards, skill, claimed, level)
			if not (claimed == 0 and level == 1) then -- a brand-new character does not get six toasts
				table.insert(reached, { skill = skill, level = level, count = level - claimed })
			end
		end
	end

	if #reached > 0 or not derivedFor[player] then
		rebuild(player, rewards)
	end
	building[player] = nil

	for _, info in ipairs(reached) do
		LevelUp:FireClient(player, info)
	end
	if again[player] then
		again[player] = nil
		SkillRewardService.sync(player)
	end
end

--- Highest paid level of a skill (for other server systems / tests).
function SkillRewardService.getClaimedLevel(player: Player, skill: string): number
	local data = SkillsDataManager.GetData(player)
	local claimed = data and data._Rewards and data._Rewards.claimed
	return claimed and claimed[skill] or 0
end

SkillsDataManager.OnChanged(function(player)
	if player.Parent then
		SkillRewardService.sync(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	building[player] = nil
	again[player] = nil
	derivedFor[player] = nil
	pendingAttr[player] = nil
end)

return SkillRewardService
