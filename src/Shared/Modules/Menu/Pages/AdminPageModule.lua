--[[
	AdminPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Client side of the Nexus admin panel (admin ids only). It is a developer tool:
	see every item, give yourself items / statistics, add temporary attribute bonuses.

	Two pieces:
	  addNexusButton(frame, baseButton, config)  Nexus home, top-right cell. Admins get the
	                                             button; everyone else keeps the blank slot.
	  AdminGrid page (populate / depopulate)     one grid, four tabs: Items, Stats, Bonuses, Tools.

	Security: hiding the button is cosmetic. Every action goes through the server's
	AdminAction RemoteFunction, which re-checks AdminConfig.isAdmin and validates inputs.

	Page layout (9 columns x 6 rows, LayoutOrder = 9 * row + col):
	  row 0       tabs at col 2-5, status at col 8
	  rows 1-4    content, cols 1-7 (28 slots per page)
	  row 5       paging / filters, Back + Close at the end

	Wiring (CentralizedMenuController):
	  init(sharedRefs)  -> then registerPooledGrid("AdminGrid", getTemplateFolder(), ...)
	  populate(frame) / depopulate()   grid onPopulate / onDepopulate hooks
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AdminConfig = require(Modules:WaitForChild("AdminConfig")) :: any
local Items = require(Modules:WaitForChild("Items")) :: any
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
local Attributes = require(Modules:WaitForChild("Attributes")) :: any
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any
local StatisticsPageModule = require(Modules:WaitForChild("StatisticsPageModule")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

local player = Players.LocalPlayer

local TOOLTIP_SOURCE = "admin"
local PAGE_SIZE = 28
local PER_ROW = 7
local LAST_CELL = 53
local BACK_ORDER = 52
local CLOSE_ORDER = 53
local NEXUS_ADMIN_ORDER = -1 -- the blank this button replaces (see NEXUS_BLANK_GROUPS)

local TABS = {
	{ key = "Items", color = "#55FF55" },
	{ key = "Stats", color = "#FFAA00" },
	{ key = "Bonuses", color = "#55FFFF" },
	{ key = "Tools", color = "#FF5555" },
}
local CATEGORIES = { false, "weapon", "armor", "accessory", "material", "consumable", "misc" } -- false = all
local RARITIES = { false, 0, 1, 2, 3, 4, 5, 6 }
local CATEGORY_COLORS = {
	all = "#FFFFFF",
	weapon = "#FF5555",
	armor = "#55FFFF",
	accessory = "#FF55FF",
	material = "#55FF55",
	consumable = "#FFAA00",
	misc = "#AAAAAA",
}
local STACK_CAP = 64

-- ===================== AUDIO =====================
local UISounds = workspace:WaitForChild("UISounds")
local UIClick = UISounds:WaitForChild("Click")
local UIClick3 = UISounds:WaitForChild("Click3")

-- ===================== STATE =====================
local M = {}

local TooltipModule = nil
local statSlotTemplate = nil
local blankSlotTemplate = nil
local templateFolder = nil

-- What the panel shows. Survives closing/reopening the menu.
local view = {
	tab = "Items",
	itemPage = 1,
	category = false,
	rarity = false,
	search = "",
	skill = "Farming",
	amount = 100,
	attrPage = 1,
	attr = nil,
	bonusMode = "flat",
	bonusAmount = 10,
	bonusDuration = 60,
	cap = 100,
}
local status = { ok = true, msg = "Ready" }

local ui = nil -- active page: { frame, gen, content, used, conns, statSlots, bonusSlots, statusSlot }
local generation = 0

-- ===================== HELPERS =====================
local function hexColor(hex)
	return Color3.fromHex((tostring(hex):gsub("#", "")))
end

local function fmt(n)
	return MoneyLib.DealWithPoints(n)
end

local function rich(hex, text)
	return string.format('<font color="%s">%s</font>', hex, text)
end

local function invoke(action, payload)
	local remote = ReplicatedStorage:WaitForChild("AdminAction", 5)
	if not remote then
		return { ok = false, msg = "AdminAction remote missing" }
	end
	local success, result = pcall(function()
		return remote:InvokeServer(action, payload)
	end)
	if not success or type(result) ~= "table" then
		return { ok = false, msg = "Request failed" }
	end
	return result
end

local function setStatus(ok, msg)
	status.ok, status.msg = ok, msg
	print(string.format("[AdminPanel] %s %s", ok and "OK" or "ERR", msg))
	local slot = ui and ui.statusSlot
	if slot and slot.Parent then
		local color = hexColor(ok and "#55FF55" or "#FF5555")
		slot.BackgroundColor3 = color
		local bg = slot:FindFirstChild("BG")
		if bg then
			bg.ImageColor3 = color
		end
		local label = slot:FindFirstChild("Label")
		if label then
			label.Text = ok and "OK" or "ERR"
		end
	end
end

--- Run a server action without blocking the UI. `after(result)` runs on the same page only.
local function act(action, payload, after)
	local mine = ui
	task.spawn(function()
		local result = invoke(action, payload)
		if ui == mine then
			setStatus(result.ok, result.msg or "")
			if after then
				after(result)
			end
		end
	end)
end

local function shiftDown()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- ===================== BUTTON TEXT STYLE =====================
-- Every piece of text on an admin button: Silkscreen, a 2px outline, and a white -> grey vertical-ish fade.
local BUTTON_FONT = Font.new("rbxassetid://12187371840") -- Silkscreen (TooltipModule.Style.FONT_PIXEL)
local BUTTON_TEXT_GRADIENT = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 170))

local function styleButtonText(textObject)
	textObject.FontFace = BUTTON_FONT
	local stroke = textObject:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = textObject
	local gradient = textObject:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	gradient.Color = BUTTON_TEXT_GRADIENT
	gradient.Rotation = 90 -- top white, bottom grey
	gradient.Parent = textObject
end

-- ===================== SLOT BUILDERS =====================
local function addLabel(slot, text, color)
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.9, 0.55)
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Text = text
	label.ZIndex = 5
	styleButtonText(label)
	label.Parent = slot
	return label
end

--- Clone a StatSlot into the page. o: color, icon, count, label, tip, onClick(shift), selected, name
local function newSlot(lo, o)
	local slot = statSlotTemplate:Clone()
	slot.Name = o.name or "AdminSlot"
	slot.LayoutOrder = lo
	slot.Visible = true

	local color = hexColor(o.color or "#555555")
	slot.BackgroundColor3 = color
	local bg = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = o.selected and Color3.new(1, 1, 1) or color
			if o.selected then
				stroke.Thickness = math.max(stroke.Thickness, 2) + 1
			end
		end
	end
	local icon = slot:FindFirstChild("Icon")
	if icon then
		if o.item then
			ItemIcons.apply(icon, o.item)
		else
			icon.Image = o.icon or ""
		end
	end
	local countLabel = slot:FindFirstChild("ItemCount")
	if not countLabel and o.count then
		-- The runtime StatSlot has no count label; add a bottom-right one.
		countLabel = Instance.new("TextLabel")
		countLabel.Name = "ItemCount"
		countLabel.BackgroundTransparency = 1
		countLabel.AnchorPoint = Vector2.new(1, 1)
		countLabel.Position = UDim2.fromScale(0.96, 0.96)
		countLabel.Size = UDim2.fromScale(0.8, 0.3)
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.TextScaled = true
		countLabel.TextColor3 = Color3.new(1, 1, 1)
		countLabel.ZIndex = 6
		styleButtonText(countLabel)
		countLabel.Parent = slot
	end
	if countLabel then
		countLabel.Text = o.count or ""
	end
	if o.label then
		addLabel(slot, o.label, o.labelColor and hexColor(o.labelColor))
	end

	if o.tip then
		slot.MouseEnter:Connect(function()
			UIClick3:Play()
			local tip = type(o.tip) == "function" and o.tip() or o.tip
			TooltipModule.show(tip, TOOLTIP_SOURCE, slot)
		end)
		slot.MouseLeave:Connect(function()
			TooltipModule.hide(TOOLTIP_SOURCE)
		end)
	end
	if o.onClick then
		slot.MouseButton1Click:Connect(function()
			UIClick:Play()
			o.onClick(shiftDown())
		end)
	end
	if o.onRightClick then
		slot.MouseButton2Click:Connect(function()
			UIClick:Play()
			o.onRightClick()
		end)
	end

	ui.used[lo] = true
	table.insert(ui.content, slot) -- a rebuild drops everything listed here
	slot.Parent = ui.frame
	return slot
end

--- A slot with a TextBox in it. o: color, placeholder, text, tip, onChange(text)
local function newInput(lo, o)
	local slot = newSlot(lo, { color = o.color, tip = o.tip, name = o.name })
	local box = Instance.new("TextBox")
	box.Name = "Input"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromScale(0.86, 0.5)
	box.BackgroundColor3 = Color3.new(0, 0, 0)
	box.BackgroundTransparency = 0.4
	box.BorderSizePixel = 0
	box.TextColor3 = o.textColor and hexColor(o.textColor) or Color3.new(1, 1, 1)
	box.PlaceholderText = o.placeholder or ""
	box.Text = o.text or ""
	box.ClearTextOnFocus = false
	box.TextScaled = true
	box.ZIndex = 6
	styleButtonText(box)
	box.FocusLost:Connect(function()
		o.onChange(box.Text)
	end)
	box.Parent = slot
	return slot, box
end

-- ===================== SELECTOR (cycling filter button) =====================
-- A button that steps through a list of options. The tooltip shows EVERY option as a bullet list with a thick
-- arrow on the selected one: left click goes down the list, right click goes up. Each option has its own
-- colour, used for its tooltip line and for the button's text (Silkscreen, see styleButtonText).
--   o: name, title, color (title colour), desc (string | function), options = { { value, label, color } },
--      get() -> current value, set(value)  (set() normally rebuilds the page)
local SELECTOR_SLOT_COLOR = "#3A3A3A" -- neutral, so the coloured text stays readable

local function selectorTip(o, index)
	local lines = {}
	for i, opt in ipairs(o.options) do
		if i == index then
			table.insert(lines, rich("#FFFF55", "►") .. " " .. rich(opt.color, "<b>" .. opt.label .. "</b>"))
		else
			table.insert(lines, rich("#AAAAAA", "•") .. " " .. rich(opt.color, opt.label))
		end
	end
	local desc = type(o.desc) == "function" and o.desc() or o.desc
	return {
		title = rich(o.color, "<b>" .. o.title .. "</b>"),
		description = desc,
		blocks = { { text = table.concat(lines, "\n"), align = "Left", dynamic = true } },
		dividers = { d1 = true, d4 = true }, -- a divider above and below the list
		click = {
			{ text = "TO GO DOWN", color = "#55FFFF", icon = "lmb" },
			{ text = "TO GO UP", color = "#55FF55", icon = "rmb" },
		},
	}
end

local function newSelector(lo, o)
	local index = 1
	local current = o.get()
	for i, opt in ipairs(o.options) do
		if opt.value == current then
			index = i
			break
		end
	end
	local opt = o.options[index]

	local function step(delta)
		o.set(o.options[(index - 1 + delta) % #o.options + 1].value)
	end

	local slot = newSlot(lo, {
		name = o.name,
		color = SELECTOR_SLOT_COLOR,
		label = opt.label,
		labelColor = opt.color,
		tip = function()
			return selectorTip(o, index)
		end,
		onClick = function()
			step(1)
		end,
		onRightClick = function()
			step(-1)
		end,
	})
	-- A click rebuilds the page, so the slot under the cursor is brand new and never gets a MouseEnter:
	-- once it has been laid out, put the tooltip straight back (showing the new selection) if the cursor is on it.
	task.delay(0.08, function()
		if not slot.Parent or not TooltipModule.isShown(slot) then
			return
		end
		local mouse = UserInputService:GetMouseLocation() - game:GetService("GuiService"):GetGuiInset()
		local pos, size = slot.AbsolutePosition, slot.AbsoluteSize
		if mouse.X >= pos.X and mouse.X <= pos.X + size.X and mouse.Y >= pos.Y and mouse.Y <= pos.Y + size.Y then
			TooltipModule.show(selectorTip(o, index), TOOLTIP_SOURCE, slot)
		end
	end)
	return slot
end

-- ===================== PAGE CHROME =====================
local rebuild -- forward declaration

local function pager(page, pages, setPage)
	newSlot(48, {
		name = "Prev",
		color = "#AAAAAA",
		label = "<",
		tip = { title = rich("#FFFFFF", "<b>Previous page</b>"), desc = "", click = "" },
		onClick = function()
			setPage(math.max(1, page - 1))
			rebuild()
		end,
	})
	newSlot(49, { name = "PageLabel", color = "#555555", label = string.format("%d/%d", page, pages) })
	newSlot(50, {
		name = "Next",
		color = "#AAAAAA",
		label = ">",
		tip = { title = rich("#FFFFFF", "<b>Next page</b>"), desc = "", click = "" },
		onClick = function()
			setPage(math.min(pages, page + 1))
			rebuild()
		end,
	})
end

local function cycle(list, current, step)
	local index = table.find(list, current) or 1
	return list[(index - 1 + step) % #list + 1]
end

-- ===================== TAB: ITEMS =====================
local function buildItems()
	local matches = {}
	for _, def in ipairs(Items.list()) do
		local name = (def.displayName or def.id):lower()
		if
			(not view.category or def.category == view.category)
			and (view.rarity == false or def.rarity == view.rarity)
			and (view.search == "" or name:find(view.search, 1, true) or def.id:lower():find(view.search, 1, true))
		then
			table.insert(matches, def)
		end
	end

	local pages = math.max(1, math.ceil(#matches / PAGE_SIZE))
	view.itemPage = math.clamp(view.itemPage, 1, pages)

	for i = 1, PAGE_SIZE do
		local def = matches[(view.itemPage - 1) * PAGE_SIZE + i]
		if not def then
			break
		end
		local row, col = (i - 1) // PER_ROW + 1, (i - 1) % PER_ROW + 1
		local rarity = Items.getRarity(def.rarity)
		local rarityHex = rarity and rarity.hexColor or "#AAAAAA"
		local stack = (def.maxStack or 1) > 1 and math.min(def.maxStack, STACK_CAP) or 5
		local hasIcon = not ItemIcons.resolve(def).placeholder
		newSlot(9 * row + col, {
			name = "Item_" .. def.id,
			color = rarityHex,
			item = def,
			label = not hasIcon and def.displayName:sub(1, 3):upper() or nil,
			tip = {
				title = rich(rarityHex, "<b>" .. (def.displayName or def.id) .. "</b>"),
				desc = string.format(
					"%s\n%s",
					rich("#AAAAAA", string.format("%s  -  %s  -  id: %s", rarity and rarity.name or "?", def.category, def.id)),
					rich("#555555", "Shift-click to give " .. stack)
				),
				click = rich("#FFFF55", "Click to give 1!"),
			},
			onClick = function(shift)
				act("give", { itemId = def.id, count = shift and stack or 1 })
			end,
		})
	end

	-- Footer: search, category, rarity, pager
	newInput(45, {
		name = "Search",
		color = "#55FF55",
		textColor = "#55FF55",
		placeholder = "search",
		text = view.search,
		tip = { title = rich("#55FF55", "<b>Search</b>"), desc = rich("#AAAAAA", "Matches name or id."), click = "" },
		onChange = function(text)
			view.search = text:lower()
			view.itemPage = 1
			rebuild()
		end,
	})
	local categoryOptions = {}
	for _, category in ipairs(CATEGORIES) do
		table.insert(categoryOptions, {
			value = category,
			label = category or "all",
			color = CATEGORY_COLORS[category or "all"],
		})
	end
	newSelector(46, {
		name = "Category",
		title = "Category",
		color = "#FFAA00",
		desc = rich("#AAAAAA", "Filter the item list."),
		options = categoryOptions,
		get = function()
			return view.category
		end,
		set = function(value)
			view.category = value
			view.itemPage = 1
			rebuild()
		end,
	})

	local rarityOptions = {}
	for _, rarity in ipairs(RARITIES) do
		local config = rarity ~= false and Items.getRarity(rarity)
		table.insert(rarityOptions, {
			value = rarity,
			label = config and config.name or "any",
			color = config and config.hexColor or "#FFFFFF",
		})
	end
	newSelector(47, {
		name = "Rarity",
		title = "Rarity",
		color = "#FFFFFF",
		desc = function()
			return rich("#AAAAAA", string.format("%d matching items", #matches))
		end,
		options = rarityOptions,
		get = function()
			return view.rarity
		end,
		set = function(value)
			view.rarity = value
			view.itemPage = 1
			rebuild()
		end,
	})
	pager(view.itemPage, pages, function(page)
		view.itemPage = page
	end)
end

-- ===================== TAB: STATS =====================
local function ownedCount(skill, key)
	return StatisticsPageModule.getCount(skill, key)
end

local function buildStats()
	for i, skill in ipairs(StatisticsConfig.SKILL_NAMES) do
		newSlot(9 + i, {
			name = "Skill_" .. skill,
			color = StatisticsConfig.SKILL_COLORS[skill],
			label = skill,
			selected = view.skill == skill,
			tip = { title = rich(StatisticsConfig.SKILL_COLORS[skill], "<b>" .. skill .. "</b>"), desc = "", click = rich("#FFFF55", "Click to select!") },
			onClick = function()
				view.skill = skill
				rebuild()
			end,
		})
	end
	newInput(16, {
		name = "Amount",
		color = "#FFAA00",
		placeholder = "amount",
		text = tostring(view.amount),
		tip = { title = rich("#FFAA00", "<b>Amount</b>"), desc = rich("#AAAAAA", "Clicking a statistic sets it to this."), click = "" },
		onChange = function(text)
			view.amount = math.clamp(math.floor(tonumber(text) or view.amount), 0, AdminConfig.MAX_STAT)
		end,
	})

	local chain = StatisticsConfig.STAT_CHAINS[view.skill] or {}
	for i, item in ipairs(chain) do
		if i > 2 * PER_ROW then
			break
		end
		local row, col = (i - 1) // PER_ROW + 2, (i - 1) % PER_ROW + 1
		local slot = newSlot(9 * row + col, {
			name = "Stat_" .. item.key,
			color = item.color,
			icon = item.icon,
			count = fmt(ownedCount(view.skill, item.key)),
			tip = function()
				return {
					title = rich(item.color or "#FFFFFF", "<b>" .. (item.name or item.key) .. "</b>"),
					desc = rich("#AAAAAA", "Owned: ") .. rich("#FFFFFF", fmt(ownedCount(view.skill, item.key))),
					click = rich("#FFFF55", "Click to set to " .. fmt(view.amount) .. "!"),
				}
			end,
			onClick = function()
				act("setStat", { skill = view.skill, key = item.key, count = view.amount })
			end,
		})
		ui.statSlots[item.key] = slot
	end

	newSlot(37, {
		name = "MaxAll",
		color = "#55FF55",
		label = "Max all",
		tip = { title = rich("#55FF55", "<b>Max all statistics</b>"), desc = rich("#AAAAAA", "Sets every statistic to " .. fmt(AdminConfig.MAX_STAT) .. "."), click = rich("#FFFF55", "Click!") },
		onClick = function()
			act("maxStats")
		end,
	})
	newSlot(38, {
		name = "Restore",
		color = "#FF5555",
		label = "Restore",
		tip = { title = rich("#FF5555", "<b>Restore statistics</b>"), desc = rich("#AAAAAA", "Undo every admin edit this session (real progress is kept)."), click = rich("#FFFF55", "Click!") },
		onClick = function()
			act("restoreStats")
		end,
	})
end

local function refreshStatCounts()
	for key, slot in pairs(ui and ui.statSlots or {}) do
		local countLabel = slot.Parent and slot:FindFirstChild("ItemCount")
		if countLabel then
			countLabel.Text = fmt(ownedCount(view.skill, key))
		end
	end
end

-- ===================== TAB: BONUSES =====================
local function sortedAttributes()
	local list = {}
	for _, def in pairs(Attributes.all()) do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	return list
end

local function bonusText(bonus)
	local def = Attributes.get(bonus.attr)
	local amount = bonus.mode == "pct" and string.format("+%s%%", fmt(bonus.amount)) or string.format("%+g", bonus.amount)
	return (def and def.name or bonus.attr), amount
end

--- Row 4 (cells 36-44): one slot per active temp bonus (click to remove), blanks elsewhere.
--- Re-rendered on every refresh, so it owns its cells and tracks them in ui.bonusSlots.
local function renderBonusRow(bonuses)
	for _, slot in ipairs(ui.bonusSlots) do
		slot:Destroy()
	end
	table.clear(ui.bonusSlots)

	for lo = 36, 44 do
		local bonus = bonuses[lo - 36]
		if bonus then
			local attrName, amount = bonusText(bonus)
			local def = Attributes.get(bonus.attr)
			table.insert(
				ui.bonusSlots,
				newSlot(lo, {
					name = "Bonus_" .. bonus.id,
					color = def and def.color or "#FF55FF",
					label = amount,
					count = bonus.remaining and (bonus.remaining .. "s") or "inf",
					tip = {
						title = rich("#FF55FF", "<b>" .. attrName .. " " .. amount .. "</b>"),
						desc = rich("#AAAAAA", bonus.remaining and ("Expires in " .. bonus.remaining .. "s") or "Until cleared"),
						click = rich("#FF5555", "Click to remove!"),
					},
					onClick = function()
						act("removeBonus", { id = bonus.id }, function()
							M.refreshBonuses()
						end)
					end,
				})
			)
		elseif blankSlotTemplate then
			local blank = blankSlotTemplate:Clone()
			blank.LayoutOrder = lo
			blank.Visible = true
			blank.Parent = ui.frame
			ui.used[lo] = true
			table.insert(ui.bonusSlots, blank)
		end
	end
end

function M.refreshBonuses()
	local mine = ui
	if not mine or view.tab ~= "Bonuses" then
		return
	end
	task.spawn(function()
		local result = invoke("listBonuses")
		if ui == mine and view.tab == "Bonuses" and result.ok and type(result.data) == "table" then
			renderBonusRow(result.data)
		end
	end)
end

local function buildBonuses()
	local attrs = sortedAttributes()
	local pages = math.max(1, math.ceil(#attrs / (2 * PER_ROW)))
	view.attrPage = math.clamp(view.attrPage, 1, pages)

	for i = 1, 2 * PER_ROW do
		local def = attrs[(view.attrPage - 1) * 2 * PER_ROW + i]
		if not def then
			break
		end
		local row, col = (i - 1) // PER_ROW + 1, (i - 1) % PER_ROW + 1
		newSlot(9 * row + col, {
			name = "Attr_" .. def.key,
			color = def.color,
			label = def.name,
			selected = view.attr == def.key,
			tip = { title = rich(def.color or "#FFFFFF", "<b>" .. def.name .. "</b>"), desc = rich("#AAAAAA", def.description or ""), click = rich("#FFFF55", "Click to select!") },
			onClick = function()
				view.attr = def.key
				rebuild()
			end,
		})
	end

	-- Row 3: mode, amount, duration, add
	newSelector(28, {
		name = "Mode",
		title = "Bonus type",
		color = "#55FFFF",
		desc = function()
			return rich("#AAAAAA", view.bonusMode == "pct" and "Percent: x(1 + amount/100)" or "Flat: added to the attribute")
		end,
		options = {
			{ value = "flat", label = "Flat", color = "#55FF55" },
			{ value = "pct", label = "%", color = "#FFAA00" },
		},
		get = function()
			return view.bonusMode
		end,
		set = function(value)
			view.bonusMode = value
			rebuild()
		end,
	})
	newInput(29, {
		name = "BonusAmount",
		color = "#55FFFF",
		placeholder = "amount",
		text = tostring(view.bonusAmount),
		tip = { title = rich("#55FFFF", "<b>Amount</b>"), desc = rich("#AAAAAA", "Negative numbers work."), click = "" },
		onChange = function(text)
			view.bonusAmount = tonumber(text) or view.bonusAmount
		end,
	})
	newInput(30, {
		name = "BonusDuration",
		color = "#55FFFF",
		placeholder = "secs",
		text = tostring(view.bonusDuration),
		tip = { title = rich("#55FFFF", "<b>Duration (seconds)</b>"), desc = rich("#AAAAAA", "0 = until removed."), click = "" },
		onChange = function(text)
			view.bonusDuration = math.max(0, math.floor(tonumber(text) or view.bonusDuration))
		end,
	})
	newSlot(31, {
		name = "AddBonus",
		color = "#55FF55",
		label = "ADD",
		tip = function()
			local def = view.attr and Attributes.get(view.attr)
			return {
				title = rich("#55FF55", "<b>Add bonus</b>"),
				desc = rich("#AAAAAA", def and def.name or "Select an attribute first"),
				click = rich("#FFFF55", "Click to add!"),
			}
		end,
		onClick = function()
			if not view.attr then
				return setStatus(false, "Select an attribute first")
			end
			act("addBonus", {
				attr = view.attr,
				mode = view.bonusMode,
				amount = view.bonusAmount,
				duration = view.bonusDuration,
			}, function()
				M.refreshBonuses()
			end)
		end,
	})

	pager(view.attrPage, pages, function(page)
		view.attrPage = page
	end)
	renderBonusRow({}) -- blanks now, real bonuses as soon as the server answers
	M.refreshBonuses()
end

-- ===================== TAB: TOOLS =====================
local function buildTools()
	newSlot(10, {
		name = "ClearItems",
		color = "#FF5555",
		label = "Clear items",
		tip = { title = rich("#FF5555", "<b>Clear inventory</b>"), desc = rich("#AAAAAA", "Removes every item and unequips armor."), click = rich("#FFFF55", "Click!") },
		onClick = function()
			act("clearItems")
		end,
	})
	newSlot(11, {
		name = "ClearBonuses",
		color = "#FF55FF",
		label = "Clear bonuses",
		tip = { title = rich("#FF55FF", "<b>Clear bonuses</b>"), desc = rich("#AAAAAA", "Removes every admin bonus."), click = rich("#FFFF55", "Click!") },
		onClick = function()
			act("clearBonuses")
		end,
	})
	newInput(13, {
		name = "CapAmount",
		color = "#FFAA00",
		placeholder = "slots",
		text = tostring(view.cap),
		tip = { title = rich("#FFAA00", "<b>Capacity</b>"), desc = rich("#AAAAAA", "Max inventory slots."), click = "" },
		onChange = function(text)
			view.cap = math.max(1, math.floor(tonumber(text) or view.cap))
		end,
	})
	newSlot(14, {
		name = "SetCap",
		color = "#FFAA00",
		label = "Set cap",
		tip = { title = rich("#FFAA00", "<b>Set capacity</b>"), desc = rich("#AAAAAA", "Applies the number to the left."), click = rich("#FFFF55", "Click!") },
		onClick = function()
			act("setCap", { cap = view.cap })
		end,
	})
end

local BUILDERS = { Items = buildItems, Stats = buildStats, Bonuses = buildBonuses, Tools = buildTools }

-- ===================== PAGE BUILD =====================
local function clearContent()
	for _, instance in ipairs(ui.bonusSlots) do
		instance:Destroy() -- includes the blanks renderBonusRow adds outside ui.content
	end
	for _, instance in ipairs(ui.content) do
		instance:Destroy()
	end
	table.clear(ui.content)
	table.clear(ui.used)
	table.clear(ui.statSlots)
	table.clear(ui.bonusSlots)
	ui.used[BACK_ORDER] = true
	ui.used[CLOSE_ORDER] = true
end

local function build()
	local frame = ui.frame

	for index, tab in ipairs(TABS) do
		newSlot(1 + index, {
			name = "Tab_" .. tab.key,
			color = tab.color,
			label = tab.key,
			selected = view.tab == tab.key,
			tip = { title = rich(tab.color, "<b>" .. tab.key .. "</b>"), desc = "", click = rich("#FFFF55", "Click to open!") },
			onClick = function()
				if view.tab ~= tab.key then
					view.tab = tab.key
					rebuild()
				end
			end,
		})
	end
	ui.statusSlot = newSlot(8, {
		name = "Status",
		color = status.ok and "#55FF55" or "#FF5555",
		label = status.ok and "OK" or "ERR",
		tip = function()
			return { title = rich(status.ok and "#55FF55" or "#FF5555", "<b>Last action</b>"), desc = rich("#AAAAAA", status.msg), click = "" }
		end,
	})

	BUILDERS[view.tab]()

	-- Everything not used gets a blank so the grid stays full.
	if blankSlotTemplate then
		for lo = 0, LAST_CELL do
			if not ui.used[lo] then
				local blank = blankSlotTemplate:Clone()
				blank.LayoutOrder = lo
				blank.Visible = true
				blank.Parent = frame
				table.insert(ui.content, blank)
				ui.used[lo] = true
			end
		end
	end
end

rebuild = function()
	if not ui then
		return
	end
	TooltipModule.hide(TOOLTIP_SOURCE)
	clearContent()
	build()
end

-- ===================== GRID HOOKS =====================
function M.populate(frame)
	if not AdminConfig.isAdmin(player) then
		warn("[AdminPageModule] populate refused: not an admin")
		return
	end
	if not (statSlotTemplate and blankSlotTemplate) then
		warn("[AdminPageModule] Slot templates missing - cannot build page")
		return
	end

	generation += 1
	ui = {
		frame = frame,
		gen = generation,
		content = {},
		used = {},
		conns = {},
		statSlots = {},
		bonusSlots = {},
		statusSlot = nil,
	}
	ui.used[BACK_ORDER] = true
	ui.used[CLOSE_ORDER] = true

	local back = frame:FindFirstChild("BackButton")
	if back then
		back.LayoutOrder = BACK_ORDER
	end
	local close = frame:FindFirstChild("CloseSlot")
	if close then
		close.LayoutOrder = CLOSE_ORDER
	end

	-- Keep Stats counts live while the page is open.
	table.insert(
		ui.conns,
		ReplicatedStorage:WaitForChild("StatisticsUpdated").OnClientEvent:Connect(function()
			task.defer(refreshStatCounts)
		end)
	)

	-- Active bonuses expire on a timer: refresh the row once a second while it is visible.
	local mine = ui
	task.spawn(function()
		while ui == mine do
			task.wait(1)
			if ui == mine and view.tab == "Bonuses" then
				M.refreshBonuses()
			end
		end
	end)

	build()
end

--- The grid destroys the children itself; this drops our references.
function M.depopulate()
	if ui then
		for _, conn in ipairs(ui.conns) do
			conn:Disconnect()
		end
	end
	ui = nil
	if TooltipModule then
		TooltipModule.forceHide()
	end
end

function M.getTemplateFolder()
	return templateFolder
end

-- ===================== NEXUS BUTTON =====================
--- Called from the Nexus grid's onWireTooltips. Admins get a button in the top-right cell
--- (replacing the blank there); everyone else keeps the blank. Returns connections.
function M.addNexusButton(frame, baseButton, config)
	local conns = {}
	if not (frame and baseButton and AdminConfig.isAdmin(player)) then
		return conns
	end

	for _, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") and child.LayoutOrder == NEXUS_ADMIN_ORDER then
			child:Destroy()
		end
	end

	local button = baseButton:Clone()
	button.Name = "AdminPanel"
	button.LayoutOrder = NEXUS_ADMIN_ORDER
	button.Visible = true
	local magenta = hexColor("#FF55FF")
	button.BackgroundColor3 = magenta
	local bg = button:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = magenta
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = magenta
		end
	end
	local icon = button:FindFirstChild("Icon")
	if icon then
		icon.ImageColor3 = magenta
	end
	button.Parent = frame

	table.insert(
		conns,
		button.MouseButton1Click:Connect(function()
			UIClick:Play()
			if config and config.callback then
				config.callback()
			end
		end)
	)
	table.insert(
		conns,
		button.MouseEnter:Connect(function()
			UIClick3:Play()
			TooltipModule.show(config.tooltipData, nil, button)
		end)
	)
	table.insert(
		conns,
		button.MouseLeave:Connect(function()
			TooltipModule.hide("generic")
		end)
	)
	return conns
end

-- ===================== INIT =====================
function M.init(sharedRefs)
	TooltipModule = sharedRefs.TooltipModule

	local CentralizedMenu = player.PlayerGui:WaitForChild("CentralizedAscensionMenu")
	local TemporaryMenus = CentralizedMenu:WaitForChild("TemporaryMenus")
	statSlotTemplate = TemporaryMenus:FindFirstChild("StatSlot")
	blankSlotTemplate = TemporaryMenus:FindFirstChild("BlankSlot")
	if not statSlotTemplate then
		warn("[AdminPageModule] StatSlot template NOT FOUND in TemporaryMenus")
	end
	if not blankSlotTemplate then
		warn("[AdminPageModule] BlankSlot template NOT FOUND in TemporaryMenus")
	end

	-- The admin grid has no Studio template, so build its base icons (Back / Close) from
	-- the Statistics page template. Everything else is created in code by populate.
	templateFolder = Instance.new("Folder")
	templateFolder.Name = "AdminMenu"
	local GridTemplates = ReplicatedStorage:WaitForChild("GridTemplates")
	local source = GridTemplates:FindFirstChild("StatisticsMenu2") or GridTemplates:FindFirstChild("ProfileMenu2")
	for _, name in ipairs({ "BackButton", "CloseSlot" }) do
		local original = source and source:FindFirstChild(name)
		if original then
			original:Clone().Parent = templateFolder
		else
			warn("[AdminPageModule] " .. name .. " not found in the grid templates")
		end
	end
end

return M
