-- ReplicatedStorage.GUI.AbilitySlot (template) + StarterGui.AbilityMenu.Slots (holder), used by AbilityController.
-- Slot children the script fills: Key, Name, Cost, Timer (TextLabels) and Cooldown (Frame bar that shrinks left).
-- Edit datamodel. Refuses to overwrite either piece unless FORCE.
local FORCE = false
local RS = game:GetService("ReplicatedStorage")
local SG = game:GetService("StarterGui")
local FONT = Font.new("rbxassetid://12187371840")
local gui = RS:FindFirstChild("GUI") or Instance.new("Folder")
gui.Name = "GUI"
gui.Parent = RS

local made = {}
if not gui:FindFirstChild("AbilitySlot") or FORCE then
	if gui:FindFirstChild("AbilitySlot") then
		gui.AbilitySlot:Destroy()
	end
	local slot = Instance.new("CanvasGroup")
	slot.Name = "AbilitySlot"
	slot.Size = UDim2.fromOffset(250, 44)
	slot.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	slot.BackgroundTransparency = 0.35
	slot.BorderSizePixel = 0
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 6)
	local st = Instance.new("UIStroke", slot)
	st.Color = Color3.fromRGB(85, 85, 85)
	st.Thickness = 2

	local cd = Instance.new("Frame")
	cd.Name = "Cooldown"
	cd.BackgroundColor3 = Color3.new(0, 0, 0)
	cd.BackgroundTransparency = 0.45
	cd.BorderSizePixel = 0
	cd.Size = UDim2.fromScale(0, 1)
	cd.ZIndex = 1
	cd.Parent = slot

	local function label(name, text, size, pos, anchor, align, color)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Text = text
		l.FontFace = FONT
		l.TextSize = size
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(0, 0, 1, 0)
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Position = pos
		l.AnchorPoint = anchor
		l.TextXAlignment = align
		l.TextColor3 = color
		l.ZIndex = 2
		local s = Instance.new("UIStroke", l)
		s.Color = Color3.new(0, 0, 0)
		s.Thickness = 1.5
		l.Parent = slot
	end
	label("Key", "Q", 20, UDim2.new(0, 12, 0.5, 0), Vector2.new(0, 0.5), Enum.TextXAlignment.Left, Color3.fromRGB(255, 255, 85))
	label("Name", "Ability", 16, UDim2.new(0, 56, 0.5, -9), Vector2.new(0, 0.5), Enum.TextXAlignment.Left, Color3.fromRGB(255, 255, 255))
	label("Cost", "0 Mana", 14, UDim2.new(0, 56, 0.5, 10), Vector2.new(0, 0.5), Enum.TextXAlignment.Left, Color3.fromRGB(85, 255, 255))
	label("Timer", "", 18, UDim2.new(1, -12, 0.5, 0), Vector2.new(1, 0.5), Enum.TextXAlignment.Right, Color3.new(1, 1, 1))
	slot.Parent = gui
	table.insert(made, "GUI.AbilitySlot")
end

if not SG:FindFirstChild("AbilityMenu") or FORCE then
	if SG:FindFirstChild("AbilityMenu") then
		SG.AbilityMenu:Destroy()
	end
	local menu = Instance.new("ScreenGui")
	menu.Name = "AbilityMenu"
	menu.ResetOnSpawn = false
	local holder = Instance.new("Frame")
	holder.Name = "Slots"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(1, 0.5)
	holder.Position = UDim2.new(1, -16, 0.5, 0)
	holder.Size = UDim2.fromOffset(250, 200)
	local layout = Instance.new("UIListLayout", holder)
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	holder.Parent = menu
	menu.Parent = SG
	table.insert(made, "StarterGui.AbilityMenu")
end
return #made > 0 and ("built " .. table.concat(made, ", ")) or "all exist (set FORCE = true to rebuild)"
