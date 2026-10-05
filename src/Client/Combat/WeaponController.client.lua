-- ============================================================
--  WeaponController (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  Client-side weapon system.
--  - Handles weapon equip/unequip animations
--  - Detects weapon swings and sends hit data to server
--  - Displays damage numbers and visual effects
--  - Manages ability input (Q, R, etc.)
--  - Shows cooldown UI for abilities
--
-- ============================================================

-- Debug logging is off by default (these ran in hot paths: every navigation / purchase / notification).
local DEBUG = false
local function dprint(...)
	if DEBUG then
		print(...)
	end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry")) :: any
local TooltipModule = require(Modules:WaitForChild("TooltipModule")) :: any
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local CombatAnimator = require(Modules:WaitForChild("CombatAnimator")) :: any
local CombatFX = require(Modules:WaitForChild("CombatFX")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any

-- ===================== REMOTES =====================
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("EquipWeapon")
local UnequipWeaponEvent = ReplicatedStorage:WaitForChild("UnequipWeapon")
local WeaponAbilityEvent = ReplicatedStorage:WaitForChild("WeaponAbility")
local WeaponHitEvent = ReplicatedStorage:WaitForChild("WeaponHit")
local UpdateWeaponStatsEvent = ReplicatedStorage:WaitForChild("UpdateWeaponStats")
local SwordSwingEvent = ReplicatedStorage:WaitForChild("SwordSwing")

-- ===================== STATE =====================
local currentWeapon = nil
local currentStats = {}
local currentAbilities = {}
-- R and T belong to the camera (R = perspective, T = cursor lock; see CameraController), so abilities use Q for now
local abilityKeybinds = {
	[Enum.KeyCode.Q] = "Q",
}
local weaponTrail = nil
local animatedFor = nil -- weapon id whose equip/idle animations are running
local lastSwingTime = 0
local combo = { step = 0, busyUntil = 0, expiresAt = 0, buffered = false } -- client-side combo prediction (see SWORD COMBO)
local swingCooldown = 0.5 -- seconds between swings

-- ===================== WEAPON STATE =====================

local function onWeaponEquipped()
	if not player.Character then
		return
	end

	-- Find equipped tool in character
	for _, child in ipairs(player.Character:GetChildren()) do
		if child:IsA("Tool") then
			local weaponConfig = WeaponRegistry.getByToolName(child.Name)
			if weaponConfig then
				currentWeapon = weaponConfig
				dprint("[WeaponController] Equipped: " .. weaponConfig.displayName)

				-- situation animations (equip once, idle loops); nothing plays until an id is set in CombatConfig
				if animatedFor ~= weaponConfig.id then
					animatedFor = weaponConfig.id
					CombatAnimator.playSlot(player.Character, weaponConfig.weaponType, "equip", weaponConfig.id)
					CombatFX.equip(player.Character, weaponConfig.weaponType, weaponConfig.id)
					CombatAnimator.playSlot(player.Character, weaponConfig.weaponType, "idle", weaponConfig.id)
				end

				-- Create weapon trail
				if child:FindFirstChild("Handle") then
					-- TODO: Create trail from handle for visual feedback
				end
			end
		end
	end
end

local function onWeaponUnequipped()
	if currentWeapon then
		dprint("[WeaponController] Unequipped: " .. currentWeapon.displayName)
	end
	currentWeapon = nil
	animatedFor = nil
	if player.Character then
		CombatAnimator.stop(player.Character)
		CombatFX.stop(player.Character)
	end
	if weaponTrail then
		weaponTrail:Destroy()
		weaponTrail = nil
	end
end

-- ===================== EVENT HANDLERS =====================

EquipWeaponEvent.OnClientEvent:Connect(function(data)
	currentWeapon = WeaponRegistry.get(data.weaponId)
	currentStats = data.stats or {}
	onWeaponEquipped()
	dprint("[WeaponController] Server equipped: " .. (currentWeapon and currentWeapon.displayName or "Unknown"))
end)

UnequipWeaponEvent.OnClientEvent:Connect(function()
	onWeaponUnequipped()
	if player.Character then
		CombatAnimator.stop(player.Character)
	end
	combo.step, combo.busyUntil, combo.expiresAt, combo.buffered = 0, 0, 0, false
end)

-- Stats update from server
UpdateWeaponStatsEvent.OnClientEvent:Connect(function(stats)
	currentStats = stats or {}
	-- TODO: Update weapon UI panel with new stats
end)

-- Ability cast event (feedback)
WeaponAbilityEvent.OnClientEvent:Connect(function(data)
	local abilityName = data.abilityName
	local cooldown = data.cooldown or 5
	dprint("[WeaponController] Ability triggered: " .. abilityName .. " (CD: " .. cooldown .. "s)")
	-- TODO: Play VFX/SFX for ability
	-- TODO: Update cooldown UI
end)

-- Weapon hit event (from server, for damage numbers)
WeaponHitEvent.OnClientEvent:Connect(function(data)
	local target = data.target
	local damage = data.damage
	local isCrit = data.isCrit
	local position = data.position
	-- TODO: Show damage number floating text at position
	-- TODO: Play hit sound / particle effect
end)

-- ===================== EQUIP ON HOTBAR SLOT SELECTION =====================

-- When player equips hotbar item, auto-equip weapon if it's a weapon
if player.Character then
	onWeaponEquipped()
end
player.CharacterAdded:Connect(function(char)
	task.wait(0.1)
	onWeaponEquipped()
end)

-- ===================== WEAPON SWING / ATTACK HANDLING =====================

-- ===================== SWORD COMBO (left click) =====================
-- The server owns the combo (WeaponManager.TrySwing: timing, step order, walk speed). The client predicts the
-- same rules so a click animates at once, buffers one click while a swing is in progress, and syncs back from
-- the server's ComboStep attribute and SwordSwing broadcasts.
local function comboAllowed(): boolean
	if not currentWeapon or not CombatConfig.get(currentWeapon.weaponType) then
		return false
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not character:FindFirstChild(currentWeapon.toolName) then
		return false
	end
	-- only while the cursor is locked to the game view and no menu is open
	return UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter and not MenuBridge.isOpen()
end

local function startSwing()
	local typeConfig = CombatConfig.get(currentWeapon.weaponType)
	local now = os.clock()
	local stepCount = #typeConfig.steps
	local stepIndex = (combo.step >= stepCount or now > combo.expiresAt) and 1 or combo.step + 1
	local step = typeConfig.steps[stepIndex]
	local speed = math.max(0.5, currentWeapon.attackSpeed or 1)
	local swingTime = CombatConfig.swingTime(step, speed)

	combo.step = stepIndex
	combo.busyUntil = now + swingTime
	combo.expiresAt = combo.busyUntil + typeConfig.comboWindow
	combo.buffered = false

	CombatAnimator.play(player.Character, currentWeapon.weaponType, stepIndex, speed, currentWeapon.id)
	CombatFX.swing(player.Character, currentWeapon.weaponType, stepIndex, speed, currentWeapon.id)
	SwordSwingEvent:FireServer()
end

local function onAttackInput()
	if not comboAllowed() then
		return
	end
	local typeConfig = CombatConfig.get(currentWeapon.weaponType)
	local now = os.clock()
	if now >= combo.busyUntil then
		startSwing()
	elseif combo.busyUntil - now <= typeConfig.bufferTime then
		combo.buffered = true -- remembered: fires the moment this swing ends
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	onAttackInput()
end)

RunService.Heartbeat:Connect(function()
	if combo.buffered and os.clock() >= combo.busyUntil then
		if comboAllowed() then
			startSwing()
		else
			combo.buffered = false
		end
	end
end)

-- our own authoritative step. Other players' animations replicate by themselves, but their trail and sound are local
-- effects, so each client plays those from the server's broadcast.
SwordSwingEvent.OnClientEvent:Connect(function(swinger, stepIndex, speed, weaponType, weaponId)
	if swinger == player then
		combo.step = stepIndex -- the server's step wins
	elseif swinger and swinger.Character then
		CombatFX.swing(swinger.Character, weaponType, stepIndex, speed, weaponId)
	end
end)

CombatAnimator.preload() -- every weapon type's animation assets, once, before the first swing
CombatFX.preload() -- and its sounds

-- resync when the server drops the combo (window expired, weapon changed, rejected clicks)
player:GetAttributeChangedSignal("ComboStep"):Connect(function()
	local step = player:GetAttribute("ComboStep") or 0
	if step == 0 and os.clock() >= combo.busyUntil then
		combo.step = 0
		combo.buffered = false
	end
end)

-- ===================== ABILITY INPUT =====================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local keyName = abilityKeybinds[input.KeyCode]
	if not keyName or not currentWeapon then
		return
	end

	-- Find ability with this key
	for _, ability in ipairs(currentWeapon.abilities or {}) do
		if ability.key == keyName and ability.type == "active" then
			-- Try to cast on server
			-- TODO: Create remote to TryAbility(abilityName) on server
			dprint("[WeaponController] Attempting ability: " .. ability.name)
			break
		end
	end
end)

-- ===================== WEAPON INFO PANEL =====================

-- TODO: Create a weapon info UI panel that shows:
--   - Equipped weapon name + rarity
--   - Current stats (damage, crit, attack speed)
--   - Active abilities with cooldowns
--   - Passive abilities description

-- ===================== SYNC WITH INVENTORY ============

-- Listen for inventory updates and check if equipped tool changed
local UpdateInventoryEvent = ReplicatedStorage:WaitForChild("UpdateInventory")

UpdateInventoryEvent.OnClientEvent:Connect(function(data)
	-- If weapon unequipped from inventory, update state
	if not player.Character then
		return
	end

	local equippedToolInChar = nil
	for _, child in ipairs(player.Character:GetChildren()) do
		if child:IsA("Tool") then
			equippedToolInChar = child
			break
		end
	end

	if not equippedToolInChar then
		onWeaponUnequipped()
	end
end)

dprint("[WeaponController] Ready ✓")
