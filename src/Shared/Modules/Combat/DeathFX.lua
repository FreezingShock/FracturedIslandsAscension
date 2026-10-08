--[[
	DeathFX (ModuleScript, Shared; used by the client)
	Place inside: ReplicatedStorage > Modules

	The death look, drawn on the client from the server's EntityDeath message (DeathController). Everything about it is
	Modules/Config/DeathConfig; the server (DeathService) freezes the body and owns the timing.

	  DeathFX.play(model, kind, deathType, seed)   GLITCH then BURST (see DeathConfig for the numbers)
	  DeathFX.hide(model)                          just make the body vanish locally (too far away / over the cap)
	  DeathFX.live() -> number                     death effects alive on this client (the caps in DeathConfig.caps)

	GLITCH: a clone of the frozen body (the original is hidden locally) flickers, jitters, slices sideways and turns blue/neon,
	flickering between blue, purple and green; each body part then glows and swells until it is white-hot. BURST: the copy is removed and a few ParticleEmitters on an invisible
	box the size of the body fire glowing triangles (flipbook of four shapes, random size / rotation / spin, outward then
	floating up, shrinking), thin fast slivers, a soft glow disc and a point light pulse.
--]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DeathConfig = require(Modules:WaitForChild("Config"):WaitForChild("DeathConfig")) :: any
local EnemyConfig = require(Modules:WaitForChild("EnemyConfig")) :: any

local DeathFX = {}

local liveCount = 0
local folder: Folder? = nil

local function fxFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = "DeathFx"
	made.Parent = workspace
	folder = made
	return made
end

local function between(range: any): number
	return range[1] + math.random() * (range[2] - range[1])
end

local function colorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keypoints = {}
	for index, color in ipairs(colors) do
		table.insert(keypoints, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keypoints)
end

-- ===================== HIDING THE ORIGINAL BODY (client only: these writes never replicate) =====================
function DeathFX.hide(model: Instance)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("ForceField") then
			item.Visible = false -- the spawn bubble would otherwise stay around an invisible body
		elseif item:IsA("BasePart") then
			item.Transparency = 1
		elseif item:IsA("Decal") or item:IsA("Texture") then
			item.Transparency = 1
		elseif item:IsA("BillboardGui") or item:IsA("Highlight") then
			-- the nameplate drives its own death (EnemyNameplateController); a leftover highlight would outline nothing
			if item:IsA("Highlight") then
				item.Enabled = false
			end
		end
	end
end

-- ===================== GHOST (the glitching copy) =====================
-- A LIGHT copy: only the visible parts, each stripped of everything but its mesh / decals. Cloning a whole avatar (layered
-- clothing, cages, accessories, scripts) twice froze the game for seconds, so this never clones the Model.
type GhostPart = { part: BasePart, source: BasePart?, cf: CFrame, size: Vector3, color: Color3, material: Enum.Material, transparency: number, glowAt: number }

local KEEP = { SpecialMesh = true, Decal = true, Texture = true, BlockMesh = true, CylinderMesh = true }

-- `originals` (reveal only): the body is already hidden locally, so the real transparencies come from this map { [Instance] = number }
local function makeGhost(model: Model, maxParts: number, originals: { [Instance]: number }?): (Model?, { GhostPart })
	local container = Instance.new("Model")
	container.Name = model.Name .. "_Ghost"
	local parts: { GhostPart } = {}
	for _, item in ipairs(model:GetDescendants()) do
		if #parts >= maxParts then
			break
		end
		local realTransparency = originals and originals[item] or (item:IsA("BasePart") and item.Transparency or 1)
		if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" and realTransparency < 1 then
			local sources = item:GetChildren()
			local ok, copy = pcall(function()
				return item:Clone()
			end)
			if ok and copy then
				copy.Transparency = realTransparency
				local copies = copy:GetChildren()
				for index, child in ipairs(copies) do
					local source = sources[index]
					if originals and source and originals[source] and (child:IsA("Decal") or child:IsA("Texture")) then
						(child :: any).Transparency = originals[source]
					end
				end
				for _, child in ipairs(copies) do
					if not KEEP[child.ClassName] then
						child:Destroy()
					end
				end
				copy.Anchored = true
				copy.CanCollide = false
				copy.CanQuery = false
				copy.CanTouch = false
				copy.Massless = true
				copy.CFrame = item.CFrame
				copy.Parent = container
				table.insert(parts, { part = copy, source = item, cf = item.CFrame, size = copy.Size, color = copy.Color, material = copy.Material, transparency = copy.Transparency, glowAt = 0 })
			end
		end
	end
	if #parts == 0 then
		container:Destroy()
		return nil, parts
	end
	container.Parent = fxFolder()
	return container, parts
end

--- Runs the glitch for `seconds` of RENDERED time: each frame advances at most 1/20 s, so a hitch cannot eat the whole glitch.
--- Phase 1: the body flickers between blue, purple and green, jitters and slices. Phase 2 (overlapping): every body part,
--- one after another at random moments, starts to glow and swell until it is white-hot; then the burst.
--- `reverse` plays it backwards (the respawn): it starts white-hot and calm-less, cools to the real colours, and the jitter,
--- slices and flicker die away until the body is exactly the real one; the parts also fade in over the first quarter.
local function runGlitch(ghost: Model, parts: { GhostPart }, cfg: any, seconds: number, rng: Random, withHighlight: boolean, onDone: () -> (), reverse: boolean?)
	local glitch = cfg.glitch
	local palette = glitch.colors
	local elapsed = 0
	for _, ghostPart in ipairs(parts) do
		ghostPart.glowAt = rng:NextNumber(glitch.glowStart, glitch.glowEnd)
	end
	local picked: { Color3 } = {}
	for index in ipairs(parts) do
		picked[index] = palette[rng:NextInteger(1, #palette)]
	end
	local highlight: Highlight? = nil
	if withHighlight then
		highlight = Instance.new("Highlight")
		highlight.FillColor = palette[1]
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = ghost
		highlight.Parent = ghost
	end
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		if not ghost.Parent then
			connection:Disconnect() -- the body was removed under us (died again, left): nothing to finish
			return
		end
		elapsed += math.min(dt, 0.05)
		local raw = math.clamp(elapsed / math.max(seconds, 0.05), 0, 1)
		local t = reverse and 1 - raw or raw
		local appear = reverse and math.clamp(raw / 0.25, 0, 1) or 1
		local intensity = t ^ 1.3
		local tintAlpha = math.clamp((t - glitch.tintStart) / math.max(glitch.tintRamp, 0.01), 0, 1)
		local flickerChance = math.clamp((t - glitch.flickerStart) * 1.2, 0, 1) * 0.45
		local count = #parts
		local sliced: { [number]: number } = {}
		if t > 0.2 and t < glitch.glowEnd and rng:NextNumber() < glitch.sliceChance then
			for _ = 1, glitch.slices do
				sliced[rng:NextInteger(1, math.max(count, 1))] = (rng:NextInteger(0, 1) == 0 and -1 or 1) * glitch.sliceStuds
			end
		end
		local flickerHidden = rng:NextNumber() < flickerChance
		local glowSum = 0
		for index, ghostPart in ipairs(parts) do
			local part = ghostPart.part
			-- the colour of a part jumps to another of the palette now and then (a glitching hologram)
			if rng:NextNumber() < glitch.recolorChance then
				picked[index] = palette[rng:NextInteger(1, #palette)]
			end
			local glow = math.clamp((t - ghostPart.glowAt) / glitch.glowRamp, 0, 1)
			glowSum += glow
			local calm = 1 - glow -- a glowing part stops glitching and just burns brighter
			local jitter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1)) * glitch.jitterStuds * intensity * calm
			local slice = sliced[index] and Vector3.new(sliced[index], 0, 0) * calm or Vector3.zero
			-- the reveal follows the real part, so an idle animation cannot make the last frame differ from the body that replaces it
			local liveSource = reverse and ghostPart.source
			part.CFrame = ((liveSource and liveSource.Parent) and liveSource.CFrame or ghostPart.cf) + jitter + slice
			part.Size = ghostPart.size * (1 + glitch.glowSwell * glow)
			local base = ghostPart.color:Lerp(picked[index], tintAlpha)
			part.Color = base:Lerp(glitch.glowColor, glow)
			part.Material = tintAlpha > 0.35 and Enum.Material.Neon or ghostPart.material
			if glow > 0 then
				part.Transparency = ghostPart.transparency
			else
				part.Transparency = (flickerHidden and rng:NextNumber() < 0.6) and rng:NextNumber(0.5, 0.9) or ghostPart.transparency
			end
			if appear < 1 then
				part.Transparency = 1 - (1 - part.Transparency) * appear
			end
		end
		if highlight then
			local meanGlow = glowSum / math.max(count, 1)
			highlight.FillColor = palette[rng:NextInteger(1, #palette)]:Lerp(glitch.glowColor, meanGlow)
			highlight.FillTransparency = 0.5 - 0.5 * meanGlow + rng:NextNumber(0, 0.25) * (1 - meanGlow)
			highlight.OutlineTransparency = 0.2 * (1 - meanGlow)
		end
		if raw >= 1 then
			connection:Disconnect()
			onDone()
		end
	end)
end

-- ===================== BURST =====================
local function addEmitter(anchor: BasePart, cfg: any, texture: string, props: { [string]: any }): ParticleEmitter
	local burst = cfg.burst
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.Shape = Enum.ParticleEmitterShape.Sphere
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	emitter.Acceleration = Vector3.new(0, burst.rise, 0)
	emitter.Drag = burst.drag
	for key, value in pairs(props) do
		(emitter :: any)[key] = value
	end
	emitter.Parent = anchor
	return emitter
end

local function playBurst(model: Model, cfg: any, reduced: boolean, rng: Random, lod: boolean?)
	local burst = cfg.burst
	local boxCFrame, boxSize = model:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "DeathBurst"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(math.max(boxSize.X, 1.5), math.max(boxSize.Y, 2), math.max(boxSize.Z, 1.5))
	anchor.CFrame = boxCFrame
	anchor.Parent = fxFolder()

	local textures = DeathConfig.textures
	local colors = colorSequence(burst.colors)
	local lifeRange = NumberRange.new(burst.life[1], burst.life[2])
	local avgSize = (burst.size[1] + burst.size[2]) / 2
	local env = (burst.size[2] - burst.size[1]) / 2
	local triangles = addEmitter(anchor, cfg, textures[burst.texture] or textures.triangles, {
		Color = colors,
		Lifetime = lifeRange,
		Speed = NumberRange.new(burst.speed[1], burst.speed[2]),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, avgSize, env),
			NumberSequenceKeypoint.new(0.55, avgSize * 0.55, env * 0.55),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.65, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-burst.rotSpeed, burst.rotSpeed),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
		FlipbookStartRandom = true,
	})
	local slivers = addEmitter(anchor, cfg, textures[burst.texture] or textures.triangles, {
		Color = colors,
		Lifetime = NumberRange.new(burst.life[1] * 0.5, burst.life[2] * 0.8),
		Speed = NumberRange.new(burst.speed[2], burst.speed[2] * 2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, avgSize * 0.8, env * 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(0.85),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
		FlipbookStartRandom = true,
	})
	local glow = addEmitter(anchor, cfg, textures.glow, {
		Color = ColorSequence.new(burst.colors[3] or burst.colors[1]),
		Lifetime = NumberRange.new(burst.glow.life, burst.glow.life),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, burst.glow.size * 0.5), NumberSequenceKeypoint.new(1, burst.glow.size) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, burst.glow.transparency), NumberSequenceKeypoint.new(1, 1) }),
		Acceleration = Vector3.zero,
		Drag = 0,
	})

	local share = lod and cfg.caps.lodShare or (reduced and cfg.caps.reducedShare or 1)
	local total = math.max(8, math.floor(burst.count * share))
	for _, wave in ipairs(burst.waves) do
		local amount = math.max(1, math.floor(total * wave.share))
		if wave.at <= 0 then
			triangles:Emit(amount)
		else
			task.delay(wave.at, function()
				if triangles.Parent then
					triangles:Emit(amount)
				end
			end)
		end
	end
	if lod then
		-- far away: just the triangles
		slivers:Destroy()
		glow:Destroy()
		Debris:AddItem(anchor, cfg.timeline.burst + burst.lingerSeconds)
		return
	end
	slivers:Emit(math.max(2, math.floor(burst.slivers * share)))
	glow:Emit(1)

	local lightSettings = burst.light
	local light = Instance.new("PointLight")
	light.Color = lightSettings.color
	light.Brightness = lightSettings.brightness
	light.Range = lightSettings.range
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(lightSettings.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()

	local entry = cfg.sounds.burst
	if entry and entry.id ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = entry.id
		sound.Volume = entry.volume
		sound.PlaybackSpeed = between(entry.pitch)
		sound.RollOffMaxDistance = 110
		sound.Parent = anchor
		sound:Play()
	end
	Debris:AddItem(anchor, cfg.timeline.burst + burst.lingerSeconds)
end

-- ===================== REVEAL (the death played backwards, for a respawning player) =====================
local reveals: { [Model]: () -> () } = {} -- model -> cancel, so a second death mid-reveal can take the body back

local function playSound(parent: Instance, entry: any, rolloff: number)
	if entry and entry.id ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = entry.id
		sound.Volume = entry.volume
		sound.PlaybackSpeed = between(entry.pitch)
		sound.RollOffMaxDistance = rolloff
		sound.Parent = parent
		sound:Play()
		Debris:AddItem(sound, 4)
	end
end

--- Hides the whole body locally (and anything added to it while hidden). Returns { originals, restore }.
local function hideRestorable(model: Model): ({ [Instance]: number }, () -> ())
	local originals: { [Instance]: number } = {}
	local flags: { [Instance]: boolean } = {}
	local function take(item: Instance)
		if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
			originals[item] = (item :: any).Transparency
			;(item :: any).Transparency = 1
		elseif item:IsA("ForceField") then
			flags[item] = item.Visible
			item.Visible = false
		elseif item:IsA("Highlight") then
			flags[item] = item.Enabled
			item.Enabled = false
		end
	end
	for _, item in ipairs(model:GetDescendants()) do
		take(item)
	end
	local added = model.DescendantAdded:Connect(take)
	local function restore()
		added:Disconnect()
		for item, value in pairs(originals) do
			if item.Parent then
				(item :: any).Transparency = value
			end
		end
		for item, value in pairs(flags) do
			if item.Parent then
				if item:IsA("ForceField") then
					item.Visible = value
				else
					(item :: Highlight).Enabled = value
				end
			end
		end
	end
	return originals, restore
end

--- The reverse of the burst: triangles start small on a sphere around the body, fly inward and grow, a glow disc and a light
--- pulse peak as they merge. Counts, colours, sizes and spin come from cfg.burst; the radius and light from cfg.respawn.
local function playConverge(model: Model, cfg: any, reduced: boolean, rng: Random, lod: boolean)
	local burst, respawn = cfg.burst, cfg.respawn
	local converge = respawn.timeline.converge
	local boxCFrame = model:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "RespawnConverge"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = Vector3.one * respawn.radius * 2
	anchor.CFrame = boxCFrame
	anchor.Parent = fxFolder()

	local textures = DeathConfig.textures
	local texture = textures[burst.texture] or textures.triangles
	local colors = colorSequence(burst.colors)
	local lastAt = 0
	for _, wave in ipairs(burst.waves) do
		lastAt = math.max(lastAt, wave.at)
	end
	local flight = math.max(converge - lastAt, 0.2)
	local lifeMin, lifeMax = flight * 0.82, flight * 0.95
	local speed = respawn.radius / ((lifeMin + lifeMax) / 2)
	local avgSize = (burst.size[1] + burst.size[2]) / 2
	local env = (burst.size[2] - burst.size[1]) / 2
	local inward = {
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Acceleration = Vector3.zero,
		Drag = 0,
	}
	local function props(extra: { [string]: any }): { [string]: any }
		local out = {}
		for key, value in pairs(inward) do
			out[key] = value
		end
		for key, value in pairs(extra) do
			out[key] = value
		end
		return out
	end
	local triangles = addEmitter(anchor, cfg, texture, props({
		Color = colors,
		Lifetime = NumberRange.new(lifeMin, lifeMax),
		Speed = NumberRange.new(speed * 0.92, speed * 1.08),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, avgSize * respawn.sizeStart, env * respawn.sizeStart),
			NumberSequenceKeypoint.new(0.6, avgSize * 0.7, env * 0.7),
			NumberSequenceKeypoint.new(1, avgSize, env),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.3, 0.1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-burst.rotSpeed, burst.rotSpeed),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
		FlipbookStartRandom = true,
	}))
	local slivers = addEmitter(anchor, cfg, texture, props({
		Color = colors,
		Lifetime = NumberRange.new(lifeMin * 0.6, lifeMin),
		Speed = NumberRange.new(speed * 1.6, speed * 2.2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, avgSize * 0.8, env * 0.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 0.2) }),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(0.85),
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2,
		FlipbookMode = Enum.ParticleFlipbookMode.Random,
		FlipbookStartRandom = true,
	}))
	local glow = addEmitter(anchor, cfg, textures.glow, {
		Color = ColorSequence.new(burst.colors[3] or burst.colors[1]),
		Lifetime = NumberRange.new(burst.glow.life, burst.glow.life),
		Speed = NumberRange.new(0, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, burst.glow.size), NumberSequenceKeypoint.new(1, burst.glow.size * 0.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, burst.glow.transparency) }),
		Acceleration = Vector3.zero,
		Drag = 0,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
	})

	-- the waves in reverse order: the trickle leaves first and the dense wave last, so the cloud thickens as it closes in
	local share = lod and cfg.caps.lodShare or (reduced and cfg.caps.reducedShare or 1)
	local total = math.max(8, math.floor(burst.count * share))
	for _, wave in ipairs(burst.waves) do
		local amount = math.max(1, math.floor(total * wave.share))
		local delay = lastAt - wave.at
		if delay <= 0 then
			triangles:Emit(amount)
		else
			task.delay(delay, function()
				if triangles.Parent then
					triangles:Emit(amount)
				end
			end)
		end
	end
	if lod then
		-- far away: just the triangles (no streaks, glow disc, light pulse or sound)
		slivers:Destroy()
		glow:Destroy()
		Debris:AddItem(anchor, converge + burst.lingerSeconds)
		return
	end
	slivers:Emit(math.max(2, math.floor(burst.slivers * share)))
	task.delay(math.max(0, converge - burst.glow.life), function()
		if glow.Parent then
			glow:Emit(1)
		end
	end)

	local lightSettings = respawn.light
	local light = Instance.new("PointLight")
	light.Color = lightSettings.color
	light.Brightness = 0
	light.Range = lightSettings.range
	light.Parent = anchor
	local rise = TweenService:Create(light, TweenInfo.new(converge, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = lightSettings.brightness })
	rise.Completed:Connect(function()
		if light.Parent then
			TweenService:Create(light, TweenInfo.new(lightSettings.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
		end
	end)
	rise:Play()

	playSound(anchor, respawn.sounds.converge, 110)
	Debris:AddItem(anchor, converge + lightSettings.time + burst.lingerSeconds)
end

--- The respawn look for `model`: hidden for `delay` seconds (the camera glides to it), triangles converge on it, then it glitches in
--- (the death glitch backwards) until it is the real body. Everything is a copy; the real body is only un-hidden at the end.
function DeathFX.playReverse(model: Model, kind: string?, seed: number?, delay: number?)
	if not (model and model.Parent) or reveals[model] then
		return
	end
	local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
	local enemyType = model:GetAttribute("EnemyType")
	local entry = (not isPlayer and type(enemyType) == "string") and EnemyConfig.get(enemyType) or nil
	local cfg = DeathConfig.resolve(kind or (isPlayer and "player" or "enemy"), entry)
	local caps = cfg.caps
	local camera = workspace.CurrentCamera
	local distance = camera and (camera.CFrame.Position - model:GetPivot().Position).Magnitude or 0
	if liveCount >= caps.hardCap or distance > caps.maxDistance then
		return -- too busy or too far to see it: the body just shows up
	end
	local lod = distance > caps.lodDistance and not isPlayer -- your own and nearby bodies get the full look
	local reduced = lod or liveCount >= caps.reduceAt
	liveCount += 1
	local holdSeconds = delay or 0
	local timeline = cfg.respawn.timeline
	task.delay(holdSeconds + timeline.converge + timeline.solidify + cfg.burst.lingerSeconds, function()
		liveCount = math.max(0, liveCount - 1)
	end)
	local rng = Random.new(seed or math.random(1, 1000000))

	local originals, restore = hideRestorable(model)
	local alive = true
	local ghost: Model? = nil
	local function cancel()
		if not alive then
			return
		end
		alive = false
		reveals[model] = nil
		if ghost then
			ghost:Destroy()
		end
		restore()
	end
	reveals[model] = cancel
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			cancel()
		end
	end)

	task.spawn(function()
		task.wait(holdSeconds)
		if not alive then
			return
		end
		playConverge(model, cfg, reduced, rng, lod)
		task.wait(timeline.converge)
		if not alive then
			return
		end
		local owner = Players:GetPlayerFromCharacter(model)
		local waited = 0
		while owner and not owner:HasAppearanceLoaded() and waited < 1.5 and alive do -- clothes and accessories load a moment late
			waited += task.wait()
		end
		if not alive then
			return
		end
		local made, parts = makeGhost(model, lod and 12 or (reduced and 24 or 40), originals)
		if not made then
			cancel()
			return
		end
		ghost = made
		playSound(parts[1].part, cfg.respawn.sounds.glitchIn, 90)
		runGlitch(made, parts, cfg, timeline.solidify, rng, cfg.glitch.highlight and liveCount <= 3 and not lod, cancel, true)
	end)
end

-- ===================== PLAY =====================
function DeathFX.live(): number
	return liveCount
end

function DeathFX.play(model: Model, kind: string?, deathType: string?, seed: number?)
	if not (model and model.Parent) then
		return
	end
	local cancelReveal = reveals[model]
	if cancelReveal then
		cancelReveal() -- died again mid-reveal: give the real body back before it is copied for the death glitch
	end
	local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
	local enemyType = model:GetAttribute("EnemyType")
	local entry = (not isPlayer and type(enemyType) == "string") and EnemyConfig.get(enemyType) or nil
	local cfg = DeathConfig.resolve(kind or (isPlayer and "player" or "enemy"), entry)
	local caps = cfg.caps
	local camera = workspace.CurrentCamera
	local origin = model:GetPivot().Position
	if camera and (camera.CFrame.Position - origin).Magnitude > caps.maxDistance then
		DeathFX.hide(model)
		return
	end
	if liveCount >= caps.hardCap then
		DeathFX.hide(model)
		return
	end
	local lod = camera ~= nil and (camera.CFrame.Position - origin).Magnitude > caps.lodDistance and not isPlayer
	local reduced = lod or liveCount >= caps.reduceAt
	liveCount += 1
	local timeline = cfg.timeline
	task.delay(timeline.glitch + timeline.burst + cfg.burst.lingerSeconds, function()
		liveCount = math.max(0, liveCount - 1)
	end)
	local rng = Random.new(seed or math.random(1, 1000000))

	local ghost, parts = makeGhost(model, lod and 12 or (reduced and 24 or 40))
	DeathFX.hide(model)

	local entrySound = cfg.sounds.glitch
	if entrySound and entrySound.id ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = entrySound.id
		sound.Volume = entrySound.volume
		sound.PlaybackSpeed = between(entrySound.pitch)
		sound.RollOffMaxDistance = 90
		sound.Parent = fxFolder()
		sound:Play()
		Debris:AddItem(sound, 3)
	end

	local function burst()
		if ghost then
			ghost:Destroy()
		end
		if model.Parent then
			playBurst(model, cfg, reduced, rng, lod)
		end
	end

	if ghost and #parts > 0 then
		runGlitch(ghost, parts, cfg, timeline.glitch, rng, cfg.glitch.highlight and liveCount <= 3 and not lod, burst)
	else
		task.delay(timeline.glitch, burst)
	end
end

return DeathFX
