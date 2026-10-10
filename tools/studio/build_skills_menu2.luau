--[[
	build_skills_menu2.luau - run through the Studio MCP (execute_luau, Edit datamodel, Play stopped).

	Creates the templates of the Skills breakdown (SkillsPageModule looks them up BY NAME):
	  ReplicatedStorage.GridTemplates.SkillsMenu2         Folder: BackButton + CloseSlot (copied from CollectionsMenu4),
	                                                      PagePrev (a copy of BackButton) and PageNext (BackButton turned round)
	  StarterGui.CentralizedAscensionMenu.TemporaryMenus
	    SkillTitle        copy of TierTitle + Icon (the skill's icon, top-left; LevelLabel inside BG shows the level)
	    SkillLevelSlot    copy of CollectionLevelSlot + Icon (one level of the snake; LevelLabel = the level numeral)
	BlankSlot, TierTitle and CollectionLevelSlot must already exist (build_collection_rewards.luau).

	Restyle freely, but keep the names and the BG / Icon / LevelLabel children. Idempotent: an existing template is left
	alone unless FORCE = true. The old SkillDescFrame builder (build_skills_menu.luau) is retired and no longer used.
]]

local FORCE = false

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TM = StarterGui:WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
local GridTemplates = ReplicatedStorage:WaitForChild("GridTemplates")
local made = {}

--- true = the template exists and must be left alone (or is removed when FORCE).
local function keep(parent: Instance, name: string): boolean
	local old = parent:FindFirstChild(name)
	if old and not FORCE then
		return true
	end
	if old then
		old:Destroy()
	end
	return false
end

--- A centred icon copied from StatSlot's Icon, sized so the level numeral still reads.
local function addIcon(slot: Instance)
	local icon = TM.StatSlot.Icon:Clone()
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.42)
	icon.Size = UDim2.fromScale(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.ZIndex = 3
	icon.Parent = slot
end

-- skill title (top-left)
if not keep(TM, "SkillTitle") then
	local slot = TM.TierTitle:Clone()
	slot.Name = "SkillTitle"
	slot.Visible = false
	addIcon(slot)
	slot.Parent = TM
	table.insert(made, "SkillTitle")
end

-- one level of the snake
if not keep(TM, "SkillLevelSlot") then
	local slot = TM.CollectionLevelSlot:Clone()
	slot.Name = "SkillLevelSlot"
	slot.Visible = false
	addIcon(slot)
	slot.Parent = TM
	table.insert(made, "SkillLevelSlot")
end

-- the grid folder: Back and Close from the collections page, plus the two page arrows
if not keep(GridTemplates, "SkillsMenu2") then
	local folder = GridTemplates.CollectionsMenu4:Clone()
	folder.Name = "SkillsMenu2"
	folder.Parent = GridTemplates
	table.insert(made, "GridTemplates.SkillsMenu2")
end
local folder = GridTemplates.SkillsMenu2
local back = folder:FindFirstChild("BackButton")
if back then
	if not keep(folder, "PagePrev") then
		local prev = back:Clone()
		prev.Name = "PagePrev"
		prev.Parent = folder
		table.insert(made, "PagePrev")
	end
	if not keep(folder, "PageNext") then
		local nextArrow = back:Clone()
		nextArrow.Name = "PageNext"
		local icon = nextArrow:FindFirstChild("Icon")
		if icon then
			icon.Rotation = 180
		else
			nextArrow.Rotation = 180
		end
		nextArrow.Parent = folder
		table.insert(made, "PageNext")
	end
end

return #made == 0 and "nothing to do: every SkillsMenu2 template already exists" or ("built: " .. table.concat(made, ", "))
