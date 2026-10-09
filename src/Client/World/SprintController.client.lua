--[[
	SprintController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	DODGE ROLL: pressing MovementConfig.dodge.key sends bare intent (DodgeRequest, no arguments). The server validates and spends the
	Stamina, then broadcasts DodgeEvent; our own roll is a short LinearVelocity dash driven by the numbers it sends.

	Tells the server whether a sprint key is held (MovementConfig.sprint.keys). That is all the client does: the server
	decides whether the player can actually sprint (stamina, movement) and applies the Speed boost; CameraController
	widens the field of view from the `Sprinting` Player attribute the server sets.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local MovementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MovementConfig")) :: any
local SetSprint = ReplicatedStorage:WaitForChild("SetSprint")

local keys = {}
for _, keyCode in ipairs(MovementConfig.sprint.keys) do
	keys[keyCode] = true
end

local held = false
local function setHeld(value: boolean)
	if held ~= value then
		held = value
		SetSprint:FireServer(value)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if keys[input.KeyCode] and not gameProcessed then
		setHeld(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if keys[input.KeyCode] then
		setHeld(false)
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	setHeld(false) -- never leave sprint stuck on when the window loses focus
end)

Players.LocalPlayer.CharacterAdded:Connect(function()
	held = false -- the server resets sprint on spawn; the next press starts fresh
end)

-- ===================== DODGE ROLL =====================
local DodgeRequest = ReplicatedStorage:WaitForChild("DodgeRequest")
local DodgeEvent = ReplicatedStorage:WaitForChild("DodgeEvent")
local MenuBridge = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MenuBridge")) :: any
local player = Players.LocalPlayer
local DODGE_KEY = MovementConfig.dodge.key
local DODGE = MovementConfig.dodge
local SECTORS = { "f", "fr", "r", "br", "b", "bl", "l", "fl" }

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == DODGE_KEY and not gameProcessed and not MenuBridge.isOpen() then
		DodgeRequest:FireServer()
	end
end)

-- every roll clip (every dodge type) is downloaded at launch and a track per clip is loaded into each new character's Animator,
-- so the first roll plays without a hitch
local rollAnimations: { [string]: Animation } = {}
local rollTracks: { [string]: AnimationTrack } = {}

local function collectRollAnimations(animations: any)
	if type(animations) ~= "table" then
		return
	end
	for _, set in pairs(animations) do
		if type(set) == "table" then
			for _, id in pairs(set) do
				if type(id) == "string" and id ~= "" and not rollAnimations[id] then
					local animation = Instance.new("Animation")
					animation.AnimationId = id
					rollAnimations[id] = animation
				end
			end
		end
	end
end

collectRollAnimations(MovementConfig.dodge.animations)
for _, typeConfig in pairs(MovementConfig.dodge.types) do
	collectRollAnimations(typeConfig.animations)
end

task.spawn(function()
	local list = {}
	for _, animation in pairs(rollAnimations) do
		table.insert(list, animation)
	end
	if #list > 0 then
		game:GetService("ContentProvider"):PreloadAsync(list)
	end
end)

local function loadRollTracks(character: Model)
	table.clear(rollTracks)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 10)) :: Animator?
	if not animator then
		return
	end
	for id, animation in pairs(rollAnimations) do
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			rollTracks[id] = track
		end
	end
end

player.CharacterAdded:Connect(loadRollTracks)
if player.Character then
	task.spawn(loadRollTracks, player.Character)
end

--- The roll direction: where the player is steering, else where the character faces (flat).
local function rollDirection(root: BasePart, humanoid: Humanoid): Vector3
	local move = humanoid.MoveDirection
	if move.Magnitude > 0.1 then
		return move.Unit
	end
	local look = root.CFrame.LookVector
	return Vector3.new(look.X, 0, look.Z).Unit
end

local function playSound(root: BasePart, id: string)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = 0.8
	sound.RollOffMaxDistance = 80
	sound.Parent = root
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 3)
end

--- A flat ring (ground) or a ring standing across the roll (air) that grows and fades out.
local function spawnRing(cfg, position: Vector3, direction: Vector3)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = cfg.color
	ring.Size = Vector3.new(cfg.thickness, cfg.from, cfg.from) -- the cylinder's axis is its X
	if cfg.vertical then
		ring.CFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(0, math.pi / 2, 0)
	else
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	end
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(cfg.time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(cfg.thickness * 0.2, cfg.to, cfg.to),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, cfg.time + 0.1)
end

--- A beam-like ribbon sweeping behind the roll: a wide coloured outer layer that fades out to `fadeColor`, and a thin
--- bright white core inside it. Both taper to a point at the tail. Lives for the roll plus its fade.
local TAPER = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.55, 0.6),
	NumberSequenceKeypoint.new(1, 0),
})

local function ribbon(root: BasePart, width: number, color: Color3, fadeColor: Color3?, transparency: number, lifetime: number, life: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-width / 2, -0.2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(width / 2, -0.2, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = fadeColor and ColorSequence.new(color, fadeColor) or ColorSequence.new(color)
	trail.Lifetime = lifetime
	trail.Transparency = NumberSequence.new(transparency, 1)
	trail.WidthScale = TAPER
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.MinLength = 0.05
	trail.Parent = root
	Debris:AddItem(a0, life)
	Debris:AddItem(a1, life)
	Debris:AddItem(trail, life)
end

local function spawnTrail(root: BasePart, cfg, life: number)
	ribbon(root, cfg.width, cfg.color, cfg.fadeColor, 0.25, cfg.lifetime, life)
	ribbon(root, cfg.width * 0.3, cfg.coreColor, nil, 0, cfg.lifetime * 0.7, life)
end

--- Motes: a burst on the first frame, then a steady stream until the roll ends.
local function spawnMotes(root: BasePart, cfg, texture: string, duration: number)
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(cfg.color)
	emitter.Lifetime = NumberRange.new(0.4, 0.9)
	emitter.Speed = NumberRange.new(cfg.speed * 0.5, cfg.speed)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = cfg.accel
	emitter.Size = NumberSequence.new(0.35, 0)
	emitter.Transparency = NumberSequence.new(0, 1)
	emitter.LightEmission = 1
	emitter.Rate = 0
	emitter.Parent = attachment
	emitter:Emit(cfg.burst)
	emitter.Rate = cfg.rate
	task.delay(duration, function()
		emitter.Rate = 0
	end)
	Debris:AddItem(attachment, duration + 1)
end

--- The roll FX for everyone who can see the roller; ground or air look chosen by the roller's FloorMaterial.
local function playRollFx(root: BasePart, humanoid: Humanoid, duration: number)
	local fx = DODGE.fx[humanoid.FloorMaterial == Enum.Material.Air and "air" or "ground"]
	spawnRing(fx.ring, root.Position - Vector3.new(0, fx.ring.drop, 0), rollDirection(root, humanoid))
	spawnTrail(root, fx.trail, duration + fx.trail.lifetime)
	spawnMotes(root, fx.motes, DODGE.fx.moteTexture, duration)
end

DodgeEvent.OnClientEvent:Connect(function(roller, distance, duration, soundId, animations)
	if typeof(roller) ~= "Instance" or not roller:IsA("Player") or type(distance) ~= "number" or type(duration) ~= "number" then
		return
	end
	local character = roller.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then
		return
	end
	if type(soundId) == "string" and soundId ~= "" then
		playSound(root, soundId) -- everybody hears it, 3D at the roller
	end
	playRollFx(root, humanoid, duration) -- everybody sees it
	if roller ~= player then
		return
	end
	local direction = rollDirection(root, humanoid)
	-- the clip: ground or air set, the sector (45 degrees each) of the roll direction relative to where the character faces
	local delay = 0
	if type(animations) == "table" then
		local set = animations[humanoid.FloorMaterial == Enum.Material.Air and "air" or "ground"]
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local id = nil
		if type(set) == "table" and look.Magnitude > 0.01 then
			look = look.Unit
			local right = Vector3.new(-look.Z, 0, look.X) -- look x up
			local angle = math.deg(math.atan2(direction:Dot(right), direction:Dot(look)))
			id = set[SECTORS[(math.floor((angle + 22.5) / 45) % 8) + 1]]
		end
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if type(id) == "string" and id ~= "" and animator then
			local track = rollTracks[id]
			if not track then -- not loaded yet (or an id only the server knows): load it now
				local animation = Instance.new("Animation")
				animation.AnimationId = id
				track = animator:LoadAnimation(animation)
				track.Priority = Enum.AnimationPriority.Action
				rollTracks[id] = track
			end
			local speed = DODGE.animationDuration / math.max(duration, 0.05)
			delay = DODGE.animationDashStart / speed -- the clip crouches first, the dash starts when the roll does
			track:Play(0.04, 1, speed)
		end
	end
	-- the dash: a velocity that covers `distance` in `duration`, removed afterwards (the server never moves the character)
	if delay > 0 then
		task.wait(delay)
	end
	local attachment = Instance.new("Attachment")
	attachment.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.MaxForce = math.huge
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / math.max(duration, 0.05))
	velocity.Parent = root
	task.delay(duration, function()
		velocity:Destroy()
		attachment:Destroy()
	end)
end)
