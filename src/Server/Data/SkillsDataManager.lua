--[[
	SkillsDataManager (ModuleScript)
	Place inside: ServerScriptService

	Handles:
	  - Skill XP and levels (SkillsConfig: Hypixel curve, per-skill caps, wisdom)
	  - Adding XP to skills (AddXP is the only entry)
	  - Saving via ProfileService (slots into existing DataManager pattern)
	  - _G.ChangeSkill(player, skillName, level) for manual level setting
	  - Firing SkillUpdated RemoteEvent to clients
	  
	UPDATED: Inventory fields merged into the same ProfileStore under
	         the `_Inventory` key. InventoryDataManager accesses this
	         via GetProfile() / GetInventoryData(). Skill data is
	         completely untouched — inventory is structurally isolated.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- CORRECT: ServerScriptService is server-only
local ServerScriptService = game:GetService("ServerScriptService")
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService")) :: any

local SkillsDataManager = {}

-- ===================== CONFIG =====================
-- Skills, level caps, the XP curve (Hypixel) and the Roman numerals live in SkillsConfig.
local SkillsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SkillsConfig")) :: any
local SKILL_NAMES = SkillsConfig.ORDER

function SkillsDataManager.ToRoman(n)
	return SkillsConfig.roman(n)
end

--- XP needed to go from `level` to the next one in `skillName` (0 at the cap).
function SkillsDataManager.GetXPNeeded(skillName, level)
	return SkillsConfig.xpNeeded(skillName, level)
end

function SkillsDataManager.GetCap(skillName)
	return SkillsConfig.cap(skillName)
end

-- ===================== PROFILE STORE =====================
-- Unified template: skills at top level, inventory under _Inventory.
-- Reconcile() fills in _Inventory for existing players on first load.
local PROFILE_TEMPLATE = {}
for _, skillName in ipairs(SKILL_NAMES) do
	PROFILE_TEMPLATE[skillName] = { level = 1, xp = 0 }
end

-- Skill level rewards (SkillRewardService): claimed[skill] = highest level already paid out (a high-water mark),
-- recipes / unlocks = ids recorded by the recipe / unlock reward types. Reconcile() backfills it for existing players.
PROFILE_TEMPLATE._Rewards = { claimed = {}, recipes = {}, unlocks = {} }

-- ── Inventory data (structurally isolated under one key) ──
-- items         : array of { itemId = string, count = number }
-- hotbarSlots   : { [1] = itemId or nil, ..., [9] = itemId or nil }
-- toolOrder     : { [itemId] = number } — display sort order
-- nextOrderIndex: number — auto-increment for new item types
-- maxCapacity   : number — total item cap across all stacks
-- gridSlots     : { ["1"] = toolName, ... } (string keys: DataStore-safe)
-- equippedSlots : { Helmet = "iron_helmet", ... } (Items registry ids)
-- itemSchema    : bumped when the item system changes shape; a mismatch resets
--                 items/hotbar/grid/equipped (skills & stats are untouched)
local ITEM_SCHEMA = 2

-- (itemSchema is deliberately NOT in the template: Reconcile would fill it in
--  for old profiles and hide the mismatch. sanitizeSkillData stamps it.)
PROFILE_TEMPLATE._Inventory = {
	items = {},
	hotbarSlots = {},
	gridSlots = {},
	equippedSlots = {},
	toolOrder = {},
	nextOrderIndex = 1,
	maxCapacity = 1000,
	hotbarShowAll = false,
}

local SkillProfileStore = ProfileService.GetProfileStore(
	"PlayerSkills_v1", -- no version bump needed — Reconcile handles new keys
	PROFILE_TEMPLATE
)

local skillProfiles = {} -- [player.UserId] = profile

-- In your server DataManager (wherever ProfileService saves happen):

local SetHotbarVisibilityFunc = Instance.new("RemoteFunction")
SetHotbarVisibilityFunc.Name = "SetHotbarVisibility"
SetHotbarVisibilityFunc.Parent = ReplicatedStorage

local GetHotbarVisibilityFunc = Instance.new("RemoteFunction")
GetHotbarVisibilityFunc.Name = "GetHotbarVisibility"
GetHotbarVisibilityFunc.Parent = ReplicatedStorage

SetHotbarVisibilityFunc.OnServerInvoke = function(player, showAll)
	local profile = skillProfiles[player.UserId]
	if profile then
		profile.Data._Inventory.hotbarShowAll = (showAll == true)
	end
end

GetHotbarVisibilityFunc.OnServerInvoke = function(player)
	-- Profile may not be loaded yet if client fires before PlayerAdded completes.
	-- Poll briefly rather than returning a stale false.
	local attempts = 0
	while not skillProfiles[player.UserId] and attempts < 20 do
		task.wait(0.25)
		attempts += 1
	end
	local profile = skillProfiles[player.UserId]
	if profile then
		return profile.Data._Inventory.hotbarShowAll or false
	end
	return false
end

-- ===================== REMOTE EVENT =====================
local SkillUpdated = ReplicatedStorage:FindFirstChild("SkillUpdated")
if not SkillUpdated then
	SkillUpdated = Instance.new("RemoteEvent")
	SkillUpdated.Name = "SkillUpdated"
	SkillUpdated.Parent = ReplicatedStorage
end

-- ===================== SANITIZE =====================
local function sanitizeSkillData(data)
	for _, skillName in ipairs(SKILL_NAMES) do
		if type(data[skillName]) ~= "table" then
			data[skillName] = { level = 1, xp = 0 }
		else
			local skill = data[skillName]
			-- a saved level above the (new) cap or XP above the (new) curve is clamped; levels are never lowered otherwise
			skill.level = math.clamp(math.floor(tonumber(skill.level) or 1), 1, SkillsConfig.cap(skillName))
			local needed = SkillsConfig.xpNeeded(skillName, skill.level)
			skill.xp = needed > 0 and math.clamp(tonumber(skill.xp) or 0, 0, needed - 1) or 0
		end
	end

	if type(data._Rewards) ~= "table" then
		data._Rewards = { claimed = {}, recipes = {}, unlocks = {} }
	end
	for _, key in ipairs({ "claimed", "recipes", "unlocks" }) do
		if type(data._Rewards[key]) ~= "table" then
			data._Rewards[key] = {}
		end
	end

	-- ── Sanitize inventory fields ──
	if type(data._Inventory) ~= "table" then
		data._Inventory = {
			itemSchema = ITEM_SCHEMA,
			gridSlots = {},
			equippedSlots = {},
			items = {},
			hotbarSlots = {},
			toolOrder = {},
			nextOrderIndex = 1,
			maxCapacity = 1000,
		}
	end
	local inv = data._Inventory
	if inv.itemSchema ~= ITEM_SCHEMA then
		-- Old item format (pre item-system rework): start the inventory fresh.
		inv.itemSchema = ITEM_SCHEMA
		inv.items = {}
		inv.hotbarSlots = {}
		inv.gridSlots = {}
		inv.equippedSlots = {}
		inv.toolOrder = {}
		inv.nextOrderIndex = 1
	end
	if type(inv.gridSlots) ~= "table" then
		inv.gridSlots = {}
	end
	if type(inv.equippedSlots) ~= "table" then
		inv.equippedSlots = {}
	end
	if type(inv.items) ~= "table" then
		inv.items = {}
	end
	if type(inv.hotbarSlots) ~= "table" then
		inv.hotbarSlots = {}
	end
	if type(inv.toolOrder) ~= "table" then
		inv.toolOrder = {}
	end
	inv.nextOrderIndex = math.max(tonumber(inv.nextOrderIndex) or 1, 1)
	inv.maxCapacity = math.max(tonumber(inv.maxCapacity) or 1000, 1)
	if inv.hotbarShowAll == nil then
		inv.hotbarShowAll = false
	end
end

-- ===================== WISDOM =====================
-- XP gain = floor(base * (1 + (skill wisdom + global Wisdom) / 100)). AttributeStatManager is required lazily
-- (it may require this module), and wisdom counts as 0 until the attribute profile is loaded.
local AttributeStatManager: any = nil
local function attributes()
	if AttributeStatManager == nil then
		AttributeStatManager = false
		local module = ServerScriptService:FindFirstChild("AttributeStatManager")
		if module then
			local ok, result = pcall(require, module)
			AttributeStatManager = ok and result or false
		end
	end
	return AttributeStatManager or nil
end

--- Total wisdom of a skill in percent (skill wisdom + global Wisdom).
function SkillsDataManager.GetWisdom(player, skillName): number
	local config = SkillsConfig.skills[skillName]
	local manager = attributes()
	if not (config and manager and manager.IsLoaded(player)) then
		return 0
	end
	local total = (tonumber(manager.GetFinalValue(player, config.wisdom)) or 0)
		+ (tonumber(manager.GetFinalValue(player, "Wisdom")) or 0)
	return math.max(total, 0)
end

-- ===================== BUILD CLIENT PAYLOAD =====================
-- level, xp, xpNeeded, roman, pct per skill, plus cap and wisdom (percent) so the GUI can show everything
local function buildClientData(player, data)
	local payload = {}
	for _, skillName in ipairs(SKILL_NAMES) do
		local skillData = data[skillName]
		local level = skillData.level
		local xp = skillData.xp
		local xpNeeded = SkillsDataManager.GetXPNeeded(skillName, level)
		payload[skillName] = {
			level = level,
			xp = xp,
			xpNeeded = xpNeeded,
			roman = SkillsDataManager.ToRoman(level),
			pct = (xpNeeded > 0) and math.clamp(xp / xpNeeded, 0, 1) or 1,
			cap = SkillsConfig.cap(skillName),
			wisdom = SkillsDataManager.GetWisdom(player, skillName),
		}
	end
	return payload
end

local function fireUpdate(player)
	local profile = skillProfiles[player.UserId]
	if not profile then
		return
	end
	SkillUpdated:FireClient(player, buildClientData(player, profile.Data))
end

-- Many XP grants in a burst (a button held down) collapse into one update: at most 10 per second per player.
local UPDATE_INTERVAL = 0.1
local dirty: { [Player]: boolean } = {}
local changedListeners: { (Player) -> () } = {}

--- Register fn(player), called after every flushed change (and after a profile loads).
function SkillsDataManager.OnChanged(fn: (Player) -> ())
	table.insert(changedListeners, fn)
end

local function markDirty(player)
	dirty[player] = true
end
SkillsDataManager.MarkDirty = markDirty

local function flush(player)
	dirty[player] = nil
	fireUpdate(player)
	for _, fn in ipairs(changedListeners) do
		task.spawn(fn, player)
	end
end

do
	local elapsed = 0
	game:GetService("RunService").Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < UPDATE_INTERVAL then
			return
		end
		elapsed = 0
		for player in pairs(dirty) do
			if player.Parent and skillProfiles[player.UserId] then
				flush(player)
			else
				dirty[player] = nil
			end
		end
	end)
end

-- ===================== LOAD / RELEASE =====================
function SkillsDataManager.LoadData(player)
	local profile = SkillProfileStore:LoadProfileAsync("Skills_" .. player.UserId, "ForceLoad")

	if profile == nil then
		player:Kick("Failed to load your skill data. Please rejoin.")
		return
	end

	profile:ListenToRelease(function()
		skillProfiles[player.UserId] = nil
		player:Kick("Your skill data was loaded elsewhere. Please rejoin.")
	end)

	if not player:IsDescendantOf(Players) then
		profile:Release()
		return
	end

	profile:Reconcile()
	sanitizeSkillData(profile.Data)
	skillProfiles[player.UserId] = profile

	-- Send initial data to client (and let the reward service catch the player up)
	flush(player)

	return profile.Data
end

-- Other managers that keep a live copy of their data (InventoryDataManager) register here so they can
-- write it into the profile BEFORE it is released (PlayerRemoving order between scripts is not guaranteed).
local beforeReleaseHooks: { (Player) -> () } = {}

function SkillsDataManager.OnBeforeRelease(fn: (Player) -> ())
	table.insert(beforeReleaseHooks, fn)
end

function SkillsDataManager.ReleaseData(player)
	local profile = skillProfiles[player.UserId]
	if profile then
		for _, hook in ipairs(beforeReleaseHooks) do
			local ok, err = pcall(hook, player)
			if not ok then
				warn("[SkillsDataManager] before-release hook failed: " .. tostring(err))
			end
		end
		profile:Release()
	end
	skillProfiles[player.UserId] = nil
end

-- ===================== GET DATA =====================
function SkillsDataManager.GetData(player)
	local profile = skillProfiles[player.UserId]
	return profile and profile.Data or nil
end

-- ===================== GET PROFILE (for InventoryDataManager) =====================
--- Returns the raw profile object so other managers can access
--- their own data slice. Returns nil if not loaded.
function SkillsDataManager.GetProfile(player)
	return skillProfiles[player.UserId]
end

-- ===================== GET INVENTORY DATA =====================
--- Convenience accessor for the _Inventory slice.
--- Returns the live table reference (mutations persist to profile).
function SkillsDataManager.GetInventoryData(player)
	local profile = skillProfiles[player.UserId]
	if not profile then
		return nil
	end
	return profile.Data._Inventory
end

-- ===================== IS LOADED =====================
--- Returns true if the player's profile is loaded and ready.
function SkillsDataManager.IsLoaded(player): boolean
	return skillProfiles[player.UserId] ~= nil
end

-- ===================== ADD XP =====================
--- The ONLY way skill XP is gained. `amount` is the base XP before wisdom; `source` is a free label (button id, ...).
--- Returns the XP actually gained and whether a level was gained.
function SkillsDataManager.AddXP(player, skillName, amount, source)
	local data = SkillsDataManager.GetData(player)
	if not data then
		warn("[SkillsDataManager] No data for " .. player.Name)
		return 0, false
	end

	local skill = type(skillName) == "string" and SkillsConfig.skills[skillName] and data[skillName]
	if type(skill) ~= "table" or type(amount) ~= "number" or amount ~= amount or amount < 0 or amount == math.huge then
		warn("[SkillsDataManager] Bad AddXP call: " .. tostring(skillName) .. " " .. tostring(amount))
		return 0, false
	end

	local cap = SkillsConfig.cap(skillName)
	if skill.level >= cap then
		return 0, false -- max level: XP is locked
	end

	local gain = math.floor(amount * (100 + SkillsDataManager.GetWisdom(player, skillName)) / 100 + 1e-9)
	skill.xp += gain

	-- Handle level-ups (loop in case of large XP grants)
	local leveledUp = false
	while skill.level < cap do
		local needed = SkillsDataManager.GetXPNeeded(skillName, skill.level)
		if skill.xp < needed then
			break
		end
		skill.xp -= needed
		skill.level += 1
		leveledUp = true
	end
	if skill.level >= cap then
		skill.xp = 0
	end

	markDirty(player)
	return gain, leveledUp
end

-- ===================== SET LEVEL DIRECTLY =====================
-- Used by _G.ChangeSkill and any admin tools. Never lowers a reward already paid (claimed levels are a high-water mark).
function SkillsDataManager.SetLevel(player, skillName, level)
	local data = SkillsDataManager.GetData(player)
	if not data then
		warn("[SkillsDataManager] No data for " .. player.Name)
		return
	end

	local skill = type(skillName) == "string" and SkillsConfig.skills[skillName] and data[skillName]
	if type(skill) ~= "table" then
		warn("[SkillsDataManager] Unknown skill: " .. tostring(skillName))
		return
	end

	skill.level = math.clamp(math.floor(tonumber(level) or 1), 1, SkillsConfig.cap(skillName))
	skill.xp = 0 -- reset XP to 0 when manually set

	markDirty(player)
	print(
		string.format(
			"[SkillsDataManager] %s's %s set to Level %d (%s)",
			player.Name,
			skillName,
			skill.level,
			SkillsDataManager.ToRoman(skill.level)
		)
	)
end

-- ===================== ADMIN REMOTE =====================
local ChangeSkill = Instance.new("RemoteEvent")
ChangeSkill.Name = "ChangeSkill"
ChangeSkill.Parent = ReplicatedStorage

local AdminConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AdminConfig"))

ChangeSkill.OnServerEvent:Connect(function(player, targetName, skillName, level)
	-- Only allow admins, and never trust the argument types
	if not AdminConfig.isAdmin(player) then
		return
	end
	if type(targetName) ~= "string" or type(skillName) ~= "string" or type(level) ~= "number" then
		return
	end

	local target = Players:FindFirstChild(targetName)
	if target then
		SkillsDataManager.SetLevel(target, skillName, level)
	end
end)

-- ===================== MANUAL SAVE =====================
function SkillsDataManager.Save(player)
	local profile = skillProfiles[player.UserId]
	if profile then
		profile:Save()
	end
end

-- ===================== AUTO HOOK PLAYERS =====================
Players.PlayerAdded:Connect(function(player)
	SkillsDataManager.LoadData(player)
end)

Players.PlayerRemoving:Connect(function(player)
	SkillsDataManager.ReleaseData(player)
end)

-- Handle players already in game (Studio testing)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		SkillsDataManager.LoadData(player)
	end)
end

return SkillsDataManager
