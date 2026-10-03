--[[
	Items/Stats (ModuleScript)

	How an item's `stats` table becomes (a) tooltip rows and (b) real
	attribute boosts. Stat keys are the ProfileConfig attribute keys
	(Strength, Defense, Health, CritChance, CritIncrease, MagicFind, Speed,
	PressSpeed ...) plus one pseudo stat, `Damage` (weapon damage, display only).

	Item stat values:
	    Strength = 50                  flat +50
	    CritChance = 10                flat +10 (shown as +10%)
	    Strength = { mult = 0.05 }     +5% multiplier (shown as +5%)
	    Defense  = { flat = 5, mult = 0.1 }   both

	  Stats.rows(stats)    -> tooltip rows { name, value, color, icon }
	  Stats.split(stats)   -> flat{ Attr = n }, mult{ Attr = m }  (m is 1.05 for +5%)
	  Stats.isKnown(key)   -> bool
--]]

local Stats = {}

local TEMPLATE_SHEET = "rbxassetid://86089182239746"
local function sheetIcon(x: number, y: number, size: number)
	return { image = TEMPLATE_SHEET, rectOffset = Vector2.new(x, y), rectSize = Vector2.new(size, size) }
end

-- Keys that display with a % suffix.
Stats.PERCENT = { CritChance = true, CritIncrease = true }

-- Per-stat display tweaks (name / color / icon). Everything not listed here
-- falls back to the ProfileConfig attribute definition.
Stats.OVERRIDES = {
	Damage = { name = "Damage", color = "#FF5555", icon = sheetIcon(675, 0, 175), pseudo = true },
	Strength = { icon = sheetIcon(675, 0, 175) },
	Defense = { icon = sheetIcon(175, 175, 175) },
	CritChance = { icon = sheetIcon(675, 175, 175) },
	CritIncrease = { name = "Crit Damage", icon = sheetIcon(510, 0, 170) },
}

-- Rows are listed in this order first; everything else follows alphabetically.
Stats.ORDER = { "Damage", "Strength", "Defense", "Health", "CritChance", "CritIncrease" }

-- ── ProfileConfig attribute lookup (key -> {name,color,icon}) ──
local attrByKey: { [string]: any } = {}
do
	local modules = script.Parent.Parent
	local cfgModule = modules and modules:FindFirstChild("ProfileConfig")
	local ok, cfg = false, nil
	if cfgModule then
		ok, cfg = pcall(require, cfgModule)
	end
	if ok and cfg and cfg.ATTRIBUTE_CATEGORIES then
		for _, list in pairs(cfg.ATTRIBUTE_CATEGORIES) do
			for _, attr in ipairs(list) do
				attrByKey[attr.key] = attr
			end
		end
	end
end

function Stats.isKnown(key: string): boolean
	return Stats.OVERRIDES[key] ~= nil or attrByKey[key] ~= nil
end

local function describe(key: string)
	local attr = attrByKey[key] or {}
	local over = Stats.OVERRIDES[key] or {}
	return {
		name = over.name or attr.name or key,
		color = over.color or attr.color or "#FFFFFF",
		icon = over.icon or attr.icon,
	}
end

local function fmtNumber(n: number): string
	if n == math.floor(n) then
		return string.format("%d", n)
	end
	local s = string.format("%.2f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s
end

local function parse(value: any): (number?, number?)
	if type(value) == "number" then
		return value, nil
	elseif type(value) == "table" then
		return value.flat, value.mult
	end
	return nil, nil
end

--- Tooltip rows for an item's stats table.
function Stats.rows(stats: { [string]: any }?): { any }
	local rows = {}
	if not stats then
		return rows
	end

	local keys = {}
	for key in pairs(stats) do
		table.insert(keys, key)
	end
	local rank = {}
	for i, key in ipairs(Stats.ORDER) do
		rank[key] = i
	end
	table.sort(keys, function(a, b)
		local ra, rb = rank[a] or 100, rank[b] or 100
		if ra ~= rb then
			return ra < rb
		end
		return a < b
	end)

	for _, key in ipairs(keys) do
		local flat, mult = parse(stats[key])
		local info = describe(key)
		if flat and flat ~= 0 then
			local suffix = Stats.PERCENT[key] and "%" or ""
			local sign = flat > 0 and "+" or ""
			table.insert(rows, {
				name = info.name,
				value = sign .. fmtNumber(flat) .. suffix,
				color = info.color,
				icon = info.icon,
			})
		end
		if mult and mult ~= 0 then
			local sign = mult > 0 and "+" or ""
			table.insert(rows, {
				name = info.name,
				value = sign .. fmtNumber(mult * 100) .. "%",
				color = info.color,
				icon = info.icon,
			})
		end
	end
	return rows
end

--- Split into attribute boosts. Damage (pseudo stat) is skipped.
--- mult values are returned as AttributeStatManager multipliers (1 + mult).
function Stats.split(stats: { [string]: any }?): ({ [string]: number }, { [string]: number })
	local flatOut, multOut = {}, {}
	for key, value in pairs(stats or {}) do
		local over = Stats.OVERRIDES[key]
		if not (over and over.pseudo) then
			local flat, mult = parse(value)
			if flat and flat ~= 0 then
				flatOut[key] = flat
			end
			if mult and mult ~= 0 then
				multOut[key] = 1 + mult
			end
		end
	end
	return flatOut, multOut
end

return Stats
