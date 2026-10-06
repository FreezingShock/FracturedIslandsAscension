--[[
	AttributeStatManager (ModuleScript)
	Place inside: ServerScriptService

	Handles:
	  - Loading base stats from ProfileConfig
	  - Storing computed attributes in ProfileService (PlayerAttributes_v1)
	  - Building flat boosts (equipment, milestones)
	  - Building multiplier boosts (accessories)
	  - Computing final values: (base + flat) × (1 + mult)
	  - Firing StatUpdated RemoteEvent to clients with full breakdown
	  - RequestStats RemoteFunction for client initial data requests
	  - EQUIPPED ITEMS: ApplyEquipment() rebuilds the armor/accessory boosts
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService")) :: any

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ProfileConfig = require(Modules:WaitForChild("ProfileConfig")) :: any

local AttributeStatManager = {}

--- Fired (server side) with the player whenever their final stats may have changed (the same moments StatUpdated is
--- sent to the client). ResourceService listens to resize max health / mana / stamina.
AttributeStatManager.Changed = Instance.new("BindableEvent")

-- ===================== REFERENCES =====================
local BASE_STATS = ProfileConfig.BASE_STATS
local ATTRIBUTE_CATEGORIES = ProfileConfig.ATTRIBUTE_CATEGORIES

-- ===================== PROFILE STORE =====================
-- Template: mirrors SkillsDataManager pattern
-- Structure: { [attrKey] = { flatBoosts = { {label, value, color?} }, multipliers = { {label, value, color?} } } }
-- Stores sources of boosts for display in client tooltips (breakdown panel).
-- The computed final values are sent via StatUpdated event (not stored).

local TEMPLATE = {}
for skill, attrs in pairs(ATTRIBUTE_CATEGORIES) do
	for _, attr in ipairs(attrs) do
		TEMPLATE[attr.key] = {
			flatBoosts = {}, -- array of { label = "...", value = number, color? = "#HEX" }
			multipliers = {}, -- array of { label = "...", value = number, color? = "#HEX" }
		}
	end
end

local AttributeProfileStore = ProfileService.GetProfileStore("PlayerAttributes_v1", TEMPLATE)
local attributeProfiles = {} -- [userId] = profile

-- ===================== REMOTE EVENTS & FUNCTIONS =====================
local function ensureRemote(name, remoteType)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new(remoteType)
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local StatUpdated = ReplicatedStorage:FindFirstChild("StatUpdated")
if StatUpdated and StatUpdated.ClassName ~= "RemoteEvent" then
	StatUpdated:Destroy()
	StatUpdated = nil
end
if not StatUpdated then
	StatUpdated = Instance.new("RemoteEvent")
	StatUpdated.Name = "StatUpdated"
	StatUpdated.Parent = ReplicatedStorage
end

local RequestStats = ReplicatedStorage:FindFirstChild("RequestStats")
if RequestStats and RequestStats.ClassName ~= "RemoteFunction" then
	RequestStats:Destroy()
	RequestStats = nil
end
if not RequestStats then
	RequestStats = Instance.new("RemoteFunction")
	RequestStats.Name = "RequestStats"
	RequestStats.Parent = ReplicatedStorage
end

-- ===================== DATA HELPERS =====================
local function getAttributeProfile(player)
	return attributeProfiles[player.UserId]
end

local function getAttributeData(player)
	local profile = getAttributeProfile(player)
	return profile and profile.Data or nil
end

-- ===================== STAT COMPUTATION =====================
--- Compute the final value of an attribute.
--- Formula: (baseValue + sum(flatBoosts)) × (1 + sum(multiplier - 1))
--- flatBoosts: array of { value = number }
--- multipliers: array of { value = number } (1 = no change, 1.5 = +50%)
local function computeFinalValue(baseValue, flatBoosts, multipliers)
	local flatTotal = 0
	for _, boost in ipairs(flatBoosts or {}) do
		flatTotal = flatTotal + (tonumber(boost.value) or 0)
	end

	local multBonus = 0
	for _, mult in ipairs(multipliers or {}) do
		multBonus = multBonus + ((tonumber(mult.value) or 1) - 1)
	end

	return (baseValue + flatTotal) * (1 + multBonus)
end

--- Build the full breakdown for a single attribute.
--- Returns: { flatBoosts = {...}, multipliers = {...}, baseValue = number, finalValue = number }
local function buildAttributeBreakdown(attrKey, baseValue, cachedData)
	local entry = cachedData and cachedData[attrKey] or {}
	local flatBoosts = entry.flatBoosts or {}
	local multipliers = entry.multipliers or {}

	local finalValue = computeFinalValue(baseValue, flatBoosts, multipliers)

	return {
		flatBoosts = flatBoosts,
		multipliers = multipliers,
		baseValue = baseValue,
		finalValue = finalValue,
	}
end

--- Build the full payload sent via StatUpdated.
--- Returns: { [attrKey] = { base, final, flatBoosts, multipliers } }
local function buildStatPayload(player)
	local data = getAttributeData(player)
	if not data then
		return nil
	end

	local payload = {}

	-- Iterate all attributes and compute final values
	for skill, attrs in pairs(ATTRIBUTE_CATEGORIES) do
		for _, attr in ipairs(attrs) do
			local attrKey = attr.key
			local baseValue = BASE_STATS[attrKey] or 0
			local breakdown = buildAttributeBreakdown(attrKey, baseValue, data)

			payload[attrKey] = {
				base = breakdown.baseValue,
				final = breakdown.finalValue,
				flatBoosts = breakdown.flatBoosts,
				multipliers = breakdown.multipliers,
			}
		end
	end

	return payload
end

local function fireStatUpdate(player)
	local payload = buildStatPayload(player)
	if payload then
		StatUpdated:FireClient(player, payload)
		AttributeStatManager.Changed:Fire(player)
	end
end

-- ===================== PLACEHOLDER BUILDERS =====================
--- Apply flat boosts from equipment, milestones, etc.
--- PLACEHOLDER: currently empty. Wire in EquipmentConfig later.
local function applyFlatBoosts(data, player)
	-- TODO: Fetch equipped items from InventorySystem
	-- For each item: data[attrKey].flatBoosts += { label = itemName, value = amount }
	-- Example placeholder:
	-- data["Health"].flatBoosts = { { label = "Starter Helmet", value = 20 } }
end

--- Apply multiplier boosts from accessories.
--- PLACEHOLDER: currently empty. Wire in EquippedAccessories later.
local function applyMultiplierBoosts(data, player)
	-- TODO: Fetch equipped accessories from EquippedAccessories
	-- For each accessory: data[attrKey].multipliers += { label = accessoryName, value = 1.15 }
	-- Example placeholder:
	-- data["CritChance"].multipliers = { { label = "Ring of Accuracy", value = 1.10 } }
end

local tempBonuses = {} -- [userId] = { [bonusId] = { id, attr, mode, amount, expiresAt } } (admin panel)

-- Debug boosts ("admin" from /set, "admin:<n>" from the admin panel) and session boosts ("session:<name>", e.g. sprint)
-- never persist: they are stripped when a profile loads, so a crash mid-boost cannot leave one behind.
local function isAdminBoost(boost)
	return boost.id == "admin"
		or (type(boost.id) == "string" and (boost.id:sub(1, 6) == "admin:" or boost.id:sub(1, 8) == "session:"))
end

local function stripAdminFrom(list)
	local kept = {}
	for _, boost in ipairs(list or {}) do
		if not isAdminBoost(boost) then
			table.insert(kept, boost)
		end
	end
	return kept
end

-- ===================== LOAD / RELEASE =====================
local sanitizeAttributeData -- defined below (was an accidental global)

function AttributeStatManager.LoadData(player)
	local profile = AttributeProfileStore:LoadProfileAsync("Attributes_" .. player.UserId, "ForceLoad")

	if profile == nil then
		player:Kick("Failed to load attribute data. Please rejoin.")
		return
	end

	profile:ListenToRelease(function()
		attributeProfiles[player.UserId] = nil
		player:Kick("Attribute data was loaded elsewhere. Please rejoin.")
	end)

	if not player:IsDescendantOf(Players) then
		profile:Release()
		return
	end

	profile:Reconcile()
	sanitizeAttributeData(profile.Data)
	for _, entry in pairs(profile.Data) do
		if type(entry) == "table" then
			entry.flatBoosts = stripAdminFrom(entry.flatBoosts)
			entry.multipliers = stripAdminFrom(entry.multipliers)
		end
	end
	attributeProfiles[player.UserId] = profile

	-- Send initial stats to client
	fireStatUpdate(player)

	return profile.Data
end

function AttributeStatManager.ReleaseData(player)
	local profile = getAttributeProfile(player)
	if profile then
		profile:Release()
	end
	attributeProfiles[player.UserId] = nil
	tempBonuses[player.UserId] = nil
end

-- ===================== SANITIZE =====================
--- Ensure all attribute keys exist with proper structure.
sanitizeAttributeData = function(data)
	for skill, attrs in pairs(ATTRIBUTE_CATEGORIES) do
		for _, attr in ipairs(attrs) do
			local attrKey = attr.key
			if type(data[attrKey]) ~= "table" then
				data[attrKey] = { flatBoosts = {}, multipliers = {} }
			else
				if type(data[attrKey].flatBoosts) ~= "table" then
					data[attrKey].flatBoosts = {}
				end
				if type(data[attrKey].multipliers) ~= "table" then
					data[attrKey].multipliers = {}
				end
			end
		end
	end
end

-- ===================== PUBLIC API =====================

--- Get the final computed value of an attribute.
function AttributeStatManager.GetFinalValue(player, attrKey)
	local data = getAttributeData(player)
	if not data or not data[attrKey] then
		return BASE_STATS[attrKey] or 0
	end

	local baseValue = BASE_STATS[attrKey] or 0
	local breakdown = buildAttributeBreakdown(attrKey, baseValue, data)
	return breakdown.finalValue
end

--- Get the full breakdown (base, flatBoosts, multipliers, final) for an attribute.
function AttributeStatManager.GetAttributeBreakdown(player, attrKey)
	local data = getAttributeData(player)
	if not data then
		return nil
	end

	local baseValue = BASE_STATS[attrKey] or 0
	return buildAttributeBreakdown(attrKey, baseValue, data)
end

--- Manually add a flat boost to an attribute (for milestone rewards, equipment changes, etc.)
--- EXAMPLE: AddFlatBoost(player, "Health", "Starter Helmet", 20, "#FF5555")
function AttributeStatManager.AddFlatBoost(player, attrKey, label, amount, color, id)
	local data = getAttributeData(player)
	if not data or not data[attrKey] then
		return false
	end

	table.insert(data[attrKey].flatBoosts, {
		id = id or "generic",
		label = label,
		value = amount,
		color = color,
	})

	fireStatUpdate(player)
	return true
end

--- Manually add a multiplier boost to an attribute (for accessories, etc.)
--- EXAMPLE: AddMultiplierBoost(player, "CritChance", "Ring of Accuracy", 1.10, "#5555FF")
function AttributeStatManager.AddMultiplierBoost(player, attrKey, label, multiplier, color, id)
	local data = getAttributeData(player)
	if not data or not data[attrKey] then
		return false
	end

	table.insert(data[attrKey].multipliers, {
		id = id or "generic",
		label = label,
		value = multiplier,
		color = color,
	})

	fireStatUpdate(player)
	return true
end

--- Clear all flat boosts for an attribute (useful for unequipping items).
function AttributeStatManager.ClearFlatBoosts(player, attrKey, slotId)
	local data = getAttributeData(player)
	if not data or not data[attrKey] then
		return false
	end

	if slotId == nil or slotId == "all" then
		data[attrKey].flatBoosts = {}
	else
		-- Remove only boosts matching this slotId
		local filtered = {}
		for _, boost in ipairs(data[attrKey].flatBoosts) do
			if boost.id ~= slotId then
				table.insert(filtered, boost)
			end
		end
		data[attrKey].flatBoosts = filtered
	end

	fireStatUpdate(player)
	return true
end

--- Clear all multiplier boosts for an attribute (useful for removing accessories).
function AttributeStatManager.ClearMultiplierBoosts(player, attrKey, slotId)
	local data = getAttributeData(player)
	if not data or not data[attrKey] then
		return false
	end

	if slotId == nil or slotId == "all" then
		data[attrKey].multipliers = {}
	else
		-- Remove only boosts matching this slotId
		local filtered = {}
		for _, mult in ipairs(data[attrKey].multipliers) do
			if mult.id ~= slotId then
				table.insert(filtered, mult)
			end
		end
		data[attrKey].multipliers = filtered
	end

	fireStatUpdate(player)
	return true
end

--- Manually save (for explicit checkpoints; auto-save via profile:Save() is built-in).
function AttributeStatManager.Save(player)
	local profile = getAttributeProfile(player)
	if profile then
		profile:Save()
	end
end

--- Trigger a stat update without changing data (refreshes client display).
function AttributeStatManager.NotifyUpdate(player)
	fireStatUpdate(player)
end

--- Check if player's attribute data is loaded.
function AttributeStatManager.IsLoaded(player): boolean
	return getAttributeProfile(player) ~= nil
end

-- ===================== EQUIPPED ITEMS API =====================
-- Equipment boosts are tagged with an id starting with this prefix so they can
-- be wiped and rebuilt in one pass (they persist in the profile, so a stale
-- one from a previous session is removed the same way).
local EQUIP_PREFIX = "equip:"

--- Rebuild every equipment boost from scratch (one StatUpdated fire).
--- entries: array of { slotId, itemId, label, color?, flat = {Attr = n}, mult = {Attr = m} }
---   mult values are multipliers (1.05 = +5%).
function AttributeStatManager.ApplyEquipment(player, entries)
	local data = getAttributeData(player)
	if not data then
		return false
	end

	local function keep(boost)
		return not (type(boost.id) == "string" and boost.id:sub(1, #EQUIP_PREFIX) == EQUIP_PREFIX)
	end

	-- 1) strip old equipment boosts from every attribute
	for _, entry in pairs(data) do
		if type(entry) == "table" then
			local flats, mults = {}, {}
			for _, boost in ipairs(entry.flatBoosts or {}) do
				if keep(boost) then
					table.insert(flats, boost)
				end
			end
			for _, boost in ipairs(entry.multipliers or {}) do
				if keep(boost) then
					table.insert(mults, boost)
				end
			end
			entry.flatBoosts, entry.multipliers = flats, mults
		end
	end

	-- 2) add the current set
	for _, item in ipairs(entries or {}) do
		local id = EQUIP_PREFIX .. item.slotId
		for attrKey, amount in pairs(item.flat or {}) do
			if data[attrKey] then
				table.insert(data[attrKey].flatBoosts, {
					id = id,
					label = item.label,
					value = amount,
					color = item.color,
					itemId = item.itemId,
					slotId = item.slotId,
					sourceType = item.sourceType,
				})
			else
				warn("[AttributeStatManager] equipment stat has no attribute: " .. tostring(attrKey))
			end
		end
		for attrKey, amount in pairs(item.mult or {}) do
			if data[attrKey] then
				table.insert(data[attrKey].multipliers, {
					id = id,
					label = item.label,
					value = amount,
					color = item.color,
					itemId = item.itemId,
					slotId = item.slotId,
					sourceType = item.sourceType,
				})
			end
		end
	end

	fireStatUpdate(player)
	return true
end

-- ===================== COLLECTION BOOSTS =====================
-- Permanent collection tier rewards (CollectionService). Same idea as the equipment boosts: tagged with an id prefix and
-- rebuilt from scratch every time, so a boost saved by a previous session is replaced and can never stack.
local COLLECTION_PREFIX = "collection:"

--- entries: array of { id, label, color?, attr, flat? = n, mult? = m } (mult is a multiplier, 1.05 = +5%).
function AttributeStatManager.ApplyCollection(player, entries)
	local data = getAttributeData(player)
	if not data then
		return false
	end

	local function keep(boost)
		return not (type(boost.id) == "string" and boost.id:sub(1, #COLLECTION_PREFIX) == COLLECTION_PREFIX)
	end

	for _, entry in pairs(data) do
		if type(entry) == "table" then
			local flats, mults = {}, {}
			for _, boost in ipairs(entry.flatBoosts or {}) do
				if keep(boost) then
					table.insert(flats, boost)
				end
			end
			for _, boost in ipairs(entry.multipliers or {}) do
				if keep(boost) then
					table.insert(mults, boost)
				end
			end
			entry.flatBoosts, entry.multipliers = flats, mults
		end
	end

	for _, item in ipairs(entries or {}) do
		local target = data[item.attr]
		if target then
			local boost = {
				id = COLLECTION_PREFIX .. item.id,
				label = item.label,
				color = item.color,
				sourceType = "collection",
			}
			if item.flat then
				boost.value = item.flat
				table.insert(target.flatBoosts, boost)
			elseif item.mult then
				boost.value = item.mult
				table.insert(target.multipliers, boost)
			end
		else
			warn("[AttributeStatManager] collection reward has no attribute: " .. tostring(item.attr))
		end
	end

	fireStatUpdate(player)
	return true
end

-- ===================== ADMIN (DEBUG) BOOSTS =====================
-- /set and /add use one flat boost per attribute with this id. They are
-- removed when the profile loads, so debug values never persist.
local ADMIN_ID = "admin"

-- The /set boost is the single flat boost with id "admin"; panel bonuses
-- ("admin:<n>", see below) are left alone.
local function stripAdmin(entry)
	local kept = {}
	for _, boost in ipairs(entry.flatBoosts or {}) do
		if boost.id ~= ADMIN_ID then
			table.insert(kept, boost)
		end
	end
	entry.flatBoosts = kept
end

--- Current admin amount on an attribute (0 if none).
function AttributeStatManager.GetAdminBoost(player, attrKey)
	local data = getAttributeData(player)
	for _, boost in ipairs(data and data[attrKey] and data[attrKey].flatBoosts or {}) do
		if boost.id == ADMIN_ID then
			return boost.value
		end
	end
	return 0
end

--- Set (replace) the admin boost on an attribute. amount 0 removes it.
function AttributeStatManager.SetAdminBoost(player, attrKey, amount)
	local data = getAttributeData(player)
	if not data or not data[attrKey] then
		return false
	end
	stripAdmin(data[attrKey])
	if amount ~= 0 then
		table.insert(data[attrKey].flatBoosts, {
			id = ADMIN_ID,
			label = "Admin",
			value = amount,
			color = "#FF55FF",
			sourceType = "admin",
		})
	end
	fireStatUpdate(player)
	return true
end

--- Remove every admin boost (all attributes).
function AttributeStatManager.ClearAdminBoosts(player)
	local data = getAttributeData(player)
	if not data then
		return false
	end
	for _, entry in pairs(data) do
		if type(entry) == "table" then
			stripAdmin(entry)
		end
	end
	fireStatUpdate(player)
	return true
end

-- ===================== TEMP BONUSES (admin panel) =====================
-- Timed or until-cleared bonuses, flat ("flat") or percent ("pct" -> multiplier).
-- Held in memory and tagged "admin:<n>"; stripped from the profile on load, so they
-- never persist even if the server crashes mid-bonus.
local tempBonusCounter = 0

local function removeBoostById(list, id)
	local kept = {}
	for _, boost in ipairs(list or {}) do
		if boost.id ~= id then
			table.insert(kept, boost)
		end
	end
	return kept
end

--- Remove one temp bonus. Returns true if it existed.
function AttributeStatManager.RemoveTempBonus(player, bonusId)
	local mine = tempBonuses[player.UserId]
	local bonus = mine and mine[bonusId]
	if not bonus then
		return false
	end
	mine[bonusId] = nil
	local data = getAttributeData(player)
	local entry = data and data[bonus.attr]
	if entry then
		entry.flatBoosts = removeBoostById(entry.flatBoosts, bonusId)
		entry.multipliers = removeBoostById(entry.multipliers, bonusId)
		fireStatUpdate(player)
	end
	return true
end

--- Add a temp bonus. mode "flat" adds `amount`; "pct" adds amount% (x1 + amount/100).
--- duration <= 0 means until removed. Returns the bonus id, or nil + reason.
function AttributeStatManager.AddTempBonus(player, attrKey, mode, amount, duration)
	local data = getAttributeData(player)
	if not data or not data[attrKey] then
		return nil, "Unknown attribute"
	end
	if mode ~= "flat" and mode ~= "pct" then
		return nil, "Mode must be flat or pct"
	end

	tempBonusCounter += 1
	local bonusId = "admin:" .. tempBonusCounter
	local expiresAt = duration > 0 and (os.clock() + duration) or nil

	local mine = tempBonuses[player.UserId]
	if not mine then
		mine = {}
		tempBonuses[player.UserId] = mine
	end
	mine[bonusId] = { id = bonusId, attr = attrKey, mode = mode, amount = amount, expiresAt = expiresAt }

	if mode == "flat" then
		table.insert(data[attrKey].flatBoosts, {
			id = bonusId,
			label = "Admin",
			value = amount,
			color = "#FF55FF",
			sourceType = "admin",
		})
	else
		table.insert(data[attrKey].multipliers, {
			id = bonusId,
			label = "Admin",
			value = 1 + amount / 100,
			color = "#FF55FF",
			sourceType = "admin",
		})
	end
	fireStatUpdate(player)

	if duration > 0 then
		task.delay(duration, function()
			if player.Parent then
				AttributeStatManager.RemoveTempBonus(player, bonusId)
			end
		end)
	end
	return bonusId
end

--- Active temp bonuses: array of { id, attr, mode, amount, remaining (nil = until cleared) }.
function AttributeStatManager.ListTempBonuses(player)
	local out = {}
	for _, bonus in pairs(tempBonuses[player.UserId] or {}) do
		table.insert(out, {
			id = bonus.id,
			attr = bonus.attr,
			mode = bonus.mode,
			amount = bonus.amount,
			remaining = bonus.expiresAt and math.max(0, math.ceil(bonus.expiresAt - os.clock())) or nil,
		})
	end
	table.sort(out, function(a, b)
		return tonumber(a.id:sub(7)) < tonumber(b.id:sub(7))
	end)
	return out
end

--- Remove every temp bonus (does not touch the /set boost).
function AttributeStatManager.ClearTempBonuses(player)
	for bonusId in pairs(tempBonuses[player.UserId] or {}) do
		AttributeStatManager.RemoveTempBonus(player, bonusId)
	end
end

-- ===================== REMOTE FUNCTION HANDLERS =====================

--- RequestStats RemoteFunction: client calls this to get current stats.
RequestStats.OnServerInvoke = function(player)
	-- Poll briefly if not loaded yet (mirrors SkillsDataManager pattern)
	local attempts = 0
	while not getAttributeProfile(player) and attempts < 20 do
		task.wait(0.25)
		attempts += 1
	end

	return buildStatPayload(player)
end

-- ===================== PLAYER LIFECYCLE =====================
Players.PlayerAdded:Connect(function(player)
	AttributeStatManager.LoadData(player)
end)

Players.PlayerRemoving:Connect(function(player)
	AttributeStatManager.ReleaseData(player)
end)

-- Handle players already in game (Studio testing)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		AttributeStatManager.LoadData(player)
	end)
end

print("AttributeStatManager: Ready ✓")
return AttributeStatManager
