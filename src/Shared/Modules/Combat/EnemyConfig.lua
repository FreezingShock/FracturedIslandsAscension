--[[
	EnemyConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Everything about an enemy that is not damage: hit / crit / death effects, hit sounds, the nameplate and (for mobs) the
	body and behaviour. Read by EnemyFX (client), EnemyService / DummyService (server) and the nameplate controller.

	LAYERS (each one overrides the one before, per field):
	  1. EnemyConfig.fx / .sounds                     the library of effect presets and sound entries
	  2. EnemyConfig.enemies[type].fx[preset]         an enemy type's own tweak of a preset
	  3. EnemyConfig.enemies[type].weapons[weaponType or weaponId].fx[preset]   a weapon's effect on that enemy
	Sound slots (hit / crit / crash / death) name an entry of EnemyConfig.sounds; enemies[type].sounds picks the entries and
	enemies[type].weapons[...].sounds overrides them per weapon. An empty id is skipped silently: set the ids later.

	ENEMY BEHAVIOUR AND REWARDS (EnemyService / LootService read these)
	  enemies[type].attacks = { { attack = "<id>", weight = 1, cooldown = { 3, 5 } }, ... }   ids are EnemyConfig.attacks
	  enemies[type].xp      = { skill = "Combat", amount = 40 }     granted to the killer (SkillsDataManager.AddXP, wisdom applies)
	  enemies[type].drops   = list of: { table = "<dropTables key>" }, a drop entry, or a pool (see DROPS below)

	DROPS: a drop entry is { kind = "item" | "armor" | "stat", id, count = { min, max }, chance = 0..1 }. item / armor ids
	are Items ids (armor is the same as an item, the kind only documents intent); stat entries are
	{ kind = "stat", skill = "Combat", id = "<StatisticsConfig key>", name, color = "#hex", count, chance }. Each entry rolls on its
	own; the killer's MagicFind multiplies the chance (capped at 1). A pool is { kind = "pool", chance, rolls = { 1, 1 },
	entries = { { ...drop entry..., weight } } }: it rolls `rolls` times, each picking one entry by weight.

	RECIPES
	  New attack:       add EnemyConfig.attacks.<id> = { kind = "melee", range, windup, damage, arc, recover, telegraph }.
	  New mob attack:   add the id to enemies.<key>.attacks (several entries = the mob picks by weight).
	  New attack kind:  kinds are implemented in Server/Combat/EnemyAttacks.lua (melee, combo, lunge, slam, parry): add a runner there,
	                    then any enemy can list it. Fields shared by all kinds: range (max studs), minRange, windup, damage, recover,
	                    telegraph = { shape = "cone" | "line" | "circle" | "none", color }, animation (CombatConfig.animations key) or
	                    animationId ("rbxassetid://..", wins over the key), hitMarker (animation marker that lands the hit, else the
	                    timing numbers are used), soundId, minLevel (enemy level needed), condition ("targetSwung" = only right after the
	                    target swung a weapon).
	  AI numbers:       EnemyConfig.ai is the library (idle / alert / chase / engage / return); an enemy's mob table (legacy fields) and
	                    mob.ai override it, per field: aggroRange, leashRange, spacing = { min, max } (hold this ring while attacks
	                    recharge, nil = walk up and stand), flank = { chance, orbitSeconds = { a, b } } (circle the target on that ring),
	                    returnHealSeconds (full heal while walking home after a leash), attackGap (min seconds between attacks).
	  New enemy with a weapon: enemies.<key>.mob.weapon = { item = "<Items id>" } (EnemyRig). The Tool is that item's own (its model,
	                    grip, combo and abilities), so a mob wields exactly what a player can. The item must have a toolName.
	                    template = a ServerStorage rig (R6) when you have custom modelling; phases = nil is RESERVED for bosses.
	  New ability attack: EnemyConfig.attacks.<id> = { kind = "ability", ability = "<AbilityConfig id>", damageMult, range, minRange,
	                    recover, [pose], [telegraph = { color }] }. The ability must be listed on the mob's item (checked at load);
	                    its shape, cast time, hit frame, dash and knockback come from AbilityConfig, the damage from here.
	  New drop table:   add EnemyConfig.dropTables.<name> = { entries... } and reference it with { table = "<name>" }.
	  New enemy type:   add enemies.<key> = { name, nameplate, sounds, [fx], [mob] }; spawn it with a model attribute
	                    EnemyType = "<key>" (EnemyService does that for a marker in Workspace.EnemySpawns).
	  Recolour a hit:   enemies.<key>.fx.hit_normal = { sparks = { color = { ... } } }  (only the fields you change)
	  Per-weapon look:  enemies.<key>.weapons.sword = { fx = { hit_crit = { ring = { size = 14 } } } }
	  Set a sound:      sounds.enemy_hit.id = "rbxassetid://123" (every enemy using that entry), or add a new entry
	                    and point enemies.<key>.sounds.hit at it.
	  New preset:       add it to EnemyConfig.fx; anything may play it by name (EnemyFX.play(preset, ...)).

	PRESET SHAPE (every part optional): burst (flipbook impact star), flash (starburst flare), ring (shockwave disc),
	slash (cut mark), sparks (streaks), shards (slivers), puff (smoke flipbook), motes (lingering dots), light (PointLight
	pop). Ranges are { min, max }, colors a list of Color3 (a gradient over the particle's life), sizes { start, end }.
	Textures are EnemyConfig.textures (tools/fx/gen_fx_textures.py makes them; re-upload and paste the new ids).

	  EnemyConfig.resolve(enemyType, weaponType, weaponId, preset) -> merged preset table (cached, identical table per combo)
	  EnemyConfig.sound(enemyType, weaponType, weaponId, slot)     -> sound entry or nil
	  EnemyConfig.get(enemyType)                                   -> the enemy's entry (falls back to "default")
	  EnemyConfig.statsFor(enemyType)                              -> { level, maxHealth, defense, strength, critChance, hitDamage, ... }
	  EnemyConfig.damageOf(enemyType, attack, multiplier)          -> amount, isCrit   (the damage a move really does, from the gear)
	  EnemyConfig.dropsFor(enemyType)                              -> flat list of drop entries / pools
--]]

local EnemyConfig = {}

-- ===================== LIMITS (per client) =====================
EnemyConfig.limits = {
	maxLive = 26, -- effect rigs alive at once; past it normal hits are dropped (crits and deaths still play up to hardCap)
	hardCap = 40,
	targetCooldown = 0.06, -- seconds between NORMAL-hit effects on one target (stops a many-hit ability from flooding)
	maxDistance = 150, -- studs from the camera beyond which effects are skipped
	poolSize = 12, -- rigs kept ready per preset
}

-- ===================== 0. TEXTURES =====================
-- Generated by tools/fx/gen_fx_textures.py (white + alpha, tinted by each preset's colours), uploaded as images.
-- smoke and burst are 4x4 flipbooks (16 frames played once over the particle's life).
EnemyConfig.textures = {
	streak = "rbxassetid://96301713385777", -- tapered spark streak
	shard = "rbxassetid://85123166542162", -- sharp sliver
	flare = "rbxassetid://119658481753499", -- 8-point starburst flash
	ring = "rbxassetid://91930147480435", -- crisp shockwave ring
	slash = "rbxassetid://112261534443760", -- crescent cut mark
	dot = "rbxassetid://105239482007932", -- small soft mote
	smoke = "rbxassetid://88116739257838", -- flipbook: billowing puff
	burst = "rbxassetid://138960659957311", -- flipbook: spiked impact star
}

-- ===================== 1. LIBRARY: EFFECT PRESETS =====================
local WHITE = Color3.fromRGB(255, 255, 255)
local WARM = Color3.fromRGB(255, 226, 150)
local GOLD = Color3.fromRGB(255, 176, 64)
local EMBER = Color3.fromRGB(255, 120, 40)
local ICE = Color3.fromRGB(190, 240, 255)
local CYAN = Color3.fromRGB(80, 200, 255)
local BLUE = Color3.fromRGB(60, 110, 255)
local DEEP = Color3.fromRGB(30, 60, 230)
local CRIMSON = Color3.fromRGB(255, 70, 60)
local BLOOD = Color3.fromRGB(190, 25, 25)
local SALMON = Color3.fromRGB(255, 205, 190)
local DUST = { Color3.fromRGB(215, 205, 190), Color3.fromRGB(120, 112, 100) }
-- Minecraft XP greens: pale glint, green (#55FF55), dark green (#00AA00)
local XPGLINT = Color3.fromRGB(215, 255, 205)
local XPGREEN = Color3.fromRGB(85, 255, 85)
local XPDARK = Color3.fromRGB(0, 170, 0)

-- Parts of a preset (all optional): burst (flipbook impact star), flash (flare), ring (shockwave disc), slash (cut mark),
-- sparks (streaks), shards (slivers), puff (smoke flipbook), motes (lingering dots), light (PointLight pop).
EnemyConfig.fx = {
	-- a normal hit: a spiked impact flash, a hot flare, warm spark streaks and a few shards back toward the attacker
	hit_normal = {
		burst = { count = 1, color = { WHITE, WARM, GOLD }, size = { 3.2, 5.2 }, life = 0.22 },
		flash = { count = 1, color = { WHITE, WARM }, size = { 2.5, 4 }, life = 0.12, transparency = 0.1 },
		sparks = { count = 12, color = { WHITE, WARM, GOLD, EMBER }, speed = { 26, 58 }, spread = 32, life = { 0.14, 0.34 }, size = { 1.5, 0.5 }, drag = 4, gravity = 46 },
		shards = { count = 3, color = { WARM, GOLD }, speed = { 14, 30 }, spread = 40, life = { 0.2, 0.4 }, size = { 0.9, 0.4 }, drag = 3, gravity = 60 },
		puff = { count = 1, color = DUST, speed = { 0, 0 }, life = 0.45, size = { 2.2, 3.8 }, transparency = 0.45 },
		light = { color = WARM, brightness = 3, range = 9, time = 0.14 },
	},

	-- a crit: the same language, bigger and cold blue, with a crisp shockwave, a cut mark and drifting motes
	hit_crit = {
		burst = { count = 1, color = { WHITE, ICE, CYAN, BLUE }, size = { 4, 6.5 }, life = 0.28 },
		flash = { count = 1, color = { WHITE, ICE }, size = { 2.5, 4.5 }, life = 0.14, transparency = 0.15 },
		ring = { count = 1, color = { WHITE, CYAN, BLUE }, size = { 1, 6 }, life = 0.34, transparency = 0.1, speed = 0.5, horizontal = true },
		slash = { count = 1, color = { WHITE, ICE, CYAN }, size = { 2.2, 4.2 }, life = 0.16, rotation = { -35, 35 }, transparency = 0.25 },
		sparks = { count = 22, color = { WHITE, ICE, CYAN, DEEP }, speed = { 32, 80 }, spread = 38, life = { 0.2, 0.5 }, size = { 2, 0.6 }, drag = 3.5, gravity = 34 },
		shards = { count = 6, color = { ICE, CYAN, BLUE }, speed = { 16, 38 }, spread = 48, life = { 0.25, 0.5 }, size = { 1.3, 0.5 }, drag = 3, gravity = 55 },
		puff = { count = 1, color = { Color3.fromRGB(200, 225, 255), Color3.fromRGB(70, 90, 160) }, speed = { 0, 0 }, life = 0.55, size = { 2.4, 4 }, transparency = 0.55 },
		motes = { count = 14, color = { ICE, CYAN, BLUE }, speed = { 2, 9 }, spread = 180, life = { 0.7, 1.3 }, size = { 0.5, 0.05 }, drag = 2, rise = 3 },
		light = { color = CYAN, brightness = 3, range = 12, time = 0.2 },
	},

	-- a Crash hit (falling swing): the crit language in red, with a wider ground shockwave and a heavier shard spray
	hit_crash = {
		burst = { count = 1, color = { WHITE, SALMON, CRIMSON, BLOOD }, size = { 4.5, 7.5 }, life = 0.3 },
		flash = { count = 1, color = { WHITE, SALMON }, size = { 2.8, 5 }, life = 0.14, transparency = 0.15 },
		ring = { count = 1, color = { WHITE, CRIMSON, BLOOD }, size = { 1, 8 }, life = 0.38, transparency = 0.1, speed = 0.5, horizontal = true },
		slash = { count = 1, color = { WHITE, SALMON, CRIMSON }, size = { 2.4, 4.6 }, life = 0.16, rotation = { -35, 35 }, transparency = 0.25 },
		sparks = { count = 24, color = { WHITE, SALMON, CRIMSON, BLOOD }, speed = { 32, 80 }, spread = 40, life = { 0.2, 0.5 }, size = { 2, 0.6 }, drag = 3.5, gravity = 34 },
		shards = { count = 8, color = { SALMON, CRIMSON, BLOOD }, speed = { 16, 40 }, spread = 52, life = { 0.25, 0.55 }, size = { 1.4, 0.5 }, drag = 3, gravity = 55 },
		puff = { count = 1, color = { Color3.fromRGB(255, 200, 190), Color3.fromRGB(110, 40, 40) }, speed = { 0, 0 }, life = 0.55, size = { 2.6, 4.4 }, transparency = 0.55 },
		motes = { count = 14, color = { SALMON, CRIMSON, BLOOD }, speed = { 2, 9 }, spread = 180, life = { 0.7, 1.3 }, size = { 0.5, 0.05 }, drag = 2, rise = 3 },
		light = { color = CRIMSON, brightness = 3, range = 12, time = 0.2 },
	},

	-- a Full hit (swing-timing bar full): a gold edge played over the hit / crit / crash style
	hit_full = {
		flash = { count = 1, color = { WHITE, Color3.fromRGB(255, 215, 80) }, size = { 2, 3.5 }, life = 0.12, transparency = 0.2 },
		sparks = { count = 8, color = { WHITE, Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 190, 40) }, speed = { 22, 50 }, spread = 45, life = { 0.14, 0.32 }, size = { 1.4, 0.5 }, drag = 4, gravity = 40 },
		motes = { count = 6, color = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 190, 40) }, speed = { 2, 8 }, spread = 180, life = { 0.5, 0.9 }, size = { 0.45, 0.05 }, drag = 2, rise = 3 },
	},

	-- XP gained: a soft green flare, a ring that breathes out, motes drifting up and a few streaks (ActionBarClient plays it at the
	-- player's centre; small and short so frequent gains stay calm)
	xp_gain = {
		flash = { count = 1, color = { XPGLINT, XPGREEN }, size = { 1.8, 3 }, life = 0.2, transparency = 0.3 },
		ring = { count = 1, color = { XPGLINT, XPGREEN, XPDARK }, size = { 0.8, 4.2 }, life = 0.42, transparency = 0.4, speed = 0.5, horizontal = true },
		sparks = { count = 7, color = { XPGLINT, XPGREEN, XPDARK }, speed = { 8, 18 }, spread = 55, life = { 0.3, 0.6 }, size = { 1.1, 0.3 }, drag = 3, rise = 8 },
		motes = { count = 9, color = { XPGLINT, XPGREEN, XPDARK }, speed = { 2, 7 }, spread = 180, life = { 0.7, 1.2 }, size = { 0.4, 0.05 }, drag = 2, rise = 4 },
		light = { color = XPGREEN, brightness = 1.6, range = 9, time = 0.22 },
	},

	-- a LEVEL tick: the crit / crash language in green: a spiked star, a big flare, a wide ground shockwave, a streak fountain,
	-- shards, rising green smoke and a column of motes (played once per level, then xp_levelup_wave follows)
	xp_levelup = {
		burst = { count = 1, color = { XPGLINT, XPGREEN, XPDARK }, size = { 5, 9 }, life = 0.4 },
		flash = { count = 1, color = { XPGLINT, XPGREEN }, size = { 4, 7.5 }, life = 0.2, transparency = 0.15 },
		ring = { count = 1, color = { XPGLINT, XPGREEN, XPDARK }, size = { 1.5, 11 }, life = 0.55, transparency = 0.2, speed = 0.5, horizontal = true },
		sparks = { count = 32, color = { XPGLINT, XPGREEN, XPDARK }, speed = { 18, 44 }, spread = 70, life = { 0.4, 0.9 }, size = { 1.8, 0.5 }, drag = 3, rise = 12 },
		shards = { count = 8, color = { XPGREEN, XPDARK }, speed = { 12, 30 }, spread = 60, life = { 0.3, 0.6 }, size = { 1.2, 0.4 }, drag = 3, gravity = 30 },
		puff = { count = 4, color = { XPGREEN, XPDARK }, speed = { 2, 8 }, spread = 180, life = 0.8, size = { 3, 5.5 }, transparency = 0.55, rise = 2 },
		motes = { count = 26, color = { XPGLINT, XPGREEN, XPDARK }, speed = { 3, 12 }, spread = 180, life = { 1, 1.8 }, size = { 0.55, 0.05 }, drag = 2, rise = 5 },
		light = { color = XPGREEN, brightness = 3.5, range = 17, time = 0.4 },
	},

	-- the second wave of a level tick (a beat later): a wider, slower ring and a gentle halo, so a level lands in two pulses
	xp_levelup_wave = {
		flash = { count = 1, color = { XPGREEN, XPDARK }, size = { 3, 6 }, life = 0.28, transparency = 0.35 },
		ring = { count = 1, color = { XPGLINT, XPGREEN, XPDARK }, size = { 2, 17 }, life = 0.75, transparency = 0.3, speed = 0.5, horizontal = true },
		sparks = { count = 14, color = { XPGREEN, XPDARK }, speed = { 10, 26 }, spread = 90, life = { 0.4, 0.8 }, size = { 1.3, 0.4 }, drag = 3, rise = 9 },
		light = { color = XPDARK, brightness = 2.2, range = 14, time = 0.45 },
	},
}

-- ===================== 1b. LIBRARY: SOUNDS =====================
-- Silent until you set an id ("rbxassetid://123"). 3D at the hit point: full volume inside minDistance studs, silent
-- beyond maxDistance, so anyone nearby hears it.
EnemyConfig.sounds = {
	enemy_hit = { id = "", volume = 0.7, pitch = { 0.92, 1.08 }, minDistance = 12, maxDistance = 90 },
	enemy_crit = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 14, maxDistance = 100 },
	enemy_crash = { id = "", volume = 1.0, pitch = { 0.9, 1.0 }, minDistance = 16, maxDistance = 110 },
	enemy_death = { id = "", volume = 0.9, pitch = { 0.92, 1.05 }, minDistance = 16, maxDistance = 110 },
}

-- ===================== 1c. LIBRARY: ATTACKS =====================
-- kind "melee": after `windup` seconds (the mob stops, faces the target and its body flashes red) a hit lands on the target
-- if it is still within range + leeway studs and inside the `arc` degrees in front of the mob; then `recover` seconds.
-- damage is the base before the player's Defense (DamageService.hurtPlayer).
EnemyConfig.attacks = {
	melee_swing = { kind = "melee", range = 5, leeway = 1.5, windup = 0.6, damageMult = 1, arc = 120, recover = 0.5 },

	-- Rustblade Knight moveset (see header: kinds live in EnemyAttacks)
	-- combo: plays the steps of CombatConfig[weaponType].steps (animation, hitFrame, duration, recovery of the player's sword combo), a
	-- cone hit per step; it keeps swinging while the target stays inside range * chainReach. Each step hits for the gear's hit x the
	-- step's own damageMult (CombatConfig) x damageMult here; the last step also x finisherMult.
	knight_combo = {
		kind = "combo", weaponType = "sword", range = 5.5, leeway = 1.5, arc = 110, damageMult = 0.4, finisherMult = 1.6,
		windup = 0.5, chainWindup = 0.1, chainReach = 1.5, recover = 0.6, missChance = 0.15,
		telegraph = { shape = "cone", color = Color3.fromRGB(255, 70, 50) },
	},
	-- lunge: the gap-closer. A line telegraph, then a fast dash `dash.distance` studs toward where the target stood.
	knight_lunge = {
		kind = "lunge", minRange = 9, range = 18, windup = 0.7, damageMult = 0.9, hitRadius = 4.5, recover = 0.7, missChance = 0.2, sound = "sword_atk3",
		dash = { distance = 14, speed = 70 }, pose = "raise",
		telegraph = { shape = "line", width = 4.5, color = Color3.fromRGB(255, 150, 40) },
	},
	-- slam: ground AoE around the knight.
	knight_slam = {
		kind = "slam", minRange = 0, range = 8, radius = 10, windup = 1.0, damageMult = 1.1, recover = 0.9, sound = "sword_crit4", pose = "raise",
		telegraph = { shape = "circle", color = Color3.fromRGB(255, 60, 60) },
	},
	-- Weapon abilities (AbilityConfig library, the ones a player's copy of the knight's item casts). Ranges match the ability's shape.
	-- Frost Nova's ground zone, Overload, Chain Lightning and the slow / burn effects are not applied to enemies yet.
	knight_holy_nova = { kind = "ability", ability = "holy_nova", range = 18, damageMult = 0.15, recover = 0.8, pose = "raise" },
	knight_blink_dash = { kind = "ability", ability = "blink_dash", range = 22, minRange = 6, damageMult = 0.1, recover = 0.6, pose = "raise" },
	knight_thunder_clap = { kind = "ability", ability = "thunder_clap", range = 14, damageMult = 0.05, recover = 0.7, pose = "raise" },
	knight_frost_nova = { kind = "ability", ability = "frost_nova", range = 20, damageMult = 0.2, recover = 0.7, pose = "raise" },

	-- parry: a short guard. Hits the knight takes meanwhile do `damageTaken` of their damage; used right after the target swings.
	knight_parry = {
		kind = "parry", range = 9, windup = 0.1, duration = 0.9, damageTaken = 0.25, recover = 0.25, pose = "guard",
		condition = "targetSwung", sound = "sword_equip", telegraph = { shape = "none", color = Color3.fromRGB(110, 170, 255) },
	},
}

-- ===================== 1c. LIBRARY: AI =====================
-- Defaults of every mob (legacy mob fields and mob.ai override them per field). Seconds / studs.
EnemyConfig.ai = {
	walkSpeed = 10, -- idle / holding the ring
	chaseSpeed = 14, -- chasing
	aggroRange = 28, -- a player this close is chased
	leashRange = 60, -- studs from home: past it the mob gives up, walks home (ignoring everyone) and heals
	stopDistance = 4, -- studs from the target where it stands still (legacy walk-up behaviour, spacing = nil)
	hitAggroSeconds = 6, -- whoever last hit it is chased this long even outside aggroRange
	loseRange = 1.35, -- an acquired target is kept until it is aggroRange * this far away
	wanderRadius = 14,
	wanderEvery = { 3, 7 },
	alertSeconds = 0.45, -- the beat between seeing a target and chasing it (it turns to face the target)
	attackGap = 0.5, -- min seconds between the end of one attack and the start of the next
	returnHealSeconds = 3, -- time to heal from nothing to full while walking home
	returnSpeedMult = 1.25,
	arriveDistance = 4, -- studs from home that end the return
	spacing = nil, -- { min, max }: the ring it holds around the target while its attacks recharge
	flank = nil, -- { chance = 0..1, orbitSeconds = { a, b } }
	repeatPenalty = 0.35, -- weight multiplier for the attack it used last (variety)
}

-- walking / running / idle: R6 locomotion animations played on the mob by EnemyLocomotion (Roblox's own R6 set; an enemy's
-- mob.locomotion = { idle, walk, run } overrides them for custom animation). run plays above runAt studs/s.
EnemyConfig.locomotion = {
	idle = "rbxassetid://180435571",
	walk = "rbxassetid://180426354",
	run = "rbxassetid://180426354",
	runAt = 12,
	speedScale = 14.5, -- a track plays at speed / this
}

-- procedural poses (degrees added to the R6 shoulders while a move winds up; an animation id slot replaces them later)
EnemyConfig.poses = {
	raise = { rightShoulder = Vector3.new(-155, 0, 0), time = 0.35 }, -- sword overhead
	guard = { rightShoulder = Vector3.new(-80, 0, 25), leftShoulder = Vector3.new(-60, 0, -25), time = 0.1 }, -- blade across the body
}

-- ===================== 1c. LIBRARY: ENEMY LEVELS =====================
-- Every enemy's level is estimated from its gear (EnemyConfig.statsFor), shown on its nameplate, and scales nothing:
--   power = maxHealth * weights.hp + hitDamage * weights.damage + defense * weights.defense
--   level = clamp(round(baseLevel + curve * power ^ exponent), baseLevel, maxLevel)
-- Tune weights / curve here, once, for all enemies.
EnemyConfig.levels = {
	baseLevel = 1,
	maxLevel = 100,
	weights = { hp = 0.02, damage = 2, defense = 1.5 },
	curve = 1.2,
	exponent = 0.5,
}

-- ===================== 1e. ENEMY GEAR (stats come from what the enemy holds) =====================
-- A level is ESTIMATED from the gear and shown on the nameplate. It scales nothing: every number below comes from the items.
--   weapon       mob.weapon.item: the Items id of the sword (its Damage, rarity and own stats). Without one, unarmed.
--   equipment    enemies[type].equipment = { helmet, chestplate, leggings, boots = <Items id>, accessories = { <Items id>, ... } }
--                Their stats are read from the same Items defs a player's copy gets (Defense, Health, Strength, CritChance, ...).
-- Totals: flat sum, times (1 + sum of multipliers), like AttributeStatManager.
--   maxHealth    mob.health (the body) + gear Health + Defense x 1 (a player's rule)
--   Defense      reduces every hit it takes: damage x 100 / (100 + Defense)
--   hit          (weapon Damage x rarity scaling + flatBase) x (1 + Strength x strengthScale) x the attack's damageMult
--                x the move's multiplier (combo step / finisher / ability damageMult), then the CritChance roll
-- EnemyConfig.statsFor(type) / EnemyConfig.damageOf(type, attack, multiplier) do the math.
EnemyConfig.unarmed = { Damage = 6 } -- weapon Damage of a mob with no weapon item

-- ===================== 1d. LIBRARY: DROP TABLES =====================
-- Reference one from an enemy with { table = "<name>" }. Stats go straight to the killer's statistics when picked up.
EnemyConfig.dropTables = {
	mob_basic = {
		{ kind = "stat", skill = "Combat", id = "RottenFlesh", name = "Rotten Flesh", color = "#8B6D3F", count = { 1, 3 }, chance = 0.8 },
		{ kind = "stat", skill = "Combat", id = "Bone", name = "Bone", color = "#FFFFFF", count = { 1, 2 }, chance = 0.4 },
		{ kind = "stat", skill = "Combat", id = "String", name = "String", color = "#D9CDB8", count = { 1, 2 }, chance = 0.3 },
		{ kind = "pool", chance = 0.12, rolls = { 1, 1 }, entries = {
			{ kind = "armor", id = "iron_helmet", weight = 3 },
			{ kind = "armor", id = "iron_chestplate", weight = 2 },
			{ kind = "armor", id = "iron_leggings", weight = 3 },
			{ kind = "armor", id = "iron_boots", weight = 3 },
		} },
		{ kind = "item", id = "gold_terrafruit", count = { 1, 1 }, chance = 0.05 },
		{ kind = "item", id = "feather", count = { 1, 2 }, chance = 0.2 },
		{ kind = "item", id = "copper_ingot", count = { 1, 2 }, chance = 0.12 },
		{ kind = "item", id = "redstone", count = { 1, 3 }, chance = 0.12 },
		{ kind = "item", id = "emerald", count = { 1, 1 }, chance = 0.02 },
		{ kind = "pool", chance = 0.04, rolls = { 1, 1 }, entries = {
			{ kind = "armor", id = "golden_chestplate", weight = 2 },
			{ kind = "armor", id = "golden_leggings", weight = 3 },
			{ kind = "armor", id = "golden_boots", weight = 3 },
			{ kind = "armor", id = "diamond_helmet", weight = 1 },
		} },
	},

	-- five placeholder mobs, each with its own loot identity (stats go to the Combat statistics, items / armor to the inventory)
	slime_drops = {
		{ kind = "stat", skill = "Combat", id = "Slimeball", name = "Slimeball", color = "#55FF55", count = { 1, 3 }, chance = 0.9 },
		{ kind = "item", id = "coal_terrafruit", count = { 1, 2 }, chance = 0.25 },
		{ kind = "item", id = "slime_ball", count = { 1, 3 }, chance = 0.5 },
		{ kind = "item", id = "frostbrand", count = { 1, 1 }, chance = 0.02 },
	},
	skeleton_drops = {
		{ kind = "stat", skill = "Combat", id = "Bone", name = "Bone", color = "#FFFFFF", count = { 1, 3 }, chance = 0.9 },
		{ kind = "stat", skill = "Combat", id = "String", name = "String", color = "#D9CDB8", count = { 1, 2 }, chance = 0.4 },
		{ kind = "pool", chance = 0.1, rolls = { 1, 1 }, entries = {
			{ kind = "armor", id = "iron_helmet", weight = 3 },
			{ kind = "armor", id = "iron_chestplate", weight = 2 },
			{ kind = "armor", id = "iron_leggings", weight = 3 },
			{ kind = "armor", id = "iron_boots", weight = 3 },
		} },
		{ kind = "item", id = "iron_terrafruit", count = { 1, 1 }, chance = 0.1 },
		{ kind = "item", id = "bone", count = { 1, 3 }, chance = 0.6 },
		{ kind = "item", id = "flint", count = { 1, 2 }, chance = 0.25 },
		{ kind = "item", id = "blink_blade", count = { 1, 1 }, chance = 0.02 },
	},
	spider_drops = {
		{ kind = "stat", skill = "Combat", id = "String", name = "String", color = "#D9CDB8", count = { 1, 3 }, chance = 0.9 },
		{ kind = "stat", skill = "Combat", id = "SpiderEye", name = "Spider Eye", color = "#AA0000", count = { 1, 2 }, chance = 0.5 },
		{ kind = "item", id = "swift_gloves", count = { 1, 1 }, chance = 0.04 },
		{ kind = "item", id = "string", count = { 1, 3 }, chance = 0.6 },
		{ kind = "item", id = "spider_eye", count = { 1, 1 }, chance = 0.3 },
		{ kind = "item", id = "rabbit_foot", count = { 1, 1 }, chance = 0.03 },
		{ kind = "item", id = "phantom_membrane", count = { 1, 1 }, chance = 0.02 },
	},
	imp_drops = {
		{ kind = "stat", skill = "Combat", id = "Gunpowder", name = "Gunpowder", color = "#AAAAAA", count = { 1, 3 }, chance = 0.8 },
		{ kind = "stat", skill = "Combat", id = "BlazeRod", name = "Blaze Rod", color = "#FFAA00", count = { 1, 1 }, chance = 0.3 },
		{ kind = "stat", skill = "Combat", id = "MagmaCream", name = "Magma Cream", color = "#FF5555", count = { 1, 1 }, chance = 0.15 },
		{ kind = "item", id = "warriors_belt", count = { 1, 1 }, chance = 0.04 },
		{ kind = "item", id = "gunpowder", count = { 1, 2 }, chance = 0.5 },
		{ kind = "item", id = "blaze_rod", count = { 1, 1 }, chance = 0.2 },
		{ kind = "item", id = "glowstone_dust", count = { 1, 2 }, chance = 0.15 },
	},
	wisp_drops = {
		{ kind = "stat", skill = "Combat", id = "EnderPearl", name = "Ender Pearl", color = "#00AAAA", count = { 1, 2 }, chance = 0.4 },
		{ kind = "stat", skill = "Combat", id = "GhastTear", name = "Ghast Tear", color = "#FFFFFF", count = { 1, 1 }, chance = 0.12 },
		{ kind = "stat", skill = "Combat", id = "ShulkerShell", name = "Shulker Shell", color = "#FF55FF", count = { 1, 1 }, chance = 0.05 },
		{ kind = "item", id = "gold_terrafruit", count = { 1, 1 }, chance = 0.1 },
		{ kind = "item", id = "sapphire_amulet", count = { 1, 1 }, chance = 0.05 },
		{ kind = "item", id = "ender_pearl", count = { 1, 1 }, chance = 0.2 },
		{ kind = "item", id = "diamond", count = { 1, 1 }, chance = 0.02 },
		{ kind = "item", id = "nautilus_shell", count = { 1, 1 }, chance = 0.03 },
		{ kind = "item", id = "stormcaller", count = { 1, 1 }, chance = 0.02 },
	},
}

-- ===================== 2. ENEMY TYPES =====================
-- name        shown on the nameplate (a model attribute EnemyName overrides it)
-- nameplate   the nameplate over its head (ReplicatedStorage.GUI.EnemyNameplate). On for every enemy; false opts out
-- equipment   { helmet, chestplate, leggings, boots, accessories = { ... } }: Items ids of the gear it wears (see 1e. ENEMY GEAR)
-- tags        list of NameplateConfig.tags ids shown as permanent chips (an element, "boss", ...); debuffs / effects are added at
--             runtime with EnemyTags.add (server)
-- sounds      slot -> key in EnemyConfig.sounds
-- fx          per-preset tweaks (layer 2); weapons[...] per-weapon tweaks (layer 3)
-- mob         present only for enemies EnemyService spawns: body / behaviour (see EnemyService)
EnemyConfig.enemies = {
	-- anything Damageable with no EnemyType attribute
	default = {
		name = "Enemy",
		nameplate = true,
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
	},

	dummy = {
		name = "Training Dummy",
		nameplate = true,
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
	},

	placeholder_mob = {
		name = "Placeholder Mob",
		nameplate = true,
		tags = { "fire", "enrage" },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = { { attack = "melee_swing", weight = 1, cooldown = { 3, 5 } } },
		xp = { skill = "Combat", amount = 40 },
		drops = { { table = "mob_basic" } },
		mob = {
			template = "PlaceholderMob", -- ServerStorage model to clone; a tinted plain R6 rig when it does not exist
			bodyColor = Color3.fromRGB(176, 70, 70),
			health = 600,
			walkSpeed = 10,
			chaseSpeed = 14,
			aggroRange = 28, -- studs: a player this close is chased
			leashRange = 60, -- studs from home: past it the mob gives up and walks back
			stopDistance = 4, -- studs: it stops this close to its target (inside its attack range)
			hitAggroSeconds = 6, -- whoever last hit it is chased this long even outside aggroRange
			wanderRadius = 14, -- studs around home it strolls when idle
			wanderEvery = { 3, 7 }, -- seconds between strolls
			respawnSeconds = 5,
		},
	},

	rustblade_knight = {
		name = "Rustblade Knight",
		nameplate = true,
		moveDamage = { knight_combo = 1.07, knight_lunge = 1.6, knight_slam = 2.1 },
		tags = { "shield" },
		equipment = { helmet = "iron_helmet", chestplate = "iron_chestplate", leggings = "iron_leggings", boots = "iron_boots", accessories = { "warriors_belt" } },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		-- weight picks among the attacks whose distance window fits; cooldown is per attack
		attacks = {
			{ attack = "knight_combo", weight = 5, cooldown = { 2.5, 4 } },
			{ attack = "knight_lunge", weight = 3, cooldown = { 6, 9 } },
			{ attack = "knight_slam", weight = 2, cooldown = { 8, 12 } },
			{ attack = "knight_parry", weight = 6, cooldown = { 5, 8 } },
		},
		phases = nil, -- RESERVED: bosses get weighted sets per HP phase here; basic enemies never use it
		xp = { skill = "Combat", amount = 90 },
		drops = { { table = "mob_basic" } },
		mob = {
			template = "RustbladeKnight", -- ServerStorage R6 rig when it exists (custom model later); else a plain R6 rig
			bodyColor = Color3.fromRGB(150, 120, 100),
			weapon = { item = "sword_basic" }, -- Iron Sword: its Tool, model, combo (no ability on the item)
			health = 240,
			walkSpeed = 10,
			chaseSpeed = 15,
			respawnSeconds = 8,
			ai = {
				aggroRange = 32,
				leashRange = 55,
				spacing = { min = 6, max = 10 },
				flank = { chance = 0.55, orbitSeconds = { 1.2, 2.6 } },
				attackGap = 0.12,
			},
		},
	},

	-- Knight variants: same moveset library as the Rustblade Knight, each with its own look, blade, stats and attack mix
	ashen_knight = {
		name = "Fallen Paladin",
		nameplate = true,
		moveDamage = { knight_combo = 0.49, knight_lunge = 0.82, knight_slam = 1.15, knight_holy_nova = 0.38 },
		tags = { "fire" },
		equipment = { helmet = "diamond_helmet", chestplate = "golden_chestplate", accessories = { "sapphire_amulet" } },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = {
			{ attack = "knight_combo", weight = 5, cooldown = { 2.5, 4 } },
			{ attack = "knight_lunge", weight = 1, cooldown = { 6, 9 } },
			{ attack = "knight_slam", weight = 2, cooldown = { 7, 10 } },
			{ attack = "knight_holy_nova", weight = 3, cooldown = { 8, 11 } },
			{ attack = "knight_parry", weight = 1, cooldown = { 6, 9 } },
		},
		xp = { skill = "Combat", amount = 110 },
		drops = { { table = "mob_basic" } },
		mob = {
			template = "RustbladeKnight",
			bodyColor = Color3.fromRGB(62, 58, 66),
			weapon = { item = "sword_legendary" }, -- Excalibur: Diamond model, Holy Nova
			health = 150,
			walkSpeed = 9,
			chaseSpeed = 14,
			respawnSeconds = 8,
			ai = {
				aggroRange = 30,
				leashRange = 55,
				spacing = { min = 5, max = 8 },
				flank = { chance = 0.3, orbitSeconds = { 1, 2 } },
				attackGap = 0.3,
			},
		},
	},
	tide_knight = {
		name = "Tide Knight",
		nameplate = true,
		moveDamage = { knight_combo = 0.23, knight_lunge = 0.46, knight_blink_dash = 0.21 },
		tags = { "storm" },
		equipment = { boots = "golden_boots", accessories = { "phantom_membrane", "swift_gloves" } },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = {
			{ attack = "knight_combo", weight = 3, cooldown = { 2.5, 4 } },
			{ attack = "knight_lunge", weight = 2, cooldown = { 5, 8 } },
			{ attack = "knight_blink_dash", weight = 4, cooldown = { 6, 9 } },
			{ attack = "knight_parry", weight = 4, cooldown = { 4, 7 } },
		},
		xp = { skill = "Combat", amount = 95 },
		drops = { { table = "mob_basic" } },
		mob = {
			template = "RustbladeKnight",
			bodyColor = Color3.fromRGB(60, 110, 140),
			weapon = { item = "blink_blade" }, -- Blink Blade: Gold model, Blink Dash
			health = 500,
			walkSpeed = 11,
			chaseSpeed = 17,
			respawnSeconds = 8,
			ai = {
				aggroRange = 32,
				leashRange = 55,
				spacing = { min = 8, max = 12 },
				flank = { chance = 0.7, orbitSeconds = { 1, 2 } },
				attackGap = 0.2,
			},
		},
	},
	thorn_knight = {
		name = "Thornbound Knight",
		nameplate = true,
		moveDamage = { knight_combo = 0.066, knight_slam = 0.13, knight_thunder_clap = 0.088 },
		tags = { "nature" },
		equipment = { helmet = "solar_crown", chestplate = "iron_chestplate", accessories = { "nautilus_shell", "lucky_cloak" } },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = {
			{ attack = "knight_combo", weight = 4, cooldown = { 2.5, 4 } },
			{ attack = "knight_slam", weight = 2, cooldown = { 6, 9 } },
			{ attack = "knight_thunder_clap", weight = 3, cooldown = { 8, 11 } },
			{ attack = "knight_parry", weight = 2, cooldown = { 5, 8 } },
		},
		xp = { skill = "Combat", amount = 130 },
		drops = { { table = "mob_basic" } },
		mob = {
			template = "RustbladeKnight",
			bodyColor = Color3.fromRGB(90, 120, 60),
			weapon = { item = "stormcaller" }, -- Stormcaller: Diamond model, Thunder Clap
			health = 310,
			walkSpeed = 8,
			chaseSpeed = 12,
			respawnSeconds = 8,
			ai = {
				aggroRange = 28,
				leashRange = 55,
				spacing = { min = 7, max = 9 },
				flank = { chance = 0.2, orbitSeconds = { 1.5, 2.5 } },
				attackGap = 0.4,
			},
		},
	},
	glacier_knight = {
		name = "Glacier Knight",
		nameplate = true,
		moveDamage = { knight_combo = 0.25, knight_lunge = 0.42, knight_frost_nova = 0.38 },
		tags = { "ice" },
		equipment = { helmet = "iron_helmet", chestplate = "golden_chestplate", accessories = { "rabbit_foot", "nautilus_shell" } },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = {
			{ attack = "knight_combo", weight = 4, cooldown = { 2.5, 4 } },
			{ attack = "knight_lunge", weight = 2, cooldown = { 5, 8 } },
			{ attack = "knight_frost_nova", weight = 3, cooldown = { 9, 12 } },
			{ attack = "knight_parry", weight = 4, cooldown = { 4, 7 } },
		},
		xp = { skill = "Combat", amount = 120 },
		drops = { { table = "mob_basic" } },
		mob = {
			template = "RustbladeKnight",
			bodyColor = Color3.fromRGB(200, 230, 245),
			weapon = { item = "frostbrand" }, -- Frostbrand: Iron model, Frost Nova
			health = 220,
			walkSpeed = 9,
			chaseSpeed = 15,
			respawnSeconds = 8,
			ai = {
				aggroRange = 30,
				leashRange = 55,
				spacing = { min = 6, max = 9 },
				flank = { chance = 0.4, orbitSeconds = { 1, 2.2 } },
				attackGap = 0.25,
			},
		},
	},

	slime_blob = {
		name = "Slime Blob",
		nameplate = true,
		tags = { "earth" },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = { { attack = "melee_swing", weight = 1, cooldown = { 3, 5 } } },
		xp = { skill = "Combat", amount = 25 },
		drops = { { table = "slime_drops" } },
		mob = {
			template = "PlaceholderMob",
			bodyColor = Color3.fromRGB(90, 200, 90),
			health = 400,
			walkSpeed = 6,
			chaseSpeed = 10,
			aggroRange = 20,
			leashRange = 60,
			stopDistance = 4,
			hitAggroSeconds = 6,
			wanderRadius = 14,
			wanderEvery = { 3, 7 },
			respawnSeconds = 5,
		},
	},
	skeleton_grunt = {
		name = "Skeleton Grunt",
		nameplate = true,
		tags = { "ice" },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = { { attack = "melee_swing", weight = 1, cooldown = { 2.5, 4 } } },
		xp = { skill = "Combat", amount = 45 },
		drops = { { table = "skeleton_drops" } },
		mob = {
			template = "PlaceholderMob",
			bodyColor = Color3.fromRGB(225, 225, 215),
			health = 900,
			walkSpeed = 10,
			chaseSpeed = 14,
			aggroRange = 28,
			leashRange = 60,
			stopDistance = 4,
			hitAggroSeconds = 6,
			wanderRadius = 14,
			wanderEvery = { 3, 7 },
			respawnSeconds = 5,
		},
	},
	spider_scout = {
		name = "Spider Scout",
		nameplate = true,
		tags = { "storm" },
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = { { attack = "melee_swing", weight = 1, cooldown = { 2, 3.5 } } },
		xp = { skill = "Combat", amount = 35 },
		drops = { { table = "spider_drops" } },
		mob = {
			template = "PlaceholderMob",
			bodyColor = Color3.fromRGB(60, 40, 50),
			health = 500,
			walkSpeed = 14,
			chaseSpeed = 20,
			aggroRange = 32,
			leashRange = 60,
			stopDistance = 4,
			hitAggroSeconds = 6,
			wanderRadius = 14,
			wanderEvery = { 3, 7 },
			respawnSeconds = 5,
		},
	},
	cinder_imp = {
		name = "Cinder Imp",
		nameplate = true,
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = { { attack = "melee_swing", weight = 1, cooldown = { 2.5, 4.5 } } },
		xp = { skill = "Combat", amount = 60 },
		drops = { { table = "imp_drops" } },
		mob = {
			template = "PlaceholderMob",
			bodyColor = Color3.fromRGB(230, 120, 40),
			health = 800,
			walkSpeed = 12,
			chaseSpeed = 16,
			aggroRange = 30,
			leashRange = 60,
			stopDistance = 4,
			hitAggroSeconds = 6,
			wanderRadius = 14,
			wanderEvery = { 3, 7 },
			respawnSeconds = 5,
		},
	},
	void_wisp = {
		name = "Void Wisp",
		nameplate = true,
		sounds = { hit = "enemy_hit", crit = "enemy_crit", crash = "enemy_crash", death = "enemy_death" },
		attacks = { { attack = "melee_swing", weight = 1, cooldown = { 3, 5 } } },
		xp = { skill = "Combat", amount = 110 },
		drops = { { table = "wisp_drops" } },
		mob = {
			template = "PlaceholderMob",
			bodyColor = Color3.fromRGB(150, 90, 220),
			health = 1400,
			walkSpeed = 9,
			chaseSpeed = 13,
			aggroRange = 26,
			leashRange = 60,
			stopDistance = 4,
			hitAggroSeconds = 6,
			wanderRadius = 14,
			wanderEvery = { 3, 7 },
			respawnSeconds = 5,
		},
	},
}

-- ===================== RESOLVING =====================
local function merge(base: any, over: any): any
	if over == nil then
		return base
	end
	if type(base) ~= "table" or type(over) ~= "table" or #over > 0 then
		return over
	end
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(over) do
		out[k] = merge(base[k], v)
	end
	return out
end

local resolved: { [string]: any } = {}

--- The flat drop list of an enemy: its `drops` with every { table = "<name>" } expanded from EnemyConfig.dropTables.
local aiCache: { [string]: any } = {}

--- The merged AI numbers of an enemy type: EnemyConfig.ai < the mob table's legacy fields < mob.ai.
function EnemyConfig.aiFor(enemyType: string): any
	local cached = aiCache[enemyType]
	if cached then
		return cached
	end
	local merged = table.clone(EnemyConfig.ai)
	local entry = EnemyConfig.enemies[enemyType]
	local mob = entry and entry.mob
	if mob then
		for key in pairs(EnemyConfig.ai) do
			if mob[key] ~= nil then
				merged[key] = mob[key]
			end
		end
		for key, value in pairs(mob.ai or {}) do
			merged[key] = value
		end
	end
	aiCache[enemyType] = merged
	return merged
end

function EnemyConfig.dropsFor(enemyType: string?): { any }
	local out = {}
	for _, entry in ipairs(EnemyConfig.get(enemyType).drops or {}) do
		if entry.table then
			for _, dropped in ipairs(EnemyConfig.dropTables[entry.table] or {}) do
				table.insert(out, dropped)
			end
		else
			table.insert(out, entry)
		end
	end
	return out
end

function EnemyConfig.get(enemyType: string?): any
	return EnemyConfig.enemies[enemyType or "default"] or EnemyConfig.enemies.default
end

local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local Items = require(Modules:WaitForChild("Items")) :: any
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry")) :: any

local HEALTH_PER_DEFENSE = 1 -- the same rule as a player (ResourceConfig: Health = Health + Defense x 1)

--- Adds an Items def's stats to `totals`: a number is flat, { flat, mult } is flat plus a multiplier (like AttributeStatManager).
local function addStats(totals: { [string]: any }, def: any?)
	for key, value in pairs(def and def.stats or {}) do
		local total = totals[key] or { flat = 0, mult = 0 }
		totals[key] = total
		if type(value) == "table" then
			total.flat += tonumber(value.flat) or 0
			total.mult += tonumber(value.mult) or 0
		elseif type(value) == "number" then
			total.flat += value
		end
	end
end

local function totalOf(totals: { [string]: any }, key: string): number
	local total = totals[key]
	return total and total.flat * (1 + total.mult) or 0
end

--- The plain Damage of a weapon def (the flat part when it is written as { flat, mult }).
local function weaponDamageOf(def: any?): number
	local value = def and def.stats and def.stats.Damage
	if type(value) == "table" then
		return tonumber(value.flat) or 0
	end
	return tonumber(value) or 0
end

local statsCache: { [string]: any } = {}

--- Everything an enemy's gear makes it (cached per type): max health, Defense, Strength, crit, the weapon's hit and the level
--- estimated from them. Read by EnemyService (spawn), the attacks (damageOf) and the nameplate (client).
function EnemyConfig.statsFor(enemyType: string?): any
	local key = enemyType or "default"
	local cached = statsCache[key]
	if cached then
		return cached
	end
	local entry = EnemyConfig.get(enemyType)
	local mob = entry.mob or {}
	local weaponDef = mob.weapon and mob.weapon.item and Items.get(mob.weapon.item)
	local equipment = entry.equipment or {}
	local totals: { [string]: any } = {}
	addStats(totals, weaponDef)
	for _, slot in ipairs({ "helmet", "chestplate", "leggings", "boots" }) do
		addStats(totals, equipment[slot] and Items.get(equipment[slot]))
	end
	for _, id in ipairs(equipment.accessories or {}) do
		addStats(totals, Items.get(id))
	end

	local defense = math.max(totalOf(totals, "Defense"), 0)
	local strength = totalOf(totals, "Strength")
	local maxHealth = (mob.health or 0) + totalOf(totals, "Health") + defense * HEALTH_PER_DEFENSE
	local weaponBase = WeaponRegistry.getScaledDamage(weaponDef and weaponDamageOf(weaponDef) or EnemyConfig.unarmed.Damage, weaponDef and weaponDef.rarity or 0)
	local hitDamage = (weaponBase + CombatConfig.damage.flatBase) * (1 + strength * CombatConfig.damage.strengthScale)

	local lv = EnemyConfig.levels
	local power = maxHealth * lv.weights.hp + hitDamage * lv.weights.damage + defense * lv.weights.defense
	local info = {
		level = math.clamp(math.round(lv.baseLevel + lv.curve * power ^ lv.exponent), lv.baseLevel, lv.maxLevel),
		maxHealth = maxHealth,
		defense = defense,
		strength = strength,
		critChance = math.clamp(totalOf(totals, "CritChance"), 0, CombatConfig.damage.critChanceCap),
		critIncrease = totalOf(totals, "CritIncrease"),
		weaponBase = weaponBase,
		hitDamage = math.floor(hitDamage + 0.5), -- one plain hit, before the attack's own multipliers and crit
		weaponType = weaponDef and weaponDef.weapon and weaponDef.weapon.weaponType or nil,
	}
	statsCache[key] = info
	return info
end

--- The damage one attack (or one combo step) does from the mob's gear. Same formula as a player's swing (DamageService.compute):
--- (weapon Damage x rarity + flatBase) x (1 + Strength x strengthScale) x attack.damageMult x multiplier, then the CritChance roll.
--- `multiplier` is the extra part of the move: a combo step's damageMult, a finisher, or an ability's own damageMult.
--- Returns the amount and whether it crit.
function EnemyConfig.damageOf(enemyType: string?, attack: any, multiplier: number?): (number, boolean)
	local info = EnemyConfig.statsFor(enemyType)
	local config = CombatConfig.damage
	local amount = (info.weaponBase + config.flatBase) * (1 + info.strength * config.strengthScale) * (attack.damageMult or 1) * (multiplier or 1)
	local isCrit = math.random() * 100 < info.critChance
	if isCrit then
		amount *= 1 + (config.critBase + info.critIncrease) * config.critScale
	end
	return math.max(1, math.floor(amount + 0.5)), isCrit
end

function EnemyConfig.resolve(enemyType: string?, weaponType: string?, weaponId: string?, preset: string): any
	local key = table.concat({ enemyType or "", weaponType or "", weaponId or "", preset }, "|")
	local cached = resolved[key]
	if cached then
		return cached
	end
	local enemy = EnemyConfig.get(enemyType)
	local out = EnemyConfig.fx[preset]
	out = merge(out, enemy.fx and enemy.fx[preset])
	local weapons = enemy.weapons
	if weapons then
		out = merge(out, weapons[weaponType or ""] and weapons[weaponType or ""].fx and weapons[weaponType or ""].fx[preset])
		out = merge(out, weapons[weaponId or ""] and weapons[weaponId or ""].fx and weapons[weaponId or ""].fx[preset])
	end
	resolved[key] = out
	return out
end

function EnemyConfig.sound(enemyType: string?, weaponType: string?, weaponId: string?, slot: string): any?
	local enemy = EnemyConfig.get(enemyType)
	local name = enemy.sounds and enemy.sounds[slot]
	local weapons = enemy.weapons
	if weapons then
		for _, w in ipairs({ weaponType or "", weaponId or "" }) do
			local override = weapons[w] and weapons[w].sounds and weapons[w].sounds[slot]
			if override then
				name = override
			end
		end
	end
	local entry = name and EnemyConfig.sounds[name]
	if entry and entry.id and entry.id ~= "" then
		return entry
	end
	return nil
end

return EnemyConfig
