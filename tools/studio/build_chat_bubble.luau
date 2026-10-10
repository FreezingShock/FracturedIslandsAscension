-- build_chat_bubble.luau
-- Builds the two chat-bubble templates beside the nameplate (ChatBubble clones them over a player's EnemyNameplate):
--   ReplicatedStorage.GUI.EnemyNameplate_BubbleStack   Frame: the column the bubbles stack in (UIListLayout, grows upward)
--   ReplicatedStorage.GUI.EnemyNameplate_Bubble        CanvasGroup (GroupTransparency fades it) > Tail (rotated square, under) + Pill (dark, stroked)
--                                                      > Text (Silkscreen, rich text, black stroke): the same look as the nameplate's LevelBadge
-- Restyle freely in Studio, keep the names: ChatBubble looks up Pill and Text by name. Numbers live in ChatConfig.Bubble.
-- Run on the Edit datamodel with the Studio MCP (stop Play first). Skips when the templates exist unless FORCE = true.
local FORCE = false

local GUI = game:GetService("ReplicatedStorage"):FindFirstChild("GUI")
assert(GUI, "ReplicatedStorage.GUI is missing")
if GUI:FindFirstChild("EnemyNameplate_BubbleStack") or GUI:FindFirstChild("EnemyNameplate_Bubble") then
	if not FORCE then
		return "bubble templates already exist (set FORCE = true to rebuild)"
	end
	for _, name in ipairs({ "EnemyNameplate_BubbleStack", "EnemyNameplate_Bubble" }) do
		if GUI:FindFirstChild(name) then
			GUI[name]:Destroy()
		end
	end
end

local SILK = Font.new("rbxassetid://12187371840") -- Silkscreen, the nameplate's font

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

local function stroke(parent, color, thickness, mode)
	return new("UIStroke", {
		Color = hex(color),
		Thickness = thickness,
		ApplyStrokeMode = mode or Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- the column: bubbles are its children, oldest at the top, newest at the bottom; the controller anchors it above the nameplate
local stack = new("Frame", {
	Name = "EnemyNameplate_BubbleStack",
	AnchorPoint = Vector2.new(0.5, 1),
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
}, GUI)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, stack)

-- one bubble: grows to fit its text, so the pill, the tail and the fade all move together
local bubble = new("CanvasGroup", {
	Name = "EnemyNameplate_Bubble",
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	GroupTransparency = 0,
}, GUI)

-- the tail: a small square turned 45 degrees, drawn under the pill so only its lower point shows
local tail = new("Frame", {
	Name = "Tail",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.fromOffset(10, 10),
	Rotation = 45,
	BackgroundColor3 = hex("#0E0E10"),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 1,
}, bubble)
stroke(tail, "#2A2A2D", 2)

local pill = new("Frame", {
	Name = "Pill",
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	BackgroundColor3 = hex("#0E0E10"),
	BackgroundTransparency = 0.1,
	BorderSizePixel = 0,
	ZIndex = 2,
}, bubble)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, pill)
stroke(pill, "#2A2A2D", 2)
new("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 5),
	PaddingBottom = UDim.new(0, 5),
}, pill)

local text = new("TextLabel", {
	Name = "Text",
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.fromOffset(0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	FontFace = SILK,
	TextSize = 16,
	TextColor3 = hex("#FFFFFF"),
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	TextWrapped = true,
	RichText = true,
	Text = "",
}, pill)
stroke(text, "#000000", 1.5, Enum.ApplyStrokeMode.Contextual)
new("UISizeConstraint", { MaxSize = Vector2.new(260, 1000000) }, text) -- the controller sets the real width from ChatConfig.Bubble.MaxWidth

return "built ReplicatedStorage.GUI.EnemyNameplate_BubbleStack and EnemyNameplate_Bubble (Pill > Text, Tail)"
