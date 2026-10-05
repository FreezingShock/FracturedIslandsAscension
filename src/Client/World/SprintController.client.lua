--[[
	SprintController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

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
