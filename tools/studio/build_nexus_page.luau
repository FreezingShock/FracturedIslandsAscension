-- build_nexus_page.luau
-- Creates the GUI templates of the Aetheric Nexus Level page (NexusLevelPageModule looks them up BY NAME). Run through the Studio MCP
-- (execute_luau, Edit datamodel, Play stopped), AFTER build_nexus_badge.luau (the page's big badge is a clone of the HUD badge).
--   ReplicatedStorage.GridTemplates.NexusLevelMenu      Folder: BackButton + CloseSlot (copied from CollectionsMenu3)
--   StarterGui.CentralizedAscensionMenu.TemporaryMenus
--     NexusSpacer       a transparent cell (the cells a big slot spans)
--     NexusBadgeSlot    one cell; Panel (4 x 5 cells wide) > Badge (clone of FIAHUD.Root.Badge, UIScale 2, NexusBadgeView drives it)
--     NexusInfoPanel    one cell; Panel (5 x 5 cells wide) > LevelLabel, NextLabel, BarTrack > BarFill (gradient), XpLabel, SourcesLabel,
--                       Rows (UIListLayout) > RowTemplate > Title + Value, TotalLabel, TotalValue
-- Restyle freely, keep the names and the Panel / label children. Idempotent: an existing template is left alone unless FORCE = true.
-- Designed in the Figma master file (page Menus & HUD, "GridTemplates.NexusLevelMenu").
local FORCE = false

local RS = game:GetService("ReplicatedStorage")
local TM = game:GetService("StarterGui"):WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
local GridTemplates = RS:WaitForChild("GridTemplates")
local XP = require(RS.Modules.Config.HudTheme:Clone()).badge.xp
local made = {}

local FONT = Font.new("rbxassetid://12187371840", Enum.FontWeight.Regular, Enum.FontStyle.Normal) -- Silkscreen
local CELL, GAP = 50, 9
local function span(n)
	return n * CELL + (n - 1) * GAP
end

local function fresh(parent, name)
	local old = parent:FindFirstChild(name)
	if old and not FORCE then
		return nil
	end
	if old then
		old:Destroy()
	end
	return true
end

local function holder(name)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Size = UDim2.fromOffset(CELL, CELL)
	f.Visible = false
	f.ZIndex = 2
	f.Parent = TM
	return f
end

local function panel(parent, w, h)
	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
	p.BorderSizePixel = 0
	p.Position = UDim2.fromOffset(0, 0)
	p.Size = UDim2.fromOffset(w, h)
	p.ZIndex = 2
	p.Parent = parent
	Instance.new("UICorner", p).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 20)
	stroke.Thickness = 2
	stroke.Parent = p
	return p
end

local function text(parent, name, x, y, w, h, size, align)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = Color3.new(1, 1, 1)
	l.RichText = true
	l.Text = ""
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.ZIndex = 3
	l.Parent = parent
	return l
end

if fresh(TM, "NexusSpacer") then
	local s = holder("NexusSpacer")
	s.ZIndex = 1
	table.insert(made, "NexusSpacer")
end

if fresh(TM, "NexusBadgeSlot") then
	local hudBadge = game:GetService("StarterGui"):WaitForChild("FIAHUD"):WaitForChild("Root"):WaitForChild("Badge")
	local slot = holder("NexusBadgeSlot")
	local p = panel(slot, span(4), span(5))
	local badge = hudBadge:Clone()
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.5, 0.5)
	badge.ZIndex = 3
	local scale = Instance.new("UIScale")
	scale.Scale = 2
	scale.Parent = badge
	badge.Parent = p
	table.insert(made, "NexusBadgeSlot")
end

if fresh(TM, "NexusInfoPanel") then
	local slot = holder("NexusInfoPanel")
	local W = span(5)
	local p = panel(slot, W, span(5))
	text(p, "LevelLabel", 14, 12, W - 28, 28, 20)
	text(p, "NextLabel", 14, 44, W - 28, 14, 10)
	local track = Instance.new("Frame")
	track.Name = "BarTrack"
	track.BackgroundColor3 = XP.trough
	track.BorderSizePixel = 0
	track.Position = UDim2.fromOffset(14, 62)
	track.Size = UDim2.fromOffset(W - 28, 14)
	track.ZIndex = 3
	track.Parent = p
	local fill = Instance.new("Frame")
	fill.Name = "BarFill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 4
	fill.Parent = track
	local gradient = Instance.new("UIGradient")
	local keys = {}
	for i, color in ipairs(XP.fillBands) do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#XP.fillBands - 1), color))
	end
	gradient.Color = ColorSequence.new(keys)
	gradient.Rotation = 90 -- the same top-to-bottom green gradient as the badge's xp
	gradient.Parent = fill
	text(p, "XpLabel", 14, 82, W - 28, 16, 12)
	local caption = text(p, "SourcesLabel", 14, 122, W - 28, 14, 10)
	caption.Text = '<font color="#AAAAAA">XP SOURCES</font>'
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(14, 142)
	rows.Size = UDim2.fromOffset(W - 28, 96)
	rows.ZIndex = 3
	rows.Parent = p
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = rows
	local row = Instance.new("Frame")
	row.Name = "RowTemplate"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromOffset(W - 28, 22)
	row.Visible = false
	row.ZIndex = 3
	row.Parent = rows
	text(row, "Title", 0, 0, W - 100, 22, 11)
	text(row, "Value", W - 28 - 90, 0, 90, 22, 11, Enum.TextXAlignment.Right)
	local total = text(p, "TotalLabel", 14, W - 40, 120, 20, 11)
	total.Text = '<font color="#FFFFFF">TOTAL XP</font>'
	text(p, "TotalValue", W - 14 - 120, W - 40, 120, 20, 11, Enum.TextXAlignment.Right)
	table.insert(made, "NexusInfoPanel")
end

if fresh(GridTemplates, "NexusLevelMenu") then
	local folder = Instance.new("Folder")
	folder.Name = "NexusLevelMenu"
	local source = GridTemplates:WaitForChild("CollectionsMenu3")
	for _, name in ipairs({ "BackButton", "CloseSlot" }) do
		source[name]:Clone().Parent = folder
	end
	folder.Parent = GridTemplates
	table.insert(made, "NexusLevelMenu")
end

return #made == 0 and "nothing to do (all templates exist)" or ("created: " .. table.concat(made, ", "))
