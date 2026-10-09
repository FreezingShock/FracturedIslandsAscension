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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == DODGE_KEY and not gameProcessed and not MenuBridge.isOpen() then
		DodgeRequest:FireServer()
	end
end)

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

DodgeEvent.OnClientEvent:Connect(function(roller, distance, duration, soundId, animationId)
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
	if roller ~= player then
		return
	end
	if type(animationId) == "string" and animationId ~= "" then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local animation = Instance.new("Animation")
			animation.AnimationId = animationId
			animator:LoadAnimation(animation):Play()
		end
	end
	-- the dash: a velocity that covers `distance` in `duration`, removed afterwards (the server never moves the character)
	local direction = rollDirection(root, humanoid)
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
