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
local CameraConfig = require(Modules:WaitForChild("Config"):WaitForChild("CameraConfig")) :: any
local CameraFeel = require(Modules:WaitForChild("CameraFeel")) :: any

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
local pools: { [string]: { BasePart } } = { ring = {}, bolt = {}, area = {}, layer = {} }
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
	elseif kind == "bolt" or kind == "layer" then
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
	if kind == "layer" then
		part:ClearAllChildren() -- layer parts carry their own emitters and lights; those go with them
	end
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

-- ===================== LAYERED FX =====================
-- An fx with `layers` (AbilityConfig.fx) is stacked: each layer is one visual, drawn by the builder of its `kind` below.
-- Layers use the same pools and caps as everything else. A running effect is a handle that owns its parts and emitters;
-- one Heartbeat (layerStep) steps every handle. A handle ends as one: by time, by the server's "end", or when a following
-- caster dies. Ending fades the parts and lets the emitters finish (LINGER seconds), then the parts go back to the pool.
-- The rules for designing a layer are in docs/FX_GUIDE.md.
local LINGER = 2.5
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local FEET = Vector3.new(0, 2.8, 0) -- HumanoidRootPart centre to the floor

local handles: { any } = {}
local layerConnection: RBXScriptConnection? = nil

local function colorSeq(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for index, color in ipairs(colors) do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

--- Particles start small, swell, then shrink to nothing.
local function sizeCurve(size: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.5),
		NumberSequenceKeypoint.new(0.25, size),
		NumberSequenceKeypoint.new(1, 0),
	})
end

--- Particles stay bright for most of their life, then fade.
local FADE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.7, 0.3),
	NumberSequenceKeypoint.new(1, 1),
})

local function range(pair: { number }): NumberRange
	return NumberRange.new(pair[1], pair[2] or pair[1])
end

--- An emitter with the shared look (glowing, spinning, fading). The builder sets the rest.
local function newEmitter(spec: any, size: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.texture or SPARKLE
	emitter.Color = colorSeq(spec.colors or { Color3.new(1, 1, 1) })
	emitter.LightEmission = spec.lightEmission or 1
	emitter.Lifetime = range(spec.lifetime or { 1, 2 })
	emitter.Speed = range(spec.speed or { 2, 4 })
	emitter.Size = sizeCurve(size)
	emitter.Transparency = FADE
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.SpreadAngle = Vector2.new(spec.spread or 180, spec.spread or 180)
	emitter.Acceleration = spec.acceleration or Vector3.zero
	emitter.Drag = spec.drag or 0
	emitter.Shape = Enum.ParticleEmitterShape.Box
	return emitter
end

--- A part for one layer (nil at the part cap). Reset here, so a reused part never keeps the last layer's shape.
local function layerPart(handle: any): BasePart?
	local part = acquire("layer")
	if part then
		part.Shape = Enum.PartType.Block
		part.Material = Enum.Material.Neon
		part.Transparency = 0
		part.Size = Vector3.one
		table.insert(handle.parts, part)
	end
	return part
end

--- Reserves one emitter for the handle (false at the emitter cap).
local function canEmit(handle: any): boolean
	if liveEmitters >= Limits.maxEmitters then
		return false
	end
	liveEmitters += 1
	handle.emitters += 1
	return true
end

--- Where a layer sits: the caster (default) or the end of the line (`at = "end"`).
local function anchorOf(spec: any, ctx: any): Vector3
	if spec.at == "end" then
		return ctx.endPoint()
	end
	return ctx.center()
end

--- Makes sure the handle lasts until this layer is finished.
local function keepUntil(handle: any, spec: any, ctx: any, length: number)
	handle.endsAt = math.max(handle.endsAt, ctx.start + (spec.delay or 0) + length)
end

--- Easing curves for layers that move, grow or fade (`ease = "outBack"` ...). Input t runs 0..1 and is clamped.
local EASE = {
	linear = function(t: number): number
		return t
	end,
	outQuad = function(t: number): number
		return 1 - (1 - t) * (1 - t)
	end,
	outCubic = function(t: number): number
		return 1 - (1 - t) ^ 3
	end,
	outBack = function(t: number): number -- overshoots a little, then settles
		local c = 1.70158
		return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
	end,
	inCubic = function(t: number): number -- accelerates (a drop)
		return t ^ 3
	end,
	inOutSine = function(t: number): number
		return -(math.cos(math.pi * t) - 1) / 2
	end,
}

local function ease(name: string?, t: number): number
	return (EASE[name or "outCubic"] or EASE.outCubic)(math.clamp(t, 0, 1))
end

local builders: { [string]: (any, any, any) -> () } = {}

-- Flat glowing disc on the ground that breathes (pulses) in size.
builders.disc = function(handle, spec, ctx)
	local part = layerPart(handle)
	if not part then
		return
	end
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material[spec.material or "ForceField"] -- ForceField shimmers; Neon would be a flat glow
	part.Color = spec.color
	part.Transparency = spec.transparency or 0.6
	local radius = spec.radius or ctx.radius * (spec.scale or 1)
	table.insert(handle.steps, function(now)
		local pulse = 1 + math.sin(now * (spec.pulse or 1) * math.pi * 2) * (spec.pulseAmount or 0.05)
		local diameter = math.max(radius * 2 * pulse, 0.2)
		local ground = anchorOf(spec, ctx) - FEET + Vector3.new(0, spec.height or 0.2, 0)
		part.Size = Vector3.new(0.12, diameter, diameter)
		part.CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90))
	end)
end

-- A ring of short neon runes that turns; each rune shimmers on its own beat. Colours alternate around the ring.
builders.glyph = function(handle, spec, ctx)
	local colors = spec.colors or { Color3.new(1, 1, 1) }
	local count = spec.count or 8
	local radius = spec.radius or ctx.radius * (spec.scale or 1)
	local spin = math.rad(spec.spin or 30)
	local alpha = spec.transparency or 0.1
	local bars = {}
	for index = 1, count do
		local part = layerPart(handle)
		if not part then
			break
		end
		part.Color = colors[(index - 1) % #colors + 1]
		part.Size = Vector3.new(spec.length or 1.5, spec.width or 0.3, 0.1)
		table.insert(bars, { part = part, index = index })
	end
	if spec.time then
		keepUntil(handle, spec, ctx, spec.time)
	end
	table.insert(handle.steps, function(now)
		local centre = anchorOf(spec, ctx) - FEET + Vector3.new(0, spec.height or 0.3, 0)
		local phase = now * spin
		for _, bar in ipairs(bars) do
			local angle = (bar.index - 1) / count * math.pi * 2 + phase
			local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			-- turned so each rune is a tangent to the ring
			bar.part.CFrame = CFrame.new(centre + offset) * CFrame.Angles(0, -(angle + math.pi / 2), 0)
			bar.part.Transparency = alpha + 0.4 * (0.5 + 0.5 * math.sin(now * 5 + bar.index))
		end
	end)
end

-- A cone of coloured light from above, pointing down at the effect. Brightness flickers.
builders.spot = function(handle, spec, ctx)
	local part = layerPart(handle)
	if not part then
		return
	end
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	local light = Instance.new("SpotLight")
	light.Color = spec.color
	light.Range = spec.range or 20
	light.Angle = spec.angle or 40
	light.Brightness = spec.brightness or 3
	light.Parent = part
	local base = light.Brightness
	table.insert(handle.steps, function(now)
		local top = anchorOf(spec, ctx) + Vector3.new(0, spec.height or 12, 0)
		part.CFrame = CFrame.lookAt(top, top - Vector3.yAxis, Vector3.zAxis)
		light.Brightness = base * (1 + (spec.flicker or 0) * math.sin(now * 9))
	end)
end

-- Particles in a box over the area that keep drifting (sparkles rising, spores falling). Follows the effect.
builders.motes = function(handle, spec, ctx)
	if not canEmit(handle) then
		return
	end
	local part = layerPart(handle)
	if not part then
		return
	end
	local radius = spec.radius or ctx.radius * (spec.scale or 1)
	part.Transparency = 1
	part.Size = Vector3.new(radius * 2, 1, radius * 2)
	local emitter = newEmitter(spec, spec.size or 0.4)
	emitter.Rate = spec.rate or 12
	emitter.EmissionDirection = spec.direction or Enum.NormalId.Top
	emitter.Parent = part
	table.insert(handle.steps, function()
		part.CFrame = CFrame.new(anchorOf(spec, ctx) + Vector3.new(0, spec.height or 1, 0))
	end)
end

-- A ring on the ground that races outward (a shockwave). Starts after `delay`, grows, then fades.
builders.shock = function(handle, spec, ctx)
	local part = layerPart(handle)
	if not part then
		return
	end
	part.Shape = Enum.PartType.Cylinder
	part.Color = spec.color
	part.Transparency = 1
	local time = spec.time or 0.5
	local start = ctx.start + (spec.delay or 0)
	local radius = spec.radius or ctx.radius * (spec.scale or 1)
	keepUntil(handle, spec, ctx, time + 0.1)
	table.insert(handle.steps, function(now)
		if now < start then
			return
		end
		local t = math.clamp((now - start) / time, 0, 1)
		local eased = 1 - (1 - t) ^ 3
		local diameter = math.max(radius * 2 * eased, 0.2)
		part.Size = Vector3.new((spec.height or 0.6) * (1 - 0.5 * t), diameter, diameter)
		part.CFrame = CFrame.new(anchorOf(spec, ctx) - FEET + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Transparency = 0.05 + 0.95 * t ^ 1.5
	end)
end

-- Straight cracks shooting out from the impact point. Each one grows, holds, then fades.
builders.cracks = function(handle, spec, ctx)
	local count = spec.count or 6
	local length = spec.radius or ctx.radius * (spec.scale or 1)
	local time = spec.time or 0.4
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, time + 0.25)
	for index = 1, count do
		local part = layerPart(handle)
		if not part then
			break
		end
		part.Color = spec.color
		part.Transparency = 1
		local heading = (index - 1) / count * math.pi * 2 + (math.random() - 0.5) * 0.5
		local dir = Vector3.new(math.cos(heading), 0, math.sin(heading))
		local reach = length * (0.7 + 0.3 * math.random())
		table.insert(handle.steps, function(now)
			if now < start then
				return
			end
			local t = math.clamp((now - start) / time, 0, 1)
			local ground = anchorOf(spec, ctx) - FEET + Vector3.new(0, 0.1, 0)
			local len = math.max(reach * t, 0.1)
			local mid = ground + dir * (len / 2)
			part.Size = Vector3.new(spec.width or 0.3, 0.08, len)
			part.CFrame = CFrame.lookAt(mid, mid + dir)
			local fade = math.max(0, (t - 0.6) / 0.4)
			part.Transparency = fade + (1 - fade) * 0.05
		end)
	end
end

-- A one-off puff of particles (debris, embers) that flies out and falls. Fires once, after `delay`.
builders.burst = function(handle, spec, ctx)
	if not canEmit(handle) then
		return
	end
	local part = layerPart(handle)
	if not part then
		return
	end
	part.Transparency = 1
	part.Size = Vector3.one * 0.5
	local emitter = newEmitter(spec, spec.size or 0.6)
	emitter.Rate = 0
	emitter.EmissionDirection = spec.direction or Enum.NormalId.Top
	emitter.Acceleration = spec.acceleration or Vector3.new(0, -20, 0)
	emitter.Drag = spec.drag or 1
	emitter.Parent = part
	local start = ctx.start + (spec.delay or 0)
	local fired = false
	keepUntil(handle, spec, ctx, (spec.lifetime and (spec.lifetime[2] or spec.lifetime[1]) or 1) + 0.2)
	table.insert(handle.steps, function(now)
		part.CFrame = CFrame.new(anchorOf(spec, ctx) - FEET + Vector3.new(0, spec.height or 0.3, 0))
		if not fired and now >= start then
			fired = true
			emitter:Emit(spec.count or 20)
		end
	end)
end

-- A straight neon bolt from the first point to the last, with a wider soft glow behind it. Fades out.
builders.beam = function(handle, spec, ctx)
	local points = ctx.points
	if not points or #points < 2 then
		return
	end
	local a, b = points[1], points[#points]
	local time = spec.time or 0.3
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, time + 0.1)
	local bolts = {
		{ part = layerPart(handle), color = spec.color, width = spec.width or 0.5, base = 0 },
		{ part = layerPart(handle), color = spec.glowColor or spec.color, width = spec.glowWidth or 2, base = spec.glowTransparency or 0.6 },
	}
	for _, bolt in ipairs(bolts) do
		if bolt.part then
			bolt.part.Color = bolt.color
			bolt.part.Transparency = 1
		end
	end
	table.insert(handle.steps, function(now)
		if now < start then
			return
		end
		local t = math.clamp((now - start) / time, 0, 1)
		local mid = (a + b) / 2
		local length = math.max((b - a).Magnitude, 0.1)
		for _, bolt in ipairs(bolts) do
			if bolt.part then
				bolt.part.Size = Vector3.new(bolt.width, bolt.width, length)
				bolt.part.CFrame = CFrame.lookAt(mid, b)
				bolt.part.Transparency = bolt.base + (1 - bolt.base) * t * t
			end
		end
	end)
end

-- Wind streaks that ride along the line with the projectile: the emitter moves from the first point to the last and
-- blows backwards, so the streaks trail behind it.
builders.streaks = function(handle, spec, ctx)
	local points = ctx.points
	if not points or #points < 2 or not canEmit(handle) then
		return
	end
	local a, b = points[1], points[#points]
	local part = layerPart(handle)
	if not part then
		return
	end
	part.Transparency = 1
	part.Size = Vector3.one * 0.5
	local emitter = newEmitter(spec, spec.size or 0.3)
	emitter.Rate = spec.rate or 60
	emitter.EmissionDirection = Enum.NormalId.Back
	emitter.Parent = part
	local time = spec.time or 0.3
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, time + (spec.lifetime and (spec.lifetime[2] or spec.lifetime[1]) or 0.5))
	table.insert(handle.steps, function(now)
		if now < start then
			return
		end
		local t = math.clamp((now - start) / time, 0, 1)
		local position = a:Lerp(b, t)
		if (b - position).Magnitude > 0.05 then
			part.CFrame = CFrame.lookAt(position, b)
		end
		emitter.Enabled = t < 1
	end)
end

-- A ring that repeats: one pulse every `every` seconds (one per zone tick, say), each racing outward and fading.
builders.pulse = function(handle, spec, ctx)
	local part = layerPart(handle)
	if not part then
		return
	end
	part.Shape = Enum.PartType.Cylinder
	part.Color = spec.color
	part.Transparency = 1
	local time = spec.time or 0.6
	local every = spec.every or math.huge
	local start = ctx.start + (spec.delay or 0)
	local radius = spec.radius or ctx.radius * (spec.scale or 1)
	if spec.every == nil then
		keepUntil(handle, spec, ctx, time + 0.1)
	end
	table.insert(handle.steps, function(now)
		local age = now - start
		if age < 0 then
			part.Transparency = 1
			return
		end
		local phase = age % every
		if phase > time then
			part.Transparency = 1
			return
		end
		local t = phase / time
		local diameter = math.max(radius * 2 * ease(spec.ease, t), 0.2)
		part.Size = Vector3.new((spec.height or 0.5) * (1 - 0.5 * t), diameter, diameter)
		part.CFrame = CFrame.new(anchorOf(spec, ctx) - FEET + Vector3.new(0, spec.lift or 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		part.Transparency = 0.05 + 0.95 * t ^ 1.5
	end)
end

-- Straight rays from one point: a fan of thin bars that can tilt upward and turn while they grow (holy rays, frost cracks).
builders.rays = function(handle, spec, ctx)
	local colors = spec.colors or { spec.color }
	local count = spec.count or 8
	local length = spec.radius or ctx.radius * (spec.scale or 1)
	local time = spec.time or 0.5
	local tilt = math.rad(spec.tilt or 0)
	local spin = math.rad(spec.spin or 0)
	local lift = spec.lift or 0.1
	local width = spec.width or 0.3
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, time + 0.25)
	for index = 1, count do
		local part = layerPart(handle)
		if not part then
			break
		end
		part.Color = colors[(index - 1) % #colors + 1]
		part.Transparency = 1
		local heading = (index - 1) / count * math.pi * 2 + (math.random() - 0.5) * 0.4
		local reach = length * (0.75 + 0.25 * math.random())
		table.insert(handle.steps, function(now)
			local age = now - start
			if age < 0 then
				part.Transparency = 1
				return
			end
			local t = math.clamp(age / time, 0, 1)
			local h = heading + spin * age
			local dir = Vector3.new(math.cos(h) * math.cos(tilt), math.sin(tilt), math.sin(h) * math.cos(tilt))
			local base = anchorOf(spec, ctx) - FEET + Vector3.new(0, lift, 0)
			local len = math.max(reach * ease(spec.ease, t), 0.1)
			local mid = base + dir * (len / 2)
			part.Size = Vector3.new(width, width, len)
			part.CFrame = CFrame.lookAt(mid, mid + dir)
			local fade = math.max(0, (t - 0.6) / 0.4)
			part.Transparency = fade + (1 - fade) * 0.05
		end)
	end
end

-- A neon bolt that shoots from the first point to the last: it grows along the path (eased), holds, then fades.
-- Lay residue behind it with a `trail` layer.
builders.bolt = function(handle, spec, ctx)
	local points = ctx.points
	if not points or #points < 2 then
		return
	end
	local a, b = points[1], points[#points]
	local grow = spec.grow or 0
	local time = spec.time or 0.3
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, grow + time + 0.1)
	local bolts = {
		{ part = layerPart(handle), color = spec.color, width = spec.width or 0.5, base = 0 },
		{ part = layerPart(handle), color = spec.glowColor or spec.color, width = spec.glowWidth or 2, base = spec.glowTransparency or 0.6 },
	}
	for _, bolt in ipairs(bolts) do
		if bolt.part then
			bolt.part.Color = bolt.color
			bolt.part.Transparency = 1
		end
	end
	table.insert(handle.steps, function(now)
		local age = now - start
		if age < 0 then
			return
		end
		local tip = a:Lerp(b, grow > 0 and ease(spec.ease, age / grow) or 1)
		local length = (tip - a).Magnitude
		local fade = math.clamp((age - grow) / time, 0, 1)
		for _, bolt in ipairs(bolts) do
			if bolt.part then
				if length < 0.1 then
					bolt.part.Transparency = 1
				else
					bolt.part.Size = Vector3.new(bolt.width, bolt.width, length)
					bolt.part.CFrame = CFrame.lookAt((a + tip) / 2, tip)
					bolt.part.Transparency = bolt.base + (1 - bolt.base) * fade * fade
				end
			end
		end
	end)
end

-- Residue: slabs laid along the path. Each one appears as the front passes it, then fades slowly. `time` is how long
-- the front takes to cross (match the projectile), `fade` how long each slab lingers.
builders.trail = function(handle, spec, ctx)
	local points = ctx.points
	if not points or #points < 2 then
		return
	end
	local a, b = points[1], points[#points]
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local dir = (b - a).Unit
	local count = spec.count or 8
	local time = spec.time or 0.3
	local fade = spec.fade or 1
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, time + fade)
	local segment = length / count * 1.1
	for index = 1, count do
		local part = layerPart(handle)
		if not part then
			break
		end
		part.Color = spec.color
		part.Material = Enum.Material[spec.material or "Neon"]
		part.Transparency = 1
		part.Size = Vector3.new(spec.width or 1.5, spec.height or 0.2, segment)
		local frac = (index - 0.5) / count
		local mid = a:Lerp(b, frac)
		local cframe = CFrame.lookAt(mid, mid + dir)
		local passAt = start + frac * time
		table.insert(handle.steps, function(now)
			local age = now - passAt
			if age < 0 then
				part.Transparency = 1
				return
			end
			part.CFrame = cframe
			local f = math.clamp(age / fade, 0, 1)
			part.Transparency = f * f
		end)
	end
end

-- Jagged lightning. Links come from the cast's points (a chain), or with `arcs` from random arcs out of the caster. The
-- shape is rolled again every `refresh` seconds so the bolt crackles instead of sitting still, then it fades over `time`.
builders.lightning = function(handle, spec, ctx)
	local links = {}
	if spec.arcs then
		local center = anchorOf(spec, ctx)
		local radius = spec.radius or ctx.radius * (spec.scale or 1)
		for _ = 1, spec.arcs do
			local heading = math.random() * math.pi * 2
			local reach = radius * (0.6 + 0.4 * math.random())
			local target = center + Vector3.new(math.cos(heading) * reach, (math.random() - 0.5) * 3, math.sin(heading) * reach)
			table.insert(links, { a = center, b = target })
		end
	elseif ctx.points then
		for index = 1, #ctx.points - 1 do
			table.insert(links, { a = ctx.points[index], b = ctx.points[index + 1] })
		end
	end
	if #links == 0 then
		return
	end
	local segments = spec.segments or 5
	local jitter = spec.jitter or 1.2
	local width = spec.width or 0.35
	local time = spec.time or 0.3
	local refresh = spec.refresh or 0.05
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, time + 0.1)
	local bolts = {}
	for _, link in ipairs(links) do
		local parts = {}
		for _ = 1, segments do
			local part = layerPart(handle)
			if not part then
				break
			end
			part.Color = spec.color
			part.Transparency = 1
			table.insert(parts, part)
		end
		table.insert(bolts, { a = link.a, b = link.b, parts = parts })
	end
	local nextRoll = start
	table.insert(handle.steps, function(now)
		local age = now - start
		if age < 0 then
			return
		end
		if age >= time then
			for _, bolt in ipairs(bolts) do
				for _, part in ipairs(bolt.parts) do
					part.Transparency = 1
				end
			end
			return
		end
		if now < nextRoll then
			return
		end
		nextRoll = now + refresh
		local fade = math.clamp((age - time * 0.5) / (time * 0.5), 0, 1)
		for _, bolt in ipairs(bolts) do
			local count = #bolt.parts
			local pts = { bolt.a }
			for k = 1, count - 1 do
				local offset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * jitter
				table.insert(pts, bolt.a:Lerp(bolt.b, k / count) + offset)
			end
			table.insert(pts, bolt.b)
			for s, part in ipairs(bolt.parts) do
				local p, q = pts[s], pts[s + 1]
				local len = math.max((q - p).Magnitude, 0.1)
				part.Size = Vector3.new(width, width, len)
				part.CFrame = CFrame.lookAt((p + q) / 2, q)
				part.Transparency = math.clamp(fade + math.random() * 0.15, 0, 1)
			end
		end
	end)
end

-- A column of light that rises out of the ground, or with `descend` drops from the sky to it. Then it fades.
builders.pillar = function(handle, spec, ctx)
	local part = layerPart(handle)
	if not part then
		return
	end
	part.Color = spec.color
	part.Transparency = 1
	local height = spec.height or 14
	local time = spec.time or 0.4
	local width = spec.width or 1.2
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, time + 0.25)
	table.insert(handle.steps, function(now)
		local age = now - start
		if age < 0 then
			part.Transparency = 1
			return
		end
		local t = math.clamp(age / time, 0, 1)
		local e = ease(spec.ease, t)
		local top = spec.descend and height * (1 - e) or height * e
		local len = math.max(top, 0.1)
		local w = width * (1 - 0.4 * t)
		local ground = anchorOf(spec, ctx) - FEET
		part.Size = Vector3.new(w, len, w)
		part.CFrame = CFrame.new(ground + Vector3.new(0, len / 2, 0))
		local fade = math.max(0, (t - 0.6) / 0.4)
		part.Transparency = 0.1 + 0.9 * fade
	end)
end

-- A glowing ball with a soft halo. It grows (eased), or with `shrink` implodes into its point. `perPoint` puts one on
-- every point of the cast (one per chain strike); otherwise it sits on the anchor (`at = "end"` for the end of a line).
builders.orb = function(handle, spec, ctx)
	local anchors = { false }
	if spec.perPoint and ctx.points then
		anchors = ctx.points
	end
	local time = spec.time or 0.4
	local start = ctx.start + (spec.delay or 0)
	local size = spec.size or 1.2
	keepUntil(handle, spec, ctx, time + 0.1)
	for _, point in ipairs(anchors) do
		local core = layerPart(handle)
		local halo = layerPart(handle)
		if not (core and halo) then
			break
		end
		core.Shape = Enum.PartType.Ball
		core.Color = spec.color
		core.Transparency = 1
		halo.Shape = Enum.PartType.Ball
		halo.Color = spec.glowColor or spec.color
		halo.Transparency = 1
		table.insert(handle.steps, function(now)
			local age = now - start
			if age < 0 then
				core.Transparency = 1
				halo.Transparency = 1
				return
			end
			local t = math.clamp(age / time, 0, 1)
			local e = ease(spec.ease, t)
			local s = math.max(size * (spec.shrink and (1 - e) or e), 0.05)
			local center = (point or anchorOf(spec, ctx)) + Vector3.new(0, spec.height or 0, 0)
			local fade = math.max(0, (t - 0.5) / 0.5)
			core.Size = Vector3.one * s
			core.CFrame = CFrame.new(center)
			core.Transparency = fade * fade
			halo.Size = Vector3.one * s * 2.4
			halo.CFrame = core.CFrame
			halo.Transparency = math.min(1, 0.7 + 0.3 * fade)
		end)
	end
end

-- Crystal spikes in a ring that grow up out of the ground (eased with a small overshoot), can turn slowly, then hold.
builders.shards = function(handle, spec, ctx)
	local count = spec.count or 10
	local radius = spec.radius or ctx.radius * (spec.scale or 1)
	local height = spec.height or 4
	local grow = spec.time or 0.5
	local colors = spec.colors or { spec.color }
	local start = ctx.start + (spec.delay or 0)
	keepUntil(handle, spec, ctx, grow + 0.2)
	local spikes = {}
	for index = 1, count do
		local part = layerPart(handle)
		if not part then
			break
		end
		part.Material = Enum.Material[spec.material or "Glass"]
		part.Color = colors[(index - 1) % #colors + 1]
		part.Transparency = 1
		table.insert(spikes, {
			part = part,
			index = index,
			width = (spec.width or 0.6) * (0.7 + 0.6 * math.random()),
			height = height * (0.7 + 0.6 * math.random()),
			lean = math.rad((math.random() - 0.5) * 16),
		})
	end
	table.insert(handle.steps, function(now)
		local age = now - start
		if age < 0 then
			return
		end
		local g = ease("outBack", age / grow)
		local ground = anchorOf(spec, ctx) - FEET
		local turn = math.rad(spec.spin or 0) * age
		for _, spike in ipairs(spikes) do
			local angle = (spike.index - 1) / count * math.pi * 2 + turn
			local len = math.max(spike.height * g, 0.05)
			local base = ground + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			spike.part.Size = Vector3.new(spike.width, len, spike.width * 0.6)
			spike.part.CFrame = CFrame.new(base + Vector3.new(0, len / 2, 0)) * CFrame.Angles(0, -angle, 0) * CFrame.Angles(spike.lean, 0, 0)
			spike.part.Transparency = 0.15
		end
	end)
end

-- Chunks thrown out on arcs: they fly, fall under gravity, land on the ground and fade. Each one spins.
builders.debris = function(handle, spec, ctx)
	local colors = spec.colors or { Color3.fromRGB(120, 90, 60) }
	local count = spec.count or 10
	local sizes = spec.size or { 0.4, 0.9 }
	local flight = spec.flight or { 0.7, 1.1 }
	local speed = spec.speed or { 8, 14 }
	local up = spec.up or 14
	local gravity = spec.gravity or 40
	local start = ctx.start + (spec.delay or 0)
	local origin = anchorOf(spec, ctx) - FEET
	keepUntil(handle, spec, ctx, flight[2] + 0.8)
	for index = 1, count do
		local part = layerPart(handle)
		if not part then
			break
		end
		part.Material = Enum.Material[spec.material or "Slate"]
		part.Color = colors[(index - 1) % #colors + 1]
		part.Transparency = 1
		local s = sizes[1] + (sizes[2] - sizes[1]) * math.random()
		part.Size = Vector3.new(s, s * (0.5 + 0.5 * math.random()), s)
		local heading = math.random() * math.pi * 2
		local horizontal = speed[1] + (speed[2] - speed[1]) * math.random()
		local vx, vz = math.cos(heading) * horizontal, math.sin(heading) * horizontal
		local vy = up * (0.6 + 0.8 * math.random())
		local air = flight[1] + (flight[2] - flight[1]) * math.random()
		local spinSpeed = math.rad(200 + 300 * math.random()) * (math.random() < 0.5 and -1 or 1)
		table.insert(handle.steps, function(now)
			local age = now - start
			if age < 0 then
				part.Transparency = 1
				return
			end
			local t = math.min(age, air)
			local pos = origin + Vector3.new(vx * t, vy * t - 0.5 * gravity * t * t, vz * t)
			pos = Vector3.new(pos.X, math.max(pos.Y, origin.Y + s * 0.5), pos.Z)
			part.CFrame = CFrame.new(pos) * CFrame.Angles(spinSpeed * t, spinSpeed * 0.5 * t, 0)
			part.Transparency = math.min(1, math.max(0, (age - air) / 0.6))
		end)
	end
end

--- Ends a handle: stops its emitters and lights, fades its parts, and returns the parts to the pool after LINGER seconds.
local function endHandle(handle: any)
	local index = table.find(handles, handle)
	if index then
		table.remove(handles, index)
	end
	liveEmitters = math.max(0, liveEmitters - handle.emitters)
	handle.emitters = 0
	handle.steps = {}
	local parts = handle.parts
	handle.parts = {}
	for _, part in ipairs(parts) do
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("ParticleEmitter") or child:IsA("SpotLight") then
				child.Enabled = false
			end
		end
		if part.Transparency < 1 then
			TweenService:Create(part, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
	end
	task.delay(LINGER, function()
		for _, part in ipairs(parts) do
			release("layer", part)
		end
	end)
end

local function endHandlesByKey(key: string)
	for index = #handles, 1, -1 do
		if handles[index].key == key then
			endHandle(handles[index])
		end
	end
end

local function layerStep()
	local now = os.clock()
	for index = #handles, 1, -1 do
		local handle = handles[index]
		local root = handle.root
		local humanoid = root and root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
		local dead = handle.follow and not (humanoid and humanoid.Health > 0)
		if now >= handle.endsAt or dead then
			endHandle(handle)
		else
			for _, step in ipairs(handle.steps) do
				step(now)
			end
		end
	end
	if #handles == 0 and layerConnection then
		layerConnection:Disconnect()
		layerConnection = nil
	end
end

--- Starts the layered effect for one cast. `data.points` (line / chain / dash) and `data.duration` are optional.
local function playLayered(caster: Player, data: any, ability: any, fx: any)
	local origin = data.origin :: Vector3
	local root = caster.Character and caster.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local zone = ability.zone
	local follow = zone ~= nil and zone.follow ~= false
	local key = zone and zoneKey(caster, data.abilityId) or nil
	if key then
		endHandlesByKey(key) -- a recast replaces the old effect
	end
	local points = data.points
	local handle = { key = key, root = root, follow = follow, parts = {}, steps = {}, emitters = 0, endsAt = 0 }
	local ctx = {
		start = os.clock(),
		radius = ability.shape and (ability.shape.radius or ability.shape.reach or ability.shape.length) or 10,
		points = points,
		center = function(): Vector3
			if follow and root and root.Parent then
				return root.Position
			end
			return origin
		end,
		endPoint = function(): Vector3
			return points and points[#points] or origin
		end,
	}
	handle.endsAt = ctx.start + (zone and (data.duration or zone.duration) or 0.5)
	for _, layer in ipairs(fx.layers) do
		local build = builders[layer.kind]
		if build then
			build(handle, layer, ctx)
		else
			warn(("[AbilityController] %s: unknown fx layer '%s'"):format(tostring(data.abilityId), tostring(layer.kind)))
		end
	end
	table.insert(handles, handle)
	if not layerConnection then
		layerConnection = RunService.Heartbeat:Connect(layerStep)
	end
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
	if ability then
		-- camera feel: an ability's shake (AbilityConfig.fx.<id>.shake: a preset name, or false for none), and a blink whip
		local fxConfig = ability.fx and AbilityConfig.fx[ability.fx]
		local shake = fxConfig and fxConfig.shake
		if shake ~= false then
			CameraFeel.shake(shake or CameraConfig.shake.abilityPreset, origin)
		end
		if caster == player and ability.dash and data.points and #data.points >= 2 then
			CameraFeel.whip(data.points[2] - data.points[1])
			CameraFeel.punchFov(CameraConfig.blink.punchFov)
			CameraFeel.trail(CameraConfig.blink.trailSeconds)
		end
	end
	if not ability or tooFar(origin) then
		return
	end
	playSound(origin, ability.sound and AbilityConfig.sounds[ability.sound])
	local fx = ability.fx and AbilityConfig.fx[ability.fx]
	if not fx then
		return
	end
	if fx.layers then
		if ability.zone then
			endZoneByKey(zoneKey(caster, data.abilityId)) -- layers replace the older zone effect
		end
		playLayered(caster, data, ability, fx)
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
		endHandlesByKey(zoneKey(data.caster, data.abilityId))
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
	for index = #handles, 1, -1 do
		local key = handles[index].key
		if key and key:match("^" .. leaving.UserId .. "/") then
			endHandle(handles[index])
		end
	end
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
