--[[
	AbilityConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Every weapon ability (the ones cast with a key, not the combo) is data in this file. Same layering as CombatConfig:

	1. LIBRARY    AbilityConfig.abilities[id]   what an ability is and does
	2. WEAPON     Items/Defs/Weapons: abilities = { { name, text, ability = "<id>", key = "RMB" | "Z" | "X" | "C" | "V" } }
	              `ability` links a weapon to a library entry. A weapon may list several (one per key). The `key` on the weapon
	              entry is the binding (it falls back to the library entry's key). Keys must be in AbilityConfig.keys and
	              unique on one weapon: AbilityConfig.validate() logs an error at load for a bad or duplicate key.
	3. OVERRIDES  AbilityConfig.overrides[weaponId][abilityId] = { manaCost = 80, ... }   one weapon tweaks one ability

	Ability fields
	  name, key          display name; "Q", "E" ... a keyboard key name, or "RMB" (pressed, never held)
	  manaCost, cooldown spent when cast / seconds before it can be cast again
	  castTime           seconds the caster is locked out of the combo while casting
	  hitFrame           seconds after the press when the damage / effect lands (match it to the animation)
	  shape              what it hits, measured from the caster (DamageService.query):
	                       { kind = "circle", radius }            everything around you
	                       { kind = "cone", reach, arc }          in front of you (arc = total degrees)
	                       { kind = "line", length, width }       a beam straight ahead
	                     optional on any shape: vertical (studs up / down, default CombatConfig.damage.verticalTolerance),
	                     lineOfSight (false = walls do not block it)
	  damageMult         multiplier on the normal weapon damage formula (Strength and crit apply): 3.0 = 300%
	  knockback          push away from the caster (0 = none); maxTargets  how many it may hit (nearest first)
	  zone               nil = one instant hit. Else it leaves an area that keeps hitting:
	                       { duration, tickInterval, tickOnCast = true (first tick at once), follow = true (moves with you) }
	                     follow = false pins the area where the caster stood at the hit frame (a frost field)
	  effects            list applied to every target the ability hits (a zone re-applies each tick):
	                       { kind = "slow", mult = 0.4, duration = 2.5 }                     walk speed x mult (strongest wins)
	                       { kind = "burn", damageMult = 0.2, interval = 1, duration = 3 }   damage over time (a fraction of the ability hit)
	  chain              { jumps, range, falloff }: after the first target (nearest in `shape`) the hit jumps to the nearest
	                     other enemy within `range` studs of the last one, `jumps` times, each hit x falloff of the one before
	  dash               { distance }: the caster is moved forward up to `distance` studs (stops short of walls) after the
	                     hit; `shape` (a line) is measured from where the dash started
	  animation          CombatConfig.animations key played on the caster ("" / nil = none). A placeholder until published.
	  sound / fx         AbilityConfig.sounds / AbilityConfig.fx keys. Sounds with id "" are silent.
	  fx kinds           nova (expanding ring), zone (embers over the area, follows the caster), frost (a ground ring and snow
	                     that stay for the zone duration), dash (a streak from start to end), chain (jagged bolts between targets)

	Recipes
	  New ability ................ add a library entry, add `ability = "<id>", key = "Z"` to a weapon in Defs/Weapons.
	  Two abilities on one item .. list both in the weapon's abilities, each with its own key (RMB / Z / X / C / V).
	  Real animation ............. publish it, add it to CombatConfig.animations, set `animation = "<key>"`.
	  Real sound ................. put the id in AbilityConfig.sounds[...].id.
	  One weapon casts it cheaper  overrides[weaponId] = { [abilityId] = { manaCost = 30 } }.

	API
	  AbilityConfig.get(abilityId, weaponId?)    -> merged ability table (with .id) or nil
	  AbilityConfig.forWeapon(weaponId)          -> list of { id, config } the weapon can cast (config.key = the weapon's binding)
	  AbilityConfig.validate()                   -> logs bad / duplicate keys and unknown ability ids (the server calls it once)
	  AbilityConfig.byKey(weaponId, keyName)     -> the weapon's ability bound to that key, or nil
	  AbilityConfig.animationKeys()              -> every animation key used (for preloading)
--]]

local AbilityConfig = {}

AbilityConfig.maxZonesPerPlayer = 2 -- active zones one player may keep running (exploit / performance cap)
AbilityConfig.minPressGap = 0.15 -- seconds between two presses of the same key (earlier ones are dropped, even if they would be valid)
AbilityConfig.maxZonesGlobal = 24 -- zones running on the whole server
AbilityConfig.maxBurnsGlobal = 60 -- targets burning on the whole server (one burn per target)
AbilityConfig.fxDistance = 220 -- studs: only players this close to the caster are sent the cast / effect messages

-- The keys an ability may be bound to (the client sends the key name, the server looks it up on the held weapon).
AbilityConfig.keys = { RMB = true, Z = true, X = true, C = true, V = true }

-- Client effect limits (AbilityController).
AbilityConfig.fxLimits = {
	maxDistance = 170, -- studs from the camera: farther casts show no effect
	maxEmitters = 16, -- particle emitters alive at once (embers / snow / motes / bursts); past it a layer is skipped
	maxParts = 160, -- effect parts alive at once (a layered cast uses about 10 to 25)
	poolSize = 40, -- parts kept ready per kind
}

-- ===================== 1. LIBRARY =====================
AbilityConfig.abilities = {
	overload = {
		name = "Overload",
		key = "RMB",
		manaCost = 60,
		cooldown = 10,
		castTime = 0.6,
		hitFrame = 0.3,
		shape = { kind = "circle", radius = 50, vertical = 25, lineOfSight = false },
		damageMult = 1.0, -- about 500 with Solar Blade; Strength and crit add on top
		knockback = 0,
		maxTargets = 12,
		zone = { duration = 9, tickInterval = 3, tickOnCast = true, follow = true },
		animation = "sword_combo2", -- placeholder
		sound = "overload_cast",
		fx = "overload",
	},
	holy_nova = {
		name = "Holy Nova",
		key = "Z",
		manaCost = 40,
		cooldown = 6,
		castTime = 0.55,
		hitFrame = 0.3,
		shape = { kind = "circle", radius = 18 },
		damageMult = 3.0,
		knockback = 40,
		maxTargets = 12,
		animation = "sword_combo4", -- placeholder
		sound = "holy_nova_cast",
		fx = "holy_nova",
	},
	blink_dash = {
		name = "Blink Dash",
		key = "RMB",
		manaCost = 40,
		cooldown = 5,
		castTime = 0.35,
		hitFrame = 0.1,
		shape = { kind = "line", length = 22, width = 6, vertical = 8 },
		damageMult = 2.2,
		knockback = 0,
		maxTargets = 8,
		dash = { distance = 22 },
		animation = "sword_combo3", -- placeholder
		sound = "blink_cast",
		fx = "blink",
	},
	chain_lightning = {
		name = "Chain Lightning",
		key = "RMB",
		manaCost = 50,
		cooldown = 7,
		castTime = 0.5,
		hitFrame = 0.25,
		shape = { kind = "cone", reach = 30, arc = 70 }, -- the first target: the nearest enemy in front
		damageMult = 2.0,
		knockback = 0,
		maxTargets = 1,
		chain = { jumps = 4, range = 16, falloff = 0.8 },
		animation = "sword_combo4", -- placeholder
		sound = "chain_cast",
		fx = "chain",
	},
	thunder_clap = {
		name = "Thunder Clap",
		key = "Z",
		manaCost = 35,
		cooldown = 9,
		castTime = 0.5,
		hitFrame = 0.25,
		shape = { kind = "circle", radius = 14 },
		damageMult = 1.5,
		knockback = 30,
		maxTargets = 10,
		effects = {
			{ kind = "slow", mult = 0.5, duration = 2 },
			{ kind = "burn", damageMult = 0.25, interval = 1, duration = 3 },
		},
		animation = "sword_combo2", -- placeholder
		sound = "clap_cast",
		fx = "thunder_clap",
	},
	venom_cloud = {
		name = "Venom Cloud",
		key = "X",
		manaCost = 45,
		cooldown = 10,
		castTime = 0.5,
		hitFrame = 0.3,
		shape = { kind = "circle", radius = 16, lineOfSight = false },
		damageMult = 0.6,
		knockback = 0,
		maxTargets = 10,
		zone = { duration = 8, tickInterval = 2, tickOnCast = true, follow = false },
		effects = { { kind = "burn", damageMult = 0.3, interval = 2, duration = 4 } },
		animation = "sword_combo3", -- placeholder
		sound = "venom_cast",
		fx = "venom_cloud",
	},
	earthshatter = {
		name = "Earthshatter",
		key = "RMB",
		manaCost = 60,
		cooldown = 8,
		castTime = 0.7,
		hitFrame = 0.6,
		shape = { kind = "circle", radius = 12 },
		damageMult = 4.0,
		knockback = 60,
		maxTargets = 8,
		animation = "sword_combo2", -- placeholder
		sound = "earth_cast",
		fx = "earthshatter",
	},
	gale_lance = {
		name = "Gale Lance",
		key = "V",
		manaCost = 35,
		cooldown = 4,
		castTime = 0.4,
		hitFrame = 0.2,
		shape = { kind = "line", length = 30, width = 5, vertical = 8 },
		damageMult = 1.6,
		knockback = 15,
		maxTargets = 6,
		animation = "sword_combo3", -- placeholder
		sound = "lance_cast",
		fx = "gale_lance",
	},
	frost_nova = {
		name = "Frost Nova",
		key = "RMB",
		manaCost = 55,
		cooldown = 12,
		castTime = 0.55,
		hitFrame = 0.3,
		shape = { kind = "circle", radius = 20, lineOfSight = false },
		damageMult = 1.2,
		knockback = 0,
		maxTargets = 12,
		zone = { duration = 6, tickInterval = 1.5, tickOnCast = true, follow = false },
		effects = { { kind = "slow", mult = 0.4, duration = 2.5 } },
		animation = "sword_combo4", -- placeholder
		sound = "frost_cast",
		fx = "frost",
	},
}

-- Sounds (3D, played at the caster). id = "" is silent until you upload one.
AbilityConfig.sounds = {
	overload_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	holy_nova_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	blink_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	chain_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	clap_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	venom_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	earth_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	lance_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	frost_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
}

-- Visuals (AbilityController builds them from these numbers).
--   nova = a flat ring that expands to the shape's radius      zone = embers drifting over the shape's area for the zone's duration
--   frost = a ground ring + snow over the area for the zone's duration (pinned where it was cast)
--   dash = a streak from where the caster started to where it ended      chain = jagged bolts caster -> target -> target ...
AbilityConfig.fx = {
	holy_nova = {
		layers = {
			{ kind = "pillar", color = Color3.fromRGB(255, 248, 215), width = 2.6, height = 18, time = 0.25, ease = "inCubic", descend = true },
			{ kind = "shock", color = Color3.fromRGB(255, 222, 130), time = 0.5, height = 0.5, delay = 0.2 },
			{ kind = "shock", color = Color3.fromRGB(255, 255, 255), scale = 0.7, time = 0.35, delay = 0.25, height = 0.3 },
			{ kind = "rays", colors = { Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 255, 255) }, count = 12, tilt = 12, lift = 1.6, spin = 40, time = 0.5, width = 0.25, delay = 0.2 },
			{ kind = "glyph", colors = { Color3.fromRGB(255, 240, 160), Color3.fromRGB(255, 255, 255) }, count = 12, radius = 3.5, length = 0.8, width = 0.15, spin = 220, height = 4.5, transparency = 0.05, time = 0.8 },
			{ kind = "burst", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 230, 140) }, count = 28, speed = { 6, 12 }, lifetime = { 0.7, 1.2 }, size = 0.4, spread = 60, delay = 0.2 },
			{ kind = "spot", color = Color3.fromRGB(255, 225, 130), range = 22, angle = 60, height = 12, brightness = 4 },
		},
	},
	overload = {
		layers = {
			{ kind = "pillar", color = Color3.fromRGB(255, 130, 40), width = 3, height = 22, time = 0.45 },
			{ kind = "burst", colors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 130, 40), Color3.fromRGB(180, 40, 20) }, texture = "rbxasset://textures/particles/fire_main.dds", count = 30, speed = { 10, 18 }, lifetime = { 0.8, 1.4 }, size = 0.9, spread = 60, lightEmission = 0.6 },
			{ kind = "disc", color = Color3.fromRGB(90, 20, 10), transparency = 0.5, height = 0.2, pulse = 0.6, pulseAmount = 0.03 },
			{ kind = "disc", color = Color3.fromRGB(255, 120, 30), transparency = 0.82, scale = 0.5, height = 0.4, pulse = 1.2, pulseAmount = 0.08 },
			{ kind = "glyph", colors = { Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 90, 20) }, count = 16, scale = 0.95, length = 4, width = 0.5, spin = 20, height = 0.3, transparency = 0.1 },
			{ kind = "glyph", colors = { Color3.fromRGB(255, 230, 120) }, count = 8, scale = 0.35, length = 3, width = 0.25, spin = -60, height = 0.45, transparency = 0.1 },
			{ kind = "pulse", color = Color3.fromRGB(255, 140, 40), every = 3, time = 0.7, height = 0.5, lift = 0.3, ease = "outQuad" },
			{ kind = "motes", colors = { Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 150, 40), Color3.fromRGB(200, 50, 20) }, rate = 22, lifetime = { 3, 4.5 }, speed = { 4, 7 }, size = 0.5, height = 22, direction = Enum.NormalId.Bottom, spread = 8, drag = 0.2 },
			{ kind = "motes", colors = { Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 90, 20), Color3.fromRGB(150, 25, 10) }, texture = "rbxasset://textures/particles/fire_main.dds", rate = 14, lifetime = { 1.2, 2 }, speed = { 2, 4 }, size = 2.2, height = -2, direction = Enum.NormalId.Top, spread = 30, lightEmission = 0.6 },
			{ kind = "spot", color = Color3.fromRGB(255, 170, 80), range = 40, angle = 60, height = 22, brightness = 2, flicker = 0.15 },
		},
	},
	blink = {
		shake = false, -- the blink uses its own camera whip and FOV punch (CameraFeel), not a shake
		layers = {
			{ kind = "trail", color = Color3.fromRGB(255, 230, 140), count = 7, width = 2.2, height = 4.6, time = 0.35, fade = 0.45 },
			{ kind = "orb", color = Color3.fromRGB(255, 250, 220), glowColor = Color3.fromRGB(255, 210, 90), size = 2.2, time = 0.2, shrink = true, ease = "inCubic" },
			{ kind = "bolt", color = Color3.fromRGB(255, 250, 220), glowColor = Color3.fromRGB(255, 210, 90), width = 0.3, glowWidth = 2, glowTransparency = 0.7, grow = 0.12, time = 0.25 },
			{ kind = "streaks", colors = { Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 200, 90) }, rate = 80, lifetime = { 0.2, 0.4 }, speed = { 8, 14 }, size = 0.3, time = 0.35, spread = 10 },
			{ kind = "orb", at = "end", delay = 0.3, color = Color3.fromRGB(255, 250, 220), glowColor = Color3.fromRGB(255, 210, 90), size = 2.6, time = 0.35, ease = "outBack" },
			{ kind = "burst", at = "end", delay = 0.3, colors = { Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 200, 90) }, count = 14, speed = { 6, 10 }, lifetime = { 0.4, 0.7 }, size = 0.3, spread = 180 },
		},
	},
	chain = {
		layers = {
			{ kind = "spot", color = Color3.fromRGB(180, 220, 255), range = 18, angle = 50, height = 10, brightness = 4 },
			{ kind = "burst", colors = { Color3.fromRGB(220, 240, 255), Color3.fromRGB(120, 200, 255) }, count = 16, speed = { 6, 10 }, lifetime = { 0.3, 0.6 }, size = 0.25, height = 0.3, spread = 180 },
			{ kind = "lightning", color = Color3.fromRGB(190, 230, 255), width = 0.35, segments = 5, jitter = 1.2, time = 0.3, refresh = 0.05 },
			{ kind = "orb", perPoint = true, color = Color3.fromRGB(210, 240, 255), glowColor = Color3.fromRGB(120, 200, 255), size = 1.2, time = 0.3, shrink = true, ease = "inCubic" },
		},
	},
	thunder_clap = {
		layers = {
			{ kind = "shock", color = Color3.fromRGB(200, 235, 255), time = 0.3, height = 0.4 },
			{ kind = "shock", color = Color3.fromRGB(120, 180, 255), scale = 0.7, time = 0.5, delay = 0.06, height = 0.25 },
			{ kind = "pillar", color = Color3.fromRGB(210, 240, 255), width = 1.6, height = 12, time = 0.2 },
			{ kind = "lightning", arcs = 7, scale = 1.0, color = Color3.fromRGB(230, 245, 255), width = 0.25, segments = 6, jitter = 1.4, time = 0.35, refresh = 0.04, delay = 0.02 },
			{ kind = "disc", color = Color3.fromRGB(90, 160, 255), transparency = 0.6, scale = 0.9, height = 0.2, pulse = 2.5, pulseAmount = 0.06, material = "ForceField" },
			{ kind = "burst", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 200, 255) }, count = 22, speed = { 12, 18 }, lifetime = { 0.4, 0.8 }, size = 0.3, spread = 50, acceleration = Vector3.new(0, -25, 0), height = 0.5 },
			{ kind = "spot", color = Color3.fromRGB(170, 210, 255), range = 18, angle = 40, height = 10, brightness = 5 },
		},
	},
	-- Layered effects: each layer is one visual, stacked. See docs/FX_GUIDE.md for the layer kinds and the rules.
	venom_cloud = {
		layers = {
			{ kind = "disc", color = Color3.fromRGB(30, 90, 25), transparency = 0.45, height = 0.3, pulse = 0.5, pulseAmount = 0.04 },
			{ kind = "disc", color = Color3.fromRGB(150, 255, 80), transparency = 0.8, scale = 0.6, height = 0.6, pulse = 0.9, pulseAmount = 0.1 },
			{ kind = "glyph", colors = { Color3.fromRGB(200, 255, 120), Color3.fromRGB(110, 230, 60) }, count = 12, scale = 0.92, length = 2.4, width = 0.3, spin = 45, height = 0.4, transparency = 0.05 },
			{ kind = "glyph", colors = { Color3.fromRGB(200, 100, 255) }, count = 6, scale = 0.45, length = 1.1, width = 0.25, spin = -90, height = 0.5, transparency = 0.1 },
			{ kind = "glyph", colors = { Color3.fromRGB(120, 255, 90), Color3.fromRGB(230, 255, 150) }, count = 24, scale = 1.0, length = 0.9, width = 0.12, spin = -20, height = 0.35, transparency = 0.2 },
			{ kind = "burst", colors = { Color3.fromRGB(240, 255, 140), Color3.fromRGB(120, 240, 70) }, count = 24, speed = { 4, 9 }, lifetime = { 0.8, 1.4 }, size = 0.5, height = 0.5, spread = 120, acceleration = Vector3.new(0, -4, 0) },
			{ kind = "spot", color = Color3.fromRGB(160, 255, 110), range = 26, angle = 30, height = 14, brightness = 2.5, flicker = 0.2 },
			{ kind = "motes", colors = { Color3.fromRGB(240, 255, 130), Color3.fromRGB(120, 240, 70), Color3.fromRGB(40, 140, 40) }, rate = 16, lifetime = { 2, 3 }, speed = { 1.5, 3 }, size = 0.35, height = 0.8, direction = Enum.NormalId.Top, spread = 70 },
			{ kind = "motes", colors = { Color3.fromRGB(200, 90, 255), Color3.fromRGB(70, 150, 50) }, rate = 9, lifetime = { 2.5, 4 }, speed = { 0.1, 0.6 }, size = 0.5, height = 6, direction = Enum.NormalId.Bottom, spread = 180, acceleration = Vector3.new(0, -0.8, 0), drag = 0.5 },
		},
	},
	gale_lance = {
		layers = {
			-- residue first: the cut it leaves in the air lingers after the lance is gone
			{ kind = "trail", color = Color3.fromRGB(150, 230, 255), count = 14, width = 1.2, height = 0.15, time = 0.3, fade = 2.4 },
			{ kind = "bolt", color = Color3.fromRGB(245, 255, 255), glowColor = Color3.fromRGB(110, 230, 255), width = 0.45, glowWidth = 2.4, glowTransparency = 0.7, grow = 0.15, time = 0.4, ease = "outCubic" },
			{ kind = "streaks", colors = { Color3.fromRGB(235, 255, 255), Color3.fromRGB(120, 220, 255), Color3.fromRGB(70, 150, 255) }, rate = 90, lifetime = { 0.25, 0.5 }, speed = { 10, 16 }, size = 0.25, time = 0.3, spread = 12 },
			{ kind = "glyph", at = "end", colors = { Color3.fromRGB(160, 240, 255), Color3.fromRGB(230, 252, 255) }, count = 8, radius = 2.2, length = 1.2, width = 0.2, spin = 260, height = 0.3, transparency = 0.1, time = 0.8 },
			{ kind = "shock", at = "end", delay = 0.28, color = Color3.fromRGB(190, 245, 255), radius = 3, time = 0.35, height = 0.25 },
			{ kind = "burst", at = "end", delay = 0.28, colors = { Color3.fromRGB(150, 240, 255), Color3.fromRGB(255, 255, 255) }, count = 12, speed = { 6, 10 }, lifetime = { 0.4, 0.7 }, size = 0.35, height = 0.3, spread = 180 },
		},
	},
	earthshatter = {
		shake = "explosion", -- a heavy slam: the strongest ability shake (CameraConfig.shake.presets)
		layers = {
			{ kind = "shock", color = Color3.fromRGB(255, 228, 140), time = 0.45, height = 0.7 },
			{ kind = "shock", color = Color3.fromRGB(200, 120, 50), scale = 0.65, time = 0.7, delay = 0.1, height = 0.4 },
			{ kind = "cracks", color = Color3.fromRGB(255, 180, 70), count = 7, time = 0.4, delay = 0.02, width = 0.35 },
			{ kind = "rays", colors = { Color3.fromRGB(255, 200, 100), Color3.fromRGB(255, 240, 180) }, count = 6, tilt = 6, lift = 0.1, time = 0.6, width = 0.4, delay = 0.02 },
			{ kind = "debris", colors = { Color3.fromRGB(140, 100, 60), Color3.fromRGB(90, 65, 40), Color3.fromRGB(200, 160, 110) }, material = "Slate", count = 12, size = { 0.35, 0.8 }, speed = { 6, 12 }, up = 14, gravity = 38, flight = { 0.7, 1.1 }, delay = 0.02 },
			{ kind = "burst", colors = { Color3.fromRGB(190, 160, 120), Color3.fromRGB(120, 100, 80) }, texture = "rbxasset://textures/particles/smoke_main.dds", count = 18, speed = { 2, 5 }, lifetime = { 1.2, 2 }, size = 1.8, delay = 0.03, height = 0.5, spread = 90, lightEmission = 0.1, acceleration = Vector3.new(0, 2, 0) },
			{ kind = "burst", colors = { Color3.fromRGB(255, 250, 200), Color3.fromRGB(255, 190, 80) }, count = 16, speed = { 6, 11 }, lifetime = { 0.6, 1.0 }, size = 0.3, delay = 0.05, height = 0.6, spread = 90 },
			{ kind = "spot", color = Color3.fromRGB(255, 235, 170), range = 18, angle = 55, height = 11, brightness = 6 },
		},
	},
	frost = {
		layers = {
			{ kind = "disc", color = Color3.fromRGB(120, 215, 255), transparency = 0.55, height = 0.2, pulse = 0.4, pulseAmount = 0.03, material = "ForceField" },
			{ kind = "disc", color = Color3.fromRGB(230, 252, 255), transparency = 0.82, scale = 0.5, height = 0.35, pulse = 0.9, pulseAmount = 0.06, material = "ForceField" },
			{ kind = "rays", colors = { Color3.fromRGB(190, 245, 255), Color3.fromRGB(255, 255, 255) }, count = 10, time = 0.6, width = 0.2, lift = 0.15 },
			{ kind = "shards", colors = { Color3.fromRGB(170, 235, 255), Color3.fromRGB(230, 252, 255) }, count = 14, scale = 0.95, height = 5, width = 0.6, time = 0.6, spin = 6, material = "Glass" },
			{ kind = "pulse", color = Color3.fromRGB(200, 245, 255), every = 1.5, time = 0.6, height = 0.4, lift = 0.25, ease = "outQuad" },
			{ kind = "motes", colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 235, 255) }, rate = 14, lifetime = { 3, 5 }, speed = { 1, 2 }, size = 0.35, height = 16, direction = Enum.NormalId.Bottom, spread = 180 },
			{ kind = "motes", colors = { Color3.fromRGB(200, 245, 255), Color3.fromRGB(120, 210, 240) }, texture = "rbxasset://textures/particles/smoke_main.dds", lightEmission = 0.2, rate = 4, lifetime = { 3, 4 }, speed = { 0.5, 1.2 }, size = 2.5, height = -1.5, direction = Enum.NormalId.Top, spread = 60 },
			{ kind = "spot", color = Color3.fromRGB(170, 235, 255), range = 24, angle = 35, height = 16, brightness = 2, flicker = 0.1 },
		},
	},
}

-- ===================== 3. PER-WEAPON OVERRIDES =====================
AbilityConfig.overrides = {}

-- ===================== LOOKUPS =====================
local merged: { [string]: any } = {}

function AbilityConfig.get(abilityId: string?, weaponId: string?): any?
	local base = abilityId and AbilityConfig.abilities[abilityId]
	if not base then
		return nil
	end
	local override = weaponId and AbilityConfig.overrides[weaponId] and AbilityConfig.overrides[weaponId][abilityId]
	if not override then
		return base
	end
	local cacheKey = weaponId .. "/" .. abilityId
	if not merged[cacheKey] then
		local copy = table.clone(base)
		for k, v in pairs(override) do
			copy[k] = v
		end
		merged[cacheKey] = copy
	end
	return merged[cacheKey]
end

local bound: { [string]: any } = {}

--- The abilities a weapon item can cast, in the order the item lists them. config.key is the weapon's binding.
function AbilityConfig.forWeapon(weaponId: string?): { any }
	local out = {}
	local WeaponRegistry = require(script.Parent:WaitForChild("WeaponRegistry")) :: any
	local weapon = weaponId and WeaponRegistry.get(weaponId)
	for _, entry in ipairs(weapon and weapon.abilities or {}) do
		local ability = entry.ability and AbilityConfig.get(entry.ability, weaponId)
		if ability then
			if entry.key and entry.key ~= ability.key then
				local cacheKey = weaponId .. "/" .. entry.ability .. "@" .. entry.key
				if not bound[cacheKey] then
					local copy = table.clone(ability)
					copy.key = entry.key
					bound[cacheKey] = copy
				end
				ability = bound[cacheKey]
			end
			table.insert(out, { id = entry.ability, config = ability })
		end
	end
	return out
end

function AbilityConfig.byKey(weaponId: string?, keyName: string): (any?, string?)
	for _, entry in ipairs(AbilityConfig.forWeapon(weaponId)) do
		if entry.config.key == keyName then
			return entry.config, entry.id
		end
	end
	return nil, nil
end

--- Logs every problem in the weapon -> ability links (bad key, duplicate key on one weapon, unknown ability id).
--- Returns the number of problems.
function AbilityConfig.validate(): number
	local WeaponRegistry = require(script.Parent:WaitForChild("WeaponRegistry")) :: any
	local problems = 0
	for weaponId, weapon in pairs(WeaponRegistry.Weapons) do
		local used: { [string]: string } = {}
		for _, entry in ipairs(weapon.abilities or {}) do
			if entry.ability then
				local library = AbilityConfig.abilities[entry.ability]
				local key = entry.key or (library and library.key)
				if not library then
					problems += 1
					warn(string.format("[AbilityConfig] %s lists unknown ability '%s'", weaponId, entry.ability))
				elseif not (key and AbilityConfig.keys[key]) then
					problems += 1
					warn(string.format("[AbilityConfig] %s: ability '%s' has key '%s', not one of RMB / Z / X / C / V", weaponId, entry.ability, tostring(key)))
				elseif used[key] then
					problems += 1
					warn(string.format("[AbilityConfig] %s: key %s is bound twice ('%s' and '%s')", weaponId, key, used[key], entry.ability))
				else
					used[key] = entry.ability
				end
			end
		end
	end
	return problems
end

function AbilityConfig.animationKeys(): { string }
	local out, seen = {}, {}
	for _, ability in pairs(AbilityConfig.abilities) do
		local key = ability.animation
		if key and key ~= "" and not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	return out
end

return AbilityConfig
