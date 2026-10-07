--[[
	ScoreboardConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The right-side scoreboard (StarterGui.FIAScoreboard, driven by ScoreboardController). Hypixel-SkyBlock style, in the drop-tooltip look.

	LAYERS, each overriding the one before:
	  1. library[<lineId>]      every line the scoreboard knows: { format, when? }
	  2. order                  the default top-to-bottom list of line ids ("-" = a blank spacer)
	  3. zones[<zoneKey>]       per zone: name + color for the zone line, and `bottom` = the zone-specific lines (ids of library or of
	                            this zone's own `lines`) shown above the footer. A zone key is a ZoneConfig.ZONES key (the player
	                            attribute `Zone` set by ZoneManager); a player in no zone is in `defaultZone`.

	FORMAT: Roblox rich text ("<font color='#FFAA00'>...</font>") plus tokens in braces:
	  {date} {server} {calendar} {time} {zone} {zoneColor} {zonePlayers} {coins} {objective} {fontValue}
	FONTS: the label's base font (Panel.Template.Text.FontFace; Noto Sans once uploaded, until then the tooltip body font) is for easy-to-read words: "Purse:", "Objective", the in-game clock). VALUES (the purse
	  number, zone name, real-life date, title, objective text) use the pixel font Silkscreen: wrap them in
	  <font family='{fontValue}' color='#...'>...</font>. The base font is the Text label's FontFace in the Studio template.
	`when` hides the line when that token is empty ("objective" -> only shown while the player has an Objective).
	Colours are the Minecraft palette: gold-title #FFD700, gold #FFAA00, green #55FF55, aqua #55FFFF, red #FF5555, yellow #FFFF55,
	gray #AAAAAA, dark gray #555555, white #FFFFFF.

	RECIPES
	  New line:                 library.foo = { format = "<font color='#AAAAAA'>Foo:</font> {x}" } and add "foo" to order (or a zone bottom)
	  New zone:                 zones.mines = { name = "Deep Mines", color = "#55FFFF", bottom = { "hint" } }  (+ the zone in ZoneConfig.ZONES)
	  Zone-only line:           zones.dummy_yard.lines.kills = { format = "..." } and put "kills" in its bottom
	  Hide the whole board:     enabled = false
	  Put the [J] hint back:    add "hint" at the end of order (the line still exists in the library)
	  Move it:                  layout.yScale (fraction of the screen height) and layout.rightMargin (px at 1080p)
	  Fainter / solid:          layout.bodyTransparency and layout.borderTransparency
	The panel scales with the viewport (layout.baseHeight is the screen height it was designed for).
]]

local ScoreboardConfig = {}

ScoreboardConfig.enabled = true

ScoreboardConfig.layout = {
	width = 300, -- px at baseHeight (outer border included); long lines wrap instead of widening it
	textSize = 24, -- every line
	spacerHeight = 6,
	rightMargin = 16, -- px at baseHeight
	yScale = 0.28, -- top edge of the panel as a fraction of the screen height
	baseHeight = 1080, -- the screen height the pixel sizes are designed for (UIScale = screen height / baseHeight, clamped)
	minScale = 0.6,
	maxScale = 1.4,
	bodyTransparency = 0.5, -- the body gradient (0 = solid, 1 = invisible); the Hypixel board is a faint dark glass
	borderTransparency = 0.6, -- the 4px outer border
	refreshEvery = 0.25, -- seconds between token refreshes (a line is only rewritten when its text changed)
}

ScoreboardConfig.fonts = { value = "rbxassetid://12187371840" } -- Silkscreen (the tooltip pixel font); the base font is on the template

ScoreboardConfig.defaultZone = "unknown"
ScoreboardConfig.defaultObjective = "Craft a workbench" -- until a quest system sets the player attribute Objective
ScoreboardConfig.serverIdLength = 4 -- characters of game.JobId shown

ScoreboardConfig.library = {
	title = { format = "<font family='{fontValue}' color='#FFD700'>FRACTURED ISLANDS</font>", center = true },
	date = { format = "<font family='{fontValue}' color='#AAAAAA'>{date}</font> <font family='{fontValue}' color='#555555'>{server}</font>" },
	calendar = { format = "<font color='#FFFFFF'>{calendar}</font>" },
	clock = { format = "<font color='#AAAAAA'>{time}</font>" },
	zone = { format = "<font family='{fontValue}' color='{zoneColor}'>{zone}</font>" },
	zonePlayers = { format = "<font color='#AAAAAA'>In zone:</font> <font family='{fontValue}' color='#55FFFF'>{zonePlayers}</font>" },
	purse = { format = "<font color='#FFFFFF'>Purse:</font> <font family='{fontValue}' color='#FFAA00'>{coins}</font>", flashOnChange = true },
	objectiveTitle = { format = "<font color='#FFFFFF'>Objective</font>", when = "objective" },
	objective = { format = "<font family='{fontValue}' color='#FFFF55'>{objective}</font>", when = "objective" },
	hint = { format = "<font color='#FFFF55'>[J]</font> <font color='#AAAAAA'>Recent gains</font>" },
}

-- the lines every zone shows, top to bottom; "-" is a blank spacer; "@bottom" is replaced by the zone's own lines (then a spacer)
ScoreboardConfig.order = {
	"title",
	"date",
	"-",
	"calendar",
	"clock",
	"zone",
	"zonePlayers",
	"-",
	"purse",
	"-",
	"objectiveTitle",
	"objective",
	"-",
	"@bottom",
}

ScoreboardConfig.zones = {
	unknown = { name = "Unknown", color = "#AAAAAA", bottom = {} },
	starter_island = { name = "Starter Island", color = "#55FF55", bottom = {} },
	dummy_yard = {
		name = "Dummy Yard",
		color = "#FF5555",
		bottom = { "danger", "dummies" },
		lines = {
			danger = { format = "<font color='#AAAAAA'>Danger:</font> <font family='{fontValue}' color='#55FF55'>LOW</font>" },
			dummies = { format = "<font color='#AAAAAA'>Dummies:</font> <font family='{fontValue}' color='#FF5555'>7/10</font>" },
		},
	},
}

--- The zone entry for a zone key (the default zone when the key is nil or not configured).
function ScoreboardConfig.zone(key: string?): (string, any)
	local k = key and ScoreboardConfig.zones[key] and key or ScoreboardConfig.defaultZone
	return k, ScoreboardConfig.zones[k]
end

--- The ordered list of { id, def } for a zone: order with "@bottom" expanded and conditions left to the controller.
function ScoreboardConfig.linesFor(key: string?): { any }
	local _, zone = ScoreboardConfig.zone(key)
	local out = {}
	local function def(id: string)
		return (zone.lines and zone.lines[id]) or ScoreboardConfig.library[id]
	end
	for _, id in ipairs(ScoreboardConfig.order) do
		if id == "-" then
			table.insert(out, { id = "spacer", spacer = true })
		elseif id == "@bottom" then
			local bottom = zone.bottom or {}
			for _, bid in ipairs(bottom) do
				if def(bid) then
					table.insert(out, { id = bid, def = def(bid) })
				end
			end
			if #bottom > 0 then
				table.insert(out, { id = "spacer", spacer = true })
			end
		elseif def(id) then
			table.insert(out, { id = id, def = def(id) })
		end
	end
	return out
end

return ScoreboardConfig
