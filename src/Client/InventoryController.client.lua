-- ============================================================
--  InventoryController (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  Client-side inventory system for Fractured Islands: Ascension.
--
--  REWRITTEN: Inventory slots now live inside the CentralizedMenu's
--  Inventory frame (innerFrame > Inventory > InventoryFrame).
--  Hotbar stays in CustomInventory ScreenGui.
--  Slot 9 is a permanent "Menu" button that opens the full Nexus menu.
--  E key toggles inventory-only mode.
--  Drag works cross-ScreenGui via AbsolutePosition hit testing.
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
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any
local LiquidGlassHandler = require(Modules:WaitForChild("LiquidGlassHandler")) :: any

local StarterGui = game:GetService("StarterGui")

-- Disable default Roblox backpack/inventory
local function disableDefaultBackpack()
	local success, _ = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)
end

disableDefaultBackpack()
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	disableDefaultBackpack()
end)

-- ===================== AUDIO =====================
local UISounds = workspace:WaitForChild("UISounds")
local UIClick = UISounds:WaitForChild("Click")
local UIClick3 = UISounds:WaitForChild("Click3")

local guiAudios = workspace:FindFirstChild("GUI Audios")
local selectSound1 = guiAudios and guiAudios:FindFirstChild("Select.01")
local selectSound2 = guiAudios and guiAudios:FindFirstChild("Select.02")
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

-- ===================== GUI REFERENCES — HOTBAR (CustomInventory) =====================
local hotbarGui = playerGui:WaitForChild("CustomInventory")
local hotbarFrame = hotbarGui:WaitForChild("Hotbar")
local hotbarBB = hotbarFrame:WaitForChild("HotbarBB")
local hotbarFrames = hotbarBB:WaitForChild("HotbarFrames")
local slotTemplate = ReplicatedStorage:WaitForChild("SlotTemplate")

-- ===================== GUI REFERENCES — INVENTORY (inside CentralizedMenu) =====================
local centralizedMenu = playerGui:WaitForChild("CentralizedAscensionMenu")
local boundingBox = centralizedMenu:WaitForChild("BoundingBox")
local outerFrame = boundingBox:WaitForChild("outerFrame")
local innerFrame = outerFrame:WaitForChild("innerFrame")
local inventoryPanel = innerFrame:WaitForChild("Inventory")
local inventoryFrame = inventoryPanel:WaitForChild("InventoryFrame")
local capacityLabel = inventoryPanel:WaitForChild("BackpackCapacity")

-- ===================== GUI REFERENCES — TRANSFER FRAME =====================
local transferContainer = hotbarGui:WaitForChild("Transfer")
local transferFrame = transferContainer:WaitForChild("TransferFrame")
local transferLabel = transferFrame:WaitForChild("TransferLabel")
local transferBG = transferFrame:WaitForChild("BG")

-- ===================== TWEEN CONFIG =====================
local TWEEN_QUINT = TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ===================== DRAG CONFIG =====================
local DRAG_THRESHOLD = 4
local GHOST_TRANSPARENCY = 0.6
local HIGHLIGHT_COLOR_VALID = Color3.fromHex("#55FF55")
local DIM_TRANSPARENCY = 0.5

-- ===================== TRANSFER FRAME CONFIG =====================
local TRANSFER_POS_HIDDEN = UDim2.fromScale(0.5, 1.5)
local TRANSFER_POS_SHOWN = UDim2.fromScale(0.5, 0.5)
local transferTweenIn = TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local transferTweenOut = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local transferColorTween = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local TRANSFER_DEFAULT_COLOR = Color3.fromHex("#FFAA00")
local TRANSFER_DEFAULT_TEXT = Color3.fromHex("#FFFF55")
local TRANSFER_HOVER_COLOR = Color3.fromHex("#00AA00")
local TRANSFER_HOVER_TEXT = Color3.fromHex("#55FF55")

local transferVisible = false
local transferHovered = false
local transferSlideTween = nil

-- ===================== COLOR CONFIG =====================
local DARKEN_FACTOR = 0.7
local LIGHTEN_FACTOR = 0.7
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)

-- ===================== TRANSFER FRAME FUNCTIONS =====================
local function _setTransferColors(frameColor, textColor, instant)
	if instant then
		transferFrame.BackgroundColor3 = frameColor
		transferBG.ImageColor3 = frameColor
		transferFrame.UIStroke.Color = frameColor
		transferLabel.UIStroke.Color = frameColor
		transferLabel.TextColor3 = textColor
		return
	end
	TweenService:Create(transferFrame, transferColorTween, { BackgroundColor3 = frameColor }):Play()
	TweenService:Create(transferBG, transferColorTween, { ImageColor3 = frameColor }):Play()
	TweenService:Create(transferFrame.UIStroke, transferColorTween, { Color = frameColor }):Play()
	TweenService:Create(transferLabel.UIStroke, transferColorTween, { Color = frameColor }):Play()
	TweenService:Create(transferLabel, transferColorTween, { TextColor3 = textColor }):Play()
end

local function _showTransferFrame()
	if transferVisible then
		return
	end
	transferVisible = true
	transferHovered = false
	transferLabel.Text = "Transfer to Inventory"
	_setTransferColors(TRANSFER_DEFAULT_COLOR, TRANSFER_DEFAULT_TEXT, true)
	transferContainer.Visible = true
	transferFrame.Position = TRANSFER_POS_HIDDEN
	if transferSlideTween then
		transferSlideTween:Cancel()
	end
	transferSlideTween = TweenService:Create(transferFrame, transferTweenIn, { Position = TRANSFER_POS_SHOWN })
	transferSlideTween:Play()
end

local function _hideTransferFrame()
	if not transferVisible then
		return
	end
	transferVisible = false
	transferHovered = false
	if transferSlideTween then
		transferSlideTween:Cancel()
	end
	transferSlideTween = TweenService:Create(transferFrame, transferTweenOut, { Position = TRANSFER_POS_HIDDEN })
	transferSlideTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and not transferVisible then
			transferContainer.Visible = false
		end
	end)
	transferSlideTween:Play()
end

local function _isOverTransferFrame(screenPos)
	if not transferVisible then
		return false
	end
	local absPos = transferFrame.AbsolutePosition
	local absSize = transferFrame.AbsoluteSize
	return screenPos.X >= absPos.X
		and screenPos.X <= absPos.X + absSize.X
		and screenPos.Y >= absPos.Y
		and screenPos.Y <= absPos.Y + absSize.Y
end

local function _updateTransferHover(isHovered)
	if isHovered == transferHovered then
		return
	end
	transferHovered = isHovered
	if isHovered then
		transferLabel.Text = "Complete Transfer"
		_setTransferColors(TRANSFER_HOVER_COLOR, TRANSFER_HOVER_TEXT, false)
	else
		transferLabel.Text = "Transfer to Inventory"
		_setTransferColors(TRANSFER_DEFAULT_COLOR, TRANSFER_DEFAULT_TEXT, false)
	end
end

-- ===================== STATE =====================
local inventoryVisible = false
local currentEquippedTool = nil

-- Data from server
local currentHotbarData = {} -- { [1..9] = toolInfo or false }
local currentInventoryData = {} -- { toolInfo, ... }
local currentTotalItems = 0
local currentMaxCapacity = 1000

-- Drag state (PC)
local dragState = nil
local suppressTooltip = false

-- Mobile selection
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local mobileSelectedName = nil
local mobileSelectedSlot = nil

-- Slot pools
local hotbarSlots = {} -- [1..9] = { frame, toolInfo, hovered }
local inventoryPool = {} -- array of { frame, toolInfo, hovered, inUse }
local MAX_HOTBAR = 9
local MENU_SLOT = 9 -- Slot 9 is permanently "Menu"

-- Active highlight during drag
local highlightedSlot = nil
local highlightOriginalColor = nil

transferContainer.Visible = false
transferFrame.Position = TRANSFER_POS_HIDDEN

-- ===================== EQUIP SOUND HANDLER =====================
PlayEquipSound.OnClientEvent:Connect(function(action)
	if action == "equip" and equipSound then
		equipSound:Play()
	elseif action == "unequip" and unequipSound then
		unequipSound:Play()
	end
end)

-- ===================== TWEEN HELPERS =====================
local function _tweenTo(obj, props, info)
	local tw = TweenService:Create(obj, info or TWEEN_QUINT, props)
	tw:Play()
	return tw
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

	return { title = title, desc = desc, click = "" }
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

-- ===================== SLOT VISUAL HELPERS =====================
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

-- ===================== SLOT 9 — PERMANENT MENU BUTTON =====================
local function setupMenuSlot(slotFrame)
	local mythicConf = ItemRegistry.getRarity(6) -- Mythic
	slotFrame.ToolName.Text = "Menu"
	slotFrame.StackNum.Text = ""
	slotFrame.RarityLabel.Text = mythicConf.display
	slotFrame.RarityLabel.TextColor3 = mythicConf.color
	slotFrame.UIStroke.Color = mythicConf.color
	slotFrame.BackgroundColor3 = mythicConf.bgColor
	slotFrame.BackgroundTransparency = 0.3
	slotFrame.SlotNum.Text = "C"
	slotFrame.Visible = true
end

-- ===================== HOTBAR SLOT CREATION (once) =====================
local function createHotbarSlots()
	for i = 1, MAX_HOTBAR do
		local newSlot = slotTemplate:Clone()
		newSlot.Name = "Slot" .. i
		newSlot.LayoutOrder = i
		newSlot.SlotNum.Text = tostring(i)
		newSlot.Parent = hotbarFrames
		newSlot.Visible = false
		newSlot.Swap.Visible = false

		local slotData = {
			frame = newSlot,
			toolInfo = nil,
			hovered = false,
		}
		hotbarSlots[i] = slotData
		LiquidGlassHandler.apply(newSlot)
		if i == MENU_SLOT then
			-- ── Menu button: always visible, special styling ──
			setupMenuSlot(newSlot)

			newSlot.MouseEnter:Connect(function()
				slotData.hovered = true
				local mythicConf = ItemRegistry.getRarity(6)
				newSlot.BackgroundColor3 = mythicConf.bgColor:Lerp(WHITE, LIGHTEN_FACTOR)
				TooltipModule.show({
					title = '<font color="#FFFF55"><b>Menu</b></font>',
					desc = '<font color="#AAAAAA">Open the Nexus Menu and inventory.</font>',
					click = '<font color="#FFFF55">Click to view!</font>',
				}, TOOLTIP_SOURCE)
			end)

			newSlot.MouseLeave:Connect(function()
				slotData.hovered = false
				local mythicConf = ItemRegistry.getRarity(6)
				newSlot.BackgroundColor3 = mythicConf.bgColor
				hideItemTooltip()
			end)
		else
			-- ── Normal item slot ──
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
end

-- ===================== DROPSHADOW TWEEN =====================
local dropShadow = hotbarBB:FindFirstChild("DropShadow")
if dropShadow then
	local dropShadowTween = nil

	local function tweenDropShadow()
		local s = hotbarBB.AbsoluteSize
		if dropShadowTween then
			dropShadowTween:Cancel()
		end
		dropShadowTween = TweenService:Create(
			dropShadow,
			TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(s.X, s.Y) }
		)
		dropShadowTween:Play()
	end

	-- Snap on first frame, then tween all future changes
	task.defer(function()
		local s = hotbarBB.AbsoluteSize
		dropShadow.Size = UDim2.fromOffset(s.X, s.Y)
	end)

	hotbarBB:GetPropertyChangedSignal("AbsoluteSize"):Connect(tweenDropShadow)
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
	LiquidGlassHandler.apply(newSlot)

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

-- ===================== REFRESH DISPLAY =====================
local function refreshHotbar()
	for i = 1, MAX_HOTBAR do
		if i == MENU_SLOT then
			-- Menu slot is always visible and never changes from server data
			setupMenuSlot(hotbarSlots[i].frame)
			continue
		end

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

	-- Update pool slots
	for i, toolInfo in ipairs(currentInventoryData) do
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
		slotData.frame.BackgroundTransparency = 0.3
		slotData.frame.Visible = true
		slotData.frame.Swap.Visible = false
	end

	-- Hide unused pool slots
	for i = #currentInventoryData + 1, #inventoryPool do
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

-- Show all 8 item hotbar slots (not slot 9) during drag
local function _showAllHotbarSlots()
	for i = 1, MAX_HOTBAR - 1 do -- slots 1-8 only
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

-- ===================== DRAG SYSTEM =====================

local function findSlotAtPosition(screenPos)
	-- Check hotbar slots (1-8, skip menu slot 9)
	for i = 1, MAX_HOTBAR - 1 do
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

	-- Check inventory slots (only when visible)
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

local function isOverInventoryArea(screenPos)
	if not inventoryVisible then
		return false
	end
	local absPos = boundingBox.AbsolutePosition
	local absSize = boundingBox.AbsoluteSize
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
	slotFrame.UIStroke.Color = valid and HIGHLIGHT_COLOR_VALID or Color3.fromHex("#FF5555")
end

local function _createDragGhost(sourceFrame)
	local ghost = sourceFrame:Clone()
	ghost.Name = "DragGhost"
	-- Parent to hotbarGui (CustomInventory) which is always enabled
	ghost.Parent = hotbarGui
	ghost.ZIndex = 100
	ghost.BackgroundTransparency = GHOST_TRANSPARENCY
	local absSize = sourceFrame.AbsoluteSize
	ghost.Size = UDim2.fromOffset(absSize.X, absSize.Y)
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)

	for _, child in ipairs(ghost:GetDescendants()) do
		if child:IsA("GuiObject") then
			if child.BackgroundTransparency < 1 then
				child.BackgroundTransparency = math.max(child.BackgroundTransparency, GHOST_TRANSPARENCY)
			end
		end
	end

	for _, child in ipairs(ghost:GetDescendants()) do
		if child:IsA("GuiButton") then
			child.Active = false
		end
	end

	return ghost
end

local function _cleanupDrag()
	if dragState then
		if dragState.sourceFrame then
			dragState.sourceFrame.BackgroundTransparency = 0.3
		end
		if dragState.ghost then
			dragState.ghost:Destroy()
		end
		dragState = nil
	end
	_clearDragHighlight()
	_hideTransferFrame()
	refreshHotbar()
end

local function _startDragOnSlot(toolInfo, slotFrame, isHotbar, slotIndex, mousePos)
	if not toolInfo then
		return
	end

	-- Block drag when inventory panel is closed — click-to-equip only
	-- Exception: hotbar drag in inventory-only mode shows transfer frame
	if not inventoryVisible then
		if isHotbar and slotIndex then
			EquipToolFunc:InvokeServer(slotIndex)
		else
			EquipToolByNameFunc:InvokeServer(toolInfo.name)
		end
		UIClick:Play()
		return
	end

	-- Show transfer frame when dragging from hotbar in inventory-only mode (no nexus grid)
	local currentMode = MenuBridge.getMode()
	if isHotbar and currentMode == "inventory" then
		_showTransferFrame()
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
		dragState.isDragging = true
		dragState.ghost = _createDragGhost(dragState.sourceFrame)
		dragState.sourceFrame.BackgroundTransparency = DIM_TRANSPARENCY
	end

	-- Ghost in IgnoreGuiInset=true ScreenGui: add inset.Y to viewport-relative input.Position
	if dragState.ghost then
		local inset = GuiService:GetGuiInset()
		dragState.ghost.Position = UDim2.fromOffset(mousePos.X, mousePos.Y + inset.Y)
	end

	-- Hit test uses viewport-relative coords (matches AbsolutePosition)
	local screenPos = Vector2.new(mousePos.X, mousePos.Y)
	local targetSlot, _, _ = findSlotAtPosition(screenPos)
	if targetSlot and targetSlot.frame ~= dragState.sourceFrame then
		_setDragHighlight(targetSlot.frame, true)
		_updateTransferHover(false)
	elseif _isOverTransferFrame(screenPos) then
		_clearDragHighlight()
		_updateTransferHover(true)
	else
		_clearDragHighlight()
		_updateTransferHover(false)
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

	-- Hit test BEFORE cleanup (cleanup hides empty hotbar slots)
	local targetSlot, targetIsHotbar, targetSlotIndex
	local overInventory = false
	local overTransfer = false
	if wasDragging then
		local adjustedPos = Vector2.new(mousePos.X, mousePos.Y)
		targetSlot, targetIsHotbar, targetSlotIndex = findSlotAtPosition(adjustedPos)
		overInventory = isOverInventoryArea(adjustedPos)
		overTransfer = _isOverTransferFrame(adjustedPos)
	end

	_cleanupDrag()
	_hideTransferFrame()
	suppressTooltip = false

	if not wasDragging then
		if sourceIsHotbar and sourceSlotIndex then
			EquipToolFunc:InvokeServer(sourceSlotIndex)
		else
			EquipToolByNameFunc:InvokeServer(toolName)
		end
		UIClick:Play()
		return
	end

	if overTransfer then
		MoveToEndFunc:InvokeServer(toolName)
		if selectSound2 then
			selectSound2:Play()
		end
	elseif targetSlot and targetSlot.toolInfo then
		SwapItemsFunc:InvokeServer(toolName, targetSlot.toolInfo.name)
		if selectSound2 then
			selectSound2:Play()
		end
	elseif targetSlot and targetIsHotbar and not targetSlot.toolInfo then
		AssignHotbarFunc:InvokeServer(targetSlotIndex, toolName)
		if selectSound2 then
			selectSound2:Play()
		end
	elseif overInventory then
		if sourceIsHotbar then
			MoveToEndFunc:InvokeServer(toolName)
			if selectSound2 then
				selectSound2:Play()
			end
		end
	else
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
			clearMobileSelection()
		else
			SwapItemsFunc:InvokeServer(mobileSelectedName, toolInfo.name)
			if selectSound2 then
				selectSound2:Play()
			end
			clearMobileSelection()
		end
	else
		if selectSound1 then
			selectSound1:Play()
		end
		mobileSelectedName = toolInfo.name
		mobileSelectedSlot = slotFrame
		slotFrame.Swap.Visible = true
	end
end

-- ===================== SLOT INPUT WIRING =====================
local function wireHotbarSlotInput(slotIndex)
	local slotData = hotbarSlots[slotIndex]
	local selectBtn = slotData.frame:WaitForChild("Select")

	if slotIndex == MENU_SLOT then
		-- ── Menu button click → open full Nexus menu ──
		selectBtn.MouseButton1Down:Connect(function()
			UIClick:Play()
			MenuBridge.openFullMenu()
		end)
		return
	end

	selectBtn.MouseButton1Down:Connect(function()
		if not slotData.toolInfo then
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

		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		_startDragOnSlot(slotData.toolInfo, slotData.frame, true, slotIndex, mousePos)
	end)
end

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
UserInputService.InputBegan:Connect(function(input, _)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		suppressTooltip = true
		TooltipModule.forceHide()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		suppressTooltip = false
		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local adjustedPos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		local slotData = findSlotAtPosition(adjustedPos)
		if slotData and slotData.toolInfo and not dragState then
			showItemTooltip(slotData.toolInfo)
		end
	end
end)

-- ===================== SERVER DATA HANDLER =====================
UpdateInventoryEvent.OnClientEvent:Connect(function(data)
	currentHotbarData = data.hotbar or {}
	currentInventoryData = data.inventory or {}
	currentTotalItems = data.total_items or 0
	currentMaxCapacity = data.max_capacity or 1000

	refreshAll()
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
	[Enum.KeyCode.C] = 9,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	local key = input.KeyCode

	-- E key → toggle inventory-only mode
	if key == Enum.KeyCode.E then
		MenuBridge.openInventory()
		return
	end

	-- G key → close everything
	if key == Enum.KeyCode.G then
		if MenuBridge.isOpen() then
			MenuBridge.closeAll()
		end
		return
	end

	-- Number keys → equip hotbar slot
	local slotIndex = keyToSlot[key]
	if slotIndex then
		if slotIndex == MENU_SLOT then
			-- Key 9 → open full menu (same as clicking slot 9)
			MenuBridge.openFullMenu()
			return
		end

		if mobileSelectedName then
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
		else
			EquipToolFunc:InvokeServer(slotIndex)
		end
	end
end)

-- ===================== MENUBRIDGE CALLBACKS =====================
-- CentralizedMenuController notifies us when state changes
MenuBridge._onStateChanged = function(mode)
	local wasVisible = inventoryVisible
	inventoryVisible = (mode ~= nil) -- visible in both "inventory" and "full" modes

	if inventoryVisible and not wasVisible then
		refreshInventory()
	end

	-- Cleanup drag if menu closes mid-drag
	if not inventoryVisible and dragState then
		_cleanupDrag()
		suppressTooltip = false
	end

	-- Clear mobile selection on close
	if not inventoryVisible then
		clearMobileSelection()
		TooltipModule.forceHide()
	end
end

-- Expose refresh for external callers
MenuBridge._refreshInventory = function()
	refreshInventory()
end

-- ===================== INITIAL STATE =====================
createHotbarSlots()
for i = 1, MAX_HOTBAR do
	wireHotbarSlotInput(i)
end

hotbarFrame.Visible = true

print("[InventoryController] Ready ✓")
