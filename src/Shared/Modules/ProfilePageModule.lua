-- ============================================================
--  ProfilePageModule (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Grid-aware data & tooltip module for the Profile system.
--  GridMenuModule owns grid visibility — this module provides:
--    • Dynamic rich-text tooltips for skill attribute categories
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

-- ===================== TOOLTIP BUILDERS =====================

--- Build the compact rich-text attribute list for a skill category.
--- Returns a string suitable for TooltipModule's `stats` field.
---
--- Format per line (mirrors SkyBlock profile tooltip):
---   ‣ <colored attr name> <white value>
---
--- Example:
---   ‣ Mining Fortune 108
---   ‣ Mining Speed 140
---   ‣ Mining Crit Chance 21%
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

		-- Append % for crit chance attributes
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
--- Used by showSkillAttributeTooltip().
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

	-- No click action yet — sub-grids deferred
	local click = ""

	return {
		title = title,
		desc = desc,
		stats = stats,
		click = click,
	}
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
	-- The server fires this with the full stat snapshot.
	-- We cache it for tooltip value computation.
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

--- Show the dynamic tooltip for a skill attribute category button.
--- Called from CentralizedMenuController's profile tooltip wiring.
function M.showSkillAttributeTooltip(skillName)
	local tooltipData = buildSkillCategoryTooltipData(skillName)
	TooltipModule.show(tooltipData, TOOLTIP_SOURCE)
end

--- Hide the skill attribute tooltip (only if we own it).
function M.hideSkillAttributeTooltip()
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
