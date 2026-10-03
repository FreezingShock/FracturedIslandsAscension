-- ============================================================
--  WeaponManager (ModuleScript)
--  Place inside: ServerScriptService
--
--  Server-authoritative weapon system.
--  - Tracks equipped weapons per player
--  - Applies stat bonuses when equipped
--  - Manages ability cooldowns
--  - Validates hits and applies damage
--  - Fires remote events for VFX/SFX
--
--  API:
--    WeaponManager.EquipWeapon(player, weaponId)
--    WeaponManager.UnequipWeapon(player)
--    WeaponManager.GetEquipped(player) → weaponId or nil
--    WeaponManager.GetStats(player) → { damage, critChance, ... }
--    WeaponManager.TryAbility(player, abilityName) → success
--    WeaponManager.OnWeaponHit(player, targetPlayer, damage)
-- ============================================================

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
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
local WeaponAbilityEvent = ensureRemote("RemoteEvent", "WeaponAbility")
local WeaponHitEvent = ensureRemote("RemoteEvent", "WeaponHit")
local UpdateWeaponStatsEvent = ensureRemote("RemoteEvent", "UpdateWeaponStats")

-- ===================== RUNTIME STATE =====================
-- [userId] = { weaponId, toolInstance, stats, abilities }
local playerWeapons = {}
-- [userId] = { [abilityName] = lastCastTime }
local abilityDodges = {}

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

--- Check if an ability is off cooldown.
local function isAbilityReady(player, abilityName)
	if not abilityDodges[player.UserId] then
		abilityDodges[player.UserId] = {}
	end
	local lastCast = abilityDodges[player.UserId][abilityName]
	return lastCast == nil or (tick() - lastCast) >= 1000 -- safety cap
end

--- Mark ability as just-cast.
local function markAbilityCast(player, abilityName, cooldown)
	if not abilityDodges[player.UserId] then
		abilityDodges[player.UserId] = {}
	end
	abilityDodges[player.UserId][abilityName] = tick()
end

--- Get cooldown remaining for an ability.
local function getAbilityCooldown(player, abilityName, cooldown)
	if not abilityDodges[player.UserId] then
		return 0
	end
	local lastCast = abilityDodges[player.UserId][abilityName]
	if not lastCast then
		return 0
	end
	local elapsed = tick() - lastCast
	return math.max(0, cooldown - elapsed)
end

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

	-- Find the tool in backpack
	local backpack = player:FindFirstChild("Backpack")
	local toolInstance = nil
	if backpack then
		toolInstance = backpack:FindFirstChild(weaponConfig.toolName)
	end

	if not toolInstance or not toolInstance:IsA("Tool") then
		warn("[WeaponManager] Tool not found in backpack: " .. weaponConfig.toolName)
		return false
	end

	-- Unequip any previous weapon
	if playerWeapons[player.UserId] then
		WeaponManager.UnequipWeapon(player)
	end

	-- Equip via Humanoid
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
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

--- Attempt to cast an ability. Returns success, remaining cooldown.
function WeaponManager.TryAbility(player, abilityName: string): (boolean, number?)
	local state = playerWeapons[player.UserId]
	if not state then
		return false, nil
	end

	-- Find ability in equipped weapon
	local ability = nil
	for _, ab in ipairs(state.abilities) do
		if ab.name == abilityName then
			ability = ab
			break
		end
	end

	if not ability then
		return false, nil
	end

	-- Passive abilities can't be cast
	if ability.type == "passive" then
		return false, nil
	end

	-- Check cooldown
	local cooldown = ability.cooldown or 5
	if not isAbilityReady(player, abilityName) then
		local remaining = getAbilityCooldown(player, abilityName, cooldown)
		return false, remaining
	end

	-- Mark cast
	markAbilityCast(player, abilityName, cooldown)

	-- Fire event for client VFX/SFX
	WeaponAbilityEvent:FireClient(player, {
		abilityName = abilityName,
		weaponId = state.weaponId,
		cooldown = cooldown,
	})

	-- TODO: Apply ability effects (damage, particles, etc.)
	return true, cooldown
end

--- Get cooldown info for an ability.
function WeaponManager.GetAbilityCooldown(player, abilityName: string): (number, number)
	local state = playerWeapons[player.UserId]
	if not state then
		return 0, 0
	end

	local ability = nil
	for _, ab in ipairs(state.abilities) do
		if ab.name == abilityName then
			ability = ab
			break
		end
	end

	if not ability or ability.type == "passive" then
		return 0, 0
	end

	local cooldown = ability.cooldown or 5
	local remaining = getAbilityCooldown(player, abilityName, cooldown)
	return cooldown, remaining
end

-- ===================== DAMAGE & HIT REGISTRATION =====================

--- Handle a weapon hit. Apply damage with rarity scaling, crits, etc.
--- Returns { damage, isCrit, knockback }
function WeaponManager.OnWeaponHit(player, targetPlayer, hitConfig)
	hitConfig = hitConfig or {}

	local state = playerWeapons[player.UserId]
	if not state then
		return nil
	end

	local stats = state.stats
	local baseDamage = stats.baseDamage or 10
	local critChance = stats.critChance or 0.1
	local critMultiplier = stats.critMultiplier or 1.5
	local knockback = stats.knockback or 15

	-- Compute damage
	local isCrit = math.random() < critChance
	local finalDamage = baseDamage
	if isCrit then
		finalDamage = finalDamage * critMultiplier
	end

	-- TODO: Apply damage to targetPlayer's health
	-- Call damage system / AttributeStatManager

	-- Fire hit event for VFX
	WeaponHitEvent:FireAllClients({
		attacker = player.Name,
		target = targetPlayer.Name,
		damage = finalDamage,
		isCrit = isCrit,
		position = hitConfig.position,
		weaponId = state.weaponId,
	})

	return {
		damage = finalDamage,
		isCrit = isCrit,
		knockback = knockback,
	}
end

-- ===================== PLAYER LIFECYCLE =====================

--- Clean up when player leaves.
local function onPlayerLeaving(player)
	abilityDodges[player.UserId] = nil
	playerWeapons[player.UserId] = nil
end

Players.PlayerRemoving:Connect(onPlayerLeaving)

print("[WeaponManager] Loaded ✓")
return WeaponManager
