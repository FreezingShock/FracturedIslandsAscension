-- ============================================================
--  InventoryController (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  Client-side inventory system for Fractured Islands: Ascension.
--
--  REWRITTEN: 27-slot grid system (Minecraft-style).
--  - 27 permanent blank slots always visible in inventory panel
--  - Items fill grid slots; blanks show where items CAN go
--  - Overflow items (28+) appear below the grid when all 27 full
--  - Drag item onto blank = place it there (server-persisted)
--  - Blank slots cannot be dragged
--  - Auto-condense: overflow auto-fills empty grid slots server-side
--
--  Hotbar stays in CustomInventory ScreenGui (unchanged).
--  Slot 9 is a permanent "Menu" button.
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
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
ItemIcons.preload()
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any
local LiquidGlassHandler = require(Modules:WaitForChild("LiquidGlassHandler")) :: any

-- ===================== ENSURE MENUBRIDGE CALLBACKS REGISTERED =====================
-- CentralizedMenuController registers these callbacks.
-- Wait for them to ensure proper load order and prevent race conditions.
local function waitForMenuBridgeReady(timeout)
	timeout = timeout or 5
	local startTime = tick()
	while (not MenuBridge._openFullMode or not MenuBridge._openInventoryMode)
		and (tick() - startTime) < timeout do
		task.wait(0.05)
	end
	if not MenuBridge._openFullMode then
		error("[InventoryController] MenuBridge._openFullMode not registered (CentralizedMenuController may not have loaded)")
	end
	if not MenuBridge._openInventoryMode then
		error("[InventoryController] MenuBridge._openInventoryMode not registered (CentralizedMenuController may not have loaded)")
	end
end

-- Wait for MenuBridge to be fully initialized
task.spawn(waitForMenuBridgeReady)

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
local AssignGridSlotFunc = ReplicatedStorage:WaitForChild("AssignGridSlot")
local DropItemFunc = ReplicatedStorage:WaitForChild("DropItem")
local MoveToEndFunc = ReplicatedStorage:WaitForChild("MoveToEnd")
local RequestInventoryEvent = ReplicatedStorage:WaitForChild("RequestInventory")
local TrashItemFunc = ReplicatedStorage:WaitForChild("TrashItem")
local RestoreTrashFunc = ReplicatedStorage:WaitForChild("RestoreTrash")

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

-- ===================== CONSTANTS =====================
local GRID_SLOTS = 27
local MAX_HOTBAR = 9
local PIN_SLOT = 9 -- slot 9 holds the Nexus Star: a pinned, equippable item (left click with it opens the menu)

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

-- ===================== BLANK SLOT CONFIG =====================
local BLANK_TRANSPARENCY = 0.6
local BLANK_RARITY = ItemRegistry.getRarity(0) -- Common gray

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

-- Data from server (new payload format)
local currentHotbarData = {} -- { [1..9] = toolInfo or false }
local currentGridData = {} -- { [1..27] = toolInfo or nil } (sparse)
local currentOverflowData = {} -- { toolInfo, ... } (dense)
local currentTotalItems = 0
local currentMaxCapacity = 1000
local currentSelected = 1 -- selected hotbar slot (server-tracked; an empty slot means an empty hand)
local currentTrash = nil -- toolInfo of the last trashed stack (server keeps it until the next trash / rejoin)

-- Pages: the 27 grid slots followed by the overflow items, cut into pages of whole rows (9 per row).
-- With the Nexus menu open the frame is 2 rows tall (18 per page), otherwise 3 rows (27), so the page
-- size follows the mode and the layout never shows a half-cut row.
local COLUMNS = 9
local function pageSize()
	return MenuBridge.getMode() == "full" and COLUMNS * 2 or COLUMNS * 3
end
local currentPage = 1
local pageCount = 1

-- Drag state (PC)
local dragState = nil
local suppressTooltip = false

-- Mobile selection
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local mobileSelectedName = nil
local mobileSelectedSlot = nil

-- Slot pools
local hotbarSlots = {} -- [1..9] = { frame, toolInfo, hovered }
local gridPool = {} -- [1..27] = { frame, toolInfo, hovered, isBlank }
local overflowPool = {} -- array of { frame, toolInfo, hovered, inUse }
local trashSlot = nil -- { frame, hovered } (bound by bindTrashSlot)
local pageBar = nil -- { frame, prev, next, label } (bound by bindPageBar)

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

--- Build and show the tooltip for an inventory item. All layout and
--- section toggling lives in TooltipModule; item data -> tooltip mapping
--- lives in TooltipModule.Items (so new item fields never touch this file).
local function showItemTooltip(toolInfo)
	if suppressTooltip or not toolInfo then
		return
	end
	TooltipModule.show(TooltipModule.Items.fromTool(toolInfo), TOOLTIP_SOURCE)
end

local function hideItemTooltip()
	TooltipModule.hide(TOOLTIP_SOURCE)
end

-- ===================== SLOT VISUAL HELPERS =====================
--- Show the item's icon in a slot (hides the name text when a real icon is drawn; tooltip carries the name).
local function setSlotIcon(slotFrame, toolInfo)
	local img = ItemIcons.ensureImage(slotFrame)
	local hasIcon = false
	if toolInfo then
		local id = toolInfo.itemId or toolInfo.name
		hasIcon = ItemIcons.apply(img, ItemRegistry.exists(id) and ItemRegistry.get(id) or { id = id })
	end
	img.Visible = hasIcon
	slotFrame.ToolName.Visible = not hasIcon
end

--- The selected hotbar slot is the darkened one (copies of one item share a Tool name, so match by slot).
local function isSelectedSlot(slotIndex)
	return slotIndex == currentSelected
end

--- "12x" for stackables; nothing for unstackable gear (a "1x" on every sword is noise).
local function stackText(toolInfo)
	return toolInfo.unstackable and "" or (tostring(toolInfo.count) .. "x")
end

local function updateSlotVisual(slotFrame, toolInfo, isEquipped, isHovered)
	slotFrame.BackgroundTransparency = 0.3
	setSlotIcon(slotFrame, toolInfo)
	if not toolInfo then
		slotFrame.ToolName.Text = ""
		slotFrame.StackNum.Text = ""
		slotFrame.RarityLabel.Text = ""
		slotFrame.UIStroke.Color = ItemRegistry.getRarity(0).color
		slotFrame.BackgroundColor3 = ItemRegistry.getRarity(0).bgColor
		if isEquipped then
			slotFrame.BackgroundColor3 = slotFrame.BackgroundColor3:Lerp(BLACK, DARKEN_FACTOR)
		end
		return
	end

	local rarityConf = ItemRegistry.getRarity(toolInfo.rarity or 0)
	slotFrame.ToolName.Text = toolInfo.displayName or toolInfo.name
	slotFrame.StackNum.Text = stackText(toolInfo)
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

--- Render a grid slot as blank (empty placeholder).
local function renderSlotBlank(slotFrame)
	setSlotIcon(slotFrame, nil)
	slotFrame.ToolName.Text = ""
	slotFrame.StackNum.Text = ""
	slotFrame.RarityLabel.Text = ""
	slotFrame.UIStroke.Color = BLANK_RARITY.color
	slotFrame.BackgroundColor3 = BLANK_RARITY.bgColor
	slotFrame.BackgroundTransparency = BLANK_TRANSPARENCY
	slotFrame.Visible = true
	slotFrame.Swap.Visible = false
end

--- Render a grid/overflow slot as filled with an item.
local function renderSlotFilled(slotFrame, toolInfo, isHovered)
	setSlotIcon(slotFrame, toolInfo)
	local rarityConf = ItemRegistry.getRarity(toolInfo.rarity or 0)
	slotFrame.ToolName.Text = toolInfo.displayName or toolInfo.name
	slotFrame.StackNum.Text = stackText(toolInfo)
	slotFrame.RarityLabel.Text = rarityConf.display
	slotFrame.RarityLabel.TextColor3 = rarityConf.color
	slotFrame.UIStroke.Color = rarityConf.color
	slotFrame.BackgroundColor3 = isHovered and rarityConf.bgColor:Lerp(WHITE, LIGHTEN_FACTOR) or rarityConf.bgColor
	slotFrame.BackgroundTransparency = 0.3
	slotFrame.Visible = true
	slotFrame.Swap.Visible = false
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
		TooltipModule.registerHover(newSlot, function()
			if slotData.toolInfo then
				showItemTooltip(slotData.toolInfo)
			end
		end)
		LiquidGlassHandler.apply(newSlot, {
			SeparatedBorderOutline = {
				enabled = true,
				offset = 4,
				thickness = 2,
				color = Color3.fromRGB(255, 255, 255),
			},
		})
		-- every slot is a normal item slot; slot 9 simply holds the pinned Nexus Star
		newSlot.MouseEnter:Connect(function()
			slotData.hovered = true
			updateSlotVisual(newSlot, slotData.toolInfo, isSelectedSlot(i), true)
			if slotData.toolInfo then
				showItemTooltip(slotData.toolInfo)
			end
		end)

		newSlot.MouseLeave:Connect(function()
			slotData.hovered = false
			updateSlotVisual(newSlot, slotData.toolInfo, isSelectedSlot(i), false)
			hideItemTooltip()
		end)
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

-- ===================== GRID SLOT CREATION (27 slots, once at init) =====================
local function createGridSlots()
	for i = 1, GRID_SLOTS do
		local newSlot = slotTemplate:Clone()
		newSlot.Name = "GridSlot" .. i
		newSlot.LayoutOrder = i
		newSlot.SlotNum.Visible = false
		newSlot.Parent = inventoryFrame
		newSlot.Swap.Visible = false

		local slotData = {
			frame = newSlot,
			toolInfo = nil,
			hovered = false,
			isBlank = true,
		}
		gridPool[i] = slotData
		TooltipModule.registerHover(newSlot, function()
			if slotData.toolInfo then
				showItemTooltip(slotData.toolInfo)
			end
		end)

		-- GlassVisible = false: only the hover outline + stroke; the 3D glass parts are never built for these slots
		LiquidGlassHandler.apply(newSlot, {
			GlassVisible = false,
			SeparatedBorderOutline = {
				enabled = true,
				offset = 4,
				thickness = 2,
				color = Color3.fromRGB(255, 255, 255),
			},
		})

		-- Start as blank
		renderSlotBlank(newSlot)

		-- ── Hover connections (wired once, never re-wired) ──
		newSlot.MouseEnter:Connect(function()
			slotData.hovered = true
			if slotData.toolInfo then
				local rarityConf = ItemRegistry.getRarity(slotData.toolInfo.rarity or 0)
				newSlot.BackgroundColor3 = rarityConf.bgColor:Lerp(WHITE, LIGHTEN_FACTOR)
				showItemTooltip(slotData.toolInfo)
			end
			-- Blank slots: no hover visual change, no tooltip
		end)

		newSlot.MouseLeave:Connect(function()
			slotData.hovered = false
			if slotData.toolInfo then
				local rarityConf = ItemRegistry.getRarity(slotData.toolInfo.rarity or 0)
				newSlot.BackgroundColor3 = rarityConf.bgColor
			end
			hideItemTooltip()
		end)
	end
end

-- ===================== OVERFLOW SLOT POOL =====================
local function getOrCreateOverflowSlot(index)
	if overflowPool[index] then
		return overflowPool[index]
	end

	local newSlot = slotTemplate:Clone()
	newSlot.Name = "OverflowSlot" .. index
	newSlot.LayoutOrder = GRID_SLOTS + index -- after grid slots
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
	overflowPool[index] = slotData
	TooltipModule.registerHover(newSlot, function()
		if slotData.toolInfo then
			showItemTooltip(slotData.toolInfo)
		end
	end)

	LiquidGlassHandler.apply(newSlot, {
		GlassVisible = false,
		SeparatedBorderOutline = {
			enabled = true,
			offset = 4,
			thickness = 2,
			color = Color3.fromRGB(255, 255, 255),
		},
	})

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

local hotbarShowAllPref = false -- mirrors server-saved preference
-- Applies the current visibility preference (or drag override).
-- dragOverride=true forces all slots visible (drag in progress).
local function applyHotbarVisibility(dragOverride)
	local showAll = dragOverride or hotbarShowAllPref
	for i = 1, MAX_HOTBAR do
		local slotData = hotbarSlots[i]
		if showAll then
			slotData.frame.Visible = true
		else
			-- Only show if filled
			slotData.frame.Visible = (slotData.toolInfo ~= nil) or i == currentSelected
		end
	end
end

-- Show every hotbar slot during a drag
local function _showAllHotbarSlots()
	applyHotbarVisibility(true) -- drag override = force all visible
end

-- ===================== SCROLLING LOGIC =====================
local function updateScrolling()
	inventoryFrame.ScrollingEnabled = false -- paged: the page bar replaces the scroll wheel
end

-- ===================== PAGE BAR =====================
local PAGE_HOLD_TIME = 0.45 -- seconds a dragged item must hover an arrow to flip the page

local refreshInventory -- defined with the refresh functions below

local function setPage(page)
	page = math.clamp(page, 1, pageCount)
	if page == currentPage then
		return false
	end
	currentPage = page
	refreshInventory()
	TooltipModule.recheckPointer(true)
	return true
end

--- Hook up the hand-made PageBar (Inventory.PageBar.Pager.Prev / Next / PageLabel). The look is yours to edit in
--- Studio; this only wires clicks, the "n / N" text and keeps the bar under the grid.
local function bindPageBar()
	local frame = inventoryPanel:WaitForChild("PageBar")
	local pager = frame:WaitForChild("Pager")
	local prev = pager:WaitForChild("Prev")
	local nxt = pager:WaitForChild("Next")
	local label = pager:WaitForChild("PageLabel")

	prev.MouseButton1Click:Connect(function()
		if setPage(currentPage - 1) then
			UIClick:Play()
		end
	end)
	nxt.MouseButton1Click:Connect(function()
		if setPage(currentPage + 1) then
			UIClick:Play()
		end
	end)

	pageBar = { frame = frame, prev = prev, next = nxt, label = label }

	-- The grid frame shrinks/grows with the Nexus menu: keep the bar glued under it
	local function follow()
		frame.Position = UDim2.new(0, 0, 0, inventoryFrame.AbsoluteSize.Y + 6)
	end
	inventoryFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow)
	follow()
end

-- ===================== TRASH SLOT =====================
--- Trash slot parts (hand-made: PageBar.TrashSlot with ToolName, ItemImage, UIStroke). Empty keeps your styling;
--- a trashed item shows its icon (or name) and rarity colour until it is taken back.
local function renderTrash()
	if not trashSlot then
		return
	end
	local info = trashSlot
	if currentTrash then
		local id = currentTrash.itemId or currentTrash.name
		local hasIcon = info.image
			and ItemIcons.apply(info.image, ItemRegistry.exists(id) and ItemRegistry.get(id) or { id = id })
		if info.image then
			info.image.Visible = hasIcon and true or false
		end
		info.nameLabel.Visible = not hasIcon
		info.nameLabel.Text = currentTrash.displayName or currentTrash.name
		if info.stroke then
			info.stroke.Color = ItemRegistry.getRarity(currentTrash.rarity or 0).color
		end
	else
		if info.image then
			info.image.Visible = false
		end
		info.nameLabel.Visible = true
		info.nameLabel.Text = info.emptyText
		if info.stroke then
			info.stroke.Color = info.emptyStroke
		end
	end
end

--- Thicker outline while a dragged item hovers the trash slot.
local function setTrashHot(hot)
	if trashSlot and trashSlot.hot ~= hot then
		trashSlot.hot = hot
		if trashSlot.stroke then
			trashSlot.stroke.Thickness = hot and trashSlot.baseThickness + 2 or trashSlot.baseThickness
		end
	end
end

local function isOverFrame(frame, screenPos)
	local absPos, absSize = frame.AbsolutePosition, frame.AbsoluteSize
	return screenPos.X >= absPos.X
		and screenPos.X <= absPos.X + absSize.X
		and screenPos.Y >= absPos.Y
		and screenPos.Y <= absPos.Y + absSize.Y
end

local function bindTrashSlot()
	local frame = pageBar.frame:WaitForChild("TrashSlot")
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local nameLabel = frame:WaitForChild("ToolName")
	trashSlot = {
		frame = frame,
		nameLabel = nameLabel,
		image = frame:FindFirstChild("ItemImage"),
		stroke = stroke,
		emptyText = nameLabel.Text,
		emptyStroke = stroke and stroke.Color or WHITE,
		baseThickness = stroke and stroke.Thickness or 2,
		hovered = false,
		hot = false,
	}

	--- The trashed item's tooltip, or an explanation while the slot is empty
	local function showTrashTooltip()
		if currentTrash then
			showItemTooltip(currentTrash)
		elseif not suppressTooltip then
			TooltipModule.show({
				title = '<font color="#FF5555"><b>Trash</b></font>',
				desc = '<font color="#AAAAAA">Drop an item here to delete it. The last item you trash stays here until you throw away another or leave, so you can take it back.</font>',
				click = { { text = "TO DRAG AN ITEM IN", color = "#FF5555", icon = "lmb" } },
			}, TOOLTIP_SOURCE)
		end
	end

	TooltipModule.registerHover(frame, showTrashTooltip)
	frame.MouseEnter:Connect(function()
		trashSlot.hovered = true
		showTrashTooltip()
	end)
	frame.MouseLeave:Connect(function()
		trashSlot.hovered = false
		hideItemTooltip()
	end)
	renderTrash()
end

-- ===================== HOVER RECONCILE =====================
--- Make the tooltip match what is under the cursor right now. Needed because MouseEnter only fires on mouse
--- MOVEMENT: after a refresh (equip, pickup, drop, swap) the slot under a still cursor holds a different item,
--- and after a drag the tooltip was suppressed - neither would update until the mouse moved.
local findSlotAtPosition -- defined with the drag system below
local reconcileHover
reconcileHover = function()
	if suppressTooltip or (dragState and dragState.isDragging) then
		return
	end
	local rawMouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local slotData = findSlotAtPosition(Vector2.new(rawMouse.X, rawMouse.Y - inset.Y))
	if slotData and slotData.toolInfo then
		showItemTooltip(slotData.toolInfo)
	elseif
		TooltipModule.isActiveSource(TOOLTIP_SOURCE)
		and not (trashSlot and trashSlot.hovered)
	then
		hideItemTooltip() -- the slot under the cursor is empty now
	end
end

-- ===================== REFRESH DISPLAY =====================
local function refreshHotbar()
	for i = 1, MAX_HOTBAR do
		local slotData = hotbarSlots[i]
		local toolInfo = currentHotbarData[i]
		local hasItem = (type(toolInfo) == "table" and toolInfo.name ~= nil)

		slotData.toolInfo = hasItem and toolInfo or nil

		local isEq = isSelectedSlot(i)
		updateSlotVisual(slotData.frame, slotData.toolInfo, isEq, slotData.hovered)

		slotData.frame.Visible = hasItem or isEq -- the selected slot stays visible even when empty (empty hand)
	end
	applyHotbarVisibility(false) -- apply visibility based on current preference (no drag override)
end

refreshInventory = function()
	if not inventoryVisible then
		return
	end

	-- ── Grid slots 1-27 ──
	for i = 1, GRID_SLOTS do
		local slotData = gridPool[i]
		-- Server sends false for blanks (dense array); normalize to nil
		local toolInfo = currentGridData[i]
		if toolInfo == false then
			toolInfo = nil
		end

		slotData.toolInfo = toolInfo

		if toolInfo then
			slotData.isBlank = false
			renderSlotFilled(slotData.frame, toolInfo, slotData.hovered)
		else
			slotData.isBlank = true
			renderSlotBlank(slotData.frame)
		end
	end

	-- ── Overflow slots (28+) ──
	for i, toolInfo in ipairs(currentOverflowData) do
		local slotData = getOrCreateOverflowSlot(i)
		slotData.toolInfo = toolInfo
		slotData.inUse = true
		renderSlotFilled(slotData.frame, toolInfo, slotData.hovered)
	end

	-- ── Pages: only the current page's slots are shown ──
	local size = pageSize()
	pageCount = math.ceil((GRID_SLOTS + #currentOverflowData) / size)
	currentPage = math.clamp(currentPage, 1, pageCount)
	for i = 1, GRID_SLOTS do
		gridPool[i].frame.Visible = math.ceil(i / size) == currentPage
	end
	for i = 1, #currentOverflowData do
		overflowPool[i].frame.Visible = math.ceil((GRID_SLOTS + i) / size) == currentPage
	end
	if pageBar then
		pageBar.label.Text = currentPage .. " / " .. pageCount
		pageBar.prev.TextTransparency = currentPage > 1 and 0 or 0.6
		pageBar.next.TextTransparency = currentPage < pageCount and 0 or 0.6
	end

	-- Hide unused overflow pool slots
	for i = #currentOverflowData + 1, #overflowPool do
		local slotData = overflowPool[i]
		slotData.toolInfo = nil
		slotData.inUse = false
		slotData.frame.Visible = false
	end

	-- ── Capacity label ──
	capacityLabel.Text = tostring(currentTotalItems) .. "/" .. tostring(currentMaxCapacity)

	-- ── Scrolling ──
	updateScrolling()
end

local function refreshAll()
	refreshHotbar()
	refreshInventory()
	renderTrash()
	task.defer(reconcileHover) -- after layout: the item under a stationary cursor may have changed
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

--- Find a slot at the given screen position.
--- Returns: slotData, location ("hotbar"|"grid"|"overflow"|nil), index, isBlank
findSlotAtPosition = function(screenPos)
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
				return slotData, "hotbar", i, false
			end
		end
	end

	-- Check grid slots (always visible when inventory is open)
	if inventoryVisible then
		for i = 1, GRID_SLOTS do
			local slotData = gridPool[i]
			if slotData.frame.Visible then
				local absPos = slotData.frame.AbsolutePosition
				local absSize = slotData.frame.AbsoluteSize
				if
					screenPos.X >= absPos.X
					and screenPos.X <= absPos.X + absSize.X
					and screenPos.Y >= absPos.Y
					and screenPos.Y <= absPos.Y + absSize.Y
				then
					return slotData, "grid", i, slotData.isBlank
				end
			end
		end

		-- Check overflow slots
		for i, slotData in ipairs(overflowPool) do
			if slotData.inUse and slotData.frame.Visible then
				local absPos = slotData.frame.AbsolutePosition
				local absSize = slotData.frame.AbsoluteSize
				if
					screenPos.X >= absPos.X
					and screenPos.X <= absPos.X + absSize.X
					and screenPos.Y >= absPos.Y
					and screenPos.Y <= absPos.Y + absSize.Y
				then
					return slotData, "overflow", i, false
				end
			end
		end
	end

	return nil, nil, nil, false
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
	MenuBridge.updateEquipDrag(nil) -- clear armor-slot hover highlight
	if dragState then
		if dragState.sourceFrame then
			-- Restore appropriate transparency based on whether source was grid-blank
			-- (filled slots = 0.3, but refreshAll will correct this anyway)
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

local function _startDragOnSlot(toolInfo, slotFrame, location, slotIndex, mousePos)
	if not toolInfo then
		return
	end

	-- With the inventory closed only the hotbar reacts (a tap holds the item); nothing can be dragged
	if not inventoryVisible and location ~= "hotbar" then
		return
	end

	-- Show transfer frame when dragging from hotbar in inventory-only mode (no nexus grid)
	local currentMode = MenuBridge.getMode()
	if location == "hotbar" and currentMode == "inventory" then
		_showTransferFrame()
	end

	-- (the tooltip stays while the button is merely held/clicked; it hides once the drag really starts)
	dragState = {
		toolName = toolInfo.name,
		itemId = toolInfo.itemId,
		equipSlot = toolInfo.slot, -- armor / accessory slot this item fits, if any
		sourceFrame = slotFrame,
		sourceLocation = location, -- "hotbar", "grid", "overflow"
		slotIndex = slotIndex,
		ghost = nil,
		startPos = mousePos,
		isDragging = false,
	}

	if inventoryVisible then
		_showAllHotbarSlots()
	end
end

local function onDragMove(mousePos)
	if not dragState then
		return
	end

	if not dragState.isDragging then
		local dist = (mousePos - dragState.startPos).Magnitude
		if dist < DRAG_THRESHOLD or not inventoryVisible then
			return
		end
		dragState.isDragging = true
		suppressTooltip = true
		TooltipModule.forceHide()
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
	local targetSlot, _, _, _ = findSlotAtPosition(screenPos)
	local overEquipSlot = MenuBridge.updateEquipDrag(screenPos, dragState.equipSlot)
	if overEquipSlot then
		_clearDragHighlight()
		_updateTransferHover(false)
	elseif targetSlot and targetSlot.frame ~= dragState.sourceFrame then
		_setDragHighlight(targetSlot.frame, true)
		_updateTransferHover(false)
	elseif _isOverTransferFrame(screenPos) then
		_clearDragHighlight()
		_updateTransferHover(true)
	else
		_clearDragHighlight()
		_updateTransferHover(false)
	end
	setTrashHot(trashSlot ~= nil and dragState.sourceLocation ~= "trash" and isOverFrame(trashSlot.frame, screenPos))
end

-- Holding a dragged item over a page arrow flips the page (checked every frame: the cursor may be still)
local pageHold = { dir = 0, t = 0 }
RunService.Heartbeat:Connect(function(dt)
	if not (dragState and dragState.isDragging and pageBar and inventoryVisible) then
		pageHold.dir = 0
		return
	end
	local rawMouse = UserInputService:GetMouseLocation()
	local pos = Vector2.new(rawMouse.X, rawMouse.Y - GuiService:GetGuiInset().Y)
	local dir = 0
	if isOverFrame(pageBar.prev, pos) then
		dir = -1
	elseif isOverFrame(pageBar.next, pos) then
		dir = 1
	end
	if dir == 0 then
		pageHold.dir = 0
		return
	end
	if dir ~= pageHold.dir then
		pageHold.dir, pageHold.t = dir, 0
	end
	pageHold.t += dt
	if pageHold.t >= PAGE_HOLD_TIME then
		pageHold.t = 0
		if setPage(currentPage + dir) then
			UIClick:Play()
		end
	end
end)

local function onDragEnd(mousePos)
	if not dragState then
		suppressTooltip = false
		return
	end

	local wasDragging = dragState.isDragging
	local toolName = dragState.toolName
	local itemId = dragState.itemId
	local equipSlot = dragState.equipSlot
	local sourceLocation = dragState.sourceLocation
	local sourceIndex = dragState.slotIndex

	-- Hit test BEFORE cleanup (cleanup hides empty hotbar slots)
	local targetSlot, targetLocation, targetSlotIndex, targetIsBlank
	local overInventory = false
	local overTransfer = false
	local overTrash = false
	local overEquipSlot = nil
	if wasDragging then
		local adjustedPos = Vector2.new(mousePos.X, mousePos.Y)
		overEquipSlot = MenuBridge.updateEquipDrag(adjustedPos, equipSlot)
		targetSlot, targetLocation, targetSlotIndex, targetIsBlank = findSlotAtPosition(adjustedPos)
		overInventory = isOverInventoryArea(adjustedPos)
		overTransfer = _isOverTransferFrame(adjustedPos)
		overTrash = trashSlot ~= nil and inventoryVisible and isOverFrame(trashSlot.frame, adjustedPos)
	end

	_cleanupDrag()
	_hideTransferFrame()
	setTrashHot(false)
	suppressTooltip = false

	-- ── Left click (no drag): a hotbar slot holds / puts away its item; inventory slots do nothing ──
	if not wasDragging then
		if sourceLocation == "hotbar" and sourceIndex and not isMobile then
			task.spawn(function()
				EquipToolFunc:InvokeServer(sourceIndex)
			end)
			UIClick:Play()
		end
		return
	end

	-- Dragged out of the trash slot onto the inventory: take the item back
	if sourceLocation == "trash" then
		if not overTrash and (targetSlot or overInventory) then
			task.spawn(function()
				RestoreTrashFunc:InvokeServer()
			end)
			if selectSound2 then
				selectSound2:Play()
			end
		end
		return
	end

	-- Dropped on the trash slot: the whole stack goes (and stays in the trash slot to be taken back)
	if overTrash then
		task.spawn(function()
			TrashItemFunc:InvokeServer(toolName)
		end)
		UIClick:Play()
		return
	end

	-- ── Drag completed → determine action ──

	-- Dropped on an armor / accessory slot → equip if it fits that slot
	if overEquipSlot then
		if equipSlot and overEquipSlot == equipSlot and itemId then
			local equipItemFunc = ReplicatedStorage:FindFirstChild("EquipItem")
			if equipItemFunc then
				equipItemFunc:InvokeServer(equipSlot, itemId, toolName)
				if selectSound2 then
					selectSound2:Play()
				end
			end
		end
		return
	end

	-- Dropped on transfer frame → move hotbar item to inventory
	if overTransfer then
		MoveToEndFunc:InvokeServer(toolName)
		if selectSound2 then
			selectSound2:Play()
		end
		return
	end

	-- Dropped on a blank grid slot → assign to that grid position
	if targetSlot and targetIsBlank and targetLocation == "grid" then
		AssignGridSlotFunc:InvokeServer(targetSlotIndex, toolName)
		if selectSound2 then
			selectSound2:Play()
		end
		return
	end

	-- Dropped on a filled slot (grid, overflow, or hotbar with item) → swap
	if targetSlot and targetSlot.toolInfo then
		-- Hotbar target with item → swap via SwapItemsFunc
		-- Grid target with item → swap via SwapItemsFunc
		-- Overflow target with item → swap via SwapItemsFunc
		SwapItemsFunc:InvokeServer(toolName, targetSlot.toolInfo.name)
		if selectSound2 then
			selectSound2:Play()
		end
		return
	end

	-- Dropped on empty hotbar slot → assign to hotbar
	if targetSlot and targetLocation == "hotbar" and not targetSlot.toolInfo then
		AssignHotbarFunc:InvokeServer(targetSlotIndex, toolName)
		if selectSound2 then
			selectSound2:Play()
		end
		return
	end

	-- Dropped over inventory area (not on a specific slot) → hotbar item transfers
	if overInventory then
		if sourceLocation == "hotbar" then
			MoveToEndFunc:InvokeServer(toolName)
			if selectSound2 then
				selectSound2:Play()
			end
		end
		return
	end

	-- Dropped outside everything → drop item to world
	DropItemFunc:InvokeServer(toolName, true) -- dragging a stack out of the inventory drops all of it
	UIClick:Play()
end

-- ===================== MOBILE TAP SYSTEM =====================
local function clearMobileSelection()
	if mobileSelectedSlot then
		mobileSelectedSlot.Swap.Visible = false
	end
	mobileSelectedName = nil
	mobileSelectedSlot = nil
end

local function handleMobileTap(toolInfo, slotFrame, location, slotIndex, isBlank)
	-- Tapping a blank slot with a selection → assign to that grid slot
	if isBlank and location == "grid" and mobileSelectedName then
		AssignGridSlotFunc:InvokeServer(slotIndex, mobileSelectedName)
		if selectSound2 then
			selectSound2:Play()
		end
		clearMobileSelection()
		return
	end

	-- Tapping a blank slot without selection → do nothing
	if isBlank then
		clearMobileSelection()
		return
	end

	-- Tapping empty hotbar slot with selection → assign to hotbar
	if not toolInfo then
		if mobileSelectedName and location == "hotbar" and slotIndex then
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

	-- Tapping a filled slot
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

-- ===================== RIGHT CLICK EQUIP =====================
--- Armor / accessories go to their equipment slot; everything else is held (hotbar slot or by name).
local function rightClickEquip(toolInfo, location, slotIndex)
	if not toolInfo or dragState or toolInfo.equippable == false then
		return
	end
	if toolInfo.slot and toolInfo.itemId then
		local equipItemFunc = ReplicatedStorage:FindFirstChild("EquipItem")
		if equipItemFunc then
			task.spawn(function()
				equipItemFunc:InvokeServer(toolInfo.slot, toolInfo.itemId, toolInfo.name)
			end)
		end
	elseif location == "hotbar" and slotIndex then
		EquipToolFunc:InvokeServer(slotIndex)
	else
		return -- tools in the inventory cannot be held: move them to the hotbar first
	end
	UIClick:Play()
end

-- ===================== SLOT INPUT WIRING =====================
local function wireHotbarSlotInput(slotIndex)
	local slotData = hotbarSlots[slotIndex]
	local selectBtn = slotData.frame:WaitForChild("Select")

	selectBtn.MouseButton2Down:Connect(function()
		rightClickEquip(slotData.toolInfo, "hotbar", slotIndex)
	end)

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

		if slotData.toolInfo.pinned then
			-- the Nexus Star never moves: a click just selects (holds) it
			task.spawn(function()
				EquipToolFunc:InvokeServer(slotIndex)
			end)
			return
		end

		if isMobile then
			handleMobileTap(slotData.toolInfo, slotData.frame, "hotbar", slotIndex, false)
			return
		end

		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		_startDragOnSlot(slotData.toolInfo, slotData.frame, "hotbar", slotIndex, mousePos)
	end)
end

local function wireGridSlotInput(gridIndex)
	local slotData = gridPool[gridIndex]
	local selectBtn = slotData.frame:WaitForChild("Select")

	selectBtn.MouseButton2Down:Connect(function()
		if not slotData.isBlank then
			rightClickEquip(slotData.toolInfo, "grid", gridIndex)
		end
	end)

	selectBtn.MouseButton1Down:Connect(function()
		-- Blank slots: not drag sources, but can receive mobile selection
		if slotData.isBlank then
			if isMobile and mobileSelectedName then
				AssignGridSlotFunc:InvokeServer(gridIndex, mobileSelectedName)
				if selectSound2 then
					selectSound2:Play()
				end
				clearMobileSelection()
			end
			return
		end

		if not slotData.toolInfo then
			return
		end

		if isMobile then
			handleMobileTap(slotData.toolInfo, slotData.frame, "grid", gridIndex, false)
			return
		end

		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		_startDragOnSlot(slotData.toolInfo, slotData.frame, "grid", gridIndex, mousePos)
	end)
end

local function wireOverflowSlotInput(poolIndex)
	local slotData = overflowPool[poolIndex]
	local selectBtn = slotData.frame:WaitForChild("Select")

	selectBtn.MouseButton2Down:Connect(function()
		rightClickEquip(slotData.toolInfo, "overflow", poolIndex)
	end)

	selectBtn.MouseButton1Down:Connect(function()
		if not slotData.toolInfo then
			return
		end

		if isMobile then
			handleMobileTap(slotData.toolInfo, slotData.frame, "overflow", poolIndex, false)
			return
		end

		local rawMouse = UserInputService:GetMouseLocation()
		local inset = GuiService:GetGuiInset()
		local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - inset.Y)
		_startDragOnSlot(slotData.toolInfo, slotData.frame, "overflow", poolIndex, mousePos)
	end)
end

-- Patch getOrCreateOverflowSlot to wire input on creation
local _originalGetOrCreateOverflow = getOrCreateOverflowSlot
getOrCreateOverflowSlot = function(index)
	local existed = overflowPool[index] ~= nil
	local slotData = _originalGetOrCreateOverflow(index)
	if not existed then
		wireOverflowSlotInput(index)
	end
	return slotData
end

local function wireTrashSlotInput()
	-- input comes from the hand-made Select button (or the frame itself if it has none)
	local target = trashSlot.frame:FindFirstChild("Select") or trashSlot.frame
	target.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton2 then
			-- right click = take the trashed item back
			if currentTrash and not dragState then
				task.spawn(function()
					RestoreTrashFunc:InvokeServer()
				end)
				UIClick:Play()
			end
		elseif kind == Enum.UserInputType.Touch then
			-- tap with an item selected = trash it; otherwise tap the trashed item = take it back
			if mobileSelectedName then
				local name = mobileSelectedName
				clearMobileSelection()
				task.spawn(function()
					TrashItemFunc:InvokeServer(name)
				end)
			elseif currentTrash then
				task.spawn(function()
					RestoreTrashFunc:InvokeServer()
				end)
			end
		elseif kind == Enum.UserInputType.MouseButton1 and currentTrash then
			local rawMouse = UserInputService:GetMouseLocation()
			local mousePos = Vector2.new(rawMouse.X, rawMouse.Y - GuiService:GetGuiInset().Y)
			_startDragOnSlot(currentTrash, trashSlot.frame, "trash", 1, mousePos)
		end
	end)
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

-- ===================== TOOLTIP AFTER A CLICK / DROP =====================
-- A plain click keeps the tooltip (nothing hides it any more). When a drag ends the tooltip was suppressed, so
-- release re-reads what is under the cursor and shows that item's tooltip (the slot may hold something new).
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		task.defer(function()
			if not dragState then
				suppressTooltip = false
				reconcileHover()
			end
		end)
	end
end)

-- ===================== SERVER DATA HANDLER =====================
UpdateInventoryEvent.OnClientEvent:Connect(function(data)
	currentHotbarData = data.hotbar or {}
	currentGridData = data.gridSlots or {}
	currentOverflowData = data.overflow or {}
	currentTrash = data.trash or nil -- false when the trash slot is empty
	currentSelected = data.selected or 1
	currentTotalItems = data.total_items or 0
	currentMaxCapacity = data.max_capacity or 1000

	refreshAll()
end)

-- Ask for the current state now that the listener exists (the join-time push may have been missed)
RequestInventoryEvent:FireServer()

-- ===================== MOUSE WHEEL HOTBAR SELECT =====================
-- Like Minecraft: the wheel cycles the selected slot (1..9) while the cursor is locked to the game view.
local lastWheelAt = 0
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel or gameProcessed then
		return
	end
	if MenuBridge.isOpen() or UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
		return
	end
	local now = os.clock()
	if now - lastWheelAt < 0.05 then
		return
	end
	lastWheelAt = now
	local step = input.Position.Z > 0 and -1 or 1 -- wheel up = previous slot
	local slot = ((currentSelected - 1 + step) % MAX_HOTBAR) + 1
	currentSelected = slot -- optimistic: the server confirms with the next update
	refreshHotbar()
	task.spawn(function()
		EquipToolFunc:InvokeServer(slot)
	end)
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

	-- (E toggles the menu in CentralizedMenuController; handling it here too
	--  opened then immediately closed the inventory.)

	-- G key → close everything
	if key == Enum.KeyCode.G then
		if MenuBridge.isOpen() then
			MenuBridge.closeAll()
		end
		return
	end

	-- Q → drop one of the held item (Ctrl+Q → the whole stack)
	if key == Enum.KeyCode.Q then
		local character = player.Character
		local held = character and character:FindFirstChildOfClass("Tool")
		if held then
			local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
			task.spawn(function()
				DropItemFunc:InvokeServer(held.Name, ctrl)
			end)
		end
		return
	end

	-- C → open the full Nexus menu + inventory (the Nexus Star does the same on left click)
	if key == Enum.KeyCode.C then
		MenuBridge.openFullMenu()
		return
	end

	-- Number keys → equip hotbar slot
	local slotIndex = keyToSlot[key]
	if slotIndex then
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

-- ===================== NEXUS STAR: LEFT CLICK OPENS THE MENU =====================
-- A held tool with OnUse = "nexusMenu" (item def `onUse`): a left click in the game view opens the Nexus Menu and the
-- inventory. Clicks on GUI are filtered by gameProcessed, and nothing happens while a menu is already open.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or MenuBridge.isOpen() then
		return
	end
	local character = player.Character
	local held = character and character:FindFirstChildOfClass("Tool")
	if held and held:GetAttribute("OnUse") == "nexusMenu" then
		UIClick:Play()
		MenuBridge.openFullMenu()
	end
end)

-- ===================== MENUBRIDGE CALLBACKS =====================
-- CentralizedMenuController notifies us when state changes
local lastStateMode = nil
MenuBridge._onStateChanged = function(mode)
	local wasVisible = inventoryVisible
	inventoryVisible = (mode ~= nil) -- visible in both "inventory" and "full" modes

	if inventoryVisible and (not wasVisible or mode ~= lastStateMode) then
		refreshInventory() -- also on inventory <-> full: the page size changes with the frame height
	end
	lastStateMode = mode

	-- Update scrolling when mode changes (inventory → full or vice versa)
	if inventoryVisible then
		updateScrolling()
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

-- ── Hotbar visibility preference from CMC ──
MenuBridge._onHotbarVisibilityChanged = function(showAll)
	hotbarShowAllPref = showAll
	applyHotbarVisibility(false)
end

-- Expose refresh for external callers
MenuBridge._refreshInventory = function()
	refreshInventory()
end

-- ===================== PRELOAD ITEM ASSETS =====================
-- Meshes and textures of every Tool the player owns are loaded as soon as the Tool shows up (join, pickup,
-- respawn), long before it is first drawn, so equipping never waits for a download. The parts are kept in a
-- table so the loaded content stays referenced for the whole session.
local ContentProvider = game:GetService("ContentProvider")
local preloadedKeys = {} -- "meshId|textureId" -> true
local preloadHold = {} -- strong references

local function preloadTool(tool: Instance)
	local batch = {}
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("MeshPart") then
			local key = d.MeshId .. "|" .. d.TextureID
			if not preloadedKeys[key] then
				preloadedKeys[key] = true
				table.insert(batch, d)
				table.insert(preloadHold, d)
			end
		end
	end
	if #batch > 0 then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
		end)
	end
end

local function watchToolContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			preloadTool(child)
		end
	end
	container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			preloadTool(child)
		end
	end)
end

task.spawn(function()
	watchToolContainer(player:WaitForChild("Backpack"))
end)
player.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watchToolContainer(child)
	end
end)
if player.Character then
	watchToolContainer(player.Character)
end
player.CharacterAdded:Connect(watchToolContainer)

-- ===================== INITIAL STATE =====================
createHotbarSlots()
for i = 1, MAX_HOTBAR do
	wireHotbarSlotInput(i)
end

createGridSlots()
for i = 1, GRID_SLOTS do
	wireGridSlotInput(i)
end

bindPageBar()
bindTrashSlot()
wireTrashSlotInput()
refreshHotbar() -- hides the empty template slots (no "Label" placeholders) until the server data arrives

hotbarFrame.Visible = true
