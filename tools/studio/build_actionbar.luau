-- build_actionbar.luau
-- Builds StarterGui.FIAHUD.Root.ActionBar: the centered line above the held-item name (ActionBarClient binds by NAME):
--   ActionBar (CanvasGroup, transparent until a message shows, anchored bottom-centre at HudTheme.actionBar.pos)
--     Label (TextLabel, RichText, pixel font, the main line; Pop = UIScale for the number pop, Stroke = outline)
--     Sub   (TextLabel, RichText, the CONGRATULATIONS line above Label; Stroke = outline, flashed on level-up)
-- Sizes / position come from ReplicatedStorage.Modules.Config.HudTheme.actionBar. Run on the Edit datamodel with the Studio MCP
-- (stop Play first). Skips when it exists unless FORCE = true.
local FORCE = false

local RS = game.ReplicatedStorage
local T = require(RS.Modules.Config.HudTheme:Clone())
local A = T.actionBar
local root = game.StarterGui:FindFirstChild("FIAHUD") and game.StarterGui.FIAHUD:FindFirstChild("Root")
if not root then
	return "FIAHUD.Root not found (build the HUD first)"
end
if root:FindFirstChild("ActionBar") then
	if not FORCE then
		return "ActionBar already exists (set FORCE = true to rebuild)"
	end
	root.ActionBar:Destroy()
end

local FONT = Font.new(T.font, Enum.FontWeight.Regular, Enum.FontStyle.Normal)

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local group = new("CanvasGroup", {
	Name = "ActionBar",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.fromOffset(A.pos.X, A.pos.Y),
	Size = UDim2.fromOffset(A.size.X, A.size.Y),
	GroupTransparency = 1,
	ZIndex = 15,
}, root)
new("UIScale", { Name = "Intro" }, group) -- the entrance scale (ActionBarClient)

local function line(name, size, height, anchorY)
	local l = new("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, anchorY),
		Position = UDim2.new(0.5, 0, anchorY, 0),
		Size = UDim2.new(1, 0, 0, height),
		FontFace = FONT,
		RichText = true,
		Text = "",
		TextSize = size,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false,
	}, group)
	new("UIStroke", { Name = "Stroke", Thickness = A.stroke.thickness, Color = A.stroke.color, LineJoinMode = Enum.LineJoinMode.Miter, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, l)
	return l
end

local label = line("Label", A.labelSize, A.labelHeight, 1)
new("UIScale", { Name = "Pop" }, label)
local sub = line("Sub", A.subSize, A.subHeight, 0)
new("UIScale", { Name = "Pop" }, sub) -- the pop of each exclamation step (ActionBarClient)
sub.Position = UDim2.new(0.5, 0, 1, -A.labelHeight)
sub.AnchorPoint = Vector2.new(0.5, 1)

return "built FIAHUD.Root.ActionBar"
