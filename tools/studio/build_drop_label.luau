-- ReplicatedStorage.GUI.DropLabel: the name floating over a dropped item, cloned onto each drop part by LootService.
-- BillboardGui > Label (the script sets its text and rarity colour). Restyle freely, keep these names.
-- Edit datamodel. Refuses to overwrite unless FORCE.
local FORCE = false
local RS = game:GetService("ReplicatedStorage")
local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS
if gui:FindFirstChild("DropLabel") then
	if not FORCE then
		return "DropLabel exists (set FORCE = true to rebuild)"
	end
	gui.DropLabel:Destroy()
end

local b = Instance.new("BillboardGui")
b.Name = "DropLabel"
b.Size = UDim2.fromOffset(180, 26)
b.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
b.AlwaysOnTop = false
b.LightInfluence = 0
b.MaxDistance = 45
b.ResetOnSpawn = false

local label = Instance.new("TextLabel")
label.Name = "Label"
label.Size = UDim2.fromScale(1, 1)
label.BackgroundTransparency = 1
label.Text = "Item"
label.TextSize = 18
label.TextColor3 = Color3.new(1, 1, 1)
label.FontFace = Font.new("rbxassetid://12187371840")
label.Parent = b
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromHex("#000000")
stroke.Thickness = 1.5
stroke.Parent = label

b.Parent = gui
return "built GUI.DropLabel"
