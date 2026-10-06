--[[
	StatisticsDataManager (ModuleScript)
	Place inside: ServerScriptService

	Handles:
	  - Per-skill resource stat tracking (count + lifetime)
	  - ProfileService persistence (separate PlayerStatistics_v1 store)
	  - Multiplier computation (owning a stat boosts the stats it rewards)
	  - World-button purchases (ProcessButtonPurchase) - the ONLY way to buy a stat
	  - Passive income (stats flagged `passive` in StatisticsConfig)
	  - Session counts (in-memory, reset on join)
	  - StatisticsUpdated RemoteEvent: coalesced, sparse snapshots for the client

	There is deliberately no client -> server "purchase" remote: stats are earned
	by stepping on world buttons (ButtonServerManager) or passively, never by
	clicking a menu slot.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

-- How often a changed player is sent a fresh snapshot (seconds). Many purchases
-- or passive ticks inside this window collapse into one remote call.
local UPDATE_INTERVAL = 0.1
local PASSIVE_INTERVAL = 1

-- The economy is exponential; a double overflows to inf at ~1.8e308 and inf/NaN cannot be stored in a
-- DataStore (the profile would fail to save). Every stat is clamped below that.
local STAT_CAP = 1e300

local function finite(n: any): number
	if type(n) ~= "number" or n ~= n then
		return 0
	end
	return math.clamp(n, -STAT_CAP, STAT_CAP)
end

-- ===================== PROFILE STORE =====================
local TEMPLATE = {}
for _, skill in ipairs(SKILL_NAMES) do
	TEMPLATE[skill] = {} -- { [statKey] = { count = 0, lifetime = 0 } }
end

-- Collections (CollectionService): claimed[skill][statKey] = highest tier already paid out (a high-water mark),
-- recipes[id] = true for recipe rewards. Reconcile() backfills it for existing players.
TEMPLATE._Collections = { claimed = {}, recipes = {} }

local StatProfileStore = ProfileService.GetProfileStore("PlayerStatistics_v1", TEMPLATE)
local profiles = {} -- [userId] = profile
local sessionData = {} -- [userId] = { [skill] = { [key] = gained this session } }
local dirty = {} -- [Player] = true when a snapshot is owed
local adminSnapshot = {} -- [userId] = { [skill] = { [key] = { count, lifetime } } } (admin panel undo)
-- Permanent gain bonuses derived by CollectionService from the claimed tiers: [profile.Data] = { [skill] = { [key] = pct } }.
-- Never saved and never added into the owned counts, so a restore or clamp cannot make them stack.
local collectionBonus = setmetatable({}, { __mode = "k" })
local flushListeners = {} -- fn(player), called after every snapshot flush (CollectionService re-derives from it)

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

-- ===================== DATA HELPERS =====================
local function getPlayerData(player)
	local profile = profiles[player.UserId]
	return profile and profile.Data or nil
end

local function ensureStatEntry(data, skill, statKey)
	local skillData = data[skill]
	if not skillData then
		skillData = {}
		data[skill] = skillData
	end
	local entry = skillData[statKey]
	if not entry then
		entry = { count = 0, lifetime = 0 }
		skillData[statKey] = entry
	end
	return entry
end

local function getStatCount(data, skill, statKey)
	local skillData = data[skill]
	local entry = skillData and skillData[statKey]
	return entry and entry.count or 0
end

--- Adds `amount` to a stat's count + lifetime + this session's tally.
local function addStat(userId, data, skill, statKey, amount)
	amount = finite(amount)
	local entry = ensureStatEntry(data, skill, statKey)
	entry.count = finite(entry.count + amount)
	entry.lifetime = finite(entry.lifetime + amount)

	local session = sessionData[userId]
	if not session then
		session = {}
		sessionData[userId] = session
	end
	local skillSession = session[skill]
	if not skillSession then
		skillSession = {}
		session[skill] = skillSession
	end
	skillSession[statKey] = finite((skillSession[statKey] or 0) + amount)
end

-- ===================== MULTIPLIERS =====================
--- Multiplier applied when acquiring statKey in skill:
---   1 + sum(sourceOwned * pct / 100) over every stat (any skill) that rewards it.
function StatisticsDataManager.GetMultiplier(data, skill, statKey)
	local total = 0
	local boosts = boostLookup[skill] and boostLookup[skill][statKey]
	if boosts then
		for _, boost in ipairs(boosts) do
			total += getStatCount(data, boost.sourceSkill, boost.sourceKey) * boost.pct / 100
		end
	end
	local bonus = collectionBonus[data]
	local pct = bonus and bonus[skill] and bonus[skill][statKey]
	if pct then
		total += pct / 100
	end
	return 1 + finite(total)
end

--- CollectionService: replace the derived collection gain bonuses ({ [skill] = { [key] = pct } }).
function StatisticsDataManager.SetCollectionBonus(player, bonus)
	local data = getPlayerData(player)
	if data then
		collectionBonus[data] = bonus
		dirty[player] = true
	end
end

--- Register fn(player), called after each snapshot flush (and when a profile finishes loading).
function StatisticsDataManager.OnFlush(fn)
	table.insert(flushListeners, fn)
end

-- ===================== CLIENT SYNC =====================
--- Snapshot for the client:
---   { skills = { [skill] = { [key] = { count, lifetime, session, multiplier } } } }
--- SPARSE: a stat the player has never touched (and nothing boosts) is left out.
--- Clients treat a missing entry as zero owned / x1 multiplier.
local function buildPayload(player)
	local data = getPlayerData(player)
	if not data then
		return nil
	end
	local session = sessionData[player.UserId] or {}

	local skills = {}
	for _, skill in ipairs(SKILL_NAMES) do
		local out = {}
		local saved = data[skill] or {}
		local skillSession = session[skill]
		for _, item in ipairs(STAT_CHAINS[skill]) do
			local key = item.key
			local entry = saved[key]
			local count = entry and entry.count or 0
			local lifetime = entry and entry.lifetime or 0
			local multiplier = StatisticsDataManager.GetMultiplier(data, skill, key)
			if count ~= 0 or lifetime ~= 0 or multiplier ~= 1 then
				out[key] = {
					count = count,
					lifetime = lifetime,
					session = skillSession and skillSession[key] or 0,
					multiplier = multiplier,
				}
			end
		end
		skills[skill] = out
	end
	return { skills = skills }
end

local function markDirty(player)
	dirty[player] = true
end

local function flush(player)
	dirty[player] = nil
	local payload = buildPayload(player)
	if payload then
		StatisticsUpdated:FireClient(player, payload)
	end
	for _, fn in ipairs(flushListeners) do
		task.spawn(fn, player)
	end
end

do
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		for player in pairs(dirty) do
			if player.Parent then
				flush(player)
			else
				dirty[player] = nil
			end
		end
	end)
end

-- ===================== BUTTON PURCHASE (public) =====================
--- Called by ButtonServerManager for world-button purchases.
--- Returns: success, gainAmount, costDetails, ownedAfter
---   costDetails = { { skill, id, amount, remaining }, ... }
function StatisticsDataManager.ProcessButtonPurchase(player, skill, statKey, baseGain, costEntries)
	local data = getPlayerData(player)
	if not data then
		return false, "No data", nil, nil
	end

	local config = statConfigLookup[skill] and statConfigLookup[skill][statKey]
	if not config then
		return false, "Unknown stat", nil, nil
	end
	if config.passive then
		return false, "Passive stats cannot be purchased", nil, nil
	end

	-- Validate every cost before touching anything.
	for _, costEntry in ipairs(costEntries) do
		if getStatCount(data, costEntry.skill, costEntry.id) < costEntry.amount then
			return false, "Not enough " .. costEntry.id, nil, nil
		end
	end

	local costDetails = {}
	for _, costEntry in ipairs(costEntries) do
		local entry = ensureStatEntry(data, costEntry.skill, costEntry.id)
		entry.count = finite(entry.count - costEntry.amount)
		table.insert(costDetails, {
			skill = costEntry.skill,
			id = costEntry.id,
			amount = costEntry.amount,
			remaining = entry.count,
		})
	end

	local multiplier = StatisticsDataManager.GetMultiplier(data, skill, statKey)
	local gain = math.max(1, math.floor(finite(baseGain * multiplier)))
	addStat(player.UserId, data, skill, statKey, gain)

	markDirty(player)
	return true, gain, costDetails, data[skill][statKey].count
end

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
	sessionData[player.UserId] = {}

	-- Make sure every configured stat has an entry (new stats appear on old saves) and repair any
	-- non-finite value a previous version may have saved.
	for _, skill in ipairs(SKILL_NAMES) do
		for _, item in ipairs(STAT_CHAINS[skill]) do
			local entry = ensureStatEntry(profile.Data, skill, item.key)
			entry.count = finite(entry.count)
			entry.lifetime = finite(entry.lifetime)
		end
	end

	flush(player)
	return profile.Data
end

function StatisticsDataManager.ReleaseData(player)
	local profile = profiles[player.UserId]
	if profile then
		profile:Release()
	end
	profiles[player.UserId] = nil
	sessionData[player.UserId] = nil
	dirty[player] = nil
	adminSnapshot[player.UserId] = nil
end

function StatisticsDataManager.Save(player)
	local profile = profiles[player.UserId]
	if profile then
		profile:Save()
	end
end

function StatisticsDataManager.GetData(player)
	return getPlayerData(player)
end

-- ===================== ADMIN (admin panel) =====================
-- Admin edits write to the real profile, so the first edit of a session snapshots
-- every count/lifetime and AdminRestore puts them back. The caller (the admin
-- remote) has already checked the player is an admin.
local function snapshotOnce(player, data)
	if adminSnapshot[player.UserId] then
		return
	end
	local snap = {}
	for _, skill in ipairs(SKILL_NAMES) do
		snap[skill] = {}
		for key, entry in pairs(data[skill] or {}) do
			snap[skill][key] = { count = entry.count, lifetime = entry.lifetime }
		end
	end
	adminSnapshot[player.UserId] = snap
end

--- Set one stat's owned count. Returns ok, reason.
function StatisticsDataManager.AdminSetCount(player, skill, statKey, count)
	local data = getPlayerData(player)
	if not data then
		return false, "No data"
	end
	if not (statConfigLookup[skill] and statConfigLookup[skill][statKey]) then
		return false, "Unknown stat"
	end
	snapshotOnce(player, data)
	local entry = ensureStatEntry(data, skill, statKey)
	entry.count = finite(count)
	entry.lifetime = math.max(entry.lifetime, entry.count)
	markDirty(player)
	return true
end

--- Set every statistic to `count`.
function StatisticsDataManager.AdminSetAll(player, count)
	local data = getPlayerData(player)
	if not data then
		return false, "No data"
	end
	snapshotOnce(player, data)
	for _, skill in ipairs(SKILL_NAMES) do
		for _, item in ipairs(STAT_CHAINS[skill]) do
			local entry = ensureStatEntry(data, skill, item.key)
			entry.count = count
			entry.lifetime = math.max(entry.lifetime, count)
		end
	end
	markDirty(player)
	return true
end

--- Undo every admin edit this session. Returns ok, reason.
function StatisticsDataManager.AdminRestore(player)
	local data = getPlayerData(player)
	local snap = adminSnapshot[player.UserId]
	if not data then
		return false, "No data"
	end
	if not snap then
		return false, "Nothing to restore"
	end
	for _, skill in ipairs(SKILL_NAMES) do
		for _, item in ipairs(STAT_CHAINS[skill]) do
			local entry = ensureStatEntry(data, skill, item.key)
			local saved = snap[skill][item.key]
			entry.count = saved and saved.count or 0
			entry.lifetime = saved and saved.lifetime or 0
		end
	end
	adminSnapshot[player.UserId] = nil
	markDirty(player)
	return true
end

-- ===================== PASSIVE INCOME =====================
-- Built from the config: any stat with `passive = true` and `passiveGain`.
local PASSIVE_GRANTS = {}
for _, skill in ipairs(SKILL_NAMES) do
	for _, item in ipairs(STAT_CHAINS[skill]) do
		if item.passive and item.passiveGain then
			table.insert(PASSIVE_GRANTS, { skill = skill, statKey = item.key, amount = item.passiveGain })
		end
	end
end

task.spawn(function()
	while true do
		task.wait(PASSIVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = getPlayerData(player)
			if not data then
				continue
			end
			for _, grant in ipairs(PASSIVE_GRANTS) do
				local multiplier = StatisticsDataManager.GetMultiplier(data, grant.skill, grant.statKey)
				addStat(player.UserId, data, grant.skill, grant.statKey, math.floor(finite(grant.amount * multiplier)))
			end
			markDirty(player)
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
