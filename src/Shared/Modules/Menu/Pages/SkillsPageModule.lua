--[[
	SkillsPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	The Skills page of the Nexus menu: each SkillsGrid button opens the breakdown of one skill (SkillsMenu.SkillDescFrame).
	Everything it shows comes from SkillsConfig (skills, caps, XP curve, rewards, Roman numerals) and the SkillUpdated payload
	the server sends ({ level, xp, xpNeeded, roman, pct, cap, wisdom } per skill); rewards are granted by SkillRewardService.

	SkillDescFrame (built by tools/studio/build_skills_menu.luau, looked up BY NAME):
	  StatNameVal  StatName, StatValue (level), LineDivider.Line      Desc.DescLabel
	  XpBar        Fill + Label ("xp / needed (pct)")                 WisdomLabel   NextReward
	  SkillLevels  ScrollingFrame with reusable slots Level1..Level25 + PageToggle (page count = ceil(cap / 25))

	Called by CentralizedMenuController:
	  init(sharedRefs, skillsMenuFrame)
	  open(statKey)            show the breakdown of one skill
	  close() / reset()        navigating away (animated) / menu hard-closed (instant)
	  showGridSkillTooltip(statKey, silent) / hideGridSkillTooltip()   hub + statistics tooltip
--]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("SkillsConfig")) :: any
local CollectionRewards = require(Modules:WaitForChild("CollectionRewards")) :: any
local StatisticLogModule = require(Modules:WaitForChild("StatisticLogModule")) :: any
local Style = require(Modules:WaitForChild("TooltipModule"):WaitForChild("Style")) :: any

local UISounds = workspace:WaitForChild("UISounds")
local UIClick = UISounds:WaitForChild("Click")
local UIClick3 = UISounds:WaitForChild("Click3")

local PAGE_SIZE = Config.PAGE_SIZE
local ORDER = Config.ORDER
local SHADOW_DELAY = 0.5
local TOAST_SECONDS = 4
local COLORS = { completed = "#55FF55", inProgress = "#FFFF55", locked = "#FF5555" }
local MILESTONE_COLOR = Color3.fromHex("FFD700")

-- ===================== STATE =====================
local initialized = false
local isOpen = false
local sharedRefs: any = nil
local TooltipModule: any = nil

local activeSkill: string? = nil
local currentPage = 1
local latestData: any = nil
local useRomanNumerals = true

-- Frame references (set by init)
local skillDescFrame, statNameLabel, statUIStroke, statUnderline, descLabel, line, statValueLabel
local skillLevelsFrame, levelScrollFrame, pageToggleButton, levelGradient
local xpBar, xpFill, xpLabel, xpLeft, xpRight, xpMask, wisdomLabel, nextRewardLabel
local DEFAULT_LEVELS_BG, DEFAULT_LEVELS_STROKE

local slots: { any } = {} -- [i] = { button, label, stroke, thickness, level, status, milestone, text }
local barShown = -1 -- last xp fraction drawn (so the tween only runs when it changes)
local barValue = Instance.new("NumberValue") -- the tweened fill fraction, drawn through the mask gradient
local barTween: Tween? = nil
local hoveredSlot: number? = nil
local gridTooltip: { active: boolean, skill: string? } = { active = false, skill = nil }

-- ===================== HELPERS =====================
local function roman(n: number): string
	return Config.roman(n)
end

local function displayLevel(n: number): string
	return useRomanNumerals and roman(n) or tostring(n)
end

local function displayLevelAlt(n: number): string
	return useRomanNumerals and tostring(n) or roman(n)
end

local function shorthand(n: number): string
	if n >= 1000000 then
		local v = n / 1000000
		return (v == math.floor(v)) and (math.floor(v) .. "m") or (string.format("%.1f", v) .. "m")
	elseif n >= 1000 then
		local v = n / 1000
		return (v == math.floor(v)) and (math.floor(v) .. "k") or (string.format("%.1f", v) .. "k")
	end
	return tostring(math.floor(n))
end

local function fmtLevelTitle(colorHex: string, skillName: string, level: number): string
	return string.format(
		"<font color='%s'><b>%s</b> <b>%s</b></font><font family='rbxasset://11598121416' weight='400' color='#AAAAAA'> (%s)</font>",
		colorHex,
		skillName,
		displayLevel(level),
		displayLevelAlt(level)
	)
end

local function entryOf(skill: string)
	local entry = latestData and latestData[skill]
	if type(entry) == "table" then
		return entry
	end
	return { level = 1, xp = 0, xpNeeded = Config.xpNeeded(skill, 1), pct = 0, cap = Config.cap(skill), wisdom = 0 }
end

local function statusOf(level: number, playerLevel: number): string
	if level <= playerLevel then
		return "completed"
	elseif level == playerLevel + 1 then
		return "inProgress"
	end
	return "locked"
end

--- Rich text lines of a level's rewards, straight from the registry (a new reward type needs no change here).
local function rewardLines(skill: string, level: number): { string }
	local lines = {}
	for _, reward in ipairs(Config.getRewards(skill, level)) do
		local info = CollectionRewards.describe(reward, { skill = skill, level = level })
		local star = (reward.type == "unlock") and "<font color='#FFD700'>★ </font>" or ""
		table.insert(lines, star .. info.text)
	end
	return lines
end

local function progressBlock(entry: any, colorHex: string): any
	local pct = entry.pct or 0
	return {
		pct = pct,
		color = colorHex,
		animate = true,
		label = string.format(
			"<font color='#FFFF55'>%s</font><font color='#FFAA00'>/</font><font color='#FFFF55'>%s</font> <font color='#AAAAAA'>(%d%%)</font>",
			shorthand(entry.xp or 0),
			shorthand(entry.xpNeeded or 0),
			math.floor(pct * 100)
		),
	}
end

local function skillAverage(): number
	local total = 0
	for _, skill in ipairs(ORDER) do
		total += entryOf(skill).level or 1
	end
	return total / #ORDER
end

-- ===================== SCROLL SHADOW =====================
-- A soft gradient over the level strip that shows after the pointer has been idle, hinting that it scrolls.
local shadowActive = false
local shadowTween: Tween? = nil
local shadowToken = 0

local GRAD_RIGHT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.75, 1),
	NumberSequenceKeypoint.new(1, 0),
})
local GRAD_LEFT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 1),
	NumberSequenceKeypoint.new(1, 1),
})
local GRAD_BOTH = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 1),
	NumberSequenceKeypoint.new(0.75, 1),
	NumberSequenceKeypoint.new(1, 0),
})

local function hideShadow()
	if shadowTween then
		shadowTween:Cancel()
		shadowTween = nil
	end
	if not shadowActive then
		return
	end
	shadowActive = false
	shadowTween = TweenService:Create(
		levelScrollFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	shadowTween:Play()
end

local function showShadow()
	local maxX = math.max(levelScrollFrame.AbsoluteCanvasSize.X - levelScrollFrame.AbsoluteSize.X, 0)
	if maxX <= 1 then
		return -- everything fits: nothing to hint at
	end
	local x = levelScrollFrame.CanvasPosition.X
	levelGradient.Transparency = x <= 35 and GRAD_RIGHT or (x >= maxX - 35 and GRAD_LEFT or GRAD_BOTH)
	shadowActive = true
	if shadowTween then
		shadowTween:Cancel()
	end
	shadowTween = TweenService:Create(
		levelScrollFrame,
		TweenInfo.new(2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 }
	)
	shadowTween:Play()
end

--- Restart the idle timer (a debounce, so there is no per-frame loop while the page is closed or idle).
local function scheduleShadow()
	hideShadow()
	shadowToken += 1
	local token = shadowToken
	task.delay(SHADOW_DELAY, function()
		if token == shadowToken and isOpen then
			showShadow()
		end
	end)
end

-- ===================== TYPEWRITER =====================
local typewriterToken = 0
local function typewrite(label: TextLabel, text: string, speed: number)
	typewriterToken += 1
	local token = typewriterToken
	label.Text = text
	label.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		for i = 1, length do
			if token ~= typewriterToken then
				return
			end
			label.MaxVisibleGraphemes = i
			task.wait(speed)
		end
		if token == typewriterToken then
			label.MaxVisibleGraphemes = -1
		end
	end)
end

-- ===================== SLOT PULSE =====================
local pulseTween: Tween? = nil
local pulsedButton: any = nil

local function stopPulse()
	if pulseTween then
		pulseTween:Cancel()
		pulseTween = nil
	end
	if pulsedButton and pulsedButton.Parent then
		pulsedButton.BackgroundTransparency = 0.75
	end
	pulsedButton = nil
end

--- The level being worked on breathes a little (BackgroundTransparency 0.75 <-> 0.5).
local function startPulse(button: any)
	if pulsedButton == button and pulseTween then
		return
	end
	stopPulse()
	pulsedButton = button
	button.BackgroundTransparency = 0.75
	pulseTween = TweenService:Create(
		button,
		TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ BackgroundTransparency = 0.5 }
	)
	pulseTween:Play()
end

-- ===================== RENDER =====================
local function pageOf(skill: string, level: number): number
	return math.clamp(math.ceil(math.max(level, 1) / PAGE_SIZE), 1, Config.pageCount(skill))
end

-- ===================== XP BAR (the tooltip's progress bar) =====================
--- The fill is revealed by a UIGradient transparency mask, exactly like TooltipModule's progress bar.
local function maskSequence(p: number): NumberSequence
	p = math.clamp(p, 0, 1)
	if p <= 0 then
		return NumberSequence.new(1)
	elseif p >= 1 then
		return NumberSequence.new(0)
	end
	p = math.min(p, 0.995)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(p, 0),
		NumberSequenceKeypoint.new(p + 0.004, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

barValue.Changed:Connect(function(value)
	if xpMask then
		xpMask.Transparency = maskSequence(value)
	end
end)

local function setBar(pct: number, colorHex: string, animate: boolean)
	if barTween then
		barTween:Cancel()
		barTween = nil
	end
	xpMask.Color = ColorSequence.new(Style.color3(Style.light(colorHex)), Style.color3(Style.dark(colorHex)))
	if animate then
		barTween = TweenService:Create(
			barValue,
			TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Value = pct }
		)
		barTween:Play()
	else
		barValue.Value = pct
		xpMask.Transparency = maskSequence(pct) -- Changed does not fire when the value is unchanged
	end
end

local function renderToggle(skill: string)
	local pages = Config.pageCount(skill)
	pageToggleButton.Visible = pages > 1
	local label = pageToggleButton:FindFirstChild("Label")
	if not label or pages <= 1 then
		return
	end
	local nextPage = currentPage % pages + 1
	local first = (nextPage - 1) * PAGE_SIZE + 1
	local last = math.min(nextPage * PAGE_SIZE, Config.cap(skill))
	local range = displayLevel(first) .. " – " .. displayLevel(last)
	label.Text = nextPage > currentPage and ("Levels " .. range .. " <font color='#FFFF55'>▶</font>")
		or ("<font color='#FFFF55'>◀</font> Levels " .. range)
end

--- Level slots: only a slot whose level, status or milestone flag changed is touched.
local function renderSlots(force: boolean?)
	local skill = activeSkill
	if not skill then
		return
	end
	local entry = entryOf(skill)
	local playerLevel = entry.level or 1
	local cap = Config.cap(skill)
	local pulse: any = nil

	for i, slot in ipairs(slots) do
		local level = (currentPage - 1) * PAGE_SIZE + i
		if level > cap then
			if slot.button.Visible then
				slot.button.Visible = false
				slot.level = nil
			end
			continue
		end
		local status = statusOf(level, playerLevel)
		local milestone = Config.isMilestone(skill, level)
		local text = displayLevel(level)
		if
			force
			or slot.level ~= level
			or slot.status ~= status
			or slot.milestone ~= milestone
			or slot.text ~= text
		then
			slot.level, slot.status, slot.milestone, slot.text = level, status, milestone, text
			local color = Color3.fromHex(COLORS[status]:sub(2))
			slot.button.Visible = true
			slot.button.BackgroundColor3 = color
			if slot.stroke then
				slot.stroke.Color = milestone and MILESTONE_COLOR or color
				slot.stroke.Thickness = milestone and math.max(slot.thickness, 3) or slot.thickness
			end
			if slot.label then
				slot.label.TextColor3 = color
				slot.label.Text = text
			end
		end
		if status == "inProgress" then
			pulse = slot.button
		end
	end

	if pulse then
		startPulse(pulse)
	else
		stopPulse()
	end
	renderToggle(skill)
end

local function renderHeader(force: boolean?)
	local skill = activeSkill
	if not skill then
		return
	end
	local config = Config.skills[skill]
	local entry = entryOf(skill)
	local level = entry.level or 1
	local cap = Config.cap(skill)

	statValueLabel.Text = displayLevel(level)

	-- XP bar: current level on the left, next level (or MAX) on the right, the fill in the skill's color
	if xpBar then
		local atCap = level >= cap
		local pct = atCap and 1 or (entry.pct or 0)
		xpLabel.Text = atCap and "MAX LEVEL"
			or string.format(
				"%s / %s  (%d%%)",
				shorthand(entry.xp or 0),
				shorthand(entry.xpNeeded or 0),
				math.floor(pct * 100)
			)
		xpLeft.Text = displayLevel(level)
		xpRight.Text = atCap and "MAX" or displayLevel(level + 1)
		if force or barShown ~= pct then
			barShown = pct
			setBar(pct, atCap and "#FFD700" or config.color, not force)
		end
	end

	if wisdomLabel then
		wisdomLabel.Text = string.format(
			"<font color='%s'>%s Wisdom</font> <font color='#55FF55'>+%s%% XP</font>",
			config.color,
			config.name,
			string.format("%g", math.floor((entry.wisdom or 0) * 100 + 0.5) / 100)
		)
	end

	if nextRewardLabel then
		if level >= cap then
			nextRewardLabel.Text =
				"<font color='#FFD700'>MAX LEVEL</font> <font color='#AAAAAA'>every reward of this skill is yours.</font>"
		else
			nextRewardLabel.Text = string.format(
				"<font color='#AAAAAA'>Next reward (Level %s):</font>  %s",
				displayLevel(level + 1),
				table.concat(rewardLines(skill, level + 1), "  <font color='#555555'>|</font>  ")
			)
		end
	end
end

local function applyStatColor(color: Color3)
	statNameLabel.TextColor3 = color
	statUIStroke.Color = color
	statUnderline.BackgroundColor3 = color
	line.BackgroundColor3 = color
	line.UIStroke.Color = color
	skillDescFrame.StatNameVal.StatValue.Underline.BackgroundColor3 = color
	skillLevelsFrame.BackgroundColor3 = color
	skillLevelsFrame.UIStroke.Color = color
end

local function revertStatColor()
	skillLevelsFrame.BackgroundColor3 = DEFAULT_LEVELS_BG
	skillLevelsFrame.UIStroke.Color = DEFAULT_LEVELS_STROKE
end

-- ===================== TOOLTIPS =====================
local tooltipFromLevels = false

local function showLevelTooltip(slotIndex: number, silent: boolean?)
	local skill = activeSkill
	local slot = slots[slotIndex]
	if not (skill and slot and slot.level) then
		return
	end
	local level = slot.level
	local entry = entryOf(skill)
	local status = statusOf(level, entry.level or 1)
	local statusText = ({ completed = "Completed", inProgress = "In Progress", locked = "Locked" })[status]
	local lines = rewardLines(skill, level)
	if #lines == 0 then
		lines = { "<font color='#AAAAAA'>No rewards for this level.</font>" }
	end
	local tooltip: any = {
		title = fmtLevelTitle(COLORS[status], Config.skills[skill].name, level),
		description = string.format(
			"<font color='#AAAAAA'>Status: </font><font color='%s'><b>%s</b></font>",
			COLORS[status],
			statusText
		) .. (slot.milestone and "  <font color='#FFD700'>★ Milestone</font>" or ""),
		blocks = { { title = "Rewards", text = table.concat(lines, "\n"), align = "Left" } },
	}
	if status == "inProgress" then
		tooltip.progress = progressBlock(entry, Config.skills[skill].color)
	end
	if not silent then
		UIClick3:Play()
	end
	hoveredSlot = slotIndex
	tooltipFromLevels = true
	TooltipModule.show(tooltip, "skillLevels")
end

local function hideLevelTooltip()
	hoveredSlot = nil
	if not tooltipFromLevels then
		return
	end
	TooltipModule.hide("skillLevels")
	tooltipFromLevels = false
end

local function buildGridTooltip(skill: string): any?
	local config = Config.skills[skill]
	if not config then
		return nil
	end
	local entry = entryOf(skill)
	local level = entry.level or 1
	local tooltip: any = {
		title = fmtLevelTitle(config.color, config.name, level),
		description = string.format(
			"%s\n<font color='#AAAAAA'>Skill Average: </font><font color='#FFFF55'><b>%.1f</b></font>  <font color='#AAAAAA'>Wisdom: </font><font color='#55FF55'>+%g%% XP</font>",
			config.description,
			skillAverage(),
			math.floor((entry.wisdom or 0) * 100 + 0.5) / 100
		),
		click = { text = "CLICK TO VIEW!", color = "#FFFF55" },
	}
	if level >= Config.cap(skill) then
		tooltip.blocks =
			{ { title = "MAX LEVEL", text = "This skill has reached its maximum level.", color = "#FFD700" } }
	else
		tooltip.progress = progressBlock(entry, config.color)
		tooltip.blocks = {
			{
				title = "Level " .. displayLevel(level + 1) .. " Rewards",
				text = table.concat(rewardLines(skill, level + 1), "\n"),
				align = "Left",
			},
		}
	end
	return tooltip
end

local function showGridSkillTooltip(statKey: string, silent: boolean?)
	if not initialized then
		return
	end
	local tooltip = buildGridTooltip(statKey)
	if not tooltip then
		return
	end
	if not silent then
		UIClick3:Play()
	end
	gridTooltip.active = true
	gridTooltip.skill = statKey
	TooltipModule.show(tooltip, "skillGrid")
end

local function hideGridSkillTooltip()
	if not gridTooltip.active then
		return
	end
	TooltipModule.hide("skillGrid")
	gridTooltip.active = false
	gridTooltip.skill = nil
end

-- ===================== TOAST =====================
local function onLevelUp(info: any)
	if type(info) ~= "table" or type(info.skill) ~= "string" or type(info.level) ~= "number" then
		return
	end
	local config = Config.skills[info.skill]
	if not config or info.level < 1 or info.level > config.cap then
		return
	end
	local extra = (type(info.count) == "number" and info.count > 1)
			and string.format(" <font color='#AAAAAA'>(+%d levels)</font>", info.count - 1)
		or ""
	StatisticLogModule.log(
		string.format(
			"<font color='%s'><b>%s</b></font> <font color='#FFFF55'>reached level <b>%s</b></font>%s  %s",
			config.color,
			config.name,
			displayLevel(info.level),
			extra,
			table.concat(rewardLines(info.skill, info.level), "  ")
		),
		TOAST_SECONDS
	)
	UIClick3:Play()
end

-- ===================== MODULE =====================
local M = {}

--- Place Level1..Level25 along the snake path of SkillsConfig.SNAKE and size the scrolling canvas to fit it.
local function layoutSnake()
	local snake = Config.SNAKE
	local grid = levelScrollFrame:FindFirstChildOfClass("UIGridLayout")
	if grid then
		grid.Enabled = false -- positions are set here now
	end
	local cells = Config.snakeCells(PAGE_SIZE)
	local stepX, stepY = snake.cell + snake.gapX, snake.cell + snake.gapY
	local maxCol = 0
	for i, cell in ipairs(cells) do
		local button = levelScrollFrame:FindFirstChild("Level" .. i)
		if button then
			button.AnchorPoint = Vector2.zero
			button.Size = UDim2.fromOffset(snake.cell, snake.cell)
			button.Position = UDim2.fromOffset(snake.pad + cell[1] * stepX, snake.pad + cell[2] * stepY)
		end
		maxCol = math.max(maxCol, cell[1])
	end
	levelScrollFrame.CanvasSize = UDim2.fromOffset(snake.pad * 2 + maxCol * stepX + snake.cell, 0)
end

--- The 25 level buttons. They are renamed Level1..Level25 here (one each, whatever the Studio names are), so a duplicate or
--- missing name in the template can never leave a slot unplaced or without a tooltip.
local function collectSlotButtons(): { TextButton }
	local buttons = {}
	for index, child in ipairs(levelScrollFrame:GetChildren()) do
		if child:IsA("TextButton") then
			table.insert(buttons, { button = child, key = tonumber(child.Name:match("%d+")) or 999, index = index })
		end
	end
	table.sort(buttons, function(a, b)
		if a.key ~= b.key then
			return a.key < b.key
		end
		return a.index < b.index
	end)
	local list = {}
	for i, entry in ipairs(buttons) do
		if i <= PAGE_SIZE then
			entry.button.Name = "Level" .. i
			table.insert(list, entry.button)
		else
			entry.button.Visible = false -- an extra stray button
		end
	end
	if #list < PAGE_SIZE then
		warn("[SkillsPageModule] the level strip has only " .. #list .. " slots (needs " .. PAGE_SIZE .. ")")
	end
	return list
end

local function bindSlots()
	local buttons = collectSlotButtons()
	layoutSnake()
	for i, button in ipairs(buttons) do
		local stroke = button:FindFirstChildOfClass("UIStroke")
		slots[i] = {
			button = button,
			label = button:FindFirstChild("Label"),
			stroke = stroke,
			thickness = stroke and stroke.Thickness or 1,
		}
		button.MouseEnter:Connect(function()
			showLevelTooltip(i)
		end)
		button.MouseLeave:Connect(hideLevelTooltip)
	end
end

function M.init(refs: any, frame: Instance)
	if initialized then
		return
	end
	initialized = true
	sharedRefs = refs
	TooltipModule = refs.TooltipModule

	skillDescFrame = frame:WaitForChild("SkillDescFrame")
	statNameLabel = skillDescFrame.StatNameVal.StatName
	statUIStroke = statNameLabel.UIStroke
	statUnderline = statNameLabel.Underline
	descLabel = skillDescFrame.Desc.DescLabel
	line = skillDescFrame.StatNameVal.LineDivider.Line
	statValueLabel = skillDescFrame.StatNameVal.StatValue

	skillLevelsFrame = skillDescFrame.SkillLevels
	levelScrollFrame = skillLevelsFrame:WaitForChild("ScrollingFrame")
	pageToggleButton = skillLevelsFrame:WaitForChild("PageToggle")
	levelGradient = levelScrollFrame:WaitForChild("UIGradient")
	DEFAULT_LEVELS_BG = skillLevelsFrame.BackgroundColor3
	DEFAULT_LEVELS_STROKE = skillLevelsFrame.UIStroke.Color

	-- the elements added by build_skills_menu.luau (the page still works without them)
	-- XpBar = a clone of the tooltip's ProgressBar (inner ProgressBar > Progress + ProgressLabel) with the level numerals beside it
	xpBar = skillDescFrame:FindFirstChild("XpBar")
	local inner = xpBar and xpBar:FindFirstChild("ProgressBar")
	xpFill = inner and inner:FindFirstChild("Progress")
	xpLabel = inner and inner:FindFirstChild("ProgressLabel")
	xpLeft = xpBar and xpBar:FindFirstChild("Left")
	xpRight = xpBar and xpBar:FindFirstChild("Right")
	if xpFill then
		for _, child in ipairs(xpFill:GetChildren()) do
			if child:IsA("UIGradient") then
				if not xpMask then
					xpMask = child
				else
					child.Enabled = false -- the template's extra gradient would fight the mask
				end
			end
		end
	end
	if not (xpMask and xpLabel and xpLeft and xpRight) then
		xpBar = nil
	end
	wisdomLabel = skillDescFrame:FindFirstChild("WisdomLabel")
	nextRewardLabel = skillDescFrame:FindFirstChild("NextReward")
	if not (xpBar and wisdomLabel and nextRewardLabel) then
		warn("[SkillsPageModule] XpBar / WisdomLabel / NextReward missing: run tools/studio/build_skills_menu.luau")
	end

	skillDescFrame.Position = UDim2.new(0, 0, 0, 0)
	bindSlots()

	pageToggleButton.MouseButton1Click:Connect(function()
		if not activeSkill then
			return
		end
		currentPage = currentPage % Config.pageCount(activeSkill) + 1
		UIClick:Play()
		levelScrollFrame.CanvasPosition = Vector2.zero
		renderSlots(true)
		scheduleShadow()
	end)

	levelScrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if isOpen then
			scheduleShadow()
		end
	end)

	local SkillUpdated = ReplicatedStorage:WaitForChild("SkillUpdated", 10)
	if SkillUpdated then
		SkillUpdated.OnClientEvent:Connect(function(data)
			if type(data) ~= "table" then
				return
			end
			latestData = data
			if isOpen and activeSkill then
				renderHeader()
				renderSlots()
				if hoveredSlot then
					showLevelTooltip(hoveredSlot, true) -- the in-progress bar moves while hovered
				end
			end
			if gridTooltip.active and gridTooltip.skill then
				showGridSkillTooltip(gridTooltip.skill, true)
			end
		end)
	end

	local LevelUp = ReplicatedStorage:WaitForChild("SkillLevelUp", 10)
	if LevelUp then
		LevelUp.OnClientEvent:Connect(onLevelUp)
	end
end

function M.open(statKey: string)
	local config = Config.skills[statKey]
	if not config then
		warn("[SkillsPageModule] Unknown skill: " .. tostring(statKey))
		return
	end
	isOpen = true
	activeSkill = statKey
	currentPage = pageOf(statKey, math.min((entryOf(statKey).level or 1) + 1, Config.cap(statKey)))
	barShown = -1

	skillDescFrame.Position = UDim2.new(0, 0, 0, 0)
	applyStatColor(Color3.fromHex(config.color:sub(2)))
	statNameLabel.Text = config.name
	descLabel.Text = ""
	descLabel.MaxVisibleGraphemes = -1
	levelScrollFrame.CanvasPosition = Vector2.zero

	renderHeader(true)
	renderSlots(true)
	scheduleShadow()

	task.delay(0.25, function()
		if activeSkill == statKey then
			typewrite(descLabel, config.description, 0.025)
		end
	end)
end

local function closePage()
	isOpen = false
	typewriterToken += 1
	hideLevelTooltip()
	stopPulse()
	hideShadow()
	revertStatColor()
	activeSkill = nil
	currentPage = 1
end

function M.close()
	closePage()
end

function M.reset()
	closePage()
	descLabel.Text = ""
	descLabel.MaxVisibleGraphemes = -1
	skillDescFrame.Position = UDim2.new(0, 0, 0, 0)
end

function M.navigateBack() end

M.showGridSkillTooltip = showGridSkillTooltip
M.hideGridSkillTooltip = hideGridSkillTooltip

return M
