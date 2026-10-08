-- build_scoreboard.luau
-- Builds StarterGui.FIAScoreboard from the Figma file "FIA Scoreboard" (tooltip look: gradient body, 4px dark + 2px light border).
-- Scripts (ScoreboardController) bind by NAME, so restyle freely but do not rename:
--   FIAScoreboard (ScreenGui, ResetOnSpawn off)
--     Panel (Frame, the right-hand column; anchored top-right by ScoreboardController, UIScale scales it with the screen)
--       Board (Frame, the 4px outer border)      > Lines (Frame, the gradient body + 2px inner border, UIListLayout)
--       Template (Frame, hidden)  one scoreboard line: Text (TextLabel, RichText)    -- cloned per line, never edit at runtime
-- Run on the Edit datamodel with the Studio MCP (stop Play first). Skips when FIAScoreboard exists unless FORCE = true.
local FORCE = false

local StarterGui = game:GetService("StarterGui")
if StarterGui:FindFirstChild("FIAScoreboard") then
	if not FORCE then
		return "FIAScoreboard already exists (set FORCE = true to rebuild)"
	end
	StarterGui.FIAScoreboard:Destroy()
end

local FONT = Font.new("rbxassetid://12187371840", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
-- scoreboard lines: an easy-to-read base font (the tooltip body font; Noto Sans is not a built-in Roblox family, so upload it and put its
-- asset id here) with Silkscreen values via rich text <font family=...>
local TEXT_FONT = Font.new("rbxassetid://12187370747", Enum.FontWeight.Bold)
local W = 300 -- panel width at the 1080p design size (outer border included); ScoreboardConfig.layout.width overrides it at runtime

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
		FontFace = FONT,
		Text = text,
		TextColor3 = hex(color),
		TextSize = size or 14,
		RichText = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
	}, parent)
	new("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.45, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	for k, v in pairs(extra or {}) do
		l[k] = v
	end
	return l
end

-- the tooltip shell: `outer` is the 4px dark border, `body` the gradient + 2px light border with its own padding
local function shell(parent, outerName, outerClass, padX, padY, bodyTransparency)
	local outer = new(outerClass, {
		Name = outerName,
		BackgroundColor3 = hex("#4B4B4B"),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, outer)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, outer)
	local body = new("Frame", {
		Name = (outerName == "Board") and "Lines" or "Body",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = bodyTransparency or 0.22,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, outer)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, body)
	new("UIGradient", {
		Rotation = 45,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, hex("#323232")),
			ColorSequenceKeypoint.new(0.5, hex("#969696")),
			ColorSequenceKeypoint.new(1, hex("#323232")),
		}),
	}, body)
	new("UIStroke", { Thickness = 2, Color = hex("#AAAAAA"), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, body)
	new("UIPadding", {
		PaddingTop = UDim.new(0, padY), PaddingBottom = UDim.new(0, padY),
		PaddingLeft = UDim.new(0, padX), PaddingRight = UDim.new(0, padX),
	}, body)
	return outer, body
end

local gui = new("ScreenGui", { Name = "FIAScoreboard", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, StarterGui)

local panel = new("Frame", { Name = "Panel", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0.28, 0), Size = UDim2.fromOffset(W, 0), AutomaticSize = Enum.AutomaticSize.Y }, gui)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, panel)
new("UIScale", { Name = "Scale" }, panel)

-- Board > Lines
local board, lines = shell(panel, "Board", "Frame", 10, 6)
board.LayoutOrder = 1
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, lines)

-- the line template (hidden)
local tpl = new("Frame", { Name = "Template", Visible = false, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, panel)
label(tpl, "Text", "", "#FFFFFF", 24, { FontFace = TEXT_FONT, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true })

return "built StarterGui.FIAScoreboard"
