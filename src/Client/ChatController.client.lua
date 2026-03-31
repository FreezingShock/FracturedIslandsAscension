-- ============================================================
--  ChatController (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  ARCHITECTURE (2025/2026 compliant):
--    SENDING:   InputBox Enter/Send → TextChannel:SendAsync()
--               Roblox's TextChatService pipeline handles filtering
--               automatically on the backend. No manual FilterStringAsync.
--
--    RECEIVING: TextChatService.MessageReceived fires on every client
--               when a filtered message arrives from the server.
--               msg.Text is already filtered. msg.TextSource.UserId
--               identifies the sender.
--
--    SYSTEM:    SystemMessage RemoteEvent from ChatService (server)
--               for level-up, day change, etc. Rendered the same way.
--
--    WHY NOT TextService:FilterStringAsync / GetChatForUserAsync:
--               GetChatForUserAsync was deprecated in May 2025 and
--               now returns empty strings. Do not use it for chat.
--
--  Panel behaviour:
--    - High transparency when idle (unfocused, cursor not inside panel)
--    - Low transparency (opaque) when InputBox focused or cursor inside
--    - Messages fade when panel is idle
--    - / key focuses the input bar
--    - Hides the default Roblox CoreGui chat window
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ChatConfig = require(Modules:WaitForChild("ChatConfig"))
local ChatBridge = require(Modules:WaitForChild("ChatBridge"))

-- SystemMessage remote (server → client, system blocks only)
local SystemMsg = ReplicatedStorage:WaitForChild("SystemMessage")

local V = ChatConfig.Visual
local B = ChatConfig.Behaviour

-- ===================== HIDE DEFAULT ROBLOX CHAT =====================
local function hideDefaultChat()
	local ok, err = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Chat, false)
	if not ok then
		warn("[ChatController] SetCoreGuiEnabled failed:", err)
	end
end
hideDefaultChat()
player.CharacterAdded:Connect(hideDefaultChat)

-- ===================== TEXTCHANNEL REFERENCE =====================
-- Get the RBXGeneral channel that Roblox auto-creates.
-- SendAsync must be called on this channel from the client.
-- We wait for it because it may not exist the instant this script runs.
local RBXGeneral = nil

local function findTextChannel()
	local tcs = TextChatService
	local channels = tcs:FindFirstChild("TextChannels")
	if channels then
		RBXGeneral = channels:FindFirstChild("RBXGeneral")
	end
	if not RBXGeneral then
		-- Try the flat path some Studio configs use
		RBXGeneral = tcs:FindFirstChild("RBXGeneral")
	end
end

findTextChannel()

if not RBXGeneral then
	-- Wait up to 5 seconds for TextChatService to initialise
	task.spawn(function()
		for _ = 1, 50 do
			task.wait(0.1)
			findTextChannel()
			if RBXGeneral then
				break
			end
		end
		if not RBXGeneral then
			warn(
				"[ChatController] RBXGeneral TextChannel not found. "
					.. "Ensure TextChatService.CreateDefaultTextChannels = true in Studio."
			)
		end
	end)
end

-- ===================== HELPERS =====================

local function toHex(color)
	return string.format(
		"%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

local function hexToColor3(hex)
	local r = tonumber(hex:sub(1, 2), 16) / 255
	local g = tonumber(hex:sub(3, 4), 16) / 255
	local b = tonumber(hex:sub(5, 6), 16) / 255
	return Color3.new(r, g, b)
end

-- ===================== GUI BUILD (clone from ReplicatedStorage) =====================
--
--  Expected hierarchy in ReplicatedStorage > GUI > FIAChatGui  (ScreenGui):
--    FIAChatGui  (ScreenGui — blank, no children needed in template)
--      Panel       (Frame)
--        TabBar    (Frame)
--          UIListLayout
--          UIPadding
--        LogFrame  (ScrollingFrame)
--          UIListLayout
--          UIPadding
--        InputBar  (Frame)
--          InputBox  (TextBox)
--            UIPadding
--          SendBtn   (TextButton)
--        NewMsgBtn (TextButton)
--
--  The clone receives all layout properties from ChatConfig.Visual at
--  runtime so the template in Studio only needs the correct Name on
--  each instance — all sizes, colours, and positions are applied here.
--  This means you can freely restyle the template in Studio without
--  touching this script, and vice versa.
--
--  SECURITY: The template lives in ReplicatedStorage (read-only from
--  the client's perspective after initial load). We clone it, apply
--  runtime config, then parent to playerGui. The original is never
--  modified. If the template is missing we hard-error with a clear
--  message rather than silently producing a broken UI.

local GUI_TEMPLATE_PATH = { "GUI", "FIAChatGui" } -- ReplicatedStorage > GUI > FIAChatGui

local function cloneChatGui()
	-- Walk the path under ReplicatedStorage
	local root = ReplicatedStorage
	for _, name in ipairs(GUI_TEMPLATE_PATH) do
		local child = root:FindFirstChild(name)
		if not child then
			error(
				string.format(
					"[ChatController] Template not found: ReplicatedStorage.%s\n"
						.. "Create a ScreenGui named 'FIAChatGui' inside ReplicatedStorage > GUI.",
					table.concat(GUI_TEMPLATE_PATH, ".")
				),
				2
			)
		end
		root = child
	end

	local template = root -- root is now the FIAChatGui ScreenGui

	-- Clone the ScreenGui shell (children cloned automatically)
	local gui = template:Clone()
	gui.Name = "FIAChatGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true

	-- ── Resolve named descendants ────────────────────────────
	-- Each instance must exist in the template (or be created below).
	-- We use :FindFirstChild on the correct parent so the lookup is
	-- explicit and the error message names exactly what is missing.

	local function need(parent, name, className)
		local inst = parent:FindFirstChild(name)
		if not inst then
			-- Create it rather than erroring, so a minimal blank ScreenGui works
			inst = Instance.new(className or "Frame")
			inst.Name = name
			inst.Parent = parent
		end
		return inst
	end

	local Panel = need(gui, "Panel", "Frame")
	local TabBar = need(Panel, "TabBar", "Frame")
	local LogFrame = need(Panel, "LogFrame", "ScrollingFrame")
	local InputBar = need(Panel, "InputBar", "Frame")
	local InputBox = need(InputBar, "InputBox", "TextBox")
	local SendBtn = need(InputBar, "SendBtn", "TextButton")
	local NewMsgBtn = need(Panel, "NewMsgBtn", "TextButton")

	-- ── Ensure layout instances exist inside TabBar / LogFrame ─
	local function ensureLayout(parent, class, props)
		local existing = parent:FindFirstChildOfClass(class)
		if existing then
			return existing
		end
		local inst = Instance.new(class)
		for k, v in pairs(props or {}) do
			inst[k] = v
		end
		inst.Parent = parent
		return inst
	end

	ensureLayout(TabBar, "UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	})
	local tabPadding = TabBar:FindFirstChildOfClass("UIPadding")
	if not tabPadding then
		tabPadding = Instance.new("UIPadding")
		tabPadding.Parent = TabBar
	end
	tabPadding.PaddingLeft = UDim.new(0, 6)

	ensureLayout(LogFrame, "UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	})
	local logPadding = LogFrame:FindFirstChildOfClass("UIPadding")
	if not logPadding then
		logPadding = Instance.new("UIPadding")
		logPadding.Parent = LogFrame
	end
	logPadding.PaddingLeft = UDim.new(0, 8)
	logPadding.PaddingRight = UDim.new(0, 12)
	logPadding.PaddingTop = UDim.new(0, 4)
	logPadding.PaddingBottom = UDim.new(0, 4)

	-- Ensure InputBox has its left padding
	local inputBoxPad = InputBox:FindFirstChildOfClass("UIPadding")
	if not inputBoxPad then
		inputBoxPad = Instance.new("UIPadding")
		inputBoxPad.Parent = InputBox
	end
	inputBoxPad.PaddingLeft = UDim.new(0, 4)

	-- ── Apply runtime config (ChatConfig.Visual) ─────────────
	-- Sizes, positions, colours come from config — not baked into template.
	-- This keeps the Studio template as a pure structural scaffold.

	Panel.AnchorPoint = Vector2.new(0, 1)
	Panel.Position = UDim2.new(0, V.PanelOffsetX, 1, -V.PanelOffsetY)
	Panel.Size = UDim2.new(0, V.PanelWidth, 0, V.LogHeight + V.InputBarHeight + V.TabBarHeight)
	Panel.BackgroundColor3 = V.PanelBackground
	Panel.BackgroundTransparency = V.PanelBackgroundAlpha
	Panel.BorderSizePixel = 0
	Panel.ClipsDescendants = false

	TabBar.Size = UDim2.new(1, 0, 0, V.TabBarHeight)
	TabBar.Position = UDim2.new(0, 0, 0, 0)
	TabBar.BackgroundTransparency = 1

	LogFrame.Size = UDim2.new(1, 0, 0, V.LogHeight)
	LogFrame.Position = UDim2.new(0, 0, 0, V.TabBarHeight)
	LogFrame.BackgroundTransparency = 1
	LogFrame.BorderSizePixel = 0
	LogFrame.ScrollBarThickness = 4
	LogFrame.ScrollBarImageColor3 = V.ScrollBarColor
	LogFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	LogFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	LogFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	LogFrame.VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Right

	InputBar.Size = UDim2.new(1, 0, 0, V.InputBarHeight)
	InputBar.Position = UDim2.new(0, 0, 0, V.TabBarHeight + V.LogHeight)
	InputBar.BackgroundColor3 = V.InputBackground
	InputBar.BackgroundTransparency = V.InputBackgroundAlpha
	InputBar.BorderSizePixel = 0

	NewMsgBtn.Size = UDim2.new(1, 0, 0, 22)
	NewMsgBtn.Position = UDim2.new(0, 0, 0, V.TabBarHeight + V.LogHeight - 22)
	NewMsgBtn.BackgroundTransparency = 0.2
	NewMsgBtn.BorderSizePixel = 0
	NewMsgBtn.TextSize = 13
	NewMsgBtn.Text = V.NewMessageButtonText
	NewMsgBtn.AutoButtonColor = false
	NewMsgBtn.Visible = false
	NewMsgBtn.ZIndex = 6

	-- Parent last — one reparent, no intermediate layout thrash
	gui.Parent = playerGui

	return gui, Panel, TabBar, LogFrame, InputBar, InputBox, SendBtn, NewMsgBtn
end

local ChatGui, Panel, TabBar, LogFrame, InputBar, InputBox, SendBtn, NewMsgBtn = cloneChatGui()

-- ===================== STATE =====================
local messages = {}
local activeChannel = ChatConfig.DefaultChannel
local tabButtons = {}
local isFocused = false
local isHovered = false
local lastSendTime = 0
local autoScroll = true
local layoutOrder = 0

-- Track which TextChatMessage IDs we've already rendered to avoid duplicates.
-- TextChatService.MessageReceived can fire twice for the sending client
-- (once as "pending", once as the server-confirmed message).
local renderedMsgIds = {}

-- ===================== FOCUS / TRANSPARENCY =====================

local panelTween = nil

local function setPanelTransparency(focused)
	local targetAlpha = focused and V.PanelFocusedAlpha or V.PanelBackgroundAlpha
	if panelTween then
		panelTween:Cancel()
	end
	panelTween = TweenService:Create(
		Panel,
		TweenInfo.new(V.TransitionTime, Enum.EasingStyle.Quad),
		{ BackgroundTransparency = targetAlpha }
	)
	panelTween:Play()
end

local function updateFocusState()
	local active = isFocused or isHovered
	setPanelTransparency(active)
	if active then
		for _, record in ipairs(messages) do
			for _, lbl in ipairs(record.labels) do
				lbl.TextTransparency = 0
			end
		end
	end
end

InputBox.Focused:Connect(function()
	isFocused = true
	updateFocusState()
end)

InputBox.FocusLost:Connect(function()
	isFocused = false
	updateFocusState()
end)

Panel.MouseEnter:Connect(function()
	isHovered = true
	updateFocusState()
end)

Panel.MouseLeave:Connect(function()
	isHovered = false
	updateFocusState()
end)

-- ===================== CHANNEL TABS =====================
for _, channelId in ipairs(ChatConfig.ChannelOrder) do
	local channelDef = ChatConfig.Channels[channelId]
	if channelDef then
		local tab = Instance.new("TextButton")
		tab.Name = channelId
		tab.AutomaticSize = Enum.AutomaticSize.X
		tab.Size = UDim2.new(0, 0, 1, -4)
		tab.BackgroundTransparency = 1
		tab.BorderSizePixel = 0
		tab.FontFace = V.ChatFont
		tab.TextSize = 13
		tab.AutoButtonColor = false
		tab.Text = channelDef.displayName
		tab.LayoutOrder = _

		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 6)
		p.PaddingRight = UDim.new(0, 6)
		p.Parent = tab

		tab.Parent = TabBar
		tabButtons[channelId] = tab
	end
end

local function refreshTabColors()
	for channelId, tab in pairs(tabButtons) do
		tab.TextColor3 = (channelId == activeChannel) and V.TabActiveColor or V.TabInactiveColor
	end
end
refreshTabColors()

for channelId, tab in pairs(tabButtons) do
	tab.MouseButton1Click:Connect(function()
		activeChannel = channelId
		refreshTabColors()
		for _, record in ipairs(messages) do
			local p = record.payload
			record.frame.Visible = (activeChannel == "all" and not p.hideFromAll) or (p.channel == activeChannel)
		end
	end)
end

-- ===================== SCROLL HELPERS =====================
local function scrollToBottom()
	RunService.Heartbeat:Wait()
	local canvasH = LogFrame.AbsoluteCanvasSize.Y
	local frameH = LogFrame.AbsoluteSize.Y
	LogFrame.CanvasPosition = Vector2.new(0, math.max(0, canvasH - frameH))
end

local function isNearBottom()
	local canvasH = LogFrame.AbsoluteCanvasSize.Y
	local frameH = LogFrame.AbsoluteSize.Y
	return (canvasH - frameH - LogFrame.CanvasPosition.Y) <= V.AutoScrollThreshold
end

-- ===================== MESSAGE RENDERING =====================

local function makeLineLabel(text, hexColor, isBold, order)
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Line_" .. order
	lbl.Size = UDim2.new(1, 0, 0, 0)
	lbl.AutomaticSize = Enum.AutomaticSize.Y
	lbl.BackgroundTransparency = 1
	lbl.TextStrokeTransparency = 0
	lbl.FontFace = V.ChatFont
	lbl.TextSize = V.FontSize
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextWrapped = true
	lbl.RichText = true
	lbl.LayoutOrder = order

	local display = text
	if isBold then
		display = "<b>" .. display .. "</b>"
	end
	if hexColor then
		display = '<font color="#' .. hexColor .. '">' .. display .. "</font>"
	end

	lbl.Text = display
	lbl.TextColor3 = hexColor and hexToColor3(hexColor) or V.PlayerTextColor
	return lbl
end

-- Core renderer — handles both player messages and system payloads.
local function renderPayload(payload)
	layoutOrder = layoutOrder + 1
	local order = layoutOrder

	local visible = (activeChannel == "all" and not payload.hideFromAll) or (payload.channel == activeChannel)

	local entry = Instance.new("Frame")
	entry.Name = "Msg_" .. order
	entry.AutomaticSize = Enum.AutomaticSize.Y
	entry.Size = UDim2.new(1, 0, 0, 0)
	entry.BackgroundTransparency = 1
	entry.BorderSizePixel = 0
	entry.LayoutOrder = order
	entry.Visible = visible
	entry.Parent = LogFrame

	local entryLayout = Instance.new("UIListLayout")
	entryLayout.FillDirection = Enum.FillDirection.Vertical
	entryLayout.SortOrder = Enum.SortOrder.LayoutOrder
	entryLayout.Padding = UDim.new(0, V.LineSpacing)
	entryLayout.Parent = entry

	local lineLabels = {}

	if payload.type == "player" then
		-- "DisplayName: message" — text is pre-filtered by TextChatService
		local nameHex = toHex(V.PlayerNameColor)
		local textHex = toHex(V.PlayerTextColor)

		local prefix = ""
		if B.ShowTimestamps then
			local t = payload.timestamp or os.time()
			local m = math.floor(t / 60) % 60
			local s = t % 60
			prefix = string.format('<font color="#%s">[%02d:%02d] </font>', toHex(V.TimestampColor), m, s)
		end

		local richText = string.format(
			'%s<font color="#%s"><b>%s</b></font><font color="#%s">: %s</font>',
			prefix,
			nameHex,
			payload.playerName or "?",
			textHex,
			payload.text or ""
		)

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Line_1"
		lbl.Size = UDim2.new(1, 0, 0, 0)
		lbl.AutomaticSize = Enum.AutomaticSize.Y
		lbl.BackgroundTransparency = 1
		lbl.TextStrokeTransparency = 0
		lbl.FontFace = V.ChatFont
		lbl.TextSize = V.FontSize
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextWrapped = true
		lbl.RichText = true
		lbl.Text = richText
		lbl.TextColor3 = V.PlayerTextColor
		lbl.LayoutOrder = 1
		lbl.Parent = entry
		table.insert(lineLabels, lbl)
	else
		-- Multi-line system block
		local channelDef = ChatConfig.Channels[payload.channel or "all"]
		local defaultHex = channelDef and toHex(channelDef.headerColor) or "DCDCDC"

		for i, lineText in ipairs(payload.lines) do
			if lineText == "" then
				local spacer = Instance.new("Frame")
				spacer.Name = "Spacer_" .. i
				spacer.Size = UDim2.new(1, 0, 0, 6)
				spacer.BackgroundTransparency = 1
				spacer.LayoutOrder = i
				spacer.Parent = entry
			else
				local hexColor = (payload.colors and payload.colors[i]) or defaultHex
				local isBold = payload.bold and payload.bold[i] == true
				local lbl = makeLineLabel(lineText, hexColor, isBold, i)
				lbl.Parent = entry
				table.insert(lineLabels, lbl)
			end
		end
	end

	-- Sound
	if payload.sound then
		local snd = Instance.new("Sound")
		snd.SoundId = payload.sound
		snd.Volume = 0.5
		snd.Parent = SoundService
		snd:Play()
		game:GetService("Debris"):AddItem(snd, 5)
	end

	local record = {
		payload = payload,
		frame = entry,
		labels = lineLabels,
		timestamp = payload.timestamp or os.time(),
	}
	table.insert(messages, record)

	if #messages > B.MaxHistory then
		local oldest = table.remove(messages, 1)
		oldest.frame:Destroy()
	end

	if autoScroll then
		task.defer(scrollToBottom)
	else
		NewMsgBtn.Visible = true
	end

	return record
end

ChatBridge.registerRenderer(renderPayload)

-- ===================== FADE SYSTEM =====================
RunService.Heartbeat:Connect(function()
	if isFocused or isHovered then
		return
	end
	local now = os.time()
	for _, record in ipairs(messages) do
		local age = now - record.timestamp
		local alpha
		if age < V.FadeStartAge then
			alpha = 0
		elseif age > V.FadeEndAge then
			alpha = 1
		else
			alpha = (age - V.FadeStartAge) / (V.FadeEndAge - V.FadeStartAge)
		end
		for _, lbl in ipairs(record.labels) do
			lbl.TextTransparency = alpha
		end
	end
end)

-- ===================== SEND MESSAGE =====================
-- Route through TextChannel:SendAsync — Roblox filters automatically.
local function trySendMessage()
	local text = InputBox.Text
	if text == "" then
		return
	end
	if not RBXGeneral then
		warn("[ChatController] Cannot send: RBXGeneral TextChannel not found.")
		return
	end

	local now = tick()
	if now - lastSendTime < B.SendRateLimit then
		return
	end
	lastSendTime = now

	local msgText = text
	InputBox.Text = ""
	InputBox:ReleaseFocus()

	-- SendAsync yields — run in a separate thread so UI doesn't block
	task.spawn(function()
		local ok, err = pcall(function()
			RBXGeneral:SendAsync(msgText)
		end)
		if not ok then
			warn("[ChatController] SendAsync failed:", err)
		end
	end)
end

InputBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		trySendMessage()
	end
end)

SendBtn.MouseButton1Click:Connect(trySendMessage)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Slash then
		InputBox:CaptureFocus()
	end
end)

-- ===================== RECEIVE PLAYER MESSAGES =====================
-- TextChatService.MessageReceived fires on every client when a message
-- is delivered by the server. msg.Text is already filtered by Roblox.
-- msg.TextSource contains the sender's UserId.
--
-- IMPORTANT: This fires TWICE for the sending client —
--   1. Immediately as a "pending" message (MessageId may be provisional)
--   2. Again when the server confirms delivery (with final filtered text)
-- We deduplicate on MessageId to avoid showing the same message twice.
-- However, the second fire has the real filtered text, so if both fire
-- we want the second one. Strategy: always render on first fire, then
-- on second fire UPDATE the existing entry if it matches the same ID.

TextChatService.MessageReceived:Connect(function(msg)
	-- msg.Text is empty when the message is in "pending" state (before server confirms).
	-- Skip pending messages — wait for the confirmed version.
	if not msg.Text or msg.Text == "" then
		return
	end

	-- Get the sender's display name
	local senderName = "Server"
	if msg.TextSource then
		local userId = msg.TextSource.UserId
		local senderPlayer = Players:GetPlayerByUserId(userId)
		if senderPlayer then
			senderName = senderPlayer.DisplayName
		end
	end

	-- Deduplicate: if we've already rendered this MessageId, skip
	local msgId = msg.MessageId
	if msgId and msgId ~= "" then
		if renderedMsgIds[msgId] then
			return
		end
		renderedMsgIds[msgId] = true

		-- Prune old IDs to prevent memory leak (keep last 200)
		local count = 0
		for _ in pairs(renderedMsgIds) do
			count = count + 1
		end
		if count > 200 then
			renderedMsgIds = {}
		end
	end

	local payload = {
		type = "player",
		playerName = senderName,
		text = msg.Text, -- already filtered by Roblox
		channel = "all",
		timestamp = os.time(),
	}

	renderPayload(payload)
end)

-- ===================== RECEIVE SYSTEM MESSAGES =====================
SystemMsg.OnClientEvent:Connect(function(payload)
	renderPayload(payload)
end)

-- ===================== SCROLL TRACKING =====================
LogFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
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

-- ===================== STARTUP MESSAGE =====================
task.defer(function()
	ChatBridge.postRaw({
		"",
		"  Welcome to Fractured Islands: Ascension",
		"  Press / to chat.",
		"  Custom chat is in early beta — expect bugs and missing features!",
		"",
	}, {
		[2] = toHex(Color3.fromHex("#FF55FF")),
		[3] = toHex(Color3.fromHex("#AAAAAA")),
		[4] = toHex(Color3.fromHex("#FF5555")),
	}, { [2] = true }, "game")
end)

print("[ChatController] Loaded ✓")
