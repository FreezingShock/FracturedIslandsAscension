--[[
	ButtonConfig (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Shared configuration for the world-button purchase system.
	Both ButtonServerManager (server) and ButtonClientManager (client)
	require this module.

	Naming convention in workspace:
	  Buttons (Folder)
	    Button.{ConfigKey}.{Tier} (Model)
	      Top        — the part the player stands on (Anchored)
	      Hitbox     — optional larger invisible part for touch detection
	      Border     — decorative
	      Base       — decorative
	      Bottom     — decorative
	      BillboardGui (on Top or a child part)
	        UIListLayout
	        GainedAmount > GainedAmountLabel
	        SubtractedAmount > SubtractedAmountLabel
	        Arrow
	        BuyProperty

	Adding a new button type:
	  1. Add an entry to BUTTONS below
	  2. Place the model in workspace.Buttons with matching name
	  3. Done — server and client wire automatically
--]]

local ButtonConfig = {}

-- ===================== BUTTON DEFINITIONS =====================
--- Each key matches the middle segment of the model name: Button.{KEY}.{Tier}
---
--- Fields:
---   skill    : skill key in StatisticsConfig.STAT_CHAINS (e.g. "General", "Farming")
---   statKey  : stat key within that skill chain (e.g. "SilverCoins", "Seeds")
---   tiers    : [tierNumber] → { baseGain, cost, interval? }
---     baseGain : flat amount gained BEFORE multiplier
---     cost     : array of { skill, id, amount } — same shape as STAT_CHAINS cost
---     interval : seconds between auto-purchases (default 0.2 = 5/sec)

ButtonConfig.BUTTONS = {
	-- ═══════════════════ GENERAL CURRENCY ═══════════════════
	SilverCoins = {
		skill = "General",
		statKey = "SilverCoins",
		tiers = {
			[1] = {
				baseGain = 1,
				cost = { { skill = "General", id = "BronzeCoins", amount = 100 } },
				interval = 0.2,
			},
			[2] = {
				baseGain = 20,
				cost = { { skill = "General", id = "BronzeCoins", amount = 20000 } },
				interval = 0.2,
			},
			[3] = {
				baseGain = 75,
				cost = { { skill = "General", id = "BronzeCoins", amount = 75000 } },
				interval = 0.2,
			},
			[4] = {
				baseGain = 250,
				cost = { { skill = "General", id = "BronzeCoins", amount = 200000 } },
				interval = 0.2,
			},
			[5] = {
				baseGain = 750,
				cost = { { skill = "General", id = "BronzeCoins", amount = 1000000 } },
				interval = 0.2,
			},
			[6] = {
				baseGain = 2500,
				cost = { { skill = "General", id = "BronzeCoins", amount = 2500000 } },
				interval = 0.2,
			},
		},
	},

	GoldCoins = {
		skill = "General",
		statKey = "GoldCoins",
		tiers = {
			[1] = {
				baseGain = 1,
				cost = { { skill = "General", id = "SilverCoins", amount = 100 } },
				interval = 0.2,
			},
			[2] = {
				baseGain = 20,
				cost = { { skill = "General", id = "SilverCoins", amount = 20000 } },
				interval = 0.2,
			},
			[3] = {
				baseGain = 75,
				cost = { { skill = "General", id = "SilverCoins", amount = 75000 } },
				interval = 0.2,
			},
			[4] = {
				baseGain = 250,
				cost = { { skill = "General", id = "SilverCoins", amount = 200000 } },
				interval = 0.2,
			},
			[5] = {
				baseGain = 750,
				cost = { { skill = "General", id = "SilverCoins", amount = 1000000 } },
				interval = 0.2,
			},
			[6] = {
				baseGain = 2500,
				cost = { { skill = "General", id = "SilverCoins", amount = 2500000 } },
				interval = 0.2,
			},
		},
	},

	PlatinumCoins = {
		skill = "General",
		statKey = "PlatinumCoins",
		tiers = {
			[1] = {
				baseGain = 1,
				cost = { { skill = "General", id = "GoldCoins", amount = 100 } },
				interval = 0.2,
			},
			[2] = {
				baseGain = 20,
				cost = { { skill = "General", id = "GoldCoins", amount = 20000 } },
				interval = 0.2,
			},
			[3] = {
				baseGain = 75,
				cost = { { skill = "General", id = "GoldCoins", amount = 75000 } },
				interval = 0.2,
			},
			[4] = {
				baseGain = 250,
				cost = { { skill = "General", id = "GoldCoins", amount = 200000 } },
				interval = 0.2,
			},
			[5] = {
				baseGain = 750,
				cost = { { skill = "General", id = "GoldCoins", amount = 1000000 } },
				interval = 0.2,
			},
			[6] = {
				baseGain = 2500,
				cost = { { skill = "General", id = "GoldCoins", amount = 2500000 } },
				interval = 0.2,
			},
		},
	},

	DiamondCoins = {
		skill = "General",
		statKey = "DiamondCoins",
		tiers = {
			[1] = {
				baseGain = 1,
				cost = { { skill = "General", id = "PlatinumCoins", amount = 100 } },
				interval = 0.2,
			},
		},
	},

	EmeraldCoins = {
		skill = "General",
		statKey = "EmeraldCoins",
		tiers = {
			[1] = {
				baseGain = 1,
				cost = { { skill = "General", id = "DiamondCoins", amount = 100 } },
				interval = 0.2,
			},
		},
	},
	-- Add more as needed — same pattern.
}

-- ===================== DEFAULTS =====================
ButtonConfig.DEFAULT_INTERVAL = 0.3 -- 5 purchases/sec
ButtonConfig.PRESS_DEPTH = 0.12 -- studs Top moves down on press
ButtonConfig.TWEEN_DOWN = 0.15 -- seconds for press-down tween
ButtonConfig.TWEEN_UP = 0.15 -- seconds for release-up tween
ButtonConfig.GRACE_PERIOD = 0.3 -- seconds after TouchEnded before stopping loop

-- ===================== BUTTONS FOLDER =====================
ButtonConfig.BUTTONS_FOLDER = "Buttons" -- name of the folder in workspace

print("ButtonConfig: Loaded ✓")
return ButtonConfig
