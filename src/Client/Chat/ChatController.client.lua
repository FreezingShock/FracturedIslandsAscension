--[[
	ChatController (LocalScript)
	Place inside: StarterPlayerScripts

	The custom chat: a bottom-left panel in the tooltip look (ReplicatedStorage.GUI.FIAChatGui, built by tools/studio/build_chat_gui.luau,
	cloned into PlayerGui). Layout, fonts, transparencies, colours and limits come from Modules/Config/ChatConfig (Visual / Behaviour).

	  SENDING     InputBox -> TextChannel:SendAsync(); Roblox filters the text on its backend (nothing is filtered here).
	  RECEIVING   TextChatService.MessageReceived (text is already filtered AND rich-text escaped), SystemMessage RemoteEvent
	              (ChatService: level-ups / join / leave), ChatBridge.postRaw / postLocal (client-only lines).
	  KEYS        "/" shows / hides the whole chat (same as the topbar pill), Enter highlights the input (and opens the chat if it is
	              hidden), Enter again sends, Esc leaves the box, Up / Down recall what you sent. Press Enter, then type "/give ...".
	  IDLE        faint panel; the top of the log fades out (FadeGroup's UIGradient); focus or hover makes the panel solid.
	  BADGE       each player line starts with the nameplate's level badge ("LV n", the sender's Nexus level); notices have none.

	Messages are cloned from FIAChatGui.Templates (Entry / Row / Line / Spacer) and the nameplate's LevelBadge; nothing is built in code.
--]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ChatConfig = require(Modules:WaitForChild("Config"):WaitForChild("ChatConfig")) :: any
local ChatBridge = require(Modules:WaitForChild("ChatBridge")) :: any
local CFG = require(Modules:WaitForChild("Config"):WaitForChild("NameplateConfig")) :: any
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig")) :: any -- the Nexus level attribute name
local LevelBadge = require(Modules:WaitForChild("LevelBadge")) :: any
local Topbar = require(ReplicatedStorage:WaitForChild("TopbarPlus")) :: any
local SystemMsg = ReplicatedStorage:WaitForChild("SystemMessage") :: RemoteEvent

local V = ChatConfig.Visual
local B = ChatConfig.Behaviour

-- ===================== HIDE THE NATIVE CHAT =====================
local function hideDefaultChat()
	local ok, err = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, false)
	if not ok then
		warn("[ChatController] SetCoreGuiEnabled failed:", err)
	end
end
hideDefaultChat()
player.CharacterAdded:Connect(hideDefaultChat)

-- ===================== CHANNEL =====================
local general: TextChannel? = nil
task.spawn(function()
	local channels = TextChatService:WaitForChild("TextChannels", 15)
	general = channels and channels:WaitForChild("RBXGeneral", 15) :: TextChannel?
	if not general then
		warn("[ChatController] RBXGeneral TextChannel not found (TextChatService.CreateDefaultTextChannels must be on).")
	end
end)

-- ===================== GUI (clone of the Studio template) =====================
local guiRoot = ReplicatedStorage:WaitForChild("GUI", 10)
local template = guiRoot and guiRoot:WaitForChild("FIAChatGui", 10)
assert(template, "[ChatController] ReplicatedStorage.GUI.FIAChatGui is missing (run tools/studio/build_chat_gui.luau)")

local ChatGui = template:Clone() :: ScreenGui
ChatGui.Name = "FIAChatGui"
ChatGui.ResetOnSpawn = false
ChatGui.Enabled = true

local Panel = ChatGui:WaitForChild("Panel") :: Frame
local Body = Panel:WaitForChild("Body") :: Frame
local FadeGroup = Body:WaitForChild("FadeGroup") :: CanvasGroup -- the log's top fades through its UIGradient
local LogFrame = FadeGroup:WaitForChild("LogFrame") :: ScrollingFrame
local InputBar = Body:WaitForChild("InputBar") :: Frame
local InputBox = InputBar:WaitForChild("InputBox") :: TextBox
local CharCount = InputBar:WaitForChild("CharCount") :: TextLabel
local SendBtn = InputBar:WaitForChild("SendBtn") :: ImageButton
local NewMsgBtn = Body:WaitForChild("NewMsgBtn") :: TextButton
local PanelScale = Panel:WaitForChild("Scale") :: UIScale
local inputStroke = InputBar:FindFirstChildOfClass("UIStroke") :: UIStroke
local Templates = ChatGui:WaitForChild("Templates")
local EntryT = Templates:WaitForChild("Entry") :: Frame
local LineT = Templates:WaitForChild("Line") :: TextLabel
local SpacerT = Templates:WaitForChild("Spacer") :: Frame
local RowT = Templates:WaitForChild("Row") :: Frame -- a player line: [level badge] [name: text]

-- The level badge is the nameplate's own LevelBadge (GUI.EnemyNameplate), so Studio edits to it show on plates and in chat.
-- Its text is scaled to the chat's FontSize (the nameplate's name size is the reference). Missing template = no badge.
local nameplateTemplate = guiRoot and guiRoot:WaitForChild("EnemyNameplate", 10)
local badgeTemplate = nameplateTemplate and nameplateTemplate:FindFirstChild("LevelBadge", true)
local nameTemplate = nameplateTemplate and nameplateTemplate:FindFirstChild("NameLabel", true) :: TextLabel?
local badgeLabelTemplate = badgeTemplate and badgeTemplate:FindFirstChild("LevelLabel") :: TextLabel?
if not (badgeTemplate and nameTemplate and badgeLabelTemplate) then
	warn("[ChatController] GUI.EnemyNameplate has no LevelBadge / NameLabel: player lines get no level badge")
end
local badgeTextSize = (nameTemplate and badgeLabelTemplate)
	and math.max(6, math.round(badgeLabelTemplate.TextSize * V.FontSize / nameTemplate.TextSize))
	or V.FontSize
local PLAYER_BADGE = CFG.resolve("player", nil).badge -- the tint a player's plate gets (NameplateConfig.kinds.player.badge)

NewMsgBtn.Visible = false
InputBox.FontFace = V.ChatFont
InputBox.TextSize = V.FontSize
Panel.BackgroundTransparency = V.BorderIdleAlpha
Body.BackgroundTransparency = V.BodyIdleAlpha
ChatGui.Parent = playerGui

local isFocused = false
local chatOpen = true
local slideTween: Tween? = nil
local sliding = false
local panelWidth = V.PanelWidth

--- Left edge (screen px) of the FIAHUD plate, or nil while it does not exist yet.
local function hudLeft(): number?
	local hud = playerGui:FindFirstChild("FIAHUD")
	local root = hud and hud:FindFirstChild("Root")
	local back = root and root:FindFirstChild("Back")
	if back and back:IsA("GuiObject") and back.AbsoluteSize.X > 0 then
		return back.AbsolutePosition.X
	end
	return nil
end

local function currentScale(): number
	local camera = workspace.CurrentCamera
	return camera and math.clamp(camera.ViewportSize.Y / V.BaseHeight, V.MinScale, V.MaxScale) or 1
end

local function restPosition(s: number): UDim2
	return UDim2.new(0, math.floor(V.Margin * s), 1, -math.floor(V.Margin * s))
end

local function offPosition(): UDim2
	return UDim2.new(0, -(panelWidth + V.Margin + 40), 1, -V.Margin)
end

local function applyLayout()
	local s = currentScale()
	PanelScale.Scale = s
	local width = V.PanelWidth
	local left = V.FollowHud and hudLeft()
	if left then
		width = math.clamp((left - (V.Margin + V.HudGap) * s) / s, V.MinWidth, V.MaxWidth)
	end
	panelWidth = math.floor(width)
	Panel.AnchorPoint = Vector2.new(0, 1)
	Panel.Size = UDim2.fromOffset(panelWidth, V.PanelHeight)
	if not sliding then
		Panel.Position = chatOpen and restPosition(s) or offPosition()
	end
	InputBar.Size = UDim2.new(1, -16, 0, V.InputBarHeight)
	FadeGroup.Size = UDim2.new(1, 0, 1, -(V.InputBarHeight + 16))
end
applyLayout()
local layoutClock = 0
RunService.Heartbeat:Connect(function(dt) -- the HUD can appear or resize after the chat
	layoutClock += dt
	if layoutClock >= 0.3 then
		layoutClock = 0
		applyLayout()
	end
end)
local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end
watchCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCamera()
	applyLayout()
end)

-- ===================== TOPBARPLUS TOGGLE =====================
local chatIcon = Topbar.new()
chatIcon:setName("ChatToggle")
chatIcon:setLabel("Chat")
chatIcon:setOrder(1)
chatIcon:setImage("rbxassetid://72986449768058")
chatIcon:modifyTheme({
	{ "IconButton", "BackgroundColor3", Color3.fromRGB(255, 255, 255) },
	{ "IconButton", "BackgroundTransparency", 0.8 },
	{ "IconButton", "BorderSizePixel", 2 },
	{ "IconButton", "BorderColor3", Color3.fromRGB(0, 0, 0) },
	{ "IconLabel", "TextColor3", Color3.fromRGB(255, 255, 255) },
	{ "IconLabel", "TextStrokeColor3", Color3.fromRGB(0, 0, 0) },
	{ "IconLabel", "TextStrokeTransparency", 0 },
	{ "UICorner", "CornerRadius", UDim.new(0, 8) },
})
chatIcon:setCaption("Toggle Chat (/)")

--- Slides the whole chat in from / out to the left edge.
local function setChatOpen(open: boolean)
	if open == chatOpen and ChatGui.Enabled == open then
		return
	end
	chatOpen = open
	chatIcon:setImage(open and "rbxassetid://72986449768058" or "rbxassetid://122351441139765")
	if slideTween then
		slideTween:Cancel()
	end
	sliding = true
	if open then
		ChatGui.Enabled = true
		Panel.Position = offPosition()
		slideTween = TweenService:Create(Panel, TweenInfo.new(V.OpenTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = restPosition(currentScale()) })
	else
		if isFocused then
			InputBox:ReleaseFocus()
		end
		slideTween = TweenService:Create(Panel, TweenInfo.new(V.CloseTime, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = offPosition() })
	end
	local tween = slideTween :: Tween
	tween.Completed:Connect(function(state)
		if slideTween ~= tween then
			return -- a newer open / close replaced this one
		end
		sliding = false
		if not chatOpen and state == Enum.PlaybackState.Completed then
			ChatGui.Enabled = false
		end
	end)
	tween:Play()
end
chatIcon.selected:Connect(function()
	setChatOpen(true)
end)
chatIcon.deselected:Connect(function()
	setChatOpen(false)
end)
chatIcon:select() -- the chat starts open, so the pill starts selected

-- ===================== STATE =====================
local messages: { any } = {}
local isHovered = false
local lastSendTime = 0
local autoScroll = true
local layoutOrder = 0
local renderedIds: { [string]: boolean } = {}
local renderedCount = 0
local sentHistory: { string } = {}
local historyIndex = 0
local focusLostAt = 0

-- ===================== FOCUS / TRANSPARENCY =====================
local panelTween: Tween? = nil
local bodyTween: Tween? = nil

local function updateFocusState()
	local active = isFocused or isHovered
	local info = TweenInfo.new(V.TransitionTime, Enum.EasingStyle.Quad)
	if panelTween then
		panelTween:Cancel()
	end
	if bodyTween then
		bodyTween:Cancel()
	end
	panelTween = TweenService:Create(Panel, info, { BackgroundTransparency = active and V.BorderActiveAlpha or V.BorderIdleAlpha })
	bodyTween = TweenService:Create(Body, info, { BackgroundTransparency = active and V.BodyActiveAlpha or V.BodyIdleAlpha })
	panelTween:Play()
	bodyTween:Play()
	if inputStroke then
		TweenService:Create(inputStroke, info, { Color = isFocused and V.InputActiveStroke or V.InputIdleStroke }):Play()
		if isFocused then
			inputStroke.Thickness = V.FocusPulse
			TweenService:Create(inputStroke, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Thickness = 2 }):Play()
		end
	end
end

Panel.MouseEnter:Connect(function()
	isHovered = true
	updateFocusState()
end)
Panel.MouseLeave:Connect(function()
	isHovered = false
	updateFocusState()
end)

-- ===================== SCROLL =====================
local scrollTween: Tween? = nil
local scrolling = false
local function scrollToBottom()
	RunService.Heartbeat:Wait()
	local target = Vector2.new(0, math.max(0, LogFrame.AbsoluteCanvasSize.Y - LogFrame.AbsoluteSize.Y))
	if scrollTween then
		scrollTween:Cancel()
	end
	scrolling = true
	local tween = TweenService:Create(LogFrame, TweenInfo.new(V.ScrollTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = target })
	scrollTween = tween
	tween.Completed:Connect(function()
		if scrollTween == tween then
			scrolling = false
		end
	end)
	tween:Play()
end

local function isNearBottom(): boolean
	return (LogFrame.AbsoluteCanvasSize.Y - LogFrame.AbsoluteSize.Y - LogFrame.CanvasPosition.Y) <= V.AutoScrollThreshold
end

LogFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if scrolling then
		return -- our own smooth scroll
	end
	autoScroll = isNearBottom()
	if autoScroll then
		NewMsgBtn.Visible = false
	end
end)
NewMsgBtn.MouseButton1Click:Connect(function()
	autoScroll = true
	NewMsgBtn.Visible = false
	scrollToBottom()
end)

-- Scrollbar always visible at the configured thickness. The wheel steps WheelStep px per notch (Roblox's native wheel is too
-- small), so the native wheel is off on desktop while the pointer is over the log; touch keeps the native drag.
LogFrame.ScrollBarThickness = V.ScrollBarThickness
LogFrame.ScrollBarImageTransparency = 0
LogFrame.ScrollingEnabled = UserInputService.TouchEnabled
local rowLayout = RowT:FindFirstChildOfClass("UIListLayout")
if rowLayout then
	rowLayout.Padding = UDim.new(0, V.BadgeGap) -- the gap between a player's badge and name (ChatConfig.Visual.BadgeGap)
end
local logHovered = false
LogFrame.MouseEnter:Connect(function()
	logHovered = true
end)
LogFrame.MouseLeave:Connect(function()
	logHovered = false
end)
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel or not logHovered then
		return
	end
	local maxY = math.max(0, LogFrame.AbsoluteCanvasSize.Y - LogFrame.AbsoluteSize.Y)
	LogFrame.CanvasPosition = Vector2.new(0, math.clamp(LogFrame.CanvasPosition.Y - input.Position.Z * V.WheelStep, 0, maxY))
end)

-- ===================== RENDERING =====================
local function nameColorFor(userId: number?): string
	if userId == player.UserId and V.SelfNameColor then
		return V.SelfNameColor
	end
	local colors = V.NameColors
	return colors[((userId or 0) % #colors) + 1]
end

local function newLine(entry: Frame, order: number, rich: string): TextLabel
	local line = LineT:Clone()
	line.Name = "Line" .. order
	line.LayoutOrder = order
	line.FontFace = V.ChatFont
	line.TextSize = V.FontSize
	line.Text = rich
	if entry.Name ~= "Row" then
		-- only a row (badge + name) fills the width left over by the badge; a plain line keeps its template size
		local flex = line:FindFirstChildOfClass("UIFlexItem")
		if flex then
			flex:Destroy()
		end
	end
	local stroke = line:FindFirstChildOfClass("UIStroke")
	line.TextTransparency = 1 -- fades in
	if stroke then
		stroke.Transparency = 1
		TweenService:Create(stroke, TweenInfo.new(V.LineFadeTime), { Transparency = V.StrokeTransparency }):Play()
	end
	TweenService:Create(line, TweenInfo.new(V.LineFadeTime), { TextTransparency = 0 }):Play()
	line.Parent = entry
	return line
end

local function playSound(id: string?)
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.5
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 5)
end

--- A fresh level badge for one player line: the nameplate's LevelBadge, filled with "LV n" and the player tint row.
local function badgeFor(level: number): Frame?
	if not badgeTemplate or not badgeLabelTemplate then
		return nil
	end
	local badge = badgeTemplate:Clone() :: Frame
	local label = badge:FindFirstChild("LevelLabel") :: TextLabel?
	if label then
		label.TextSize = badgeTextSize
		label.Text = LevelBadge.text(level)
	end
	LevelBadge.paint(badge, PLAYER_BADGE)
	return badge
end

local function renderPayload(payload: any)
	layoutOrder += 1
	local entry = EntryT:Clone()
	entry.Name = "Msg_" .. layoutOrder
	entry.LayoutOrder = layoutOrder
	local labels = {}

	if payload.type == "player" or payload.type == "notice" then
		local stamp = ""
		if B.ShowTimestamps then
			stamp = string.format('<font color="#%s">[%s] </font>', V.TimestampColor:ToHex(), os.date("%H:%M", payload.timestamp or os.time()))
		end
		local nameHex = payload.nameColor or nameColorFor(payload.userId)
		local rich = string.format(
			'%s<font color="#%s">%s</font><font color="#%s">: %s</font>',
			stamp,
			nameHex:gsub("^#", ""),
			payload.playerName or "?",
			V.PlayerTextColor:ToHex(),
			payload.text or ""
		)
		if payload.type == "player" then
			-- a player line is a row: the level badge, then the name and text. Notices have no badge.
			local row = RowT:Clone()
			row.Name = "Row"
			row.Parent = entry
			local badge = badgeFor(payload.level or 0)
			if badge then
				badge.LayoutOrder = 1
				badge.Parent = row
			end
			table.insert(labels, newLine(row, 2, rich))
		else
			table.insert(labels, newLine(entry, 1, rich))
		end
	else
		for i, lineText in ipairs(payload.lines or {}) do
			if lineText == "" then
				local spacer = SpacerT:Clone()
				spacer.LayoutOrder = i
				spacer.Parent = entry
			else
				local hexColor = (payload.colors and payload.colors[i]) or "DCDCDC"
				local rich = lineText
				if payload.bold and payload.bold[i] == true then
					rich = "<b>" .. rich .. "</b>"
				end
				table.insert(labels, newLine(entry, i, string.format('<font color="#%s">%s</font>', hexColor, rich)))
			end
		end
	end
	entry.Parent = LogFrame
	playSound(payload.sound)

	table.insert(messages, { frame = entry, labels = labels })
	if #messages > B.MaxHistory then
		table.remove(messages, 1).frame:Destroy()
	end
	if autoScroll then
		task.defer(scrollToBottom)
	else
		NewMsgBtn.Visible = true
	end
end

ChatBridge.registerRenderer(renderPayload)

--- A one-line system notice in the chat itself.
local function notice(text: string, hexColor: string?)
	renderPayload({ type = "system", lines = { text }, colors = { [1] = hexColor or "FF5555" }, timestamp = os.time() })
end

-- ===================== SENDING =====================
local function trySend()
	local text = InputBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return
	end
	if #text > B.MaxMessageLength then
		text = text:sub(1, B.MaxMessageLength)
	end
	local channel = general
	if not channel then
		notice("Chat is still loading, try again in a moment.")
		return
	end
	local now = os.clock()
	if now - lastSendTime < B.SendRateLimit then
		notice(B.TooFastNotice)
		return
	end
	lastSendTime = now

	table.insert(sentHistory, text)
	if #sentHistory > B.SendHistory then
		table.remove(sentHistory, 1)
	end
	historyIndex = #sentHistory + 1
	InputBox.Text = ""
	InputBox:ReleaseFocus()

	task.spawn(function()
		local ok, err = pcall(function()
			channel:SendAsync(text)
		end)
		if not ok then
			warn("[ChatController] SendAsync failed:", err)
		end
	end)
end

InputBox.Focused:Connect(function()
	isFocused = true
	CharCount.Visible = true
	updateFocusState()
end)
InputBox.FocusLost:Connect(function(enterPressed)
	isFocused = false
	focusLostAt = os.clock()
	CharCount.Visible = false
	updateFocusState()
	if enterPressed then
		trySend()
	end
end)
InputBox:GetPropertyChangedSignal("Text"):Connect(function()
	local length = #InputBox.Text
	if length > B.MaxMessageLength then
		InputBox.Text = InputBox.Text:sub(1, B.MaxMessageLength)
		return
	end
	CharCount.Text = string.format("%d/%d", length, B.MaxMessageLength)
	CharCount.TextColor3 = length >= B.MaxMessageLength - 20 and Color3.fromHex("#FF5555") or Color3.fromHex("#AAAAAA")
end)
SendBtn.MouseButton1Click:Connect(trySend)

local function focusInput(prefill: string?)
	if isFocused or not ChatGui.Enabled then
		return
	end
	InputBox:CaptureFocus()
	if prefill then
		RunService.Heartbeat:Wait()
		if InputBox.Text == "" then
			InputBox.Text = prefill
		end
		InputBox.CursorPosition = #InputBox.Text + 1
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if isFocused then
		if input.KeyCode == Enum.KeyCode.Escape then
			InputBox:ReleaseFocus()
		elseif input.KeyCode == Enum.KeyCode.Up and #sentHistory > 0 then
			historyIndex = math.max(1, historyIndex - 1)
			InputBox.Text = sentHistory[historyIndex]
			InputBox.CursorPosition = #InputBox.Text + 1
		elseif input.KeyCode == Enum.KeyCode.Down and #sentHistory > 0 then
			historyIndex = math.min(#sentHistory + 1, historyIndex + 1)
			InputBox.Text = sentHistory[historyIndex] or ""
			InputBox.CursorPosition = #InputBox.Text + 1
		end
		return
	end
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Slash then
		if chatOpen then
			chatIcon:deselect() -- the topbar pill drives setChatOpen
		else
			chatIcon:select()
		end
	elseif input.KeyCode == Enum.KeyCode.Return and os.clock() - focusLostAt > 0.25 then
		if not chatOpen then
			chatIcon:select()
		end
		task.spawn(focusInput, nil)
	end
end)

-- ===================== RECEIVING =====================
local function hidden(text: string): boolean
	for _, pattern in ipairs(B.HideNoticePatterns) do
		if text:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

TextChatService.MessageReceived:Connect(function(msg)
	if not msg.Text or msg.Text == "" then
		return -- still pending: the confirmed message fires again
	end
	local id = msg.MessageId
	if id and id ~= "" then
		if renderedIds[id] then
			return
		end
		renderedIds[id] = true
		renderedCount += 1
		if renderedCount > 200 then
			renderedIds = { [id] = true }
			renderedCount = 1
		end
	end
	local source = msg.TextSource
	if not source then
		if hidden(msg.Text) then
			return
		end
		renderPayload({ type = "notice", playerName = "System", nameColor = V.SystemNameColor:ToHex(), text = msg.Text, timestamp = os.time() })
		return
	end
	local sender = Players:GetPlayerByUserId(source.UserId)
	-- the sender's Nexus level: the server's Player attribute (the nameplate reads the same one); the client never writes it
	local nexus = sender and sender:GetAttribute(ResourceConfig.nexusLevelAttribute)
	renderPayload({
		type = "player",
		playerName = sender and sender.DisplayName or source.Name,
		userId = source.UserId,
		level = type(nexus) == "number" and nexus or 0,
		text = msg.Text, -- filtered and rich-text escaped by TextChatService
		timestamp = os.time(),
	})
end)

SystemMsg.OnClientEvent:Connect(renderPayload)

-- ===================== STARTUP LINES =====================
task.defer(function()
	ChatBridge.postRaw({
		"Welcome to Fractured Islands: Ascension",
		"Press Enter to chat. / shows or hides the chat.",
	}, {
		[1] = "FF55FF",
		[2] = "AAAAAA",
	}, { [1] = true }, "game")
end)
