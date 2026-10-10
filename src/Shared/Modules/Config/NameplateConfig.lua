--[[
	NameplateConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	Every number, colour and tag of the enemy nameplate (EnemyNameplateController clones ReplicatedStorage.GUI.EnemyNameplate
	for every "Enemy" model; the look of the template is hand-restylable in Studio, the behaviour lives here).

	TEMPLATE NAMES the controller looks up (anywhere under the BillboardGui):
	  Title > NameLabel, LevelBadge > LevelLabel      rise + fade in
	  BarGroup > Bar > Track > Ghost, Fill, HpLabel   the bar scales in; Fill drops fast, Ghost trails it
	  Tags (CanvasGroup)                              row under the name; one pill per kind (GUI.EnemyNameplate_TagGroup) holds that kind's chips
	  Tag chip (GUI.EnemyNameplate_Tag, has a Scale UIScale): Icon > Glyph (placeholder letter) / IconImage, Count (stacks / seconds)

	RECIPES
	  New tag (element, debuff, effect): add tags.<id> = { kind, name, color, glyph, icon = "" } below.
	      icon = "rbxassetid://..." shows the image; with no icon the glyph letter is shown on a colour tile (placeholder).
	  Permanent tag on an enemy:         EnemyConfig.enemies.<key>.tags = { "fire" }
	  Debuff / active effect at runtime: EnemyTags.add(model, "burn", { duration = 5, stacks = 1 })   (server)
	                                     EnemyTags.remove(model, "burn")
	  Retune a distance / tween:         edit show / intro / hp / tagsCfg below.
--]]

local NameplateConfig = {}

-- ===================== VISIBILITY =====================
NameplateConfig.show = {
	nameDistance = 40, -- studs: name + level fade in inside this
	barDistance = 40, -- studs: the bar shows inside this, only while the enemy is below max health
	tagDistance = 18, -- studs: the tag row animates in inside this (chips pop in one by one) and out again past it
	fullHideDelay = 1.5, -- seconds the bar stays after the enemy is back at full health, then it closes again
	fadeSeconds = 0.25,
	checkInterval = 0.1, -- seconds between distance checks (one shared loop for every plate)
	hysteresis = 2, -- studs of slack before a shown part hides again (no flicker at the edge)
	heightOffset = 2.2, -- studs above the head (the template StudsOffsetWorldSpace is set from this)
}

-- ===================== APPEAR / TWEENS =====================
NameplateConfig.intro = {
	nameRise = 8, -- pixels the name + badge slide up while fading in
	nameSeconds = 0.35,
	barSeconds = 0.45, -- the bar opens between the name and the tags (its slot grows from 0) and scales from barStartScale to 1
	barCloseSeconds = 0.3,
	barStartScale = 0.6,
	tagSeconds = 0.25,
	tagStartScale = 0.4,
	tagRise = 8, -- pixels the row slides up while it appears
	tagStagger = 0.05, -- seconds between each chip popping in
	tagHideSeconds = 0.15,
	hideSeconds = 0.2,
}

NameplateConfig.hp = {
	fillSeconds = 0.12, -- Fill drops fast
	healSeconds = 0.2,
	ghostDelay = 0.35, -- the trail waits, then follows
	ghostSeconds = 0.5,
	countSeconds = 0.25, -- the HP number counts toward the new value
	-- HP number: 1,234 -> "1234", 36,500 -> "36.5K", 1,250,000 -> "1.2M"
	units = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } },
	showMax = true, -- "15.3K/36.5K" (false = only the current value)
}

-- Death (the glitch, the shards, the timing) is Modules/Config/DeathConfig.hud.

-- ===================== LEVEL BADGE =====================
-- tint = enemy level - the player's Combat level; the first row whose `upTo` is >= the difference wins.
-- top / bottom = badge gradient, stroke = border, text = level colour
NameplateConfig.levelTints = {
	{ upTo = -8, name = "trivial", top = "#8B8B8E", bottom = "#5A5A5E", stroke = "#2A2A2D", text = "#FFFFFF" },
	{ upTo = -3, name = "easy", top = "#4E8F4E", bottom = "#2C5E2C", stroke = "#142B14", text = "#FFFFFF" },
	{ upTo = 2, name = "even", top = "#A8941F", bottom = "#6A5A0C", stroke = "#2E2808", text = "#FFFFFF" },
	{ upTo = math.huge, name = "dangerous", top = "#B64A4A", bottom = "#7A2222", stroke = "#2E0C0C", text = "#FFFFFF" },
}
NameplateConfig.tintSeconds = 0.2

-- ===================== TAG ROW =====================
NameplateConfig.tagsCfg = {
	maxVisible = 6, -- further tags are hidden
	-- left to right: elements first, then active effects, then debuffs
	kindOrder = { element = 1, effect = 2, debuff = 3 },
	lowTimeSeconds = 3, -- the timer text turns lowTimeColor under this
	lowTimeColor = "#FF5555",
	timerStep = 0.25, -- seconds between timer text refreshes
}

-- outline of each kind's pill (top -> bottom gradient: lighter on top)
NameplateConfig.tagKinds = {
	element = { top = "#9BFF9B", bottom = "#38C238" },
	effect = { top = "#9A9AFF", bottom = "#4646E0" },
	debuff = { top = "#FF9A9A", bottom = "#D03C3C" },
}

-- kind = element | effect | debuff. color = tile colour shown only while icon is "" (glyph = its placeholder letter).
-- Icons: assets/tag_icons/<id>.png, drawn by tools/gen_tag_icons.py (ids in assets/tag_icons/ids.json).
NameplateConfig.tags = {
	-- elements (permanent, from EnemyConfig.enemies.<key>.tags)
	fire = { kind = "element", name = "Fire", color = "#FF8A2A", glyph = "F", icon = "rbxassetid://102117766495412" },
	ice = { kind = "element", name = "Ice", color = "#7FE3FF", glyph = "I", icon = "rbxassetid://129287916714928" },
	earth = { kind = "element", name = "Earth", color = "#A7824F", glyph = "E", icon = "rbxassetid://132840379929150" },
	storm = { kind = "element", name = "Storm", color = "#C9A8FF", glyph = "S", icon = "rbxassetid://99696933054046" },
	nature = { kind = "element", name = "Nature", color = "#3FBF4A", glyph = "N", icon = "rbxassetid://97187782220297" },
	-- debuffs (EnemyTags.add, a duration and a stack count)
	burn = { kind = "debuff", name = "Burn", color = "#FF5530", glyph = "B", icon = "rbxassetid://118952046941037" },
	slow = { kind = "debuff", name = "Slow", color = "#8FB4FF", glyph = "S", icon = "rbxassetid://87561563126080" },
	poison = { kind = "debuff", name = "Poison", color = "#6BDB4A", glyph = "P", icon = "rbxassetid://137492234467042" },
	bleed = { kind = "debuff", name = "Bleed", color = "#C21E3A", glyph = "L", icon = "rbxassetid://91561574594671" },
	-- active effects
	shield = { kind = "effect", name = "Shield", color = "#FFD24A", glyph = "D", icon = "rbxassetid://103820293560489" },
	enrage = { kind = "effect", name = "Enrage", color = "#FF4C6A", glyph = "E", icon = "rbxassetid://84757432578478" },
	regen = { kind = "effect", name = "Regen", color = "#55FF99", glyph = "R", icon = "rbxassetid://97225490143648" },
	power = { kind = "effect", name = "Power", color = "#E8EEF5", glyph = "W", icon = "rbxassetid://118056444083285" },
	empower = { kind = "effect", name = "Empower", color = "#FFD24A", glyph = "M", icon = "rbxassetid://109814746839733" },
}

-- ===================== KINDS AND TYPES (layered overrides) =====================
--[[
	NameplateConfig.resolve(kind, typeId) -> { show, intro, hp, cameraModes?, badge? } for one plate.
	Layers, later ones win per field:  the shared defaults above  ->  kinds[kind]  ->  types[typeId]
	  kind   = "enemy" | "npc" | "player" | "self"   (the controller decides it from who owns the model)
	  typeId = the EnemyConfig key of an enemy / NPC (nil for players)
	Recipes:
	  Change every plate:            edit show / intro / hp above (enemies, NPCs and players all follow)
	  New player or self look:       kinds.player / kinds.self  (e.g. badge = { top, bottom, stroke, text })
	  Look for one enemy or NPC:     types.<EnemyConfig key> = { show = { heightOffset = 3 } }
	  Self plate visibility:         kinds.self.cameraModes (CameraController phases: "first" | "shoulder" | "free")
	  badge: a fixed level badge tint (no combat-level compare); without it the badge uses tintFor (the levelTints above).
--]]

NameplateConfig.kinds = {
	enemy = {},
	npc = {}, -- hostile / passive NPCs: no passive flag in EnemyConfig yet, so nothing classifies as npc today
	player = {
		badge = { top = "#55FFFF", bottom = "#2A8C8C", stroke = "#0E3A3A", text = "#FFFFFF" }, -- Nexus level badge, not compared to combat level
		bubble = {}, -- chat bubble overrides for other players (fields of ChatConfig.Bubble, e.g. { Lifetime = 4 })
	},
	self = {
		cameraModes = { free = true }, -- the plate shows only in these camera phases: third-person free orbit, never first person
		badge = { top = "#55FFFF", bottom = "#2A8C8C", stroke = "#0E3A3A", text = "#FFFFFF" },
		bubble = {}, -- chat bubble overrides for your own bubble (fields of ChatConfig.Bubble)
	},
}

NameplateConfig.types = {}

local SECTIONS = { "show", "intro", "hp" }

function NameplateConfig.resolve(kind: string, typeId: string?): any
	local out: any = { show = {}, intro = {}, hp = {} }
	local sources = { NameplateConfig, NameplateConfig.kinds[kind] or {}, NameplateConfig.types[typeId or ""] or {} }
	for _, source in ipairs(sources) do
		for _, section in ipairs(SECTIONS) do
			for key, value in pairs(source[section] or {}) do
				out[section][key] = value
			end
		end
		out.cameraModes = source.cameraModes or out.cameraModes
		out.badge = source.badge or out.badge
	end
	return out
end

return NameplateConfig
