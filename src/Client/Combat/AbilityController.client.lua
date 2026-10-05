--[[
	AbilityController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Everything the player sees and hears of a key ability (AbilityConfig). The server decides and casts; every client
	hears about it on the AbilityCast remote and shows it here:
	  * caster's own client: the cast animation (AbilityConfig `animation` -> CombatConfig.animations; replicates to others)
	  * everyone: the 3D sound at the caster and the effect (`fx`): an expanding ring ("nova") or embers over the area
	    that follow the caster for the zone's duration ("zone"). Numbers live in AbilityConfig.fx / .sounds.
	  * the cooldown / mana HUD: one slot per ability of the held weapon, cloned from the hand-made template
	    ReplicatedStorage.GUI.AbilitySlot into StarterGui.AbilityMenu.Slots (restyle both in Studio; this script only fills
	    in text, colours and the cooldown bar, it creates no UI).

	AbilitySlot template (CanvasGroup): Key (TextLabel), Name (TextLabel), Cost (TextLabel), Cooldown (Frame, a bar that
	shrinks to the left as the cooldown runs out), Timer (TextLabel, seconds left).
--]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AbilityConfig = require(Modules:WaitForChild("AbilityConfig")) :: any
local CombatAnimator = require(Modules:WaitForChild("CombatAnimator")) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CastEvent = ReplicatedStorage:WaitForChild("AbilityCast")
local template = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("AbilitySlot") :: CanvasGroup

local MANA_OK = Color3.fromRGB(85, 255, 255)
local MANA_LOW = Color3.fromRGB(255, 85, 85)
local NAME_READY = Color3.fromRGB(255, 255, 255)
local NAME_BUSY = Color3.fromRGB(150, 150, 150)

-- ===================== EFFECTS =====================
local function anchorAt(position: Vector3): Part
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = workspace.CurrentCamera
	return anchor
end

local function playSound(position: Vector3, entry: any)
	if not (entry and entry.id and entry.id ~= "") then
		return
	end
	local anchor = anchorAt(position)
	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume or 0.8
	local pitch = entry.pitch
	sound.PlaybackSpeed = pitch and (pitch[1] + (pitch[2] - pitch[1]) * math.random()) or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = entry.minDistance or 20
	sound.RollOffMaxDistance = entry.maxDistance or 100
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 6)
end

local function feetOf(root: BasePart): Vector3
	return root.Position - Vector3.new(0, 2.8, 0)
end

local function novaRing(root: BasePart, fx: any, radius: number)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = fx.color
	ring.Transparency = 0.25
	ring.Size = Vector3.new(fx.height or 0.6, 2, 2)
	ring.CFrame = CFrame.new(feetOf(root)) * CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: lay it flat
	ring.Parent = workspace.CurrentCamera
	local info = TweenInfo.new(fx.time or 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(ring, info, { Size = Vector3.new(fx.height or 0.6, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, (fx.time or 0.45) + 0.1)
end

local function emberZone(root: BasePart, fx: any, radius: number, duration: number)
	local area = Instance.new("Part")
	area.Anchored = true
	area.CanCollide = false
	area.CanQuery = false
	area.CanTouch = false
	area.Transparency = 1
	area.Size = Vector3.new(radius * 2, 1, radius * 2)
	area.Parent = workspace.CurrentCamera

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = fx.color
	emitter.LightEmission = 1
	emitter.Rate = fx.rate or 90
	emitter.Lifetime = NumberRange.new(1.2, 2.2)
	emitter.Speed = NumberRange.new(fx.speed or 8)
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.size or 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Parent = area

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if root.Parent then
			area.CFrame = CFrame.new(root.Position + Vector3.new(0, 22, 0))
		end
	end)
	task.delay(duration, function()
		connection:Disconnect()
		emitter.Enabled = false
		Debris:AddItem(area, 2.5) -- the last embers finish falling
	end)
end

local function showCast(data: any)
	local caster = data.caster :: Player
	local ability = AbilityConfig.get(data.abilityId, data.weaponId)
	local character = caster and caster.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (ability and root) then
		return
	end
	if caster == player then
		CombatAnimator.playKey(character, ability.animation)
	end
	task.delay(ability.hitFrame or 0.25, function()
		if not root.Parent then
			return
		end
		playSound(root.Position, ability.sound and AbilityConfig.sounds[ability.sound])
		local fx = ability.fx and AbilityConfig.fx[ability.fx]
		local radius = ability.shape and (ability.shape.radius or ability.shape.reach or ability.shape.length) or 10
		if fx and fx.kind == "nova" then
			novaRing(root, fx, radius)
		elseif fx and fx.kind == "zone" and ability.zone then
			emberZone(root, fx, radius, ability.zone.duration)
		end
	end)
end

-- ===================== HUD =====================
local slotsFrame: Frame? = nil
local slots: { [string]: { frame: CanvasGroup, ability: any } } = {}
local readyAt: { [string]: number } = {} -- abilityId -> workspace:GetServerTimeNow() when castable again

local function clearSlots()
	for id, slot in pairs(slots) do
		slot.frame:Destroy()
		slots[id] = nil
	end
end

local function heldWeaponId(): string?
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	return tool and tool:GetAttribute("ItemId") or nil
end

local function rebuild()
	clearSlots()
	local frame = slotsFrame
	local weaponId = heldWeaponId()
	if not (frame and weaponId) then
		return
	end
	for index, entry in ipairs(AbilityConfig.forWeapon(weaponId)) do
		local ability = entry.config
		local slot = template:Clone() :: CanvasGroup
		slot.Name = entry.id
		slot.LayoutOrder = index
		local keyLabel = slot:FindFirstChild("Key") :: TextLabel
		local nameLabel = slot:FindFirstChild("Name") :: TextLabel
		local costLabel = slot:FindFirstChild("Cost") :: TextLabel
		keyLabel.Text = ability.key
		nameLabel.Text = ability.name
		costLabel.Text = ability.manaCost .. " Mana"
		slot.Parent = frame
		slots[entry.id] = { frame = slot, ability = ability }
	end
end

local function refresh()
	local mana = player:GetAttribute("Mana") or 0
	local now = workspace:GetServerTimeNow()
	for id, slot in pairs(slots) do
		local ability = slot.ability
		local left = math.max(0, (readyAt[id] or 0) - now)
		local bar = slot.frame:FindFirstChild("Cooldown") :: Frame?
		local timer = slot.frame:FindFirstChild("Timer") :: TextLabel?
		local cost = slot.frame:FindFirstChild("Cost") :: TextLabel?
		local name = slot.frame:FindFirstChild("Name") :: TextLabel?
		if bar then
			bar.Size = UDim2.new(ability.cooldown > 0 and math.clamp(left / ability.cooldown, 0, 1) or 0, 0, 1, 0)
		end
		if timer then
			timer.Text = left > 0 and string.format("%.1f", left) or ""
		end
		local enough = mana >= ability.manaCost
		if cost then
			cost.TextColor3 = enough and MANA_OK or MANA_LOW
		end
		if name then
			name.TextColor3 = (left <= 0 and enough) and NAME_READY or NAME_BUSY
		end
	end
end

local function bind(gui: Instance)
	local frame = gui:WaitForChild("Slots", 10)
	if not (frame and frame:IsA("Frame")) then
		warn("[AbilityController] StarterGui.AbilityMenu.Slots (Frame) is missing")
		return
	end
	slotsFrame = frame
	slots = {}
	rebuild()
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(rebuild)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			task.defer(rebuild)
		end
	end)
	task.defer(rebuild)
end

CastEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or typeof(data.caster) ~= "Instance" or type(data.abilityId) ~= "string" then
		return
	end
	if data.caster == player and type(data.readyAt) == "number" then
		readyAt[data.abilityId] = data.readyAt
	end
	showCast(data)
end)

RunService.Heartbeat:Connect(refresh)

local existing = playerGui:FindFirstChild("AbilityMenu")
if existing then
	task.spawn(bind, existing)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "AbilityMenu" then
		task.spawn(bind, child) -- recreated (respawn with ResetOnSpawn)
	end
end)
player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end
