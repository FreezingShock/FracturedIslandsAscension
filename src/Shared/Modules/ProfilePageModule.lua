-- ============================================================
--  ProfilePageModule (ModuleScript)
--  Place inside: TemporaryMenus (next to ProfileMenu frame)
--
--  Replaces: ProfileMenuHandler (LocalScript) + StatUpdate script
--
--  API:
--    init(sharedRefs, profileMenuFrame)
--    open()          — user clicks Profile grid button
--    close()         — animated navigation away
--    reset()         — instant hard-close
--    navigateBack()  — return from stat breakdown to stat list
-- ============================================================

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")

-- ===================== MODULE STATE =====================
local initialized = false
local isOpen = false

-- Shared references (set by init)
local shared = nil
local TooltipModule = nil

-- Frame references (set by init)
local profileMenuFrame = nil
local scrollingFrame = nil
local statDescFrame = nil

-- ===================== STAT BUTTONS CONFIG =====================
-- Built in init() once we have frame references.
local statButtons = nil

local PAGE_TITLES = {
	Obtainment = "Obtainment Guide",
	Flat = "Flat Boosts",
	Multiplier = "Multiplier Boosts",
}

local PAGE_COLORS = {
	Obtainment = Color3.fromHex("#FF55FF"),
	Flat = Color3.fromHex("#FFFF55"),
	Multiplier = Color3.fromHex("#55FF55"),
}

-- ===================== TYPEWRITER =====================
local typewriterThreads = {}

local function typewrite(label, text, speed)
	speed = speed or 0.03
	if typewriterThreads[label] then
		typewriterThreads[label] = false
	end
	local token = {}
	typewriterThreads[label] = token
	label.Text = text
	label.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		for i = 1, length do
			if typewriterThreads[label] ~= token then
				return
			end
			label.MaxVisibleGraphemes = i
			task.wait(speed)
		end
		label.MaxVisibleGraphemes = -1
		if typewriterThreads[label] == token then
			typewriterThreads[label] = nil
		end
	end)
end

-- ===================== TWEEN HELPER =====================
local uiTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
local function tween(object, properties)
	TweenService:Create(object, uiTweenInfo, properties):Play()
end

-- ===================== DESC FRAME REFERENCES =====================
local statNameLabel = nil
local statUIStroke = nil
local statUnderline = nil
local descLabel = nil
local line = nil
local statValueLabel = nil

local Pages = nil
local flatBoosts = nil
local multBoosts = nil
local obtainmentBtn = nil

local currentPage = nil
local scrolling = nil
local pageDesc = nil
local titleFrame = nil
local pageTitle = nil
local totalFrame = nil
local totalLabel = nil

-- Search box references
local searchBoxOuter = nil
local searchBoxInner = nil
local searchBox = nil

-- Stat name labels (for typewriter restore)
local statNameLabels = {}

-- ===================== STAT DATA =====================
local latestStatData = nil

local DEFAULT_FLAT = {
	Speed = { flatBoosts = { { label = "Default", value = 16 } }, multipliers = { { label = "Default", value = 1 } } },
	JumpHeight = {
		flatBoosts = { { label = "Default", value = 7.2 } },
		multipliers = { { label = "Default", value = 1 } },
	},
	PressSpeed = { flatBoosts = {}, multipliers = { { label = "Default", value = 1 } } },
}

local function getStatEntry(dmKey)
	if latestStatData then
		local entry = latestStatData[dmKey]
		if entry and type(entry) == "table" then
			return entry
		end
	end
	return DEFAULT_FLAT[dmKey] or { flatBoosts = {}, multipliers = {} }
end

-- ===================== FLAT BOOST TEXT =====================
local function buildFlatBoostText(dmKey)
	local entry = getStatEntry(dmKey)
	local boosts = entry.flatBoosts or {}

	local hex = "#FFFFFF"
	local statName = ""
	for _, e in ipairs(statButtons) do
		if e.dmKey == dmKey then
			hex = e.hex
			statName = e.stat
			break
		end
	end

	if #boosts == 0 then
		return "No flat boosts yet.", ""
	end

	local lines = {}
	local total = 0
	for _, boost in ipairs(boosts) do
		total = total + tonumber(boost.value)
		local valStr = (boost.value == math.floor(boost.value)) and tostring(math.floor(boost.value))
			or tostring(boost.value)
		table.insert(
			lines,
			string.format(
				"<font color='#555555'>‣</font> <font color='#55FF55'>+%s</font><font color='#777777'> — </font><font color='%s'>%s</font>",
				valStr,
				boost.color or "#FFFF55",
				boost.label
			)
		)
	end

	local totalStr = (total == math.floor(total)) and tostring(math.floor(total)) or string.format("%.2f", total)

	local mults = entry.multipliers or {}
	local hasMultipliers = false
	for _, m in ipairs(mults) do
		if m.value ~= 1 then
			hasMultipliers = true
			break
		end
	end

	local totalLine =
		string.format("<font color='#AAAAAA'>Flat Total:  </font><font color='#FFFF55'>%s</font>", totalStr)

	if hasMultipliers then
		totalLine = totalLine
			.. "\n"
			.. string.format(
				"<font color='#AAAAAA'><i>%s<font color='#555555'> is affected by multiplier.</font></i></font>",
				"<font color='" .. hex .. "'>" .. statName .. "</font>"
			)
	end

	return table.concat(lines, "\n"), totalLine
end

-- ===================== MULTIPLIER TEXT =====================
local function buildMultiplierText(dmKey)
	local entry = getStatEntry(dmKey)
	local mults = entry.multipliers or {}

	local displayName = ""
	local hex = "#FFFFFF"
	for _, e in ipairs(statButtons) do
		if e.dmKey == dmKey then
			displayName = e.stat
			hex = e.hex
			break
		end
	end

	local lines = {}
	local totalBonus = 0
	local flatTotal = 0
	local flatBoostsList = entry.flatBoosts or {}
	for _, boost in ipairs(flatBoostsList) do
		flatTotal = flatTotal + tonumber(boost.value)
	end

	if #mults == 0 then
		lines[#lines + 1] = "<font color='#555555'>No multipliers yet.</font>"
	else
		for _, mult in ipairs(mults) do
			local bonus = (tonumber(mult.value) or 1) - 1
			totalBonus = totalBonus + bonus
			local pctStr = string.format("+%.4g%%", bonus * 100)
			local xStr = string.format("×%.4g", mult.value)
			table.insert(
				lines,
				string.format(
					"<font color='#555555'>‣</font> <font color='#55FF55'>%s</font> <font color='#555555'>(%s)</font><font color='#555555'> — </font><font color='%s'>%s</font>",
					xStr,
					pctStr,
					mult.color or "#FFFF55",
					mult.label
				)
			)
		end
	end

	local combinedMult = 1 + totalBonus
	local boostedAmount = flatTotal * combinedMult

	local flatStr = (flatTotal == math.floor(flatTotal)) and tostring(math.floor(flatTotal))
		or string.format("%.2f", flatTotal)

	local multStr = string.format("%.4g", combinedMult)

	local boostedStr = (boostedAmount == math.floor(boostedAmount)) and tostring(math.floor(boostedAmount))
		or string.format("%.2f", boostedAmount)

	local totalLine = string.format(
		"<font color='#AAAAAA'>Multiplier: </font><font color='#55FF55'>×%s (+%.4g%%)</font>\n"
			.. "<font color='#AAAAAA'>Multiplied Total: </font><font color='#55FF55'>%s </font><font color='%s'>%s</font>\n"
			.. "<font color='#FFFF55'>%s </font><font color='#AAAAAA'>×</font><font color='#55FF55'> %s </font><font color='#AAAAAA'>= </font><font color='#FFAA00'>%s</font>",
		multStr,
		totalBonus * 100,
		boostedStr,
		hex,
		displayName,
		flatStr,
		multStr,
		boostedStr
	)

	return table.concat(lines, "\n"), totalLine
end

-- ===================== PAGE CONTENT =====================
local function getPageContent(statKey, pageType)
	local entry = nil
	for _, e in ipairs(statButtons) do
		if e.statKey == statKey then
			entry = e
			break
		end
	end
	if not entry then
		return { title = "Unknown", desc = "No data.", total = "" }
	end

	local title = PAGE_TITLES[pageType]
		.. " <font color='#AAAAAA'>-</font> "
		.. "<font color='"
		.. entry.hex
		.. "'>"
		.. entry.stat
		.. "</font>"

	local desc, total
	if pageType == "Flat" then
		desc, total = buildFlatBoostText(entry.dmKey)
	elseif pageType == "Multiplier" then
		desc, total = buildMultiplierText(entry.dmKey)
	else
		desc = entry.pages[pageType] or "No data."
		total = ""
	end

	return { title = title, desc = desc, total = total or "" }
end

-- ===================== STATE =====================
local activeStatKey = nil
local activePageType = "Obtainment"
local internalView = "list" -- "list" or "breakdown"

-- ===================== GRADIENT (instant swap) =====================
local GRADIENT_DEFAULT = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("#646464")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("#FFFFFF")),
})
local GRADIENT_SELECTED = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromHex("#4b4b4b")),
	ColorSequenceKeypoint.new(1, Color3.fromHex("#c8c8c8")),
})

local function setGradient(button, colorSeq)
	local g = button:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = colorSeq
	end
end

local pageButtons = nil -- set in init

local function updateButtonGradients(selectedPageType)
	for pageType, btn in pairs(pageButtons) do
		setGradient(btn, pageType == selectedPageType and GRADIENT_SELECTED or GRADIENT_DEFAULT)
	end
end

-- ===================== SHOW PAGE =====================
local function showPage(pageType)
	if not activeStatKey or not pageType then
		return
	end
	local content = getPageContent(activeStatKey, pageType)
	updateButtonGradients(pageType)
	typewrite(pageDesc, content.desc)
	typewrite(pageTitle, content.title, 0.01)

	local pageColor = PAGE_COLORS[pageType] or Color3.fromHex("#FFFFFF")
	currentPage.UIStroke.Color = pageColor
	currentPage.TitleFrame.Underline.BackgroundColor3 = pageColor
	totalFrame.Underline.BackgroundColor3 = pageColor
	pageTitle.TextColor3 = pageColor
	scrolling.ScrollBarImageColor3 = pageColor
	totalFrame.BackgroundColor3 = pageColor
	titleFrame.BackgroundColor3 = pageColor
	totalFrame.ImageColor3 = pageColor

	if content.total and content.total ~= "" then
		typewrite(totalLabel, content.total, 0.02)
		totalFrame.Visible = true
	else
		totalLabel.Text = ""
		totalFrame.Visible = false
	end
end

-- ===================== STAT COLOR =====================
local function applyStatColor(color)
	statNameLabel.TextColor3 = color
	statUIStroke.Color = color
	statUnderline.BackgroundColor3 = color
	line.BackgroundColor3 = color
	line.UIStroke.Color = color
	statDescFrame.StatNameVal.StatValue.Underline.BackgroundColor3 = color
end

-- ===================== SEARCH FILTER =====================
local function applySearchFilter(query)
	if not statButtons then
		return
	end
	query = string.lower(query or "")
	for _, entry in ipairs(statButtons) do
		local btn = entry.button
		-- The button's parent hierarchy: stat card frame
		local card = entry.cardFrame
		if card then
			if query == "" then
				card.Visible = true
			else
				card.Visible = string.find(string.lower(entry.stat), query, 1, true) ~= nil
			end
		end
	end
end

-- ===================== OPEN STAT BREAKDOWN =====================
local function onStatButtonClicked(statName, statKey, description, color)
	activeStatKey = statKey
	activePageType = "Obtainment"
	internalView = "breakdown"
	totalLabel.Text = ""
	totalFrame.Visible = false

	shared.pushSubPage("StatBreakdown:" .. statKey)
	shared.typewriteTitle("Stat Breakdown")

	applyStatColor(color)
	showPage("Obtainment")

	UIClick:Play()
	tween(scrollingFrame, { Position = UDim2.fromScale(-1, 0) })
	tween(statDescFrame, { Position = UDim2.new(0, 0, 0, 0) })
	tween(searchBoxOuter, { Position = UDim2.new(1, -205, -1, 4) })
	task.wait(0.125)
	typewrite(statNameLabel, statName, 0.05)
	typewrite(descLabel, description, 0.025)

	-- Blank all stat name labels
	for _, entry in ipairs(statButtons) do
		if statNameLabels[entry.statKey] then
			statNameLabels[entry.statKey].Text = ""
		end
	end
end

-- ===================== RESTORE STAT LIST =====================
local function restoreStatList()
	shared.typewriteTitle("Your Profile")
	UIClick:Play()
	tween(statDescFrame, { Position = UDim2.fromScale(1, 0) })
	tween(scrollingFrame, { Position = UDim2.new(0, 0, 0, 0) })
	tween(searchBoxOuter, { Position = UDim2.new(1, -205, 0, 4) })

	for _, btn in pairs(pageButtons) do
		setGradient(btn, GRADIENT_DEFAULT)
	end

	task.wait(0.25)
	for _, entry in ipairs(statButtons) do
		local label = statNameLabels[entry.statKey]
		if label then
			typewrite(label, entry.stat)
		end
	end
end

-- ===================== LIVE STAT VALUE (Heartbeat) =====================
local dmKeyMap = {
	Walkspeed = "Speed",
	JumpHeight = "JumpHeight",
	PressSpeed = "PressSpeed",
}

local lastDisplayedTotal = nil
local lastDisplayedKey = nil

-- ===================== MODULE API =====================
local M = {}

function M.init(sharedRefs, frame)
	if initialized then
		return
	end
	initialized = true

	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule
	profileMenuFrame = frame

	scrollingFrame = profileMenuFrame:WaitForChild("ScrollingFrame")
	statDescFrame = profileMenuFrame:WaitForChild("StatDescFrame")

	-- Search box from shared topBarFrame
	searchBoxOuter = shared.topBarFrame:WaitForChild("searchBoxOuter")
	local searchBoxInnerFrame = searchBoxOuter:FindFirstChild("searchBoxInner")
	if searchBoxInnerFrame then
		searchBox = searchBoxInnerFrame:FindFirstChild("searchBox")
	end

	-- Desc frame internals
	statNameLabel = statDescFrame.StatNameVal.StatName
	statUIStroke = statNameLabel.UIStroke
	statUnderline = statNameLabel.Underline
	descLabel = statDescFrame.Desc.DescLabel
	line = statDescFrame.StatNameVal.LineDivider.Line
	statValueLabel = statDescFrame.StatNameVal.StatValue

	Pages = statDescFrame.Pages
	flatBoosts = Pages.FlatBoosts
	multBoosts = Pages.MultiplierBoosts
	obtainmentBtn = Pages.ObtainmentGuide

	currentPage = statDescFrame.CurrentPage
	scrolling = currentPage.ScrollingBB.Scrolling
	pageDesc = scrolling.Desc
	titleFrame = currentPage.TitleFrame
	pageTitle = titleFrame.Title
	totalFrame = currentPage.TotalFrame
	totalLabel = totalFrame.Total

	pageButtons = {
		Obtainment = obtainmentBtn,
		Flat = flatBoosts,
		Multiplier = multBoosts,
	}

	-- Build stat buttons config
	statButtons = {
		{
			cardFrame = scrollingFrame:WaitForChild("PressSpeed"),
			button = scrollingFrame:WaitForChild("PressSpeed"),
			stat = "Press Speed",
			statKey = "PressSpeed",
			dmKey = "PressSpeed",
			description = "Increases how many times the player can press a button in 1 second.",
			color = Color3.fromHex("#FFAA00"),
			hex = "#FFAA00",
			pages = { Obtainment = "1.\n2.\n3." },
		},
		{
			cardFrame = scrollingFrame:WaitForChild("Walkspeed"),
			button = scrollingFrame:WaitForChild("Walkspeed"),
			stat = "Speed",
			statKey = "Walkspeed",
			dmKey = "Speed",
			description = "Increases the player's movement speed.",
			color = Color3.fromHex("#FFFFFF"),
			hex = "#FFFFFF",
			pages = {
				Obtainment = "Speed can be increased through Speed upgrades in the Shop and by reaching certain rebirth thresholds.\n\nSome limited-time events also reward permanent speed bonuses.",
			},
		},
		{
			cardFrame = scrollingFrame:WaitForChild("JumpHeight"),
			button = scrollingFrame:WaitForChild("JumpHeight"),
			stat = "Jump Height",
			statKey = "JumpHeight",
			dmKey = "JumpHeight",
			description = "Increases the player's jump height.",
			color = Color3.fromHex("#55FF55"),
			hex = "#55FF55",
			pages = {
				Obtainment = "Jump Height improves by purchasing Jump upgrades in the Shop or equipping certain accessories.\n\nThe 'High Jumper' gamepass provides a strong permanent multiplier.",
			},
		},
		{
			cardFrame = scrollingFrame:WaitForChild("CriticalChance"),
			button = scrollingFrame:WaitForChild("CriticalChance"),
			stat = "Critical Chance",
			statKey = "CriticalChance",
			dmKey = "CriticalChance",
			description = "Chance to deal a critical hit when pressing buttons.",
			color = Color3.fromHex("#5555FF"),
			hex = "#5555FF",
			pages = { Obtainment = "Critical Chance is obtained through accessories and skill milestones." },
		},
		{
			cardFrame = scrollingFrame:WaitForChild("CriticalIncrease"),
			button = scrollingFrame:WaitForChild("CriticalIncrease"),
			stat = "Critical Increase",
			statKey = "CriticalIncrease",
			dmKey = "CriticalIncrease",
			description = "Multiplier applied when a critical hit occurs.",
			color = Color3.fromHex("#FF55FF"),
			hex = "#FF55FF",
			pages = { Obtainment = "Critical Increase comes from enchantments and accessories." },
		},
		{
			cardFrame = scrollingFrame:WaitForChild("MagicFind"),
			button = scrollingFrame:WaitForChild("MagicFind"),
			stat = "Magic Find",
			statKey = "MagicFind",
			dmKey = "MagicFind",
			description = "Boosts the chance of finding rare drops.",
			color = Color3.fromHex("#55FFFF"),
			hex = "#55FFFF",
			pages = { Obtainment = "Magic Find scales with all skills combined and certain rare accessories." },
		},
	}

	-- Build stat name label refs
	for _, entry in ipairs(statButtons) do
		local bb = entry.cardFrame:FindFirstChild("BoundingBox")
		if bb then
			statNameLabels[entry.statKey] = bb:FindFirstChild("StatName")
		end
	end

	-- Initial positions
	scrollingFrame.Position = UDim2.fromScale(0, 0)
	statDescFrame.Position = UDim2.fromScale(1, 0)

	-- ===================== WIRE STAT BUTTON CLICKS (ONCE) =====================
	for _, entry in ipairs(statButtons) do
		local captured = entry
		entry.button.MouseButton1Click:Connect(function()
			if not isOpen then
				return
			end
			onStatButtonClicked(captured.stat, captured.statKey, captured.description, captured.color)
		end)
	end

	-- ===================== WIRE PAGE TAB HOVERS (ONCE) =====================
	local function wirePageButton(button, pageType)
		button.MouseEnter:Connect(function()
			if not isOpen or internalView ~= "breakdown" then
				return
			end
			activePageType = pageType
			UIClick:Play()
			showPage(pageType)
		end)
	end

	wirePageButton(obtainmentBtn, "Obtainment")
	wirePageButton(flatBoosts, "Flat")
	wirePageButton(multBoosts, "Multiplier")

	-- ===================== WIRE SEARCH BOX (ONCE) =====================
	if searchBox then
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			if not isOpen or internalView ~= "list" then
				return
			end
			applySearchFilter(searchBox.Text)
		end)

		searchBox.FocusLost:Connect(function()
			-- Don't clear — keep the filter active until cleared by user
		end)
	end

	-- ===================== HEARTBEAT: LIVE STAT VALUE =====================
	RunService.Heartbeat:Connect(function()
		if not isOpen or not activeStatKey or not latestStatData then
			return
		end
		local dmKey = dmKeyMap[activeStatKey]
		if not dmKey then
			return
		end

		local statTable = latestStatData[dmKey]
		if not statTable then
			return
		end

		local flat = 0
		if type(statTable.flatBoosts) == "table" then
			for _, boost in ipairs(statTable.flatBoosts) do
				local v = tonumber(boost.value)
				if v then
					flat = flat + v
				end
			end
		end

		local mult = 1
		if type(statTable.multipliers) == "table" then
			local bonus = 0
			for _, m in ipairs(statTable.multipliers) do
				local v = tonumber(m.value)
				if v then
					bonus = bonus + (v - 1)
				end
			end
			mult = 1 + bonus
		end

		local total = flat * mult
		if total ~= lastDisplayedTotal or activeStatKey ~= lastDisplayedKey then
			lastDisplayedTotal = total
			lastDisplayedKey = activeStatKey
			local totalStr = (total == math.floor(total)) and tostring(math.floor(total))
				or string.format("%.2f", total)
			statValueLabel.Text = totalStr
		end
	end)

	-- ===================== HEARTBEAT: STAT CARD VALUE LABELS =====================
	-- Updates the stat value shown on each card in the list view (like old StatUpdate script)
	RunService.Heartbeat:Connect(function()
		if not isOpen or not latestStatData then
			return
		end
		if internalView ~= "list" then
			return
		end

		for _, entry in ipairs(statButtons) do
			local dmKey = dmKeyMap[entry.statKey] or entry.dmKey
			local statTable = latestStatData[dmKey]
			if statTable then
				local flat = 0
				if type(statTable.flatBoosts) == "table" then
					for _, boost in ipairs(statTable.flatBoosts) do
						local v = tonumber(boost.value)
						if v then
							flat = flat + v
						end
					end
				end
				local mult = 1
				if type(statTable.multipliers) == "table" then
					local bonus = 0
					for _, m in ipairs(statTable.multipliers) do
						local v = tonumber(m.value)
						if v then
							bonus = bonus + (v - 1)
						end
					end
					mult = 1 + bonus
				end
				local total = flat * mult
				local bb = entry.cardFrame:FindFirstChild("BoundingBox")
				if bb then
					local valLabel = bb:FindFirstChild("StatValue")
					if valLabel then
						local totalStr = (total == math.floor(total)) and tostring(math.floor(total))
							or string.format("%.2f", total)
						valLabel.Text = totalStr
					end
				end
			end
		end
	end)

	-- ===================== SERVER STAT SYNC =====================
	local StatUpdated = ReplicatedStorage:WaitForChild("StatUpdated")
	local RequestStats = ReplicatedStorage:WaitForChild("RequestStats")

	local function sanitizeStatData(data)
		if type(data) ~= "table" then
			return
		end
		for _, statTable in pairs(data) do
			if type(statTable) == "table" then
				if type(statTable.flatBoosts) == "table" then
					for _, b in ipairs(statTable.flatBoosts) do
						b.value = tonumber(b.value) or 0
					end
				end
				if type(statTable.multipliers) == "table" then
					for _, m in ipairs(statTable.multipliers) do
						m.value = tonumber(m.value) or 1
					end
				end
			end
		end
	end

	if StatUpdated then
		StatUpdated.OnClientEvent:Connect(function(data)
			sanitizeStatData(data)
			latestStatData = data
			-- If we're viewing a breakdown page, refresh it silently
			if isOpen and activeStatKey and internalView == "breakdown" then
				local ok, err = pcall(function()
					showPage(activePageType)
				end)
				if not ok then
					warn("ProfilePage showPage error: " .. tostring(err))
				end
			end
		end)
	end

	-- Request initial data
	if RequestStats then
		task.delay(1, function()
			RequestStats:FireServer()
		end)
	end

	print("ProfilePageModule: Initialized ✓")
end

function M.open()
	isOpen = true
	internalView = "list"
	activeStatKey = nil
	activePageType = "Obtainment"
	lastDisplayedTotal = nil
	lastDisplayedKey = nil

	-- Reset positions
	scrollingFrame.Position = UDim2.fromScale(0, 0)
	statDescFrame.Position = UDim2.fromScale(1, 0)
	totalLabel.Text = ""
	totalFrame.Visible = false

	-- Show search box
	tween(searchBoxOuter, { Position = UDim2.new(1, -205, 0, 4) })

	-- Clear search filter
	if searchBox then
		searchBox.Text = ""
	end
	applySearchFilter("")

	-- Restore stat name labels
	for _, entry in ipairs(statButtons) do
		local label = statNameLabels[entry.statKey]
		if label then
			typewrite(label, entry.stat)
		end
	end

	-- Reset page button gradients
	if pageButtons then
		for _, btn in pairs(pageButtons) do
			setGradient(btn, GRADIENT_DEFAULT)
		end
	end
end

function M.close()
	isOpen = false
	internalView = "list"
	activeStatKey = nil
	activePageType = "Obtainment"
end

function M.reset()
	isOpen = false
	internalView = "list"
	activeStatKey = nil
	activePageType = "Obtainment"
	lastDisplayedTotal = nil
	lastDisplayedKey = nil

	-- Snap positions
	scrollingFrame.Position = UDim2.fromScale(0, 0)
	statDescFrame.Position = UDim2.fromScale(1, 0)
	totalLabel.Text = ""
	totalFrame.Visible = false

	-- Reset search
	if searchBox then
		searchBox.Text = ""
	end
	applySearchFilter("")

	-- Set all stat name labels instantly
	if statButtons then
		for _, entry in ipairs(statButtons) do
			local label = statNameLabels[entry.statKey]
			if label then
				label.Text = entry.stat
				label.MaxVisibleGraphemes = -1
			end
		end
	end

	if pageButtons then
		for _, btn in pairs(pageButtons) do
			setGradient(btn, GRADIENT_DEFAULT)
		end
	end
end

function M.navigateBack()
	if internalView ~= "breakdown" then
		return
	end
	internalView = "list"
	activeStatKey = nil
	activePageType = "Obtainment"
	totalLabel.Text = ""
	totalFrame.Visible = false

	for _, btn in pairs(pageButtons) do
		setGradient(btn, GRADIENT_DEFAULT)
	end

	restoreStatList()
end

return M
