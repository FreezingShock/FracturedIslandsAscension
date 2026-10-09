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
local AbilityConfig = require(Modules:WaitForChild("AbilityConfig")) :: any
local CombatAnimator = require(Modules:WaitForChild("CombatAnimator")) :: any
local CombatFX = require(Modules:WaitForChild("CombatFX")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any

-- ===================== REMOTES =====================
local EquipWeaponEvent = ReplicatedStorage:WaitForChild("EquipWeapon")
local UnequipWeaponEvent = ReplicatedStorage:WaitForChild("UnequipWeapon")
local AbilityCastEvent = ReplicatedStorage:WaitForChild("AbilityCast")
local UpdateWeaponStatsEvent = ReplicatedStorage:WaitForChild("UpdateWeaponStats")
local SwordSwingEvent = ReplicatedStorage:WaitForChild("SwordSwing")

-- ===================== STATE =====================
local currentWeapon = nil
local currentStats = {}
local currentAbilities = {}
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

-- Hit feedback (flash, damage numbers, impact sound) is DamageNumberController: it listens to the WeaponHit remote.

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
	-- works with the cursor locked or free (T, third-person free camera); never while a menu is open. A click on a
	-- GUI button is already filtered out by gameProcessed in the input handler.
	return not MenuBridge.isOpen()
end

--- With a free cursor there is no crosshair, so the character turns toward where the cursor points (on the ground
--- plane at hip height; above the horizon it falls back to the camera's heading).
local function faceCursor()
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return -- the locked camera already steers the body
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not (root and camera) then
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local flat
	if math.abs(ray.Direction.Y) > 1e-3 then
		local t = (root.Position.Y - ray.Origin.Y) / ray.Direction.Y
		if t > 0 then
			local hit = ray.Origin + ray.Direction * t
			flat = Vector3.new(hit.X - root.Position.X, 0, hit.Z - root.Position.Z)
		end
	end
	if not flat or flat.Magnitude < 0.75 then
		local look = camera.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	if flat.Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
	end
end

local function startSwing()
	local dodgeUntil = player:GetAttribute("DodgeUntil")
	if type(dodgeUntil) == "number" and workspace:GetServerTimeNow() < dodgeUntil then
		return -- no swinging while rolling
	end
	local typeConfig = CombatConfig.get(currentWeapon.weaponType)
	local now = os.clock()
	local stepCount = #typeConfig.steps
	local stepIndex = (combo.step >= stepCount or now > combo.expiresAt) and 1 or combo.step + 1
	local step = typeConfig.steps[stepIndex]
	local speed = math.max(0.5, currentWeapon.attackSpeed or 1)
	local swingTime = CombatConfig.swingTime(step, speed)

	combo.step = stepIndex
	combo.busyUntil = now + swingTime
	combo.expiresAt = combo.busyUntil + CombatConfig.comboWindowFor(typeConfig, swingTime, speed)
	combo.startedAt = now
	combo.buffered = false

	faceCursor()
	CombatAnimator.play(player.Character, currentWeapon.weaponType, stepIndex, speed, currentWeapon.id)
	CombatFX.swing(player.Character, currentWeapon.weaponType, stepIndex, speed, currentWeapon.id)
	SwordSwingEvent:FireServer()
end

local function onAttackInput()
	if not comboAllowed() then
		return
	end
	-- a click in the air plays nothing now: the server holds the swing until we land (Crash hit) and then broadcasts it
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		local now = os.clock()
		if not (combo.awaitUntil and now < combo.awaitUntil) then
			combo.awaitUntil = now + CombatConfig.crash.queueSeconds + 0.5
			SwordSwingEvent:FireServer()
		end
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

-- HOLD TO ATTACK (CombatConfig <type>.holdToAttack): while left click stays down the combo keeps going. Unlike a click (which may be
-- buffered a little before the swing ends) a held button waits for the attack bar to be FULL (ChargeTime seconds after the last swing began),
-- so every held swing is a full-damage one.
local holdingAttack = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	holdingAttack = true
	onAttackInput()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		holdingAttack = false
	end
end)

RunService.Heartbeat:Connect(function()
	local now0 = os.clock()
	if holdingAttack and currentWeapon and now0 >= combo.busyUntil then
		local typeConfig = CombatConfig.get(currentWeapon.weaponType)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local grounded = humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
		local charge = player:GetAttribute("ChargeTime")
		local charged = type(charge) ~= "number" or combo.startedAt == nil or now0 - combo.startedAt >= charge
		if typeConfig and typeConfig.holdToAttack and grounded and charged and comboAllowed() then
			startSwing()
			return
		end
		if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			holdingAttack = false -- the release was missed (menu opened, focus lost)
		end
	end
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
SwordSwingEvent.OnClientEvent:Connect(function(swinger, stepIndex, speed, weaponType, weaponId, crash)
	if swinger == player then
		combo.step = stepIndex -- the server's step wins
		-- a swing we did not animate ourselves (the landing swing of a click made in the air): play it now
		local waiting = combo.awaitUntil ~= nil and os.clock() < combo.awaitUntil
		local typeConfig = CombatConfig.get(weaponType)
		local step = typeConfig and typeConfig.steps[stepIndex]
		if (crash == true or waiting) and step and player.Character then
			combo.awaitUntil = nil
			local now = os.clock()
			combo.busyUntil = now + CombatConfig.swingTime(step, speed)
			combo.expiresAt = combo.busyUntil + CombatConfig.comboWindowFor(typeConfig, CombatConfig.swingTime(step, speed), speed)
			combo.startedAt = now
			combo.buffered = false
			faceCursor()
			CombatAnimator.play(player.Character, weaponType, stepIndex, speed, weaponId, crash == true)
			CombatFX.swing(player.Character, weaponType, stepIndex, speed, weaponId)
		end
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
-- A key press only asks the server ("I pressed Q"). The server checks the weapon, mana and cooldown and casts; the
-- effects (animation, sound, ring, embers, cooldown / mana HUD) are AbilityController, driven by the server's broadcast.

local function abilityKeyName(input: InputObject): string?
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		return "RMB"
	elseif input.UserInputType == Enum.UserInputType.Keyboard then
		return input.KeyCode.Name
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not currentWeapon or MenuBridge.isOpen() then
		return
	end
	local keyName = abilityKeyName(input)
	if not keyName or not AbilityConfig.byKey(currentWeapon.id, keyName) then
		return -- not one of this weapon's ability keys
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 or not character:FindFirstChild(currentWeapon.toolName) then
		return
	end
	faceCursor() -- cones / lines are aimed along the body
	AbilityCastEvent:FireServer(keyName)
end)

-- the server accepted our cast: the combo is locked for the cast time (mirrors WeaponManager.Lock)
AbilityCastEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or data.caster ~= player then
		return
	end
	local ability = AbilityConfig.get(data.abilityId, data.weaponId)
	combo.busyUntil = math.max(combo.busyUntil, os.clock() + (ability and ability.castTime or 0.5))
	combo.buffered = false
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
