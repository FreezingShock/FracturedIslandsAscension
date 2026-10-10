--[[
	ChatBubble (ModuleScript, Client)
	Place inside: StarterPlayerScripts

	The speech bubble over a player's nameplate. ChatController calls ChatBubble.say(sender, text) for every player line it renders
	(notices, enemies and NPCs never get one). The bubble is a child of that player's EnemyNameplate billboard, placed just above the
	plate's Stack, so it rises and falls as the health bar and tags open and close (it follows the Stack's AbsoluteSize).

	  * up to ChatConfig.Bubble.MaxBubbles per player; the newest sits at the bottom, the oldest fades early past the cap
	  * each bubble lives Lifetime seconds and fades over its last FadeSeconds, then is removed
	  * your own bubble shows only in the camera phases NameplateConfig.kinds.self.cameraModes allows (third-person free)
	  * the look comes from the hand-made templates ReplicatedStorage.GUI.EnemyNameplate_BubbleStack / _Bubble (tools/studio/build_chat_bubble.luau)
	  * native Roblox bubble chat is switched off, so only this bubble shows

	Reads only: the message text (already filtered by TextChatService) and the local camera mode. Nothing is sent.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ChatConfig = require(Modules:WaitForChild("Config"):WaitForChild("ChatConfig")) :: any
local NameplateConfig = require(Modules:WaitForChild("Config"):WaitForChild("NameplateConfig")) :: any

local guiFolder = ReplicatedStorage:WaitForChild("GUI")
local stackTemplate = guiFolder:WaitForChild("EnemyNameplate_BubbleStack") :: Frame
local bubbleTemplate = guiFolder:WaitForChild("EnemyNameplate_Bubble") :: CanvasGroup

local localPlayer = Players.LocalPlayer
local ChatBubble = {}

-- native bubble chat would draw a second, unthemed bubble over the same head
pcall(function()
	TextChatService.BubbleChatConfiguration.Enabled = false
end)

--- ChatConfig.Bubble, with the kind's overrides on top (NameplateConfig.kinds.<kind>.bubble).
local function settings(kind: string): any
	local out = {}
	for key, value in pairs(ChatConfig.Bubble) do
		out[key] = value
	end
	local override = NameplateConfig.kinds[kind] and NameplateConfig.kinds[kind].bubble or {}
	for key, value in pairs(override) do
		out[key] = value
	end
	return out
end

-- one placer per plate: the bubble column sits above the plate's Stack and follows its height every frame
-- (an AbsoluteSize signal was not reliable: the tag row opening left the column behind)
local placers: { [BillboardGui]: () -> () } = {}
local order = 0

RunService.Heartbeat:Connect(function()
	for gui, place in pairs(placers) do
		if gui.Parent then
			place()
		else
			placers[gui] = nil
		end
	end
end)

local function stackFor(gui: BillboardGui, gap: number): Frame?
	local plateStack = gui:FindFirstChild("Stack") :: Frame?
	if not plateStack then
		return nil
	end
	local box = gui:FindFirstChild("BubbleStack") :: Frame?
	if not box then
		box = stackTemplate:Clone()
		box.Name = "BubbleStack"
		box.Parent = gui
	end
	if not placers[gui] then
		placers[gui] = function()
			-- the Stack is centred in the billboard, so its top is (height / 2) above the centre
			box.Position = UDim2.new(0.5, 0, 0.5, -(plateStack.AbsoluteSize.Y / 2 + gap))
		end
		placers[gui]()
	end
	return box
end

--- Starts a bubble's fade-out (once) and removes it when the fade ends.
local function leave(bubble: CanvasGroup, seconds: number)
	if bubble:GetAttribute("Leaving") then
		return
	end
	bubble:SetAttribute("Leaving", true)
	local tween = TweenService:Create(bubble, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 })
	tween.Completed:Connect(function()
		bubble:Destroy()
	end)
	tween:Play()
end

local function shownFor(player: Player): boolean
	if player ~= localPlayer then
		return true
	end
	local modes = NameplateConfig.resolve("self").cameraModes
	return modes ~= nil and modes[localPlayer:GetAttribute("CameraMode")] == true
end

--- Shows `text` above `player`'s nameplate. Silent when the player has no plate yet (it is attached a moment after spawn).
function ChatBubble.say(player: Player, text: string)
	local character = player.Character
	local gui = character and character:FindFirstChild("EnemyNameplate")
	if not (gui and gui:IsA("BillboardGui")) or not shownFor(player) then
		return
	end
	local kind = player == localPlayer and "self" or "player"
	local cfg = settings(kind)
	local box = stackFor(gui, cfg.Gap)
	if not box then
		return
	end

	order += 1
	local bubble = bubbleTemplate:Clone()
	bubble.Name = "Bubble"
	bubble.LayoutOrder = order
	local pill = bubble:FindFirstChild("Pill") :: Frame
	local label = pill:FindFirstChild("Text") :: TextLabel
	label.Text = text -- already filtered and rich-text escaped by TextChatService
	label.TextSize = cfg.TextSize
	-- the same stroke as this kind's level badge (NameplateConfig.kinds.<kind>.badge), so the bubble matches the plate's colour
	local badge = NameplateConfig.resolve(kind).badge
	if badge then
		for _, part in ipairs({ pill, bubble:FindFirstChild("Tail") }) do
			local stroke = part and part:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = Color3.fromHex(badge.stroke)
			end
		end
	end
	local limit = label:FindFirstChildOfClass("UISizeConstraint")
	if limit then
		limit.MaxSize = Vector2.new(cfg.MaxWidth, 1000000)
	end
	bubble.Parent = box

	-- over the cap: the oldest live bubbles fade out now
	local live = {}
	for _, child in ipairs(box:GetChildren()) do
		if child.Name == "Bubble" and child:IsA("CanvasGroup") and not child:GetAttribute("Leaving") then
			table.insert(live, child)
		end
	end
	table.sort(live, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #live > cfg.MaxBubbles do
		leave(table.remove(live, 1) :: CanvasGroup, cfg.FadeSeconds)
	end

	task.delay(cfg.Lifetime - cfg.FadeSeconds, function()
		if bubble.Parent then
			leave(bubble, cfg.FadeSeconds)
		end
	end)
	task.delay(cfg.Lifetime, function()
		bubble:Destroy()
	end)
end

return ChatBubble
