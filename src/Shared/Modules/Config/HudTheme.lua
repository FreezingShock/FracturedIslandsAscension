--[[
	HudTheme (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	Design tokens exported from the Figma file "FIA HUD - Health, Mana, XP, Hotbar" (collection "FIA HUD"). Every colour
	and size the HUD builders and controllers use lives here, so restyling the HUD is a change to this one table.
	Sizes are in pixels at the Figma 1:1 scale (the HUD frame is 1088 x 276; one art pixel = PIXEL = 4 px).

	Pixel icons are character maps: one string per row, '.' = transparent, any other character is a key into the icon's
	palette. build_resource_panels.luau turns them into Frames (one Frame per horizontal run, no image upload needed).
--]]

local function hex(h: string): Color3
	local n = tonumber(h:sub(2), 16) :: number
	return Color3.fromRGB(bit32.rshift(n, 16) % 256, bit32.rshift(n, 8) % 256, n % 256)
end

local HudTheme = {}

HudTheme.PIXEL = 4

HudTheme.colors = {
	panelFill = hex("#8c6c50"),
	panelBorder = hex("#3b2a1f"),
	panelHighlight = hex("#c4a07a"),
	panelShadow = hex("#6a4e38"),
	panelTrack = hex("#5e4330"),
	postFill = hex("#7a5c44"),
	postCap = hex("#b09478"),
	slotFill = hex("#d9ab70"),
	slotBorder = hex("#5a3d28"),
	slotShadow = hex("#c28f55"),
	slotHighlight = hex("#e8bd8a"),
	slotSelectedFill = hex("#e8c98f"),
	slotSelectedBorder = hex("#b9a6d8"),
	hpFill = hex("#e0614c"),
	hpDark = hex("#b04334"),
	hpLight = hex("#f08a74"),
	hpCap = hex("#f6b09c"),
	hpTrack = hex("#3a1f1a"),
	manaFill = hex("#3f6fb5"),
	manaDark = hex("#2a4a85"),
	manaLight = hex("#5ab4e8"),
	manaCap = hex("#9fd8f5"),
	manaTrack = hex("#1c2a4a"),
	xpFull = hex("#5aa845"),
	xpFullDark = hex("#2f6a2a"),
	xpCore = hex("#f3e28a"),
	xpEmpty = hex("#35682c"),
	xpEmptyCore = hex("#43843a"),
	badgeFill = hex("#fde88a"),
	badgeRing = hex("#e4c27a"),
	badgeShade = hex("#f1d27a"),
	badgeBorder = hex("#4a3322"),
	badgeWhite = hex("#ffffff"),
	leafFill = hex("#5aa845"),
	leafDark = hex("#2f6a2a"),
	leafLight = hex("#8fd070"),
	text = hex("#ffffff"),
	textStroke = hex("#1a1210"),
	textShadow = hex("#4a3a30"),
	barOutline = hex("#1a1210"),
}

-- Resource panel (Health on the left, Mana on the right); bar = 276 x 24 with a 4 px outline, fill steps in 4 px
HudTheme.resourcePanel = {
	size = Vector2.new(356, 96),
	border = 4,
	textSize = 36, -- game HUD font (Silkscreen is not a Roblox font) + 2 px hard drop shadow, 40 px tall box at y = 12
	textY = 12,
	barSize = Vector2.new(276, 24),
	barY = 56,
	iconMargin = 15, -- panel edge -> icon
	iconGap = 8, -- icon -> bar
	barMarginFar = 24, -- bar -> the opposite panel edge
	topFillPx = 4, -- highlight strip on top of the fill
	shadeFillPx = 4, -- dark strip under the fill
	capPx = 4, -- bright end cap on the fill
}

-- StatsMenu.Stats scaling and row order (Stats is a horizontal list: Health | Stamina | Mana)
HudTheme.hud = {
	fullScaleWidth = 1280, -- viewport width at which the HUD is shown at 1:1; Stats' UIScale shrinks it below that
	minScale = 0.5,
	rowOrder = { Health = 1, Stamina = 2, Mana = 3 },
}

HudTheme.icons = {
	heart = {
		cell = 3,
		palette = { o = "#3a1410", r = "hpFill", l = "hpLight" },
		rows = {
			"..ooo.ooo..",
			".orrrorrro.",
			"orlrrrrrrro",
			"orlrrrrrrro",
			"orrrrrrrrro",
			".orrrrrrro.",
			"..orrrrro..",
			"...orrro...",
			"....oro....",
			".....o.....",
		},
	},
	-- Intelligence pencil, 12x12 (cell 3 so Frames stay on whole pixels; the Figma icon is 33 px, this one 36 px)
	pencil = {
		cell = 3,
		palette = { o = "#0e1f4a", b = "manaFill", l = "manaLight", D = "manaDark" },
		rows = {
			"........oo..",
			"......oolbo.",
			".....olobolo",
			"....olololbo",
			"...ololbbooo",
			"..ololbbolo.",
			".ololbbolo..",
			"ololbbolo...",
			"obobbolo....",
			"oDDooDo.....",
			"ooDDDo......",
			"ooooo.......",
		},
	},
}

return HudTheme
