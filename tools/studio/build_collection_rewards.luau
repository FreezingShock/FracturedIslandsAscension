--[[
	build_collection_rewards.luau - run through the Studio MCP (execute_luau, Edit datamodel, Play stopped).

	Creates the GUI templates of the Collections reward page (CollectionsPageModule looks them up BY NAME):
	  ReplicatedStorage.GridTemplates.CollectionsMenu4        Folder: BackButton + CloseSlot (copied from CollectionsMenu3)
	  StarterGui.CentralizedAscensionMenu.TemporaryMenus
	    TierTitle              copy of CollectionLevelSlot (the tier numeral at the top middle, LevelLabel inside BG)
	    RewardSlot             copy of StatSlot + an "Amount" label (the short reward text, e.g. +5%)
	    CollectionStatSlot     copy of StatSlot + a "LevelLabel" (the collection level shown on the Menu2 stat slots)

	Restyle them freely, but keep the names and the Icon / BG / label children. Idempotent: an existing template is left
	alone unless FORCE = true.
]]

local FORCE = false

local TM = game:GetService("StarterGui"):WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
local GridTemplates = game:GetService("ReplicatedStorage"):WaitForChild("GridTemplates")
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

local function cornerLabel(slot, name)
	local source = TM.CollectionLevelSlot.BG.LevelLabel:Clone()
	source.Name = name
	source.AnchorPoint = Vector2.new(1, 1)
	source.Position = UDim2.new(1, -3, 1, -3)
	source.Size = UDim2.fromScale(0.6, 0.4)
	source.ZIndex = 3
	source.Text = ""
	source.TextXAlignment = Enum.TextXAlignment.Right
	source.Parent = slot
	return source
end

-- tier numeral
if fresh(TM, "TierTitle") then
	local slot = TM.CollectionLevelSlot:Clone()
	slot.Name = "TierTitle"
	slot.Visible = false
	slot.Parent = TM
	table.insert(made, "TierTitle")
end

-- reward slot
if fresh(TM, "RewardSlot") then
	local slot = TM.StatSlot:Clone()
	slot.Name = "RewardSlot"
	slot.Visible = false
	cornerLabel(slot, "Amount")
	slot.Parent = TM
	table.insert(made, "RewardSlot")
end

-- statistic slot with a collection level label
if fresh(TM, "CollectionStatSlot") then
	local slot = TM.StatSlot:Clone()
	slot.Name = "CollectionStatSlot"
	slot.Visible = false
	cornerLabel(slot, "LevelLabel")
	slot.Parent = TM
	table.insert(made, "CollectionStatSlot")
end

-- the reward page's grid template
if fresh(GridTemplates, "CollectionsMenu4") then
	local folder = Instance.new("Folder")
	folder.Name = "CollectionsMenu4"
	local source = GridTemplates:WaitForChild("CollectionsMenu3")
	for _, name in ipairs({ "BackButton", "CloseSlot" }) do
		source[name]:Clone().Parent = folder
	end
	folder.Parent = GridTemplates
	table.insert(made, "CollectionsMenu4")
end

return #made == 0 and "nothing to do (all templates exist)" or ("created: " .. table.concat(made, ", "))
