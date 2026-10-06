-- ReplicatedStorage.GUI.DropCard and DropChip: the tooltips over dropped items, cloned by DropTooltipController.
-- Both are cut from StarterGui.TooltipMenu.Template so the frame, TitleFrame, ItemIcon, TitleLabel, ItemTags and StackLabel
-- are the real tooltip's (restyle the tooltip, rebuild these with FORCE = true). Edit datamodel. Refuses to overwrite unless FORCE.
--
-- DropCard (BillboardGui)
--   TagTemplate (Frame, hidden)          the tag pill prototype (cloned into ItemTags)
--   Group (CanvasGroup)                  anchored bottom centre; the controller tweens GroupTransparency, Scale and Position
--     Scale (UIScale), UIPadding         padding keeps the outside rings inside the canvas
--     Card (Frame)                       Template look: StrokeOuter (4), StrokeInner (2), gradient, corner, padding
--       TitleFrame > ItemIcon (strokes, ItemImage), TitleLabel, ItemTags, StackLabel
--       Divider1, DescriptionLabel
-- DropChip (BillboardGui) > Group (CanvasGroup) > Scale, UIPadding, Chip (Frame: StrokeOuter, StrokeInner, Dot, NameLabel)
local FORCE = false

local RS = game:GetService("ReplicatedStorage")
local SG = game:GetService("StarterGui")
local template = SG:FindFirstChild("TooltipMenu") and SG.TooltipMenu:FindFirstChild("Template")
assert(template, "StarterGui.TooltipMenu.Template not found")

local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
for _, name in ipairs({ "DropCard", "DropChip" }) do
	local old = gui:FindFirstChild(name)
	if old then
		if not FORCE then
			return name .. " exists (set FORCE = true to rebuild)"
		end
		old:Destroy()
	end
end

local KEEP = { UIStroke = true, UIGradient = true, UIListLayout = true, UIPadding = true, UICorner = true, UISizeConstraint = true }
local function strokesOf(frame: Instance)
	local outer, inner
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("UIStroke") then
			if c.Thickness >= 3 then
				outer = outer or c
			else
				inner = inner or c
			end
		end
	end
	if outer then
		outer.Name = "StrokeOuter"
	end
	if inner then
		inner.Name = "StrokeInner"
	end
end

local function billboard(name: string, size: Vector2, offset: Vector3)
	local b = Instance.new("BillboardGui")
	b.Name = name
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.StudsOffsetWorldSpace = offset
	b.AlwaysOnTop = false
	b.LightInfluence = 0
	b.MaxDistance = 12
	b.ResetOnSpawn = false
	b.ClipsDescendants = false
	b.Active = false
	return b
end

local function group(parent: Instance)
	local g = Instance.new("CanvasGroup")
	g.Name = "Group"
	g.AnchorPoint = Vector2.new(0.5, 1)
	g.Position = UDim2.fromScale(0.5, 1)
	g.Size = UDim2.new()
	g.AutomaticSize = Enum.AutomaticSize.XY
	g.BackgroundTransparency = 1
	g.GroupTransparency = 1
	g.Parent = parent
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = g
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Scale = 1
	scale.Parent = g
	return g
end

-- ===================== DropCard =====================
local card = billboard("DropCard", Vector2.new(440, 220), Vector3.new(0, 1.9, 0))
local g = group(card)

local frame = template:Clone()
frame.Name = "Card"
frame.Visible = true
frame.Position = UDim2.new()
frame.AnchorPoint = Vector2.new()
frame.Size = UDim2.new()
frame.AutomaticSize = Enum.AutomaticSize.XY
frame.LayoutOrder = 0
for _, c in ipairs(frame:GetChildren()) do
	if not KEEP[c.ClassName] and c.Name ~= "TitleFrame" and c.Name ~= "Divider1" and c.Name ~= "DescriptionLabel" then
		c:Destroy()
	end
end
strokesOf(frame)
local sizeC = frame:FindFirstChildOfClass("UISizeConstraint")
if sizeC then
	sizeC.MinSize = Vector2.new(0, 0)
	sizeC.MaxSize = Vector2.new(340, math.huge)
end
frame.Divider1.LayoutOrder = 1
frame.Divider1.Visible = false
frame.DescriptionLabel.LayoutOrder = 2
frame.DescriptionLabel.Visible = false
frame.DescriptionLabel.TextSize = 16
frame.TitleFrame.LayoutOrder = 0
frame.TitleFrame.Visible = true

-- tag prototype lives beside the card; ItemTags starts empty
local tags = frame.TitleFrame.ItemTags
local proto = tags:FindFirstChild("Rarity") or tags:FindFirstChildWhichIsA("Frame")
local tagProto = proto:Clone()
tagProto.Name = "TagTemplate"
tagProto.Visible = false
tagProto.Parent = card
for _, c in ipairs(tags:GetChildren()) do
	if c:IsA("Frame") then
		c:Destroy()
	end
end
frame.TitleFrame.TitleLabel.Text = "Item"
local stack = frame.TitleFrame:FindFirstChild("StackLabel")
if stack then
	stack.Visible = false
end
local icon = frame.TitleFrame.ItemIcon
local iconStrokes = 0
for _, c in ipairs(icon:GetChildren()) do
	if c:IsA("UIStroke") then
		iconStrokes += 1
		c.Name = iconStrokes == 1 and "IconStrokeA" or "IconStrokeB" -- A = rarity colour, B = its dark partner (as TooltipModule does)
	end
end
local img = Instance.new("ImageLabel")
img.Name = "ItemImage"
img.BackgroundTransparency = 1
img.AnchorPoint = Vector2.new(0.5, 0.5)
img.Position = UDim2.fromScale(0.5, 0.5)
img.Size = UDim2.new(1, -10, 1, -10)
img.ScaleType = Enum.ScaleType.Fit
img.Parent = icon
frame.Parent = g
card.Parent = gui

-- ===================== DropChip =====================
local chip = billboard("DropChip", Vector2.new(300, 70), Vector3.new(0, 1.5, 0))
local cg = group(chip)
local cf = template:Clone()
cf.Name = "Chip"
cf.Visible = true
cf.Position = UDim2.new()
cf.AnchorPoint = Vector2.new()
cf.Size = UDim2.new()
cf.AutomaticSize = Enum.AutomaticSize.XY
for _, c in ipairs(cf:GetChildren()) do
	if not (c:IsA("UIStroke") or c:IsA("UIGradient") or c:IsA("UICorner")) then
		c:Destroy()
	end
end
strokesOf(cf)
local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Horizontal
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 6)
list.Parent = cf
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 4), UDim.new(0, 4)
pad.Parent = cf
local dot = Instance.new("Frame")
dot.Name = "Dot"
dot.Size = UDim2.fromOffset(10, 10)
dot.BackgroundColor3 = Color3.fromRGB(170, 170, 170)
dot.BorderSizePixel = 0
dot.LayoutOrder = 0
dot.Parent = cf
local dc = Instance.new("UICorner")
dc.CornerRadius = UDim.new(0, 2)
dc.Parent = dot
local ds = Instance.new("UIStroke")
ds.Thickness = 2
ds.Color = Color3.fromRGB(85, 85, 85)
ds.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
ds.Parent = dot
local nameLabel = template.TitleFrame.TitleLabel:Clone()
nameLabel.Name = "NameLabel"
nameLabel.Text = "Item"
nameLabel.TextSize = 14
nameLabel.Position = UDim2.new()
nameLabel.LayoutOrder = 1
nameLabel.AutomaticSize = Enum.AutomaticSize.XY
local ns = nameLabel:FindFirstChildOfClass("UIStroke")
if ns then
	ns.Thickness = 1.5
end
nameLabel.Parent = cf
cf.Parent = cg
chip.Parent = gui

return "built GUI.DropCard and GUI.DropChip"
