-- ============================================================
--  WeaponManager (ModuleScript)
--  Place inside: ServerScriptService
--
--  Server-authoritative weapon system.
--  - Tracks equipped weapons per player
--  - Applies stat bonuses when equipped
--  - Validates hits and applies damage
--  - Fires remote events for VFX/SFX
--
--  API:
--    WeaponManager.EquipWeapon(player, weaponId)
--    WeaponManager.UnequipWeapon(player)
--    WeaponManager.GetEquipped(player) → weaponId or nil
--    WeaponManager.GetStats(player) → { damage, critChance, ... }
--    WeaponManager.Lock(player, seconds)  (an ability cast locks the combo; abilities live in AbilityService)
--    (sword hits: TrySwing -> onSwingHit -> DamageService.swing at each step's hit frame)
-- ============================================================

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry")) :: any
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
local MovementService = require(ServerScriptService:WaitForChild("MovementService")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any

local WeaponManager = {}

-- ===================== REMOTES =====================
local function ensureRemote(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local EquipWeaponEvent = ensureRemote("RemoteEvent", "EquipWeapon")
local UnequipWeaponEvent = ensureRemote("RemoteEvent", "UnequipWeapon")
ensureRemote("RemoteEvent", "WeaponHit") -- DamageService broadcasts every hit on it: (target, position, damage, isCrit, ...)
local UpdateWeaponStatsEvent = ensureRemote("RemoteEvent", "UpdateWeaponStats")
local SwordSwingEvent = ensureRemote("RemoteEvent", "SwordSwing") -- client -> server: "I clicked"; server -> clients: (player, step, speed)

-- ===================== RUNTIME STATE =====================
-- [userId] = { weaponId, toolInstance, stats, abilities }
local playerWeapons = {}
-- ===================== COMBO STATE =====================
-- [userId] = { step, busyUntil, expiresAt, ticket, slowed, baseSpeed }
local combos = {}
local SWING_SLACK = 0.1 -- network jitter allowance when a swing arrives just before the previous one has ended

--- Called at each accepted swing's hit frame: the hit is only resolved if the same weapon is still held (a weapon
--- switch or reset in between cancels it). Replace `WeaponManager.onSwingHit` to change what a swing does.
WeaponManager.onSwingHit = function(player, stepIndex, weaponId)
	local state = playerWeapons[player.UserId]
	if not state or state.weaponId ~= weaponId then
		return
	end
	DamageService.swing(player, stepIndex, weaponId, state.stats)
end

-- ===================== HELPERS =====================

--- Build stat bonuses from a weapon config.
local function getWeaponStats(weaponConfig, rarity)
	rarity = rarity or weaponConfig.rarity or 0
	local scaling = WeaponRegistry.getRarityScaling(rarity)

	return {
		baseDamage = weaponConfig.baseDamage * scaling,
		critChance = weaponConfig.critChance,
		critMultiplier = weaponConfig.critMultiplier,
		attackSpeed = weaponConfig.attackSpeed,
		knockback = weaponConfig.knockback,
		range = weaponConfig.range,
		weaponType = weaponConfig.weaponType,
		rarity = rarity,
	}
end

--- Apply weapon stats to player via AttributeStatManager.
local function applyWeaponStats(player, stats)
	if not AttributeStatManager then
		return
	end
	-- TODO: Call AttributeStatManager API to add flat bonuses
	-- For now, stats are stored and used by WeaponController
end

--- Remove weapon stats from player.
local function removeWeaponStats(player)
	if not AttributeStatManager then
		return
	end
	-- TODO: Call AttributeStatManager API to remove bonuses
end

-- ===================== SWORD COMBO =====================
local function getCombo(player)
	local c = combos[player.UserId]
	if not c then
		c = { step = 0, busyUntil = 0, expiresAt = 0, ticket = 0, slowed = false }
		combos[player.UserId] = c
	end
	return c
end

local function restoreWalkSpeed(player, c)
	if c.slowed then
		c.slowed = false
		MovementService.SetFactor(player, "combat", nil)
	end
end

--- Drop the combo (weapon changed, death, leave): step 0, walk speed back.
local function resetCombo(player)
	local c = combos[player.UserId]
	if not c then
		return
	end
	c.ticket += 1
	c.step = 0
	c.busyUntil = 0
	c.expiresAt = 0
	restoreWalkSpeed(player, c)
	player:SetAttribute("ComboStep", 0)
end

--- A click with the held weapon. Returns (accepted, stepIndex).
function WeaponManager.TrySwing(player): (boolean, number?)
	local weapon = playerWeapons[player.UserId]
	local typeConfig = weapon and CombatConfig.get(weapon.config.weaponType)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (typeConfig and humanoid) or humanoid.Health <= 0 then
		return false, nil
	end
	if not character:FindFirstChild(weapon.config.toolName) then
		return false, nil -- not actually in hand
	end

	local c = getCombo(player)
	local now = os.clock()
	if now < c.busyUntil - SWING_SLACK then
		return false, nil -- still swinging
	end

	local stepCount = #typeConfig.steps
	local stepIndex = (c.step >= stepCount or now > c.expiresAt) and 1 or c.step + 1
	local step = typeConfig.steps[stepIndex]
	local speed = math.max(0.5, weapon.stats.attackSpeed or 1)
	local swingTime = CombatConfig.swingTime(step, speed)

	c.ticket += 1
	local ticket = c.ticket
	c.step = stepIndex
	c.busyUntil = now + swingTime
	c.expiresAt = c.busyUntil + typeConfig.comboWindow
	player:SetAttribute("ComboStep", stepIndex)

	-- slower walking while swinging (the finisher is heavier)
	c.slowed = true
	MovementService.SetFactor(player, "combat", stepIndex == stepCount and typeConfig.finisherMoveSpeedFactor or typeConfig.moveSpeedFactor)

	SwordSwingEvent:FireAllClients(player, stepIndex, speed, weapon.config.weaponType, weapon.weaponId)

	task.delay(step.hitFrame / speed, function()
		local hook = (WeaponManager :: any).onSwingHit
		if hook and c.ticket == ticket then
			hook(player, stepIndex, weapon.weaponId)
		end
	end)
	task.delay(swingTime, function()
		if c.ticket == ticket then
			restoreWalkSpeed(player, c)
		end
	end)
	task.delay(swingTime + typeConfig.comboWindow, function()
		if c.ticket == ticket then
			c.step = 0
			player:SetAttribute("ComboStep", 0)
		end
	end)
	return true, stepIndex
end

local swingAllowed = RateLimiter.new(8, 6)
SwordSwingEvent.OnServerEvent:Connect(function(player)
	if swingAllowed(player) then
		WeaponManager.TrySwing(player)
	end
end)

-- ===================== EQUIP / UNEQUIP =====================

--- Equip a weapon by its ID. Must be in player's inventory.
function WeaponManager.EquipWeapon(player, weaponId: string): boolean
	local weaponConfig = WeaponRegistry.get(weaponId)
	if not weaponConfig then
		warn("[WeaponManager] Unknown weapon: " .. weaponId)
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	-- Find the tool: WeaponInit calls this when the Tool is already held (in the Character)
	local backpack = player:FindFirstChild("Backpack")
	local toolInstance = character:FindFirstChild(weaponConfig.toolName)
	if not toolInstance and backpack then
		toolInstance = backpack:FindFirstChild(weaponConfig.toolName)
	end

	if not toolInstance or not toolInstance:IsA("Tool") then
		warn("[WeaponManager] Tool not found for " .. player.Name .. ": " .. weaponConfig.toolName)
		return false
	end

	-- Unequip any previous weapon
	if playerWeapons[player.UserId] then
		WeaponManager.UnequipWeapon(player)
	end
	resetCombo(player)

	-- Equip via Humanoid (nothing to do when the Tool is already in hand)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and toolInstance.Parent ~= character then
		humanoid:EquipTool(toolInstance)
	end

	-- Store equipped state
	local rarity = toolInstance:GetAttribute("Rarity") or 0
	local stats = getWeaponStats(weaponConfig, rarity)

	playerWeapons[player.UserId] = {
		weaponId = weaponId,
		toolInstance = toolInstance,
		config = weaponConfig,
		stats = stats,
		abilities = weaponConfig.abilities or {},
	}

	-- Apply stat bonuses
	applyWeaponStats(player, stats)

	-- Fire events
	EquipWeaponEvent:FireClient(player, { weaponId = weaponId, stats = stats })
	UpdateWeaponStatsEvent:FireClient(player, stats)

	print("[WeaponManager] " .. player.Name .. " equipped " .. weaponConfig.displayName)
	return true
end

--- Unequip current weapon.
function WeaponManager.UnequipWeapon(player): boolean
	local state = playerWeapons[player.UserId]
	if not state then
		return false
	end

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end
	end

	-- Remove stat bonuses
	removeWeaponStats(player)

	-- Clear state
	playerWeapons[player.UserId] = nil
	resetCombo(player)

	-- Fire events
	UnequipWeaponEvent:FireClient(player)

	return true
end

--- Get currently equipped weapon ID, or nil.
function WeaponManager.GetEquipped(player): string?
	local state = playerWeapons[player.UserId]
	return state and state.weaponId or nil
end

--- Get computed stats for player's equipped weapon.
function WeaponManager.GetStats(player)
	local state = playerWeapons[player.UserId]
	if not state then
		return nil
	end
	return state.stats
end

-- ===================== ABILITIES =====================
-- Key-cast abilities (cost, cooldown, shape, damage) live in AbilityService + AbilityConfig. This is the one hook it needs.

--- Lock the combo for `seconds` (a cast in progress): swings are refused until it ends.
function WeaponManager.Lock(player, seconds: number)
	local c = getCombo(player)
	local untilTime = os.clock() + seconds
	c.busyUntil = math.max(c.busyUntil, untilTime)
	c.expiresAt = math.max(c.expiresAt, untilTime + 0.2)
end

-- ===================== PLAYER LIFECYCLE =====================

--- Clean up when player leaves.
local function onPlayerLeaving(player)
	playerWeapons[player.UserId] = nil
	combos[player.UserId] = nil
end

Players.PlayerRemoving:Connect(onPlayerLeaving)

print("[WeaponManager] Loaded ✓")
return WeaponManager
