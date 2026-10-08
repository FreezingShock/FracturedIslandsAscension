--[[
	DeathController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Plays the death look (DeathFX: glitch, then a burst of glowing triangles) when the server says something died
	(RemoteEvent EntityDeath { model, kind, deathType, seed } from DeathService; the client never sends anything).
	The nameplate's own glitch + shards run in EnemyNameplateController from the same message.

	When the dead one is YOU (DeathConfig.selfDeath): the screen goes with the body.
	  glitch  the view cools to blue and desaturates, the camera shakes harder and starts pulling back and up
	  burst   a white-cyan flash and a bloom pulse as the triangles go off, the camera keeps floating away
	  respawn the effects are removed and CameraController takes the view back (it pauses while the player attribute
	          DeathCam is true)
--]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DeathFX = require(Modules:WaitForChild("DeathFX")) :: any
local DeathConfig = require(Modules:WaitForChild("Config"):WaitForChild("DeathConfig")) :: any
local remote = ReplicatedStorage:WaitForChild("EntityDeath") :: RemoteEvent
local respawnRemote = ReplicatedStorage:WaitForChild("EntityRespawn") :: RemoteEvent

local player = Players.LocalPlayer
local STEP_NAME = "FIADeathCam"
local ARM_PARTS = { -- the parts CameraController keeps visible in first person (it hides the rest)
	LeftUpperArm = true, LeftLowerArm = true, LeftHand = true, RightUpperArm = true, RightLowerArm = true, RightHand = true,
	["Left Arm"] = true, ["Right Arm"] = true,
}

local active: { effects: { Instance }, token: number }? = nil
local tokenCounter = 0
local deathView: { direction: Vector3, distance: number, fov: number }? = nil -- where the death camera was looking from
local awaitingRespawn = false -- you died; the death camera is held until the reveal (or the failsafe) hands it back

local function clear()
	RunService:UnbindFromRenderStep(STEP_NAME)
	if active then
		for _, effect in ipairs(active.effects) do
			effect:Destroy()
		end
		active = nil
	end
	player:SetAttribute("DeathCam", nil)
	awaitingRespawn = false
end

local function selfDeath(model: Model)
	clear()
	tokenCounter += 1
	local token = tokenCounter
	local cfg = DeathConfig.resolve("player", nil)
	local look = cfg.selfDeath
	local timeline = cfg.timeline
	local camera = workspace.CurrentCamera
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (camera and root) then
		return
	end

	-- screen: cool blue during the glitch, a flash at the burst, back to normal
	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "DeathFxCorrection"
	correction.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "DeathFxBloom"
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 1
	bloom.Parent = Lighting
	active = { effects = { correction, bloom }, token = token }

	TweenService:Create(correction, TweenInfo.new(timeline.glitch, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TintColor = look.glitchTint,
		Saturation = look.glitchSaturation,
		Contrast = look.glitchContrast,
	}):Play()
	task.delay(timeline.glitch, function()
		if not (active and active.token == token) then
			return
		end
		correction.Brightness = look.flash
		bloom.Intensity = look.bloom
		TweenService:Create(correction, TweenInfo.new(look.flashSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Brightness = 0,
			TintColor = Color3.new(1, 1, 1),
			Saturation = 0,
			Contrast = 0,
		}):Play()
		TweenService:Create(bloom, TweenInfo.new(timeline.burst, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Intensity = 0 }):Play()
	end)

	-- camera: CameraController pauses; this drifts back and up and shakes while the body glitches
	player:SetAttribute("DeathCam", true)
	local startFov = camera.FieldOfView
	local focus = root.Position + Vector3.new(0, 1.5, 0)
	local away = camera.CFrame.Position - focus
	local distance = math.max(away.Magnitude, 6)
	local direction = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, 1)
	deathView = { direction = direction, distance = distance, fov = startFov }
	awaitingRespawn = true
	local total = timeline.glitch + timeline.burst
	local elapsed = 0
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, function(dt)
		elapsed += math.min(dt, 0.05)
		local t = math.clamp(elapsed / total, 0, 1)
		local ease = 1 - (1 - t) ^ 2.2
		local glitchT = math.clamp(elapsed / math.max(timeline.glitch, 0.05), 0, 1)
		local settle = elapsed < timeline.glitch and 1 or math.max(0, 1 - (elapsed - timeline.glitch) / 0.35)
		local shake = look.shake * (glitchT ^ 1.5) * settle
		local drift = CFrame.Angles(0, math.rad(look.orbitDegrees) * ease, 0)
		local offset = drift:VectorToWorldSpace(direction) * (distance + look.pullBack * ease) + Vector3.new(0, look.rise * ease, 0)
		local position = focus + offset + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * shake
		camera.CFrame = CFrame.lookAt(position, focus + Vector3.new(0, look.rise * 0.25 * ease, 0))
		camera.FieldOfView = startFov + look.fovBonus * ease
	end)
end

local function selfRespawn(model: Model)
	local view = deathView
	local camera = workspace.CurrentCamera
	local root = model:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not (view and camera and root and awaitingRespawn) then
		clear()
		return
	end
	-- take over from the death camera step and the death screen effects, but keep the camera paused (DeathCam stays true)
	RunService:UnbindFromRenderStep(STEP_NAME)
	if active then
		for _, effect in ipairs(active.effects) do
			effect:Destroy()
		end
		active = nil
	end
	tokenCounter += 1
	local token = tokenCounter
	awaitingRespawn = false
	local cfg = DeathConfig.resolve("player", nil)
	local look = cfg.selfRespawn
	local timeline = cfg.respawn.timeline
	local reveal = timeline.converge + timeline.solidify
	local startCFrame = camera.CFrame
	local startFov = camera.FieldOfView

	local correction = Instance.new("ColorCorrectionEffect")
	correction.Name = "RespawnFxCorrection"
	correction.TintColor = look.tint
	correction.Saturation = look.saturation
	correction.Contrast = look.contrast
	correction.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "RespawnFxBloom"
	bloom.Intensity = 0
	bloom.Size = 24
	bloom.Threshold = 1
	bloom.Parent = Lighting
	active = { effects = { correction, bloom }, token = token }

	-- camera, one render step with four stretches: GLIDE from the death view to a framing of the new body, HOLD there while it
	-- converges and glitches in, SWING (an arc) into the head while the head and torso fade out for the first-person view, and a
	-- robotic LOCK-IN (a dip in the field of view, a tiny nod, a flash) before CameraController takes over exactly there.
	local holdEnd = timeline.travel + reveal
	local swingEnd = holdEnd + timeline.swing
	local lockEnd = swingEnd + look.lockSeconds
	local firstFov = player:GetAttribute("FirstPersonFov") or 100
	local head = model:FindFirstChild("Head") :: BasePart?
	local rootYaw = select(2, root.CFrame:ToOrientation())
	local firstRotation = CFrame.fromOrientation(0, rootYaw, 0)
	local fadeParts: { BasePart } = {}
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and not item:FindFirstAncestorOfClass("Tool") and not ARM_PARTS[item.Name] then
			table.insert(fadeParts, item)
		end
	end
	local lockPlayed = false
	local elapsed = 0
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, function(dt)
		elapsed += math.min(dt, 0.05)
		local focus = root.Position + Vector3.new(0, 1.5, 0)
		local framing = CFrame.lookAt(focus + view.direction * look.distance + Vector3.new(0, look.rise, 0), focus)
		local eyes = head and head.Position or focus
		local firstPerson = CFrame.new(eyes) * firstRotation
		if elapsed < timeline.travel then
			local a = TweenService:GetValue(elapsed / math.max(timeline.travel, 0.05), Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			camera.CFrame = startCFrame:Lerp(framing, a)
			camera.FieldOfView = startFov + (view.fov - startFov) * a -- the death widened the view; it settles back
		elseif elapsed < holdEnd then
			camera.CFrame = framing
			camera.FieldOfView = view.fov
		elseif elapsed < swingEnd then
			local u = (elapsed - holdEnd) / math.max(timeline.swing, 0.05)
			local a = TweenService:GetValue(u, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)
			local pose = framing:Lerp(firstPerson, a)
			local side = framing.RightVector * (math.sin(math.pi * a) * look.swingArc) -- bows out sideways, then dives in
			camera.CFrame = pose + side
			camera.FieldOfView = view.fov + (firstFov - view.fov) * a
			local fade = math.clamp((a - 0.45) / 0.55, 0, 1)
			for _, part in ipairs(fadeParts) do
				part.LocalTransparencyModifier = fade
			end
		else
			local u = math.clamp((elapsed - swingEnd) / math.max(look.lockSeconds, 0.05), 0, 1)
			local kick = math.sin(math.pi * u)
			camera.CFrame = firstPerson * CFrame.Angles(math.rad(-look.lockNod) * kick, 0, 0)
			camera.FieldOfView = firstFov - look.lockFov * kick
			for _, part in ipairs(fadeParts) do
				part.LocalTransparencyModifier = 1
			end
			if not lockPlayed then
				lockPlayed = true
				correction.Brightness = look.lockFlash
				TweenService:Create(correction, TweenInfo.new(look.lockSeconds * 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
				if look.lockSound.id ~= "" then
					local sound = Instance.new("Sound")
					sound.SoundId = look.lockSound.id
					sound.Volume = look.lockSound.volume
					sound.Parent = workspace.CurrentCamera
					sound:Play()
					Debris:AddItem(sound, 3)
				end
			end
			if elapsed >= lockEnd then
				if active and active.token == token then
					clear() -- CameraController continues from this exact pose
				end
			end
		end
	end)

	-- screen: cool until the triangles merge, then a flash + bloom pulse while it clears
	task.delay(timeline.travel + timeline.converge, function()
		if not (active and active.token == token) then
			return
		end
		correction.Brightness = look.flash
		bloom.Intensity = look.bloom
		TweenService:Create(correction, TweenInfo.new(timeline.solidify, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Brightness = 0,
			TintColor = Color3.new(1, 1, 1),
			Saturation = 0,
			Contrast = 0,
		}):Play()
		TweenService:Create(bloom, TweenInfo.new(timeline.solidify, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Intensity = 0 }):Play()
	end)
end

player.CharacterAdded:Connect(function()
	if not awaitingRespawn then
		clear()
		return
	end
	-- the death camera stays until EntityRespawn starts the reveal; if that never comes, give the view back
	local token = tokenCounter
	task.delay(DeathConfig.resolve("player", nil).selfRespawn.failsafeSeconds, function()
		if tokenCounter == token and awaitingRespawn then
			clear()
		end
	end)
end)

respawnRemote.OnClientEvent:Connect(function(model, seed, kind)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	if type(seed) ~= "number" or type(kind) ~= "string" then
		return
	end
	-- a player's reveal waits for the camera glide; mobs and dummies start at once
	local delay = kind == "player" and DeathConfig.resolve("player", nil).respawn.timeline.travel or 0
	DeathFX.playReverse(model, kind, seed, delay)
	if model == player.Character then
		selfRespawn(model)
	end
end)

remote.OnClientEvent:Connect(function(model, kind, deathType, seed)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	if type(kind) ~= "string" or (type(deathType) ~= "string" and deathType ~= nil) then
		return
	end
	DeathFX.play(model, kind, deathType, type(seed) == "number" and seed or nil)
	if model == player.Character then
		selfDeath(model)
	end
end)
