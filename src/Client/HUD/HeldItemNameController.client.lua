--[[
	HeldItemNameController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Shows the name of the item in hand above the hotbar, Minecraft style: it types in letter by letter, stays for a few
	seconds, then fades out. Drives StarterGui.FIAHUD > Root > Name [CanvasGroup] > Label [TextLabel] (with its
	UIStroke child); this script creates no UI.

	  text colour    the item's rarity colour (Rarity.hexColor)
	  stroke colour  the dark Minecraft counterpart (Rarity.darkColor)
	  name           the item definition's display name (Items.get(ItemId)), else the Tool's name
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Items = require(Modules:WaitForChild("Items")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CHARS_PER_SECOND = 32 -- typewriter speed
local HOLD_TIME = 2.5 -- seconds the finished name stays
local FADE_IN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PUT_AWAY_GRACE = 0.4 -- switching items puts the old one away and draws the new one a moment later

local group: CanvasGroup? = nil
local label: TextLabel? = nil
local stroke: UIStroke? = nil
local generation = 0 -- bumped on every new name: older typing / hold / fade steps see it and stop
local fadeTween: Tween? = nil
local shownTool: Tool? = nil

local function fadeTo(transparency: number, info: TweenInfo)
	if not group then
		return
	end
	if fadeTween then
		fadeTween:Cancel()
	end
	fadeTween = TweenService:Create(group, info, { GroupTransparency = transparency })
	fadeTween:Play()
end

local function describe(tool: Tool): (string, Color3, Color3)
	local def = Items.get(tool:GetAttribute("ItemId") or "")
	local name = def and def.displayName or tool.Name
	local rarity = Items.getRarity(tool:GetAttribute("Rarity") or (def and def.rarity) or 0)
	return name, Color3.fromHex(rarity.hexColor or "#FFFFFF"), rarity.darkColor or Color3.fromHex("#555555")
end

local function show(tool: Tool)
	if not (group and label) or MenuBridge.isOpen() then
		return
	end
	generation += 1
	local mine = generation
	shownTool = tool

	local name, color, dark = describe(tool)
	label.Text = name
	label.TextColor3 = color
	if stroke then
		stroke.Color = dark
	end
	label.MaxVisibleGraphemes = 0 -- the label keeps its full width (AutomaticSize) while the letters appear
	fadeTo(0, FADE_IN)

	task.spawn(function()
		local total = utf8.len(name) or #name
		local step = 1 / CHARS_PER_SECOND
		for shown = 1, total do
			task.wait(step)
			if generation ~= mine then
				return
			end
			label.MaxVisibleGraphemes = shown
		end
		label.MaxVisibleGraphemes = -1 -- everything
		task.wait(HOLD_TIME)
		if generation == mine then
			fadeTo(1, FADE_OUT)
		end
	end)
end

local function heldTool(): Tool?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Tool") or nil
end

local function onToolChanged()
	local tool = heldTool()
	if tool then
		if tool ~= shownTool then
			show(tool)
		end
		return
	end
	-- nothing in hand: wait a moment (a switch re-draws almost at once), then fade away
	local mine = generation
	task.delay(PUT_AWAY_GRACE, function()
		if generation == mine and not heldTool() then
			shownTool = nil
			fadeTo(1, FADE_OUT)
		end
	end)
end

local function watchCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			onToolChanged()
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			onToolChanged()
		end
	end)
	task.defer(onToolChanged)
end

local function bind(gui: Instance)
	local root = gui:WaitForChild("Root", 10)
	local g = root and root:WaitForChild("Name", 10)
	local l = g and g:WaitForChild("Label", 10)
	if not (g and l and g:IsA("CanvasGroup") and l:IsA("TextLabel")) then
		warn("[HeldItemName] FIAHUD.Root.Name (CanvasGroup) > Label (TextLabel) is missing")
		return
	end
	group, label = g, l
	stroke = l:FindFirstChildOfClass("UIStroke")
	g.GroupTransparency = 1
	l.Text = ""
	shownTool = nil
	if player.Character then
		task.defer(onToolChanged)
	end
end

-- the name hides while a menu is open (it would sit over the inventory); the next item change shows it again
task.spawn(function()
	local wasOpen = false
	while true do
		task.wait(0.1)
		local open = MenuBridge.isOpen()
		if open and not wasOpen then
			generation += 1
			shownTool = nil
			fadeTo(1, FADE_OUT)
		end
		wasOpen = open
	end
end)

local existing = playerGui:FindFirstChild("FIAHUD")
if existing then
	task.spawn(bind, existing)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "FIAHUD" then
		task.spawn(bind, child) -- the GUI was recreated (respawn with ResetOnSpawn)
	end
end)

player.CharacterAdded:Connect(watchCharacter)
if player.Character then
	watchCharacter(player.Character)
end
