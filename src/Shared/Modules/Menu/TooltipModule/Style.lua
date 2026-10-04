--[[
	TooltipModule/Style (ModuleScript)

	Every visual constant the tooltip uses lives here, so restyling never
	means editing the renderer:
	  - font families
	  - stat-icon spritesheet
	  - the Minecraft-style color pairs (bright / dark) used for strokes
	  - skill colors, click-hint icons
	  - hex <-> Color3 helpers
--]]

local Style = {}

-- ===================== FONTS =====================
-- These match the fonts already used inside StarterGui.TooltipMenu.Template.
Style.FONT_PIXEL = "rbxassetid://12187371840" -- stat values, ability titles, pills
Style.FONT_BODY = "rbxassetid://12187370747" -- descriptions
-- Font for DYNAMIC sections (attribute summaries, sources, contributions...).
-- To use Silkscreen: upload it as a font family and put its asset id here.
Style.FONT_DYNAMIC = Style.FONT_PIXEL
Style.DYNAMIC_TEXT_SIZE = 20

-- Minecraft color codes (&a, &7 ... also accepted as §a) -> hex.
Style.MC_CODES = {
	["0"] = "#000000", ["1"] = "#0000AA", ["2"] = "#00AA00", ["3"] = "#00AAAA",
	["4"] = "#AA0000", ["5"] = "#AA00AA", ["6"] = "#FFAA00", ["7"] = "#AAAAAA",
	["8"] = "#555555", ["9"] = "#5555FF", a = "#55FF55", b = "#55FFFF",
	c = "#FF5555", d = "#FF55FF", e = "#FFFF55", f = "#FFFFFF",
}

-- ===================== STAT ICON SPRITESHEET =====================
-- Icons are addressed as { col, row } on a grid of cellSize x cellSize cells.
-- Anything that already uses ProfileConfig icons ({col,row}) keeps working.
-- To use a different sheet for one icon, pass { image = "rbxassetid://...",
-- rectOffset = Vector2.new(x, y), rectSize = Vector2.new(w, h) } instead.
Style.SPRITE = {
	assetId = "rbxassetid://115852737004664",
	cellSize = 170,
}

-- ===================== COLOR PAIRS =====================
-- bright -> dark (Minecraft chat-color pairs). Used to derive stroke and
-- background colors from a single "main" color.
local DARK_OF = {
	["#FF5555"] = "#AA0000",
	["#FF55FF"] = "#AA00AA",
	["#FFFF55"] = "#FFAA00",
	["#55FF55"] = "#00AA00",
	["#55FFFF"] = "#00AAAA",
	["#5555FF"] = "#0000AA",
	["#FFFFFF"] = "#AAAAAA",
	["#AAAAAA"] = "#555555",
	["#FFAA00"] = "#AA5500",
}
local BRIGHT_OF = {}
for bright, dark in pairs(DARK_OF) do
	BRIGHT_OF[dark] = bright
end

Style.DEFAULT_TITLE_COLOR = "#FFFFFF"
Style.DEFAULT_STATS_TITLE = "STATS"
Style.DEFAULT_STATS_COLOR = "#55FF55"
Style.DEFAULT_BLOCK_COLOR = "#FFAA00"
Style.DEFAULT_CLICK_COLOR = "#FFFF55"

-- Skill -> tag color (used by Items.fromTool for skill badges).
Style.SKILL_COLORS = {
	Farming = "#FFAA00",
	Foraging = "#55FF55",
	Fishing = "#55FFFF",
	Mining = "#5555FF",
	Combat = "#FF5555",
	Carpentry = "#FFAA00",
	General = "#FFFFFF",
}

-- Click-hint icons live on one sheet; "lmb" and "rmb" are the two currently
-- drawn in the template.
Style.CLICK_ICONS = {
	lmb = { offset = Vector2.new(0, 0), size = Vector2.new(32, 32) },
	rmb = { offset = Vector2.new(32, 0), size = Vector2.new(32, 32) },
}

-- Shared click-hint pills (the icon is the mouse button, the text finishes the sentence).
-- Right click = green (equip), left click = aqua (drag).
Style.CLICK_HINTS = {
	equip = { text = "TO EQUIP", color = "#55FF55", icon = "rmb" },
	unequip = { text = "TO UNEQUIP", color = "#55FF55", icon = "rmb" },
	drag = { text = "TO DRAG", color = "#55FFFF", icon = "lmb" },
}

-- ===================== COLOR HELPERS =====================

--- Normalize a Color3 or "#RRGGBB"/"RRGGBB" string to upper-case "#RRGGBB".
function Style.hex(color: any): string
	if typeof(color) == "Color3" then
		return string.format(
			"#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5)
		)
	end
	local s = tostring(color or "#FFFFFF"):upper()
	if s:sub(1, 1) ~= "#" then
		s = "#" .. s
	end
	return s
end

function Style.color3(color: any): Color3
	if typeof(color) == "Color3" then
		return color
	end
	local ok, c = pcall(Color3.fromHex, Style.hex(color))
	return ok and c or Color3.new(1, 1, 1)
end

--- The darker partner of a color (stroke / background tint).
function Style.dark(color: any): string
	local hex = Style.hex(color)
	if DARK_OF[hex] then
		return DARK_OF[hex]
	end
	local h, s, v = Style.color3(hex):ToHSV()
	return Style.hex(Color3.fromHSV(h, s, v * 0.6))
end

--- The brighter partner of a color. Palette colors are already "bright".
function Style.light(color: any): string
	local hex = Style.hex(color)
	if DARK_OF[hex] then
		return hex
	end
	if BRIGHT_OF[hex] then
		return BRIGHT_OF[hex]
	end
	return Style.hex(Style.color3(hex):Lerp(Color3.new(1, 1, 1), 0.35))
end

return Style
