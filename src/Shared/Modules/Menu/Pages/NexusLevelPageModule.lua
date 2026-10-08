--[[
	NexusLevelPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	The Aetheric Nexus Level page of the Ascension menu (grid "NexusLevelMenu", opened from the Profile grid's AethericNexus button).
	A pooled grid like the Collections pages: the engine clones GridTemplates.NexusLevelMenu (BackButton + CloseSlot) into a buffer on
	every navigation and runs populate(frame); depopulate() runs when the page is left. Everything on it is READ from the Player
	attributes NexusService publishes (NexusConfig.attributes): the client never asks the server for anything.

	  cells (NexusConfig.page)   a 9 x 6 grid, cell = row * columns + column (= LayoutOrder)
	    NexusBadgeSlot           the big badge (a copy of the HUD badge at 2x, same NexusBadgeView), spans badgeCells; NexusSpacer fills the rest
	    NexusInfoPanel           level, xp bar, "x / 100 XP", one row per NexusConfig.categories and the total; spans infoCells
	    BackButton / CloseSlot   the footer (CollectionsConfig.LAYOUT footer columns); BlankSlot fills every free cell
	The templates live in StarterGui.CentralizedAscensionMenu.TemporaryMenus (tools/studio/build_nexus_page.luau builds them; restyle
	freely, keep the names: NexusBadgeSlot.Panel.Badge, NexusInfoPanel.Panel.{LevelLabel, NextLabel, BarTrack.BarFill, XpLabel,
	Rows.RowTemplate.{Title, Value}, TotalLabel, TotalValue). New categories get a row automatically (cloned from RowTemplate).

	API:  init(sharedRefs) / populate(frame) / depopulate() / reset() / tooltipText() -> { title, desc, click } for the Profile button
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = Modules:WaitForChild("Config")
local NexusConfig = require(Config:WaitForChild("NexusConfig")) :: any
local HudTheme = require(Config:WaitForChild("HudTheme")) :: any
local CollectionsConfig = require(Modules:WaitForChild("CollectionsConfig")) :: any
local NexusBadgeView = require(Modules:WaitForChild("NexusBadgeView")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

local ATTR = NexusConfig.attributes
local LAYOUT = CollectionsConfig.LAYOUT
local PAGE = NexusConfig.page
local XP = HudTheme.badge.xp

local player = Players.LocalPlayer

local M = {}

local templates: { [string]: Instance? } = {}
local live: { connections: { RBXScriptConnection }, view: any, refresh: (() -> ())? } = { connections = {}, view = nil, refresh = nil }

-- ===================== HELPERS =====================
local function rich(hexColor: string, text: string): string
	return string.format('<font color="%s">%s</font>', hexColor, text)
end

local function number(n: number): string
	return MoneyLib.DealWithPoints(math.floor(n))
end

local function cell(row: number, col: number): number
	return row * LAYOUT.columns + col
end

--- Everything the page and the tooltip show, from the Player attributes.
local function snapshot()
	local level = player:GetAttribute(ATTR.level) or 0
	local progress = player:GetAttribute(ATTR.progress) or 0
	local total = player:GetAttribute(ATTR.total) or 0
	local _, _, into, need = NexusConfig.levelFromXp(total)
	return {
		level = level,
		progress = progress,
		total = total,
		into = into,
		need = need,
		maxed = level >= NexusConfig.curve.maxLevel,
	}
end

local function xpText(s): string
	if s.maxed then
		return rich("#FFAA00", "<b>MAX LEVEL</b>")
	end
	return string.format("%s%s%s %s", rich("#FFFF55", number(s.into)), rich("#FFAA00", "/"), rich("#FFFF55", number(s.need)), rich("#AAAAAA", "XP"))
end

--- Tooltip of the Profile grid's AethericNexus button.
function M.tooltipText()
	local s = snapshot()
	local color = NexusConfig.colorFor(s.level)
	return {
		title = string.format('%s %s', rich("#FF55FF", "<b>Aetheric Nexus Level</b>"), rich(color, "<b>" .. s.level .. "</b>")),
		desc = rich("#AAAAAA", "Your account level, earned from skill level-ups and collections.")
			.. "\n"
			.. xpText(s),
		click = rich("#FFFF55", "Click to view!"),
	}
end

-- ===================== GRID BUILDING =====================
local function clone(name: string): any
	local template = templates[name]
	return template and template:Clone() or nil
end

local function place(frame: Instance, occupied: { [number]: boolean }, index: number, slot: any)
	slot.LayoutOrder = index
	slot.Visible = true
	slot.Parent = frame
	occupied[index] = true
end

local function fillRows(info: any, s)
	local rows = info.Panel.Rows
	local order = NexusConfig.categoryOrder()
	for _, id in ipairs(order) do
		local category = NexusConfig.categories[id]
		local row = rows:FindFirstChild("Row_" .. id)
		if not row then
			row = rows.RowTemplate:Clone()
			row.Name = "Row_" .. id
			row.LayoutOrder = category.order or 99
			row.Visible = true
			row.Parent = rows
			row.Title.Text = rich(category.color, category.name)
		end
		row.Value.Text = number(player:GetAttribute(ATTR.categoryPrefix .. id) or 0)
	end
	info.Panel.TotalValue.Text = rich("#FFFF55", number(s.total))
end

function M.populate(frame: Instance)
	M.depopulate()
	local occupied: { [number]: boolean } = {}

	-- the big badge, then the transparent spacers under it
	local badgeSlot = clone("NexusBadgeSlot")
	local infoSlot = clone("NexusInfoPanel")
	local function spans(box: any, anchor: any)
		for row = box.rows[1], box.rows[2] do
			for col = box.cols[1], box.cols[2] do
				local index = cell(row, col)
				if row == box.rows[1] and col == box.cols[1] and anchor then
					place(frame, occupied, index, anchor)
				else
					local spacer = clone("NexusSpacer")
					if spacer then
						spacer.Name = "Spacer"
						place(frame, occupied, index, spacer)
					end
				end
			end
		end
	end
	spans(PAGE.badgeCells, badgeSlot)
	spans(PAGE.infoCells, infoSlot)

	if badgeSlot then
		live.view = NexusBadgeView.bind(badgeSlot.Panel.Badge, player)
	end
	if infoSlot then
		local panel = infoSlot.Panel
		local fill = panel.BarTrack.BarFill
		local tween: Tween? = nil
		local first = true
		local function refresh()
			local s = snapshot()
			panel.LevelLabel.Text = string.format("%s %s", rich("#FFAA00", "LEVEL"), rich(NexusConfig.colorFor(s.level), tostring(s.level)))
			panel.XpLabel.Text = xpText(s)
			panel.NextLabel.Text = rich("#AAAAAA", s.maxed and "COMPLETE" or "NEXT LEVEL")
			local goal = UDim2.fromScale(math.clamp(s.progress, 0, 1), 1)
			if tween then
				tween:Cancel()
			end
			if first then
				fill.Size = goal
				first = false
			else
				tween = TweenService:Create(fill, TweenInfo.new(XP.tween.time, XP.tween.style, XP.tween.direction), { Size = goal })
				tween:Play()
			end
			fillRows(infoSlot, s)
		end
		refresh()
		live.refresh = refresh
		local signals = { ATTR.level, ATTR.progress, ATTR.total }
		for id in pairs(NexusConfig.categories) do
			table.insert(signals, ATTR.categoryPrefix .. id)
		end
		for _, attribute in ipairs(signals) do
			table.insert(live.connections, player:GetAttributeChangedSignal(attribute):Connect(refresh))
		end
	end

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
				blank.LayoutOrder = index
				blank.Visible = true
				blank.Parent = frame
			end
		end
	end
end

function M.depopulate()
	for _, connection in ipairs(live.connections) do
		connection:Disconnect()
	end
	table.clear(live.connections)
	if live.view then
		live.view.destroy()
		live.view = nil
	end
	live.refresh = nil
end

function M.reset()
	M.depopulate()
end

function M.init(refs: any)
	local temporary = player:WaitForChild("PlayerGui"):WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
	for _, name in ipairs({ "NexusBadgeSlot", "NexusInfoPanel", "NexusSpacer", "BlankSlot" }) do
		templates[name] = temporary:FindFirstChild(name)
		if not templates[name] then
			warn("[NexusLevelPageModule] TemporaryMenus." .. name .. " is missing: run tools/studio/build_nexus_page.luau")
		end
	end
end

return M
