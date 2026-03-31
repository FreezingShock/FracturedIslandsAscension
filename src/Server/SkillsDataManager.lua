--[[
	SkillsDataManager (ModuleScript)
	Place inside: ServerScriptService

	Handles:
	  - Skill XP thresholds (levels I -> L)
	  - Adding XP to skills
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

-- ===================== ROMAN NUMERALS =====================
local ROMAN = {
	"I",
	"II",
	"III",
	"IV",
	"V",
	"VI",
	"VII",
	"VIII",
	"IX",
	"X",
	"XI",
	"XII",
	"XIII",
	"XIV",
	"XV",
	"XVI",
	"XVII",
	"XVIII",
	"XIX",
	"XX",
	"XXI",
	"XXII",
	"XXIII",
	"XXIV",
	"XXV",
	"XXVI",
	"XXVII",
	"XXVIII",
	"XXIX",
	"XXX",
	"XXXI",
	"XXXII",
	"XXXIII",
	"XXXIV",
	"XXXV",
	"XXXVI",
	"XXXVII",
	"XXXVIII",
	"XXXIX",
	"XL",
	"XLI",
	"XLII",
	"XLIII",
	"XLIV",
	"XLV",
	"XLVI",
	"XLVII",
	"XLVIII",
	"XLIX",
	"L",
}

function SkillsDataManager.ToRoman(n)
	return ROMAN[math.clamp(n, 1, 50)] or tostring(n)
end

-- ===================== XP THRESHOLDS =====================
-- XP required to go FROM level N to level N+1
-- Levels 1->50 (so index 1 = XP needed to go from Lv1 to Lv2, etc.)
-- Fully customizable — just edit the values below.
-- Max level is 50 (Level L). At max level XP is locked.

local XP_THRESHOLDS = {
	-- Lv1->2    Lv2->3    Lv3->4    Lv4->5    Lv5->6
	50,
	150,
	300,
	500,
	750,
	-- Lv6->7    Lv7->8    Lv8->9    Lv9->10
	1050,
	1400,
	1800,
	2250,
	3300,
	-- Lv10->11 ... Lv19->20
	4100,
	5000,
	6000,
	7100,
	8300,
	9600,
	11000,
	12500,
	14100,
	15800,
	-- Lv20->21 ... Lv29->30
	17600,
	19500,
	21500,
	23600,
	25800,
	28100,
	30500,
	33000,
	35600,
	38300,
	-- Lv30->31 ... Lv39->40
	41100,
	44000,
	47000,
	50100,
	53300,
	56600,
	60000,
	63500,
	67100,
	70800,
	-- Lv40->41 ... Lv49->50
	74600,
	78500,
	82500,
	86600,
	90800,
	95100,
	99500,
	104000,
	108600,
	113300,
}
-- Index 50 is intentionally absent — max level has no "next threshold"
-- (49 thresholds cover transitions 1->2 through 49->50)

local MAX_LEVEL = 50

function SkillsDataManager.GetXPNeeded(level)
	if level >= MAX_LEVEL then
		return 0
	end -- already max
	return XP_THRESHOLDS[level] or 999999
end

-- ===================== SKILL NAMES =====================
local SKILL_NAMES = {
	"Farming",
	"Foraging",
	"Fishing",
	"Mining",
	"Combat",
	"Carpentry",
}

-- ===================== PROFILE STORE =====================
-- Unified template: skills at top level, inventory under _Inventory.
-- Reconcile() fills in _Inventory for existing players on first load.
local PROFILE_TEMPLATE = {}
for _, skillName in ipairs(SKILL_NAMES) do
	PROFILE_TEMPLATE[skillName] = { level = 1, xp = 0 }
end

-- ── Inventory data (structurally isolated under one key) ──
-- items         : array of { itemId = string, count = number }
-- hotbarSlots   : { [1] = itemId or nil, ..., [9] = itemId or nil }
-- toolOrder     : { [itemId] = number } — display sort order
-- nextOrderIndex: number — auto-increment for new item types
-- maxCapacity   : number — total item cap across all stacks
PROFILE_TEMPLATE._Inventory = {
	items = {},
	hotbarSlots = {},
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
			data[skillName].level = math.clamp(tonumber(data[skillName].level) or 1, 1, MAX_LEVEL)
			data[skillName].xp = math.max(tonumber(data[skillName].xp) or 0, 0)
		end
	end

	-- ── Sanitize inventory fields ──
	if type(data._Inventory) ~= "table" then
		data._Inventory = {
			items = {},
			hotbarSlots = {},
			toolOrder = {},
			nextOrderIndex = 1,
			maxCapacity = 1000,
		}
	end
	local inv = data._Inventory
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

-- ===================== BUILD CLIENT PAYLOAD =====================
-- Sends level, xp, xpNeeded per skill so the GUI can display everything
local function buildClientData(data)
	local payload = {}
	for _, skillName in ipairs(SKILL_NAMES) do
		local skillData = data[skillName]
		local level = skillData.level
		local xp = skillData.xp
		local xpNeeded = SkillsDataManager.GetXPNeeded(level)
		payload[skillName] = {
			level = level,
			xp = xp,
			xpNeeded = xpNeeded,
			roman = SkillsDataManager.ToRoman(level),
			pct = (xpNeeded > 0) and math.clamp(xp / xpNeeded, 0, 1) or 1,
		}
	end
	return payload
end

local function fireUpdate(player)
	local profile = skillProfiles[player.UserId]
	if not profile then
		return
	end
	SkillUpdated:FireClient(player, buildClientData(profile.Data))
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

	-- Send initial data to client
	fireUpdate(player)

	return profile.Data
end

function SkillsDataManager.ReleaseData(player)
	local profile = skillProfiles[player.UserId]
	if profile then
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
-- Returns true if leveled up
function SkillsDataManager.AddXP(player, skillName, amount)
	local data = SkillsDataManager.GetData(player)
	if not data then
		warn("[SkillsDataManager] No data for " .. player.Name)
		return false
	end

	local skill = data[skillName]
	if not skill then
		warn("[SkillsDataManager] Unknown skill: " .. skillName)
		return false
	end

	if skill.level >= MAX_LEVEL then
		fireUpdate(player)
		return false
	end

	local leveledUp = false
	skill.xp = skill.xp + amount

	-- Handle level-ups (loop in case of large XP grants)
	while skill.level < MAX_LEVEL do
		local needed = SkillsDataManager.GetXPNeeded(skill.level)
		if skill.xp >= needed then
			skill.xp = skill.xp - needed
			skill.level = skill.level + 1
			leveledUp = true
		else
			break
		end
	end

	-- Cap XP at max level
	if skill.level >= MAX_LEVEL then
		skill.xp = 0
	end

	fireUpdate(player)
	return leveledUp
end

-- ===================== SET LEVEL DIRECTLY =====================
-- Used by _G.ChangeSkill and any admin tools
function SkillsDataManager.SetLevel(player, skillName, level)
	local data = SkillsDataManager.GetData(player)
	if not data then
		warn("[SkillsDataManager] No data for " .. player.Name)
		return
	end

	local skill = data[skillName]
	if not skill then
		warn("[SkillsDataManager] Unknown skill: " .. skillName)
		return
	end

	skill.level = math.clamp(tonumber(level) or 1, 1, MAX_LEVEL)
	skill.xp = 0 -- reset XP to 0 when manually set

	fireUpdate(player)
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

ChangeSkill.OnServerEvent:Connect(function(player, targetName, skillName, level)
	-- Only allow admins
	local ADMIN_IDS = { 288851273 } -- replace with your Roblox user ID
	local isAdmin = false
	for _, id in ipairs(ADMIN_IDS) do
		if player.UserId == id then
			isAdmin = true
			break
		end
	end
	if not isAdmin then
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
