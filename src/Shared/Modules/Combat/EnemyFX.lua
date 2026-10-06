--[[
	EnemyFX (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	The look and sound of an enemy being hit or killed, at the point of contact. Runs locally on every client (the server
	broadcasts each hit on the WeaponHit remote; DamageNumberController calls this). Everything is built from particles
	and a few neon parts, no image assets: the numbers, colours and counts come from EnemyConfig presets.

	Effects are POOLED: each resolved preset owns a few ready-made rigs (a part + attachment + emitters + light)
	that are moved and re-fired, never rebuilt per hit. A per-client cap, a per-target cooldown for normal hits and a
	distance cut-off (EnemyConfig.limits) keep a many-target ability cheap.

	  EnemyFX.hit(data)                     data = the WeaponHit payload (point, dir, isCrit, crash, killed, target, enemyType, weaponType, weaponId)
	  EnemyFX.play(preset, enemyType, weaponType, weaponId, point, dir, priority?)   one preset at a point; dir = spray direction
	  EnemyFX.death(model, enemyType, weaponType, weaponId)                          burst at the body's centre + dissolve
	  EnemyFX.liveCount() -> number                                                   rigs currently playing (for tests)
--]]

local TweenService = game:GetService("TweenService")

local EnemyConfig = require(script.Parent:WaitForChild("EnemyConfig")) :: any
local CombatFX = require(script.Parent:WaitForChild("CombatFX")) :: any

local LIMITS = EnemyConfig.limits

local TEX = EnemyConfig.textures

local EnemyFX = {}

local folder: Folder? = nil
local function root(): Folder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "_EnemyFX"
		folder.Parent = workspace
	end
	return folder :: Folder
end

local live = 0
local lastHitOn: { [Instance]: number } = setmetatable({}, { __mode = "k" })
-- [resolved preset table] = { free = { rig }, total = number }
local pools: { [any]: any } = setmetatable({}, { __mode = "k" })

-- ===================== BUILDING A RIG =====================
local function gradient(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, color in ipairs(colors) do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

local function range(value: any, fallback: number): NumberRange
	if type(value) == "table" then
		return NumberRange.new(value[1], value[2] or value[1])
	end
	local v = value or fallback
	return NumberRange.new(v, v)
end

local function fade(from: number?, to: number?): NumberSequence
	local a, b = from or 0, to or 1
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, a),
		NumberSequenceKeypoint.new(0.55, a + (b - a) * 0.35),
		NumberSequenceKeypoint.new(1, b),
	})
end

-- per kind: texture key, additive?, orientation, flipbook?
local KIND = {
	flash = { tex = "flare", glow = 1, orient = "FacingCamera" },
	burst = { tex = "burst", glow = 1, orient = "FacingCamera", flipbook = true },
	sparks = { tex = "streak", glow = 1, orient = "VelocityParallel" },
	shards = { tex = "shard", glow = 0.6, orient = "VelocityParallel" },
	puff = { tex = "smoke", glow = 0, orient = "FacingCamera", flipbook = true },
	motes = { tex = "dot", glow = 1, orient = "FacingCamera" },
	ring = { tex = "ring", glow = 1, orient = "VelocityPerpendicular" }, -- a disc facing along the spray direction
	slash = { tex = "slash", glow = 1, orient = "FacingCamera" },
}
local KINDS = { "burst", "puff", "ring", "flash", "slash", "sparks", "shards", "motes" } -- draw order irrelevant; fixed for stability

local function emitter(parent: Instance, spec: any, kind: string): ParticleEmitter
	local def = KIND[kind]
	local e = Instance.new("ParticleEmitter")
	e.Name = kind
	e.Enabled = false
	e.Rate = 0
	e.Texture = TEX[def.tex]
	e.Color = gradient(spec.color or { Color3.new(1, 1, 1) })
	e.Lifetime = range(spec.life, 0.4)
	e.Speed = range(spec.speed, 0)
	e.SpreadAngle = Vector2.new(spec.spread or 0, spec.spread or 0)
	e.Drag = spec.drag or 0
	e.Acceleration = Vector3.new(0, (spec.rise or 0) - (spec.gravity or 0), 0)
	e.EmissionDirection = Enum.NormalId.Top
	e.LockedToPart = false
	e.LightEmission = spec.glow or def.glow
	e.LightInfluence = def.glow > 0 and 0 or 0.4
	e.Orientation = Enum.ParticleOrientation[def.orient]
	e.Rotation = spec.rotation and NumberRange.new(spec.rotation[1], spec.rotation[2]) or NumberRange.new(0, 0)
	e.RotSpeed = spec.rotSpeed and NumberRange.new(spec.rotSpeed[1], spec.rotSpeed[2]) or NumberRange.new(0, 0)

	local size = spec.size or { 1, 0 }
	if kind == "ring" or kind == "burst" or kind == "flash" or kind == "slash" then
		-- fast out, slow settle: most of the growth happens in the first quarter of the life
		local from, to = size[1], size[2] or size[1]
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, from),
			NumberSequenceKeypoint.new(0.25, from + (to - from) * 0.8),
			NumberSequenceKeypoint.new(1, to),
		})
	else
		e.Size = NumberSequence.new(size[1], size[2] or size[1])
	end

	if def.flipbook then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		e.FlipbookStartRandom = false
		e.Transparency = NumberSequence.new(spec.transparency or 0)
	elseif kind == "flash" or kind == "ring" or kind == "slash" then
		local t = spec.transparency or 0.1
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, t),
			NumberSequenceKeypoint.new(0.4, t + (1 - t) * 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
	else
		e.Transparency = fade(spec.transparency and spec.transparency[1] or 0, spec.transparency and spec.transparency[2] or 1)
	end
	e.Parent = parent
	return e
end

local function longestLife(preset: any): number
	local life = 0.2
	for _, kind in ipairs(KINDS) do
		local spec = preset[kind]
		if spec then
			local l = type(spec.life) == "table" and (spec.life[2] or spec.life[1]) or spec.life or 0.4
			life = math.max(life, l)
		end
	end
	if preset.light then
		life = math.max(life, preset.light.time or 0.2)
	end
	return life + 0.15
end

local function buildRig(preset: any): any
	local part = Instance.new("Part")
	part.Name = "EnemyFXRig"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.CFrame = CFrame.new(0, -5000, 0)

	local attachment = Instance.new("Attachment")
	attachment.Name = "Origin"
	attachment.Parent = part

	local rig: any = { part = part, emitters = {}, life = longestLife(preset), token = 0 }
	for _, kind in ipairs(KINDS) do
		local spec = preset[kind]
		if spec then
			local parent = attachment
			if kind == "ring" and spec.horizontal then
				-- a ground-style shockwave: its own attachment kept upright in the world (the others follow the spray direction)
				local upright = Instance.new("Attachment")
				upright.Name = "RingOrigin"
				upright.Parent = part
				rig.ringAttachment = upright
				parent = upright
			end
			rig.emitters[kind] = emitter(parent, spec, kind)
		end
	end
	if preset.light then
		local light = Instance.new("PointLight")
		light.Enabled = false
		light.Shadows = false
		light.Color = preset.light.color or Color3.new(1, 1, 1)
		light.Range = preset.light.range or 10
		light.Brightness = 0
		light.Parent = part
		rig.light = light
	end
	part.Parent = root()
	return rig
end

-- ===================== PLAYING =====================
local function facingFrame(point: Vector3, dir: Vector3): CFrame
	local up = math.abs(dir.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	-- the emitters fire along the attachment's Top (+Y): point +Y along dir
	return CFrame.lookAt(point, point + dir, up) * CFrame.Angles(-math.pi / 2, 0, 0)
end

local function release(preset: any, rig: any)
	live = math.max(0, live - 1)
	local pool = pools[preset]
	if pool.total > LIMITS.poolSize then
		pool.total -= 1
		rig.part:Destroy()
		return
	end
	rig.part.CFrame = CFrame.new(0, -5000, 0)
	table.insert(pool.free, rig)
end

local function fire(preset: any, point: Vector3, dir: Vector3)
	local pool = pools[preset]
	if not pool then
		pool = { free = {}, total = 0 }
		pools[preset] = pool
	end
	local rig = table.remove(pool.free)
	if not rig then
		rig = buildRig(preset)
		pool.total += 1
	end
	live += 1
	rig.token += 1
	local token = rig.token

	rig.part.CFrame = facingFrame(point, dir)
	if rig.ringAttachment then
		rig.ringAttachment.WorldCFrame = CFrame.new(point)
	end
	for kind, e in pairs(rig.emitters) do
		e:Emit(preset[kind].count or 1)
	end

	if rig.light then
		local spec = preset.light
		rig.light.Brightness = spec.brightness or 3
		rig.light.Enabled = true
		TweenService:Create(rig.light, TweenInfo.new(spec.time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	end

	task.delay(rig.life, function()
		if rig.token ~= token then
			return
		end
		if rig.light then
			rig.light.Enabled = false
		end
		release(preset, rig)
	end)
end

--- One preset at a point. `dir` = where the spray goes (a unit vector, usually back toward the attacker).
--- `priority` "low" effects are dropped first when the cap is reached.
function EnemyFX.play(presetName: string, enemyType: string?, weaponType: string?, weaponId: string?, point: Vector3, dir: Vector3?, priority: string?)
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - point).Magnitude > LIMITS.maxDistance then
		return
	end
	if live >= (priority == "low" and LIMITS.maxLive or LIMITS.hardCap) then
		return
	end
	local preset = EnemyConfig.resolve(enemyType, weaponType, weaponId, presetName)
	if not preset then
		return
	end
	local direction = dir and dir.Magnitude > 1e-3 and dir.Unit or Vector3.yAxis
	fire(preset, point, direction)
end

local function dissolve(model: Model, spec: any)
	local delay, time = spec.delay or 0.3, spec.time or 0.8
	task.delay(delay, function()
		if not model.Parent then
			return
		end
		local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" and item.Transparency < 1 then
				TweenService:Create(item, info, { Transparency = 1 }):Play()
			elseif item:IsA("Decal") or item:IsA("Texture") then
				TweenService:Create(item, info, { Transparency = 1 }):Play()
			end
		end
	end)
end

function EnemyFX.death(model: Model, enemyType: string?, weaponType: string?, weaponId: string?)
	local center = model:GetBoundingBox().Position
	EnemyFX.play("death", enemyType, weaponType, weaponId, center, Vector3.yAxis, "high")
	local entry = EnemyConfig.sound(enemyType, weaponType, weaponId, "death")
	if entry then
		CombatFX.playAt(center, entry)
	end
	local preset = EnemyConfig.resolve(enemyType, weaponType, weaponId, "death")
	if preset and preset.dissolve then
		dissolve(model, preset.dissolve)
	end
end

--- A WeaponHit payload: the hit effect (normal or crit), its sound, and the death effect on a kill.
function EnemyFX.hit(data: any)
	local point = typeof(data.point) == "Vector3" and data.point or data.position
	local dir = typeof(data.dir) == "Vector3" and data.dir or Vector3.yAxis
	local enemyType = type(data.enemyType) == "string" and data.enemyType or nil
	local weaponType = type(data.weaponType) == "string" and data.weaponType or nil
	local weaponId = type(data.weaponId) == "string" and data.weaponId or nil
	local isCrit = data.isCrit == true
	local isCrash = data.crash == true
	local target = typeof(data.target) == "Instance" and data.target or nil

	if not (isCrit or isCrash) and target then
		local now = os.clock()
		if now - (lastHitOn[target] or 0) < LIMITS.targetCooldown then
			return
		end
		lastHitOn[target] = now
	end

	EnemyFX.play(isCrash and "hit_crash" or isCrit and "hit_crit" or "hit_normal", enemyType, weaponType, weaponId, point, dir, (isCrit or isCrash) and "high" or "low")
	-- a Crash plays its own slot (the crit step sound still plays from the swing); empty = the crit / hit slot
	local entry = (isCrash and EnemyConfig.sound(enemyType, weaponType, weaponId, "crash"))
		or EnemyConfig.sound(enemyType, weaponType, weaponId, isCrit and "crit" or "hit")
	if entry and not data.killed then
		CombatFX.playAt(point, entry)
	end
	if data.killed and target and target:IsA("Model") then
		EnemyFX.death(target, enemyType, weaponType, weaponId)
	end
end

function EnemyFX.liveCount(): number
	return live
end

return EnemyFX
