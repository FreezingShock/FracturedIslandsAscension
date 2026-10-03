--[[
	TooltipModule/Sections (ModuleScript)

	Generic, data-driven tooltip sections. A tooltip config may carry
	  sections = { { type = "list", title = "Summary", rows = {...} }, ... }
	and the tooltip works out what to draw from what it is given - callers never
	touch the template. Each section type is a small function that turns a
	section into a "block" (title + rich text) the template already renders, so
	new section types need no GUI work.

	Dynamic sections always render CENTERED in the pixel font (Style.FONT_DYNAMIC)
	and accept Minecraft color codes (&a green, &7 gray, &f white, &e yellow ...).

	Built-in types:
	  text          { title, text }                      free text, color codes OK
	  list          { title, rows = { row, ... } }       one centered line per row
	  requirements  { title, rows = { { label, met = bool }, ... } }
	  stats         { title, rows = { {name, value, color, icon}, ... } }
	                (drawn in the template's stats area; a second one falls back to a list)

	A list row is either
	  { label = "Base", value = "10", labelColor = "#AAAAAA", color = "#FFFFFF",
	    detail = "(Chestplate)" }          -> "Base 10 (Chestplate)"
	or a free line:
	  { text = "&7Share &f67% &7of all bonuses" }

	Color note: avoid &8 / #555555 (dark gray) in dynamic text, it is hard to read
	on the tooltip background. Use &7 for secondary text.

	Common fields on any section:
	  color         accent color for the header
	  hidden        true = skip
	  first         true = place above the other blocks
	  collapsible   true = can fold. Collapsed shows `summary`; HOLD SHIFT to expand.
	  collapsed     default state when collapsible (default true)
	  summary       line(s) shown while collapsed (color codes OK)

	Add a type:   Sections.register("effects", function(section) return { title=..., text=... } end)
--]]

local Style = require(script.Parent:WaitForChild("Style"))
local Rich = require(script.Parent:WaitForChild("Rich"))

local Sections = {}

Sections.Types = {}

local LABEL = "#AAAAAA"
local VALUE = "#FFFFFF"
local DETAIL = "#AAAAAA"

function Sections.register(typeName: string, builder: (section: any) -> any?)
	Sections.Types[typeName] = builder
end

local function colored(text: any, hex: string): string
	return string.format('<font color="%s">%s</font>', Style.hex(hex), tostring(text))
end

local function rowLine(row: any): string
	if row.text ~= nil then
		return Rich.mc(row.text)
	end
	local line = colored(Rich.mc(row.label or "?"), row.labelColor or LABEL)
	if row.value ~= nil and row.value ~= "" then
		line ..= "  " .. colored(row.value, row.color or VALUE)
	end
	if row.detail ~= nil and row.detail ~= "" then
		line ..= " " .. colored(row.detail, DETAIL)
	end
	return line
end

--- A centered dynamic block.
local function block(title: any, lines: { string }, color: any, extra: any?): any
	local spec = {
		title = title,
		text = table.concat(lines, "\n"),
		color = color,
		align = "Center",
		dynamic = true,
	}
	for k, v in pairs(extra or {}) do
		spec[k] = v
	end
	return spec
end

Sections.register("text", function(section)
	return block(section.title, { Rich.mc(section.text or "") }, section.color)
end)

Sections.register("list", function(section)
	local lines = {}
	for _, row in ipairs(section.rows or {}) do
		table.insert(lines, rowLine(row))
	end
	return block(section.title, lines, section.color)
end)

Sections.register("requirements", function(section)
	local lines = {}
	for _, row in ipairs(section.rows or {}) do
		local met = row.met == true
		table.insert(lines, colored((met and "+ " or "x ") .. tostring(row.label or "?"), met and "#55FF55" or "#FF5555"))
	end
	return block(section.title or "Requirements", lines, section.color or "#FF5555")
end)

--- Expand cfg.sections into the template channels (stats / blocks).
--- `expandAll` = true while SHIFT is held. Mutates cfg (a copy).
function Sections.resolve(cfg: any, expandAll: boolean)
	local list = cfg.sections
	if type(list) ~= "table" then
		return
	end

	local front, back = {}, {}
	for _, existing in ipairs(cfg.blocks or {}) do
		table.insert(back, existing)
	end

	for _, section in ipairs(list) do
		if section.hidden then
			continue
		end

		-- First "stats" section drives the template's stats area.
		if section.type == "stats" and cfg.stats == nil and section.rows and #section.rows > 0 then
			cfg.stats = section.rows
			if section.title ~= nil then
				cfg.statsTitle = section.title
			end
			continue
		end

		local builder = Sections.Types[section.type or "text"]
		if section.type == "stats" then
			builder = Sections.Types.list
		end
		builder = builder or Sections.Types.text
		local spec = builder(section)
		if not spec then
			continue
		end

		if section.collapsible then
			local startsCollapsed = section.collapsed ~= false
			local expanded = expandAll or not startsCollapsed
			local title = spec.title or section.title or ""
			if expanded then
				spec.title = "- " .. title
			else
				spec.title = "+ " .. title .. ' <font color="#FFFF55">[SHIFT]</font>'
				spec.text = section.summary and Rich.mc(section.summary) or nil
			end
		end
		table.insert(section.first and front or back, spec)
	end

	for _, spec in ipairs(back) do
		table.insert(front, spec)
	end
	cfg.blocks = front
	cfg.sections = nil
end

return Sections
