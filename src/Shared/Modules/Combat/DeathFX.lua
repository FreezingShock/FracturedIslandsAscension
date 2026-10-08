--[[
	DeathFX (ModuleScript, Shared; used by the client)
	Place inside: ReplicatedStorage > Modules

	The death look, drawn on the client from the server's EntityDeath message (DeathController). Everything about it is
	Modules/Config/DeathConfig; the server (DeathService) freezes the body and owns the timing.

	  DeathFX.play(model, kind, deathType, seed)   GLITCH then BURST (see DeathConfig for the numbers)
	  DeathFX.hide(model)                          just make the body vanish locally (too far away / over the cap)
	  DeathFX.live() -> number                     death effects alive on this client (the caps in DeathConfig.caps)

	GLITCH: a clone of the frozen body (the original is hidden locally) flickers, jitters, slices sideways and turns blue/neon,
	with sweeping neon scan bars and a pulsing outline. BURST: the copy is removed and a few ParticleEmitters on an invisible
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
type GhostPart = { part: BasePart, cf: CFrame, color: Color3, material: Enum.Material, transparency: number }

local KEEP = { SpecialMesh = true, Decal = true, Texture = true, BlockMesh = true, CylinderMesh = true }

local function makeGhost(model: Model, maxParts: number): (Model?, { GhostPart })
	local container = Instance.new("Model")
	container.Name = model.Name .. "_Ghost"
	local parts: { GhostPart } = {}
	for _, item in ipairs(model:GetDescendants()) do
		if #parts >= maxParts then
			break
		end
		if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" and item.Transparency < 1 then
			local ok, copy = pcall(function()
				return item:Clone()
			end)
			if ok and copy then
				for _, child in ipairs(copy:GetChildren()) do
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
				table.insert(parts, { part = copy, cf = item.CFrame, color = copy.Color, material = copy.Material, transparency = copy.Transparency })
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

-- thin neon bars that sweep up and down the body while it glitches (cheap, and reads as "scanning / deleting")
local function makeScanBars(model: Model, cfg: any): { BasePart }
	local bars: { BasePart } = {}
	local boxCFrame, boxSize = model:GetBoundingBox()
	for index = 1, cfg.glitch.scanBars do
		local bar = Instance.new("Part")
		bar.Name = "ScanBar"
		bar.Anchored = true
		bar.CanCollide = false
		bar.CanQuery = false
		bar.CanTouch = false
		bar.Material = Enum.Material.Neon
		bar.Color = cfg.glitch.tint
		bar.Transparency = 0.35
		bar.Size = Vector3.new(boxSize.X + 1.2, 0.12, boxSize.Z + 1.2)
		bar.CFrame = boxCFrame
		bar:SetAttribute("Phase", (index - 1) / math.max(cfg.glitch.scanBars, 1))
		bar:SetAttribute("Base", boxCFrame.Position.Y)
		bar:SetAttribute("Height", boxSize.Y)
		bar.Parent = fxFolder()
		table.insert(bars, bar)
	end
	return bars
end

--- Runs the glitch for `seconds` of RENDERED time: each frame advances at most 1/20 s, so a hitch cannot eat the whole glitch.
local function runGlitch(ghost: Model, parts: { GhostPart }, bars: { BasePart }, cfg: any, seconds: number, rng: Random, withHighlight: boolean, onDone: () -> ())
	local glitch = cfg.glitch
	local elapsed = 0
	local highlight: Highlight? = nil
	if withHighlight then
		highlight = Instance.new("Highlight")
		highlight.FillColor = glitch.tint
		highlight.OutlineColor = Color3.new(1, 1, 1)
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = ghost
		highlight.Parent = ghost
	end
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function(dt)
		elapsed += math.min(dt, 0.05)
		local t = math.clamp(elapsed / math.max(seconds, 0.05), 0, 1)
		local intensity = t ^ 1.4
		local tintAlpha = math.clamp((t - glitch.tintStart) / math.max(1 - glitch.tintStart, 0.01), 0, 1)
		local flickerChance = math.clamp((t - glitch.flickerStart) * 1.2, 0, 1) * 0.6
		local whiten = math.clamp((t - 0.88) / 0.12, 0, 1)
		local count = #parts
		local sliced: { [number]: number } = {}
		if t > 0.3 and rng:NextNumber() < glitch.sliceChance then
			for _ = 1, glitch.slices do
				sliced[rng:NextInteger(1, math.max(count, 1))] = (rng:NextInteger(0, 1) == 0 and -1 or 1) * glitch.sliceStuds
			end
		end
		local flickerHidden = rng:NextNumber() < flickerChance
		for index, ghostPart in ipairs(parts) do
			local part = ghostPart.part
			local jitter = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.5), rng:NextNumber(-1, 1)) * glitch.jitterStuds * intensity
			local slice = sliced[index] and Vector3.new(sliced[index], 0, 0) or Vector3.zero
			part.CFrame = ghostPart.cf + jitter + slice
			part.Color = ghostPart.color:Lerp(glitch.tint, tintAlpha):Lerp(Color3.new(1, 1, 1), whiten)
			part.Material = tintAlpha > 0.5 and Enum.Material.Neon or ghostPart.material
			part.Transparency = (flickerHidden and rng:NextNumber() < 0.7) and rng:NextNumber(0.5, 0.95) or ghostPart.transparency
		end
		for _, bar in ipairs(bars) do
			local phase = bar:GetAttribute("Phase") :: number
			local sweep = (math.sin((t * glitch.scanSweeps + phase) * math.pi * 2) + 1) / 2
			local base, height = bar:GetAttribute("Base") :: number, bar:GetAttribute("Height") :: number
			bar.Position = Vector3.new(bar.Position.X, base - height / 2 + height * sweep, bar.Position.Z)
			bar.Transparency = 0.25 + (1 - intensity) * 0.4 + (flickerHidden and 0.3 or 0)
		end
		if highlight then
			highlight.FillTransparency = 0.45 + rng:NextNumber(0, 0.4)
		end
		if t >= 1 then
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

local function playBurst(model: Model, cfg: any, reduced: boolean, rng: Random)
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

	local share = reduced and cfg.caps.reducedShare or 1
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

-- ===================== PLAY =====================
function DeathFX.live(): number
	return liveCount
end

function DeathFX.play(model: Model, kind: string?, deathType: string?, seed: number?)
	if not (model and model.Parent) then
		return
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
	local reduced = liveCount >= caps.reduceAt
	liveCount += 1
	local timeline = cfg.timeline
	task.delay(timeline.glitch + timeline.burst + cfg.burst.lingerSeconds, function()
		liveCount = math.max(0, liveCount - 1)
	end)
	local rng = Random.new(seed or math.random(1, 1000000))

	local ghost, parts = makeGhost(model, reduced and 24 or 40)
	local bars = ghost and makeScanBars(model, cfg) or {}
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
		for _, bar in ipairs(bars) do
			bar:Destroy()
		end
		if model.Parent then
			playBurst(model, cfg, reduced, rng)
		end
	end

	if ghost and #parts > 0 then
		runGlitch(ghost, parts, bars, cfg, timeline.glitch, rng, cfg.glitch.highlight and liveCount <= 3, burst)
	else
		task.delay(timeline.glitch, burst)
	end
end

return DeathFX
