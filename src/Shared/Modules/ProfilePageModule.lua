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
--
--  The 6 skill attribute buttons on ProfileMenu1 use dynamic
--  tooltips wired in CentralizedMenuController (not GridMenuModule
--  tooltipData) because they require live stat values.
--
--  API:
--    init(sharedRefs)
--    showSkillAttributeTooltip(skillName)
--    hideSkillAttributeTooltip()
--    getAttributeValue(attrKey)
--    getAttributeData(attrKey)
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- ===================== MODULES =====================
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ProfileConfig = require(Modules:WaitForChild("ProfileConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

-- ===================== CONFIG REFERENCES =====================
local ATTRIBUTE_CATEGORIES = ProfileConfig.ATTRIBUTE_CATEGORIES
local SKILL_COLORS = ProfileConfig.SKILL_COLORS
local SKILL_DISPLAY_ORDER = ProfileConfig.SKILL_DISPLAY_ORDER
local TOOLTIP_COLORS = ProfileConfig.TOOLTIP_COLORS
local attrLookup = ProfileConfig.attrLookup

-- ===================== STATE =====================
local initialized = false
local shared = nil
local TooltipModule = nil

-- Cached attribute data from server.
-- Format: { [attrKey] = { flatBoosts = { {label, value, color?} }, multipliers = { {label, value, color?} } } }
-- Keys match ProfileConfig attribute keys (e.g. "FarmingFortune", "Walkspeed").
local cachedAttributeData = {}

-- ===================== TOOLTIP SOURCE =====================
-- Unique source identifier so profile tooltips don't clobber
-- other tooltip owners (skills, inventory, etc.)
local TOOLTIP_SOURCE = "profile"

-- ===================== REMOTES =====================
-- These are the same remotes the old ProfilePageModule used.
-- StatUpdated fires whenever the server recomputes player stats.
-- RequestStats asks the server to send the current snapshot.
local StatUpdated = ReplicatedStorage:FindFirstChild("StatUpdated")
local RequestStats = ReplicatedStorage:FindFirstChild("RequestStats")

-- ===================== HELPERS =====================

--- Format a number for display.  Integers use MoneyLib shorthand;
--- small decimals keep 2dp; large decimals floor then shorthand.
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
-- The server's StatUpdated payload may use different keys than
-- ProfileConfig attribute keys.  This map resolves mismatches.
-- If an attribute key is NOT in this map, the module tries using
-- the attribute key directly as the data key.
--
-- Add entries here when the server uses a different name than
-- the ProfileConfig key (e.g., server sends "Speed" but config
-- says "Walkspeed").
local ATTR_TO_DATA_KEY = {
	Walkspeed = "Speed",
	-- FarmingFortune = "FarmingFortune",  -- same, no mapping needed
	-- PressSpeed = "PressSpeed",          -- same
}

--- Resolve an attribute key to the data key used in cachedAttributeData.
local function resolveDataKey(attrKey)
	return ATTR_TO_DATA_KEY[attrKey] or attrKey
end

-- ===================== LEGACY TOOLTIP BUILDERS =====================
-- Kept for reference / non-icon tooltip contexts.  Profile skill
-- attribute tooltips now use icon stat lines via showSkillAttributeTooltip().

--- Build the compact rich-text attribute list for a skill category.
--- Returns a string suitable for TooltipModule's `stats` field.
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

--- Build tooltip data table for a skill attribute category button.
--- Legacy path — used only if icon tooltips are not desired.
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

	local click = ""

	return {
		title = title,
		desc = desc,
		stats = stats,
		click = click,
	}
end

-- ===================== SUMMARY TOOLTIP CONFIG =====================
-- Keys shown in the Nexus "Profile" button tooltip (top 5 overview).
-- Each entry references a skill + key from ATTRIBUTE_CATEGORIES.
local SUMMARY_STAT_KEYS = {
	{ skill = "General", key = "Health" },
	{ skill = "General", key = "Defense" },
	{ skill = "General", key = "PressSpeed" },
	{ skill = "General", key = "CritChance" },
	{ skill = "General", key = "CritIncrease" },
}

--- Check if a stat key should display a % suffix.
local function needsPercentSuffix(key)
	return string.find(key, "CritChance") ~= nil or string.find(key, "CritIncrease") ~= nil
end

--- Build icon stat lines from an array of attribute config entries.
--- Handles icon, color, name, value, suffix, and layout order.
--- Returns the number of lines created.
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

		-- Caller-side belt-and-suspenders
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

-- ===================== MODULE API =====================
local M = {}

--- Initialize the module.  Call once from CentralizedMenuController.
--- sharedRefs = the same table passed to all page modules.
function M.init(sharedRefs)
	if initialized then
		return
	end
	initialized = true

	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule

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

--- Show the dynamic icon tooltip for a skill attribute category button.
function M.showSkillAttributeTooltip(skillName)
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
	refs.Divider3.Visible = false
	refs.Stats.Visible = false
	refs.Rewards.Visible = false
	refs.ProgressOuter.Visible = false
	refs.ProgressLabel.Visible = false
	refs.Click.Visible = false

	local attrs = ATTRIBUTE_CATEGORIES[skillName]
	if attrs and #attrs > 0 then
		local count = buildIconLines(attrs, TooltipModule.ICON_STATS_BASE_LO)
		TooltipModule.adjustForIconCount(count)
	end

	TooltipModule.showRaw(TOOLTIP_SOURCE)
end

--- Hide the skill attribute tooltip (only if we own it).
function M.hideSkillAttributeTooltip()
	TooltipModule.hide(TOOLTIP_SOURCE)
end

--- Show a summary profile tooltip (top 5 stats) on the Nexus "Profile" button.
function M.showProfileSummaryTooltip()
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

	-- Resolve config entries from SUMMARY_STAT_KEYS
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

--- Hide the summary profile tooltip.
function M.hideProfileSummaryTooltip()
	TooltipModule.hide(TOOLTIP_SOURCE)
end

--- Show the full profile tooltip (ALL stats from all skills) on the "MyProfile" button.
--- Stats are grouped by skill in SKILL_DISPLAY_ORDER but not visually separated.
function M.showFullProfileTooltip()
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

	-- General attributes only
	local attrs = ATTRIBUTE_CATEGORIES["General"]
	if attrs and #attrs > 0 then
		local count = buildIconLines(attrs, TooltipModule.ICON_STATS_BASE_LO)
		TooltipModule.adjustForIconCount(count)
	end

	TooltipModule.showRaw(TOOLTIP_SOURCE)
end

--- Hide the full profile tooltip.
function M.hideFullProfileTooltip()
	TooltipModule.hide(TOOLTIP_SOURCE)
end

--- Get the computed final value of an attribute by its config key.
--- Returns 0 if no data is cached yet.
function M.getAttributeValue(attrKey)
	local dataKey = resolveDataKey(attrKey)
	return computeFinalValue(dataKey)
end

--- Get the raw cached data entry for an attribute.
--- Returns { flatBoosts = {}, multipliers = {} } or nil.
function M.getAttributeData(attrKey)
	local dataKey = resolveDataKey(attrKey)
	return cachedAttributeData[dataKey]
end

--- Get all computed attribute values for a skill category.
--- Returns { { key, name, color, value } ... }
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

--- Check if attribute data has been received from the server.
function M.hasData()
	return next(cachedAttributeData) ~= nil
end

return M
