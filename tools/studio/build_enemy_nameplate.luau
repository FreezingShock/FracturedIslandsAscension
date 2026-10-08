-- ReplicatedStorage.GUI.EnemyNameplate (+ EnemyNameplate_Tag): the nameplate EnemyNameplateController clones over every Enemy.
-- Designed in Figma (tools/figma/enemy_nameplate_design_v3.png). Names the script looks up (restyle freely, keep the names):
--   Title(CanvasGroup) > NameLabel, LevelBadge > LevelLabel
--   BarGroup(CanvasGroup) > Bar > Track > Ghost, Fill, HpLabel ; EdgeL / EdgeR diamonds
--   Tags (CanvasGroup under the name) > pills EnemyNameplate_TagGroup > chips EnemyNameplate_Tag (Scale, Icon > Glyph / IconImage, Count)
-- All numbers / colours of the BEHAVIOUR live in Modules.Config.NameplateConfig. Edit datamodel. Refuses to overwrite unless FORCE.
local FORCE = false
local RS = game:GetService("ReplicatedStorage")
local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
for _, name in ipairs({ "EnemyNameplate", "EnemyNameplate_Tag", "EnemyNameplate_TagGroup" }) do
	if gui:FindFirstChild(name) then
		if not FORCE then
			return name .. " exists (set FORCE = true to rebuild)"
		end
		gui[name]:Destroy()
	end
end

local function hex(h)
	return Color3.fromHex(h)
end
local SILK_PATH = "rbxasset://fonts/families/Silkscreen.json"
local SILK = Font.new(SILK_PATH)
local MERRI = Font.fromEnum(Enum.Font.Merriweather)

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end
local function stroke(parent, color, thickness, border)
	return new("UIStroke", {
		Color = hex(color),
		Thickness = thickness,
		ApplyStrokeMode = border and Enum.ApplyStrokeMode.Border or Enum.ApplyStrokeMode.Contextual,
	}, parent)
end
local function gradient(parent, top, bottom)
	return new("UIGradient", { Rotation = 90, Color = ColorSequence.new(hex(top), hex(bottom)) }, parent)
end
local function label(props, parent)
	props.BackgroundTransparency = 1
	return new("TextLabel", props, parent)
end

-- ===================== NAMEPLATE =====================
local b = new("BillboardGui", {
	Name = "EnemyNameplate",
	Size = UDim2.fromOffset(250, 84),
	StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0),
	AlwaysOnTop = false,
	LightInfluence = 0,
	MaxDistance = 70,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

-- name + level
local title = new("CanvasGroup", {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 0),
	Size = UDim2.new(1, 0, 0, 28),
	BackgroundTransparency = 1,
}, b)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, title)
local nameLabel = label({
	Name = "NameLabel",
	LayoutOrder = 1,
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	Text = "Enemy",
	TextSize = 17,
	FontFace = MERRI,
	TextColor3 = hex("#FF5555"),
}, title)
stroke(nameLabel, "#1A0808", 2)
local badge = new("Frame", {
	Name = "LevelBadge",
	LayoutOrder = 2,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 19),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, title)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, badge)
stroke(badge, "#2A2A2D", 2, true).Name = "BadgeStroke"
gradient(badge, "#8B8B8E", "#5A5A5E").Name = "BadgeGradient"
new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, badge)
local lv = label({
	Name = "LevelLabel",
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	Text = "LV 1",
	TextSize = 11,
	FontFace = SILK,
	TextColor3 = hex("#FFFFFF"),
}, badge)
stroke(lv, "#000000", 1)

-- bar
local barGroup = new("CanvasGroup", {
	Name = "BarGroup",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 48),
	Size = UDim2.fromOffset(190, 26),
	BackgroundTransparency = 1,
}, b)
local bar = new("Frame", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(164, 14),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, barGroup)
gradient(bar, "#8A6444", "#4A2F1E")
stroke(bar, "#1E1209", 2, true)
local track = new("Frame", {
	Name = "Track",
	Position = UDim2.fromOffset(4, 3),
	Size = UDim2.new(1, -8, 1, -6),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, bar)
gradient(track, "#2E211B", "#4A362B")
local ghost = new("Frame", {
	Name = "Ghost",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 1,
}, track)
gradient(ghost, "#F6D2A0", "#C98A55")
local fill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ZIndex = 2,
}, track)
gradient(fill, "#F28C5E", "#B4492A")
new("Frame", {
	Name = "Highlight",
	Size = UDim2.new(1, 0, 0, 2),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BackgroundTransparency = 0.7,
	BorderSizePixel = 0,
	ZIndex = 3,
}, fill)
local hp = label({
	Name = "HpLabel",
	Size = UDim2.fromScale(1, 1),
	Text = "0",
	TextSize = 10,
	FontFace = SILK,
	TextColor3 = hex("#FFFFFF"),
	ZIndex = 5,
}, track)
stroke(hp, "#000000", 1)

-- diamond ends (rotated squares with a lighter gem)
for _, side in ipairs({ "L", "R" }) do
	local edge = new("Frame", {
		Name = "Edge" .. side,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, side == "L" and 13 or 177, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, barGroup)
	gradient(edge, "#B0865E", "#5E3C24")
	stroke(edge, "#1E1209", 2, true)
	new("Frame", {
		Name = "Gem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = hex("#D7B087"),
		BorderSizePixel = 0,
		ZIndex = 7,
	}, edge)
end

-- tag row (under the name): a pill per kind holds that kind's icon chips
new("UIScale", { Name = "Scale" }, barGroup)
local tags = new("CanvasGroup", {
	Name = "Tags",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 27),
	Size = UDim2.new(1, 0, 0, 20),
	BackgroundTransparency = 1,
}, b)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tags)
b.Parent = gui

-- ===================== TAG GROUP PILL + TAG CHIP =====================
local group = new("Frame", {
	Name = "EnemyNameplate_TagGroup",
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 18),
	BackgroundColor3 = hex("#1B1512"),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
}, nil)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, group)
stroke(group, "#8A6444", 2, true)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 3),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, group)
new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, group)
group.Parent = gui

local chip = new("Frame", {
	Name = "EnemyNameplate_Tag",
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 14),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, nil)
new("UIScale", { Name = "Scale" }, chip)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 2),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, chip)
local icon = new("Frame", {
	Name = "Icon",
	LayoutOrder = 1,
	Size = UDim2.fromOffset(12, 12),
	BackgroundColor3 = hex("#FFFFFF"),
	BorderSizePixel = 0,
}, chip)
new("UICorner", { CornerRadius = UDim.new(0, 2) }, icon)
label({
	Name = "Glyph",
	Size = UDim2.fromScale(1, 1),
	Text = "?",
	TextSize = 8,
	FontFace = Font.new(SILK_PATH, Enum.FontWeight.Bold),
	TextColor3 = hex("#1B1512"),
}, icon)
new("ImageLabel", {
	Name = "IconImage",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = "",
	Visible = false,
	ZIndex = 2,
}, icon)
local count = label({
	Name = "Count",
	LayoutOrder = 2,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	Text = "",
	TextSize = 9,
	FontFace = SILK,
	TextColor3 = hex("#FFFFFF"),
	Visible = false,
}, chip)
stroke(count, "#000000", 1)
chip.Parent = gui

return "built GUI.EnemyNameplate + EnemyNameplate_Tag + EnemyNameplate_TagGroup"
