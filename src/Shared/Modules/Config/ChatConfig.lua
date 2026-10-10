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

-- ===================== CHANNELS (minimal, for routing only) =====================
-- Channels are kept purely for template organization.
-- UI no longer shows tabs — all messages in one stream.
ChatConfig.Channels = {
	["all"] = {
		displayName = "All",
		headerColor = Color3.fromRGB(255, 255, 255),
	},
	["game"] = {
		displayName = "Game",
		headerColor = Color3.fromRGB(100, 210, 255),
	},
	["combat"] = {
		displayName = "Combat",
		headerColor = Color3.fromRGB(255, 100, 100),
	},
	["events"] = {
		displayName = "Events",
		headerColor = Color3.fromRGB(255, 210, 50),
	},
}

ChatConfig.DefaultChannel = "all"

-- ===================== TEMPLATES =====================
-- FIELDS:
--   channel     (string)  — which channel tab this appears in (no longer visible in UI)
--   lines       (array)   — message lines; "" = blank spacer
--   colors      (table)   — [lineIndex] = Color3
--   bold        (table)   — [lineIndex] = true
--   tokens      (table)   — documented token names for reference
--   sound       (string)  — optional SoundId played on client receipt
--   hideFromAll (bool)    — only show in own channel, not "All" tab (kept for logic)

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
		lines = { "  Equipped: {item}" },
		colors = { [1] = Color3.fromRGB(180, 180, 255) },
		tokens = { "item" },
	},

	-- ── Combat Events ─────────────────────────────────────────
	HIT_DEALT = {
		channel = "combat",
		lines = { "  Hit {enemy} for {damage}" },
		colors = { [1] = Color3.fromRGB(255, 160, 160) },
		tokens = { "enemy", "damage" },
	},
	CRIT_HIT = {
		channel = "combat",
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
-- The look itself (strokes, fonts, corners) is the Studio template ReplicatedStorage.GUI.FIAChatGui (tools/studio/build_chat_gui.luau);
-- these numbers are what the controller applies at runtime. Pixel sizes are for a 1080p screen and scale with the viewport.
ChatConfig.Visual = {
	-- Panel layout (bottom-left anchor)
	PanelWidth = 480, -- used until the HUD is found
	PanelHeight = 450,
	-- The width follows FIAHUD: the chat fills the gutter between the left margin and the HUD's left edge (never over the hotbar),
	-- clamped to MinWidth / MaxWidth. HudGap = px kept clear of the HUD. Set FollowHud = false for a fixed PanelWidth.
	FollowHud = true,
	HudGap = 16,
	MinWidth = 300,
	MaxWidth = 640,
	Margin = 16, -- px from the left / bottom edge
	BaseHeight = 1080,
	MinScale = 0.6,
	MaxScale = 1.4,
	InputBarHeight = 38,

	-- Fonts: readable text uses the tooltip body font in Bold (Noto Sans once uploaded: put its asset id here)
	ChatFont = Font.new("rbxassetid://12187370747", Enum.FontWeight.Bold),
	FontSize = 20,
	LineSpacing = 2,

	-- Transparency: both layers of the tooltip shell (4px outer border, black body). Idle = faint, active (focused / hovered) = solid.
	BorderIdleAlpha = 0.85,
	BorderActiveAlpha = 0.35,
	BodyIdleAlpha = 0.8,
	BodyActiveAlpha = 0.4,
	InputActiveStroke = Color3.fromHex("#FFFFFF"),
	InputIdleStroke = Color3.fromHex("#555555"),
	TransitionTime = 0.2,
	-- Animation (seconds): the whole chat sliding in / out when toggled with "/" or the topbar pill, a new line fading in, the log
	-- scrolling to the newest line, and the input stroke flaring when it gets focus.
	OpenTime = 0.4,
	CloseTime = 0.3,
	LineFadeTime = 0.25,
	ScrollTime = 0.2,
	FocusPulse = 4, -- px the input stroke flares to when focused (it settles back to 2)

	-- Colours (Minecraft palette)
	PlayerTextColor = Color3.fromHex("#EEEEEE"),
	TimestampColor = Color3.fromHex("#777777"),
	SystemNameColor = Color3.fromHex("#FFFF55"),
	NameColors = { "#FF5555", "#FFAA00", "#FFFF55", "#55FF55", "#55FFFF", "#5555FF", "#FF55FF", "#00AAAA" }, -- a player's name colour is picked from these by UserId
	SelfNameColor = nil, -- e.g. "#55FFFF" to give your own name a fixed colour

	StrokeTransparency = 0.45, -- the UIStroke of every line

	-- Top fade: the newest lines are solid; the top FadeTopFraction of the log fades from invisible at the top edge to solid.
	-- It is a UIGradient transparency on the log's CanvasGroup (FadeGroup in tools/studio/build_chat_gui.luau), so it fades children.
	FadeTopFraction = 0.3,

	-- Level badge: each player line starts with the nameplate's LevelBadge (cloned from GUI.EnemyNameplate). Its text is scaled
	-- so "LV n" sits at the chat's FontSize (the nameplate name is the reference size); BadgeGap = px between badge and name.
	BadgeGap = 6,
	-- The tint row a chat badge uses comes from NameplateConfig.kinds.player.badge (the same row players get on their plate).

	-- Scroll: a thin scrollbar that stays visible, and the wheel step in px (desktop wheel is handled by ChatController)
	ScrollBarThickness = 6,
	WheelStep = 60,
	AutoScrollThreshold = 20,
}

-- ===================== BUBBLE CONFIG (the chat bubble over a player's nameplate) =====================
-- The look (pill, stroke, tail, text colour) is the Studio template ReplicatedStorage.GUI.EnemyNameplate_Bubble (+ _BubbleStack),
-- built by tools/studio/build_chat_bubble.luau. These numbers are what ChatBubble applies at runtime.
-- Layering: this table, then NameplateConfig.kinds.<kind>.bubble for that kind ("player" for others, "self" for you).
--   Lifetime / FadeSeconds: a bubble fades out over its last FadeSeconds, then is removed at Lifetime.
--   MaxBubbles: a player shows up to this many at once; an older one fades early when a new one arrives over the cap.
--   MaxWidth: the bubble wraps its text at this many px. Gap: px between the bubbles and the top of the nameplate's Stack.
ChatConfig.Bubble = {
	MaxBubbles = 3,
	Lifetime = 6,
	FadeSeconds = 1,
	TextSize = 16,
	MaxWidth = 260,
	Gap = 8,
}

-- ===================== BEHAVIOUR CONFIG =====================
ChatConfig.Behaviour = {
	MaxHistory = 120,
	MaxMessageLength = 200,
	SendRateLimit = 1.5, -- seconds between player messages (server enforced)
	ShowTimestamps = false,
	ShowJoinLeave = true,
	SendHistory = 30, -- sent messages you can recall with Up / Down
	-- server notices that only add noise (TextChatService "Roblox automatically translates ...")
	HideNoticePatterns = { "automatically translates" },
	TooFastNotice = "You are chatting too fast.",
}

-- Admin ids live in Modules/AdminConfig.

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
