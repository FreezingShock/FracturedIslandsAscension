-- build_intro_screen.luau
-- Builds ReplicatedFirst.IntroScreen: the loading screen with the tour overlay, title, caption (click it for the next
-- scene), progress bar, Play, menu bar, menu panel, and the templates the menu pages clone rows from.
-- Colours are Minecraft colour codes (CLAUDE.md): every button is a bright code colour with its darker shade underneath,
-- white text with a black drop shadow, and the panels are opaque enough to read over the cutscene.
-- IntroLoader clones it into PlayerGui; IntroController binds by NAME, so restyle freely but do not rename:
--   IntroScreen (ScreenGui)
--     SkipSurface (Frame, see-through, Active)  press and hold on the empty screen to jump to the next scene
--     Fade (Frame, black)                        transitions between scenes and the fade into the game
--     LetterTop, LetterBottom (Frame, black)     cinematic bars for the tour
--     Vignette (Frame, gradient)                 soft dark edges
--     Overlay (CanvasGroup)                      everything the player reads or clicks; fades out on Play
--       Title (Frame) > Main (TextLabel), Sub (TextLabel)
--       Caption (Frame) > Name, Index (TextLabel), Hit (TextButton, the whole plate: click = next scene)
--       Tip (TextLabel)                          rotating tips
--       StatusLabel (TextLabel)                  "LOADING 42%" / "READY"
--       ProgressBar (Frame) > Fill (Frame) > Shimmer (UIGradient)
--       PlayButton (TextButton) > Scale (UIScale)  locked (Active off) until the preload reaches 100%
--       MenuBar (Frame) > (UIListLayout)           menu buttons are cloned in from Templates
--       MenuPanel (CanvasGroup, hidden) > Title, Divider, Content (ScrollingFrame), CloseButton
--       SkipRing (Frame) > Fill                    the hold-to-skip progress
--     Templates (Folder): never shown, cloned from
--       MenuButton (TextButton) > Scale (UIScale), Accent (Frame, gold bar when its menu is open)
--       Heading, Row (Frame) > Inner (Frame) > Text (TextLabel)
--       Option (Frame) > Inner (Frame) > Label (TextLabel), Value (TextButton)
-- Look and placeholder text only; menus, timings and shot paths live in Modules/Config/LoadingConfig.
-- Run on the Edit datamodel with the Studio MCP (stop Play first). Rebuilds when FORCE = true (replaces the old screen).
local FORCE = true

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local existing = ReplicatedFirst:FindFirstChild("IntroScreen")
if existing then
	if not FORCE then
		return "IntroScreen already exists (set FORCE = true to rebuild)"
	end
	existing:Destroy()
end

-- Minecraft colour codes: bright colour on top, its shade below
local GOLD, GOLD_DARK = Color3.fromHex("#FFAA00"), Color3.fromHex("#AA5500") -- &6
local YELLOW = Color3.fromHex("#FFFF55") -- &e
local GREEN, GREEN_DARK = Color3.fromHex("#55FF55"), Color3.fromHex("#00AA00") -- &a / &2
local AQUA, AQUA_DARK = Color3.fromHex("#55FFFF"), Color3.fromHex("#00AAAA") -- &b / &3
local PURPLE = Color3.fromHex("#FF55FF") -- &d
local RED, RED_DARK = Color3.fromHex("#FF5555"), Color3.fromHex("#AA0000") -- &c / &4
local GRAY, GRAY_DARK = Color3.fromHex("#AAAAAA"), Color3.fromHex("#555555") -- &7 / &8
local WHITE = Color3.fromHex("#FFFFFF") -- &f
local BLACK = Color3.new(0, 0, 0)
local PANEL_TOP, PANEL_BOTTOM = Color3.fromHex("#241A3C"), Color3.fromHex("#140D26")

local HEAD_FONT = Font.new("rbxassetid://12187371840", Enum.FontWeight.Regular, Enum.FontStyle.Normal) -- Silkscreen
local BODY_FONT = Font.fromEnum(Enum.Font.GothamMedium)
local SERIF_FONT = Font.fromEnum(Enum.Font.Merriweather)

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for key, value in pairs(props) do
		(inst :: any)[key] = value
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	return new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	}, parent)
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	return new("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function text(name: string, props: { [string]: any }, parent: Instance): TextLabel
	local base = {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = BODY_FONT,
		TextColor3 = WHITE,
		TextScaled = true,
		TextWrapped = true,
		ZIndex = 4,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	return new("TextLabel", base, parent)
end

-- a Minecraft-style button: bright code colour on top, its shade below, white text with a black drop shadow
local function button(name: string, props: { [string]: any }, parent: Instance, top: Color3, bottom: Color3): TextButton
	local base = {
		Name = name,
		BackgroundColor3 = top,
		FontFace = HEAD_FONT,
		TextColor3 = WHITE,
		TextScaled = true,
		TextStrokeTransparency = 0,
		TextStrokeColor3 = BLACK,
		AutoButtonColor = false,
		ZIndex = 4,
	}
	for key, value in pairs(props) do
		base[key] = value
	end
	local btn = new("TextButton", base, parent)
	gradient(btn, top, bottom)
	stroke(btn, BLACK, 3)
	new("UIScale", { Name = "Scale" }, btn)
	return btn
end

-- ===================== SCREEN =====================
local screen = new("ScreenGui", {
	Name = "IntroScreen",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 1000,
}, ReplicatedFirst)

new("Frame", {
	Name = "SkipSurface",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Active = true,
	ZIndex = 1,
}, screen)

new("Frame", {
	Name = "Fade",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	ZIndex = 2,
}, screen)

local vignette = new("Frame", {
	Name = "Vignette",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	ZIndex = 3,
}, screen)
new("UIGradient", {
	Color = ColorSequence.new(BLACK, BLACK),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.28, 1),
		NumberSequenceKeypoint.new(0.72, 1),
		NumberSequenceKeypoint.new(1, 0.25),
	}),
	Rotation = 90,
}, vignette)

new("Frame", {
	Name = "LetterTop",
	Position = UDim2.new(0, 0, -0.12, 0),
	Size = UDim2.new(1, 0, 0.12, 0),
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	ZIndex = 5,
}, screen)
new("Frame", {
	Name = "LetterBottom",
	Position = UDim2.new(0, 0, 1.12, 0),
	Size = UDim2.new(1, 0, 0.12, 0),
	BackgroundColor3 = BLACK,
	BorderSizePixel = 0,
	ZIndex = 5,
}, screen)

local overlay = new("CanvasGroup", {
	Name = "Overlay",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	GroupTransparency = 0,
	ZIndex = 6,
}, screen)

-- title: gold-to-yellow gradient with a black pixel shadow; the aqua subtitle fades in after
local title = new("Frame", {
	Name = "Title",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0.05),
	Size = UDim2.fromScale(0.7, 0.16),
	BackgroundTransparency = 1,
	ZIndex = 6,
}, overlay)
local main = text("Main", {
	Size = UDim2.fromScale(1, 0.62),
	Text = "FRACTURED ISLANDS",
	FontFace = HEAD_FONT,
	TextColor3 = WHITE,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = BLACK,
}, title)
gradient(main, GOLD, YELLOW, 0)
text("Sub", {
	Position = UDim2.fromScale(0, 0.64),
	Size = UDim2.fromScale(1, 0.34),
	Text = "ASCENSION",
	FontFace = HEAD_FONT,
	TextColor3 = AQUA,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = BLACK,
	TextTransparency = 1,
}, title)

-- caption: the whole plate is the "next scene" button (Hit sits on top, transparent)
local caption = new("Frame", {
	Name = "Caption",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 36, 1, -150),
	Size = UDim2.new(0, 420, 0, 84),
	BackgroundColor3 = PANEL_BOTTOM,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	ZIndex = 6,
}, overlay)
gradient(caption, PANEL_TOP, PANEL_BOTTOM)
stroke(caption, PURPLE, 3)
new("UIScale", { Name = "Scale" }, caption) -- the scene box shrinks in and springs out when clicked
text("Name", {
	Position = UDim2.new(0, 16, 0, 12),
	Size = UDim2.new(1, -32, 0, 40),
	Text = "",
	FontFace = HEAD_FONT,
	TextColor3 = PURPLE,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = BLACK,
}, caption)
text("Index", {
	Position = UDim2.new(0, 16, 0, 56),
	Size = UDim2.new(1, -32, 0, 18),
	Text = "",
	FontFace = BODY_FONT,
	TextColor3 = GRAY,
	TextXAlignment = Enum.TextXAlignment.Left,
}, caption)
new("TextButton", {
	Name = "Hit",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	ZIndex = 9,
}, caption)

text("Tip", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -28),
	Size = UDim2.new(0.6, 0, 0, 22),
	Text = "",
	FontFace = SERIF_FONT,
	TextColor3 = YELLOW,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = BLACK,
}, overlay)

text("StatusLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -76),
	Size = UDim2.new(0.34, 0, 0, 22),
	Text = "LOADING  0%",
	FontFace = HEAD_FONT,
	TextColor3 = AQUA,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = BLACK,
}, overlay)
local bar = new("Frame", {
	Name = "ProgressBar",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -52),
	Size = UDim2.new(0.34, 0, 0, 16),
	BackgroundColor3 = GRAY_DARK,
	BorderSizePixel = 0,
	ZIndex = 6,
}, overlay)
stroke(bar, BLACK, 2)
local fill = new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = GREEN,
	BorderSizePixel = 0,
	ZIndex = 7,
}, bar)
gradient(fill, GREEN, GREEN_DARK)
new("UIGradient", {
	Name = "Shimmer",
	Color = ColorSequence.new(WHITE, WHITE),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	}),
	Rotation = 0,
}, fill)

-- Play: emerald (&a) when ready, gray (&7) while loading
button("PlayButton", {
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -40, 1, -40),
	Size = UDim2.new(0, 260, 0, 64),
	Text = "LOADING...",
	Active = false,
	ZIndex = 6,
}, overlay, GRAY, GRAY_DARK)

local menuBar = new("Frame", {
	Name = "MenuBar",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 36, 0.5, 0),
	Size = UDim2.new(0, 230, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	ZIndex = 6,
}, overlay)
new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, menuBar)

local panel = new("CanvasGroup", {
	Name = "MenuPanel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -36, 0.5, 0),
	Size = UDim2.new(0, 440, 0, 430),
	BackgroundColor3 = PANEL_BOTTOM,
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	GroupTransparency = 0,
	Visible = false,
	ZIndex = 6,
}, overlay)
gradient(panel, PANEL_TOP, PANEL_BOTTOM)
stroke(panel, GOLD, 3)
new("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PANEL_BOTTOM, BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 1 }, panel) -- solid behind the gradient (lowest layer)
text("Title", {
	Position = UDim2.new(0, 18, 0, 14),
	Size = UDim2.new(1, -80, 0, 38),
	Text = "Menu",
	FontFace = HEAD_FONT,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = BLACK,
}, panel)
new("Frame", {
	Name = "Divider",
	Position = UDim2.new(0, 18, 0, 60),
	Size = UDim2.new(1, -36, 0, 2),
	BackgroundColor3 = GOLD,
	BorderSizePixel = 0,
	ZIndex = 7,
}, panel)
local content = new("ScrollingFrame", {
	Name = "Content",
	Position = UDim2.new(0, 18, 0, 74),
	Size = UDim2.new(1, -36, 1, -92),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 4,
	ScrollBarImageColor3 = GOLD,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 7,
}, panel)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
new("UIPadding", { PaddingRight = UDim.new(0, 8) }, content)
button("CloseButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 10),
	Size = UDim2.new(0, 40, 0, 40),
	Text = "X",
	ZIndex = 8,
}, panel, RED, RED_DARK)

local ring = new("Frame", {
	Name = "SkipRing",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 24),
	Size = UDim2.new(0, 260, 0, 14),
	BackgroundColor3 = GRAY_DARK,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 7,
}, overlay)
stroke(ring, BLACK, 2)
new("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = GOLD,
	BorderSizePixel = 0,
	ZIndex = 8,
}, ring)

-- ===================== TEMPLATES =====================
local templates = new("Folder", { Name = "Templates" }, screen)

-- menu button: aqua by default (&b), gold when its panel is open (&6); the Accent bar marks the open one
local menuButton = button("MenuButton", {
	Size = UDim2.new(1, 0, 0, 44),
	Text = "Menu",
}, templates, AQUA, AQUA_DARK)
new("Frame", {
	Name = "Accent",
	Size = UDim2.new(0, 6, 1, 0),
	BackgroundColor3 = YELLOW,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 5,
}, menuButton)

local function rowTemplate(name: string, height: number): Frame
	local rowFrame = new("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, templates)
	new("Frame", {
		Name = "Inner",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 7,
	}, rowFrame)
	return rowFrame
end

local heading = rowTemplate("Heading", 34)
text("Text", {
	Size = UDim2.fromScale(1, 1),
	Text = "Heading",
	FontFace = HEAD_FONT,
	TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextScaled = true,
	TextStrokeTransparency = 0,
	TextStrokeColor3 = BLACK,
}, heading.Inner)

local rowLine = rowTemplate("Row", 30)
text("Text", {
	Size = UDim2.fromScale(1, 1),
	Text = "Line",
	TextStrokeTransparency = 0.2,
	TextStrokeColor3 = BLACK,
	FontFace = BODY_FONT,
	TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextScaled = true,
}, rowLine.Inner)

local option = rowTemplate("Option", 40)
text("Label", {
	Size = UDim2.new(0.62, 0, 1, 0),
	Text = "Option",
	FontFace = BODY_FONT,
	TextColor3 = AQUA,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextScaled = true,
}, option.Inner)
button("Value", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.new(0, 120, 0, 30),
	Text = "ON",
}, option.Inner, GREEN, GREEN_DARK)

return "built ReplicatedFirst.IntroScreen"
