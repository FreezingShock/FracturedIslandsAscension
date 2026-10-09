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

local TooltipModule: any = nil
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

--- "+5 Health" lines of a level's rewards (Minecraft colours), or "None".
local function rewardLines(level: number): string
	local rewards = NexusConfig.rewardsFor(level)
	if #rewards == 0 then
		return rich("#555555", "None")
	end
	local lines = {}
	for _, reward in ipairs(rewards) do
		local stat = NexusConfig.rewards.stats[reward.stat]
		table.insert(lines, string.format("%s %s", rich("#55FF55", "+" .. reward.amount), rich(stat and stat.color or "#FFFFFF", stat and stat.name or reward.stat)))
	end
	return table.concat(lines, "\n")
end

local function barText(done: number, total: number): string
	local width = 20
	local filled = total > 0 and math.floor(done / total * width + 0.5) or 0
	return rich("#55FF55", string.rep("=", filled)) .. rich("#555555", string.rep("=", width - filled)) .. " " .. rich("#55FFFF", done .. "/" .. total)
end

local function sourcesText(): string
	local lines = {}
	for _, id in ipairs(NexusConfig.categoryOrder()) do
		local category = NexusConfig.categories[id]
		table.insert(lines, string.format("%s: %s", rich(category.color, category.name), rich("#FFFFFF", number(player:GetAttribute(ATTR.categoryPrefix .. id) or 0))))
	end
	return table.concat(lines, "\n")
end

--- A NexusConfig.tooltips entry as a TooltipModule config, tokens filled from the snapshot (`extra` adds / overrides tokens).
local function tooltipFor(id: string, extra: { [string]: string }?): any
	local entry = NexusConfig.tooltips[id]
	local s = snapshot()
	local milestone = NexusConfig.nextMilestone(s.level)
	local done, all = NexusConfig.milestoneCount(s.level)
	local tokens: { [string]: string } = {
		level = tostring(s.level),
		total = number(s.total),
		xp = xpText(s),
		pct = tostring(math.floor(s.total / NexusConfig.maxXp() * 100)),
		max = tostring(NexusConfig.curve.maxLevel),
		bar = barText(done, all),
		milestones = tostring(done),
		milestone = tostring(milestone or NexusConfig.curve.maxLevel),
		reward = rewardLines(milestone or NexusConfig.curve.maxLevel),
		sources = sourcesText(),
	}
	for key, value in pairs(extra or {}) do
		tokens[key] = value
	end
	local function fill(text: string): string
		return (text:gsub("{(%w+)}", function(key)
			return tokens[key] or ""
		end))
	end
	local lines = {}
	for _, line in ipairs(entry.lines) do
		table.insert(lines, fill(line))
	end
	local last = lines[#lines] or ""
	local click = ""
	if last:find("Click", 1, true) then -- the trailing "Click to ...!" line is the tooltip's own click row
		click = last
		table.remove(lines)
		if lines[#lines] == "" then
			table.remove(lines)
		end
	end
	return { title = fill(entry.title), desc = table.concat(lines, "\n"), click = click }
end

--- Tooltip of the Nexus buttons (home + Profile).
function M.tooltipText()
	local s = snapshot()
	return {
		title = string.format("%s %s", rich("#FF55FF", "<b>Aetheric Nexus Level</b>"), rich(NexusConfig.colorFor(s.level), "<b>" .. s.level .. "</b>")),
		desc = rich("#AAAAAA", "Your account level, earned from skill level-ups and collections.") .. "\n" .. xpText(s),
		click = rich("#FFFF55", "Click to view!"),
	}
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
					return tooltipFor("milestone")
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
				local extra = { level = tostring(entry.level), reward = rewardLines(entry.level), xp = entry.level == s.level and xpText(s) or "" }
				local config = tooltipFor("pane", extra)
				return config
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

function M.init(refs: any)
	TooltipModule = refs.TooltipModule
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
