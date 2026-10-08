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

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DeathFX = require(Modules:WaitForChild("DeathFX")) :: any
local DeathConfig = require(Modules:WaitForChild("Config"):WaitForChild("DeathConfig")) :: any
local remote = ReplicatedStorage:WaitForChild("EntityDeath") :: RemoteEvent

local player = Players.LocalPlayer
local STEP_NAME = "FIADeathCam"

local active: { effects: { Instance }, token: number }? = nil
local tokenCounter = 0

local function clear()
	RunService:UnbindFromRenderStep(STEP_NAME)
	if active then
		for _, effect in ipairs(active.effects) do
			effect:Destroy()
		end
		active = nil
	end
	player:SetAttribute("DeathCam", nil)
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

player.CharacterAdded:Connect(function()
	clear()
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
