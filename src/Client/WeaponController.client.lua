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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry")) :: any
local TooltipModule = require(Modules:WaitForChild("TooltipModule")) :: any

-- ===================== REMOTES =====================
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("EquipWeapon")
local UnequipWeaponEvent = ReplicatedStorage:WaitForChild("UnequipWeapon")
local WeaponAbilityEvent = ReplicatedStorage:WaitForChild("WeaponAbility")
local WeaponHitEvent = ReplicatedStorage:WaitForChild("WeaponHit")
local UpdateWeaponStatsEvent = ReplicatedStorage:WaitForChild("UpdateWeaponStats")

-- ===================== STATE =====================
local currentWeapon = nil
local currentStats = {}
local currentAbilities = {}
local abilityKeybinds = {
	[Enum.KeyCode.Q] = "Q",
	[Enum.KeyCode.R] = "R",
	[Enum.KeyCode.T] = "T",
}
local weaponTrail = nil
local lastSwingTime = 0
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
				print("[WeaponController] Equipped: " .. weaponConfig.displayName)

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
		print("[WeaponController] Unequipped: " .. currentWeapon.displayName)
	end
	currentWeapon = nil
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
	print("[WeaponController] Server equipped: " .. (currentWeapon and currentWeapon.displayName or "Unknown"))
end)

UnequipWeaponEvent.OnClientEvent:Connect(function()
	onWeaponUnequipped()
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
	print("[WeaponController] Ability triggered: " .. abilityName .. " (CD: " .. cooldown .. "s)")
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

-- Detect when equipped tool is activated (left-click)
local lastSwingInfo = nil

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not currentWeapon or not player.Character then
			return
		end

		-- Cooldown check
		local timeSinceLastSwing = tick() - lastSwingTime
		if timeSinceLastSwing < swingCooldown then
			return
		end

		lastSwingTime = tick()

		-- Perform swing detection
		local character = player.Character
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		-- TODO: Raycasts or region-based hit detection
		-- For now, just log swing
		print("[WeaponController] Swing with " .. currentWeapon.displayName)

		-- TODO: Send hit data to server if targets found
		-- Server validates damage, applies to targets
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
			print("[WeaponController] Attempting ability: " .. ability.name)
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

print("[WeaponController] Ready ✓")
