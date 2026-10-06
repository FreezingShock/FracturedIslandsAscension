-- ReplicatedStorage.GUI.EnemyNameplate: the name + health bar cloned by EnemyNameplateController over every Enemy.
-- NameLabel = the name (pixel font), Bar = dark bar, Bar.Fill = health fraction (the script sets Fill's width).
-- Restyle freely, but keep these names. Edit datamodel. Refuses to overwrite unless FORCE.
local FORCE = false
local RS = game:GetService("ReplicatedStorage")
local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
if gui:FindFirstChild("EnemyNameplate") then
	if not FORCE then
		return "EnemyNameplate exists (set FORCE = true to rebuild)"
	end
	gui.EnemyNameplate:Destroy()
end

local b = Instance.new("BillboardGui")
b.Name = "EnemyNameplate"
b.Size = UDim2.fromOffset(150, 34)
b.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
b.AlwaysOnTop = false
b.LightInfluence = 0
b.MaxDistance = 70
b.ResetOnSpawn = false
b.ZIndexBehavior = Enum.ZIndexBehavior.Global

local name = Instance.new("TextLabel")
name.Name = "NameLabel"
name.Size = UDim2.new(1, 0, 0, 20)
name.BackgroundTransparency = 1
name.Text = "Enemy"
name.TextSize = 18
name.TextColor3 = Color3.fromHex("#FFFFFF")
name.FontFace = Font.new("rbxassetid://12187371840")
name.Parent = b
local nameStroke = Instance.new("UIStroke")
nameStroke.Color = Color3.fromHex("#555555")
nameStroke.Thickness = 1.5
nameStroke.Parent = name

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 0)
bar.Position = UDim2.new(0.5, 0, 0, 23)
bar.Size = UDim2.new(0.8, 0, 0, 8)
bar.BackgroundColor3 = Color3.fromHex("#1B1B1B")
bar.BorderSizePixel = 0
bar.Parent = b
local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromHex("#000000")
barStroke.Thickness = 1.5
barStroke.Parent = bar

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Color3.fromHex("#FF5555")
fill.BorderSizePixel = 0
fill.Parent = bar

b.Parent = gui
return "built GUI.EnemyNameplate"
