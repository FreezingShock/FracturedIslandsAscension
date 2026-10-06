--[[
	AttackBarController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	The Minecraft-style attack-charge bar under the crosshair. It fills while you rest after a swing and is full when your
	next swing would be a Full hit (CombatConfig.timing). The server owns the clock: it sets the player attributes
	LastSwing (server time of the last swing) and ChargeTime (seconds of rest for a full bar at the held weapon's attack
	speed; nil when no combat weapon is held). The bar is a hand-made template, ReplicatedStorage.GUI.AttackBar
	(ScreenGui > Frame > Fill); restyle it in Studio, the script only sizes / tints Fill and shows or hides the gui.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig")) :: any
local template = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("AttackBar") :: ScreenGui

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FLASH = Color3.fromRGB(255, 255, 255)

local gui = playerGui:FindFirstChild("AttackBar") :: ScreenGui?
if not gui then
	gui = template:Clone()
	gui.Name = "AttackBar"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.Parent = playerGui
end
local screen = gui :: ScreenGui
local frame = screen:WaitForChild("Frame") :: Frame
local fill = frame:WaitForChild("Fill") :: Frame

local wasFull = false

RunService.RenderStepped:Connect(function()
	local charge = player:GetAttribute("ChargeTime")
	local last = player:GetAttribute("LastSwing")
	if type(charge) ~= "number" or type(last) ~= "number" or charge <= 0 then
		screen.Enabled = false
		wasFull = false
		return
	end
	screen.Enabled = true
	local elapsed = workspace:GetServerTimeNow() - last
	local fraction = math.clamp(elapsed / charge, 0, 1)
	fill.Size = UDim2.fromScale(fraction, 1)

	-- the tier colour: the tier this rest would give (the controller does not know the weapon's speed, only the charge time)
	local boundary = CombatConfig.chargeTime(1)
	local tier = CombatConfig.timingTier(elapsed, boundary / charge)
	local color = Color3.fromHex(tier.color or "#FFFFFF")
	local full = fraction >= 1
	if full and not wasFull then
		fill.BackgroundColor3 = FLASH
		TweenService:Create(fill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = color }):Play()
	elseif not full or not wasFull then
		fill.BackgroundColor3 = color
	end
	wasFull = full
end)
