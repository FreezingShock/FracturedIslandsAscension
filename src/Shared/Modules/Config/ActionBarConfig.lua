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
	  Quieter / other sounds:    library.default.sounds.xp = { volume = 0.3 }   (or another id)
	  No XP particles:           library.default.fx.enabled = false   (the look is EnemyConfig.fx.xp_gain / xp_levelup / xp_levelup_wave)
	  Bigger entrance:           library.default.intro = { rise = 28, scale = 0.7 }   (any key you leave out keeps its value)
	  Another colour for gains:  kinds.xp.pieces.gain.color = "#55FFFF"
	  Combat level text red:     skills.Combat = { levelColor = "#FF5555" }
	  New message from code:     ActionBarService.show(player, "<font color='#55FF55'>Saved!</font>", { hold = 3 })
]]

local ActionBarConfig = {}

ActionBarConfig.library = {
	default = {
		hold = 5, -- seconds a message stays after it finished typing / was last updated
		-- the entrance: the line fades in while it springs up into place (Back easing overshoots a little), grows from `scale`
		-- to full size, and its outline flares to `strokePulse` px before settling back
		intro = { time = 0.5, fade = 0.3, rise = 18, scale = 0.86, style = "Back", strokePulse = 4 },
		fadeOut = 0.4,
		sink = 6, -- px it sinks while fading out
		typeSpeed = 70, -- characters per second of the typewriter (about 0.4s for a normal XP line)
		replaceFade = 0.15, -- seconds the old line takes to fade before a different skill's line types in
		pop = { scale = 1.14, time = 0.2 }, -- the number pop when a stacked gain arrives
		pctTween = 0.25, -- seconds the % takes to move to its new value
		-- FX at the player's centre (EnemyConfig.fx presets, played through EnemyFX): a small green burst when XP arrives, a grand
		-- one on EVERY level tick (the level number ticking up), followed a beat later by a wide second wave. Skipped in first person
		-- (player attribute CameraMode == "first", set by CameraController) so nothing covers the view.
		fx = {
			enabled = true,
			hideInFirstPerson = true,
			gain = { preset = "xp_gain", minGap = 0.3, lift = 0.4 }, -- lift = studs above the character's centre
			levelup = { preset = "xp_levelup", wave = "xp_levelup_wave", waveDelay = 0.16, lift = 0.3 },
		},
		-- SOUNDS. One Sound per slot is reused, so a new play CUTS the old one (sounds never pile up), and minGap drops requests
		-- that come too soon. xp = XP appearing / stacking (its pitch climbs a little with each consecutive gain, resets after
		-- ladderReset seconds); levelup = the level number ticking up; ticker = the extra blips when SEVERAL levels tick at once
		-- (the xp sound, pitched up one step per level); tick = typewriter characters. "" = silent.
		sounds = {
			xp = { id = "rbxassetid://106742416285496", volume = 0.55, pitch = 1, minGap = 0.45, ladderStep = 0.045, ladderMax = 1.35, ladderReset = 2.5 },
			levelup = { id = "rbxassetid://82373959251026", volume = 0.85, pitch = 1, minGap = 1 },
			ticker = { id = "rbxassetid://106742416285496", volume = 0.45, pitch = 1.15, minGap = 0.1, ladderStep = 0.12, ladderMax = 1.9 },
			tick = { id = "", volume = 0.25, pitch = 1.6 },
			duckXp = 1.1, -- seconds after the level-up sound starts in which stacked XP stays quiet (the fanfare owns the moment)
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
	-- "+100 Combat XP - 100.0% - Combat Level 5", a couple of seconds at 100%, then the % drops to 0, the level TICKS UP
	-- (5 -> 6) and the % climbs to where you really are: "+250 Combat XP - 25.0% - Combat Level 6", then CONGRATULATIONS.
	-- More XP keeps stacking into the line the whole time.
	levelup = {
		hold = 3,
		levelColor = "skill", -- colour of "Combat Level 5" ("skill" = the skill's colour)
		levelFormat = "{skill} Level {level}",
		levelTypeSpeed = 22, -- the level text types in this slowly when it first appears
		tickDelay = 2, -- seconds the line rests at 100% before the level ticks up
		dropTime = 0.3, -- the % running down to 0
		tickStep = 0.28, -- seconds per level while the number ticks up (several levels at once tick one by one)
		tickPop = 1.18, -- the level text pops by this scale on every tick
		fillTime = 0.6, -- the % climbing to the real progress in the new level
		-- "! CONGRATULATIONS !" types in, then the marks grow on BOTH sides: !! -> !!! (each step pops and flashes the outline)
		congrats = {
			text = "CONGRATULATIONS",
			color = "#FFFF55", -- yellow
			bold = true,
			marks = { char = "!", color = "#55FFFF", bold = true, steps = { 1, 2, 3 }, stepTime = 0.22, gap = " ", pop = 1.16 },
			flash = "#FFFFFF", -- the outline flashes this colour when it lands and on every step
			flashTime = 0.45,
			typeSpeed = 30,
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
