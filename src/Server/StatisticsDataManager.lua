--[[
	StatisticsDataManager (ModuleScript)
	Place inside: ServerScriptService

	Handles:
	  - Per-skill resource stat tracking (count + lifetime)
	  - ProfileService persistence (separate PlayerStatistics_v1 store)
	  - Multiplier chain computation (higher stats boost lower stat gains)
	  - Purchase validation and cost deduction
	  - Session count tracking (in-memory, resets on join)
	  - Currency stub (temporary until CurrencyManager exists)
	  - StatisticsUpdated RemoteEvent for client sync
	  - PurchaseStat RemoteEvent for client → server purchases
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService")) :: any

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("StatisticsConfig")) :: any

local StatisticsDataManager = {}

-- ===================== REFERENCES FROM CONFIG =====================
local STAT_CHAINS = Config.STAT_CHAINS
local SKILL_NAMES = Config.SKILL_NAMES
local boostLookup = Config.boostLookup
local statConfigLookup = Config.statConfigLookup

-- ===================== PROFILE STORE =====================
local TEMPLATE = {}
for _, skill in ipairs(SKILL_NAMES) do
	TEMPLATE[skill] = {} -- { [statKey] = { count = 0, lifetime = 0 } }
end

local StatProfileStore = ProfileService.GetProfileStore("PlayerStatistics_v1", TEMPLATE)
local profiles = {} -- [userId] = profile
local sessionData = {} -- [userId] = { [skill] = { [key] = count } }

-- ===================== REMOTE EVENTS =====================
local function ensureRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local StatisticsUpdated = ensureRemote("StatisticsUpdated")
local PurchaseStat = ensureRemote("PurchaseStat")

-- ===================== DATA HELPERS =====================
local function getPlayerData(player)
	local profile = profiles[player.UserId]
	return profile and profile.Data or nil
end

local function ensureStatEntry(data, skill, statKey)
	if not data[skill] then
		data[skill] = {}
	end
	if not data[skill][statKey] then
		data[skill][statKey] = { count = 0, lifetime = 0 }
	end
end

local function getStatCount(data, skill, statKey)
	local skillData = data[skill]
	if not skillData or not skillData[statKey] then
		return 0
	end
	return skillData[statKey].count or 0
end

-- ===================== MULTIPLIER COMPUTATION =====================
--- Returns the total multiplier applied when acquiring statKey in skill.
--- Formula: 1 + Σ(sourceCount × pct / 100) for all items boosting this stat.
function StatisticsDataManager.GetMultiplier(data, skill, statKey)
	local boosts = boostLookup[skill] and boostLookup[skill][statKey]
	if not boosts then
		return 1
	end
	local total = 0
	for _, boost in ipairs(boosts) do
		local sourceCount = getStatCount(data, skill, boost.sourceKey)
		total = total + (sourceCount * boost.pct / 100)
	end
	return 1 + total
end

-- ===================== BUILD CLIENT PAYLOAD =====================
--- Builds the full payload sent to the client via StatisticsUpdated.
--- Shape: { skills = { [skill] = { [key] = { count, lifetime, session, multiplier } } }, currency = { ... } }
local function buildPayload(player)
	local data = getPlayerData(player)
	if not data then
		return nil
	end
	local userId = player.UserId
	local session = sessionData[userId] or {}

	local payload = { skills = {}, currency = {} }

	for _, skill in ipairs(SKILL_NAMES) do
		payload.skills[skill] = {}
		local chain = STAT_CHAINS[skill]
		for _, item in ipairs(chain) do
			ensureStatEntry(data, skill, item.key)
			local entry = data[skill][item.key]
			local sessSkill = session[skill] or {}
			payload.skills[skill][item.key] = {
				count = entry.count,
				lifetime = entry.lifetime,
				session = sessSkill[item.key] or 0,
				multiplier = StatisticsDataManager.GetMultiplier(data, skill, item.key),
			}
		end
	end

	return payload
end

local function fireUpdate(player)
	local payload = buildPayload(player)
	if payload then
		StatisticsUpdated:FireClient(player, payload)
	end
end

-- ===================== PURCHASE LOGIC =====================
--- Validates costs, deducts them, computes multiplied gain, increments stat.
--- Returns: success (bool), message/gainAmount
local function processPurchase(player, skillName, statKey)
	local data = getPlayerData(player)
	if not data then
		return false, "No data"
	end

	local config = statConfigLookup[skillName] and statConfigLookup[skillName][statKey]
	if not config then
		return false, "Unknown stat"
	end

	-- Block purchase of passive-only items
	if config.passive then
		return false, "Cannot purchase passive items"
	end

	local userId = player.UserId

	-- ── Validate all costs ──
	for _, costEntry in ipairs(config.cost or {}) do
		local costSkill = costEntry.skill
		local costId = costEntry.id
		if getStatCount(data, costSkill, costId) < costEntry.amount then
			return false, "Not enough " .. costId
		end
	end
	-- ── Deduct all costs ──
	for _, costEntry in ipairs(config.cost or {}) do
		local costSkill = costEntry.skill
		local costId = costEntry.id
		ensureStatEntry(data, costSkill, costId)
		data[costSkill][costId].count = data[costSkill][costId].count - costEntry.amount
	end

	-- ── Compute gain with multiplier ──
	local multiplier = StatisticsDataManager.GetMultiplier(data, skillName, statKey)
	local gain = math.max(1, math.floor(1 * multiplier))

	-- ── Add stat ──
	ensureStatEntry(data, skillName, statKey)
	data[skillName][statKey].count = data[skillName][statKey].count + gain
	data[skillName][statKey].lifetime = data[skillName][statKey].lifetime + gain

	-- ── Session tracking ──
	if not sessionData[userId] then
		sessionData[userId] = {}
	end
	if not sessionData[userId][skillName] then
		sessionData[userId][skillName] = {}
	end
	sessionData[userId][skillName][statKey] = (sessionData[userId][skillName][statKey] or 0) + gain

	fireUpdate(player)
	return true, gain
end

--- ===================== BUTTON PURCHASE (public) =====================
--- Called by ButtonServerManager for world-button purchases.
--- Unlike processPurchase(), this accepts an explicit baseGain and returns
--- cost details + owned count for the client remote payload.
---
--- Returns: success, gainAmount, costDetails, ownedAfter
---   costDetails = { { skill, id, amount, remaining }, ... }
function StatisticsDataManager.ProcessButtonPurchase(player, skill, statKey, baseGain, costEntries)
	local data = getPlayerData(player)
	if not data then
		return false, "No data", nil, nil
	end

	local userId = player.UserId

	-- ── Validate all costs ──
	for _, costEntry in ipairs(costEntries) do
		local costSkill = costEntry.skill
		local costId = costEntry.id
		if getStatCount(data, costSkill, costId) < costEntry.amount then
			return false, "Not enough " .. costId, nil, nil
		end
	end

	-- ── Deduct all costs ──
	local costDetails = {}
	for _, costEntry in ipairs(costEntries) do
		local costSkill = costEntry.skill
		local costId = costEntry.id
		ensureStatEntry(data, costSkill, costId)
		data[costSkill][costId].count = data[costSkill][costId].count - costEntry.amount
		table.insert(costDetails, {
			skill = costSkill,
			id = costId,
			amount = costEntry.amount,
			remaining = data[costSkill][costId].count,
		})
	end

	-- ── Compute gain with multiplier ──
	local multiplier = StatisticsDataManager.GetMultiplier(data, skill, statKey)
	local gain = math.max(1, math.floor(baseGain * multiplier))

	-- ── Add stat ──
	ensureStatEntry(data, skill, statKey)
	data[skill][statKey].count = data[skill][statKey].count + gain
	data[skill][statKey].lifetime = data[skill][statKey].lifetime + gain

	-- ── Session tracking ──
	if not sessionData[userId] then
		sessionData[userId] = {}
	end
	if not sessionData[userId][skill] then
		sessionData[userId][skill] = {}
	end
	sessionData[userId][skill][statKey] = (sessionData[userId][skill][statKey] or 0) + gain

	local ownedAfter = data[skill][statKey].count

	fireUpdate(player)
	return true, gain, costDetails, ownedAfter
end

-- ===================== REMOTE HANDLER =====================
PurchaseStat.OnServerEvent:Connect(function(player, skillName, statKey)
	-- Type-check inputs to prevent exploits
	if type(skillName) ~= "string" or type(statKey) ~= "string" then
		return
	end
	-- Validate skill exists
	if not STAT_CHAINS[skillName] then
		return
	end
	processPurchase(player, skillName, statKey)
end)

-- ===================== LOAD / RELEASE =====================
function StatisticsDataManager.LoadData(player)
	local profile = StatProfileStore:LoadProfileAsync("Stats_" .. player.UserId, "ForceLoad")
	if not profile then
		player:Kick("Failed to load statistics data. Please rejoin.")
		return
	end

	profile:ListenToRelease(function()
		profiles[player.UserId] = nil
		player:Kick("Statistics data loaded elsewhere. Please rejoin.")
	end)

	if not player:IsDescendantOf(Players) then
		profile:Release()
		return
	end

	profile:Reconcile()
	profiles[player.UserId] = profile

	-- Initialize session tracking
	sessionData[player.UserId] = {}

	-- Ensure all stat entries exist in profile data
	for _, skill in ipairs(SKILL_NAMES) do
		if not profile.Data[skill] then
			profile.Data[skill] = {}
		end
		for _, item in ipairs(STAT_CHAINS[skill]) do
			ensureStatEntry(profile.Data, skill, item.key)
		end
	end

	fireUpdate(player)
	return profile.Data
end

function StatisticsDataManager.ReleaseData(player)
	local profile = profiles[player.UserId]
	if profile then
		profile:Release()
	end
	profiles[player.UserId] = nil
	sessionData[player.UserId] = nil
end

-- ===================== MANUAL SAVE =====================
function StatisticsDataManager.Save(player)
	local profile = profiles[player.UserId]
	if profile then
		profile:Save()
	end
end

-- ===================== PUBLIC GETTERS =====================
function StatisticsDataManager.GetData(player)
	return getPlayerData(player)
end

-- ===================== PASSIVE INCOME =====================
local PASSIVE_INTERVAL = 1 -- seconds between ticks
local PASSIVE_GRANTS = {
	{ skill = "General", statKey = "BronzeCoins", amount = 10 },
}

task.spawn(function()
	while true do
		task.wait(PASSIVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = StatisticsDataManager.GetData(player)
			if not data then
				continue
			end
			local userId = player.UserId

			for _, grant in ipairs(PASSIVE_GRANTS) do
				local skill = grant.skill
				local statKey = grant.statKey
				local baseAmount = grant.amount

				-- Ensure entry exists
				if not data[skill] then
					data[skill] = {}
				end
				if not data[skill][statKey] then
					data[skill][statKey] = { count = 0, lifetime = 0 }
				end

				-- Apply multiplier from items that boost this stat
				local multiplier = StatisticsDataManager.GetMultiplier(data, skill, statKey)
				local amount = math.floor(baseAmount * multiplier)

				data[skill][statKey].count = data[skill][statKey].count + amount
				data[skill][statKey].lifetime = data[skill][statKey].lifetime + amount

				-- Session tracking
				if not sessionData[userId] then
					sessionData[userId] = {}
				end
				if not sessionData[userId][skill] then
					sessionData[userId][skill] = {}
				end
				sessionData[userId][skill][statKey] = (sessionData[userId][skill][statKey] or 0) + amount
			end

			fireUpdate(player)
		end
	end
end)

-- ===================== PLAYER CONNECTIONS =====================
Players.PlayerAdded:Connect(function(player)
	StatisticsDataManager.LoadData(player)
end)

Players.PlayerRemoving:Connect(function(player)
	StatisticsDataManager.ReleaseData(player)
end)

-- Handle players already in game (Studio testing)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		StatisticsDataManager.LoadData(player)
	end)
end

print("StatisticsDataManager: Ready ✓")
return StatisticsDataManager
