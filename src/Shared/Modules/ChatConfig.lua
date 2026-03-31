-- ============================================================
--  ChatConfig (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Single source of truth for the entire custom chat system.
--  ChatService (server), ChatController (client), and
--  ChatBridge (client bridge) all require this.
--
--  To add a new system message type:
--    1. Add an entry to Templates{}
--    2. Call ChatService.FireSystemMessage(key, tokens, player?)
--       from the server, or ChatBridge.postLocal(key, tokens) client-side.
--  No other files need to change.
-- ============================================================

local ChatConfig = {}

-- ===================== CHANNELS =====================
ChatConfig.Channels = {
	["all"] = {
		displayName = "All",
		tabColor = Color3.fromRGB(220, 220, 220),
		headerColor = Color3.fromRGB(255, 255, 255),
	},
	["game"] = {
		displayName = "Game",
		tabColor = Color3.fromRGB(100, 210, 255),
		headerColor = Color3.fromRGB(100, 210, 255),
	},
	["combat"] = {
		displayName = "Combat",
		tabColor = Color3.fromRGB(255, 100, 100),
		headerColor = Color3.fromRGB(255, 100, 100),
	},
	["events"] = {
		displayName = "Events",
		tabColor = Color3.fromRGB(255, 210, 50),
		headerColor = Color3.fromRGB(255, 210, 50),
	},
}

ChatConfig.ChannelOrder = { "all", "game", "combat", "events" }
ChatConfig.DefaultChannel = "all"

-- ===================== TEMPLATES =====================
-- FIELDS:
--   channel     (string)  — which channel tab this appears in
--   lines       (array)   — message lines; "" = blank spacer
--   colors      (table)   — [lineIndex] = Color3
--   bold        (table)   — [lineIndex] = true
--   tokens      (table)   — documented token names for reference
--   sound       (string)  — optional SoundId played on client receipt
--   hideFromAll (bool)    — only show in own channel, not "All" tab

ChatConfig.Templates = {

	-- ── Player Lifecycle ──────────────────────────────────────
	PLAYER_JOIN = {
		channel = "game",
		lines = { "→ {player} has arrived on the islands." },
		colors = { [1] = Color3.fromRGB(100, 255, 150) },
		tokens = { "player" },
	},
	PLAYER_LEAVE = {
		channel = "game",
		lines = { "← {player} has left the islands." },
		colors = { [1] = Color3.fromRGB(180, 180, 180) },
		tokens = { "player" },
	},

	-- ── Skill Events ──────────────────────────────────────────
	SKILL_XP = {
		channel = "game",
		hideFromAll = true,
		lines = { "  +{xp} {skill} XP" },
		colors = { [1] = Color3.fromRGB(170, 255, 170) },
		tokens = { "xp", "skill" },
	},
	LEVEL_UP = {
		channel = "events",
		lines = {
			"",
			"  ✦ SKILL LEVEL UP ✦",
			"  {skill} reached Level {level}  ({romanLevel})",
			"",
		},
		colors = {
			[2] = Color3.fromRGB(255, 215, 0),
			[3] = Color3.fromRGB(100, 220, 255),
		},
		bold = { [2] = true },
		tokens = { "skill", "level", "romanLevel" },
	},
	SKILL_MILESTONE = {
		channel = "events",
		lines = {
			"",
			"  ★ MILESTONE UNLOCKED",
			"  {skill} Level {level}: {item}",
			"",
		},
		colors = {
			[2] = Color3.fromRGB(255, 180, 50),
			[3] = Color3.fromRGB(255, 240, 150),
		},
		bold = { [2] = true },
		tokens = { "skill", "level", "item" },
	},

	-- ── Button / Clicking Events ──────────────────────────────
	BUTTON_PRESS = {
		channel = "game",
		hideFromAll = true,
		lines = { "  +{amount} {skill} XP" },
		colors = { [1] = Color3.fromRGB(180, 255, 180) },
		tokens = { "amount", "skill" },
	},
	BUTTON_UPGRADE = {
		channel = "game",
		lines = {
			"  Button upgraded!",
			"  {item}  (Tier {level})",
		},
		colors = {
			[1] = Color3.fromRGB(255, 255, 255),
			[2] = Color3.fromRGB(100, 210, 255),
		},
		tokens = { "item", "level" },
	},

	-- ── Item & Drop Events ────────────────────────────────────
	ITEM_DROP = {
		channel = "game",
		lines = { "  ✦ {rarity} {item} dropped!" },
		colors = { [1] = Color3.fromRGB(255, 215, 0) },
		tokens = { "rarity", "item" },
	},
	ITEM_EQUIP = {
		channel = "game",
		hideFromAll = true,
		lines = { "  Equipped: {item}" },
		colors = { [1] = Color3.fromRGB(180, 180, 255) },
		tokens = { "item" },
	},

	-- ── Combat Events ─────────────────────────────────────────
	HIT_DEALT = {
		channel = "combat",
		hideFromAll = true,
		lines = { "  Hit {enemy} for {damage}" },
		colors = { [1] = Color3.fromRGB(255, 160, 160) },
		tokens = { "enemy", "damage" },
	},
	CRIT_HIT = {
		channel = "combat",
		hideFromAll = true,
		lines = { "  ⚔ CRIT  {enemy}  {damage}!" },
		colors = { [1] = Color3.fromRGB(255, 80, 80) },
		bold = { [1] = true },
		tokens = { "enemy", "damage" },
	},
	ENEMY_KILL = {
		channel = "combat",
		lines = { "  ✗ {enemy} defeated." },
		colors = { [1] = Color3.fromRGB(220, 100, 100) },
		tokens = { "enemy" },
	},

	-- ── World / Time Events ───────────────────────────────────
	DAY_CHANGE = {
		channel = "events",
		lines = { "", "  ☀  Day {day} has begun.", "" },
		colors = { [2] = Color3.fromRGB(255, 230, 100) },
		tokens = { "day" },
	},
	NIGHT_CHANGE = {
		channel = "events",
		lines = { "", "  ☽  Night {day} falls.", "" },
		colors = { [2] = Color3.fromRGB(150, 160, 255) },
		tokens = { "day" },
	},
	REGION_ENTER = {
		channel = "game",
		lines = { "  Entered: {region}" },
		colors = { [1] = Color3.fromRGB(140, 220, 255) },
		tokens = { "region" },
	},

	-- ── Expedition Results ────────────────────────────────────
	EXPEDITION_COMPLETE = {
		channel = "events",
		lines = {
			"",
			"  ══ EXPEDITION COMPLETE ══",
			"  Score: {score}  ({grade})",
			"  Time: {time}",
			"  +{xp} {skill} XP",
			"",
		},
		colors = {
			[2] = Color3.fromRGB(255, 215, 0),
			[3] = Color3.fromRGB(100, 255, 100),
			[4] = Color3.fromRGB(180, 180, 180),
			[5] = Color3.fromRGB(170, 255, 170),
		},
		bold = { [2] = true },
		tokens = { "score", "grade", "time", "xp", "skill" },
	},

	-- ── Admin / System ────────────────────────────────────────
	ADMIN_MESSAGE = {
		channel = "all",
		lines = { "  [ADMIN] {player}: {item}" },
		colors = { [1] = Color3.fromRGB(255, 80, 80) },
		bold = { [1] = true },
		tokens = { "player", "item" },
	},
	SERVER_NOTICE = {
		channel = "all",
		lines = { "", "  ⚑ {item}", "" },
		colors = { [2] = Color3.fromRGB(255, 100, 100) },
		bold = { [2] = true },
		tokens = { "item" },
	},
}

-- ===================== VISUAL CONFIG =====================
ChatConfig.Visual = {
	-- Panel layout (bottom-left anchor)
	PanelWidth = 480,
	LogHeight = 200,
	InputBarHeight = 38,
	TabBarHeight = 26,
	PanelOffsetX = 8,
	PanelOffsetY = 8,

	-- Fonts
	ChatFont = Font.new("rbxassetid://11598121416"),
	FontSize = 16,
	LineSpacing = 2,

	-- Colors
	PanelBackground = Color3.fromRGB(0, 0, 0),
	PanelBackgroundAlpha = 0.85, -- unfocused (more transparent)
	PanelFocusedAlpha = 0.40, -- focused / hovered (more opaque)
	InputBackground = Color3.fromRGB(0, 0, 0),
	InputBackgroundAlpha = 0.55,
	TabActiveColor = Color3.fromRGB(255, 255, 255),
	TabInactiveColor = Color3.fromRGB(120, 120, 120),
	PlayerNameColor = Color3.fromRGB(255, 255, 255),
	PlayerTextColor = Color3.fromRGB(220, 220, 220),
	TimestampColor = Color3.fromRGB(100, 100, 100),
	ScrollBarColor = Color3.fromRGB(80, 80, 80),
	TransitionTime = 0.2,

	-- Message fade (only when panel is NOT focused/hovered)
	FadeStartAge = 10, -- seconds before fade begins
	FadeEndAge = 14, -- fully transparent at this age

	-- Scroll
	AutoScrollThreshold = 20,
	NewMessageButtonText = "↓ New messages",
}

-- ===================== BEHAVIOUR CONFIG =====================
ChatConfig.Behaviour = {
	MaxHistory = 120,
	MaxMessageLength = 200,
	SendRateLimit = 1.5, -- seconds between player messages (server enforced)
	ShowTimestamps = false,
	ShowJoinLeave = true,
}

-- ===================== ADMIN CONFIG =====================
ChatConfig.AdminIds = { 288851273 }

-- ===================== RARITY COLORS =====================
ChatConfig.RarityColors = {
	[0] = Color3.fromRGB(170, 170, 170),
	[1] = Color3.fromRGB(85, 255, 85),
	[2] = Color3.fromRGB(85, 85, 255),
	[3] = Color3.fromRGB(255, 85, 255),
	[4] = Color3.fromRGB(255, 170, 0),
	[5] = Color3.fromRGB(255, 85, 85),
}

ChatConfig.RarityNames = {
	[0] = "Common",
	[1] = "Uncommon",
	[2] = "Rare",
	[3] = "Epic",
	[4] = "Legendary",
	[5] = "Mythic",
}

return ChatConfig
