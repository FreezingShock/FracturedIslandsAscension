-- ============================================================
--  AdminPanelModule (ModuleScript)
--  ReplicatedStorage > Modules
--
--  Admin-only developer panel for creating and testing items.
--  Tabs: Creator (form), Spawner (list), Existing (runtime items)
--
--  Features:
--    • Dynamic form builder from ItemCreatorConfig
--    • Stat builder (add/remove custom stats)
--    • Real-time preview with rarity colors
--    • Item spawner with count selector
--    • Persistence via inventory (items stay after reload)
--    • Connection cleanup (PITFALL 3)
--
--  API:
--    init(sharedRefs)
--    open()
--    close()
--    reset()
--    refreshSpawnerList()
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local TooltipModule = require(Modules:WaitForChild("TooltipModule")) :: any
local ItemRegistry = require(Modules:WaitForChild("ItemRegistry")) :: any
local ItemCreatorConfig = require(Modules:WaitForChild("ItemCreatorConfig")) :: any

-- ===================== REMOTES =====================
local CreateItemFunc = ReplicatedStorage:WaitForChild("CreateItem")
local SpawnItemFunc = ReplicatedStorage:WaitForChild("SpawnItem")
local GetRuntimeItemsFunc = ReplicatedStorage:WaitForChild("GetRuntimeItems")

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")

-- ===================== STATE =====================
local AdminPanelModule = {}
local initialized = false
local isOpen = false
local currentTab = "Creator" -- "Creator", "Spawner", "Existing"

local shared = nil
local adminPanelFrame = nil
local tabButtons = {}
local tabContents = {}

-- Form state
local formState = {
	displayName = "",
	description = "",
	rarity = 0,
	statTemplate = nil,
	ability = "None",
	customStats = {}, -- { { statName = "X", value = N }, ... }
}

local dynamicConnections = {} -- Track all wired connections for cleanup

-- Spawner state
local spawnerItems = {} -- { { id, displayName, rarity, source }, ... }
local selectedSpawnerItem = nil
local spawnerCount = 1

-- ===================== AUDIO REFS =====================
local function playClick()
	UIClick:Play()
end

local function playClickSmall()
	UIClick3:Play()
end

-- ===================== HELPERS =====================

local function clearConnections()
	for _, conn in ipairs(dynamicConnections) do
		conn:Disconnect()
	end
	table.clear(dynamicConnections)
end

local function wireConnection(conn)
	table.insert(dynamicConnections, conn)
end

local function getRarityConfig(rarity)
	return ItemRegistry.getRarity(rarity or 0)
end

local function formatRarityDisplay(rarity)
	local cfg = getRarityConfig(rarity)
	return cfg and cfg.name or "Unknown"
end

local function colorForRarity(rarity)
	local cfg = getRarityConfig(rarity)
	return cfg and cfg.hexColor or "#FFFFFF"
end

-- ===================== FORM VALIDATION =====================

local function validateFormState()
	if not formState.displayName or formState.displayName == "" then
		return false, "Display name is required"
	end
	if #formState.displayName > 50 then
		return false, "Display name too long (max 50 chars)"
	end
	if type(formState.rarity) ~= "number" or formState.rarity < 0 or formState.rarity > 5 then
		return false, "Invalid rarity tier"
	end
	return true, "Valid"
end

-- ===================== TAB SWITCHING =====================

local function switchTab(tabName)
	if currentTab == tabName then
		return
	end

	currentTab = tabName
	playClick()

	-- Hide all tabs, show current
	for name, frame in pairs(tabContents) do
		frame.Visible = (name == tabName)
	end

	-- Update button highlights
	for name, btn in pairs(tabButtons) do
		local isActive = (name == tabName)
		btn.BackgroundColor3 = isActive and Color3.fromHex("#55FF55") or Color3.fromHex("#333333")
		btn.TextColor3 = isActive and Color3.fromHex("#000000") or Color3.fromHex("#AAAAAA")
	end

	-- Refresh content if needed
	if tabName == "Spawner" then
		AdminPanelModule.refreshSpawnerList()
	elseif tabName == "Existing" then
		AdminPanelModule.refreshExistingList()
	end
end

-- ===================== CREATOR TAB =====================

local function buildCreatorTab(parentFrame)
	parentFrame.Name = "CreatorTab"
	parentFrame.Visible = false
	parentFrame.Size = UDim2.fromScale(1, 1)
	parentFrame.BackgroundTransparency = 1

	-- Add scrolling frame for form
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "FormScroller"
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.BackgroundTransparency = 1
	scroller.ScrollBarThickness = 12
	scroller.CanvasSize = UDim2.fromScale(1, 0) -- Auto height
	scroller.Parent = parentFrame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scroller

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = scroller

	-- ── Display Name ──
	local nameSection = Instance.new("TextLabel")
	nameSection.Name = "NameSection"
	nameSection.Size = UDim2.fromScale(1, 0)
	nameSection.AutomaticSize = Enum.AutomaticSize.Y
	nameSection.BackgroundTransparency = 1
	nameSection.TextSize = 0
	nameSection.LayoutOrder = 1
	nameSection.Parent = scroller

	local nameLayout = Instance.new("UIListLayout")
	nameLayout.FillDirection = Enum.FillDirection.Vertical
	nameLayout.SortOrder = Enum.SortOrder.LayoutOrder
	nameLayout.Padding = UDim.new(0, 4)
	nameLayout.Parent = nameSection

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Text = "Display Name"
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Color3.fromHex("#FFFF55")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.fromScale(1, 0)
	nameLabel.AutomaticSize = Enum.AutomaticSize.Y
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = nameSection

	local nameInput = Instance.new("TextBox")
	nameInput.Name = "NameInput"
	nameInput.PlaceholderText = "e.g. Legendary Sword"
	nameInput.PlaceholderColor3 = Color3.fromHex("#666666")
	nameInput.TextColor3 = Color3.fromHex("#FFFFFF")
	nameInput.BackgroundColor3 = Color3.fromHex("#222222")
	nameInput.BorderColor3 = Color3.fromHex("#555555")
	nameInput.BorderSizePixel = 1
	nameInput.Size = UDim2.fromScale(1, 0)
	nameInput.AutomaticSize = Enum.AutomaticSize.Y
	nameInput.TextSize = 14
	nameInput.Padding = UDim.new(0, 8)
	nameInput.Parent = nameSection

	wireConnection(nameInput.FocusLost:Connect(function()
		formState.displayName = nameInput.Text
	end))

	-- ── Description ──
	local descSection = Instance.new("TextLabel")
	descSection.Name = "DescSection"
	descSection.Size = UDim2.fromScale(1, 0)
	descSection.AutomaticSize = Enum.AutomaticSize.Y
	descSection.BackgroundTransparency = 1
	descSection.TextSize = 0
	descSection.LayoutOrder = 2
	descSection.Parent = scroller

	local descLayout = Instance.new("UIListLayout")
	descLayout.FillDirection = Enum.FillDirection.Vertical
	descLayout.SortOrder = Enum.SortOrder.LayoutOrder
	descLayout.Padding = UDim.new(0, 4)
	descLayout.Parent = descSection

	local descLabel = Instance.new("TextLabel")
	descLabel.Text = "Description (Optional)"
	descLabel.TextSize = 14
	descLabel.TextColor3 = Color3.fromHex("#FFFF55")
	descLabel.BackgroundTransparency = 1
	descLabel.Size = UDim2.fromScale(1, 0)
	descLabel.AutomaticSize = Enum.AutomaticSize.Y
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = descSection

	local descInput = Instance.new("TextBox")
	descInput.Name = "DescInput"
	descInput.PlaceholderText = "Item flavor text"
	descInput.PlaceholderColor3 = Color3.fromHex("#666666")
	descInput.TextColor3 = Color3.fromHex("#FFFFFF")
	descInput.BackgroundColor3 = Color3.fromHex("#222222")
	descInput.BorderColor3 = Color3.fromHex("#555555")
	descInput.BorderSizePixel = 1
	descInput.Size = UDim2.fromScale(1, 0)
	descInput.AutomaticSize = Enum.AutomaticSize.Y
	descInput.TextSize = 14
	descInput.Padding = UDim.new(0, 8)
	descInput.Parent = descSection

	wireConnection(descInput.FocusLost:Connect(function()
		formState.description = descInput.Text
	end))

	-- ── Rarity Dropdown ──
	local raritySection = Instance.new("TextLabel")
	raritySection.Name = "RaritySection"
	raritySection.Size = UDim2.fromScale(1, 0)
	raritySection.AutomaticSize = Enum.AutomaticSize.Y
	raritySection.BackgroundTransparency = 1
	raritySection.TextSize = 0
	raritySection.LayoutOrder = 3
	raritySection.Parent = scroller

	local rarityLayout = Instance.new("UIListLayout")
	rarityLayout.FillDirection = Enum.FillDirection.Vertical
	rarityLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rarityLayout.Padding = UDim.new(0, 4)
	rarityLayout.Parent = raritySection

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Text = "Rarity Tier"
	rarityLabel.TextSize = 14
	rarityLabel.TextColor3 = Color3.fromHex("#FFFF55")
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Size = UDim2.fromScale(1, 0)
	rarityLabel.AutomaticSize = Enum.AutomaticSize.Y
	rarityLabel.TextXAlignment = Enum.TextXAlignment.Left
	rarityLabel.Parent = raritySection

	local rarityButtons = Instance.new("Frame")
	rarityButtons.Name = "RarityButtons"
	rarityButtons.Size = UDim2.fromScale(1, 0)
	rarityButtons.AutomaticSize = Enum.AutomaticSize.Y
	rarityButtons.BackgroundTransparency = 1
	rarityButtons.Parent = raritySection

	local rarityGrid = Instance.new("UIGridLayout")
	rarityGrid.FillDirection = Enum.FillDirection.Horizontal
	rarityGrid.FillDirectionMaxSize = 60
	rarityGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rarityGrid.Padding = UDim.new(0, 4)
	rarityGrid.Parent = rarityButtons

	for i = 0, 5 do
		local btn = Instance.new("TextButton")
		btn.Name = "Rarity" .. i
		btn.Text = tostring(i)
		btn.TextSize = 12
		btn.Size = UDim2.fromOffset(50, 32)
		btn.BackgroundColor3 = Color3.fromHex("#333333")
		btn.TextColor3 = Color3.fromHex("#AAAAAA")
		btn.BorderSizePixel = 0
		btn.Parent = rarityButtons

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = btn

		local capturedRarity = i
		wireConnection(btn.MouseButton1Click:Connect(function()
			formState.rarity = capturedRarity
			playClickSmall()

			-- Update all rarity buttons
			for _, child in ipairs(rarityButtons:GetChildren()) do
				if child:IsA("TextButton") then
					local isActive = tonumber(child.Name:match("Rarity(%d)")) == capturedRarity
					child.BackgroundColor3 = isActive and Color3.fromHex("#55FF55") or Color3.fromHex("#333333")
					child.TextColor3 = isActive and Color3.fromHex("#000000") or Color3.fromHex("#AAAAAA")
				end
			end
		end))
	end

	-- ── Ability Dropdown ──
	local abilitySection = Instance.new("TextLabel")
	abilitySection.Name = "AbilitySection"
	abilitySection.Size = UDim2.fromScale(1, 0)
	abilitySection.AutomaticSize = Enum.AutomaticSize.Y
	abilitySection.BackgroundTransparency = 1
	abilitySection.TextSize = 0
	abilitySection.LayoutOrder = 4
	abilitySection.Parent = scroller

	local abilityLayout = Instance.new("UIListLayout")
	abilityLayout.FillDirection = Enum.FillDirection.Vertical
	abilityLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilityLayout.Padding = UDim.new(0, 4)
	abilityLayout.Parent = abilitySection

	local abilityLabel = Instance.new("TextLabel")
	abilityLabel.Text = "Special Ability"
	abilityLabel.TextSize = 14
	abilityLabel.TextColor3 = Color3.fromHex("#FFFF55")
	abilityLabel.BackgroundTransparency = 1
	abilityLabel.Size = UDim2.fromScale(1, 0)
	abilityLabel.AutomaticSize = Enum.AutomaticSize.Y
	abilityLabel.TextXAlignment = Enum.TextXAlignment.Left
	abilityLabel.Parent = abilitySection

	local abilityContainer = Instance.new("Frame")
	abilityContainer.Name = "AbilityContainer"
	abilityContainer.Size = UDim2.fromScale(1, 0)
	abilityContainer.AutomaticSize = Enum.AutomaticSize.Y
	abilityContainer.BackgroundTransparency = 1
	abilityContainer.Parent = abilitySection

	local abilityList = Instance.new("UIListLayout")
	abilityList.FillDirection = Enum.FillDirection.Vertical
	abilityList.SortOrder = Enum.SortOrder.LayoutOrder
	abilityList.Padding = UDim.new(0, 2)
	abilityList.Parent = abilityContainer

	for abilityName, abilityData in pairs(ItemCreatorConfig.ABILITY_PRESETS) do
		local btn = Instance.new("TextButton")
		btn.Name = abilityName
		btn.Text = "  " .. abilityData.name
		btn.TextSize = 12
		btn.TextColor3 = Color3.fromHex("#AAAAAA")
		btn.BackgroundColor3 = Color3.fromHex("#222222")
		btn.BorderColor3 = Color3.fromHex("#444444")
		btn.BorderSizePixel = 1
		btn.Size = UDim2.fromScale(1, 0)
		btn.AutomaticSize = Enum.AutomaticSize.Y
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Parent = abilityContainer

		local capturedAbility = abilityName
		wireConnection(btn.MouseButton1Click:Connect(function()
			formState.ability = capturedAbility
			playClickSmall()

			-- Highlight selected
			for _, child in ipairs(abilityContainer:GetChildren()) do
				if child:IsA("TextButton") then
					child.BackgroundColor3 = (child.Name == capturedAbility) and Color3.fromHex("#003300")
						or Color3.fromHex("#222222")
				end
			end
		end))
	end

	-- ── Custom Stats Section ──
	local statsSection = Instance.new("TextLabel")
	statsSection.Name = "StatsSection"
	statsSection.Size = UDim2.fromScale(1, 0)
	statsSection.AutomaticSize = Enum.AutomaticSize.Y
	statsSection.BackgroundTransparency = 1
	statsSection.TextSize = 0
	statsSection.LayoutOrder = 5
	statsSection.Parent = scroller

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 4)
	statsLayout.Parent = statsSection

	local statsLabel = Instance.new("TextLabel")
	statsLabel.Text = "Custom Stats"
	statsLabel.TextSize = 14
	statsLabel.TextColor3 = Color3.fromHex("#FFFF55")
	statsLabel.BackgroundTransparency = 1
	statsLabel.Size = UDim2.fromScale(1, 0)
	statsLabel.AutomaticSize = Enum.AutomaticSize.Y
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	statsLabel.Parent = statsSection

	local statsList = Instance.new("Frame")
	statsList.Name = "StatsList"
	statsList.Size = UDim2.fromScale(1, 0)
	statsList.AutomaticSize = Enum.AutomaticSize.Y
	statsList.BackgroundTransparency = 1
	statsList.Parent = statsSection

	local statsListLayout = Instance.new("UIListLayout")
	statsListLayout.FillDirection = Enum.FillDirection.Vertical
	statsListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsListLayout.Padding = UDim.new(0, 4)
	statsListLayout.Parent = statsList

	-- Store reference for dynamic stat adding
	parentFrame:SetAttribute("StatsList", statsList)

	-- ── Add Stat Button ──
	local addStatBtn = Instance.new("TextButton")
	addStatBtn.Name = "AddStatBtn"
	addStatBtn.Text = "+ Add Stat"
	addStatBtn.TextSize = 12
	addStatBtn.BackgroundColor3 = Color3.fromHex("#004400")
	addStatBtn.TextColor3 = Color3.fromHex("#55FF55")
	addStatBtn.BorderSizePixel = 0
	addStatBtn.Size = UDim2.fromScale(1, 0)
	addStatBtn.AutomaticSize = Enum.AutomaticSize.Y
	addStatBtn.Parent = statsSection

	local addStatCorner = Instance.new("UICorner")
	addStatCorner.CornerRadius = UDim.new(0, 4)
	addStatCorner.Parent = addStatBtn

	wireConnection(addStatBtn.MouseButton1Click:Connect(function()
		playClick()
		AdminPanelModule._addStatRow(statsList)
	end))

	-- ── Preview ──
	local previewSection = Instance.new("TextLabel")
	previewSection.Name = "PreviewSection"
	previewSection.Size = UDim2.fromScale(1, 0)
	previewSection.AutomaticSize = Enum.AutomaticSize.Y
	previewSection.BackgroundTransparency = 1
	previewSection.TextSize = 0
	previewSection.LayoutOrder = 6
	previewSection.Parent = scroller

	local previewLayout = Instance.new("UIListLayout")
	previewLayout.FillDirection = Enum.FillDirection.Vertical
	previewLayout.SortOrder = Enum.SortOrder.LayoutOrder
	previewLayout.Padding = UDim.new(0, 4)
	previewLayout.Parent = previewSection

	local previewLabel = Instance.new("TextLabel")
	previewLabel.Text = "Preview"
	previewLabel.TextSize = 14
	previewLabel.TextColor3 = Color3.fromHex("#FFFF55")
	previewLabel.BackgroundTransparency = 1
	previewLabel.Size = UDim2.fromScale(1, 0)
	previewLabel.AutomaticSize = Enum.AutomaticSize.Y
	previewLabel.TextXAlignment = Enum.TextXAlignment.Left
	previewLabel.Parent = previewSection

	local previewFrame = Instance.new("TextLabel")
	previewFrame.Name = "PreviewFrame"
	previewFrame.Size = UDim2.fromScale(1, 0)
	previewFrame.AutomaticSize = Enum.AutomaticSize.Y
	previewFrame.BackgroundColor3 = Color3.fromHex("#1a1a1a")
	previewFrame.BorderColor3 = Color3.fromHex("#444444")
	previewFrame.BorderSizePixel = 1
	previewFrame.TextSize = 0
	previewFrame.Parent = previewSection

	local previewContent = Instance.new("TextLabel")
	previewContent.Name = "PreviewContent"
	previewContent.Size = UDim2.fromScale(1, 0)
	previewContent.AutomaticSize = Enum.AutomaticSize.Y
	previewContent.BackgroundTransparency = 1
	previewContent.TextSize = 14
	previewContent.TextXAlignment = Enum.TextXAlignment.Left
	previewContent.TextYAlignment = Enum.TextYAlignment.Top
	previewContent.TextWrapped = true
	previewContent.RichText = true
	previewContent.Parent = previewFrame

	local previewPadding = Instance.new("UIPadding")
	previewPadding.PaddingLeft = UDim.new(0, 8)
	previewPadding.PaddingRight = UDim.new(0, 8)
	previewPadding.PaddingTop = UDim.new(0, 8)
	previewPadding.PaddingBottom = UDim.new(0, 8)
	previewPadding.Parent = previewFrame

	parentFrame:SetAttribute("PreviewContent", previewContent)

	-- ── Create Button ──
	local createBtn = Instance.new("TextButton")
	createBtn.Name = "CreateBtn"
	createBtn.Text = "✓ CREATE ITEM"
	createBtn.TextSize = 14
	createBtn.BackgroundColor3 = Color3.fromHex("#004400")
	createBtn.TextColor3 = Color3.fromHex("#55FF55")
	createBtn.BorderSizePixel = 0
	createBtn.Size = UDim2.fromScale(1, 0)
	createBtn.AutomaticSize = Enum.AutomaticSize.Y
	createBtn.LayoutOrder = 7
	createBtn.Parent = scroller

	local createCorner = Instance.new("UICorner")
	createCorner.CornerRadius = UDim.new(0, 4)
	createCorner.Parent = createBtn

	wireConnection(createBtn.MouseButton1Click:Connect(function()
		AdminPanelModule._createItem()
	end))

	-- Store references
	tabContents["Creator"] = parentFrame
	parentFrame:SetAttribute("NameInput", nameInput)
	parentFrame:SetAttribute("DescInput", descInput)
end

-- ===================== SPAWNER TAB =====================

local function buildSpawnerTab(parentFrame)
	parentFrame.Name = "SpawnerTab"
	parentFrame.Visible = false
	parentFrame.Size = UDim2.fromScale(1, 1)
	parentFrame.BackgroundTransparency = 1

	-- Items list
	local itemsList = Instance.new("ScrollingFrame")
	itemsList.Name = "ItemsList"
	itemsList.Size = UDim2.fromScale(1, 0.65)
	itemsList.BackgroundColor3 = Color3.fromHex("#1a1a1a")
	itemsList.BorderColor3 = Color3.fromHex("#444444")
	itemsList.BorderSizePixel = 1
	itemsList.ScrollBarThickness = 12
	itemsList.CanvasSize = UDim2.fromScale(1, 0)
	itemsList.Parent = parentFrame

	local itemsLayout = Instance.new("UIListLayout")
	itemsLayout.FillDirection = Enum.FillDirection.Vertical
	itemsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	itemsLayout.Padding = UDim.new(0, 4)
	itemsLayout.Parent = itemsList

	local itemsPadding = Instance.new("UIPadding")
	itemsPadding.PaddingLeft = UDim.new(0, 8)
	itemsPadding.PaddingRight = UDim.new(0, 8)
	itemsPadding.PaddingTop = UDim.new(0, 8)
	itemsPadding.PaddingBottom = UDim.new(0, 8)
	itemsPadding.Parent = itemsList

	parentFrame:SetAttribute("ItemsList", itemsList)

	-- Count + Spawn section
	local controlSection = Instance.new("Frame")
	controlSection.Name = "ControlSection"
	controlSection.Size = UDim2.fromScale(1, 0.35)
	controlSection.BackgroundTransparency = 1
	controlSection.Parent = parentFrame

	local controlLayout = Instance.new("UIListLayout")
	controlLayout.FillDirection = Enum.FillDirection.Vertical
	controlLayout.SortOrder = Enum.SortOrder.LayoutOrder
	controlLayout.Padding = UDim.new(0, 8)
	controlLayout.Parent = controlSection

	-- Count selector
	local countFrame = Instance.new("Frame")
	countFrame.Name = "CountFrame"
	countFrame.Size = UDim2.fromScale(1, 0)
	countFrame.AutomaticSize = Enum.AutomaticSize.Y
	countFrame.BackgroundTransparency = 1
	countFrame.LayoutOrder = 1
	countFrame.Parent = controlSection

	local countLayout = Instance.new("UIListLayout")
	countLayout.FillDirection = Enum.FillDirection.Horizontal
	countLayout.SortOrder = Enum.SortOrder.LayoutOrder
	countLayout.Padding = UDim.new(0, 4)
	countLayout.Parent = countFrame

	local countLabel = Instance.new("TextLabel")
	countLabel.Text = "Count:"
	countLabel.TextSize = 12
	countLabel.TextColor3 = Color3.fromHex("#FFFF55")
	countLabel.BackgroundTransparency = 1
	countLabel.Size = UDim2.fromOffset(60, 32)
	countLabel.LayoutOrder = 1
	countLabel.Parent = countFrame

	local countInput = Instance.new("TextBox")
	countInput.Name = "CountInput"
	countInput.Text = "1"
	countInput.TextSize = 12
	countInput.BackgroundColor3 = Color3.fromHex("#222222")
	countInput.TextColor3 = Color3.fromHex("#FFFFFF")
	countInput.BorderColor3 = Color3.fromHex("#555555")
	countInput.BorderSizePixel = 1
	countInput.Size = UDim2.fromOffset(80, 32)
	countInput.LayoutOrder = 2
	countInput.Parent = countFrame

	wireConnection(countInput.FocusLost:Connect(function()
		spawnerCount = math.max(1, tonumber(countInput.Text) or 1)
		countInput.Text = tostring(spawnerCount)
	end))

	-- Spawn button
	local spawnBtn = Instance.new("TextButton")
	spawnBtn.Name = "SpawnBtn"
	spawnBtn.Text = "⬇ SPAWN ITEM"
	spawnBtn.TextSize = 12
	spawnBtn.BackgroundColor3 = Color3.fromHex("#004400")
	spawnBtn.TextColor3 = Color3.fromHex("#55FF55")
	spawnBtn.BorderSizePixel = 0
	spawnBtn.Size = UDim2.fromScale(1, 0)
	spawnBtn.AutomaticSize = Enum.AutomaticSize.Y
	spawnBtn.LayoutOrder = 2
	spawnBtn.Parent = controlSection

	local spawnCorner = Instance.new("UICorner")
	spawnCorner.CornerRadius = UDim.new(0, 4)
	spawnCorner.Parent = spawnBtn

	wireConnection(spawnBtn.MouseButton1Click:Connect(function()
		if selectedSpawnerItem then
			AdminPanelModule._spawnItem(selectedSpawnerItem.id, spawnerCount)
		else
			warn("[AdminPanel] No item selected")
		end
	end))

	tabContents["Spawner"] = parentFrame
end

-- ===================== EXISTING TAB =====================

local function buildExistingTab(parentFrame)
	parentFrame.Name = "ExistingTab"
	parentFrame.Visible = false
	parentFrame.Size = UDim2.fromScale(1, 1)
	parentFrame.BackgroundTransparency = 1

	local existingList = Instance.new("ScrollingFrame")
	existingList.Name = "ExistingList"
	existingList.Size = UDim2.fromScale(1, 1)
	existingList.BackgroundColor3 = Color3.fromHex("#1a1a1a")
	existingList.BorderColor3 = Color3.fromHex("#444444")
	existingList.BorderSizePixel = 1
	existingList.ScrollBarThickness = 12
	existingList.CanvasSize = UDim2.fromScale(1, 0)
	existingList.Parent = parentFrame

	local existingLayout = Instance.new("UIListLayout")
	existingLayout.FillDirection = Enum.FillDirection.Vertical
	existingLayout.SortOrder = Enum.SortOrder.LayoutOrder
	existingLayout.Padding = UDim.new(0, 4)
	existingLayout.Parent = existingList

	local existingPadding = Instance.new("UIPadding")
	existingPadding.PaddingLeft = UDim.new(0, 8)
	existingPadding.PaddingRight = UDim.new(0, 8)
	existingPadding.PaddingTop = UDim.new(0, 8)
	existingPadding.PaddingBottom = UDim.new(0, 8)
	existingPadding.Parent = existingList

	tabContents["Existing"] = parentFrame
	parentFrame:SetAttribute("ExistingList", existingList)
end

-- ===================== ITEM CREATION =====================

function AdminPanelModule._addStatRow(statsList)
	local row = Instance.new("Frame")
	row.Name = "StatRow"
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.Parent = statsList

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Padding = UDim.new(0, 4)
	rowLayout.Parent = row

	-- Stat name dropdown (simplified: textbox)
	local statNameInput = Instance.new("TextBox")
	statNameInput.Name = "StatName"
	statNameInput.PlaceholderText = "Strength"
	statNameInput.PlaceholderColor3 = Color3.fromHex("#666666")
	statNameInput.TextColor3 = Color3.fromHex("#FFFFFF")
	statNameInput.BackgroundColor3 = Color3.fromHex("#222222")
	statNameInput.BorderColor3 = Color3.fromHex("#555555")
	statNameInput.BorderSizePixel = 1
	statNameInput.TextSize = 12
	statNameInput.Padding = UDim.new(0, 4)
	statNameInput.Size = UDim2.fromOffset(120, 28)
	statNameInput.LayoutOrder = 1
	statNameInput.Parent = row

	-- Stat value input
	local statValueInput = Instance.new("TextBox")
	statValueInput.Name = "StatValue"
	statValueInput.PlaceholderText = "10"
	statValueInput.PlaceholderColor3 = Color3.fromHex("#666666")
	statValueInput.TextColor3 = Color3.fromHex("#FFFFFF")
	statValueInput.BackgroundColor3 = Color3.fromHex("#222222")
	statValueInput.BorderColor3 = Color3.fromHex("#555555")
	statValueInput.BorderSizePixel = 1
	statValueInput.TextSize = 12
	statValueInput.Padding = UDim.new(0, 4)
	statValueInput.Size = UDim2.fromOffset(80, 28)
	statValueInput.LayoutOrder = 2
	statValueInput.Parent = row

	-- Remove button
	local removeBtn = Instance.new("TextButton")
	removeBtn.Name = "RemoveBtn"
	removeBtn.Text = "✕"
	removeBtn.TextSize = 12
	removeBtn.BackgroundColor3 = Color3.fromHex("#440000")
	removeBtn.TextColor3 = Color3.fromHex("#FF5555")
	removeBtn.BorderSizePixel = 0
	removeBtn.Size = UDim2.fromOffset(32, 28)
	removeBtn.LayoutOrder = 3
	removeBtn.Parent = row

	local removeCorner = Instance.new("UICorner")
	removeCorner.CornerRadius = UDim.new(0, 2)
	removeCorner.Parent = removeBtn

	wireConnection(removeBtn.MouseButton1Click:Connect(function()
		row:Destroy()
	end))

	return statNameInput, statValueInput
end

function AdminPanelModule._createItem()
	local valid, reason = validateFormState()
	if not valid then
		print("[AdminPanel] Validation failed: " .. reason)
		return
	end

	-- Build stat bonuses from custom rows
	local statBonuses = {}
	local creatorTab = tabContents["Creator"]
	local statsList = creatorTab:GetAttribute("StatsList")

	for _, row in ipairs(statsList:GetChildren()) do
		if row.Name == "StatRow" then
			local nameInput = row:FindFirstChild("StatName")
			local valueInput = row:FindFirstChild("StatValue")
			if nameInput and valueInput then
				local statName = nameInput.Text
				local statValue = tonumber(valueInput.Text) or 0
				if statName ~= "" then
					statBonuses[statName] = statValue
				end
			end
		end
	end

	-- Call server to create
	local itemData = {
		displayName = formState.displayName,
		description = formState.description,
		rarity = formState.rarity,
		ability = formState.ability,
		statBonuses = statBonuses,
	}

	print("[AdminPanel] Creating item: " .. formState.displayName)

	local success, itemId = CreateItemFunc:InvokeServer(itemData)
	if success then
		print("[AdminPanel] Created! ID: " .. itemId)
		-- Spawn it too
		AdminPanelModule._spawnItem(itemId, 1)
		playClick()
	else
		warn("[AdminPanel] Creation failed: " .. tostring(itemId))
	end
end

function AdminPanelModule._spawnItem(itemId, count)
	print("[AdminPanel] Spawning " .. itemId .. " x" .. count)
	local success = SpawnItemFunc:InvokeServer(itemId, count)
	if success then
		print("[AdminPanel] Spawned!")
		playClick()
	else
		warn("[AdminPanel] Spawn failed")
	end
end

-- ===================== REFRESHERS =====================

function AdminPanelModule.refreshSpawnerList()
	local spawnerTab = tabContents["Spawner"]
	if not spawnerTab then
		return
	end

	local itemsList = spawnerTab:GetAttribute("ItemsList")
	itemsList:ClearAllChildren()

	spawnerItems = {}

	-- Add all static items from ItemRegistry
	for itemId, entry in pairs(ItemRegistry.Items) do
		if not entry.isDynamic then
			table.insert(spawnerItems, {
				id = itemId,
				displayName = entry.displayName,
				rarity = entry.rarity,
				source = "Static",
			})
		end
	end

	-- Add runtime items from server
	local runtimeItems = GetRuntimeItemsFunc:InvokeServer() or {}
	for _, entry in ipairs(runtimeItems) do
		table.insert(spawnerItems, {
			id = entry.id,
			displayName = entry.displayName,
			rarity = entry.rarity,
			source = "Dev",
		})
	end

	-- Render items
	for idx, item in ipairs(spawnerItems) do
		local btn = Instance.new("TextButton")
		btn.Name = "ItemBtn_" .. item.id
		btn.Text = ""
		btn.BackgroundColor3 = Color3.fromHex("#222222")
		btn.BorderColor3 = Color3.fromHex("#444444")
		btn.BorderSizePixel = 1
		btn.Size = UDim2.fromScale(1, 0)
		btn.AutomaticSize = Enum.AutomaticSize.Y
		btn.Parent = itemsList

		local btnLayout = Instance.new("UIListLayout")
		btnLayout.FillDirection = Enum.FillDirection.Horizontal
		btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
		btnLayout.Padding = UDim.new(0, 8)
		btnLayout.Parent = btn

		-- Name + rarity
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Text = item.displayName .. " [" .. item.source .. "]"
		nameLabel.TextSize = 12
		nameLabel.TextColor3 = Color3.fromHex(colorForRarity(item.rarity))
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.fromScale(0.8, 0)
		nameLabel.AutomaticSize = Enum.AutomaticSize.Y
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.LayoutOrder = 1
		nameLabel.Parent = btn

		-- Rarity badge
		local rarityBadge = Instance.new("TextLabel")
		rarityBadge.Text = formatRarityDisplay(item.rarity)
		rarityBadge.TextSize = 10
		rarityBadge.TextColor3 = Color3.fromHex(colorForRarity(item.rarity))
		rarityBadge.BackgroundColor3 = Color3.fromHex("#1a1a1a")
		rarityBadge.BorderColor3 = Color3.fromHex(colorForRarity(item.rarity))
		rarityBadge.BorderSizePixel = 1
		rarityBadge.Size = UDim2.fromOffset(80, 0)
		rarityBadge.AutomaticSize = Enum.AutomaticSize.Y
		rarityBadge.LayoutOrder = 2
		rarityBadge.Parent = btn

		local capturedItem = item
		wireConnection(btn.MouseButton1Click:Connect(function()
			selectedSpawnerItem = capturedItem
			playClickSmall()

			-- Highlight
			for _, child in ipairs(itemsList:GetChildren()) do
				if child:IsA("TextButton") then
					child.BackgroundColor3 = (child == btn) and Color3.fromHex("#004400") or Color3.fromHex("#222222")
				end
			end
		end))
	end

	print("[AdminPanel] Refreshed spawner list: " .. #spawnerItems .. " items")
end

function AdminPanelModule.refreshExistingList()
	local existingTab = tabContents["Existing"]
	if not existingTab then
		return
	end

	local existingList = existingTab:GetAttribute("ExistingList")
	existingList:ClearAllChildren()

	local runtimeItems = GetRuntimeItemsFunc:InvokeServer() or {}

	if #runtimeItems == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Text = "No custom items created yet."
		emptyLabel.TextSize = 12
		emptyLabel.TextColor3 = Color3.fromHex("#666666")
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Size = UDim2.fromScale(1, 0)
		emptyLabel.AutomaticSize = Enum.AutomaticSize.Y
		emptyLabel.Parent = existingList
		return
	end

	for _, item in ipairs(runtimeItems) do
		local frame = Instance.new("TextLabel")
		frame.Name = "ItemEntry_" .. item.id
		frame.Size = UDim2.fromScale(1, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.BackgroundColor3 = Color3.fromHex("#1a1a1a")
		frame.TextSize = 0
		frame.Parent = existingList

		local frameLayout = Instance.new("UIListLayout")
		frameLayout.FillDirection = Enum.FillDirection.Vertical
		frameLayout.SortOrder = Enum.SortOrder.LayoutOrder
		frameLayout.Padding = UDim.new(0, 4)
		frameLayout.Parent = frame

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingRight = UDim.new(0, 8)
		padding.PaddingTop = UDim.new(0, 6)
		padding.PaddingBottom = UDim.new(0, 6)
		padding.Parent = frame

		-- Name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Text =
			string.format('<font color="%s"><b>%s</b></font>', colorForRarity(item.rarity), item.displayName)
		nameLabel.TextSize = 12
		nameLabel.RichText = true
		nameLabel.BackgroundTransparency = 1
		nameLabel.Size = UDim2.fromScale(1, 0)
		nameLabel.AutomaticSize = Enum.AutomaticSize.Y
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = frame

		-- Details
		local detailsLabel = Instance.new("TextLabel")
		detailsLabel.Text = string.format(
			'<font color="#AAAAAA">ID: %s | Rarity: %s | Ability: %s | Creator: %s</font>',
			item.id,
			formatRarityDisplay(item.rarity),
			item.ability or "None",
			item.createdBy or "Unknown"
		)
		detailsLabel.TextSize = 10
		detailsLabel.RichText = true
		detailsLabel.BackgroundTransparency = 1
		detailsLabel.Size = UDim2.fromScale(1, 0)
		detailsLabel.AutomaticSize = Enum.AutomaticSize.Y
		detailsLabel.TextXAlignment = Enum.TextXAlignment.Left
		detailsLabel.Parent = frame
	end

	print("[AdminPanel] Refreshed existing list: " .. #runtimeItems .. " items")
end

-- ===================== MODULE API =====================

function AdminPanelModule.init(sharedRefs)
	if initialized then
		return
	end
	initialized = true

	shared = sharedRefs

	print("[AdminPanelModule] Initialized ✓")
end

function AdminPanelModule.open()
	if isOpen then
		return
	end
	isOpen = true

	-- Find or create panel frame
	local CentralizedMenu = playerGui:FindFirstChild("CentralizedAscensionMenu")
	if not CentralizedMenu then
		warn("[AdminPanel] CentralizedAscensionMenu not found")
		return
	end

	local TemporaryMenus = CentralizedMenu:FindFirstChild("TemporaryMenus")
	if not TemporaryMenus then
		warn("[AdminPanel] TemporaryMenus not found")
		return
	end

	-- Create admin panel container (appears floating)
	if not adminPanelFrame then
		adminPanelFrame = Instance.new("Frame")
		adminPanelFrame.Name = "AdminPanel"
		adminPanelFrame.Size = UDim2.fromOffset(600, 700)
		adminPanelFrame.Position = UDim2.fromScale(0.5, 0.5)
		adminPanelFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		adminPanelFrame.BackgroundColor3 = Color3.fromHex("#0a0a0a")
		adminPanelFrame.BorderColor3 = Color3.fromHex("#555555")
		adminPanelFrame.BorderSizePixel = 2
		adminPanelFrame.Parent = playerGui

		local panelLayout = Instance.new("UIListLayout")
		panelLayout.FillDirection = Enum.FillDirection.Vertical
		panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
		panelLayout.Padding = UDim.new(0, 0)
		panelLayout.Parent = adminPanelFrame

		-- ── Title Bar ──
		local titleBar = Instance.new("TextLabel")
		titleBar.Name = "TitleBar"
		titleBar.Text = "⚙ ADMIN ITEM CREATOR"
		titleBar.TextSize = 14
		titleBar.TextColor3 = Color3.fromHex("#FFFF55")
		titleBar.BackgroundColor3 = Color3.fromHex("#1a1a1a")
		titleBar.BorderColor3 = Color3.fromHex("#444444")
		titleBar.BorderSizePixel = 1
		titleBar.Size = UDim2.fromScale(1, 0)
		titleBar.AutomaticSize = Enum.AutomaticSize.Y
		titleBar.LayoutOrder = 1
		titleBar.Parent = adminPanelFrame

		local titlePadding = Instance.new("UIPadding")
		titlePadding.PaddingLeft = UDim.new(0, 12)
		titlePadding.PaddingRight = UDim.new(0, 12)
		titlePadding.PaddingTop = UDim.new(0, 8)
		titlePadding.PaddingBottom = UDim.new(0, 8)
		titlePadding.Parent = titleBar

		-- ── Tab Buttons ──
		local tabBar = Instance.new("Frame")
		tabBar.Name = "TabBar"
		tabBar.Size = UDim2.fromScale(1, 0)
		tabBar.AutomaticSize = Enum.AutomaticSize.Y
		tabBar.BackgroundColor3 = Color3.fromHex("#1a1a1a")
		tabBar.BorderColor3 = Color3.fromHex("#444444")
		tabBar.BorderSizePixel = 1
		tabBar.LayoutOrder = 2
		tabBar.Parent = adminPanelFrame

		local tabLayout = Instance.new("UIListLayout")
		tabLayout.FillDirection = Enum.FillDirection.Horizontal
		tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
		tabLayout.Padding = UDim.new(0, 2)
		tabLayout.Parent = tabBar

		local tabPadding = Instance.new("UIPadding")
		tabPadding.PaddingLeft = UDim.new(0, 8)
		tabPadding.PaddingRight = UDim.new(0, 8)
		tabPadding.PaddingTop = UDim.new(0, 6)
		tabPadding.PaddingBottom = UDim.new(0, 6)
		tabPadding.Parent = tabBar

		for _, tabName in ipairs({ "Creator", "Spawner", "Existing" }) do
			local btn = Instance.new("TextButton")
			btn.Name = tabName .. "_Tab"
			btn.Text = tabName
			btn.TextSize = 12
			btn.BackgroundColor3 = Color3.fromHex("#333333")
			btn.TextColor3 = Color3.fromHex("#AAAAAA")
			btn.BorderSizePixel = 0
			btn.Size = UDim2.fromOffset(100, 32)
			btn.Parent = tabBar

			local btnCorner = Instance.new("UICorner")
			btnCorner.CornerRadius = UDim.new(0, 4)
			btnCorner.Parent = btn

			tabButtons[tabName] = btn

			local capturedTab = tabName
			wireConnection(btn.MouseButton1Click:Connect(function()
				switchTab(capturedTab)
			end))
		end

		-- ── Content Area ──
		local contentArea = Instance.new("Frame")
		contentArea.Name = "ContentArea"
		contentArea.Size = UDim2.fromScale(1, 1)
		contentArea.BackgroundTransparency = 1
		contentArea.LayoutOrder = 3
		contentArea.Parent = adminPanelFrame

		-- Build tabs
		buildCreatorTab(Instance.new("TextLabel", contentArea))
		buildSpawnerTab(Instance.new("TextLabel", contentArea))
		buildExistingTab(Instance.new("TextLabel", contentArea))

		-- Show Creator by default
		switchTab("Creator")
	end

	adminPanelFrame.Visible = true
	print("[AdminPanel] Opened ✓")
end

function AdminPanelModule.close()
	if not isOpen then
		return
	end
	isOpen = false
	if adminPanelFrame then
		adminPanelFrame.Visible = false
	end
	clearConnections()
	print("[AdminPanel] Closed ✓")
end

function AdminPanelModule.reset()
	close()
end

print("[AdminPanelModule] Loaded ✓")
return AdminPanelModule
