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
	barDistance = 25, -- studs: the bar is shown inside this, or inside nameDistance once the enemy is damaged
	tagDistance = 25, -- studs: the tag row follows the bar
	fadeSeconds = 0.25,
	checkInterval = 0.1, -- seconds between distance checks (one shared loop for every plate)
	hysteresis = 2, -- studs of slack before a shown part hides again (no flicker at the edge)
	heightOffset = 2.2, -- studs above the head (the template StudsOffsetWorldSpace is set from this)
}

-- ===================== APPEAR / TWEENS =====================
NameplateConfig.intro = {
	nameRise = 8, -- pixels the name + badge slide up while fading in
	nameSeconds = 0.35,
	barSeconds = 0.4, -- the bar scales from barStartScale to 1
	barStartScale = 0.55,
	tagSeconds = 0.25,
	tagStartScale = 0.4,
	hideSeconds = 0.2,
}

NameplateConfig.hp = {
	fillSeconds = 0.12, -- Fill drops fast
	healSeconds = 0.2,
	ghostDelay = 0.35, -- the trail waits, then follows
	ghostSeconds = 0.5,
	countSeconds = 0.25, -- the HP number counts toward the new value
	deathFadeSeconds = 0.3,
	-- HP number: 1,234 -> "1234", 36,500 -> "36.5K", 1,250,000 -> "1.2M"
	units = { { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } },
	showMax = false, -- true = "15.3K/36.5K"
}

-- ===================== LEVEL BADGE =====================
-- tint = enemy level - the player's Combat level; the first row whose `upTo` is >= the difference wins.
-- top / bottom = badge gradient, stroke = border, text = level colour
NameplateConfig.levelTints = {
	{ upTo = -8, name = "trivial", top = "#8B8B8E", bottom = "#5A5A5E", stroke = "#2A2A2D", text = "#FFFFFF" },
	{ upTo = -3, name = "easy", top = "#4E8F4E", bottom = "#2C5E2C", stroke = "#142B14", text = "#E8FFE8" },
	{ upTo = 2, name = "even", top = "#B9A93A", bottom = "#7C6F1C", stroke = "#2E2808", text = "#FFFFE0" },
	{ upTo = math.huge, name = "dangerous", top = "#B64A4A", bottom = "#7A2222", stroke = "#2E0C0C", text = "#FFE8E8" },
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

-- kind = element | effect | debuff. color = chip border / placeholder tile. glyph = placeholder letter (until icon is set)
NameplateConfig.tags = {
	-- elements (permanent, from EnemyConfig.enemies.<key>.tags)
	fire = { kind = "element", name = "Fire", color = "#FF8A2A", glyph = "F", icon = "" },
	ice = { kind = "element", name = "Ice", color = "#7FE3FF", glyph = "I", icon = "" },
	earth = { kind = "element", name = "Earth", color = "#A7824F", glyph = "E", icon = "" },
	storm = { kind = "element", name = "Storm", color = "#C9A8FF", glyph = "S", icon = "" },
	-- debuffs (EnemyTags.add, a duration and a stack count)
	burn = { kind = "debuff", name = "Burn", color = "#FF5530", glyph = "B", icon = "" },
	slow = { kind = "debuff", name = "Slow", color = "#8FB4FF", glyph = "S", icon = "" },
	poison = { kind = "debuff", name = "Poison", color = "#6BDB4A", glyph = "P", icon = "" },
	bleed = { kind = "debuff", name = "Bleed", color = "#C21E3A", glyph = "L", icon = "" },
	-- active effects
	shield = { kind = "effect", name = "Shield", color = "#FFD24A", glyph = "D", icon = "" },
	enrage = { kind = "effect", name = "Enrage", color = "#FF4C6A", glyph = "N", icon = "" },
	regen = { kind = "effect", name = "Regen", color = "#55FF99", glyph = "R", icon = "" },
}

return NameplateConfig
