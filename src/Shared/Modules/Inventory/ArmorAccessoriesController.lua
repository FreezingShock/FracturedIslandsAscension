-- ============================================================
--  ArmorAccessoriesController (client ModuleScript)
--  Place inside: ReplicatedStorage > Modules  (required by CentralizedMenuController)
--
--  View for the 8 equipment slots (4 armor + 4 accessories) next to the
--  inventory. It owns NO game logic: the server (EquipmentService) decides
--  what is equipped and applies the stats; this just shows it.
--
--    - Slots show the equipped item's name letters in its rarity color
--    - Hover = tooltip (empty slot hint, or the item's full tooltip)
--    - Click a filled slot = unequip
--    - Drag an armor / accessory from the inventory onto its slot = equip
--      (InventoryController asks us for the slot under the cursor through
--       MenuBridge.updateEquipDrag; clicking the item also equips it)
--    - The clip tweens open with the inventory (via MenuBridge.onStateChanged)
--    - The Profile page's equipment buttons (Nexus menu hides the clip) use the
--      same logic through M.bindExternal(buttons)
--
--  Data: server pushes `UpdateEquipped` ({ Helmet = "iron_helmet", ... }).
-- ============================================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local Items = require(Modules:WaitForChild("Items")) :: any
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any
local SlotFx = require(Modules:WaitForChild("SlotFx")) :: any
local TooltipModule = require(Modules:WaitForChild("TooltipModule")) :: any

local SLOT_ORDER = Items.Slots.Order
local TOOLTIP_SOURCE = "equipSlot"

-- ===================== GUI REFERENCES =====================
local CentralizedMenu = playerGui:WaitForChild("CentralizedAscensionMenu")
local innerFrame = CentralizedMenu:WaitForChild("BoundingBox"):WaitForChild("outerFrame"):WaitForChild("innerFrame")
local ArmorAccessoriesClip = innerFrame:WaitForChild("ArmorAccessoriesClip")
local ArmorAccessories = ArmorAccessoriesClip:WaitForChild("ArmorAccessories")

-- ===================== REMOTES =====================
local UpdateEquippedEvent = ReplicatedStorage:WaitForChild("UpdateEquipped", 15)
local UnequipItemFunc = ReplicatedStorage:WaitForChild("UnequipItem", 15)
local GetEquippedFunc = ReplicatedStorage:WaitForChild("GetEquipped", 15)

-- ===================== STATE =====================
local addView -- forward declaration (defined under VIEW WIRING)
local initialized = false
local equipped: { [string]: string } = {}
-- Every button showing a slot: the clip's own plus any bound by the Profile page.
type View = { button: GuiButton, stroke: UIStroke?, baseColor: Color3, baseTransparency: number, letters: TextLabel }
local views: { [string]: { View } } = {}
local hoverSlot: string? = nil
local hoverValid = false
local activeTween: Tween? = nil

-- Same pixel-size tween the inventory uses so layouts recompute together.
local ARMOR_CLIP_OPEN = UDim2.new(0, 70, 0, 70)
local ARMOR_CLIP_CLOSED = UDim2.new(0, 0, 0, 0)
local TWEEN_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local VALID_COLOR = Color3.fromHex("#55FF55")
local INVALID_COLOR = Color3.fromHex("#FF5555")

-- ===================== CLIP TWEEN =====================
local function tweenClip(visible: boolean)
	if activeTween then
		activeTween:Cancel()
	end
	if visible then
		ArmorAccessoriesClip.Visible = true
		ArmorAccessories.Visible = true
	end

	ArmorAccessoriesClip.AutomaticSize = Enum.AutomaticSize.None
	ArmorAccessories.AutomaticSize = Enum.AutomaticSize.None

	local tween = TweenService:Create(
		ArmorAccessoriesClip,
		TWEEN_INFO,
		{ Size = visible and ARMOR_CLIP_OPEN or ARMOR_CLIP_CLOSED }
	)
	activeTween = tween
	tween.Completed:Once(function(state)
		if state ~= Enum.PlaybackState.Completed then
			return -- cancelled by a newer tween
		end
		ArmorAccessoriesClip.AutomaticSize = Enum.AutomaticSize.Y
		ArmorAccessories.AutomaticSize = Enum.AutomaticSize.XY
		if not visible then
			ArmorAccessories.Visible = false
			ArmorAccessoriesClip.Visible = false
		end
		activeTween = nil
	end)
	tween:Play()
end

-- ===================== SLOT VISUALS =====================
--- "Iron Helmet" -> "IH", "Excalibur" -> "EX"
local function letters(name: string): string
	local words = {}
	for word in name:gmatch("[%a']+") do
		table.insert(words, (word:gsub("'", "")))
	end
	if #words >= 2 then
		return (words[1]:sub(1, 1) .. words[2]:sub(1, 1)):upper()
	end
	return (words[1] or "?"):sub(1, 2):upper()
end

local function renderView(slotId: string, view: View)
	local def = equipped[slotId] and Items.get(equipped[slotId])
	local icon = view.button:FindFirstChild("Icon")

	local color = view.baseColor
	if def then
		local rarity = Items.getRarity(def.rarity)
		color = rarity.color
		view.letters.Text = letters(def.displayName)
		view.letters.TextColor3 = rarity.color
		view.letters.Visible = true
	else
		-- Empty: accessories have no art of their own (the template reuses the
		-- helmet icon), so show the slot's short name, dimmed, instead.
		local slotDef = Items.Slots.get(slotId)
		if slotDef.short then
			view.letters.Text = slotDef.short
			view.letters.TextColor3 = Color3.fromHex(slotDef.color)
			view.letters.TextTransparency = 0.45
			view.letters.Visible = true
		else
			view.letters.Visible = false
		end
	end
	if def then
		view.letters.TextTransparency = 0
	end

	-- Equipped item art replaces the letters; the slot's own placeholder art stays for empty slots.
	local itemImage = ItemIcons.ensureImage(view.button, { size = UDim2.fromScale(0.7, 0.7), position = UDim2.fromScale(0.5, 0.5), zIndex = (icon and icon.ZIndex or 1) + 1 })
	local hasItemIcon = def ~= nil and ItemIcons.apply(itemImage, def)
	itemImage.Visible = hasItemIcon
	if hasItemIcon then
		view.letters.Visible = false
	end

	if icon and icon:IsA("ImageLabel") then
		-- the slot's own placeholder art shows only when empty and no short label replaces it
		icon.Visible = def == nil and Items.Slots.get(slotId).short == nil
	end

	if view.stroke then
		if hoverSlot == slotId then
			view.stroke.Color = hoverValid and VALID_COLOR or INVALID_COLOR
			view.stroke.Transparency = 0
		else
			view.stroke.Color = color
			view.stroke.Transparency = def and 0 or view.baseTransparency
		end
	end
end

local function renderSlot(slotId: string)
	for _, view in ipairs(views[slotId] or {}) do
		if view.button.Parent then
			renderView(slotId, view)
		end
	end
end

local function renderAll()
	for _, slotId in ipairs(SLOT_ORDER) do
		renderSlot(slotId)
	end
end

-- ===================== TOOLTIP =====================
local function showSlotTooltip(slotId: string, button: GuiButton)
	local slot = Items.Slots.get(slotId)
	local def = equipped[slotId] and Items.get(equipped[slotId])

	local config
	if def then
		config = TooltipModule.Items.fromTool({
			name = def.toolName,
			displayName = def.displayName,
			rarity = def.rarity,
		})
		config.click = { text = "TO UNEQUIP", color = "#FF5555", icon = "lmb" }
	else
		config = {
			title = slot.displayName,
			titleColor = slot.color,
			icon = { color = slot.color },
			tags = { { text = slot.type == "armor" and "Armor" or "Accessory", color = "#FFFFFF" } },
			description = "Empty. Click an item in your inventory, or drag it here, to equip it.",
		}
	end
	TooltipModule.show(config, TOOLTIP_SOURCE .. slotId, button)
end

-- ===================== INPUT =====================
local function onSlotClick(slotId: string)
	if not equipped[slotId] or not UnequipItemFunc then
		return
	end
	TooltipModule.forceHide()
	task.spawn(function()
		UnequipItemFunc:InvokeServer(slotId)
	end)
end

-- ===================== DRAG SUPPORT =====================
local function slotAtPosition(pos: Vector2): string?
	for slotId, list in pairs(views) do
		for _, view in ipairs(list) do
			local button = view.button
			if button.Parent and button.AbsoluteSize.X > 1 and TooltipModule.isShown(button) then
				local p, sz = button.AbsolutePosition, button.AbsoluteSize
				if pos.X >= p.X and pos.X <= p.X + sz.X and pos.Y >= p.Y and pos.Y <= p.Y + sz.Y then
					return slotId
				end
			end
		end
	end
	return nil
end

--- Called by InventoryController while dragging an item.
--- screenPos nil = drag ended. itemSlotId = the slot the dragged item fits (or nil).
MenuBridge._updateEquipDrag = function(screenPos: Vector2?, itemSlotId: string?): string?
	local previous = hoverSlot
	local over = screenPos and slotAtPosition(screenPos) or nil
	hoverSlot = over
	hoverValid = over ~= nil and over == itemSlotId
	if previous and previous ~= over then
		renderSlot(previous)
	end
	if over then
		renderSlot(over)
	end
	return over
end

-- ===================== VIEW WIRING =====================
--- Make `button` display + control `slotId`. Returns the view and a disconnect fn.
addView = function(slotId: string, button: GuiButton)
	local slot = Items.Slots.get(slotId)
	local bg = button:FindFirstChild("BG")
	local stroke = bg and bg:FindFirstChildOfClass("UIStroke") or nil

	local label = Instance.new("TextLabel")
	label.Name = "Letters"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.FontFace = Font.new(TooltipModule.Style.FONT_PIXEL)
	label.TextSize = 16
	label.TextStrokeTransparency = 0.4
	label.ZIndex = 10
	label.Visible = false
	label.Text = ""
	label.Parent = button

	local view: View = {
		button = button,
		stroke = stroke,
		baseColor = stroke and stroke.Color or Color3.fromHex(slot.color),
		baseTransparency = stroke and stroke.Transparency or 0,
		letters = label,
	}
	views[slotId] = views[slotId] or {}
	table.insert(views[slotId], view)

	local conns = {
		button.MouseEnter:Connect(function()
			showSlotTooltip(slotId, button)
		end),
		button.MouseLeave:Connect(function()
			TooltipModule.hide(TOOLTIP_SOURCE .. slotId)
		end),
		button.MouseButton1Click:Connect(function()
			onSlotClick(slotId)
		end),
	}

	table.insert(conns, SlotFx.bind(button))
	renderView(slotId, view)

	return view, function()
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		local list = views[slotId]
		if list then
			local i = table.find(list, view)
			if i then
				table.remove(list, i)
			end
		end
	end
end

-- ===================== DATA =====================
local function loadEquipped(data: { [string]: string }?)
	equipped = {}
	for slotId, itemId in pairs(data or {}) do
		if Items.Slots.exists(slotId) then
			equipped[slotId] = itemId
		end
	end
	renderAll()
end

-- ===================== INIT =====================
local function init()
	if initialized then
		return
	end
	initialized = true

	for _, slotId in ipairs(SLOT_ORDER) do
		local button = ArmorAccessories:FindFirstChild(slotId)
		if button and button:IsA("GuiButton") then
			addView(slotId, button)
		else
			warn("[ArmorAccessoriesController] slot button not found: " .. slotId)
		end
	end

	MenuBridge.onStateChanged(function(mode)
		tweenClip(mode == "inventory")
	end)

	if UpdateEquippedEvent then
		UpdateEquippedEvent.OnClientEvent:Connect(loadEquipped)
	end
	if GetEquippedFunc then
		task.spawn(function()
			local ok, data = pcall(function()
				return GetEquippedFunc:InvokeServer()
			end)
			if ok then
				loadEquipped(data)
			end
		end)
	end

	renderAll()
end

-- ===================== PUBLIC API =====================
local M = {}

function M.init()
	init()
end

function M.loadEquipped(data)
	loadEquipped(data)
end

function M.getEquipped()
	return equipped
end

--- Bind buttons (keyed by slot id, e.g. the Profile grid's Helmet/Cloak/...)
--- to the equipment state. Returns a function that unbinds them.
function M.bindExternal(buttons: { [string]: GuiButton }): () -> ()
	local cleanups = {}
	for slotId, button in pairs(buttons) do
		if Items.Slots.exists(slotId) and button:IsA("GuiButton") then
			local _, cleanup = addView(slotId, button)
			table.insert(cleanups, cleanup)
		end
	end
	return function()
		for _, cleanup in ipairs(cleanups) do
			cleanup()
		end
	end
end

function M.tweenClip(visible)
	tweenClip(visible)
end

task.spawn(init)

return M
