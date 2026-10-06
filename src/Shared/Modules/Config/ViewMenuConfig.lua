--[[
	ViewMenuConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The info rows of StarterGui.ViewMenu.View (bottom right), stacked upward above the POV / Cursor labels that
	CameraController drives. Layers, like CombatConfig:

	  library   row type id -> definition (what a row looks like and where its value comes from)
	  order     the enabled rows, BOTTOM TO TOP above Cursor: edit this list per update
	  overrides id -> partial definition merged over the library entry (e.g. a different colour for one build)

	Row text format, shared with the hand-made POV / Cursor labels (CameraController uses ViewMenuConfig.format too):
	<font color=word>WORD</font> <font color=gray>—</font> <font color=value>value</font>   e.g.  FPS — 60

	Definition fields
	  word         the coloured word
	  wordColor    "#RRGGBB" (Minecraft colour codes: red #FF5555, green #55FF55, yellow #FFFF55, aqua #55FFFF,
	               gold #FFAA00, light purple #FF55FF, white #FFFFFF, gray #AAAAAA)
	  valueColor   fixed colour of the value, OR
	  valueColors  { mode = "atLeast" | "atMost", steps = { { threshold, colour }, ... } } the first step that matches the number wins
	  provider     id of the value provider in ViewMenuController (PROVIDERS): returns the value text and its number
	  refresh      seconds between updates
	  sample       placeholder value text the Studio builder puts in the label (so the layout is visible without playing)
	  idleFade     { after = seconds } hide the row once its number has been 0 for that long (fades back on a non-zero)

	Add a row: put an entry in `library`, add its id to `order`, and (only when the value is something new) one provider
	function in ViewMenuController. No layout code changes.
--]]

local RED, GREEN, YELLOW, AQUA, GOLD, PURPLE, WHITE = "#FF5555", "#55FF55", "#FFFF55", "#55FFFF", "#FFAA00", "#FF55FF", "#FFFFFF"

local ViewMenuConfig = {}

-- the dash between a word and its value (a long dash, gray)
ViewMenuConfig.separator = { text = "\u{2014}", color = "#AAAAAA" }

ViewMenuConfig.toggleKey = Enum.KeyCode.U -- shows / hides every info row (session only); POV and Cursor are not affected
ViewMenuConfig.rowHeight = 24 -- px at scale 1: the pitch of POV / Cursor in the hand-made group
ViewMenuConfig.baseHeight = 46 -- px of the two hand-made labels (Cursor on top of POV) at the bottom of View
ViewMenuConfig.minWidth = 300 -- View's hand-made width
ViewMenuConfig.rowMove = 0.18 -- seconds rows take to slide when others appear or disappear
ViewMenuConfig.fade = 0.2 -- seconds a row takes to fade in or out

-- Scale: the HUD (FIAHUD) uses the middle half of the screen width; the info rows must fit the free right quarter.
ViewMenuConfig.scale = {
	referenceHeight = 1080, -- screen height at which the rows are drawn 1:1
	freeWidthFraction = 0.25, -- the free area to the right of the HUD
	margin = 16, -- View's offset from the screen edge (px, not scaled)
	min = 0.5,
	max = 1.25,
}

-- DPS: the server (DamageTracker) sums your damage over the last `window` seconds and divides by it, at most 1/publish times a second.
ViewMenuConfig.dps = { window = 5, publish = 0.25, attribute = "DPS" }

ViewMenuConfig.library = {
	DPS = {
		word = "DPS",
		wordColor = RED,
		valueColor = RED,
		provider = "dps",
		sample = "0",
		refresh = 0.1,
		idleFade = { after = 1 }, -- DPS is 0 five seconds after the last hit, so the row leaves about 6 s after it
	},
	FPS = {
		word = "FPS",
		wordColor = WHITE,
		valueColors = { mode = "atLeast", steps = { { 55, GREEN }, { 30, YELLOW }, { -math.huge, RED } } },
		provider = "fps",
		sample = "60",
		refresh = 0.5,
	},
	PING = {
		word = "PING",
		wordColor = WHITE,
		valueColors = { mode = "atMost", steps = { { 80, GREEN }, { 150, YELLOW }, { math.huge, RED } } },
		provider = "ping",
		sample = "50ms",
		refresh = 1,
	},
	SERVER = {
		word = "SERVER",
		wordColor = AQUA,
		valueColor = YELLOW,
		provider = "players",
		sample = "1/50",
		refresh = 2,
	},
	UP = {
		word = "UP",
		wordColor = GOLD,
		valueColor = YELLOW,
		provider = "uptime",
		sample = "0s",
		refresh = 1,
	},
	VERSION = {
		word = "VERSION",
		wordColor = PURPLE,
		valueColor = YELLOW,
		provider = "version",
		sample = "3.53.0 / v0",
		refresh = 60,
	},
}

ViewMenuConfig.order = { "DPS", "FPS", "PING", "SERVER", "UP", "VERSION" }

ViewMenuConfig.overrides = {}

--- "WORD — value" with Minecraft colours. A nil wordColor leaves the word in the label's own colour (POV eases it).
function ViewMenuConfig.format(word: string, wordColor: string?, value: string?, valueColor: string?): string
	local head = wordColor and string.format('<font color="%s">%s</font>', wordColor, word) or word
	if value == nil then
		return head
	end
	local sep = ViewMenuConfig.separator
	return string.format('%s <font color="%s">%s</font> <font color="%s">%s</font>', head, sep.color, sep.text, valueColor or "#FFFF55", value)
end

--- The merged definition of a row (library entry + override), or nil when the id is unknown.
function ViewMenuConfig.get(id: string): any?
	local base = ViewMenuConfig.library[id]
	if not base then
		return nil
	end
	local merged = table.clone(base)
	for key, value in pairs(ViewMenuConfig.overrides[id] or {}) do
		merged[key] = value
	end
	return merged
end

return ViewMenuConfig
