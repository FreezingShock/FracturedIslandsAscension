-- build_notifications.luau
-- Builds StarterGui.FIANotifications from the Figma file "FIA Notifications" (tooltip look: black body, 4px dark + 2px light border).
-- NotificationController binds by NAME, so restyle freely but do not rename:
--   FIANotifications (ScreenGui, ResetOnSpawn off)
--     Stack (Frame, bottom-left; UIListLayout bottom-up, UIScale "Scale")   cards are parented into Slot clones inside it
--     Templates (Folder, never shown)
--       Slot            (Frame)   one stack row: the card slides inside it, the row's height closes when the card leaves
--       CardLevelUp / CardCollection  (Frame = outer 4px border) > Body > Rule, Header (Icon (Gem, Image), Text (Title, Heading)),
--                         Gap, RewardsTitle, Lines, Flavor, Timer (Fill)
--       CardPickup      > Body > Row (Icon (Gem, Image), Label, Count), Timer (Fill)
--       CardSystem      > Body > Row (Icon (Gem, Image), Text (Title... Text, Sub)), Timer (Fill)
--       RewardLine      (TextLabel, RichText)   cloned into CardLevelUp / CardCollection Lines
-- Colours, texts and sizes of the live cards come from Modules/Config/NotificationConfig; this only holds the look and the layout.
-- Run on the Edit datamodel with the Studio MCP (stop Play first). Skips when FIANotifications exists unless FORCE = true.
local FORCE = false

local StarterGui = game:GetService("StarterGui")
if StarterGui:FindFirstChild("FIANotifications") then
	if not FORCE then
		return "FIANotifications already exists (set FORCE = true to rebuild)"
	end
	StarterGui.FIANotifications:Destroy()
end

local FONT = Font.new("rbxassetid://12187371840", Enum.FontWeight.Regular, Enum.FontStyle.Normal) -- Silkscreen
-- readable text: the tooltip body font until Noto Sans is uploaded (put its asset id here)
local TEXT_FONT = Font.new("rbxassetid://12187370747", Enum.FontWeight.Bold)
local FLAVOR_FONT = Font.fromEnum(Enum.Font.Merriweather)

local function hex(h)
	local n = tonumber(h:sub(2), 16)
	return Color3.fromRGB(bit32.rshift(n, 16) % 256, bit32.rshift(n, 8) % 256, n % 256)
end

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local function label(parent, name, text, color, size, extra)
	local l = new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = TEXT_FONT,
		Text = text,
		TextColor3 = hex(color),
		TextSize = size,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	new("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	for k, v in pairs(extra or {}) do
		l[k] = v
	end
	return l
end

local function list(parent, direction, padding, extra)
	local props = { SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = direction, Padding = UDim.new(0, padding) }
	for k, v in pairs(extra or {}) do
		props[k] = v
	end
	return new("UIListLayout", props, parent)
end

-- the tooltip shell: outer = the 4px dark border, Body = black glass + 2px light border
local function card(parent, name, width, padX, padY)
	local outer = new("Frame", {
		Name = name,
		BackgroundColor3 = hex("#4B4B4B"),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, outer)
	new("UIScale", { Name = "Pop" }, outer) -- the merge pop
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, outer)
	local body = new("Frame", {
		Name = "Body",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, outer)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, body)
	new("UIStroke", { Thickness = 2, Color = hex("#AAAAAA"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	new("UIPadding", { PaddingTop = UDim.new(0, padY), PaddingBottom = UDim.new(0, padY), PaddingLeft = UDim.new(0, padX), PaddingRight = UDim.new(0, padX) }, body)
	list(body, Enum.FillDirection.Vertical, 5)
	return outer, body
end

-- icon slot: dark square with a 2px border; Gem = the placeholder diamond (tinted by the card), Image = the real icon (hidden until set)
local function icon(parent, size)
	local f = new("Frame", { Name = "Icon", Size = UDim2.fromOffset(size, size), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.6, BorderSizePixel = 0 }, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, f)
	new("UIStroke", { Thickness = 2, Color = hex("#555555"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	local g = size * 0.38
	new("Frame", { Name = "Gem", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(g, g), Rotation = 45, BackgroundColor3 = hex("#FFFFFF"), BorderSizePixel = 0 }, f)
	new("ImageLabel", { Name = "Image", Visible = false, BackgroundTransparency = 1, Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), ScaleType = Enum.ScaleType.Fit, Image = "" }, f)
	return f
end

local function timer(parent, height)
	local t = new("Frame", { Name = "Timer", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, height) }, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 1) }, t)
	new("Frame", { Name = "Fill", BackgroundColor3 = hex("#FFFFFF"), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, t)
	return t
end

local function row(parent, name, gap, order)
	local r = new("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order }, parent)
	list(r, Enum.FillDirection.Horizontal, gap, { VerticalAlignment = Enum.VerticalAlignment.Center })
	return r
end

local gui = new("ScreenGui", { Name = "FIANotifications", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, StarterGui)

local stack = new("Frame", { Name = "Stack", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(440, 0), AutomaticSize = Enum.AutomaticSize.Y }, gui)
list(stack, Enum.FillDirection.Vertical, 6, { VerticalAlignment = Enum.VerticalAlignment.Bottom })
new("UIScale", { Name = "Scale" }, stack)

local templates = new("Folder", { Name = "Templates" }, gui)

new("Frame", { Name = "Slot", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, templates)

-- ===================== LEVEL UP / COLLECTION =====================
local function tierCard(name, width)
	local outer, body = card(templates, name, width, 14, 10)
	new("Frame", { Name = "Rule", BackgroundColor3 = hex("#FFFFFF"), BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 3), LayoutOrder = 1 }, body)
	local header = row(body, "Header", 12, 2)
	local ic = icon(header, 64)
	ic.LayoutOrder = 1
	local text = new("Frame", { Name = "Text", BackgroundTransparency = 1, Size = UDim2.new(1, -76, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, header)
	list(text, Enum.FillDirection.Vertical, 2)
	label(text, "Title", "SKILL LEVEL UP", "#FFD700", 16, { FontFace = FONT, LayoutOrder = 1 })
	label(text, "Heading", "Combat V \u{2192} VI", "#FFFFFF", 26, { LayoutOrder = 2 })
	new("Frame", { Name = "Gap", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 2), LayoutOrder = 3 }, body)
	label(body, "RewardsTitle", "REWARDS", "#55FF55", 14, { FontFace = FONT, LayoutOrder = 4 })
	local lines = new("Frame", { Name = "Lines", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 }, body)
	list(lines, Enum.FillDirection.Vertical, 2)
	label(body, "Flavor", "", "#AAAAAA", 15, { FontFace = FLAVOR_FONT, LayoutOrder = 6 })
	local t = timer(body, 4)
	t.LayoutOrder = 7
	return outer
end
tierCard("CardLevelUp", 440)
tierCard("CardCollection", 440)

label(templates, "RewardLine", "", "#FFFFFF", 20, {})

-- ===================== PICKUP =====================
do
	local outer, body = card(templates, "CardPickup", 340, 12, 8)
	local r = row(body, "Row", 10, 1)
	icon(r, 36).LayoutOrder = 1
	label(r, "Label", "", "#FFFFFF", 22, { Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY, TextWrapped = false, TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 2 })
	label(r, "Count", "", "#FFAA00", 18, { FontFace = FONT, Size = UDim2.new(0, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.XY, TextWrapped = false, TextYAlignment = Enum.TextYAlignment.Center, Visible = false, LayoutOrder = 3 })
	timer(body, 3).LayoutOrder = 2
end

-- ===================== SYSTEM =====================
do
	local outer, body = card(templates, "CardSystem", 400, 12, 9)
	local r = row(body, "Row", 10, 1)
	icon(r, 34).LayoutOrder = 1
	local col = new("Frame", { Name = "Text", BackgroundTransparency = 1, Size = UDim2.new(1, -44, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 }, r)
	list(col, Enum.FillDirection.Vertical, 1)
	label(col, "Main", "", "#FFFF55", 22, { LayoutOrder = 1 })
	label(col, "Sub", "", "#AAAAAA", 16, { LayoutOrder = 2 })
	timer(body, 3).LayoutOrder = 2
end

return "built FIANotifications (Stack + Templates: Slot, CardLevelUp, CardCollection, CardPickup, CardSystem, RewardLine)"
