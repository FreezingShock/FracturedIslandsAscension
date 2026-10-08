-- ReplicatedStorage.GUI.EnemyNameplate (+ _Tag, _TagGroup): the nameplate EnemyNameplateController clones over every Enemy.
-- Designed in Figma (tools/figma/enemy_nameplate_tagrow_v5.png). A vertical Stack (UIListLayout): Title / BarGroup / Tags.
-- BarGroup is 0 high at full health and the controller tweens it open, so the bar slides in BETWEEN the name and the tags.
-- Names the script looks up (restyle freely, keep the names):
--   Stack > Title(CanvasGroup: UIPadding, UIScale) > NameLabel, LevelBadge > LevelLabel (+ BadgeStroke, BadgeGradient)
--   Stack > BarGroup(CanvasGroup) > BarRoot(UIScale) > Bar > Track > Ghost, Fill, HpLabel ; EdgeL / EdgeR diamonds
--   Stack > Tags(CanvasGroup) > pills EnemyNameplate_TagGroup (Stroke > UIGradient) > chips EnemyNameplate_Tag (Scale, Icon > Glyph / IconImage, Count)
-- Behaviour numbers / colours live in Modules.Config.NameplateConfig. Edit datamodel. Refuses to overwrite unless FORCE.
local FORCE = false
local RS = game:GetService("ReplicatedStorage")
local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
for _, name in ipairs({ "EnemyNameplate", "EnemyNameplate_Tag", "EnemyNameplate_TagGroup", "EnemyNameplate_Shard" }) do
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
-- Silkscreen is not one of Roblox's built-in families (the family path fails to load). Until Silkscreen is uploaded as a custom
-- font, the project pixel font stands in; swap SILK_PATH for the uploaded font family id then.
local SILK_PATH = "rbxassetid://12187371840"
local SILK = Font.new(SILK_PATH)
local MERRI = Font.new(Font.fromEnum(Enum.Font.Merriweather).Family, Enum.FontWeight.Bold)

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
	Size = UDim2.fromOffset(400, 110), -- wide enough for a full tag row
	StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0),
	AlwaysOnTop = false,
	LightInfluence = 0,
	MaxDistance = 70,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local stack = new("Frame", {
	Name = "Stack",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
}, b)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 0),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, stack)

-- name + level
local title = new("CanvasGroup", {
	Name = "Title",
	LayoutOrder = 1,
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
}, stack)
new("UIPadding", {}, title) -- PaddingTop is tweened for the rise
new("UIScale", { Name = "Scale" }, title) -- death punch
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
	TextSize = 16,
	FontFace = MERRI,
	TextColor3 = hex("#FF5555"),
}, title)
stroke(nameLabel, "#1A0808", 2)
local badge = new("Frame", {
	Name = "LevelBadge",
	LayoutOrder = 2,
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, title)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, badge)
stroke(badge, "#2A2A2D", 2, true).Name = "BadgeStroke"
gradient(badge, "#8B8B8E", "#5A5A5E").Name = "BadgeGradient"
new("UIPadding", {
	PaddingLeft = UDim.new(0, 5),
	PaddingRight = UDim.new(0, 5),
	PaddingTop = UDim.new(0, 2),
	PaddingBottom = UDim.new(0, 2),
}, badge)
local lv = label({
	Name = "LevelLabel",
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	Text = "LV 1",
	TextSize = 16,
	FontFace = SILK,
	TextColor3 = hex("#FFFFFF"),
}, badge)
stroke(lv, "#000000", 1.5)

-- bar (a height of 0 hides it; the controller opens it between the title and the tags)
local barGroup = new("CanvasGroup", {
	Name = "BarGroup",
	LayoutOrder = 2,
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundTransparency = 1,
}, stack)
local barRoot = new("Frame", {
	Name = "BarRoot",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(200, 26),
	BackgroundTransparency = 1,
}, barGroup)
new("UIScale", { Name = "Scale" }, barRoot)
local bar = new("Frame", {
	Name = "Bar",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(164, 14),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, barRoot)
gradient(bar, "#8A6444", "#4A2F1E")
stroke(bar, "#1E1209", 2, true)
local track = new("Frame", {
	Name = "Track",
	Position = UDim2.fromOffset(0, 2),
	Size = UDim2.new(1, 0, 1, -4),
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
	Text = "0/0",
	TextSize = 11,
	FontFace = SILK,
	TextColor3 = hex("#FFFFFF"),
	ZIndex = 5,
}, track)
stroke(hp, "#000000", 1.5)
-- diamond ends: a rotated square, 2 studs-pixels outside each end of the bar, with a lighter gem
for _, side in ipairs({ "L", "R" }) do
	local edge = new("Frame", {
		Name = "Edge" .. side,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, side == "L" and -84 or 84, 0.5, 0),
		Size = UDim2.fromOffset(13, 13),
		Rotation = 45,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 6,
	}, barRoot)
	gradient(edge, "#B0865E", "#5E3C24")
	stroke(edge, "#1E1209", 2, true)
	new("Frame", {
		Name = "Gem",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(5, 5),
		BackgroundColor3 = hex("#D7B087"),
		BorderSizePixel = 0,
		ZIndex = 7,
	}, edge)
end

-- tag row (below the bar): a pill per kind holds that kind's icon chips
local tags = new("CanvasGroup", {
	Name = "Tags",
	LayoutOrder = 3,
	Size = UDim2.fromScale(1, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
}, stack)
-- room above (further from the bar) and below / at the sides so the pills' outer stroke is never clipped by the CanvasGroup
new("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 4),
	PaddingLeft = UDim.new(0, 6),
	PaddingRight = UDim.new(0, 6),
}, tags)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	Padding = UDim.new(0, 8), -- space between the pills
	SortOrder = Enum.SortOrder.LayoutOrder,
}, tags)
b.Parent = gui

-- ===================== TAG GROUP PILL + TAG CHIP =====================
-- the pill's fill and outline are top-to-bottom gradients (lighter on top); the controller recolours the outline per kind
local group = new("Frame", {
	Name = "EnemyNameplate_TagGroup",
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 26),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, nil)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, group)
gradient(group, "#3D312B", "#120E0C").Name = "FillGradient"
local groupStroke = stroke(group, "#FFFFFF", 2, true)
groupStroke.Name = "GroupStroke"
gradient(groupStroke, "#9BFF9B", "#2BA82B").Name = "StrokeGradient"
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, group)
new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, group)
group.Parent = gui

local chip = new("Frame", {
	Name = "EnemyNameplate_Tag",
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.fromOffset(0, 20),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, nil)
new("UIScale", { Name = "Scale" }, chip)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 3),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, chip)
local icon = new("Frame", {
	Name = "Icon",
	LayoutOrder = 1,
	Size = UDim2.fromOffset(18, 18),
	BackgroundColor3 = hex("#FFFFFF"),
	BorderSizePixel = 0,
}, chip)
new("UICorner", { CornerRadius = UDim.new(0, 2) }, icon)
label({
	Name = "Glyph",
	Size = UDim2.fromScale(1, 1),
	Text = "?",
	TextSize = 12,
	FontFace = Font.new(SILK_PATH, Enum.FontWeight.Bold),
	TextColor3 = hex("#1B1512"),
}, icon)
new("ImageLabel", {
	Name = "IconImage",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Image = "",
	ResampleMode = Enum.ResamplerMode.Pixelated, -- crisp pixel icons (assets/tag_icons, tools/gen_tag_icons.py)
	ScaleType = Enum.ScaleType.Fit,
	Visible = false,
	ZIndex = 2,
}, icon)
local count = label({
	Name = "Count",
	LayoutOrder = 2,
	AutomaticSize = Enum.AutomaticSize.X,
	Size = UDim2.new(0, 0, 1, 0),
	Text = "",
	TextSize = 14,
	FontFace = SILK,
	TextColor3 = hex("#FFFFFF"),
	Visible = false,
}, chip)
stroke(count, "#000000", 1.5)
chip.Parent = gui

-- ===================== DEATH SHARD =====================
-- one glowing triangle; the controller clones about 24 of them when the plate breaks apart (DeathConfig.hud), picks a
-- random cell of the 2x2 triangle sheet (ImageRectOffset 0 / 128) and a colour from DeathConfig.burst.colors
new("ImageLabel", {
	Name = "EnemyNameplate_Shard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(14, 14),
	BackgroundTransparency = 1,
	Image = "rbxassetid://88874298201257", -- assets/death_fx/death_triangles.png (tools/fx/gen_death_textures.py)
	ImageRectSize = Vector2.new(128, 128),
	ImageRectOffset = Vector2.new(0, 0),
	ImageColor3 = hex("#7FFFEA"),
	ResampleMode = Enum.ResamplerMode.Default,
}, gui)

return "built GUI.EnemyNameplate + _Tag + _TagGroup + _Shard"
