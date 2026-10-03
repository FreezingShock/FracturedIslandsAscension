-- ============================================================
--  ProfilePageModule (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Grid-aware data & tooltip module for the Profile system.
--  GridMenuModule owns grid visibility — this module provides:
--    • Dynamic icon-based tooltips for skill attribute categories
--    • Armor slot tooltip builders (display-only for now)
--    • Cached attribute data from StatUpdated RemoteEvent
--    • Computed final attribute values (flat × multiplier)
--    • ProfileMenu2 dynamic stat slot population + tooltips
--
--  The 6 skill attribute buttons on ProfileMenu1 use dynamic
--  tooltips wired in CentralizedMenuController (not GridMenuModule
--  tooltipData) because they require live stat values.
--
--  API:
--    init(sharedRefs, profileMenu2Frame?)
--    showSkillAttributeTooltip(skillName)
--    hideSkillAttributeTooltip()
--    getAttributeValue(attrKey)
--    getAttributeData(attrKey)
--    openAttributeGrid(skillName)           (layer 2: a skill's attributes)
--    closeAttributeGrid()
--    openAttributeDetail(frame)             (layer 3: one attribute's sources)
--    setPendingSkill / setPendingAttribute  (what the next populate shows)
--    setAttributeClickHandler(fn)           (CMC navigates to layer 3)
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- ===================== AUDIO =====================
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")

-- ===================== MODULES =====================
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ProfileConfig = require(Modules:WaitForChild("ProfileConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any
local TooltipModuleDirect = require(Modules:WaitForChild("TooltipModule")) :: any
local Items = require(Modules:WaitForChild("Items")) :: any
local Attributes = require(Modules:WaitForChild("Attributes")) :: any
local Sources = require(Modules:WaitForChild("Sources")) :: any
local SlotFx = require(Modules:WaitForChild("SlotFx")) :: any
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")

-- ===================== CONFIG REFERENCES =====================
local ATTRIBUTE_CATEGORIES = ProfileConfig.ATTRIBUTE_CATEGORIES
local BASE_STATS = ProfileConfig.BASE_STATS
local SKILL_COLORS = ProfileConfig.SKILL_COLORS
local SKILL_DISPLAY_ORDER = ProfileConfig.SKILL_DISPLAY_ORDER
local TOOLTIP_COLORS = ProfileConfig.TOOLTIP_COLORS
local attrLookup = ProfileConfig.attrLookup

-- Menu2 config — nil-safe: these may not exist yet if ProfileConfig
-- additions weren't applied.  Guarded at usage site.
local STAT_CAPS = ProfileConfig.STAT_CAPS or {}
local BREAKDOWN_MAX_FLAT = ProfileConfig.BREAKDOWN_MAX_FLAT or 3
local BREAKDOWN_MAX_MULT = ProfileConfig.BREAKDOWN_MAX_MULT or 3
local CONTENT_SLOTS = ProfileConfig.PROFILE_MENU2_CONTENT_SLOTS or {}
local MENU2_TITLES = ProfileConfig.PROFILE_MENU2_TITLES or {}

-- ===================== STATE =====================
local initialized = false
local shared = nil
local TooltipModule = nil

-- ProfileMenu2 references (set during init)
local profileMenu2Frame = nil
local statSlotTemplate = nil
local blankSlotTemplate = nil

-- Cached attribute data from server.
-- Format: { [attrKey] = { base = number, final = number, flatBoosts = { {label, value, color?} }, multipliers = { {label, value, color?} } } }
-- AttributeStatManager pre-computes and sends this.
local cachedAttributeData = {}

-- Dynamic slot tracking for ProfileMenu2 (prevents connection stacking — PITFALL 3)
local dynamicSlots = {} -- array of cloned instances (StatSlots + fill blanks)
local dynamicConnections = {} -- array of RBXScriptConnections
local activeGridSkill = nil -- which skill is currently shown in ProfileMenu2

-- Layer 2 / 3 navigation state. CMC sets these before navigating; the pooled
-- grids' onPopulate hooks read them, so going Back re-populates correctly.
local pendingSkill = nil
local pendingAttr = nil -- attribute config table
local attributeClickHandler = nil -- fn(skillName, attrConfig)

-- Layer 3 (ProfileMenu3) dynamic content, tracked separately from layer 2
-- because both buffers can briefly exist during the crossfade.
local detailSlots = {}
local detailConnections = {}

-- ===================== TOOLTIP LAZY-RESOLVE =====================
-- TooltipModule is set via init(sharedRefs), but if init timing shifts
-- (e.g. after pooled grid refactor), this self-heals from the direct require.
local function resolveTooltip()
	if TooltipModule then
		return TooltipModule
	end
	if shared and shared.TooltipModule then
		TooltipModule = shared.TooltipModule
		return TooltipModule
	end
	-- Fallback: direct require (returns same cached instance)
	if TooltipModuleDirect then
		TooltipModule = TooltipModuleDirect
		warn("[ProfilePageModule] TooltipModule resolved via direct require — sharedRefs was nil. Check init order.")
		return TooltipModule
	end
	warn("[ProfilePageModule] TooltipModule is nil — cannot show tooltip")
	return nil
end

-- ===================== TOOLTIP SOURCES =====================
local TOOLTIP_SOURCE = "profile"
local STAT_TOOLTIP_SOURCE = "profile_stat"

-- ===================== REMOTES =====================
local StatUpdated = ReplicatedStorage:FindFirstChild("StatUpdated")
local RequestStats = ReplicatedStorage:FindFirstChild("RequestStats")

-- ===================== HELPERS =====================

--- Format a number for display.
local function formatNumber(n)
	if n == nil then
		return "0"
	end
	if n == math.floor(n) then
		return MoneyLib.DealWithPoints(n)
	end
	if math.abs(n) >= 1000 then
		return MoneyLib.DealWithPoints(math.floor(n))
	end
	return string.format("%.2f", n)
end

--- Get the final computed value of an attribute from cached data.
--- AttributeStatManager sends: { base, final, flatBoosts, multipliers }
--- We just return the pre-computed final value.
local function computeFinalValue(attrKey)
	local entry = cachedAttributeData[attrKey]
	if not entry then
		return 0
	end

	-- Server pre-computes: (base + flatBoosts) × (1 + multipliers)
	-- We just display it
	return tonumber(entry.final) or 0
end

--- Get the base value of an attribute.
local function getBaseValue(attrKey)
	local entry = cachedAttributeData[attrKey]
	if not entry then
		return BASE_STATS[attrKey] or 0
	end
	return tonumber(entry.base) or 0
end

--- Sanitize incoming stat data — ensure all values are numbers.
local function sanitizeStatData(data)
	if type(data) ~= "table" then
		return
	end
	for attrKey, statTable in pairs(data) do
		if type(statTable) == "table" then
			statTable.base = tonumber(statTable.base) or 0
			statTable.final = tonumber(statTable.final) or 0
			if type(statTable.flatBoosts) ~= "table" then
				statTable.flatBoosts = {}
			else
				for _, b in ipairs(statTable.flatBoosts) do
					b.value = tonumber(b.value) or 0
				end
			end
			if type(statTable.multipliers) ~= "table" then
				statTable.multipliers = {}
			else
				for _, m in ipairs(statTable.multipliers) do
					m.value = tonumber(m.value) or 1
				end
			end
		end
	end
end

-- ===================== ATTRIBUTE KEY → DATA KEY MAP =====================
local ATTR_TO_DATA_KEY = {
	Walkspeed = "Speed",
}

local function resolveDataKey(attrKey)
	return ATTR_TO_DATA_KEY[attrKey] or attrKey
end

-- ===================== PERCENT SUFFIX CHECK =====================
local function needsPercentSuffix(key)
	return string.find(key, "CritChance") ~= nil or string.find(key, "CritIncrease") ~= nil
end

-- ===================== ATTRIBUTE LIST BUILDER =====================

local function buildAttributeListText(skillName)
	local attrs = ATTRIBUTE_CATEGORIES[skillName]
	if not attrs or #attrs == 0 then
		return '<font color="' .. TOOLTIP_COLORS.muted .. '">No attributes defined.</font>'
	end

	local lines = {}
	for _, attr in ipairs(attrs) do
		local dataKey = resolveDataKey(attr.key)
		local finalVal = computeFinalValue(dataKey)
		local valStr = formatNumber(finalVal)

		if needsPercentSuffix(attr.key) then
			valStr = valStr .. "%"
		end

		table.insert(
			lines,
			string.format(
				'<font color="%s">‣</font> <font color="%s"><b>%s</b></font> <font color="%s">%s</font>',
				TOOLTIP_COLORS.muted,
				attr.color,
				attr.name,
				TOOLTIP_COLORS.value,
				valStr
			)
		)
	end

	return table.concat(lines, "\n")
end

-- ===================== SUMMARY TOOLTIP CONFIG =====================
local SUMMARY_STAT_KEYS = {
	{ skill = "General", key = "Health" },
	{ skill = "General", key = "Defense" },
	{ skill = "General", key = "PressSpeed" },
	{ skill = "General", key = "CritChance" },
	{ skill = "General", key = "CritIncrease" },
}

--- Build tooltip stat rows from an array of attribute config entries.
local function buildStatRows(attrList)
	local rows = {}
	for _, attr in ipairs(attrList) do
		local dataKey = resolveDataKey(attr.key)
		local valStr = formatNumber(computeFinalValue(dataKey))
		if needsPercentSuffix(attr.key) then
			valStr = valStr .. "%"
		end
		table.insert(rows, {
			name = attr.name or "???",
			value = valStr,
			color = attr.color or "#FFFFFF",
			icon = attr.icon,
		})
	end
	return rows
end

-- ===================== DYNAMIC SLOT CLEANUP =====================

local function cleanupDynamicSlots()
	-- Disconnect hover connections first (PITFALL 3)
	for _, conn in ipairs(dynamicConnections) do
		conn:Disconnect()
	end
	table.clear(dynamicConnections)

	-- Destroy cloned instances
	for _, inst in ipairs(dynamicSlots) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(dynamicSlots)

	activeGridSkill = nil
end

-- ===================== STAT SLOT ICON SETUP =====================

-- Darken factor: 0 = black, 1 = original color. Adjust to taste.
local SLOT_BG_DARKEN = 0.6
local SLOT_STROKE_DARKEN = 0.6

local function darkenColor(color3, factor)
	return Color3.new(color3.R * factor, color3.G * factor, color3.B * factor)
end

local function setupStatSlotIcon(slot, attrConfig)
	local hexColor = attrConfig.color or "#FFFFFF"
	local color3 = Color3.fromHex(hexColor)

	-- ── Tint the slot frame itself ──
	slot.BackgroundColor3 = darkenColor(color3, SLOT_BG_DARKEN)

	-- ── Tint BG ImageLabel + its UIStroke ──
	local bg = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = darkenColor(color3, SLOT_BG_DARKEN)
		local bgStroke = bg:FindFirstChildOfClass("UIStroke")
		if bgStroke then
			bgStroke.Color = darkenColor(color3, SLOT_STROKE_DARKEN)
		end
	end

	-- ── Configure icon ──
	local icon = slot:FindFirstChild("Icon")
	if not icon then
		return
	end

	local iconData = attrConfig.icon
	if type(iconData) == "table" then
		local sheet = TooltipModule.STAT_SPRITESHEET
		local col = iconData[1] or 0
		local row = iconData[2] or 0
		local cs = sheet.cellSize
		icon.Image = sheet.assetId
		icon.ImageRectSize = Vector2.new(cs, cs)
		icon.ImageRectOffset = Vector2.new(col * cs, row * cs)
		icon.ImageColor3 = Color3.fromHex(attrConfig.color or "#FFFFFF")
		icon.ImageTransparency = 0
	elseif type(iconData) == "string" and iconData ~= "" then
		icon.Image = iconData
		icon.ImageRectSize = Vector2.new(0, 0)
		icon.ImageRectOffset = Vector2.new(0, 0)
		icon.ImageColor3 = Color3.fromHex(attrConfig.color or "#FFFFFF")
		icon.ImageTransparency = 0
	else
		icon.ImageTransparency = 1
	end
end

-- ===================== MODULE API =====================
local M = {}

--- Initialize the module.  Call once from CentralizedMenuController.
--- sharedRefs   = the same table passed to all page modules.
--- menu2Frame   = the ProfileMenu2 Frame instance (optional — resolves from menuFrame if nil).
function M.init(sharedRefs, menu2Frame)
	if initialized then
		return
	end
	initialized = true

	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule

	if TooltipModule then
		print("[ProfilePageModule] TooltipModule from sharedRefs: ✓")
	else
		warn("[ProfilePageModule] sharedRefs.TooltipModule is NIL — will use direct require fallback")
		TooltipModule = TooltipModuleDirect
	end

	-- ── ProfileMenu2 frame ──
	-- ProfileMenu2 is a pooled grid — no permanent frame in menuFrame.
	-- The buffer frame is set dynamically via setMenu2Frame() from
	-- the onPopulate hook each time the grid is populated.
	if menu2Frame then
		profileMenu2Frame = menu2Frame
	end
	print("[ProfilePageModule] profileMenu2Frame will be set via setMenu2Frame() on navigate")

	-- ── Resolve templates from PlayerGui (same pattern as StatisticsPageModule) ──
	local CentralizedMenu = player.PlayerGui:WaitForChild("CentralizedAscensionMenu")
	local TemporaryMenus = CentralizedMenu:WaitForChild("TemporaryMenus")

	statSlotTemplate = TemporaryMenus:FindFirstChild("StatSlot") or TemporaryMenus:WaitForChild("StatSlot", 5)
	if not statSlotTemplate then
		warn("[ProfilePageModule] StatSlot template NOT FOUND in TemporaryMenus")
	else
		print("[ProfilePageModule] StatSlot template: ✓")
	end

	blankSlotTemplate = TemporaryMenus:FindFirstChild("BlankSlot") or TemporaryMenus:WaitForChild("BlankSlot", 5)
	if not blankSlotTemplate then
		warn("[ProfilePageModule] BlankSlot template NOT FOUND in TemporaryMenus")
	else
		print("[ProfilePageModule] BlankSlot template: ✓")
	end

	-- ── Validate config ──
	if #CONTENT_SLOTS == 0 then
		warn("[ProfilePageModule] CONTENT_SLOTS is empty — did you add PROFILE_MENU2_CONTENT_SLOTS to ProfileConfig?")
	else
		print("[ProfilePageModule] CONTENT_SLOTS: ✓ (" .. #CONTENT_SLOTS .. " positions)")
	end

	-- ── Listen for StatUpdated ──
	if StatUpdated then
		StatUpdated.OnClientEvent:Connect(function(data)
			sanitizeStatData(data)
			cachedAttributeData = data
			print("[ProfilePageModule] StatUpdated received, cached " .. tostring(#data) .. " attributes")
		end)
	else
		warn("[ProfilePageModule] StatUpdated RemoteEvent not found — attribute values will show 0")
	end

	-- ── Request initial data ──
	if RequestStats then
		task.delay(1, function()
			local data = RequestStats:InvokeServer()
			if data then
				sanitizeStatData(data)
				cachedAttributeData = data
				print("[ProfilePageModule] RequestStats returned, cached " .. tostring(#data) .. " attributes")
			end
		end)
	end

	print("ProfilePageModule: Initialized ✓")
end

-- ===================== PROFILE GRID (Menu1) TOOLTIPS =====================

function M.showSkillAttributeTooltip(skillName)
	if not resolveTooltip() then
		return
	end
	local skillColor = SKILL_COLORS[skillName] or "#FFFFFF"
	local attrs = ATTRIBUTE_CATEGORIES[skillName]

	TooltipModule.show({
		title = string.format(
			'<font color="%s"><b>%s</b></font> <font color="%s">Attributes</font>',
			skillColor,
			skillName,
			TOOLTIP_COLORS.label
		),
		description = string.format("Your %s attribute bonuses.", skillName),
		statsTitle = false,
		stats = (attrs and #attrs > 0) and buildStatRows(attrs) or nil,
		click = { text = "CLICK TO VIEW!", color = "#FFFF55" },
	}, TOOLTIP_SOURCE)
end

function M.hideSkillAttributeTooltip()
	if not resolveTooltip() then
		return
	end
	TooltipModule.hide(TOOLTIP_SOURCE)
end

-- ===================== PROFILE SUMMARY TOOLTIP (Nexus) =====================

function M.showProfileSummaryTooltip()
	if not resolveTooltip() then
		return
	end

	local attrList = {}
	for _, ref in ipairs(SUMMARY_STAT_KEYS) do
		local skillAttrs = ATTRIBUTE_CATEGORIES[ref.skill]
		if skillAttrs then
			for _, attr in ipairs(skillAttrs) do
				if attr.key == ref.key then
					table.insert(attrList, attr)
					break
				end
			end
		end
	end

	TooltipModule.show({
		title = '<font color="#55FF55"><b>Your Profile</b></font>',
		description = "View your equipment, stats, and more.",
		statsTitle = false,
		stats = #attrList > 0 and buildStatRows(attrList) or nil,
		click = { text = "CLICK TO VIEW!", color = "#FFFF55" },
	}, TOOLTIP_SOURCE)
end

function M.hideProfileSummaryTooltip()
	if not resolveTooltip() then
		return
	end
	TooltipModule.hide(TOOLTIP_SOURCE)
end

-- ===================== FULL PROFILE TOOLTIP (MyProfile) =====================

function M.showFullProfileTooltip()
	if not resolveTooltip() then
		return
	end
	local attrs = ATTRIBUTE_CATEGORIES["General"]

	TooltipModule.show({
		title = '<font color="#55FF55"><b>Your Profile</b></font>',
		description = "View your equipment, attributes, and more.",
		statsTitle = false,
		stats = (attrs and #attrs > 0) and buildStatRows(attrs) or nil,
	}, TOOLTIP_SOURCE)
end

function M.hideFullProfileTooltip()
	if not resolveTooltip() then
		return
	end
	TooltipModule.hide(TOOLTIP_SOURCE)
end

-- ===================== STAT BREAKDOWN TOOLTIP (ProfileMenu2 slots) =====================

function M.showStatBreakdownTooltip(attrConfig, anchor, clickable)
	if not resolveTooltip() then
		return
	end
	local dataKey = resolveDataKey(attrConfig.key)
	local config = Attributes.tooltipConfig(dataKey, cachedAttributeData[dataKey], { clickable = clickable })
	TooltipModule.show(config, STAT_TOOLTIP_SOURCE, anchor)
end

function M.hideStatBreakdownTooltip()
	if not resolveTooltip() then
		return
	end
	TooltipModule.hide(STAT_TOOLTIP_SOURCE)
end

-- ===================== PROFILE MENU 2 — DYNAMIC POPULATION =====================

--- Set the ProfileMenu2 parent frame dynamically.
--- Called by the pooled grid's onPopulate hook with the active buffer.
--- Must be called BEFORE openAttributeGrid().
function M.setMenu2Frame(frame)
	profileMenu2Frame = frame
end

--- Populate ProfileMenu2 with stat slots for the given skill.
--- Call BEFORE GridMenuModule.navigateToGrid("ProfileMenu2").
function M.openAttributeGrid(skillName, activeFrame)
	-- Pooled grid: use the buffer frame as the parent for dynamic clones.
	if activeFrame then
		profileMenu2Frame = activeFrame
	end
	-- Clean up any previous population
	cleanupDynamicSlots()

	if not profileMenu2Frame then
		warn("[ProfilePageModule] openAttributeGrid: profileMenu2Frame is nil — aborting")
		return
	end
	if not statSlotTemplate then
		warn("[ProfilePageModule] openAttributeGrid: statSlotTemplate is nil — aborting")
		return
	end
	if #CONTENT_SLOTS == 0 then
		warn("[ProfilePageModule] openAttributeGrid: CONTENT_SLOTS is empty — aborting")
		return
	end

	activeGridSkill = skillName
	local skillColor = SKILL_COLORS[skillName] or "#FFFFFF"
	local attrs = ATTRIBUTE_CATEGORIES[skillName]
	if not attrs then
		warn("[ProfilePageModule] openAttributeGrid: no ATTRIBUTE_CATEGORIES for '" .. tostring(skillName) .. "'")
		return
	end

	print("[ProfilePageModule] openAttributeGrid: " .. skillName .. " (" .. #attrs .. " attrs)")

	-- ── Update Category button ──
	local categoryBtn = profileMenu2Frame:FindFirstChild("Category")
	if categoryBtn then
		-- Try TextLabel child first, then button's own Text property
		local textLabel = categoryBtn:FindFirstChild("TextLabel")
			or categoryBtn:FindFirstChild("NameLabel")
			or categoryBtn:FindFirstChild("Label")
		if textLabel and textLabel:IsA("TextLabel") then
			textLabel.RichText = true
			textLabel.Text = string.format(
				'<font color="%s"><b>%s</b></font> <font color="#AAAAAA">Attributes</font>',
				skillColor,
				skillName
			)
		elseif categoryBtn:IsA("TextButton") then
			categoryBtn.RichText = true
			categoryBtn.Text = string.format(
				'<font color="%s"><b>%s</b></font> <font color="#AAAAAA">Attributes</font>',
				skillColor,
				skillName
			)
		end
	end

	-- ── Clone StatSlots for each attribute ──
	local numAttrs = math.min(#attrs, #CONTENT_SLOTS)
	for i = 1, numAttrs do
		local attr = attrs[i]
		local slot = statSlotTemplate:Clone()
		slot.Name = "DynStatSlot"
		slot.LayoutOrder = CONTENT_SLOTS[i]
		slot.Visible = true

		-- Configure icon from spritesheet
		setupStatSlotIcon(slot, attr)

		slot.Parent = profileMenu2Frame
		table.insert(dynamicSlots, slot)

		-- Wire hover tooltip (connections tracked for cleanup — PITFALL 3)
		local capturedAttr = attr
		local enterConn = slot.MouseEnter:Connect(function()
			UIClick3:Play()
			M.showStatBreakdownTooltip(capturedAttr, slot, true)
		end)
		local leaveConn = slot.MouseLeave:Connect(function()
			M.hideStatBreakdownTooltip()
		end)
		table.insert(dynamicConnections, enterConn)
		table.insert(dynamicConnections, leaveConn)
		table.insert(dynamicConnections, SlotFx.bind(slot))
		table.insert(
			dynamicConnections,
			slot.MouseButton1Click:Connect(function()
				UIClick:Play()
				if attributeClickHandler then
					attributeClickHandler(skillName, capturedAttr)
				end
			end)
		)
	end

	print("[ProfilePageModule] Cloned " .. numAttrs .. " StatSlots")

	-- ── Fill remaining content positions with BlankSlots ──
	if blankSlotTemplate then
		local blanksCloned = 0
		for i = numAttrs + 1, #CONTENT_SLOTS do
			local blank = blankSlotTemplate:Clone()
			blank.Name = "DynBlank"
			blank.LayoutOrder = CONTENT_SLOTS[i]
			blank.Visible = true
			blank.Parent = profileMenu2Frame
			table.insert(dynamicSlots, blank)
			blanksCloned = blanksCloned + 1
		end
		print("[ProfilePageModule] Cloned " .. blanksCloned .. " fill blanks")
	end
end

--- Clean up ProfileMenu2 dynamic content.
--- Call BEFORE GridMenuModule.navigateBack() from ProfileMenu2.
function M.closeAttributeGrid()
	if resolveTooltip() then
		TooltipModule.forceHide()
	end
	cleanupDynamicSlots()
	print("[ProfilePageModule] closeAttributeGrid: cleaned up")
end

-- ===================== PROFILE MENU 3 — ATTRIBUTE SOURCES =====================

local function cleanupDetail()
	for _, conn in ipairs(detailConnections) do
		conn:Disconnect()
	end
	table.clear(detailConnections)
	for _, inst in ipairs(detailSlots) do
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(detailSlots)
end

local FONT_PIXEL = "rbxassetid://12187371840"

local function buildSourceSlot(source, attrConfig, dataKey, breakdown, layoutOrder, frame)
	local hex = Sources.hex(source)

	local slot = statSlotTemplate:Clone()
	slot.Name = "Source_" .. tostring(source.id or source.type)
	slot.LayoutOrder = layoutOrder
	slot.Visible = true
	setupStatSlotIcon(slot, { color = hex }) -- tint only (no icon)

	-- Initials in the source's color; amount along the bottom.
	local letters = Instance.new("TextLabel")
	letters.Name = "Letters"
	letters.BackgroundTransparency = 1
	letters.AnchorPoint = Vector2.new(0.5, 0)
	letters.Position = UDim2.new(0.5, 0, 0, 5)
	letters.Size = UDim2.new(1, 0, 0, 18)
	letters.FontFace = Font.new(FONT_PIXEL)
	letters.TextSize = 16
	letters.TextColor3 = Color3.fromHex(hex)
	letters.TextStrokeTransparency = 0.4
	letters.Text = Sources.initials(source)
	letters.ZIndex = 10
	letters.Parent = slot

	local amount = Attributes.amountText(dataKey, source)
	local value = Instance.new("TextLabel")
	value.Name = "Amount"
	value.BackgroundTransparency = 1
	value.AnchorPoint = Vector2.new(0.5, 1)
	value.Position = UDim2.new(0.5, 0, 1, -3)
	value.Size = UDim2.new(1, -2, 0, 12)
	value.FontFace = Font.new(FONT_PIXEL)
	value.TextSize = 11
	value.TextColor3 = Color3.fromHex(attrConfig.color or "#FFFFFF")
	value.TextStrokeTransparency = 0.3
	value.Text = amount
	value.ZIndex = 10
	value.Parent = slot

	slot.Parent = frame
	table.insert(detailSlots, slot)
	table.insert(detailConnections, SlotFx.bind(slot))

	local attrDef = Attributes.get(dataKey)
	table.insert(
		detailConnections,
		slot.MouseEnter:Connect(function()
			UIClick3:Play()
			TooltipModule.show(
				Sources.tooltip(source, attrDef, {
					TooltipModule = TooltipModule,
					amount = amount,
					breakdown = breakdown,
					totalText = Attributes.format(dataKey, breakdown.final),
				}),
				STAT_TOOLTIP_SOURCE,
				slot
			)
		end)
	)
	table.insert(
		detailConnections,
		slot.MouseLeave:Connect(function()
			M.hideStatBreakdownTooltip()
		end)
	)
	return slot
end

--- Remember what ProfileMenu2 / ProfileMenu3 should show on their next populate.
function M.setPendingSkill(skillName)
	pendingSkill = skillName
end

function M.setPendingAttribute(skillName, attrConfig)
	pendingSkill = skillName
	pendingAttr = attrConfig
end

function M.getPendingSkill()
	return pendingSkill
end

function M.getPendingAttribute()
	return pendingAttr
end

--- CMC registers how to navigate to layer 3 when an attribute slot is clicked.
function M.setAttributeClickHandler(fn)
	attributeClickHandler = fn
end

--- onPopulate hook for ProfileMenu2 (also runs when navigating Back to it).
function M.populateAttributeGrid(frame)
	if pendingSkill then
		M.openAttributeGrid(pendingSkill, frame)
	end
end

--- Populate ProfileMenu3 with the pending attribute and its sources.
--- Called from the grid's onPopulate hook with the active buffer frame.
function M.openAttributeDetail(frame)
	cleanupDetail()
	local attrConfig = pendingAttr
	if not frame or not attrConfig or not statSlotTemplate or not blankSlotTemplate then
		warn("[ProfilePageModule] openAttributeDetail: missing frame / attribute / templates")
		return
	end

	-- ── Row 0: the attribute itself (row 1, slot 5) ──
	local header = statSlotTemplate:Clone()
	header.Name = "AttributeHeader"
	header.LayoutOrder = ProfileConfig.PROFILE_MENU3_ATTRIBUTE_ORDER
	header.Visible = true
	setupStatSlotIcon(header, attrConfig)
	header.Parent = frame
	table.insert(detailSlots, header)
	table.insert(detailConnections, SlotFx.bind(header))
	SlotFx.setSelected(header, true) -- the attribute being inspected
	table.insert(
		detailConnections,
		header.MouseEnter:Connect(function()
			UIClick3:Play()
			M.showStatBreakdownTooltip(attrConfig, header, false)
		end)
	)
	table.insert(
		detailConnections,
		header.MouseLeave:Connect(function()
			M.hideStatBreakdownTooltip()
		end)
	)

	-- ── Rows 1-4: one slot per source, then blanks ──
	local dataKey = resolveDataKey(attrConfig.key)
	local breakdown = Attributes.breakdown(dataKey, cachedAttributeData[dataKey])
	local sources = breakdown.sources
	for i, layoutOrder in ipairs(ProfileConfig.PROFILE_MENU3_CONTENT_SLOTS) do
		local source = sources[i]
		if source then
			buildSourceSlot(source, attrConfig, dataKey, breakdown, layoutOrder, frame)
		else
			local blank = blankSlotTemplate:Clone()
			blank.Name = "DynBlank"
			blank.LayoutOrder = layoutOrder
			blank.Visible = true
			blank.Parent = frame
			table.insert(detailSlots, blank)
		end
	end
end

function M.closeAttributeDetail()
	if resolveTooltip() then
		TooltipModule.forceHide()
	end
	cleanupDetail()
end

-- ===================== QUERY API =====================

function M.getAttributeValue(attrKey)
	return computeFinalValue(attrKey)
end

function M.getAttributeData(attrKey)
	return cachedAttributeData[attrKey]
end

function M.getSkillAttributeValues(skillName)
	local attrs = ATTRIBUTE_CATEGORIES[skillName]
	if not attrs then
		return {}
	end

	local results = {}
	for _, attr in ipairs(attrs) do
		table.insert(results, {
			key = attr.key,
			name = attr.name,
			color = attr.color,
			value = computeFinalValue(attr.key),
		})
	end
	return results
end

function M.hasData()
	return next(cachedAttributeData) ~= nil
end

function M.getActiveGridSkill()
	return activeGridSkill
end

return M
