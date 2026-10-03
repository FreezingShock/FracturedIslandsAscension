--[[
	Attributes (ModuleScript)

	One clean definition per attribute, built from ProfileConfig so adding an
	attribute stays a ONE-ENTRY job:

	  1. Add { key, name, color, icon, description } to ProfileConfig.ATTRIBUTE_CATEGORIES
	  2. Add its starting value to ProfileConfig.BASE_STATS
	  (the server profile template and the Profile pages pick it up automatically)

	Optional tuning in Attributes.Overrides[key]:
	  format    "number" | "percent"       (percent adds a % suffix)
	  decimals  max decimals for small numbers
	  cap       hard cap shown in the tooltip (also read from ProfileConfig.STAT_CAPS)
	  sections  ordered tooltip section names, default { "summary", "sources" }

	A definition:  { key, name, description, color, icon, skill, base, format,
	                 decimals, cap, sections }

	  Attributes.get(key) / Attributes.find(name)   (find is case/space-insensitive)
	  Attributes.format(key, value)                 "1.2K", "10%" ...
	  Attributes.breakdown(key, data)               { base, flat, mult, final, sources }
	  Attributes.amountText(key, source)            "+30", "x1.05", "+30 x1.05"
	  Attributes.tooltipConfig(key, data, opts)     full tooltip config
	  Attributes.registerSection(name, fn)          custom tooltip section builder
--]]

local ProfileConfig = require(script.Parent:WaitForChild("ProfileConfig")) :: any
local MoneyLib = require(script.Parent:WaitForChild("MoneyLib")) :: any
local Sources = require(script.Parent:WaitForChild("Sources")) :: any

local Attributes = {}

Attributes.Overrides = {
	-- Examples of tuning (everything else uses the defaults):
	Speed = { decimals = 1 },
}

local DEFAULT_SECTIONS = { "summary", "sources" }

-- ===================== DEFINITIONS =====================
local defs: { [string]: any } = {}
local byLowerName: { [string]: string } = {}

local function isPercentKey(key: string): boolean
	return key:find("CritChance", 1, true) ~= nil or key:find("CritIncrease", 1, true) ~= nil
end

for _, skill in ipairs(ProfileConfig.SKILL_DISPLAY_ORDER) do
	for _, attr in ipairs(ProfileConfig.ATTRIBUTE_CATEGORIES[skill] or {}) do
		if not defs[attr.key] then
			local over = Attributes.Overrides[attr.key] or {}
			defs[attr.key] = {
				key = attr.key,
				name = attr.name or attr.key,
				description = attr.description or "",
				color = attr.color or "#FFFFFF",
				icon = attr.icon,
				skill = skill,
				base = ProfileConfig.BASE_STATS[attr.key] or 0,
				format = over.format or (isPercentKey(attr.key) and "percent" or "number"),
				decimals = over.decimals or 2,
				cap = over.cap or (ProfileConfig.STAT_CAPS or {})[attr.key],
				sections = over.sections or DEFAULT_SECTIONS,
			}
			byLowerName[attr.key:lower()] = attr.key
			byLowerName[(attr.name or attr.key):lower():gsub("%s+", "")] = attr.key
		end
	end
end

function Attributes.get(key: string)
	return defs[key]
end

function Attributes.find(name: string)
	local direct = defs[name] and name or byLowerName[name:lower():gsub("%s+", "")]
	return direct and defs[direct] or nil
end

function Attributes.all(): { [string]: any }
	return defs
end

-- ===================== FORMATTING =====================
local function formatNumber(n: number, decimals: number): string
	if n == math.floor(n) then
		return MoneyLib.DealWithPoints(n)
	end
	if math.abs(n) >= 1000 then
		return MoneyLib.DealWithPoints(math.floor(n))
	end
	return string.format("%." .. decimals .. "f", n)
end

function Attributes.format(key: string, value: number): string
	local def = defs[key]
	local text = formatNumber(value or 0, def and def.decimals or 2)
	if def and def.format == "percent" then
		text ..= "%"
	end
	return text
end

--- "+30", "x1.05" or "+30 x1.05" for one source of an attribute.
function Attributes.amountText(key: string, source: any): string
	local parts = {}
	if source.flat and source.flat ~= 0 then
		local sign = source.flat > 0 and "+" or "-"
		table.insert(parts, sign .. Attributes.format(key, math.abs(source.flat)))
	end
	if source.mult then
		table.insert(parts, string.format("×%.2f", source.mult))
	end
	return table.concat(parts, " ")
end

-- ===================== BREAKDOWN =====================
--- data = { base, final, flatBoosts, multipliers } as sent by AttributeStatManager.
function Attributes.breakdown(key: string, data: any)
	local def = defs[key]
	local flat, mult = 0, 1
	for _, b in ipairs(data and data.flatBoosts or {}) do
		flat += tonumber(b.value) or 0
	end
	for _, m in ipairs(data and data.multipliers or {}) do
		mult += (tonumber(m.value) or 1) - 1
	end
	local base = data and tonumber(data.base) or (def and def.base) or 0
	return {
		base = base,
		flat = flat,
		mult = mult,
		final = data and tonumber(data.final) or base,
		sources = Sources.build(key, data, base),
	}
end

-- ===================== TOOLTIP SECTIONS =====================
local SectionBuilders: { [string]: (def: any, bd: any) -> any? } = {}

function Attributes.registerSection(name: string, builder: (def: any, bd: any) -> any?)
	SectionBuilders[name] = builder
end

Attributes.registerSection("summary", function(def, bd)
	local multBonus = (bd.mult - 1) * 100
	local rows = {
		{ label = "Base", value = Attributes.format(def.key, bd.base), labelColor = "#AAAAAA" },
		{
			label = "Flat Bonuses",
			value = (bd.flat >= 0 and "+" or "") .. Attributes.format(def.key, bd.flat),
			color = bd.flat > 0 and "#55FF55" or (bd.flat < 0 and "#FF5555" or "#FFFFFF"),
			labelColor = "#FFFF55",
		},
		{
			label = "Multiplier",
			value = string.format("%.2fx", bd.mult),
			detail = multBonus ~= 0 and string.format("(%s%d%%)", multBonus > 0 and "+" or "", math.floor(multBonus + 0.5)) or nil,
			color = bd.mult > 1 and "#55FF55" or "#FFFFFF",
			labelColor = "#55FFFF",
		},
		{ label = "Total", value = Attributes.format(def.key, bd.final), color = "#FFFFFF", labelColor = "#FFAA00" },
	}
	return { type = "list", title = "Summary", color = def.color, rows = rows }
end)

Attributes.registerSection("sources", function(def, bd)
	local rows = {}
	local top, topAmount = nil, 0
	for _, source in ipairs(bd.sources) do
		local detail = Sources.detail(source)
		table.insert(rows, {
			label = Sources.name(source),
			labelColor = Sources.hex(source),
			value = Attributes.amountText(def.key, source),
			color = def.color,
			detail = detail and ("(" .. detail .. ")") or nil,
		})
		local magnitude = math.abs(source.flat or 0)
		if source.type ~= "base" and magnitude > topAmount then
			top, topAmount = source, magnitude
		end
	end
	if #rows == 0 then
		return nil
	end

	-- Collapsed view: how many sources, what they add up to, and the biggest one.
	local count = #rows
	local summary = string.format("&f%d &7source%s &7· &a%s&7 flat", count, count == 1 and "" or "s", (bd.flat >= 0 and "+" or "") .. Attributes.format(def.key, bd.flat))
	if top then
		summary ..= string.format("\n&7Top: &f%s &a%s", Sources.name(top), Attributes.amountText(def.key, top))
	end
	return {
		type = "list",
		title = "Sources",
		color = def.color,
		rows = rows,
		collapsible = true,
		summary = summary,
	}
end)

--- Full tooltip config for an attribute.
---   opts.clickable  add the "CLICK TO VIEW SOURCES!" pill
---   opts.sections   override the section list for this call
function Attributes.tooltipConfig(key: string, data: any, opts: any?): any
	opts = opts or {}
	local def = defs[key]
	if not def then
		return { title = key }
	end
	local bd = Attributes.breakdown(key, data)

	local icon
	if type(def.icon) == "table" then
		icon = { def.icon[1], def.icon[2], color = def.color }
	elseif type(def.icon) == "string" and def.icon ~= "" then
		icon = { image = def.icon, color = def.color }
	end

	local sections = {}
	for _, name in ipairs(opts.sections or def.sections) do
		local builder = SectionBuilders[name]
		local section = builder and builder(def, bd)
		if section then
			table.insert(sections, section)
		end
	end

	return {
		title = string.format(
			'<font color="%s">%s</font> <font color="#FFFFFF">%s</font>',
			def.color,
			def.name,
			Attributes.format(key, bd.final)
		),
		icon = icon,
		description = def.description,
		sections = sections,
		footer = def.cap and ("Cap: " .. formatNumber(def.cap, 0)) or nil,
		click = opts.clickable and { text = "CLICK TO VIEW SOURCES!", color = "#FFFF55" } or nil,
	}
end

return Attributes
