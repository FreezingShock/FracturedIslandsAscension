--[[
	DropFXController (LocalScript)
	Place inside: StarterPlayerScripts

	The glow and particles on dropped items (instances tagged "DropTooltip"), in the drop's rarity colour: a PointLight
	(light in ALL directions, the right type for a glowing item), rising motes, a ground ring, a light pillar, a starburst,
	and one-shot bursts when a fresh drop appears / is picked up. Every number and which rarity gets what is in
	Modules/Config/DropFXConfig (library -> rarity -> item).

	Visual only: each client builds the effect from the drop's replicated attributes (Rarity, DropColor, ItemId), so the
	server sends nothing and every player sees the same thing. The rigs live in workspace.DropFXRigs (client only), are
	POOLED, and are capped: lights on the nearest maxLights drops, particles on the nearest maxEmitterDrops, nothing past
	fxRange studs; light and rate fade out over the last fadeBand studs.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TAG = "DropTooltip"
local MERGE_TAG = "ItemDropMerge"

local Modules = ReplicatedStorage:WaitForChild("Modules")
local FXConfig = require(Modules:WaitForChild("Config"):WaitForChild("DropFXConfig")) :: any
local EnemyConfig = require(Modules:WaitForChild("EnemyConfig")) :: any
local Items = require(Modules:WaitForChild("Items")) :: any
local STACK = require(Modules:WaitForChild("Config"):WaitForChild("DropStackConfig")) :: any
local Debris = game:GetService("Debris")
local TEX = EnemyConfig.textures
local LIMITS = FXConfig.limits

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

local rigsFolder = workspace:FindFirstChild("DropFXRigs") or Instance.new("Folder")
rigsFolder.Name = "DropFXRigs"
rigsFolder.Parent = workspace

local entries: { [Instance]: any } = {}
local closing: { any } = {}
local pool: { any } = {}
local scanClock = 0

-- ===================== BUILDING BLOCKS =====================
local function seq(values: { number }): NumberSequence
	local n = #values
	if n == 1 then
		return NumberSequence.new(values[1])
	end
	local points = {}
	for i, v in ipairs(values) do
		points[i] = NumberSequenceKeypoint.new((i - 1) / (n - 1), v)
	end
	return NumberSequence.new(points)
end

local function range(values: { number }): NumberRange
	return NumberRange.new(values[1], values[2] or values[1])
end

local function baseColor(spec: any, dropColor: Color3): Color3
	local c = spec.color
	if c == "white" then
		return WHITE
	elseif type(c) == "string" and c ~= "rarity" then
		local ok, parsed = pcall(Color3.fromHex, c)
		return ok and parsed or dropColor
	end
	return dropColor
end

local function brightColor(spec: any, dropColor: Color3): Color3
	local base = baseColor(spec, dropColor)
	local mix = spec.brighten or 0
	return mix > 0 and base:Lerp(WHITE, mix) or base
end

local function attachment(name: string, parent: Instance, offset: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = offset
	a.Parent = parent
	return a
end

local function emitter(name: string, parent: Instance): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Name = name
	p.Enabled = false
	p.Rate = 0
	p.Parent = parent
	return p
end

local function buildRig()
	local part = Instance.new("Part")
	part.Name = "Rig"
	part.Size = Vector3.new(1.2, 0.2, 1.2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	local mid = attachment("Mid", part, Vector3.zero)
	local ground = attachment("Ground", part, Vector3.new(0, LIMITS.groundOffset - LIMITS.rigLift, 0))
	local top = attachment("Top", part, Vector3.new(0, 4, 0))
	local flareAt = attachment("FlareAt", part, Vector3.new(0, 1, 0))
	local light = Instance.new("PointLight")
	light.Name = "DropGlow"
	light.Enabled = false
	light.Shadows = false
	light.Parent = part
	local beam = Instance.new("Beam")
	beam.Name = "Pillar"
	beam.Attachment0 = ground
	beam.Attachment1 = top
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Enabled = false
	beam.Parent = part
	return {
		part = part,
		ground = ground,
		top = top,
		flareAt = flareAt,
		light = light,
		beam = beam,
		motes = emitter("Motes", mid),
		ring = emitter("Ring", ground),
		flare = emitter("Flare", flareAt),
		burst = emitter("Burst", mid),
		burstFlare = emitter("BurstFlare", flareAt),
		shock = emitter("Shock", ground),
		lightK = 0,
		phase = math.random() * math.pi * 2,
	}
end

-- ===================== CONFIGURE A RIG FOR ONE DROP =====================
local function configure(rig: any, e: any)
	local presets, color = e.presets, e.color
	rig.entry = e
	rig.closing = false
	rig.flash = nil

	local glow = presets.glow
	rig.glow = glow
	if glow then
		rig.light.Color = brightColor(glow, color)
		rig.light.Range = glow.range
	end

	local m = presets.motes
	rig.moteRate = m and m.rate or 0
	rig.motes.Enabled = m ~= nil
	if m then
		local p = rig.motes
		p.Texture = TEX[m.texture] or ""
		p.Lifetime = range(m.lifetime)
		p.Speed = range(m.speed)
		p.SpreadAngle = Vector2.new(m.spread, m.spread)
		p.EmissionDirection = Enum.NormalId.Top
		p.Acceleration = Vector3.new(0, m.acceleration, 0)
		p.Size = seq(m.size)
		p.Transparency = seq(m.transparency)
		p.Color = ColorSequence.new(brightColor(m, color), baseColor(m, color))
		p.LightEmission = m.lightEmission
		p.Rotation = NumberRange.new(0, 360)
		p.Orientation = Enum.ParticleOrientation.FacingCamera
	end

	local r = presets.ring
	rig.ringRate = r and r.rate or 0
	rig.ring.Enabled = r ~= nil
	if r then
		local p = rig.ring
		p.Texture = TEX[r.texture] or ""
		p.Lifetime = NumberRange.new(r.lifetime)
		p.Speed = NumberRange.new(0.05, 0.05) -- tiny upward speed: VelocityPerpendicular turns it into a flat disc on the floor
		p.EmissionDirection = Enum.NormalId.Top
		p.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		p.SpreadAngle = Vector2.zero
		p.Size = seq(r.size)
		p.Transparency = seq(r.transparency)
		p.Color = ColorSequence.new(brightColor(r, color), baseColor(r, color))
		p.LightEmission = r.lightEmission
		p.Acceleration = Vector3.zero
	end

	local f = presets.flare
	rig.flareRate = f and f.rate or 0
	rig.flare.Enabled = f ~= nil
	if f then
		local p = rig.flare
		rig.flareAt.Position = Vector3.new(0, f.lift, 0)
		p.Texture = TEX[f.texture] or ""
		p.Lifetime = NumberRange.new(f.lifetime)
		p.Speed = NumberRange.new(0, 0)
		p.Size = seq(f.size)
		p.Transparency = seq(f.transparency)
		p.Color = ColorSequence.new(brightColor(f, color), baseColor(f, color))
		p.LightEmission = f.lightEmission
		p.Rotation = NumberRange.new(0, 360)
		p.RotSpeed = NumberRange.new(-25, 25)
		p.Orientation = Enum.ParticleOrientation.FacingCamera
	end

	local pillar = presets.pillar
	rig.beam.Enabled = pillar ~= nil
	rig.pillar = pillar
	if pillar then
		rig.top.Position = Vector3.new(0, rig.ground.Position.Y + pillar.height, 0)
		rig.beam.Width0, rig.beam.Width1 = pillar.width[1], pillar.width[2]
		rig.beam.Transparency = seq(pillar.transparency)
		rig.beam.Color = ColorSequence.new(brightColor(pillar, color), baseColor(pillar, color))
		rig.beam.LightEmission = pillar.lightEmission
	end
end

--- One-shot burst of motes (+ starbursts) at the rig.
local function emitBurst(rig: any, spec: any, color: Color3)
	if not spec then
		return
	end
	local p = rig.burst
	p.Texture = TEX[spec.texture] or ""
	p.Lifetime = range(spec.lifetime)
	p.Speed = range(spec.speed)
	p.SpreadAngle = Vector2.new(180, 180)
	p.EmissionDirection = Enum.NormalId.Top
	p.Drag = 2.5
	p.Size = seq(spec.size)
	p.Transparency = seq({ 0, 1 })
	p.Color = ColorSequence.new(brightColor(spec, color), baseColor(spec, color))
	p.LightEmission = 1
	p:Emit(spec.count)
	if (spec.flareCount or 0) > 0 then
		local s = rig.burstFlare
		s.Texture = TEX.flare or ""
		s.Lifetime = NumberRange.new(0.45, 0.6)
		s.Speed = NumberRange.new(0, 0)
		s.Size = seq({ 0, spec.flareSize, 0 })
		s.Transparency = seq({ 0.3, 0.15, 1 })
		s.Color = ColorSequence.new(brightColor(spec, color), baseColor(spec, color))
		s.LightEmission = 1
		s.Rotation = NumberRange.new(0, 360)
		s:Emit(spec.flareCount)
	end
end

local joinedAt = os.clock()

--- The item pop at a world position (3D, so it fades with distance). Skipped past fxRange.
local function playPop(at: Vector3, pitch: number)
	local pop = FXConfig.sounds.pop
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if pop.id == "" or not root or (at - root.Position).Magnitude > LIMITS.fxRange then
		return
	end
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = pop.id
	s.Volume = pop.volume
	s.PlaybackSpeed = pitch
	s.RollOffMaxDistance = pop.range
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 2)
end

local function randomPitch(kind: string): number
	local p = FXConfig.sounds[kind].pitch
	return p[1] + math.random() * (p[2] - p[1])
end

--- An item landed in this stack: a burst that grows with the stack, a ground shock ring, a light flash and a pop sound
--- that climbs in pitch as the stack fills. A full stack gets `full` on top.
local function emitStack(e: any)
	local count = e.inst:GetAttribute("Count") or 1
	local pitch = FXConfig.sounds.stack.pitch
	playPop(e.rest, pitch[1] + (pitch[2] - pitch[1]) * math.clamp(count / STACK.maxStack, 0, 1)) -- heard even without a rig
	local rig, spec = e.rig, e.presets.stack
	if not rig or not spec then
		return
	end
	local full = count >= STACK.maxStack and spec.full or nil
	local color = e.color
	local burst = {
		texture = spec.texture,
		count = math.floor(math.min(spec.maxCount, spec.count + count * spec.perCount) * (full and full.countMult or 1)),
		speed = spec.speed,
		lifetime = spec.lifetime,
		size = spec.size,
		color = spec.color,
		brighten = spec.brighten,
		flareCount = full and full.flareCount or spec.flareCount,
		flareSize = (full and full.flareSize or spec.flareSize) + count * spec.flareGrow,
	}
	emitBurst(rig, burst, color)
	local ringSize = full and full.ringSize or spec.ringSize
	if ringSize and ringSize > 0 then
		local p = rig.shock
		p.Texture = TEX.ring or ""
		p.Lifetime = NumberRange.new(0.45)
		p.Speed = NumberRange.new(0.05, 0.05)
		p.EmissionDirection = Enum.NormalId.Top
		p.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		p.SpreadAngle = Vector2.zero
		p.Size = seq({ 0.4, ringSize })
		p.Transparency = seq({ 0.15, 1 })
		p.Color = ColorSequence.new(brightColor(spec, color), baseColor(spec, color))
		p.LightEmission = 1
		p:Emit(1)
	end
	local flash = full and full.flash or spec.flash
	if flash then
		rig.light.Color = brightColor(spec, color)
		rig.light.Range = math.max(rig.light.Range, 10)
		rig.flash = { t0 = os.clock(), peak = flash.brightness, time = flash.time }
	end
end

local function silence(rig: any)
	rig.light.Enabled = false
	rig.beam.Enabled = false
	rig.flash = nil
	for _, p in ipairs({ rig.motes, rig.ring, rig.flare, rig.burst, rig.burstFlare, rig.shock }) do
		p.Enabled = false
		p.Rate = 0
		p:Clear()
	end
end

-- ===================== ENTRIES =====================
local function restOf(inst: Instance): Vector3
	if inst:IsA("Model") then
		local base = inst:GetAttribute("BasePos")
		if inst:GetAttribute("Settled") and typeof(base) == "Vector3" then
			return base
		end
		return inst:GetPivot().Position
	end
	return (inst :: BasePart).Position
end

local function dropColorOf(inst: Instance, rarity: number): Color3
	local hex = inst:GetAttribute("DropColor")
	if type(hex) == "string" then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return color
		end
	end
	local def = Items.getRarity(rarity)
	return def and def.color or WHITE
end

local function register(inst: Instance)
	if entries[inst] or not (inst:IsA("BasePart") or inst:IsA("Model")) then
		return
	end
	local rarity = inst:GetAttribute("Rarity") or 0
	local e
	e = {
		inst = inst,
		rarity = rarity,
		color = dropColorOf(inst, rarity),
		presets = FXConfig.resolve(rarity, inst:GetAttribute("ItemId")),
		born = os.clock(),
		rest = restOf(inst),
		dist = math.huge,
	}
	entries[inst] = e
	if os.clock() - joinedAt > FXConfig.sounds.learnWindow then
		playPop(e.rest, randomPitch("drop")) -- a drop appeared
	end
	e.stackConn = inst:GetAttributeChangedSignal("MergeSeq"):Connect(function()
		emitStack(e)
	end)
end

local function releaseRig(e: any)
	local rig = e.rig
	if not rig then
		return
	end
	e.rig = nil
	rig.entry = nil
	silence(rig)
	rig.part.Parent = nil
	if #pool < LIMITS.poolSize then
		table.insert(pool, rig)
	else
		rig.part:Destroy()
	end
end

local function acquireRig(e: any)
	local rig = table.remove(pool) or buildRig()
	configure(rig, e)
	rig.lightK = 0
	rig.part.CFrame = CFrame.new(e.rest + Vector3.new(0, LIMITS.rigLift, 0))
	rig.part.Parent = rigsFolder
	e.rig = rig
	if os.clock() - e.born <= LIMITS.spawnWindow then
		emitBurst(rig, e.presets.spawn, e.color)
	end
end

-- Picking items up in quick succession climbs in pitch (FXConfig.sounds.pickupStreak), per player.
local streaks: { [number]: { at: number, n: number } } = {}

local function streakPitch(userId: number): number
	local cfg = FXConfig.sounds.pickupStreak
	local now = os.clock()
	local s = streaks[userId]
	if s and now - s.at <= cfg.window then
		s.n += 1
	else
		s = { n = 0, at = now }
		streaks[userId] = s
	end
	s.at = now
	return cfg.pitch[1] + (cfg.pitch[2] - cfg.pitch[1]) * math.clamp(s.n / cfg.steps, 0, 1)
end

--- A picked-up item has just flown into the player: the pop (rising pitch for a quick run of pickups), a burst in the item's
--- colour and a small light flash at the player's chest. Every rarity gets the burst (its own preset, else the library one).
local function arrive(e: any, userId: number)
	local who = Players:GetPlayerByUserId(userId)
	local theirRoot = who and who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local at = theirRoot and (theirRoot.Position + Vector3.new(0, STACK.pickup.chest, 0)) or e.rest
	playPop(at, streakPitch(userId))
	local mine = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not mine or (at - mine.Position).Magnitude > LIMITS.fxRange then
		return
	end
	local spec = e.presets.pickup or FXConfig.library.pickup
	local rig = table.remove(pool) or buildRig()
	configure(rig, { presets = {}, color = e.color }) -- nothing persistent: it only carries the burst
	rig.part.Position = at
	rig.part.Parent = rigsFolder
	emitBurst(rig, spec, e.color)
	rig.light.Color = brightColor(spec, e.color)
	rig.light.Range = 8
	rig.light.Brightness = 2
	rig.light.Enabled = true
	rig.closing = true
	rig.closeAt = os.clock() + 1.0
	table.insert(closing, rig)
end

local function unregister(inst: Instance)
	local e = entries[inst]
	if not e then
		return
	end
	entries[inst] = nil
	if e.stackConn then
		e.stackConn:Disconnect()
	end
	local rig = e.rig
	local pickedBy = inst:GetAttribute("PickupBy")
	if pickedBy then
		-- picked up: it flies to the player first (ItemDropRenderer); the pop and the burst happen where it lands
		if rig then
			releaseRig(e)
		end
		task.delay(STACK.pickup.flyTime, function()
			arrive(e, pickedBy)
		end)
		return
	end
	if rig and inst:GetAttribute("MergeInto") then
		-- it did not leave, it is flying into a stack: no goodbye burst
		releaseRig(e)
		return
	end
	if not inst:GetAttribute("MergeInto") then
		playPop(e.rest, randomPitch("pickup")) -- picked up (or expired)
	end
	if rig then
		-- picked up / expired: one last burst where it stood, the light fades, then the rig is recycled
		e.rig = nil
		rig.entry = nil
		rig.closing = true
		rig.closeAt = os.clock() + 1.2
		rig.moteRate, rig.ringRate, rig.flareRate = 0, 0, 0
		for _, p in ipairs({ rig.motes, rig.ring, rig.flare }) do
			p.Rate = 0
		end
		rig.beam.Enabled = false
		emitBurst(rig, e.presets.pickup, e.color)
		table.insert(closing, rig)
	end
end

for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
	register(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(unregister)

-- an item flying into a stack leaves a glowing trail in its colour
local function trail(model: Instance)
	local body = model:FindFirstChild("Body")
	if not (body and body:IsA("BasePart")) then
		return
	end
	local hex = model:GetAttribute("DropColor")
	local ok, color = pcall(Color3.fromHex, type(hex) == "string" and hex or "FFFFFF")
	color = (ok and color or WHITE):Lerp(WHITE, 0.35)
	local a0 = attachment("TrailA", body, Vector3.new(0, 0.3, 0))
	local a1 = attachment("TrailB", body, Vector3.new(0, -0.3, 0))
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Lifetime = 0.2
	t.LightEmission = 1
	t.Color = ColorSequence.new(color)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	t.Parent = body
end
for _, model in ipairs(CollectionService:GetTagged(MERGE_TAG)) do
	trail(model)
end
CollectionService:GetInstanceAddedSignal(MERGE_TAG):Connect(trail)

-- ===================== SCAN + UPDATE =====================
local function fadeOf(dist: number): number
	local start = LIMITS.fxRange - LIMITS.fadeBand
	local u = math.clamp((dist - start) / math.max(LIMITS.fadeBand, 0.001), 0, 1)
	return 1 - u * u * (3 - 2 * u)
end

local function scan()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local list = {}
	for _, e in pairs(entries) do
		e.rest = restOf(e.inst)
		if root and next(e.presets) ~= nil then
			e.dist = (e.rest - root.Position).Magnitude
			if e.dist <= LIMITS.fxRange then
				table.insert(list, e)
			end
		else
			e.dist = math.huge
		end
		e.wantLight, e.wantEmit = false, false
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	local cap = math.max(LIMITS.maxLights, LIMITS.maxEmitterDrops)
	for rank, e in ipairs(list) do
		if rank <= cap then
			e.wantLight = rank <= LIMITS.maxLights
			e.wantEmit = rank <= LIMITS.maxEmitterDrops
			if not e.rig then
				acquireRig(e)
			end
		end
	end
	for _, e in pairs(entries) do
		if e.rig and not (e.wantLight or e.wantEmit) then
			releaseRig(e)
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	scanClock += dt
	if scanClock >= LIMITS.scanEvery then
		scanClock = 0
		scan()
	end
	local now = os.clock()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, e in pairs(entries) do
		local rig = e.rig
		if rig then
			local pos = e.rest + Vector3.new(0, LIMITS.rigLift, 0)
			if rig.part.Position ~= pos then
				rig.part.Position = pos
			end
			local dist = root and (e.rest - root.Position).Magnitude or e.dist
			local fade = fadeOf(dist)
			local glow = rig.glow
			local target = (glow and e.wantLight) and fade or 0
			rig.lightK += (target - rig.lightK) * math.min(1, dt * 8)
			if glow and rig.lightK > 0.01 then
				local pulse = 1 + glow.pulse.amount * math.sin(now * glow.pulse.speed + rig.phase)
				rig.light.Brightness = glow.brightness * pulse * rig.lightK
				rig.light.Enabled = true
			else
				rig.light.Enabled = false
			end
			local emit = e.wantEmit and fade or 0
			rig.motes.Rate = rig.moteRate * emit
			rig.ring.Rate = rig.ringRate * emit
			rig.flare.Rate = rig.flareRate * emit
			local flash = rig.flash
			if flash then
				local k = 1 - (now - flash.t0) / flash.time
				if k > 0 then
					rig.light.Brightness = (rig.light.Enabled and rig.light.Brightness or 0) + flash.peak * k * k
					rig.light.Enabled = true
				else
					rig.flash = nil
				end
			end
			rig.beam.Enabled = rig.pillar ~= nil and emit > 0.05
			if rig.pillar then
				rig.beam.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1 - (1 - rig.pillar.transparency[1]) * emit),
					NumberSequenceKeypoint.new(1, rig.pillar.transparency[2]),
				})
			end
		end
	end
	for i = #closing, 1, -1 do
		local rig = closing[i]
		local left = rig.closeAt - now
		if left <= 0 then
			table.remove(closing, i)
			silence(rig)
			rig.part.Parent = nil
			rig.closing = false
			if #pool < LIMITS.poolSize then
				table.insert(pool, rig)
			else
				rig.part:Destroy()
			end
		else
			rig.light.Brightness *= math.max(0, 1 - dt * 6)
		end
	end
end)
