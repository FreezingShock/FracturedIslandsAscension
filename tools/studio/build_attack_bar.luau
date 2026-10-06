-- ReplicatedStorage.GUI.AttackBar: the swing-timing charge bar under the crosshair, cloned into PlayerGui by AttackBarController.
-- ScreenGui > Frame (the dark bar) > Fill (the script sets Fill's width and colour). Restyle freely, keep these names.
-- Edit datamodel. Refuses to overwrite unless FORCE.
local FORCE = false
local RS = game:GetService("ReplicatedStorage")
local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
if gui:FindFirstChild("AttackBar") then
	if not FORCE then
		return "AttackBar exists (set FORCE = true to rebuild)"
	end
	gui.AttackBar:Destroy()
end

local screen = Instance.new("ScreenGui")
screen.Name = "AttackBar"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 5
screen.Enabled = false

local frame = Instance.new("Frame")
frame.Name = "Frame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 34) -- just under the crosshair
frame.Size = UDim2.fromOffset(120, 8)
frame.BackgroundColor3 = Color3.fromHex("#1B1B1B")
frame.BorderSizePixel = 0
frame.Parent = screen
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromHex("#000000")
stroke.Thickness = 2
stroke.Parent = frame

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = Color3.fromHex("#FFFF55")
fill.BorderSizePixel = 0
fill.Parent = frame

screen.Parent = gui
return "built GUI.AttackBar"
