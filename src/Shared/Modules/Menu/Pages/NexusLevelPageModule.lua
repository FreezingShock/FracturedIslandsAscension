--[[
	NexusLevelPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	The Aetheric Nexus Level page of the Ascension menu: a copy of Hypixel SkyBlock's Levels menu, made ONLY of grid slots (grid
	"NexusLevelMenu", opened from the Nexus home's middle AethericNexus button and from the Profile menu's AethericNexus button).
	A pooled grid like the Collections pages: the engine clones GridTemplates.NexusLevelMenu (BackButton + CloseSlot) into a buffer on
	every navigation and runs populate(frame); depopulate() runs when the page is left. Everything on it is READ from the Player
	attributes NexusService publishes (NexusConfig.attributes): the client never asks the server for anything.

	  Cells (9 x 6, cell = row * columns + column): NexusConfig.page.slots (Level Ranking, Coming Soon torch, Milestone, Leveling Rewards,
	  XP Sources, Prefix Emblems) and NexusConfig.page.preview (the 5-level preview: finished = green pane, the current level = yellow
	  pane, not finished = red pane; the middle one is the current level). BackButton / CloseSlot sit in the Collections footer columns;
	  every free cell is a plain BlankSlot. The milestone button flips the preview to the next milestone level (click again to return).
	  Texts are NexusConfig.tooltips, rewards NexusConfig.rewardsFor, icons ItemIconData keys.

	Templates (StarterGui.CentralizedAscensionMenu.TemporaryMenus, tools/studio/build_nexus_page.luau): NexusSlot (a StatSlot with a
	"LevelLabel" corner label) and BlankSlot.

	API:  init(sharedRefs) / populate(frame) / depopulate() / reset() / tooltipText() -> { title, desc, click } for the Nexus buttons
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = Modules:WaitForChild("Config")
local NexusConfig = require(Config:WaitForChild("NexusConfig")) :: any
local CollectionsConfig = require(Modules:WaitForChild("CollectionsConfig")) :: any
local IconData = require(Modules:WaitForChild("ItemIconData")) :: { [string]: string }
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

local ATTR = NexusConfig.attributes
local LAYOUT = CollectionsConfig.LAYOUT
local PAGE = NexusConfig.page
local TOOLTIP_SOURCE = "nexusLevel"

local player = Players.LocalPlayer
local UISounds = workspace:WaitForChild("UISounds")
local UIClick = UISounds:WaitForChild("Click")

local M = {}

local TooltipModule: any = require(Modules:WaitForChild("TooltipModule")) -- the same instance CentralizedMenuController loaded
local templates: { [string]: Instance? } = {}
-- what the open page shows: `milestoneView` = the preview is centred on the next milestone instead of the current level
local state = { milestoneView = false }
local live: { connections: { RBXScriptConnection }, preview: { any }, milestoneSlot: any } = { connections = {}, preview = {}, milestoneSlot = nil }

-- ===================== HELPERS =====================
local function rich(hexColor: string, text: string): string
	return string.format('<font color="%s">%s</font>', hexColor, text)
end

local function number(n: number): string
	return MoneyLib.DealWithPoints(math.floor(n))
end

local function hexToColor3(hex: string): Color3
	return Color3.fromHex((hex:gsub("#", "")))
end

local function cell(row: number, col: number): number
	return row * LAYOUT.columns + col
end

--- Everything the page shows, from the Player attributes.
local function snapshot()
	local total = player:GetAttribute(ATTR.total) or 0
	local level = player:GetAttribute(ATTR.level) or 0
	local _, progress, into, need = NexusConfig.levelFromXp(total)
	return { level = level, progress = progress, total = total, into = into, need = need, maxed = level >= NexusConfig.curve.maxLevel }
end

local function xpText(s): string
	if s.maxed then
		return rich("#FFAA00", "<b>MAX LEVEL</b>")
	end
	return string.format("%s%s%s %s", rich("#FFFF55", number(s.into)), rich("#FFAA00", "/"), rich("#FFFF55", number(s.need)), rich("#AAAAAA", "XP"))
end

--- A NexusConfig.tooltips entry as a full TooltipModule config: tokens filled from the Player attributes, stats rows from
--- Tooltip.Build, the progress bar from the entry's `progress.pct` kind. `ctx` = { level, status, milestone, alt }.
local function tooltipFor(id: string, ctx: any?): any
	local entry = NexusConfig.tooltips[id]
	local Tooltip = TooltipModule
	local Build, Rich = Tooltip.Build, Tooltip.Rich
	ctx = ctx or {}
	local s = snapshot()
	local nextMilestone = NexusConfig.nextMilestone(s.level) or NexusConfig.curve.maxLevel
	local done, all = NexusConfig.milestoneCount(s.level)
	local level = ctx.level or s.level
	local tier = NexusConfig.colorFor(s.level)
	local tokens: { [string]: string } = {
		level = tostring(level),
		total = number(s.total),
		maxXp = number(NexusConfig.maxXp()),
		pct = tostring(math.floor(s.total / NexusConfig.maxXp() * 100)),
		max = tostring(NexusConfig.curve.maxLevel),
		milestone = tostring(nextMilestone),
		milestones = tostring(done),
		milestoneTotal = tostring(all),
		xp = Rich.strip(xpText(s)),
		tier = tier,
	}
	local function fill(text: any): any
		if type(text) ~= "string" then
			return text
		end
		return (text:gsub("{(%w+)}", function(key)
			return tokens[key] or ""
		end))
	end
	local function text(value: any): any -- {tokens} + Minecraft & codes
		return type(value) == "string" and Rich.mc(fill(value)) or value
	end

	local config: any = {
		title = fill(entry.title),
		titleColor = fill(entry.titleColor),
		description = text(entry.description),
		statsTitle = entry.statsTitle,
		footer = text(entry.footer),
		details = entry.details,
	}

	-- tags (the preview panes add their own status / milestone tag)
	local tags = {}
	for _, tag in ipairs(entry.tags or {}) do
		table.insert(tags, tag)
	end
	if id == "pane" then
		local paneTags = NexusConfig.tooltips.paneTags
		table.insert(tags, 1, paneTags[ctx.status or "todo"])
		if level > 0 and level % NexusConfig.rewards.milestoneEvery == 0 then
			table.insert(tags, paneTags.milestone)
		end
		config.titleColor = NexusConfig.colorFor(level)
	end
	config.tags = #tags > 0 and tags or nil

	-- stats rows
	local rows = {}
	if entry.statsFrom == "rewards" or entry.statsFrom == "milestoneRewards" then
		local rewardLevel = entry.statsFrom == "rewards" and level or nextMilestone
		rows = Build.rewardList(NexusConfig.rewardsFor(rewardLevel))
		if #rows == 0 then
			rows = { Build.row("None", "", "#AAAAAA") }
		end
	elseif entry.statsFrom == "sources" then
		for _, categoryId in ipairs(NexusConfig.categoryOrder()) do
			local category = NexusConfig.categories[categoryId]
			table.insert(rows, Build.row(category.name, number(player:GetAttribute(ATTR.categoryPrefix .. categoryId) or 0), category.color))
		end
		table.insert(rows, Build.row("Total", number(s.total) .. " XP", "#FFFF55"))
	end
	for _, row in ipairs(entry.stats or {}) do
		table.insert(rows, Build.row(row.name, fill(row.value), row.color, row.icon))
	end
	config.stats = #rows > 0 and rows or nil

	-- progress bar
	local progress = entry.progress
	if id == "pane" then
		progress = ctx.status == "current" and { pct = "xp", label = "{xp}", color = "#FFFF55" } or nil
	end
	if progress then
		local pct = progress.pct == "xp" and s.progress or (progress.pct == "milestones" and (all > 0 and done / all or 0) or (s.total / NexusConfig.maxXp()))
		config.progress = Build.progress(pct, fill(progress.label), { color = progress.color })
	end

	-- click pill
	local click = (ctx.alt and entry.clickAlt) or entry.click
	config.click = click and { text = click.text, color = click.color, icon = click.icon } or nil
	return config
end

--- Tooltip of the Nexus buttons (home + Profile).
function M.tooltipText()
	return tooltipFor("nexus")
end

-- ===================== SLOTS =====================
local function clone(name: string): any
	local template = templates[name]
	return template and template:Clone() or nil
end

--- Tint a slot: tile colour, BG image + stroke, and the icon.
local function paint(slot: any, colorHex: string, iconKey: string?)
	local color = hexToColor3(colorHex)
	slot.BackgroundColor3 = color
	local bg: any = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
	end
	local image: any = slot:FindFirstChild("Icon")
	if image and iconKey then
		image.Image = IconData[iconKey] or IconData.barrier or ""
	end
end

local function setLabel(slot: any, text: string)
	local label = slot:FindFirstChild("LevelLabel", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function hideTip()
	if TooltipModule then
		TooltipModule.hide(TOOLTIP_SOURCE)
	end
end

--- Hover shows `getConfig()` (read when the mouse enters, so it is always current); leaving or a click handler as given.
local function bind(slot: any, getConfig: () -> any, onClick: (() -> ())?)
	slot.MouseEnter:Connect(function()
		if TooltipModule then
			TooltipModule.show(getConfig(), TOOLTIP_SOURCE, slot)
		end
	end)
	slot.MouseLeave:Connect(hideTip)
	if onClick then
		slot.MouseButton1Click:Connect(function()
			UIClick:Play()
			onClick()
		end)
	end
end

-- ===================== THE 5-LEVEL PREVIEW =====================
local function centerLevel(): number
	local s = snapshot()
	if state.milestoneView then
		return NexusConfig.nextMilestone(s.level) or NexusConfig.curve.maxLevel
	end
	return s.level
end

--- Re-skin the 5 preview slots for the current state (called on populate and whenever an attribute changes).
local function refreshPreview()
	local s = snapshot()
	local center = centerLevel()
	local half = (#PAGE.preview.cols - 1) // 2
	for index, entry in ipairs(live.preview) do
		local level = center + (index - 1 - half)
		local slot = entry.slot
		if level < 0 or level > NexusConfig.curve.maxLevel then
			slot.Visible = false -- outside the curve: a blank cell shows instead
			entry.blank.Visible = true
		else
			slot.Visible = true
			entry.blank.Visible = false
			local pane = level < s.level and PAGE.panes.done or (level == s.level and PAGE.panes.current or PAGE.panes.todo)
			paint(slot, pane.color, pane.icon)
			setLabel(slot, tostring(level))
			entry.level = level
		end
	end
	if live.milestoneSlot then
		setLabel(live.milestoneSlot, state.milestoneView and "M" or "")
	end
end

-- ===================== GRID =====================
function M.populate(frame: Instance)
	M.depopulate()
	state.milestoneView = false
	local occupied: { [number]: boolean } = {}
	local function place(index: number, slot: any)
		slot.LayoutOrder = index
		slot.Visible = true
		slot.Parent = frame
		occupied[index] = true
	end

	-- the fixed slots (SkyBlock's Level Ranking, Leveling Rewards, Prefix Emblems ...)
	for id, def in pairs(PAGE.slots) do
		local slot = clone("NexusSlot")
		if slot then
			slot.Name = "Nexus_" .. id
			paint(slot, "#3A3A3A", def.icon)
			setLabel(slot, "")
			place(cell(def.row, def.col), slot)
			if id == "milestone" then
				live.milestoneSlot = slot
				bind(slot, function()
					return tooltipFor("milestone", { alt = state.milestoneView })
				end, function()
					state.milestoneView = not state.milestoneView
					refreshPreview()
				end)
			else
				bind(slot, function()
					return tooltipFor(def.tooltip)
				end)
			end
		end
	end

	-- the preview panes (each with a blank slot behind it for levels outside 0..max)
	for index, col in ipairs(PAGE.preview.cols) do
		local slot = clone("NexusSlot")
		local blank = clone("BlankSlot")
		if slot and blank then
			slot.Name = "Preview_" .. index
			blank.Name = "PreviewBlank_" .. index
			blank.LayoutOrder = cell(PAGE.preview.row, col)
			blank.Visible = false
			blank.Parent = frame
			local entry: any = { slot = slot, blank = blank, level = 0 }
			table.insert(live.preview, entry)
			place(cell(PAGE.preview.row, col), slot)
			bind(slot, function()
				local s = snapshot()
				local status = entry.level < s.level and "done" or (entry.level == s.level and "current" or "todo")
				return tooltipFor("pane", { level = entry.level, status = status })
			end)
		end
	end
	refreshPreview()

	-- footer buttons (from the grid template) and blanks
	local back: any = frame:FindFirstChild("BackButton")
	if back then
		back.LayoutOrder = cell(LAYOUT.footerRow, LAYOUT.backCol)
		occupied[back.LayoutOrder] = true
	end
	local close: any = frame:FindFirstChild("CloseSlot")
	if close then
		close.LayoutOrder = cell(LAYOUT.footerRow, LAYOUT.closeCol)
		occupied[close.LayoutOrder] = true
	end
	if templates.BlankSlot then
		for index = 0, LAYOUT.columns * LAYOUT.rows - 1 do
			if not occupied[index] then
				local blank = templates.BlankSlot:Clone() :: any
				blank.Name = "Blank"
				blank.LayoutOrder = index
				blank.Visible = true
				blank.Parent = frame
			end
		end
	end

	-- live: every attribute that changes what the page shows
	local signals = { ATTR.level, ATTR.progress, ATTR.total }
	for id in pairs(NexusConfig.categories) do
		table.insert(signals, ATTR.categoryPrefix .. id)
	end
	for _, attribute in ipairs(signals) do
		table.insert(live.connections, player:GetAttributeChangedSignal(attribute):Connect(refreshPreview))
	end
end

function M.depopulate()
	for _, connection in ipairs(live.connections) do
		connection:Disconnect()
	end
	table.clear(live.connections)
	table.clear(live.preview)
	live.milestoneSlot = nil
	state.milestoneView = false
	hideTip()
end

function M.reset()
	M.depopulate()
end

function M.init(_refs: any)
	local temporary = player:WaitForChild("PlayerGui"):WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
	templates.NexusSlot = temporary:FindFirstChild("NexusSlot") or temporary:FindFirstChild("CollectionStatSlot")
	templates.BlankSlot = temporary:FindFirstChild("BlankSlot")
	for _, name in ipairs({ "NexusSlot", "BlankSlot" }) do
		if not templates[name] then
			warn("[NexusLevelPageModule] TemporaryMenus." .. name .. " is missing: run tools/studio/build_nexus_page.luau")
		end
	end
end

return M
