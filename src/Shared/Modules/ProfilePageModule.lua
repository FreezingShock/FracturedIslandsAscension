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
--    openAttributeGrid(skillName)
--    closeAttributeGrid()
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

-- ===================== CONFIG REFERENCES =====================
local ATTRIBUTE_CATEGORIES = ProfileConfig.ATTRIBUTE_CATEGORIES
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
-- Format: { [attrKey] = { flatBoosts = { {label, value, color?} }, multipliers = { {label, value, color?} } } }
local cachedAttributeData = {}

-- Dynamic slot tracking for ProfileMenu2 (prevents connection stacking — PITFALL 3)
local dynamicSlots = {} -- array of cloned instances (StatSlots + fill blanks)
local dynamicConnections = {} -- array of RBXScriptConnections
local activeGridSkill = nil -- which skill is currently shown in ProfileMenu2

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

--- Compute the final value of an attribute from its cached data.
--- Final = sum(flatBoosts) × (1 + sum(multiplier - 1))
local function computeFinalValue(attrKey)
	local entry = cachedAttributeData[attrKey]
	if not entry then
		return 0
	end

	local flatTotal = 0
	if type(entry.flatBoosts) == "table" then
		for _, boost in ipairs(entry.flatBoosts) do
			local v = tonumber(boost.value)
			if v then
				flatTotal = flatTotal + v
			end
		end
	end

	local multBonus = 0
	if type(entry.multipliers) == "table" then
		for _, m in ipairs(entry.multipliers) do
			local v = tonumber(m.value)
			if v then
				multBonus = multBonus + (v - 1)
			end
		end
	end

	return flatTotal * (1 + multBonus)
end

--- Sanitize incoming stat data — ensure all values are numbers.
local function sanitizeStatData(data)
	if type(data) ~= "table" then
		return
	end
	for _, statTable in pairs(data) do
		if type(statTable) == "table" then
			if type(statTable.flatBoosts) == "table" then
				for _, b in ipairs(statTable.flatBoosts) do
					b.value = tonumber(b.value) or 0
				end
			end
			if type(statTable.multipliers) == "table" then
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

-- ===================== LEGACY TOOLTIP BUILDERS =====================

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

		local isCrit = string.find(attr.key, "CritChance") ~= nil
		if isCrit then
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

local function buildSkillCategoryTooltipData(skillName)
	local skillColor = SKILL_COLORS[skillName] or "#FFFFFF"

	local title = string.format(
		'<font color="%s"><b>%s</b></font> <font color="%s">Attributes</font>',
		skillColor,
		skillName,
		TOOLTIP_COLORS.label
	)

	local desc = string.format('<font color="%s">Your %s attribute bonuses.</font>', TOOLTIP_COLORS.label, skillName)
	local stats = buildAttributeListText(skillName)

	return {
		title = title,
		desc = desc,
		stats = stats,
		click = "",
	}
end

-- ===================== SUMMARY TOOLTIP CONFIG =====================
local SUMMARY_STAT_KEYS = {
	{ skill = "General", key = "Health" },
	{ skill = "General", key = "Defense" },
	{ skill = "General", key = "PressSpeed" },
	{ skill = "General", key = "CritChance" },
	{ skill = "General", key = "CritIncrease" },
}

--- Build icon stat lines from an array of attribute config entries.
local function buildIconLines(attrList, startLO)
	local count = 0
	for i, attr in ipairs(attrList) do
		local dataKey = resolveDataKey(attr.key)
		local finalVal = computeFinalValue(dataKey)
		local valStr = formatNumber(finalVal)

		if needsPercentSuffix(attr.key) then
			valStr = valStr .. "%"
		end

		local clone = TooltipModule.createIconStatLine({
			icon = attr.icon,
			color = attr.color or "#FFFFFF",
			name = attr.name or "???",
			value = valStr,
			layoutOrder = startLO + (i - 1),
		})

		-- Belt-and-suspenders
		local statLabel = clone:FindFirstChild("StatLabel", true)
		if statLabel then
			statLabel.RichText = true
			statLabel.TextColor3 = Color3.fromHex(attr.color or "#FFFFFF")
			statLabel.Text = string.format('%s <font color="#FFFFFF">%s</font>', attr.name or "???", valStr)
		end

		local img = clone:FindFirstChild("ImageLabel", true)
		if img then
			local iconData = attr.icon
			if type(iconData) == "table" then
				local sheet = TooltipModule.STAT_SPRITESHEET
				local col = iconData[1] or 0
				local row = iconData[2] or 0
				local cs = sheet.cellSize
				img.Image = sheet.assetId
				img.ImageRectSize = Vector2.new(cs, cs)
				img.ImageRectOffset = Vector2.new(col * cs, row * cs)
				img.ImageColor3 = Color3.fromHex(attr.color or "#FFFFFF")
				img.ImageTransparency = 0
			elseif type(iconData) == "string" and iconData ~= "" then
				img.Image = iconData
				img.ImageRectSize = Vector2.new(0, 0)
				img.ImageRectOffset = Vector2.new(0, 0)
				img.ImageColor3 = Color3.fromHex(attr.color or "#FFFFFF")
				img.ImageTransparency = 0
			else
				img.ImageTransparency = 1
			end
		end

		count = count + 1
	end
	return count
end

-- ===================== STAT BREAKDOWN TOOLTIP BUILDER =====================

local function buildStatBreakdownText(attrConfig)
	local dataKey = resolveDataKey(attrConfig.key)
	local entry = cachedAttributeData[dataKey]
	local lines = {}

	-- Formula placeholder
	table.insert(
		lines,
		string.format(
			'<font color="%s">Formula:</font> <font color="%s">Coming Soon</font>',
			TOOLTIP_COLORS.label,
			TOOLTIP_COLORS.comingSoon
		)
	)
	table.insert(lines, "")

	-- ── Flat Boosts ──
	local flatTotal = 0
	local flatBoosts = {}
	if entry and type(entry.flatBoosts) == "table" then
		for _, b in ipairs(entry.flatBoosts) do
			local v = tonumber(b.value) or 0
			flatTotal = flatTotal + v
			table.insert(flatBoosts, b)
		end
	end

	local flatStr = formatNumber(flatTotal)
	if needsPercentSuffix(attrConfig.key) then
		flatStr = flatStr .. "%"
	end

	table.insert(
		lines,
		string.format(
			'<font color="%s">Flat Amount:</font> <font color="%s">%s</font>',
			TOOLTIP_COLORS.accent,
			TOOLTIP_COLORS.value,
			flatStr
		)
	)

	if #flatBoosts == 0 then
		table.insert(lines, string.format('<font color="%s">‣ None</font>', TOOLTIP_COLORS.muted))
	else
		for i = 1, math.min(#flatBoosts, BREAKDOWN_MAX_FLAT) do
			local b = flatBoosts[i]
			local labelColor = b.color or "#FFFFFF"
			local valDisplay = formatNumber(math.abs(tonumber(b.value) or 0))
			local sign = (tonumber(b.value) or 0) >= 0 and "+" or "-"
			local valColor = (tonumber(b.value) or 0) >= 0 and TOOLTIP_COLORS.positive or TOOLTIP_COLORS.negative
			table.insert(
				lines,
				string.format(
					'<font color="%s">‣</font> <font color="%s">%s</font> <font color="%s">%s%s</font>',
					TOOLTIP_COLORS.muted,
					labelColor,
					b.label or "Unknown",
					valColor,
					sign,
					valDisplay
				)
			)
		end
		if #flatBoosts > BREAKDOWN_MAX_FLAT then
			local remaining = #flatBoosts - BREAKDOWN_MAX_FLAT
			table.insert(
				lines,
				string.format(
					'<font color="%s">(%d more flat boost%s...)</font>',
					TOOLTIP_COLORS.muted,
					remaining,
					remaining == 1 and "" or "s"
				)
			)
		end
	end

	table.insert(lines, "")

	-- ── Multipliers ──
	local multDisplay = 1
	local multipliers = {}
	if entry and type(entry.multipliers) == "table" then
		for _, m in ipairs(entry.multipliers) do
			local v = tonumber(m.value) or 1
			multDisplay = multDisplay + (v - 1)
			table.insert(multipliers, m)
		end
	end

	table.insert(
		lines,
		string.format(
			'<font color="#55FFFF">Multiplier Amount:</font> <font color="%s">%.2fx</font>',
			TOOLTIP_COLORS.value,
			multDisplay
		)
	)

	if #multipliers == 0 then
		table.insert(lines, string.format('<font color="%s">‣ None</font>', TOOLTIP_COLORS.muted))
	else
		for i = 1, math.min(#multipliers, BREAKDOWN_MAX_MULT) do
			local m = multipliers[i]
			local labelColor = m.color or "#FFFFFF"
			local valStr = string.format("%.2f", tonumber(m.value) or 1)
			table.insert(
				lines,
				string.format(
					'<font color="%s">‣</font> <font color="%s">%s</font> <font color="%s">×%s</font>',
					TOOLTIP_COLORS.muted,
					labelColor,
					m.label or "Unknown",
					TOOLTIP_COLORS.positive,
					valStr
				)
			)
		end
		if #multipliers > BREAKDOWN_MAX_MULT then
			local remaining = #multipliers - BREAKDOWN_MAX_MULT
			table.insert(
				lines,
				string.format(
					'<font color="%s">(%d more multiplier boost%s...)</font>',
					TOOLTIP_COLORS.muted,
					remaining,
					remaining == 1 and "" or "s"
				)
			)
		end
	end

	return table.concat(lines, "\n")
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
		end)
	else
		warn("[ProfilePageModule] StatUpdated RemoteEvent not found — attribute values will show 0")
	end

	-- ── Request initial data ──
	if RequestStats then
		task.delay(1, function()
			RequestStats:FireServer()
		end)
	end

	print("ProfilePageModule: Initialized ✓")
end

-- ===================== PROFILE GRID (Menu1) TOOLTIPS =====================

function M.showSkillAttributeTooltip(skillName)
	if not resolveTooltip() then
		return
	end
	TooltipModule.clearIconStats()
	TooltipModule.resetTailOrders()

	local refs = TooltipModule.refs
	local skillColor = SKILL_COLORS[skillName] or "#FFFFFF"

	refs.Title.Text = string.format(
		'<font color="%s"><b>%s</b></font> <font color="%s">Attributes</font>',
		skillColor,
		skillName,
		TOOLTIP_COLORS.label
	)
	refs.Desc.Text =
		string.format('<font color="%s">Your %s attribute bonuses.</font>', TOOLTIP_COLORS.label, skillName)
	refs.Desc.Visible = true
	refs.Divider1.Visible = true
	refs.Divider2.Visible = false
	refs.Divider3.Visible = true
	refs.Stats.Visible = false
	refs.Rewards.Visible = false
	refs.ProgressOuter.Visible = false
	refs.ProgressLabel.Visible = false
	refs.Click.Visible = true
	refs.Click.Text = '<font color="#FFFF55">Click to view!</font>'

	local attrs = ATTRIBUTE_CATEGORIES[skillName]
	if attrs and #attrs > 0 then
		local count = buildIconLines(attrs, TooltipModule.ICON_STATS_BASE_LO)
		TooltipModule.adjustForIconCount(count)
	end

	TooltipModule.showRaw(TOOLTIP_SOURCE)
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
	TooltipModule.clearIconStats()
	TooltipModule.resetTailOrders()

	local refs = TooltipModule.refs

	refs.Title.Text = '<font color="#55FF55"><b>Your Profile</b></font>'
	refs.Desc.Text =
		string.format('<font color="%s">View your equipment, stats, and more.</font>', TOOLTIP_COLORS.label)
	refs.Desc.Visible = true
	refs.Divider1.Visible = true
	refs.Divider2.Visible = false
	refs.Divider3.Visible = true
	refs.Stats.Visible = false
	refs.Rewards.Visible = false
	refs.ProgressOuter.Visible = false
	refs.ProgressLabel.Visible = false
	refs.Click.Text = '<font color="#FFFF55">Click to view!</font>'
	refs.Click.Visible = true

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

	if #attrList > 0 then
		local count = buildIconLines(attrList, TooltipModule.ICON_STATS_BASE_LO)
		TooltipModule.adjustForIconCount(count)
	end

	TooltipModule.showRaw(TOOLTIP_SOURCE)
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
	TooltipModule.clearIconStats()
	TooltipModule.resetTailOrders()

	local refs = TooltipModule.refs

	refs.Title.Text = '<font color="#55FF55"><b>Your Profile</b></font>'
	refs.Desc.Text =
		string.format('<font color="%s">View your equipment, attributes, and more.</font>', TOOLTIP_COLORS.label)
	refs.Desc.Visible = true
	refs.Divider1.Visible = true
	refs.Divider2.Visible = false
	refs.Divider3.Visible = false
	refs.Stats.Visible = false
	refs.Rewards.Visible = false
	refs.ProgressOuter.Visible = false
	refs.ProgressLabel.Visible = false
	refs.Click.Visible = false

	local attrs = ATTRIBUTE_CATEGORIES["General"]
	if attrs and #attrs > 0 then
		local count = buildIconLines(attrs, TooltipModule.ICON_STATS_BASE_LO)
		TooltipModule.adjustForIconCount(count)
	end

	TooltipModule.showRaw(TOOLTIP_SOURCE)
end

function M.hideFullProfileTooltip()
	if not resolveTooltip() then
		return
	end
	TooltipModule.hide(TOOLTIP_SOURCE)
end

-- ===================== STAT BREAKDOWN TOOLTIP (ProfileMenu2 slots) =====================

function M.showStatBreakdownTooltip(attrConfig)
	if not resolveTooltip() then
		return
	end
	TooltipModule.clearIconStats()
	TooltipModule.resetTailOrders()

	local refs = TooltipModule.refs
	local attrColor = attrConfig.color or "#FFFFFF"

	-- Compute value early (needed for both icon title and icon stat line)
	local dataKey = resolveDataKey(attrConfig.key)
	local finalVal = computeFinalValue(dataKey)
	local valStr = formatNumber(finalVal)
	if needsPercentSuffix(attrConfig.key) then
		valStr = valStr .. "%"
	end

	-- Icon title (replaces native TitleLabel with icon + name + value)
	TooltipModule.createIconTitle({
		icon = attrConfig.icon,
		color = attrColor,
		name = attrConfig.name or "???",
		value = valStr,
	})

	-- Description
	refs.Desc.Text = string.format('<font color="%s">%s</font>', TOOLTIP_COLORS.label, attrConfig.description or "")
	refs.Desc.Visible = true

	-- Divider1
	refs.Divider1.Visible = true

	-- Stats: full breakdown
	refs.Stats.Text = buildStatBreakdownText(attrConfig)
	refs.Stats.Visible = true

	-- Hidden elements
	refs.Rewards.Visible = false
	refs.ProgressOuter.Visible = false
	refs.ProgressLabel.Visible = false

	-- Divider3 + Cap (only if cap exists)
	local cap = STAT_CAPS[attrConfig.key]
	if cap then
		refs.Divider3.Visible = true
		refs.Click.Text = string.format(
			'<font color="%s">Cap:</font> <font color="%s">%s</font>',
			TOOLTIP_COLORS.label,
			TOOLTIP_COLORS.accent,
			formatNumber(cap)
		)
		refs.Click.Visible = true
	else
		refs.Divider3.Visible = false
		refs.Click.Visible = false
	end

	TooltipModule.showRaw(STAT_TOOLTIP_SOURCE)
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
			M.showStatBreakdownTooltip(capturedAttr)
		end)
		local leaveConn = slot.MouseLeave:Connect(function()
			M.hideStatBreakdownTooltip()
		end)
		table.insert(dynamicConnections, enterConn)
		table.insert(dynamicConnections, leaveConn)
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

-- ===================== QUERY API =====================

function M.getAttributeValue(attrKey)
	local dataKey = resolveDataKey(attrKey)
	return computeFinalValue(dataKey)
end

function M.getAttributeData(attrKey)
	local dataKey = resolveDataKey(attrKey)
	return cachedAttributeData[dataKey]
end

function M.getSkillAttributeValues(skillName)
	local attrs = ATTRIBUTE_CATEGORIES[skillName]
	if not attrs then
		return {}
	end

	local results = {}
	for _, attr in ipairs(attrs) do
		local dataKey = resolveDataKey(attr.key)
		table.insert(results, {
			key = attr.key,
			name = attr.name,
			color = attr.color,
			value = computeFinalValue(dataKey),
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
