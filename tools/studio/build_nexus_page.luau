-- build_nexus_page.luau
-- Creates the GUI templates of the Aetheric Nexus Level page (NexusLevelPageModule looks them up BY NAME). Run through the Studio MCP
-- (execute_luau, Edit datamodel, Play stopped). The page is made ONLY of grid slots (a copy of SkyBlock's Levels menu):
--   ReplicatedStorage.GridTemplates.NexusLevelMenu      Folder: BackButton + CloseSlot (copied from CollectionsMenu3)
--   StarterGui.CentralizedAscensionMenu.TemporaryMenus
--     NexusSlot         copy of StatSlot (BG, Icon, UIGradient, UICorner) + a "LevelLabel" corner label (the level number on the panes);
--                       every slot of the page is a clone of it (tinted + given an icon by the module)
--   (the earlier NexusBadgeSlot / NexusInfoPanel / NexusSpacer templates of 3.78.0 are deleted: the page has no panels any more)
-- Restyle freely, keep the names and the Icon / BG / LevelLabel children. Idempotent: an existing template is left alone unless FORCE = true.
-- Designed in the Figma master file (page Menus & HUD, "NexusLevelMenu (SkyBlock Levels layout ...)").
local FORCE = false

local RS = game:GetService("ReplicatedStorage")
local TM = game:GetService("StarterGui"):WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
local GridTemplates = RS:WaitForChild("GridTemplates")
local made = {}

local function fresh(parent, name)
	local old = parent:FindFirstChild(name)
	if old and not FORCE then
		return nil
	end
	if old then
		old:Destroy()
	end
	return true
end

for _, name in ipairs({ "NexusBadgeSlot", "NexusInfoPanel", "NexusSpacer" }) do
	local old = TM:FindFirstChild(name)
	if old then
		old:Destroy()
		table.insert(made, "removed " .. name)
	end
end

if fresh(TM, "NexusSlot") then
	local slot = TM.StatSlot:Clone()
	slot.Name = "NexusSlot"
	slot.Visible = false
	-- the corner label (same look as the Collections level labels)
	local label = TM.CollectionLevelSlot.BG.LevelLabel:Clone()
	label.Name = "LevelLabel"
	label.AnchorPoint = Vector2.new(1, 1)
	label.Position = UDim2.new(1, -3, 1, -3)
	label.Size = UDim2.fromScale(0.6, 0.4)
	label.ZIndex = 3
	label.Text = ""
	label.TextXAlignment = Enum.TextXAlignment.Right
	label.Parent = slot
	slot.Parent = TM
	table.insert(made, "NexusSlot")
end

if fresh(GridTemplates, "NexusLevelMenu") then
	local folder = Instance.new("Folder")
	folder.Name = "NexusLevelMenu"
	local source = GridTemplates:WaitForChild("CollectionsMenu3")
	for _, name in ipairs({ "BackButton", "CloseSlot" }) do
		source[name]:Clone().Parent = folder
	end
	folder.Parent = GridTemplates
	table.insert(made, "NexusLevelMenu")
end

return #made == 0 and "nothing to do (all templates exist)" or ("done: " .. table.concat(made, ", "))
