--[[
	Sources (ModuleScript)

	Where an attribute's value comes from. Every boost the server stores on an
	attribute carries a `sourceType` (and optional itemId / slotId), and this
	module turns those boosts into one entry per source for the breakdown layer.

	Source types are a registry, so a new kind of source is one register() call
	and needs no changes to the breakdown UI or the attribute tooltip:

	    Sources.register("pet", {
	        rank = 20,                         -- ordering between types (lower first)
	        color = "#FF55FF",                 -- default slot / title color
	        description = "Bonus from your active pet.",
	        describe = function(source, ctx) return { title = ..., description = ... } end, -- optional
	    })

	Built in: base, equipment, admin, other.

	  Sources.build(attrKey, data, baseValue) -> ordered array of sources
	      source = { type, id, label, color, flat?, mult?, itemId?, slotId? }
	  Sources.hex(source)       slot / title color
	  Sources.name(source)      display name (item name for equipment)
	  Sources.initials(source)  1-2 letters for the slot face
	  Sources.tooltip(source, attrDef, ctx) -> tooltip config
	      ctx = { TooltipModule = module, amount = "+30", breakdown = bd, totalText = "45" }
	  Sources.typeLabel(source)  "Equipment", "Base", "Admin" ...
	  Sources.detail(source)     extra context, e.g. the equipment slot
--]]

local Items = require(script.Parent:WaitForChild("Items")) :: any

local Sources = {}
Sources.Types = {}

function Sources.register(typeName: string, spec: any)
	spec.rank = spec.rank or 50
	Sources.Types[typeName] = spec
end

-- ===================== BUILT-IN TYPES =====================
Sources.register("base", {
	rank = 0,
	label = "Base",
	color = "#AAAAAA",
	describe = function(source, ctx)
		return {
			title = string.format('<font color="#AAAAAA">Base %s</font>', ctx.attrName or "Value"),
			description = "Your starting value before any items or bonuses.",
		}
	end,
})

Sources.register("equipment", {
	rank = 10,
	label = "Equipment",
	detailOf = function(source)
		return source.slotId
	end,
	color = "#FFFFFF",
	nameOf = function(source)
		local def = source.itemId and Items.get(source.itemId)
		return def and def.displayName or source.label
	end,
	colorOf = function(source)
		local def = source.itemId and Items.get(source.itemId)
		return def and Items.getRarity(def.rarity).hexColor or nil
	end,
	describe = function(source, ctx)
		local def = source.itemId and Items.get(source.itemId)
		if not def or not ctx.TooltipModule then
			return nil
		end
		local config = ctx.TooltipModule.Items.fromTool({
			name = def.toolName,
			displayName = def.displayName,
			rarity = def.rarity,
		})
		config.click = nil
		return config
	end,
})

Sources.register("collection", {
	rank = 20,
	label = "Collection",
	color = "#55FFFF",
	description = "A permanent reward for completing a collection tier.",
})

Sources.register("admin", {
	rank = 90,
	label = "Admin",
	color = "#FF55FF",
	description = "Debug bonus from /set or /add. Cleared with /reset.",
})

Sources.register("other", {
	rank = 50,
	label = "Bonus",
	color = "#FFFFFF",
	description = "A bonus applied to this attribute.",
})

-- ===================== BUILD =====================
local function classify(boost: any): string
	if boost.sourceType and Sources.Types[boost.sourceType] then
		return boost.sourceType
	end
	if boost.itemId then
		return "equipment"
	end
	return "other"
end

function Sources.build(attrKey: string, data: any, baseValue: number): { any }
	local list = {}
	if baseValue ~= 0 then
		table.insert(list, { type = "base", id = "base", label = "Base", color = "#AAAAAA", flat = baseValue })
	end

	local byId, ordered = {}, {}
	local function sourceFor(boost)
		local id = boost.id or ("label:" .. tostring(boost.label))
		local src = byId[id]
		if not src then
			src = {
				type = classify(boost),
				id = id,
				label = boost.label or "Unknown",
				color = boost.color,
				itemId = boost.itemId,
				slotId = boost.slotId,
				order = #ordered + 1,
			}
			byId[id] = src
			table.insert(ordered, src)
		end
		return src
	end

	for _, boost in ipairs(data and data.flatBoosts or {}) do
		local src = sourceFor(boost)
		src.flat = (src.flat or 0) + (tonumber(boost.value) or 0)
	end
	for _, boost in ipairs(data and data.multipliers or {}) do
		local src = sourceFor(boost)
		src.mult = (src.mult or 1) + ((tonumber(boost.value) or 1) - 1)
	end

	local slotRank = {}
	for i, slotId in ipairs(Items.Slots.Order) do
		slotRank[slotId] = i
	end
	table.sort(ordered, function(a, b)
		local ra, rb = Sources.Types[a.type].rank, Sources.Types[b.type].rank
		if ra ~= rb then
			return ra < rb
		end
		local sa, sb = slotRank[a.slotId or ""] or 100, slotRank[b.slotId or ""] or 100
		if sa ~= sb then
			return sa < sb
		end
		return a.order < b.order
	end)
	for _, src in ipairs(ordered) do
		table.insert(list, src)
	end
	return list
end

-- ===================== PRESENTATION =====================
function Sources.name(source: any): string
	local spec = Sources.Types[source.type]
	return spec and spec.nameOf and spec.nameOf(source) or source.label or "?"
end

function Sources.hex(source: any): string
	local spec = Sources.Types[source.type]
	return (spec and spec.colorOf and spec.colorOf(source)) or source.color or (spec and spec.color) or "#FFFFFF"
end

function Sources.typeLabel(source: any): string
	local spec = Sources.Types[source.type]
	return spec and spec.label or "Bonus"
end

function Sources.detail(source: any): string?
	local spec = Sources.Types[source.type]
	return spec and spec.detailOf and spec.detailOf(source) or nil
end

function Sources.initials(source: any): string
	local words = {}
	for word in Sources.name(source):gmatch("[%a']+") do
		table.insert(words, (word:gsub("'", "")))
	end
	local text = #words >= 2 and (words[1]:sub(1, 1) .. words[2]:sub(1, 1)) or (words[1] or "?"):sub(1, 2)
	return text:upper()
end

function Sources.tooltip(source: any, attrDef: any, ctx: any): any
	ctx = ctx or {}
	ctx.attrName = attrDef.name
	local spec = Sources.Types[source.type]
	local config = spec.describe and spec.describe(source, ctx) or nil
	if not config then
		config = {
			title = string.format('<font color="%s">%s</font>', Sources.hex(source), Sources.name(source)),
			description = spec.description or "A bonus applied to this attribute.",
		}
	end

	-- "Contribution to X": amount, share of the total, where it comes from, new total.
	local attrColor = attrDef.color or "#FFFFFF"
	local rows = {
		{ label = "Amount", value = ctx.amount or "", color = attrColor },
	}
	local bd = ctx.breakdown
	if bd then
		local share
		if source.type == "base" then
			share = bd.final ~= 0 and (source.flat or 0) / bd.final or nil
		elseif source.flat and bd.flat ~= 0 then
			share = source.flat / bd.flat
		elseif source.mult and bd.mult ~= 1 then
			share = (source.mult - 1) / (bd.mult - 1)
		end
		if share then
			table.insert(rows, {
				label = "Share",
				value = string.format("%d%%", math.floor(share * 100 + 0.5)),
				color = "#FFFF55",
				detail = source.type == "base" and "of total" or "of bonuses",
			})
		end
	end
	table.insert(rows, {
		label = "Source",
		value = Sources.typeLabel(source),
		color = Sources.hex(source),
		detail = Sources.detail(source) and ("(" .. Sources.detail(source) .. ")") or nil,
	})
	if ctx.totalText then
		table.insert(rows, { label = "Total " .. (attrDef.name or ""), value = ctx.totalText, color = "#FFFFFF" })
	end

	config.sections = config.sections or {}
	table.insert(config.sections, 1, {
		type = "list",
		title = "Contribution to " .. (attrDef.name or "?"),
		color = attrColor,
		rows = rows,
		first = true,
	})
	return config
end

return Sources
