-- ReplicatedStorage.GUI.DamageNumber: the floating damage number cloned by DamageNumberController.
-- Label = the number (pixel font), UIStroke = its outline, CritBadge = Crit Increase stat icon shown behind crit numbers
-- (stat spritesheet rbxassetid://115852737004664, 170px cells, cell {3, 0}; darker blue, a little transparent).
-- Edit datamodel. Refuses to overwrite unless FORCE.
local FORCE = false
local RS = game:GetService("ReplicatedStorage")
local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
if gui:FindFirstChild("DamageNumber") then
	if not FORCE then
		return "DamageNumber exists (set FORCE = true to rebuild)"
	end
	gui.DamageNumber:Destroy()
end

local b = Instance.new("BillboardGui")
b.Name = "DamageNumber"
b.Size = UDim2.fromOffset(160, 48)
b.AlwaysOnTop = true
b.LightInfluence = 0
b.MaxDistance = 140
b.ResetOnSpawn = false
b.ZIndexBehavior = Enum.ZIndexBehavior.Global

local label = Instance.new("TextLabel")
label.Name = "Label"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = "123"
label.TextSize = 30
label.TextColor3 = Color3.new(1, 1, 1)
label.FontFace = Font.new("rbxassetid://12187371840")
label.ZIndex = 1
label.Parent = b

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromHex("#555555")
stroke.Thickness = 2
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
stroke.Parent = label

local badge = Instance.new("ImageLabel")
badge.Name = "CritBadge"
badge.BackgroundTransparency = 1
badge.AnchorPoint = Vector2.new(0.5, 0.5)
badge.Position = UDim2.fromScale(0.5, 0.5)
badge.Size = UDim2.fromOffset(81, 81) -- 48 x 1.7
badge.Image = "rbxassetid://115852737004664"
badge.ImageRectOffset = Vector2.new(3 * 170, 0)
badge.ImageRectSize = Vector2.new(170, 170)
badge.ImageColor3 = Color3.fromHex("#0000AA")
badge.ImageTransparency = 0.45
badge.ZIndex = 0
badge.Visible = false -- the controller shows it for crits only
badge.Parent = b

b.Parent = gui
return "built GUI.DamageNumber"
