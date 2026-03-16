-- ============================================================
--  AdminCommandsClient (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  Registers /give, /clear, /cap as TextChatCommands so they
--  appear in Roblox's native command autocomplete.
--
--  Also builds a custom item-ID dropdown that activates while
--  the player is typing after "/give ".
--
--  WHY HEARTBEAT POLLING:
--    GetPropertyChangedSignal("Text") silently fails on TextBox
--    instances that live inside CoreGui (Roblox's chat bar).
--    Polling with UserInputService:GetFocusedTextBox() is the
--    only reliable cross-boundary way to read live chat input.
-- ============================================================

local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================== ADMIN GATE =====================
local ADMIN_IDS = { 288851273 }
local function isAdmin()
	for _, id in ipairs(ADMIN_IDS) do
		if player.UserId == id then
			return true
		end
	end
	return false
end
if not isAdmin() then
	return
end

-- ===================== DEPS =====================
local AdminCommandEvent = ReplicatedStorage:WaitForChild("AdminCommandEvent")
local ItemRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemRegistry"))

-- Build a sorted list of all item IDs once at startup
local ALL_ITEM_IDS = {}
for id in pairs(ItemRegistry.Items) do
	table.insert(ALL_ITEM_IDS, id)
end
table.sort(ALL_ITEM_IDS)

-- ===================== CONSTANTS =====================
local ENTRY_HEIGHT = 28
local MAX_VISIBLE = 12
local FRAME_WIDTH = 360
local GIVE_PREFIX = "/give " -- lower-case match target

local RARITY_COLORS = {
	[0] = "AAAAAA", -- Common
	[1] = "55FF55", -- Uncommon
	[2] = "5555FF", -- Rare
	[3] = "FF55FF", -- Epic
	[4] = "FFAA00", -- Legendary
	[5] = "FF5555", -- Mythic
}

-- ===================== AUTOCOMPLETE GUI =====================
local acGui = Instance.new("ScreenGui")
acGui.Name = "AdminAutocomplete"
acGui.ResetOnSpawn = false
acGui.DisplayOrder = 9999
acGui.IgnoreGuiInset = true
acGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
acGui.Parent = playerGui

local acFrame = Instance.new("Frame")
acFrame.Name = "DropdownFrame"
acFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
acFrame.BackgroundTransparency = 0
acFrame.BorderSizePixel = 0
acFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, 0)
acFrame.Visible = false
acFrame.ZIndex = 10
acFrame.ClipsDescendants = true
acFrame.Parent = acGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 5)
uiCorner.Parent = acFrame

local uiStroke = Instance.new("UIStroke")
uiStroke.Color = Color3.fromRGB(70, 70, 100)
uiStroke.Thickness = 1
uiStroke.Parent = acFrame

local uiList = Instance.new("UIListLayout")
uiList.FillDirection = Enum.FillDirection.Vertical
uiList.SortOrder = Enum.SortOrder.LayoutOrder
uiList.Parent = acFrame

-- ===================== STATE =====================
local entryPool = {} -- reusable row buttons
local lastPolledText = "" -- last text we acted on
local lastChatTextBox = nil -- last known chat TextBox (survives focus loss)
local acVisible = false

-- ===================== SHOW / HIDE =====================
local function hideDropdown()
	if not acVisible then
		return
	end
	acVisible = false
	acFrame.Visible = false
end

local function showDropdown(matches, textBox)
	if #matches == 0 then
		hideDropdown()
		return
	end

	local count = math.min(#matches, MAX_VISIBLE)

	-- Grow or create pool entries
	for i = 1, count do
		if not entryPool[i] then
			local btn = Instance.new("TextButton")
			btn.Name = "ACEntry" .. i
			btn.Size = UDim2.new(1, 0, 0, ENTRY_HEIGHT)
			btn.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
			btn.BackgroundTransparency = 0
			btn.BorderSizePixel = 0
			btn.Font = Enum.Font.Code
			btn.TextSize = 13
			btn.TextXAlignment = Enum.TextXAlignment.Left
			btn.RichText = true
			btn.AutoButtonColor = false
			btn.LayoutOrder = i
			btn.ZIndex = 11

			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 10)
			pad.Parent = btn

			btn.Parent = acFrame

			-- Wire hover + click ONCE at creation time.
			-- Click reads the "ItemId" attribute set each refresh cycle,
			-- so we never capture a stale upvalue from the loop.
			btn.MouseEnter:Connect(function()
				btn.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
			end)
			btn.MouseLeave:Connect(function()
				btn.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
			end)
			btn.MouseButton1Click:Connect(function()
				local itemId = btn:GetAttribute("ItemId")
				if not itemId then
					return
				end
				local tb = lastChatTextBox
				if tb then
					local filled = GIVE_PREFIX .. itemId .. " "
					tb.Text = filled
					tb.CursorPosition = #filled + 1
					tb:CaptureFocus()
				end
				hideDropdown()
			end)

			entryPool[i] = btn
		end

		local btn = entryPool[i]
		local id = matches[i]
		local config = ItemRegistry.Items[id]
		local rarity = config and config.rarity or 0
		local hex = RARITY_COLORS[rarity] or RARITY_COLORS[0]
		local name = config and config.displayName or id

		btn:SetAttribute("ItemId", id)
		btn.Text = string.format('<font color="#%s">%s</font>  <font color="#666677">%s</font>', hex, id, name)
		btn.Visible = true
	end

	-- Hide unused pool entries beyond the current match count
	for i = count + 1, #entryPool do
		entryPool[i].Visible = false
	end

	-- Resize frame to fit exactly `count` rows
	local frameH = count * ENTRY_HEIGHT
	acFrame.Size = UDim2.new(0, FRAME_WIDTH, 0, frameH)

	-- Position above the chat input bar using its AbsolutePosition.
	-- GetFocusedTextBox() returns CoreGui TextBoxes and their
	-- AbsolutePosition is readable from a LocalScript.
	if textBox and textBox.AbsolutePosition and textBox.AbsoluteSize then
		local ap = textBox.AbsolutePosition
		acFrame.Position = UDim2.fromOffset(ap.X, ap.Y - frameH - 6)
	else
		-- Fallback: fixed lower-left above typical Roblox chat bar
		local vp = workspace.CurrentCamera.ViewportSize
		acFrame.Position = UDim2.fromOffset(8, vp.Y - frameH - 110)
	end

	acFrame.Visible = true
	acVisible = true
end

-- ===================== FILTER =====================
local function computeMatches(text)
	-- Must start with "/give " (case-insensitive)
	if text:sub(1, #GIVE_PREFIX):lower() ~= GIVE_PREFIX then
		return nil -- not a /give command
	end

	local query = text:sub(#GIVE_PREFIX + 1)

	-- Once the count argument starts (a space after the item ID), hide
	if query:find(" ") then
		return nil
	end

	local lower = query:lower()
	local matches = {}

	for _, id in ipairs(ALL_ITEM_IDS) do
		if lower == "" or id:lower():find(lower, 1, true) then
			table.insert(matches, id)
			if #matches >= MAX_VISIBLE then
				break
			end
		end
	end

	return matches
end

-- ===================== HEARTBEAT POLL =====================
-- Polls GetFocusedTextBox() every frame.  This is the only
-- reliable way to read text from the Roblox CoreGui chat bar,
-- because GetPropertyChangedSignal("Text") is silently blocked
-- across the CoreGui boundary from a LocalScript.

local hideScheduled = false

RunService.Heartbeat:Connect(function()
	local tb = UserInputService:GetFocusedTextBox()

	if tb then
		lastChatTextBox = tb
		hideScheduled = false
		local text = tb.Text

		if text ~= lastPolledText then
			lastPolledText = text
			local matches = computeMatches(text)
			if matches then
				showDropdown(matches, tb)
			else
				hideDropdown()
			end
		end
	else
		-- No TextBox focused.
		-- Delay the hide so a MouseButton1Click on a dropdown entry
		-- (which briefly clears focus) has time to fire first.
		if acVisible and not hideScheduled then
			hideScheduled = true
			task.delay(0.18, function()
				hideScheduled = false
				if not UserInputService:GetFocusedTextBox() then
					hideDropdown()
					lastPolledText = ""
				end
			end)
		end
	end
end)

-- ===================== TEXTCHAT COMMANDS =====================
-- These register /give, /clear, /cap with Roblox's own native
-- command-autocomplete list (the dropdown that appears when you
-- type "/").  Triggered fires after the player submits — the
-- live-typing autocomplete is handled above via Heartbeat.

local function parseArgs(fullText)
	local parts = {}
	for word in fullText:gmatch("%S+") do
		table.insert(parts, word)
	end
	-- parts[1] is the alias ("/give"), strip it
	local args = {}
	for i = 2, #parts do
		table.insert(args, parts[i])
	end
	return args
end

local function makeCmd(name, primary)
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = name
	cmd.PrimaryAlias = primary
	cmd.Parent = TextChatService
	return cmd
end

local giveCmd = makeCmd("AdminGive", "/give")
local clearCmd = makeCmd("AdminClear", "/clear")
local capCmd = makeCmd("AdminCap", "/cap")

giveCmd.Triggered:Connect(function(_, unfilteredText)
	hideDropdown()
	AdminCommandEvent:FireServer("give", parseArgs(unfilteredText))
end)

clearCmd.Triggered:Connect(function()
	AdminCommandEvent:FireServer("clear", {})
end)

capCmd.Triggered:Connect(function(_, unfilteredText)
	AdminCommandEvent:FireServer("cap", parseArgs(unfilteredText))
end)

print("[AdminCommandsClient] Loaded ✓")
