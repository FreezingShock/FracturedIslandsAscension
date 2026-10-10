--[[
	SkillsPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	The breakdown of one skill: a pooled grid (GridMenuModule "SkillsMenu2", template GridTemplates.SkillsMenu2), opened from
	a SkillsGrid button through openSkill(skill). Layout comes from SkillsConfig.GRID and SkillsConfig.SNAKE (9 x 6):
	  the title slot top-left (skill icon and level; its tooltip = XP bar, wisdom, next reward),
	  the snake of level slots (PAGE_SIZE per page, pages = ceil(cap / PAGE_SIZE): Farming and Combat run to 60 = 3 pages),
	  the page arrows and Back on the bottom row.
	Flipping a page updates the live slots in place (nothing is rebuilt). Everything shown comes from SkillsConfig and the
	SkillUpdated payload ({ level, xp, xpNeeded, roman, pct, cap, wisdom } per skill). Rewards are granted server-side
	(SkillRewardService); the client only sends intent (open a skill, turn a page) through its own buttons.

	Templates (looked up BY NAME):
	  GridTemplates.SkillsMenu2                          BackButton, CloseSlot, PagePrev, PageNext
	  StarterGui.CentralizedAscensionMenu.TemporaryMenus SkillTitle, SkillLevelSlot, BlankSlot
	tools/studio/build_skills_menu2.luau builds them.

	Called by CentralizedMenuController:
	  init(sharedRefs)
	  openSkill(skill)               navigate into one skill (SkillsGrid buttons)
	  turnPage(delta)                the page arrows (-1 / +1)
	  back()                         the Back button: pop one grid
	  populate(frame) / depopulate() pooled-grid hooks
	  close() / reset()              menu closed / hard reset
	  showGridSkillTooltip(statKey, silent) / hideGridSkillTooltip()   hub + statistics tooltip
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("SkillsConfig")) :: any
local CollectionRewards = require(Modules:WaitForChild("CollectionRewards")) :: any
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
local StatisticLogModule = require(Modules:WaitForChild("StatisticLogModule")) :: any

local UISounds = workspace:WaitForChild("UISounds")
local UIClick = UISounds:WaitForChild("Click")
local UIClick3 = UISounds:WaitForChild("Click3")

local player = Players.LocalPlayer
local GRID = Config.GRID
local COLUMNS = GRID.columns
local PAGE_SIZE = Config.PAGE_SIZE
local GRID_KEY = "SkillsMenu2"
local TOOLTIP_SOURCE = "skills"
local TOAST_SECONDS = 4
local COLORS = { completed = "#55FF55", inProgress = "#FFFF55", locked = "#FF5555" }
local MILESTONE_COLOR = Color3.fromHex("FFD700")
local EMPTY_COLOR = Color3.fromHex("333333") -- a level past the cap: a plain blank
local WHITE = Color3.new(1, 1, 1)

-- ===================== STATE =====================
local initialized = false
local sharedRefs: any = nil
local TooltipModule: any = nil
local latestData: any = nil
local templates: { [string]: Instance? } = {}

-- What the page shows. Set by openSkill, cleared by back / close.
local state = { skill = nil :: string?, page = 1 }
-- Live slots of the page on screen. levels[i] = { slot, index, level (nil past the cap), thickness }
local views = { levels = {} :: { any }, title = nil :: any, prev = nil :: any, next = nil :: any }
local hoveredView: any = nil -- the level under the pointer (its tooltip follows live data)
local titleHovered = false
local gridTooltip: { active: boolean, skill: string? } = { active = false, skill = nil }

-- ===================== HELPERS =====================
local function colorOf(hex: string): Color3
	return Color3.fromHex((hex:gsub("#", "")))
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
		"<font color='%s'><b>%s</b> <b>%s</b></font><font family='rbxasset://11598121416' weight='400' color='#AAAAAA'> (%d)</font>",
		colorHex,
		skillName,
		Config.roman(level),
		level
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

local function levelOf(page: number, index: number): number
	return (page - 1) * PAGE_SIZE + index
end

local function pageOf(skill: string, level: number): number
	return math.clamp(math.ceil(math.max(level, 1) / PAGE_SIZE), 1, Config.pageCount(skill))
end

local function gridTitle(skill: string, page: number): string
	local name = Config.skills[skill].name .. " Skill"
	if Config.pageCount(skill) <= 1 then
		return name
	end
	local first = levelOf(page, 1)
	local last = math.min(levelOf(page, PAGE_SIZE), Config.cap(skill))
	return string.format("%s  ·  Levels %d-%d", name, first, last)
end

local function cellIndex(cell: { number }): number
	return cell[2] * COLUMNS + cell[1]
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

--- The slot's icon source: the first reward of the level with a listed type and an icon (SkillsConfig.SLOT_ICON_TYPES).
local function slotInfo(skill: string, level: number): any?
	for _, reward in ipairs(Config.getRewards(skill, level)) do
		if table.find(Config.SLOT_ICON_TYPES, reward.type) then
			local info = CollectionRewards.describe(reward, { skill = skill, level = level })
			if info.icon ~= nil and info.icon ~= "" then
				return info
			end
		end
	end
	return nil
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
	for _, skill in ipairs(Config.ORDER) do
		total += entryOf(skill).level or 1
	end
	return total / #Config.ORDER
end

-- ===================== SLOT LOOKS =====================
--- Reward icon: a rbxassetid string, a {col, row} cell of the stat spritesheet, or an ItemIconData key (the placeholder).
local function setIcon(slot: Instance, icon: any, tint: Color3)
	local image: any = slot:FindFirstChild("Icon")
	if not image then
		return
	end
	image.ImageColor3 = tint
	image.ImageRectSize = Vector2.zero
	image.ImageRectOffset = Vector2.zero
	image.ImageTransparency = 0
	if type(icon) == "table" and TooltipModule and TooltipModule.STAT_SPRITESHEET then
		local sheet = TooltipModule.STAT_SPRITESHEET
		local cell = sheet.cellSize
		image.Image = sheet.assetId
		image.ImageRectSize = Vector2.new(cell, cell)
		image.ImageRectOffset = Vector2.new((icon[1] or 0) * cell, (icon[2] or 0) * cell)
	elseif type(icon) == "string" and icon ~= "" then
		if string.sub(icon, 1, 11) ~= "rbxassetid:" then
			icon = ItemIcons.resolve(icon).image
		end
		image.Image = icon
	else
		image.ImageTransparency = 1
	end
end

--- Background, BG image and stroke take one colour; dimmed = locked (the slot reads as not yet reached).
local function paint(slot: any, color: Color3, dimmed: boolean?)
	slot.BackgroundColor3 = color
	slot.BackgroundTransparency = dimmed and 0.45 or 0
	local bg: any = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		bg.ImageTransparency = dimmed and 0.45 or 0
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
	end
end

local function setLabel(slot: Instance, text: string)
	local label = slot:FindFirstChild("LevelLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
		label.TextColor3 = WHITE
	end
end

local function setEnabled(button: any, enabled: boolean)
	if not button then
		return
	end
	button.Active = enabled
	button.BackgroundTransparency = enabled and 0 or 0.6
	local icon: any = button:FindFirstChild("Icon")
	if icon then
		icon.ImageTransparency = enabled and 0 or 0.7
	end
end

-- ===================== TOOLTIPS =====================
local function hideTip()
	if TooltipModule then
		TooltipModule.hide(TOOLTIP_SOURCE)
	end
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
		tooltip.blocks = { { title = "MAX LEVEL", text = "This skill has reached its maximum level.", color = "#FFD700" } }
	else
		tooltip.progress = progressBlock(entry, config.color)
		tooltip.blocks = {
			{
				title = "Level " .. Config.roman(level + 1) .. " Rewards",
				text = table.concat(rewardLines(skill, level + 1), "\n"),
				align = "Left",
			},
		}
	end
	return tooltip
end

local function levelTooltip(skill: string, level: number): any
	local config = Config.skills[skill]
	local entry = entryOf(skill)
	local status = statusOf(level, entry.level or 1)
	local statusText = ({ completed = "Completed", inProgress = "In Progress", locked = "Locked" })[status]
	local lines = rewardLines(skill, level)
	if #lines == 0 then
		lines = { "<font color='#AAAAAA'>No rewards for this level.</font>" }
	end
	local tooltip: any = {
		title = fmtLevelTitle(COLORS[status], config.name, level),
		description = string.format(
			"<font color='#AAAAAA'>Status: </font><font color='%s'><b>%s</b></font>",
			COLORS[status],
			statusText
		) .. (Config.isMilestone(skill, level) and "  <font color='#FFD700'>★ Milestone</font>" or ""),
		blocks = { { title = "Rewards", text = table.concat(lines, "\n"), align = "Left" } },
	}
	if status == "inProgress" then
		tooltip.progress = progressBlock(entry, config.color)
	end
	return tooltip
end

local function showLevelTip(view: any, silent: boolean?)
	local skill = state.skill
	if not (skill and view.level) then
		return
	end
	if not silent then
		UIClick3:Play()
	end
	hoveredView = view
	TooltipModule.show(levelTooltip(skill, view.level), TOOLTIP_SOURCE, view.slot)
end

local function showTitleTip(silent: boolean?)
	local skill = state.skill
	local tooltip = skill and buildGridTooltip(skill)
	if not tooltip or not views.title then
		return
	end
	tooltip.click = nil -- the title is the page, there is nothing to click
	if not silent then
		UIClick3:Play()
	end
	titleHovered = true
	TooltipModule.show(tooltip, TOOLTIP_SOURCE, views.title)
end

-- ===================== RENDER (in place) =====================
local function refreshTitle(skill: string)
	local title = views.title
	if not (title and title.Parent) then
		return
	end
	local config = Config.skills[skill]
	local entry = entryOf(skill)
	local level = entry.level or 1
	local atCap = level >= Config.cap(skill)
	local info = slotInfo(skill, 1) -- the skill's icon: its first stat buff
	paint(title, colorOf(atCap and "#FFD700" or config.color))
	setLabel(title, Config.roman(level))
	setIcon(title, info and info.icon or Config.PLACEHOLDER_ICON, colorOf(config.color))
end

local function refreshLevels(skill: string)
	local playerLevel = entryOf(skill).level or 1
	local cap = Config.cap(skill)
	for index, view in ipairs(views.levels) do
		local slot = view.slot
		if not slot.Parent then
			continue
		end
		local level = levelOf(state.page, index)
		local stroke: any = slot:FindFirstChildOfClass("UIStroke")
		if level > cap then
			view.level = nil
			paint(slot, EMPTY_COLOR, true)
			setLabel(slot, "")
			setIcon(slot, nil, WHITE)
			if stroke then
				stroke.Color = EMPTY_COLOR
				stroke.Thickness = view.thickness
			end
		else
			view.level = level
			local status = statusOf(level, playerLevel)
			local color = colorOf(COLORS[status])
			paint(slot, color, status == "locked")
			setLabel(slot, Config.roman(level))
			local info = slotInfo(skill, level)
			setIcon(slot, info and info.icon or Config.PLACEHOLDER_ICON, info and colorOf(info.color or "#FFFFFF") or WHITE)
			if stroke then
				local milestone = Config.isMilestone(skill, level)
				stroke.Color = milestone and MILESTONE_COLOR or color
				stroke.Thickness = milestone and math.max(view.thickness, 3) or view.thickness
			end
		end
	end
end

local function refreshArrows(skill: string)
	setEnabled(views.prev, state.page > 1)
	setEnabled(views.next, state.page < Config.pageCount(skill))
end

--- Redraws everything on screen from `state` and the latest SkillUpdated payload. Touches only existing slots.
local function refresh()
	local skill = state.skill
	if not skill then
		return
	end
	refreshTitle(skill)
	refreshLevels(skill)
	refreshArrows(skill)
	if hoveredView and hoveredView.level then
		showLevelTip(hoveredView, true) -- the hovered level's bar and status follow live data
	elseif titleHovered then
		showTitleTip(true)
	end
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
			Config.roman(info.level),
			extra,
			table.concat(rewardLines(info.skill, info.level), "  ")
		),
		TOAST_SECONDS
	)
	UIClick3:Play()
end

-- ===================== GRID BUILD (pooled-grid hook) =====================
local function cloneTemplate(name: string): any
	local template = templates[name]
	return template and template:Clone() or nil
end

local function place(frame: Instance, occupied: { [number]: Instance }, index: number, slot: any)
	slot.LayoutOrder = index
	slot.Visible = true
	slot.Parent = frame
	occupied[index] = slot
end

--- A template child of the grid (BackButton, PagePrev, ...) placed on its cell; nil when the template lacks it.
local function placeNamed(frame: Instance, occupied: { [number]: Instance }, name: string, cell: { number }): any
	local child = frame:FindFirstChild(name)
	if child then
		place(frame, occupied, cellIndex(cell), child)
	end
	return child
end

--- Every free cell gets a BlankSlot, so the grid never shows a hole.
local function fillBlanks(frame: Instance, occupied: { [number]: Instance })
	local blank = templates.blank
	if not blank then
		return
	end
	for index = 0, GRID.columns * GRID.rows - 1 do
		if not occupied[index] then
			local clone = blank:Clone() :: any
			clone.LayoutOrder = index
			clone.Visible = true
			clone.Parent = frame
		end
	end
end

local function bind(slot: Instance, onEnter: () -> (), onLeave: () -> ())
	local button = slot :: any
	button.MouseEnter:Connect(onEnter)
	button.MouseLeave:Connect(onLeave)
end

-- ===================== MODULE =====================
local M = {}

--- Builds the page on the pooled grid: title, the snake of levels, arrows, Back, Close, blanks. Reads `state`.
function M.populate(frame: Instance)
	views.levels = {}
	views.title = nil
	views.prev = nil
	views.next = nil
	local skill = state.skill
	if not skill then
		warn("[SkillsPageModule] no skill selected for " .. GRID_KEY)
		return
	end

	local occupied: { [number]: Instance } = {}
	local title = cloneTemplate("skillTitle")
	if title then
		title.Name = "SkillTitle"
		place(frame, occupied, cellIndex(GRID.title), title)
		views.title = title
		bind(title, function()
			showTitleTip()
		end, function()
			titleHovered = false
			hideTip()
		end)
	end

	for index, cell in ipairs(Config.snakeCells(PAGE_SIZE)) do
		local slot = cloneTemplate("skillLevelSlot")
		if slot then
			slot.Name = "Level" .. index
			place(frame, occupied, cellIndex(cell), slot)
			local stroke: any = slot:FindFirstChildOfClass("UIStroke")
			local view = { slot = slot, index = index, level = nil, thickness = stroke and stroke.Thickness or 1 }
			table.insert(views.levels, view)
			bind(slot, function()
				showLevelTip(view)
			end, function()
				hoveredView = nil
				hideTip()
			end)
		end
	end

	views.prev = placeNamed(frame, occupied, "PagePrev", GRID.prev)
	views.next = placeNamed(frame, occupied, "PageNext", GRID.next)
	placeNamed(frame, occupied, "BackButton", GRID.back)
	placeNamed(frame, occupied, "CloseSlot", GRID.close)
	fillBlanks(frame, occupied)
	refresh()
end

--- Pooled-grid hook: the page leaves the screen. Tooltips go; `state` stays so the page can be rebuilt on Back.
function M.depopulate()
	hoveredView = nil
	titleHovered = false
	hideTip()
	views.levels = {}
	views.title = nil
	views.prev = nil
	views.next = nil
end

--- Opens the breakdown of one skill on the first page that holds its next level.
function M.openSkill(skill: string)
	local config = Config.skills[skill]
	if not config then
		warn("[SkillsPageModule] Unknown skill: " .. tostring(skill))
		return
	end
	local entry = entryOf(skill)
	state.skill = skill
	state.page = pageOf(skill, math.min((entry.level or 1) + 1, Config.cap(skill)))
	local title = gridTitle(skill, state.page)
	sharedRefs.GridMenuModule.setGridTitle(GRID_KEY, title)
	sharedRefs.GridMenuModule.navigateToGrid(GRID_KEY)
	sharedRefs.typewriteTitle(title)
end

--- The page arrows: delta = -1 (previous) or +1 (next). Redraws the slots in place.
function M.turnPage(delta: number)
	local skill = state.skill
	if not skill then
		return
	end
	local page = math.clamp(state.page + delta, 1, Config.pageCount(skill))
	if page == state.page then
		return
	end
	state.page = page
	UIClick:Play()
	hoveredView = nil
	hideTip()
	local title = gridTitle(skill, page)
	sharedRefs.GridMenuModule.setGridTitle(GRID_KEY, title)
	sharedRefs.typewriteTitle(title)
	refresh()
end

--- The Back button: pop this grid, then forget the skill (the grid we return to does not need it).
function M.back()
	sharedRefs.GridMenuModule.navigateBack()
	state.skill = nil
	state.page = 1
end

function M.close()
	hoveredView = nil
	titleHovered = false
	hideTip()
	state.skill = nil
	state.page = 1
end

function M.reset()
	M.close()
end

--- Hub and statistics tooltips for one skill (the SkillsGrid buttons and the Statistics skill buttons call these).
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

function M.init(refs: any)
	if initialized then
		return
	end
	initialized = true
	sharedRefs = refs
	TooltipModule = refs.TooltipModule

	local temporary =
		player:WaitForChild("PlayerGui"):WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
	templates.skillTitle = temporary:FindFirstChild("SkillTitle")
	templates.skillLevelSlot = temporary:FindFirstChild("SkillLevelSlot")
	templates.blank = temporary:FindFirstChild("BlankSlot")
	if not (templates.skillTitle and templates.skillLevelSlot and templates.blank) then
		warn("[SkillsPageModule] SkillTitle / SkillLevelSlot / BlankSlot missing: run tools/studio/build_skills_menu2.luau")
	end
	for _, problem in ipairs(Config.layoutErrors()) do
		warn("[SkillsPageModule] grid layout: " .. problem)
	end

	local SkillUpdated = ReplicatedStorage:WaitForChild("SkillUpdated", 10)
	if SkillUpdated then
		SkillUpdated.OnClientEvent:Connect(function(data)
			if type(data) ~= "table" then
				return
			end
			latestData = data -- kept even while closed, so the first open shows the real level
			refresh()
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

M.showGridSkillTooltip = showGridSkillTooltip
M.hideGridSkillTooltip = hideGridSkillTooltip

return M
