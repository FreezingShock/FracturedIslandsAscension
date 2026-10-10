-- build_chat_gui.luau
-- Builds ReplicatedStorage.GUI.FIAChatGui, the template ChatController clones into PlayerGui (tooltip look: black glass body, 4px dark + 2px light border).
-- ChatController binds by NAME, so restyle freely but do not rename:
--   FIAChatGui (ScreenGui)
--     Panel (Frame = the 4px outer border; bottom-left, UIScale "Scale")
--       Body (Frame, black glass + 2px border)
--         FadeGroup (CanvasGroup, UIGradient "FadeGradient")  the log's top fades: the gradient runs 1 -> 0 over the top 30%
--           LogFrame (ScrollingFrame, UIListLayout)      messages are cloned into it from Templates
--         InputBar (Frame) > InputBox (TextBox), CharCount (TextLabel, Silkscreen), SendBtn (ImageButton)
--         NewMsgBtn (TextButton)                         "New messages" pill, shown while scrolled up
--     Templates (Folder)
--       Entry (Frame, UIListLayout)   one message; Row (Frame, horizontal UIListLayout) holds a player line's badge + name
--       Line (TextLabel RichText + UIStroke + UIFlexItem "Flex") and Spacer (Frame) are cloned into Entry or Row
--   The level badge is NOT in this template: ChatController clones it from GUI.EnemyNameplate.LevelBadge at runtime.
-- All sizes/positions/transparencies at runtime come from Modules/Config/ChatConfig.Visual. FADE_TOP must match FadeTopFraction there.
-- Run on the Edit datamodel with the Studio MCP (stop Play first). Skips when the template exists unless FORCE = true.
local FORCE = false

local GUI = game:GetService("ReplicatedStorage"):FindFirstChild("GUI")
assert(GUI, "ReplicatedStorage.GUI is missing")
if GUI:FindFirstChild("FIAChatGui") then
	if not FORCE then
		return "FIAChatGui template already exists (set FORCE = true to rebuild)"
	end
	GUI.FIAChatGui:Destroy()
end

local FONT = Font.new("rbxassetid://12187371840", Enum.FontWeight.Regular, Enum.FontStyle.Normal) -- Silkscreen
local TEXT_FONT = Font.new("rbxassetid://12187370747", Enum.FontWeight.Bold) -- readable text until Noto Sans is uploaded

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

local function textStroke(parent)
	new("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, parent)
end

local gui = new("ScreenGui", { Name = "FIAChatGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, GUI)

local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -16),
	Size = UDim2.fromOffset(480, 450),
	BackgroundColor3 = hex("#4B4B4B"),
	BackgroundTransparency = 0.8,
	BorderSizePixel = 0,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, panel)
new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, panel)
new("UIScale", { Name = "Scale" }, panel)

local body = new("Frame", { Name = "Body", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.75, BorderSizePixel = 0 }, panel)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, body)
new("UIStroke", { Thickness = 2, Color = hex("#AAAAAA"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)

-- the log sits in a CanvasGroup so its UIGradient fades the top of the log (children included): 1 at the top edge, solid by FADE_TOP
local FADE_TOP = 0.3 -- = ChatConfig.Visual.FadeTopFraction
local fade = new("CanvasGroup", {
	Name = "FadeGroup",
	Size = UDim2.new(1, 0, 1, -54),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	GroupTransparency = 0,
}, body)
new("UIGradient", {
	Name = "FadeGradient",
	Rotation = 90, -- first key point at the top
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(FADE_TOP, 0),
		NumberSequenceKeypoint.new(1, 0),
	}),
}, fade)

local log = new("ScrollingFrame", {
	Name = "LogFrame",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	ScrollBarImageColor3 = hex("#AAAAAA"),
	ScrollBarImageTransparency = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Right,
}, fade)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, log)
new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 4) }, log)

local bar = new("Frame", {
	Name = "InputBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -8),
	Size = UDim2.new(1, -16, 0, 38),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.5,
	BorderSizePixel = 0,
}, body)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, bar)
new("UIStroke", { Thickness = 2, Color = hex("#555555"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bar)

local box = new("TextBox", {
	Name = "InputBox",
	Position = UDim2.fromOffset(10, 0),
	Size = UDim2.new(1, -92, 1, 0),
	BackgroundTransparency = 1,
	FontFace = TEXT_FONT,
	TextSize = 20,
	TextColor3 = Color3.new(1, 1, 1),
	PlaceholderText = "Press / or Enter to chat",
	PlaceholderColor3 = hex("#AAAAAA"),
	Text = "",
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	MultiLine = false,
}, bar)
textStroke(box)

new("TextLabel", {
	Name = "CharCount",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -40, 0.5, 0),
	Size = UDim2.fromOffset(44, 16),
	BackgroundTransparency = 1,
	FontFace = FONT,
	TextSize = 12,
	TextColor3 = hex("#AAAAAA"),
	TextXAlignment = Enum.TextXAlignment.Right,
	Text = "",
	Visible = false,
}, bar)

new("ImageButton", {
	Name = "SendBtn",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(25, 25),
	BackgroundTransparency = 1,
	Image = "rbxassetid://136205886275971",
	ImageColor3 = hex("#AAAAAA"),
}, bar)

local pill = new("TextButton", {
	Name = "NewMsgBtn",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -54),
	Size = UDim2.fromOffset(170, 24),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	FontFace = TEXT_FONT,
	TextSize = 15,
	TextColor3 = hex("#55FFFF"),
	Text = "\u{2193} New messages",
	Visible = false,
	ZIndex = 6,
}, body)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, pill)
new("UIStroke", { Thickness = 2, Color = hex("#AAAAAA"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, pill)
textStroke(pill)

local templates = new("Folder", { Name = "Templates" }, gui)
local entry = new("Frame", { Name = "Entry", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0 }, templates)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, entry)
local row = new("Frame", { Name = "Row", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0 }, templates)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Top, Padding = UDim.new(0, 6) }, row)
local line = new("TextLabel", {
	Name = "Line",
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	FontFace = TEXT_FONT,
	TextSize = 20,
	TextColor3 = hex("#DCDCDC"),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	RichText = true,
	Text = "",
}, templates)
textStroke(line)
new("UIFlexItem", { Name = "Flex", FlexMode = Enum.UIFlexMode.Fill }, line) -- a row's name fills the width left of the badge
new("Frame", { Name = "Spacer", Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, BorderSizePixel = 0 }, templates)

return "built ReplicatedStorage.GUI.FIAChatGui (Panel > Body > FadeGroup > LogFrame, InputBar, NewMsgBtn; Templates: Entry, Row, Line, Spacer)"
