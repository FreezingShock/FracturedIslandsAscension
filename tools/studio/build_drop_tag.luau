-- ReplicatedStorage.GUI.DropTag: the tag over a dropped item, cloned (pooled) by DropTooltipController.
-- ONE BillboardGui with three layers that morph into each other: Dot (far) -> Folded (near) -> Card (aimed at).
-- The Folded chip and the Card are cut from StarterGui.TooltipMenu.Template, so the frame, TitleFrame, ItemIcon, TitleLabel,
-- ItemTags and StackLabel are the real tooltip's (restyle the tooltip, then rebuild this with FORCE = true).
-- Edit datamodel. Refuses to overwrite unless FORCE. REMOVE_OLD also deletes the 3.58.0 templates GUI.DropCard / GUI.DropChip.
--
-- DropTag (BillboardGui)                       size is only room for the layers; the controller anchors it with an Attachment
--   TagTemplate (Frame, hidden)                the tag pill prototype (cloned into ItemTags)
--   Group (Frame)
--     Dot (CanvasGroup)   Scale (UIScale)      far stage
--       Body > SizeScale (UIScale), Halo (ImageLabel, soft dot), Gem (Frame, UICorner, UIStroke, Highlight)
--     Folded (CanvasGroup) Scale (UIScale)     near stage, everything folded
--       Chip (Frame: StrokeOuter, StrokeInner) > Dot (Frame, UIStroke, Highlight), TitleLabel, CountLabel
--     Card (CanvasGroup)  Scale (UIScale)      the aimed-at drop
--       Card (Frame: StrokeOuter, StrokeInner) > TitleFrame (ItemIcon [IconStrokeA, IconStrokeB, ItemImage], TitleLabel,
--                                                  ItemTags, StackLabel), Details (Divider1, DescriptionLabel)
local FORCE = false
local REMOVE_OLD = true

local DOT_TEXTURE = "rbxassetid://105239482007932" -- EnemyConfig.textures.dot, a soft round mote (the halo)

local RS = game:GetService("ReplicatedStorage")
local SG = game:GetService("StarterGui")
local template = SG:FindFirstChild("TooltipMenu") and SG.TooltipMenu:FindFirstChild("Template")
assert(template, "StarterGui.TooltipMenu.Template not found")

local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
if gui:FindFirstChild("DropTag") then
	if not FORCE then
		return "DropTag exists (set FORCE = true to rebuild)"
	end
	gui.DropTag:Destroy()
end
if REMOVE_OLD then
	for _, name in ipairs({ "DropCard", "DropChip" }) do
		local old = gui:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

local GRAY = Color3.fromRGB(170, 170, 170)
local DARK = Color3.fromRGB(85, 85, 85)

local function make(class: string, props: { [string]: any }, parent: Instance?)
	local inst = Instance.new(class)
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	inst.Parent = parent
	return inst
end

local function pad(parent: Instance, l: number, r: number, t: number, b: number)
	return make("UIPadding", {
		PaddingLeft = UDim.new(0, l),
		PaddingRight = UDim.new(0, r),
		PaddingTop = UDim.new(0, t),
		PaddingBottom = UDim.new(0, b),
	}, parent)
end

--- The Template's two frame strokes (4 outer, 2 inner) get names the controller can find.
local function nameStrokes(frame: Instance)
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

--- A layer: a CanvasGroup anchored bottom centre on the billboard's middle; the controller moves / scales / fades it.
local function layer(name: string, parent: Instance, auto: boolean)
	local g = make("CanvasGroup", {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(),
		AutomaticSize = auto and Enum.AutomaticSize.XY or Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		Visible = false,
	}, parent)
	make("UIScale", { Name = "Scale", Scale = 1 }, g)
	return g
end

local KEEP = { UIStroke = true, UIGradient = true, UIListLayout = true, UIPadding = true, UICorner = true, UISizeConstraint = true }

local tag = make("BillboardGui", {
	Name = "DropTag",
	Size = UDim2.fromOffset(560, 340),
	AlwaysOnTop = false,
	LightInfluence = 0,
	MaxDistance = math.huge,
	ResetOnSpawn = false,
	ClipsDescendants = false,
	Active = false,
})
local group = make("Frame", { Name = "Group", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 }, tag)

-- ===================== Dot (far) =====================
local dot = layer("Dot", group, false)
dot.Size = UDim2.fromOffset(64, 64)
local body = make("Frame", {
	Name = "Body",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(44, 44),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, dot)
make("UIScale", { Name = "SizeScale", Scale = 1 }, body) -- not "Size": that would hide the Frame's own Size property
make("ImageLabel", {
	Name = "Halo",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(44, 44),
	BackgroundTransparency = 1,
	Image = DOT_TEXTURE,
	ImageTransparency = 0.62,
	ZIndex = 1,
}, body)
local gem = make("Frame", {
	Name = "Gem",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(14, 14),
	BackgroundColor3 = GRAY,
	BorderSizePixel = 0,
	ZIndex = 2,
}, body)
make("UICorner", { CornerRadius = UDim.new(0, 3) }, gem)
make("UIStroke", { Thickness = 2, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, gem)
local highlight = make("Frame", {
	Name = "Highlight",
	Position = UDim2.fromOffset(2, 2),
	Size = UDim2.fromOffset(4, 4),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.55,
	BorderSizePixel = 0,
	ZIndex = 3,
}, gem)
make("UICorner", { CornerRadius = UDim.new(0, 1) }, highlight)

-- ===================== Folded (near) =====================
local folded = layer("Folded", group, true)
pad(folded, 10, 10, 10, 10)
local chip = template:Clone()
chip.Name = "Chip"
chip.Visible = true
chip.Position = UDim2.new()
chip.AnchorPoint = Vector2.new()
chip.Size = UDim2.new()
chip.AutomaticSize = Enum.AutomaticSize.XY
chip.LayoutOrder = 0
for _, c in ipairs(chip:GetChildren()) do
	if not (c:IsA("UIStroke") or c:IsA("UIGradient") or c:IsA("UICorner")) then
		c:Destroy()
	end
end
nameStrokes(chip)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 6),
}, chip)
pad(chip, 8, 8, 4, 4)
local cdot = make("Frame", {
	Name = "Dot",
	Size = UDim2.fromOffset(10, 10),
	BackgroundColor3 = GRAY,
	BorderSizePixel = 0,
	LayoutOrder = 0,
}, chip)
make("UICorner", { CornerRadius = UDim.new(0, 2) }, cdot)
make("UIStroke", { Thickness = 2, Color = DARK, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, cdot)
local chl = make("Frame", {
	Name = "Highlight",
	Position = UDim2.fromOffset(1, 1),
	Size = UDim2.fromOffset(3, 3),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.55,
	BorderSizePixel = 0,
}, cdot)
make("UICorner", { CornerRadius = UDim.new(0, 1) }, chl)
local ctitle = template.TitleFrame.TitleLabel:Clone()
ctitle.Name = "TitleLabel"
ctitle.Text = "Item"
ctitle.TextSize = 14
ctitle.Position = UDim2.new()
ctitle.AnchorPoint = Vector2.new()
ctitle.LayoutOrder = 1
ctitle.AutomaticSize = Enum.AutomaticSize.XY
ctitle.TextTruncate = Enum.TextTruncate.AtEnd
make("UISizeConstraint", { MaxSize = Vector2.new(156, math.huge) }, ctitle)
local ctStroke = ctitle:FindFirstChildOfClass("UIStroke")
if ctStroke then
	ctStroke.Thickness = 1
end
ctitle.Parent = chip
local ccount = template.TitleFrame.StackLabel:Clone()
ccount.Name = "CountLabel"
ccount.Text = "X3"
ccount.TextSize = 14
ccount.Position = UDim2.new()
ccount.AnchorPoint = Vector2.new()
ccount.LayoutOrder = 2
ccount.AutomaticSize = Enum.AutomaticSize.XY
ccount.Visible = false
local ccStroke = ccount:FindFirstChildOfClass("UIStroke")
if ccStroke then
	ccStroke.Thickness = 1
end
ccount.Parent = chip
chip.Parent = folded

-- ===================== Card (aimed at) =====================
local cardLayer = layer("Card", group, true)
pad(cardLayer, 10, 10, 10, 10)
local card = template:Clone()
card.Name = "Card"
card.Visible = true
card.Position = UDim2.new()
card.AnchorPoint = Vector2.new()
card.Size = UDim2.new()
card.AutomaticSize = Enum.AutomaticSize.XY
card.LayoutOrder = 0
for _, c in ipairs(card:GetChildren()) do
	if not KEEP[c.ClassName] and c.Name ~= "TitleFrame" and c.Name ~= "Divider1" and c.Name ~= "DescriptionLabel" then
		c:Destroy()
	end
end
nameStrokes(card)
local limit = card:FindFirstChildOfClass("UISizeConstraint")
if limit then
	limit.MinSize = Vector2.new(0, 0)
	limit.MaxSize = Vector2.new(440, math.huge)
end

local titleFrame = card.TitleFrame
titleFrame.LayoutOrder = 0
titleFrame.Visible = true
local tags = titleFrame.ItemTags
local rarityTag = tags:FindFirstChild("Rarity") or tags:FindFirstChildWhichIsA("Frame")
local tagTemplate = rarityTag:Clone()
tagTemplate.Name = "TagTemplate"
tagTemplate.Visible = false
tagTemplate.Parent = tag
for _, c in ipairs(tags:GetChildren()) do
	if c:IsA("Frame") then
		c:Destroy()
	end
end
local tagLimit = tags:FindFirstChildOfClass("UISizeConstraint")
if tagLimit then
	tagLimit.MaxSize = Vector2.new(300, math.huge)
end
local tagList = tags:FindFirstChildOfClass("UIListLayout")
if tagList then
	tagList.Wraps = false -- a wrapping list grows to its max width; this one must hug its tags so a short name gives a narrow card
end
local title = titleFrame.TitleLabel
title.Text = "Item"
title.TextTruncate = Enum.TextTruncate.AtEnd
make("UISizeConstraint", { MaxSize = Vector2.new(296, math.huge) }, title)
local stack = titleFrame:FindFirstChild("StackLabel")
if stack then
	stack.Visible = false
end
local icon = titleFrame.ItemIcon
local strokeCount = 0
for _, c in ipairs(icon:GetChildren()) do
	if c:IsA("UIStroke") then
		strokeCount += 1
		c.Name = strokeCount == 1 and "IconStrokeA" or "IconStrokeB" -- A = the rarity colour, B = its dark partner (as TooltipModule does)
	end
end
make("ImageLabel", {
	Name = "ItemImage",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -10, 1, -10),
	ScaleType = Enum.ScaleType.Fit,
	Visible = false,
}, icon)

-- the divider and the description share one clipped frame, so they can unfold by height
local details = make("Frame", {
	Name = "Details",
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.None,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, card)
make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }, details)
local divider = card.Divider1
divider.LayoutOrder = 0
divider.Visible = true
divider.Parent = details
local desc = card.DescriptionLabel
desc.LayoutOrder = 1
desc.Visible = true
desc.Position = UDim2.new()
desc.AnchorPoint = Vector2.new()
desc.Size = UDim2.new(1, 0, 0, 0)
desc.AutomaticSize = Enum.AutomaticSize.Y
desc.TextSize = 16
desc.TextWrapped = true
desc.TextXAlignment = Enum.TextXAlignment.Left
desc.Text = ""
desc.Parent = details
card.Parent = cardLayer

tag.Parent = gui
return "built GUI.DropTag" .. (REMOVE_OLD and " (old DropCard / DropChip removed)" or "")
