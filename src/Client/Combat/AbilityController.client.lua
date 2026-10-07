--[[
	AbilityController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Everything the player sees and hears of a key ability (AbilityConfig). The server decides and casts; every client
	hears about it on the AbilityCast remote and shows it here:
	  * caster's own client: the cast animation (AbilityConfig `animation` -> CombatConfig.animations; replicates to others)
	  * everyone nearby: at the hit frame the server sends AbilityFx (origin, chain / dash points); the 3D sound and the effect
	    (`fx`) play from it: nova ring, embers (zone), ground frost, dash streak, chain bolts. Numbers live in AbilityConfig.fx /
	    .sounds. Parts and emitters are pooled and capped (AbilityConfig.fxLimits); one Heartbeat runs all zone effects.
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
local FxEvent = ReplicatedStorage:WaitForChild("AbilityFx")
local template = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("AbilitySlot") :: CanvasGroup

local MANA_OK = Color3.fromRGB(85, 255, 255)
local MANA_LOW = Color3.fromRGB(255, 85, 85)
local NAME_READY = Color3.fromRGB(255, 255, 255)
local NAME_BUSY = Color3.fromRGB(150, 150, 150)

-- ===================== EFFECTS =====================
-- Every effect part comes from a small pool (acquire / release) and the total is capped (AbilityConfig.fxLimits), so a busy
-- fight reuses the same parts instead of creating and destroying instances. One Heartbeat serves all running zones.
local Limits = AbilityConfig.fxLimits
local pools: { [string]: { BasePart } } = { ring = {}, bolt = {}, area = {} }
local liveParts = 0
local liveEmitters = 0

local function makePart(kind: string): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	if kind == "ring" then
		part.Shape = Enum.PartType.Cylinder
		part.Material = Enum.Material.Neon
	elseif kind == "bolt" then
		part.Material = Enum.Material.Neon
	else -- area: invisible box that carries the particle emitter
		part.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Emitter"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.LightEmission = 1
		emitter.Lifetime = NumberRange.new(1.2, 2.2)
		emitter.EmissionDirection = Enum.NormalId.Bottom
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.Enabled = false
		emitter.Parent = part
	end
	return part
end

local function acquire(kind: string): BasePart?
	if liveParts >= Limits.maxParts then
		return nil
	end
	liveParts += 1
	local part = table.remove(pools[kind]) or makePart(kind)
	part.Parent = workspace.CurrentCamera
	return part
end

local function release(kind: string, part: BasePart)
	liveParts = math.max(0, liveParts - 1)
	part.Parent = nil
	if kind == "area" then
		local emitter = part:FindFirstChild("Emitter") :: ParticleEmitter
		emitter.Enabled = false
		emitter:Clear()
	end
	if #pools[kind] < Limits.poolSize then
		table.insert(pools[kind], part)
	else
		part:Destroy()
	end
end

local function tooFar(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude > Limits.maxDistance
end

local function playSound(position: Vector3, entry: any)
	if not (entry and entry.id and entry.id ~= "") then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = workspace.CurrentCamera
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

local function feetOf(position: Vector3): Vector3
	return position - Vector3.new(0, 2.8, 0)
end

--- A flat ring on the ground at `position`; returns the part (nil at the part cap). The caller tweens and releases it.
local function groundRing(position: Vector3, color: Color3, height: number): BasePart?
	local ring = acquire("ring")
	if not ring then
		return nil
	end
	ring.Color = color
	ring.Transparency = 0.25
	ring.Size = Vector3.new(height, 2, 2)
	ring.CFrame = CFrame.new(feetOf(position)) * CFrame.Angles(0, 0, math.rad(90)) -- a cylinder's axis is X: lay it flat
	return ring
end

local function novaRing(position: Vector3, fx: any, radius: number)
	local ring = groundRing(position, fx.color, fx.height or 0.6)
	if not ring then
		return
	end
	local time = fx.time or 0.45
	TweenService:Create(ring, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(fx.height or 0.6, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	task.delay(time + 0.05, release, "ring", ring)
end

--- One straight neon piece from a to b.
local function boltPiece(a: Vector3, b: Vector3, color: Color3, width: number, time: number)
	local bolt = acquire("bolt")
	if not bolt then
		return
	end
	local length = math.max((b - a).Magnitude, 0.1)
	bolt.Color = color
	bolt.Transparency = 0
	bolt.Size = Vector3.new(width, width, length)
	bolt.CFrame = CFrame.lookAt((a + b) / 2, b)
	TweenService:Create(bolt, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
		Size = Vector3.new(width * 0.2, width * 0.2, length),
	}):Play()
	task.delay(time + 0.05, release, "bolt", bolt)
end

local function dashTrail(points: { Vector3 }, fx: any)
	local a, b = points[1], points[2]
	if not (a and b) then
		return
	end
	boltPiece(a, b, fx.color, fx.width or 3, fx.time or 0.35)
	local burst = fx.burst or fx.color
	novaRing(a, { color = burst, time = 0.3, height = 0.5 }, 5)
	novaRing(b, { color = burst, time = 0.3, height = 0.5 }, 5)
end

local function chainBolts(points: { Vector3 }, fx: any)
	local segments = fx.segments or 5
	local jitter = fx.jitter or 1.5
	for link = 1, #points - 1 do
		local a, b = points[link], points[link + 1]
		task.delay((link - 1) * (fx.linkDelay or 0.06), function()
			local previous = a
			for piece = 1, segments do
				local nextPoint = b
				if piece < segments then
					local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * jitter
					nextPoint = a:Lerp(b, piece / segments) + offset
				end
				boltPiece(previous, nextPoint, fx.color, fx.width or 0.5, fx.time or 0.3)
				previous = nextPoint
			end
		end)
	end
end

-- running zones: a ground ring (frost) and / or an emitter area, ended by time, by the server's "end" message, or when the
-- caster is gone
type ZoneFx = { key: string, root: BasePart?, follow: boolean, area: BasePart?, ring: BasePart?, endsAt: number, height: number }
local zonesFx: { ZoneFx } = {}
local zoneConnection: RBXScriptConnection? = nil

local function stopZoneFx(zone: ZoneFx)
	local index = table.find(zonesFx, zone)
	if index then
		table.remove(zonesFx, index)
	end
	if zone.area then
		local area = zone.area
		liveEmitters = math.max(0, liveEmitters - 1)
		local emitter = area:FindFirstChild("Emitter") :: ParticleEmitter
		emitter.Enabled = false
		task.delay(2.5, release, "area", area) -- the last particles finish falling
	end
	if zone.ring then
		local ring = zone.ring
		TweenService:Create(ring, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		task.delay(0.45, release, "ring", ring)
	end
	if #zonesFx == 0 and zoneConnection then
		zoneConnection:Disconnect()
		zoneConnection = nil
	end
end

local function zoneStep()
	local now = os.clock()
	for index = #zonesFx, 1, -1 do
		local zone = zonesFx[index]
		local root = zone.root
		local humanoid = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
		if now >= zone.endsAt or (zone.follow and not (root and root.Parent and humanoid and humanoid.Health > 0)) then
			stopZoneFx(zone)
		elseif zone.follow and zone.area and root then
			zone.area.CFrame = CFrame.new(root.Position + Vector3.new(0, zone.height, 0))
		end
	end
end

local function startZoneFx(key: string, root: BasePart?, origin: Vector3, fx: any, radius: number, duration: number)
	local zone: ZoneFx = { key = key, root = root, follow = fx.kind == "zone", area = nil, ring = nil, endsAt = os.clock() + duration, height = 22 }

	if fx.kind == "frost" then
		local ring = groundRing(origin, fx.color, 0.3)
		if ring then
			zone.ring = ring
			TweenService:Create(ring, TweenInfo.new(fx.time or 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.3, radius * 2, radius * 2),
				Transparency = 0.65,
			}):Play()
		end
		zone.height = 14
	end

	if liveEmitters < Limits.maxEmitters then
		local area = acquire("area")
		if area then
			liveEmitters += 1
			local emitter = area:FindFirstChild("Emitter") :: ParticleEmitter
			emitter.Color = typeof(fx.color) == "Color3" and ColorSequence.new(fx.color) or fx.color
			emitter.Rate = fx.rate or 90
			emitter.Speed = NumberRange.new(fx.speed or 8)
			emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, fx.size or 0.5), NumberSequenceKeypoint.new(1, 0) })
			emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			area.Size = Vector3.new(radius * 2, 1, radius * 2)
			area.CFrame = CFrame.new(origin + Vector3.new(0, zone.height, 0))
			emitter.Enabled = true
			zone.area = area
		end
	end

	if not (zone.area or zone.ring) then
		return
	end
	table.insert(zonesFx, zone)
	if not zoneConnection then
		zoneConnection = RunService.Heartbeat:Connect(zoneStep)
	end
end

local function endZoneByKey(key: string)
	for index = #zonesFx, 1, -1 do
		if zonesFx[index].key == key then
			stopZoneFx(zonesFx[index])
		end
	end
end

local function zoneKey(caster: Player, abilityId: string): string
	return caster.UserId .. "/" .. abilityId
end

--- The cast was accepted: the caster's own client plays the animation (it replicates to everyone else).
local function showCast(data: any)
	local caster = data.caster :: Player
	local ability = AbilityConfig.get(data.abilityId, data.weaponId)
	local character = caster and caster.Character
	if ability and character and caster == player then
		CombatAnimator.playKey(character, ability.animation)
	end
end

--- The hit frame: sound + visuals from the server's origin / points.
local function showFx(data: any)
	local caster = data.caster :: Player
	local ability = AbilityConfig.get(data.abilityId, data.weaponId)
	local root = caster.Character and caster.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = data.origin :: Vector3
	if not ability or tooFar(origin) then
		return
	end
	playSound(origin, ability.sound and AbilityConfig.sounds[ability.sound])
	local fx = ability.fx and AbilityConfig.fx[ability.fx]
	if not fx then
		return
	end
	local radius = ability.shape and (ability.shape.radius or ability.shape.reach or ability.shape.length) or 10
	if fx.kind == "nova" then
		novaRing(origin, fx, radius)
	elseif (fx.kind == "zone" or fx.kind == "frost") and ability.zone then
		local key = zoneKey(caster, data.abilityId)
		endZoneByKey(key) -- a recast replaces the old effect
		startZoneFx(key, root, origin, fx, radius, data.duration or ability.zone.duration)
	elseif fx.kind == "dash" and data.points then
		dashTrail(data.points, fx)
	elseif fx.kind == "chain" and data.points then
		chainBolts(data.points, fx)
	end
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

local MAX_POINTS = 12
FxEvent.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or typeof(data.caster) ~= "Instance" or not data.caster:IsA("Player") or type(data.abilityId) ~= "string" then
		return
	end
	if data.kind == "end" then
		endZoneByKey(zoneKey(data.caster, data.abilityId))
		return
	end
	if data.kind ~= "start" or typeof(data.origin) ~= "Vector3" then
		return
	end
	if data.points ~= nil then
		if type(data.points) ~= "table" or #data.points > MAX_POINTS then
			return
		end
		for _, point in ipairs(data.points) do
			if typeof(point) ~= "Vector3" then
				return
			end
		end
	end
	showFx(data)
end)

Players.PlayerRemoving:Connect(function(leaving)
	for index = #zonesFx, 1, -1 do
		if zonesFx[index].key:match("^" .. leaving.UserId .. "/") then
			stopZoneFx(zonesFx[index])
		end
	end
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
