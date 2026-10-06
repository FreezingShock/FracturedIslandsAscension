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
local RunService = game:GetService("RunService")
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
local SwordSwingEvent = ensureRemote("RemoteEvent", "SwordSwing") -- client -> server: "I clicked"; server -> clients: (player, step, speed, weaponType, weaponId, crash)

-- ===================== RUNTIME STATE =====================
-- [userId] = { weaponId, toolInstance, stats, abilities }
local playerWeapons = {}
-- ===================== COMBO STATE =====================
-- [userId] = { step, busyUntil, expiresAt, ticket, slowed, baseSpeed }
local combos = {}
local SWING_SLACK = 0.1 -- network jitter allowance when a swing arrives just before the previous one has ended
-- [userId] = { at = os.clock() of a click made in the air, grounded = consecutive frames on the ground } waiting for the
-- landing (the Crash hit); see WeaponManager.Click
local queued = {}
local LANDED_FRAMES = 3 -- frames on the ground in a row that count as having landed

--- Called at each accepted swing's hit frame: the hit is only resolved if the same weapon is still held (a weapon
--- switch or reset in between cancels it). Replace `WeaponManager.onSwingHit` to change what a swing does.
WeaponManager.onSwingHit = function(player, stepIndex, weaponId, crash)
	local state = playerWeapons[player.UserId]
	if not state or state.weaponId ~= weaponId then
		return
	end
	DamageService.swing(player, stepIndex, weaponId, state.stats, crash)
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
	queued[player.UserId] = nil
	restoreWalkSpeed(player, c)
	player:SetAttribute("ComboStep", 0)
end

--- A swing with the held weapon. `crash` = the queued landing swing of a click made in the air: it ignores the swing lock
--- (WeaponManager.Click checked it), uses CombatConfig.crash.step, never slows the walk, and hits as a Crash. `hitIn` =
--- seconds until touchdown: the hit lands then (never later than the step's own hit frame).
--- Returns (accepted, stepIndex).
function WeaponManager.TrySwing(player, crash: boolean?, hitIn: number?): (boolean, number?)
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
	if not crash and now < c.busyUntil - SWING_SLACK then
		return false, nil -- still swinging
	end

	local stepCount = #typeConfig.steps
	local stepIndex = (c.step >= stepCount or now > c.expiresAt) and 1 or c.step + 1
	if crash then
		local wanted = CombatConfig.crash.step
		stepIndex = math.clamp(wanted == "last" and stepCount or tonumber(wanted) or stepCount, 1, stepCount)
	end
	local step = typeConfig.steps[stepIndex]
	local speed = math.max(0.5, weapon.stats.attackSpeed or 1)
	local swingTime = CombatConfig.swingTime(step, speed)

	c.ticket += 1
	local ticket = c.ticket
	c.step = stepIndex
	c.busyUntil = now + swingTime
	c.expiresAt = c.busyUntil + typeConfig.comboWindow
	player:SetAttribute("ComboStep", stepIndex)

	-- slower walking while swinging (the finisher is heavier); a Crash never slows you
	if not crash then
		c.slowed = true
		MovementService.SetFactor(player, "combat", stepIndex == stepCount and typeConfig.finisherMoveSpeedFactor or typeConfig.moveSpeedFactor)
	end

	SwordSwingEvent:FireAllClients(player, stepIndex, speed, weapon.config.weaponType, weapon.weaponId, crash == true)

	local hitDelay = step.hitFrame / speed
	if crash and hitIn then
		hitDelay = math.clamp(hitIn, 0.03, hitDelay)
	end
	task.delay(hitDelay, function()
		local hook = (WeaponManager :: any).onSwingHit
		if hook and c.ticket == ticket then
			hook(player, stepIndex, weapon.weaponId, crash == true)
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

--- A click. On the ground it is a normal swing; in the air (nothing under the humanoid) it is queued, one per jump, and
--- the swing plays when the player lands (the Crash hit, CombatConfig.crash). Movement is never locked while waiting.
function WeaponManager.Click(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 and humanoid.FloorMaterial == Enum.Material.Air then
		if playerWeapons[player.UserId] and not queued[player.UserId] then
			queued[player.UserId] = { at = os.clock(), grounded = 0 }
		end
		return
	end
	WeaponManager.TrySwing(player)
end

local landingParams = RaycastParams.new()
landingParams.FilterType = Enum.RaycastFilterType.Exclude

--- Seconds until the feet reach the ground below, from the fall speed and gravity; nil while rising or with no ground
--- within reach (so a long fall does not start the swing early).
local function timeToLanding(character: Model, humanoid: Humanoid): number?
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local fallSpeed = -root.AssemblyLinearVelocity.Y
	if fallSpeed <= 0 then
		return nil
	end
	landingParams.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(root.Position, Vector3.new(0, -60, 0), landingParams)
	if not result then
		return nil
	end
	local height = result.Distance - (humanoid.HipHeight + root.Size.Y / 2)
	if height <= 0 then
		return 0
	end
	local g = workspace.Gravity
	return (-fallSpeed + math.sqrt(fallSpeed * fallSpeed + 2 * g * height)) / g
end

--- How long before touchdown the crash swing has to start so its hit frame lands on the ground.
local function crashLead(userId: number): number?
	local weapon = playerWeapons[userId]
	local typeConfig = weapon and CombatConfig.get(weapon.config.weaponType)
	if not typeConfig then
		return nil
	end
	local wanted = CombatConfig.crash.step
	local count = #typeConfig.steps
	local step = typeConfig.steps[math.clamp(wanted == "last" and count or tonumber(wanted) or count, 1, count)]
	return step.hitFrame / math.max(0.5, weapon.stats.attackSpeed or 1)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for userId, wait in pairs(queued) do
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (player and humanoid and playerWeapons[userId]) or humanoid.Health <= 0 or now - wait.at > CombatConfig.crash.queueSeconds then
			queued[userId] = nil -- gone, dead, weapon changed, or still airborne too long
		else
			-- landed = on the ground for a few frames in a row (the replicated floor state flickers for a moment)
			wait.grounded = humanoid.FloorMaterial ~= Enum.Material.Air and wait.grounded + 1 or 0
			if now >= getCombo(player).busyUntil - SWING_SLACK then
				if wait.grounded >= LANDED_FRAMES then
					queued[userId] = nil
					WeaponManager.TrySwing(player, true, 0)
				else
					-- still falling: start the swing early enough that its hit frame lands at touchdown
					local untilLanding = timeToLanding(character, humanoid)
					local lead = crashLead(userId)
					if untilLanding and lead and untilLanding <= lead then
						queued[userId] = nil
						WeaponManager.TrySwing(player, true, untilLanding)
					end
				end
			end
		end
	end
end)

local swingAllowed = RateLimiter.new(8, 6)
SwordSwingEvent.OnServerEvent:Connect(function(player)
	if swingAllowed(player) then
		WeaponManager.Click(player)
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
