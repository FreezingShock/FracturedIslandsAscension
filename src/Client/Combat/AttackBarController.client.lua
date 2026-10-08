--[[
	AttackBarController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	The Minecraft-style attack-charge bar under the crosshair. It fills while you rest after a swing and is full when your
	next swing would be a Full hit (CombatConfig.timing). The server owns the clock: it sets the player attributes
	LastSwing (server time of the last swing) and ChargeTime (seconds of rest for a full bar at the held weapon's attack
	speed; nil when no combat weapon is held). The bar is a hand-made template, ReplicatedStorage.GUI.AttackBar
	(ScreenGui > Frame > Fill); restyle it in Studio, the script only sizes / tints Fill and shows or hides the gui.

	WHERE IT SITS (player attribute CameraMode, set by CameraController): first person = right below the crosshair; shoulder
	(over the shoulder) and free = just above the Action Bar (StarterGui.FIAHUD.Root.ActionBar), tweening between the two when
	the camera mode changes. It is hidden while any menu (inventory, Nexus menu) is open and drawn behind other GUI (DisplayOrder).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any
local template = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("AttackBar") :: ScreenGui

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FLASH = Color3.fromRGB(255, 255, 255)
local BEHIND = 1 -- DisplayOrder: set back behind the menus and the other HUD
local GAP_ABOVE_ACTION_BAR = 20 -- px between the bar and the Action Bar's TEXT (measured from the text line, not the taller frame)
local FIRST_PERSON_DROP = 20 -- px below the crosshair (screen centre)
local MOVE = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

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
screen.DisplayOrder = BEHIND
frame.AnchorPoint = Vector2.new(0.5, 1) -- the bottom edge is what sits above the Action Bar

--- The Y offset (in this gui's own space) that puts the bar's BOTTOM edge at `absBottom` (screen pixels, as AbsolutePosition
--- reports them). The shift between the gui's space and the screen is measured from the bar itself, so it holds on any device
--- and with or without the top-bar inset.
local function offsetForBottom(absBottom: number): number
	local shift = frame.AbsolutePosition.Y + frame.AbsoluteSize.Y - frame.Position.Y.Offset
	return absBottom - shift
end

local function targetPosition(): (UDim2, string)
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
	if player:GetAttribute("CameraMode") == "first" then
		return UDim2.new(0.5, 0, 0, offsetForBottom(viewport.Y / 2 + FIRST_PERSON_DROP + frame.AbsoluteSize.Y)), "first"
	end
	local hud = playerGui:FindFirstChild("FIAHUD")
	local actionBar = hud and hud:FindFirstChild("Root") and hud.Root:FindFirstChild("ActionBar") :: GuiObject?
	local top = viewport.Y * 0.8
	if actionBar and actionBar:IsA("GuiObject") and actionBar.AbsoluteSize.Y > 0 then
		-- the text line (Label) is what the bar sits above; its on-screen top already includes every scale of the HUD
		local label = actionBar:FindFirstChild("Label") :: GuiObject?
		top = (label or actionBar).AbsolutePosition.Y
	end
	return UDim2.new(0.5, 0, 0, offsetForBottom(top - GAP_ABOVE_ACTION_BAR)), "above"
end

local placedKind: string? = nil
local moving: Tween? = nil

local wasFull = false

RunService.RenderStepped:Connect(function()
	local charge = player:GetAttribute("ChargeTime")
	local last = player:GetAttribute("LastSwing")
	if type(charge) ~= "number" or type(last) ~= "number" or charge <= 0 or MenuBridge.isOpen() then
		screen.Enabled = false
		wasFull = false
		return
	end
	screen.Enabled = true
	local position, kind = targetPosition()
	if placedKind == nil then
		frame.Position = position
	elseif kind ~= placedKind then
		if moving then
			moving:Cancel()
		end
		moving = TweenService:Create(frame, MOVE, { Position = position })
		moving.Completed:Once(function(state)
			if state == Enum.PlaybackState.Completed then
				moving = nil
			end
		end)
		moving:Play()
	elseif not moving then
		frame.Position = position -- follows the Action Bar if the layout changes
	end
	placedKind = kind
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
