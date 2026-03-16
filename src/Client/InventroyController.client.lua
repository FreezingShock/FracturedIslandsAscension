-- ============================================================
--  InventoryController (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  Client-side inventory system for Fractured Islands: Ascension.
--  Hotbar is always visible. Full inventory panel toggles with G.
--
--  Features:
--    - Slot pooling (no destroy/recreate on every update)
--    - True drag on PC (ghost follows cursor, drop on target)
--    - Tap-select on mobile
--    - TooltipModule integration (hides on click, shows on hover)
--    - Search & sort (rarity, quantity, name)
--    - Number key shortcuts for hotbar
--    - Drop-to-world by dragging to empty space
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local TooltipModule = require(Modules:WaitForChild("TooltipModule")) :: any
local ItemRegistry = require(Modules:WaitForChild("ItemRegistry")) :: any

local StarterGui = game:GetService("StarterGui")

-- Disable default Roblox backpack/inventory
local function disableDefaultBackpack()
	local success, err = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
	if not success then
		warn("[InventoryController] Failed to disable default backpack: " .. tostring(err))
	end
end

disableDefaultBackpack()
-- Re-disable on respawn (Roblox re-enables core GUI on character spawn)
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	disableDefaultBackpack()
end)

-- ===================== AUDIO =====================
local UISounds = workspace:WaitForChild("UISounds")
local UIClick = UISounds:WaitForChild("Click")
local UIClick3 = UISounds:WaitForChild("Click3")

-- Optional sounds from other game — use FindFirstChild so they don't error
local guiAudios = workspace:FindFirstChild("GUI Audios")
local selectSound1 = guiAudios and guiAudios:FindFirstChild("Select.01")
local selectSound2 = guiAudios and guiAudios:FindFirstChild("Select.02")
local filterSound = guiAudios and guiAudios:FindFirstChild("Click.03")
local equipSound = guiAudios and guiAudios:FindFirstChild("Hover.01")
local unequipSound = guiAudios and guiAudios:FindFirstChild("Click.05")

-- ===================== REMOTES =====================
local UpdateInventoryEvent = ReplicatedStorage:WaitForChild("UpdateInventory")
local PlayEquipSound = ReplicatedStorage:WaitForChild("PlayEquipSound")
local EquipToolFunc = ReplicatedStorage:WaitForChild("EquipTool")
local EquipToolByNameFunc = ReplicatedStorage:WaitForChild("EquipToolByName")
local SwapItemsFunc = ReplicatedStorage:WaitForChild("SwapItems")
local AssignHotbarFunc = ReplicatedStorage:WaitForChild("AssignHotbar")
local DropItemFunc = ReplicatedStorage:WaitForChild("DropItem")
local MoveToEndFunc = ReplicatedStorage:WaitForChild("MoveToEnd")

-- ===================== GUI REFERENCES =====================
local hotbarGui = playerGui:WaitForChild("CustomInventory")
local hotbarFrame = hotbarGui:WaitForChild("Hotbar")
local inventoryOuter = hotbarGui:WaitForChild("Inventory")
local inventoryFrame = inventoryOuter:WaitForChild("InventoryFrame")
local topBar = inventoryOuter:WaitForChild("TopBar")
local searchBox = topBar:WaitForChild("SearchBox")
local rarityButton = topBar:WaitForChild("Rarity")
local quantityButton = topBar:WaitForChild("Quantity")
local nameButton = topBar:WaitForChild("Name")
local myInventoryLabel = topBar:WaitForChild("MyInventory")
local dropButton = inventoryOuter:WaitForChild("DropButton")
local capacityLabel = inventoryOuter:WaitForChild("BackpackCapacity")
local InventoryArrow = hotbarGui:WaitForChild("InventoryArrow")
local slotTemplate = ReplicatedStorage:WaitForChild("SlotTemplate")

-- ===================== TWEEN CONFIG =====================
local TWEEN_QUINT = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_BACK_OUT = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_BACK_IN = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local TWEEN_LINEAR_FAST = TweenInfo.new(0.15, Enum.EasingStyle.Linear)

-- ===================== POSITION CONFIG =====================
local INVENTORY_SHOWN = UDim2.new(0.5, -335, 1, -400)
local INVENTORY_HIDDEN = UDim2.new(0.5, -335, 1, 50)
local TOPBAR_SHOWN = UDim2.fromOffset(4, 4)
local TOPBAR_HIDDEN = UDim2.fromOffset(4, -40)
local INVFRAME_SHOWN = UDim2.fromOffset(0, 40)
local INVFRAME_HIDDEN = UDim2.fromOffset(0, -265)
local SEARCH_SHOWN = UDim2.new(1, -204, 0, 4)
local SEARCH_HIDDEN = UDim2.new(1, 0, 0, 4)
local RARITY_SHOWN = UDim2.fromOffset(165, 5)
local RARITY_HIDDEN = UDim2.fromOffset(165, -40)
local QUANTITY_SHOWN = UDim2.fromOffset(80, 5)
local QUANTITY_HIDDEN = UDim2.fromOffset(80, -40)
local NAME_SHOWN = UDim2.fromOffset(10, 5)
local NAME_HIDDEN = UDim2.fromOffset(10, -40)
local DROPBTN_SHOWN = UDim2.new(0.5, -100, 1, -45)
local DROPBTN_HIDDEN = UDim2.new(0.5, -100, 1, 5)
local ARROW_WITH_SLOTS = UDim2.new(0.5, -50, 0.883, 0)
local ARROW_WITHOUT_SLOTS = UDim2.new(0.5, -50, 0.97, 0)
local INFOBUTTON_SHOWN = UDim2.new(1, -28, 1, -28)
local INFOBUTTON_HIDDEN = UDim2.fromScale(1, 1)

-- ===================== DRAG CONFIG =====================
local DRAG_THRESHOLD = 4 -- pixels before click becomes drag
local GHOST_TRANSPARENCY = 0.6
local HIGHLIGHT_COLOR_VALID = Color3.fromHex("#55FF55")
local HIGHLIGHT_COLOR_INVALID = Color3.fromHex("#FF5555")
local DIM_TRANSPARENCY = 0.5

-- ===================== COLOR CONFIG =====================
local DARKEN_FACTOR = 0.7
local LIGHTEN_FACTOR = 0.7
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- ===================== STATE =====================
local inventoryVisible = false
local isAnimating = false
local currentEquippedTool = nil

-- Data from server
local currentHotbarData = {} -- { [1..9] = toolInfo or false }
local currentInventoryData = {} -- { toolInfo, ... }
local currentTotalItems = 0
local currentMaxCapacity = 1000

-- Search & sort
local currentSearchText = ""
local currentSortCriterion = nil -- "rarity" | "quantity" | "name"
local currentSortState = nil -- "asc" | "desc"

-- Drag state (PC)
local dragState = nil -- { toolName, sourceFrame, isHotbar, slotIndex, ghost, startPos, isDragging }
local suppressTooltip = false

-- Mobile selection
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local mobileSelectedName = nil
local mobileSelectedSlot = nil

-- Slot pools
local hotbarSlots = {} -- [1..9] = { frame, toolInfo, hovered }
local inventoryPool = {} -- array of { frame, toolInfo, hovered, inUse }
local MAX_HOTBAR = 9

-- Active highlight during drag
local highlightedSlot = nil
local highlightOriginalColor = nil

-- ===================== SORT STATE COLORS =====================
local SORT_COLORS = {
	asc = Color3.fromHex("#FF5555"),
	desc = Color3.fromHex("#55FF55"),
	none = Color3.fromHex("#646464"),
}

local sortButtons = {
	Rarity = { button = rarityButton, stroke = rarityButton:WaitForChild("UIStroke"), criterion = "rarity" },
	Quantity = { button = quantityButton, stroke = quantityButton:WaitForChild("UIStroke"), criterion = "quantity" },
	Name = { button = nameButton, stroke = nameButton:WaitForChild("UIStroke"), criterion = "name" },
}

-- ===================== EQUIP SOUND HANDLER =====================
PlayEquipSound.OnClientEvent:Connect(function(action)
	if action == "equip" and equipSound then
		equipSound:Play()
	elseif action == "unequip" and unequipSound then
		unequipSound:Play()
	end
end)

-- ===================== TWEEN HELPERS =====================
local function tweenTo(obj, props, info)
	local tw = TweenService:Create(obj, info or TWEEN_QUINT, props)
	tw:Play()
	return tw
end

local function tweenStrokeColor(stroke, color)
	tweenTo(stroke, { Color = color }, TWEEN_QUINT)
end

-- ===================== TOOLTIP HELPERS =====================
local TOOLTIP_SOURCE = "inventory"

local function buildTooltipData(toolInfo)
	if not toolInfo then
		return nil
	end
	local rarity = toolInfo.rarity or 0
	local rarityConf = ItemRegistry.getRarity(rarity)
	local prefix = rarityConf and rarityConf.tooltipPrefix or '<font color="#AAAAAA">'
	local rarityName = rarityConf and rarityConf.name or "Common"

	local title = prefix .. "<b>" .. (toolInfo.displayName or toolInfo.name) .. "</b></font>"
	local desc = '<font color="#AAAAAA">' .. rarityName .. " — " .. tostring(toolInfo.count) .. "x</font>"

	return {
		title = title,
		desc = desc,
		click = "",
	}
end

local function showItemTooltip(toolInfo)
	if suppressTooltip or not toolInfo then
		return
	end
	local data = buildTooltipData(toolInfo)
	if data then
		TooltipModule.show(data, TOOLTIP_SOURCE)
	end
end

local function hideItemTooltip()
	TooltipModule.hide(TOOLTIP_SOURCE)
end

-- ===================== RARITY COLOR HELPERS =====================
local function _getSlotBaseColor(toolInfo)
	if not toolInfo then
		return ItemRegistry.getRarity(0).bgColor
	end
	local rarityConf = ItemRegistry.getRarity(toolInfo.rarity or 0)
	return rarityConf and rarityConf.bgColor or ItemRegistry.getRarity(0).bgColor
end

local function _getSlotBorderColor(toolInfo)
	if not toolInfo then
		return ItemRegistry.getRarity(0).color
	end
	local rarityConf = ItemRegistry.getRarity(toolInfo.rarity or 0)
	return rarityConf and rarityConf.color or ItemRegistry.getRarity(0).color
end

local function updateSlotVisual(slotFrame, toolInfo, isEquipped, isHovered)
	slotFrame.BackgroundTransparency = 0.3
	if not toolInfo then
		slotFrame.ToolName.Text = ""
		slotFrame.StackNum.Text = ""
		slotFrame.RarityLabel.Text = ""
		slotFrame.UIStroke.Color = ItemRegistry.getRarity(0).color
		slotFrame.BackgroundColor3 = ItemRegistry.getRarity(0).bgColor
		return
	end

	local rarityConf = ItemRegistry.getRarity(toolInfo.rarity or 0)
	slotFrame.ToolName.Text = toolInfo.displayName or toolInfo.name
	slotFrame.StackNum.Text = tostring(toolInfo.count) .. "x"
	slotFrame.RarityLabel.Text = rarityConf.display
	slotFrame.RarityLabel.TextColor3 = rarityConf.color
	slotFrame.UIStroke.Color = rarityConf.color

	local baseColor = rarityConf.bgColor
	if isEquipped then
		baseColor = baseColor:Lerp(BLACK, DARKEN_FACTOR)
	end
	if isHovered then
		baseColor = baseColor:Lerp(WHITE, LIGHTEN_FACTOR)
	end
	slotFrame.BackgroundColor3 = baseColor
end

-- ===================== HOTBAR SLOT CREATION (once) =====================
local function createHotbarSlots()
	for i = 1, MAX_HOTBAR do
		local newSlot = slotTemplate:Clone()
		newSlot.Name = "Slot" .. i
		newSlot.LayoutOrder = i
		newSlot.SlotNum.Text = tostring(i)
		newSlot.Parent = hotbarFrame
		newSlot.Visible = false
		newSlot.Swap.Visible = false

		local slotData = {
			frame = newSlot,
			toolInfo = nil,
			hovered = false,
		}
		hotbarSlots[i] = slotData

		-- ── Hover ──
		newSlot.MouseEnter:Connect(function()
			slotData.hovered = true
			local isEq = currentEquippedTool
				and slotData.toolInfo
				and currentEquippedTool.Name == slotData.toolInfo.name
			updateSlotVisual(newSlot, slotData.toolInfo, isEq, true)
			if slotData.toolInfo then
				showItemTooltip(slotData.toolInfo)
			end
		end)

		newSlot.MouseLeave:Connect(function()
			slotData.hovered = false
			local isEq = currentEquippedTool
				and slotData.toolInfo
				and currentEquippedTool.Name == slotData.toolInfo.name
			updateSlotVisual(newSlot, slotData.toolInfo, isEq, false)
			hideItemTooltip()
		end)
	end
end

-- ===================== INVENTORY SLOT POOL =====================
local function getOrCreateInventorySlot(index)
	if inventoryPool[index] then
		return inventoryPool[index]
	end

	local newSlot = slotTemplate:Clone()
	newSlot.Name = "InventorySlot" .. index
	newSlot.SlotNum.Visible = false
	newSlot.Parent = inventoryFrame
	newSlot.Visible = false
	newSlot.Swap.Visible = false

	local slotData = {
		frame = newSlot,
		toolInfo = nil,
		hovered = false,
		inUse = false,
	}
	inventoryPool[index] = slotData

	-- ── Hover (wired once) ──
	newSlot.MouseEnter:Connect(function()
		slotData.hovered = true
		if slotData.toolInfo then
			local rarityConf = ItemRegistry.getRarity(slotData.toolInfo.rarity or 0)
			newSlot.BackgroundColor3 = rarityConf.bgColor:Lerp(WHITE, LIGHTEN_FACTOR)
			showItemTooltip(slotData.toolInfo)
		end
	end)

	newSlot.MouseLeave:Connect(function()
		slotData.hovered = false
		if slotData.toolInfo then
			local rarityConf = ItemRegistry.getRarity(slotData.toolInfo.rarity or 0)
			newSlot.BackgroundColor3 = rarityConf.bgColor
		end
		hideItemTooltip()
	end)

	return slotData
end

-- ===================== FILTER & SORT =====================
local function getFilteredInventory()
	local result = {}
	for _, toolInfo in ipairs(currentInventoryData) do
		local name = (toolInfo.displayName or toolInfo.name):lower()
		if currentSearchText == "" or name:find(currentSearchText, 1, true) then
			table.insert(result, toolInfo)
		end
	end

	if currentSortCriterion and currentSortState then
		local comparator
		if currentSortCriterion == "rarity" then
			comparator = function(a, b)
				return a.rarity < b.rarity
			end
		elseif currentSortCriterion == "quantity" then
			comparator = function(a, b)
				return a.count < b.count
			end
		elseif currentSortCriterion == "name" then
			comparator = function(a, b)
				return (a.displayName or a.name) < (b.displayName or b.name)
			end
		end
		if comparator then
			if currentSortState == "desc" then
				table.sort(result, function(a, b)
					return comparator(b, a)
				end)
			else
				table.sort(result, comparator)
			end
		end
	end

	return result
end

-- ===================== REFRESH DISPLAY =====================
local function refreshHotbar()
	for i = 1, MAX_HOTBAR do
		local slotData = hotbarSlots[i]
		local toolInfo = currentHotbarData[i]
		local hasItem = (type(toolInfo) == "table" and toolInfo.name ~= nil)

		slotData.toolInfo = hasItem and toolInfo or nil

		local isEq = currentEquippedTool and hasItem and currentEquippedTool.Name == toolInfo.name
		updateSlotVisual(slotData.frame, slotData.toolInfo, isEq, slotData.hovered)

		slotData.frame.Visible = hasItem
	end
end

local function refreshInventory()
	if not inventoryVisible then
		return
	end

	local filtered = getFilteredInventory()

	-- Update pool slots
	for i, toolInfo in ipairs(filtered) do
		local slotData = getOrCreateInventorySlot(i)
		slotData.toolInfo = toolInfo
		slotData.inUse = true

		local rarityConf = ItemRegistry.getRarity(toolInfo.rarity or 0)
		slotData.frame.ToolName.Text = toolInfo.displayName or toolInfo.name
		slotData.frame.StackNum.Text = tostring(toolInfo.count) .. "x"
		slotData.frame.RarityLabel.Text = rarityConf.display
		slotData.frame.RarityLabel.TextColor3 = rarityConf.color
		slotData.frame.UIStroke.Color = rarityConf.color
		slotData.frame.BackgroundColor3 = slotData.hovered and rarityConf.bgColor:Lerp(WHITE, LIGHTEN_FACTOR)
			or rarityConf.bgColor
		slotData.frame.Visible = true
		slotData.frame.Swap.Visible = false
	end

	-- Hide unused pool slots
	for i = #filtered + 1, #inventoryPool do
		local slotData = inventoryPool[i]
		slotData.toolInfo = nil
		slotData.inUse = false
		slotData.frame.Visible = false
	end

	capacityLabel.Text = tostring(currentTotalItems) .. "/" .. tostring(currentMaxCapacity)
end

local function refreshAll()
	refreshHotbar()
	refreshInventory()
end

-- Show all 9 hotbar slots (including empty) during drag so player can drop into any
local function _showAllHotbarSlots()
	for i = 1, MAX_HOTBAR do
		hotbarSlots[i].frame.Visible = true
	end
end

-- ===================== EQUIP TRACKING =====================
local function setupCharacterEquipTracking(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			currentEquippedTool = child
			refreshHotbar()
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child == currentEquippedTool then
			currentEquippedTool = nil
			refreshHotbar()
		end
	end)
end

if player.Character then
	setupCharacterEquipTracking(player.Character)
end
player.CharacterAdded:Connect(setupCharacterEquipTracking)

-- ===================== DRAG SYSTEM (PC) =====================

--- Find which slot (hotbar or inventory) is under the given screen position.
--- Returns: slotData, isHotbar, slotIndex (or nil if nothing)
local function findSlotAtPosition(screenPos)
	-- Check hotbar slots
	for i = 1, MAX_HOTBAR do
		local slotData = hotbarSlots[i]
		if slotData.frame.Visible then
			local absPos = slotData.frame.AbsolutePosition
			local absSize = slotData.frame.AbsoluteSize
			if
				screenPos.X >= absPos.X
				and screenPos.X <= absPos.X + absSize.X
				and screenPos.Y >= absPos.Y
				and screenPos.Y <= absPos.Y + absSize.Y
			then
				return slotData, true, i
			end
		end
	end

	-- Check inventory slots
	if inventoryVisible then
		for i, slotData in ipairs(inventoryPool) do
			if slotData.inUse and slotData.frame.Visible then
				local absPos = slotData.frame.AbsolutePosition
				local absSize = slotData.frame.AbsoluteSize
				if
					screenPos.X >= absPos.X
					and screenPos.X <= absPos.X + absSize.X
					and screenPos.Y >= absPos.Y
					and screenPos.Y <= absPos.Y + absSize.Y
				then
					return slotData, false, i
				end
			end
		end
	end

	return nil, nil, nil
end

--- Check if screen position is over inventory frame (but not on a slot)
local function isOverInventoryArea(screenPos)
	if not inventoryVisible then
		return false
	end
	local absPos = inventoryFrame.AbsolutePosition
	local absSize = inventoryFrame.AbsoluteSize
	return screenPos.X >= absPos.X
		and screenPos.X <= absPos.X + absSize.X
		and screenPos.Y >= absPos.Y
		and screenPos.Y <= absPos.Y + absSize.Y
end

local function _clearDragHighlight()
	if highlightedSlot and highlightOriginalColor then
		highlightedSlot.UIStroke.Color = highlightOriginalColor
		highlightedSlot = nil
		highlightOriginalColor = nil
	end
end

local function _setDragHighlight(slotFrame, valid)
	_clearDragHighlight()
	highlightedSlot = slotFrame
	highlightOriginalColor = slotFrame.UIStroke.Color
	slotFrame.UIStroke.Color = valid and HIGHLIGHT_COLOR_VALID or HIGHLIGHT_COLOR_INVALID
end

local function _createDragGhost(sourceFrame)
	local ghost = sourceFrame:Clone()
	ghost.Name = "DragGhost"
	ghost.Parent = hotbarGui
	ghost.ZIndex = 100
	ghost.BackgroundTransparency = GHOST_TRANSPARENCY
	-- Force pixel size from source so it matches exactly regardless of parent
	local absSize = sourceFrame.AbsoluteSize
	ghost.Size = UDim2.fromOffset(absSize.X, absSize.Y)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Make all children semi-transparent too
	for _, child in ipairs(ghost:GetDescendants()) do
		if child:IsA("GuiObject") then
			if child.BackgroundTransparency < 1 then
				child.BackgroundTransparency = math.max(child.BackgroundTransparency, GHOST_TRANSPARENCY)
			end
		end
	end

	-- Remove interactivity
	for _, child in ipairs(ghost:GetDescendants()) do
		if child:IsA("GuiButton") then
			child.Active = false
		end
	end

	return ghost
end

local function _cleanupDrag()
	if dragState then
		-- Restore source slot opacity
		if dragState.sourceFrame then
			dragState.sourceFrame.BackgroundTransparency = 0
		end
		-- Destroy ghost
		if dragState.ghost then
			dragState.ghost:Destroy()
		end
		dragState = nil
	end
	_clearDragHighlight()
	-- Re-hide empty hotbar slots now that drag is over
	refreshHotbar()
end

local function _startDragOnSlot(toolInfo, slotFrame, isHotbar, slotIndex, mousePos)
	if not toolInfo then
		return
	end

	-- ── Block drag when inventory panel is closed ──
	-- Still allow immediate equip via click path
	if not inventoryVisible then
		if isHotbar and slotIndex then
			EquipToolFunc:InvokeServer(slotIndex)
		else
			EquipToolByNameFunc:InvokeServer(toolInfo.name)
		end
		UIClick:Play()
		return
	end

	suppressTooltip = true
	TooltipModule.forceHide()

	dragState = {
		toolName = toolInfo.name,
		sourceFrame = slotFrame,
		isHotbar = isHotbar,
		slotIndex = slotIndex,
		ghost = nil,
		startPos = mousePos,
		isDragging = false,
	}

	-- Reveal all 9 hotbar slots so player can target empty ones
	_showAllHotbarSlots()
end

local function onDragMove(mousePos)
	if not dragState then
		return
	end

	if not dragState.isDragging then
		local dist = (mousePos - dragState.startPos).Magnitude
		if dist < DRAG_THRESHOLD then
			return
		end
		-- Threshold exceeded — enter drag mode
		dragState.isDragging = true
		dragState.ghost = _createDragGhost(dragState.sourceFrame)
		dragState.sourceFrame.BackgroundTransparency = DIM_TRANSPARENCY
	end

	-- Move ghost — input.Position is viewport-relative, but ScreenGui uses
	-- IgnoreGuiInset=true (coordinate origin at screen top), so add inset.Y
	if dragState.ghost then
		local inset = GuiService:GetGuiInset()
		dragState.ghost.Position = UDim2.fromOffset(mousePos.X, mousePos.Y + inset.Y)
	end

	-- Highlight drop target — AbsolutePosition is in raw screen coords too
	local adjustedPos = Vector2.new(mousePos.X, mousePos.Y)
	local targetSlot, _, _ = findSlotAtPosition(adjustedPos)
	if targetSlot and targetSlot.frame ~= dragState.sourceFrame then
		_setDragHighlight(targetSlot.frame, true)
	else
		_clearDragHighlight()
	end
end

local function onDragEnd(mousePos)
	if not dragState then
		suppressTooltip = false
		return
	end

	local wasDragging = dragState.isDragging
	local toolName = dragState.toolName
	local sourceIsHotbar = dragState.isHotbar
	local sourceSlotIndex = dragState.slotIndex

	-- ── HIT TEST BEFORE CLEANUP ──
	-- _cleanupDrag calls refreshHotbar which hides empty hotbar slots.
	-- We must capture the drop target while they're still visible.
	local targetSlot, targetIsHotbar, targetSlotIndex
	local overInventory = false
	if wasDragging then
		local adjustedPos = Vector2.new(mousePos.X, mousePos.Y)
		targetSlot, targetIsHotbar, targetSlotIndex = findSlotAtPosition(adjustedPos)
		overInventory = isOverInventoryArea(adjustedPos)
	end

	_cleanupDrag()
	suppressTooltip = false

	if not wasDragging then
		-- Was a click, not a drag — equip/toggle
		if sourceIsHotbar and sourceSlotIndex then
			EquipToolFunc:InvokeServer(sourceSlotIndex)
		else
			EquipToolByNameFunc:InvokeServer(toolName)
		end
		UIClick:Play()
		return
	end

	-- ── RESOLVE DROP ACTION using pre-captured target ──
	if targetSlot and targetSlot.toolInfo then
		-- Drop on occupied slot → swap
		SwapItemsFunc:InvokeServer(toolName, targetSlot.toolInfo.name)
		if selectSound2 then
			selectSound2:Play()
		end
	elseif targetSlot and targetIsHotbar and not targetSlot.toolInfo then
		-- Drop on empty hotbar slot → assign
		AssignHotbarFunc:InvokeServer(targetSlotIndex, toolName)
		if selectSound2 then
			selectSound2:Play()
		end
	elseif overInventory then
		-- Dropped on inventory area but not on a slot
		if sourceIsHotbar then
			MoveToEndFunc:InvokeServer(toolName)
			if selectSound2 then
				selectSound2:Play()
			end
		end
	else
		-- Dropped on empty space → drop to world
		DropItemFunc:InvokeServer(toolName)
		UIClick:Play()
	end
end

-- ===================== MOBILE TAP SYSTEM =====================
local function clearMobileSelection()
	if mobileSelectedSlot then
		mobileSelectedSlot.Swap.Visible = false
	end
	mobileSelectedName = nil
	mobileSelectedSlot = nil
end

local function handleMobileTap(toolInfo, slotFrame, isHotbar, slotIndex)
	if not toolInfo then
		-- Tapped empty hotbar slot while something selected → assign
		if mobileSelectedName and isHotbar and slotIndex then
			AssignHotbarFunc:InvokeServer(slotIndex, mobileSelectedName)
			if selectSound2 then
				selectSound2:Play()
			end
			clearMobileSelection()
		else
			clearMobileSelection()
		end
		return
	end

	if mobileSelectedName then
		if mobileSelectedName == toolInfo.name then
			-- Tapped same item → deselect
			clearMobileSelection()
		else
			-- Tapped different item → swap
			SwapItemsFunc:InvokeServer(mobileSelectedName, toolInfo.name)
			if selectSound2 then
				selectSound2:Play()
			end
			clearMobileSelection()
		end
	else
		-- Nothing selected → select this item
		if selectSound1 then
			selectSound1:Play()
		end
		mobileSelectedName = toolInfo.name
		mobileSelectedSlot = slotFrame
		slotFrame.Swap.Visible = true
	end
end

-- ===================== SLOT INPUT WIRING =====================
-- Wire click/drag handlers on hotbar slots (once at creation)
local function wireHotbarSlotInput(slotIndex)
	local slotData = hotbarSlots[slotIndex]
	local selectBtn = slotData.frame:WaitForChild("Select")

	selectBtn.MouseButton1Down:Connect(function()
		if not slotData.toolInfo then
			-- Empty slot — if mobile and has selection, assign
			if isMobile and mobileSelectedName then
				AssignHotbarFunc:InvokeServer(slotIndex, mobileSelectedName)
				if selectSound2 then
					selectSound2:Play()
				end
				clearMobileSelection()
			end
			return
		end

		if isMobile then
			handleMobileTap(slotData.toolInfo, slotData.frame, true, slotIndex)
			return
		end

		-- PC: start potential drag (use raw screen coords to match InputChanged)
		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		_startDragOnSlot(slotData.toolInfo, slotData.frame, true, slotIndex, mousePos)
	end)
end

-- Wire inventory pool slot input (called once per pool slot creation)
local function wireInventorySlotInput(poolIndex)
	local slotData = inventoryPool[poolIndex]
	local selectBtn = slotData.frame:WaitForChild("Select")

	selectBtn.MouseButton1Down:Connect(function()
		if not slotData.toolInfo then
			return
		end

		if isMobile then
			handleMobileTap(slotData.toolInfo, slotData.frame, false, poolIndex)
			return
		end

		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		_startDragOnSlot(slotData.toolInfo, slotData.frame, false, poolIndex, mousePos)
	end)
end

-- Patch getOrCreateInventorySlot to wire input on creation
local _originalGetOrCreate = getOrCreateInventorySlot
getOrCreateInventorySlot = function(index)
	local existed = inventoryPool[index] ~= nil
	local slotData = _originalGetOrCreate(index)
	if not existed then
		wireInventorySlotInput(index)
	end
	return slotData
end

-- ===================== GLOBAL INPUT (drag tracking) =====================
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and dragState then
		onDragMove(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and dragState then
		onDragEnd(Vector2.new(input.Position.X, input.Position.Y))
	end
end)

-- ===================== TOOLTIP SUPPRESSION ON CLICK =====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		suppressTooltip = true
		TooltipModule.forceHide()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		suppressTooltip = false
		-- Re-show tooltip if hovering over a slot
		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local adjustedPos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		local slotData = findSlotAtPosition(adjustedPos)
		if slotData and slotData.toolInfo and not dragState then
			showItemTooltip(slotData.toolInfo)
		end
	end
end)

-- ===================== INVENTORY ARROW =====================
local arrowMoving = false
local lastArrowTarget = nil

local function updateArrowPosition()
	if arrowMoving then
		return
	end
	local hasVisibleSlot = false
	for i = 1, MAX_HOTBAR do
		if hotbarSlots[i] and hotbarSlots[i].frame.Visible then
			hasVisibleSlot = true
			break
		end
	end
	local target = hasVisibleSlot and ARROW_WITH_SLOTS or ARROW_WITHOUT_SLOTS
	if lastArrowTarget == target then
		return
	end
	lastArrowTarget = target
	arrowMoving = true
	local tw = tweenTo(InventoryArrow, { Position = target }, TWEEN_QUINT)
	tw.Completed:Once(function()
		arrowMoving = false
	end)
end

-- ===================== DROP BUTTON (mobile fallback) =====================
local dropBtnVisible = false

local function showDropButton()
	if dropBtnVisible then
		return
	end
	dropBtnVisible = true
	dropButton.Visible = true
	tweenTo(dropButton, { Position = DROPBTN_SHOWN }, TWEEN_BACK_OUT)
end

local function hideDropButton()
	if not dropBtnVisible then
		return
	end
	dropBtnVisible = false
	local tw = tweenTo(dropButton, { Position = DROPBTN_HIDDEN }, TWEEN_BACK_IN)
	tw.Completed:Once(function()
		if not dropBtnVisible then
			dropButton.Visible = false
		end
	end)
end

local function updateDropButton()
	if mobileSelectedSlot and mobileSelectedSlot.Parent == hotbarFrame then
		showDropButton()
	else
		hideDropButton()
	end
end

dropButton.MouseButton1Click:Connect(function()
	if mobileSelectedName and mobileSelectedSlot and mobileSelectedSlot.Parent == hotbarFrame then
		MoveToEndFunc:InvokeServer(mobileSelectedName)
		if selectSound2 then
			selectSound2:Play()
		end
		clearMobileSelection()
		updateDropButton()
	end
end)

-- ===================== OPEN / CLOSE INVENTORY =====================
local function openInventory()
	if isAnimating or inventoryVisible then
		return
	end
	isAnimating = true
	inventoryVisible = true
	UIClick:Play()

	inventoryOuter.Visible = true
	refreshAll()

	-- Staggered reveal using Completed callbacks
	tweenTo(
		inventoryOuter,
		{ Position = INVENTORY_SHOWN },
		TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.InOut)
	)
	task.delay(0.2, function()
		tweenTo(topBar, { Position = TOPBAR_SHOWN }, TWEEN_BACK_OUT)
	end)
	task.delay(0.3, function()
		tweenTo(inventoryFrame, { Position = INVFRAME_SHOWN }, TWEEN_QUINT)
	end)
	task.delay(0.5, function()
		tweenTo(rarityButton, { Position = RARITY_SHOWN }, TWEEN_BACK_OUT)
		if filterSound then
			filterSound:Play()
		end
	end)
	task.delay(0.55, function()
		tweenTo(quantityButton, { Position = QUANTITY_SHOWN }, TWEEN_BACK_OUT)
		if filterSound then
			filterSound:Play()
		end
	end)
	task.delay(0.6, function()
		tweenTo(nameButton, { Position = NAME_SHOWN }, TWEEN_BACK_OUT)
		if filterSound then
			filterSound:Play()
		end
	end)
	task.delay(0.65, function()
		local tw = tweenTo(searchBox, { Position = SEARCH_SHOWN }, TWEEN_BACK_OUT)
		if filterSound then
			filterSound:Play()
		end
		tw.Completed:Once(function()
			isAnimating = false
		end)
	end)

	local arrowTween = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tweenTo(InventoryArrow, { Rotation = 180 }, arrowTween)
	updateArrowPosition()
end

local function closeInventory()
	if isAnimating or not inventoryVisible then
		return
	end
	isAnimating = true
	inventoryVisible = false
	UIClick:Play()

	-- Clear selection state
	clearMobileSelection()
	hideDropButton()
	_cleanupDrag()
	TooltipModule.forceHide()

	tweenTo(
		inventoryOuter,
		{ Position = INVENTORY_HIDDEN },
		TweenInfo.new(1.0, Enum.EasingStyle.Back, Enum.EasingDirection.InOut)
	)
	task.delay(0.1, function()
		tweenTo(rarityButton, { Position = RARITY_HIDDEN }, TWEEN_BACK_IN)
		tweenTo(quantityButton, { Position = QUANTITY_HIDDEN }, TWEEN_BACK_IN)
		tweenTo(nameButton, { Position = NAME_HIDDEN }, TWEEN_BACK_IN)
		tweenTo(searchBox, { Position = SEARCH_HIDDEN }, TWEEN_BACK_IN)
	end)
	task.delay(0.15, function()
		tweenTo(topBar, { Position = TOPBAR_HIDDEN }, TWEEN_BACK_IN)
	end)
	task.delay(0.2, function()
		tweenTo(inventoryFrame, { Position = INVFRAME_HIDDEN }, TWEEN_QUINT)
	end)

	local arrowTween = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tweenTo(InventoryArrow, { Rotation = 0 }, arrowTween)

	task.delay(1.0, function()
		if not inventoryVisible then
			inventoryOuter.Visible = false
			isAnimating = false
		end
	end)

	refreshHotbar()
	updateArrowPosition()
end

local function toggleInventory()
	if inventoryVisible then
		closeInventory()
	else
		openInventory()
	end
end

-- ===================== SEARCH BOX =====================
searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	currentSearchText = searchBox.Text:lower()
	if inventoryVisible then
		refreshInventory()
	end
end)

-- ===================== SORT BUTTONS =====================
for _, btnInfo in pairs(sortButtons) do
	btnInfo.button.MouseButton1Click:Connect(function()
		local criterion = btnInfo.criterion
		if currentSortCriterion == criterion then
			if currentSortState == "desc" then
				currentSortState = "asc"
			elseif currentSortState == "asc" then
				currentSortState = nil
				currentSortCriterion = nil
			end
		else
			currentSortCriterion = criterion
			currentSortState = "desc"
		end
		UIClick:Play()

		-- Update stroke colors
		for _, otherBtn in pairs(sortButtons) do
			local color = (otherBtn.criterion == currentSortCriterion and currentSortState)
					and SORT_COLORS[currentSortState]
				or SORT_COLORS.none
			tweenStrokeColor(otherBtn.stroke, color)
		end

		if inventoryVisible then
			refreshInventory()
		end
	end)
end

-- ===================== INVENTORY ARROW CLICK =====================
InventoryArrow.MouseButton1Click:Connect(function()
	if isAnimating then
		return
	end
	toggleInventory()
end)

-- ===================== SERVER DATA HANDLER =====================
UpdateInventoryEvent.OnClientEvent:Connect(function(data)
	currentHotbarData = data.hotbar or {}
	currentInventoryData = data.inventory or {}
	currentTotalItems = data.total_items or 0
	currentMaxCapacity = data.max_capacity or 1000

	refreshAll()
	updateArrowPosition()
	updateDropButton()
end)

-- ===================== KEY BINDINGS =====================
local keyToSlot = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local key = input.KeyCode

	-- G key → toggle inventory
	if key == Enum.KeyCode.G then
		if not isAnimating then
			toggleInventory()
		end
		return
	end

	-- Number keys → equip hotbar slot (or assign if mobile selected)
	local slotIndex = keyToSlot[key]
	if slotIndex then
		if mobileSelectedName then
			-- Mobile selection active → assign to hotbar
			local targetInfo = currentHotbarData[slotIndex]
			if type(targetInfo) == "table" and targetInfo.name and targetInfo.name ~= mobileSelectedName then
				SwapItemsFunc:InvokeServer(mobileSelectedName, targetInfo.name)
			elseif not targetInfo or targetInfo == false then
				AssignHotbarFunc:InvokeServer(slotIndex, mobileSelectedName)
			end
			if selectSound2 then
				selectSound2:Play()
			end
			clearMobileSelection()
			updateDropButton()
		else
			EquipToolFunc:InvokeServer(slotIndex)
		end
	end
end)

-- ===================== INITIAL STATE =====================
createHotbarSlots()
for i = 1, MAX_HOTBAR do
	wireHotbarSlotInput(i)
end

hotbarFrame.Visible = true
inventoryOuter.Visible = false
dropButton.Visible = false

-- Initialize sort button strokes
for _, btnInfo in pairs(sortButtons) do
	btnInfo.stroke.Color = SORT_COLORS.none
end

-- Position elements in hidden state
inventoryOuter.Position = INVENTORY_HIDDEN
topBar.Position = TOPBAR_HIDDEN
inventoryFrame.Position = INVFRAME_HIDDEN
searchBox.Position = SEARCH_HIDDEN
rarityButton.Position = RARITY_HIDDEN
quantityButton.Position = QUANTITY_HIDDEN
nameButton.Position = NAME_HIDDEN
dropButton.Position = DROPBTN_HIDDEN

-- Arrow position poll (lightweight, no RenderStepped)
task.spawn(function()
	while true do
		updateArrowPosition()
		task.wait(0.5)
	end
end)

print("[InventoryController] Ready ✓")
