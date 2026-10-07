--[[
	ActionBarConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The ACTION BAR: one centered Silkscreen line above the hotbar name row (StarterGui.FIAHUD.Root.ActionBar, driven by
	ActionBarClient). Any text shown there stays for `hold` seconds (5 by default), types in, and fades out. It is fed by the
	server (ActionBarService fires the RemoteEvent "ActionBar"): the client sends nothing.

	LAYERS, each overriding the one before:
	  1. library.default       timing and feel shared by everything: hold, fades, typing speed, rise / sink, pop
	  2. kinds[<kind>]         per message kind: "xp" (skill XP), "levelup" (XP that finished a level), "text" (ActionBar.show)
	  3. skills[<SkillName>]   per skill overrides of a kind's pieces (e.g. skills.Combat = { levelColor = "#FF5555" })
	ActionBarConfig.kind(kind, skill) returns library.default < kinds[kind] < skills[skill] merged.

	XP LINE: pieces (gain, sep, pct) joined in order, each { color, format }. Tokens: {gain} {skill} {SKILL} {pct} {level}.
	STACKING: more XP of the same skill while the line is up SUMS (no retype, the number pops, % tweens, hold restarts);
	another skill replaces the line (the old one fades out first).
	LEVEL-UP: the XP line gets sep + `level` piece typed in, then `congrats` types in on a second line and flashes; nothing
	can overwrite it for its duration.

	COLOURS (Minecraft): dark aqua #00AAAA, gray #AAAAAA, gold #FFAA00, green #55FF55, light purple #FF55FF, yellow #FFFF55.
	`color = "skill"` uses the skill's colour from SkillsConfig.

	SOUNDS: { id, volume, pitch }; "" = silent until you have ids.

	RECIPES
	  Hold longer:               library.default.hold = 8
	  Faster typing:             library.default.typeSpeed = 90
	  Another colour for gains:  kinds.xp.pieces.gain.color = "#55FFFF"
	  Combat level text red:     skills.Combat = { levelColor = "#FF5555" }
	  New message from code:     ActionBarService.show(player, "<font color='#55FF55'>Saved!</font>", { hold = 3 })
]]

local ActionBarConfig = {}

ActionBarConfig.library = {
	default = {
		hold = 5, -- seconds a message stays after it finished typing / was last updated
		fadeIn = 0.18, -- the first frame fades in while rising
		fadeOut = 0.4,
		rise = 6, -- px it rises into place
		sink = 6, -- px it sinks while fading out
		typeSpeed = 70, -- characters per second of the typewriter (about 0.4s for a normal XP line)
		replaceFade = 0.15, -- seconds the old line takes to fade before a different skill's line types in
		pop = { scale = 1.14, time = 0.2 }, -- the number pop when a stacked gain arrives
		pctTween = 0.25, -- seconds the % takes to move to its new value
		sounds = {
			tick = { id = "", volume = 0.25, pitch = 1.6 }, -- every few typed characters
			pop = { id = "", volume = 0.4, pitch = 1 }, -- a stacked gain
			levelup = { id = "", volume = 0.7, pitch = 1 }, -- the level-up line
		},
	},
}

ActionBarConfig.kinds = {
	-- "+15 Combat XP - 10.0%"
	xp = {
		pieces = {
			gain = { color = "#00AAAA", format = "+{gain} {skill} XP" },
			sep = { color = "#AAAAAA", format = " - " },
			pct = { color = "#FFAA00", format = "{pct}%" },
		},
		order = { "gain", "sep", "pct" },
	},
	-- "+15 Combat XP - 100.0% - COMBAT LEVEL 12" then CONGRATULATIONS underneath
	levelup = {
		hold = 3,
		levelColor = "skill", -- colour of "COMBAT LEVEL 12" ("skill" = the skill's colour)
		levelFormat = "{SKILL} LEVEL {level}",
		levelTypeSpeed = 22, -- slower: this is the moment
		congrats = {
			text = "CONGRATULATIONS",
			color = "#FF55FF",
			flash = "#FFD700", -- the outline flashes this colour when it lands
			flashTime = 0.5,
			typeSpeed = 18,
			hold = 2.5,
		},
	},
	-- ActionBarService.show(player, text, opts): any rich text, default 5s
	text = {},
}

-- per skill overrides (levelColor etc.); everything not listed uses the kind's value
ActionBarConfig.skills = {}

local function merge(base: any, over: any): any
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(over or {}) do
		if type(v) == "table" and type(out[k]) == "table" and #v == 0 then
			out[k] = merge(out[k], v)
		else
			out[k] = v
		end
	end
	return out
end

--- library.default < kinds[kind] < skills[skill], merged.
function ActionBarConfig.kind(kind: string, skill: string?): any
	local cfg = merge(ActionBarConfig.library.default, ActionBarConfig.kinds[kind])
	if skill and ActionBarConfig.skills[skill] then
		cfg = merge(cfg, ActionBarConfig.skills[skill])
	end
	return cfg
end

return ActionBarConfig
