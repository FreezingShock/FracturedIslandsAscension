--[[
	NotificationConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The NOTIFICATION CARDS: a stack in the bottom-left corner (StarterGui.FIANotifications, driven by NotificationController, built by
	tools/studio/build_notifications.luau from the Figma file "FIA Notifications"). Every card slides in from the left edge, stays
	`hold` seconds (a timer bar drains), then slides back out to the left. The server sends them (NotifyService, RemoteEvent "Notify");
	the client sends nothing.

	LAYERS, each overriding the one before (NotificationConfig.kind(kind, key) returns them merged):
	  1. library.default        shared by every card: maxVisible, hold, slide times, gap, margin, merge pop, sounds
	  2. kinds[<kind>]          "levelup" (skill level), "collection" (collection tier), "pickup" (items / stats / Coins), "system"
	  3. skills[<Skill>]        per skill (levelup): colour + icon (the SkillIconLabel image of the Skills menu)
	  4. items[<pickup key>]    per pickup key ("coins", "item:Oak Wood", "stat:Strength"): colour / icon / hold overrides

	TEXT: rich text. Value-type words (stats, items, Coins, attributes, counts) use Silkscreen via <font family=...>, roman numerals use
	Merriweather via <font face="Merriweather">, everything that has to be easy to read stays in the label's base font (Noto Sans Bold
	once uploaded; until then the tooltip body font rbxassetid://12187370747 on the template). Colours are Minecraft codes.
	Tokens (in braces): {skill} {SKILL} {name} {from} {to} (roman numerals, already wrapped in Merriweather) {amount} {label} {text} {sub}.

	MERGING: a pickup with the same key as a card that is still showing (or waiting in the queue) adds into it: "x8" counter, the timer
	restarts, the card pops. The amount is summed, the label stays ("+11 Rotten Flesh  x4" = four pickups).
	QUEUE: at most `maxVisible` cards show at once; the rest wait first-in-first-out, a kind with a higher `priority` jumps the queue.

	RECIPES
	  Hold longer:                 library.default.hold = 10   (or kinds.levelup.hold = 12 for one kind)
	  More cards:                  library.default.maxVisible = 7
	  Move the stack:              library.default.margin (px from the left) and bottomOffset (px up from the bottom, above the chat), at 1080p
	  New pickup colour / icon:    items["item:Oak Wood"] = { color = "#55FF55", icon = "rbxassetid://123" }
	  Sounds:                      kinds.levelup.sounds.show = { id = "rbxassetid://...", volume = 0.8, pitch = 1 }   ("" = silent)
	  New skill icon:              skills.Combat.icon = "rbxassetid://..."
	  Fainter / solid cards:       library.default.bodyTransparency / borderTransparency
]]

local NotificationConfig = {}

NotificationConfig.fonts = {
	value = "rbxassetid://12187371840", -- Silkscreen (values, stats, items, attributes, titles, counts)
	numeralFace = "Merriweather", -- roman numerals (Enum.Font name for rich text <font face>)
	valueScale = 0.8, -- Silkscreen is wide: values inside a line are drawn at this fraction of the label's text size
}

NotificationConfig.library = {
	default = {
		maxVisible = 5,
		hold = 7, -- seconds a card stays
		baseHeight = 1080, -- the screen height the pixel sizes are designed for (UIScale = screen height / baseHeight, clamped)
		minScale = 0.6,
		maxScale = 1.4,
		margin = 16, -- px from the left edge at baseHeight
		bottomOffset = 190, -- px from the bottom of the screen to the bottom of the stack (clears the chat box)
		gap = 6, -- px between cards
		slideIn = { time = 0.35, style = "Quint", direction = "Out" },
		slideOut = { time = 0.3, style = "Quint", direction = "In" },
		restack = { time = 0.25, style = "Quint", direction = "Out" }, -- the gap closing when a card leaves
		pop = { scale = 1.06, time = 0.2 }, -- the card pops when a pickup merges into it
		bodyTransparency = 0.45, -- the black body
		borderTransparency = 0.35, -- the 4px outer border
		timerBar = true,
		-- SOUNDS: { id, volume, pitch }; "" = silent until you have ids. show / hide default to the toast in / out sounds the drop tags use.
		sounds = {
			show = { id = "rbxassetid://105736529842995", volume = 0.35, pitch = 1.1 },
			hide = { id = "rbxassetid://119958057244626", volume = 0.25, pitch = 1.1 },
		},
	},
}

NotificationConfig.kinds = {
	-- SKILL LEVEL UP: heading "Combat V -> VI", REWARDS list
	levelup = {
		template = "CardLevelUp",
		priority = 3,
		hold = 9,
		title = { format = "SKILL LEVEL UP", color = "#FFD700" },
		heading = "{name} {from} <font color='#555555'>\u{2192}</font> {to}", -- old level gray, arrow dark gray, new level white
		fromColor = "#AAAAAA",
		toColor = "#FFFFFF",
		color = "#FFFFFF", -- header rule / bar colour when there is no skill colour
		rewardsTitle = { text = "REWARDS", color = "#55FF55" },
		maxRewardLines = 6,
		flavor = "The islands remember your strength.",
		sounds = {
			show = { id = "" }, -- silent: the action bar already plays the level-up fanfare
		},
	},
	-- COLLECTION TIER UP: heading "Rotten Flesh III -> IV"
	collection = {
		template = "CardCollection",
		priority = 3,
		hold = 9,
		title = { format = "COLLECTION TIER UP", color = "#55FFFF" },
		heading = "{name} {from} <font color='#555555'>\u{2192}</font> {to}",
		fromColor = "#AAAAAA",
		toColor = "#FFFFFF",
		color = "#55FFFF",
		rewardsTitle = { text = "REWARDS", color = "#55FF55" },
		maxRewardLines = 6,
		sounds = {
			show = { id = "rbxassetid://82373959251026", volume = 0.6, pitch = 1.15 },
		},
	},
	-- PICKUP: "+3 Rotten Flesh  x8"; amount and label are Silkscreen values
	pickup = {
		template = "CardPickup",
		priority = 1,
		format = "{amount} {label}",
		amountPrefix = "+",
		color = "#55FF55", -- the "+3"; the label is white unless the item has its own colour
		labelColor = "#FFFFFF",
		countColor = "#FFAA00",
		countFormat = "x{count}",
	},
	-- SYSTEM / WARNING: one or two readable lines
	system = {
		template = "CardSystem",
		priority = 2,
		color = "#FFFF55",
		subColor = "#AAAAAA",
	},
}

-- the SkillIconLabel image of each skill's page in the Skills menu, plus the colour the card takes
NotificationConfig.skills = {
	Farming = { color = "#FFAA00", icon = "rbxassetid://73164649896794" },
	Foraging = { color = "#00AA00", icon = "rbxassetid://109566880051710" },
	Fishing = { color = "#00AAAA", icon = "rbxassetid://100086264971667" },
	Mining = { color = "#5555FF", icon = "rbxassetid://72803832645303" },
	Combat = { color = "#FF5555", icon = "rbxassetid://138863912557343" },
	Carpentry = { color = "#55FF55", icon = "rbxassetid://77664234503756" },
}

-- per pickup key overrides: { color?, icon?, hold? }
NotificationConfig.items = {
	coins = { color = "#FFAA00" },
}

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

--- library.default < kinds[kind] < skills[key] (levelup / collection) or items[key] (pickup), merged.
function NotificationConfig.kind(kind: string, key: string?): any
	local cfg = merge(NotificationConfig.library.default, NotificationConfig.kinds[kind])
	if key then
		if kind == "pickup" and NotificationConfig.items[key] then
			cfg = merge(cfg, NotificationConfig.items[key])
		elseif kind == "levelup" and NotificationConfig.skills[key] then
			cfg = merge(cfg, NotificationConfig.skills[key])
		end
	end
	return cfg
end

return NotificationConfig
