--[[
	CombatConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Everything animation- and combo-related for weapons lives here. Three layers, from "what plays" to "when":

	1. LIBRARY  CombatConfig.animations[key] = { id, priority, fade, looped, speed }
	   The ONLY place an animation id is written. `id = ""` means "not published yet": the slot plays nothing and the
	   rest of the combat loop still runs. priority: "Action" (default), "Movement", "Idle", "Core".

	2. TYPE     CombatConfig.<weaponType> = { combo numbers, steps = {...}, slots = {...} }
	   Every item whose item.weapon.weaponType matches uses it, so all five swords share CombatConfig.sword.
	     steps[i].animation   library key played on combo step i (+ duration / hitFrame / recovery timing)
	     slots[name]          library key played for a situation: "equip", "idle", or any name you invent
	                          (code plays a slot with CombatAnimator.playSlot(character, weaponType, name, weaponId))

	3. OVERRIDES  CombatConfig.overrides[weaponId] = { steps = { [stepIndex] = key }, slots = { [name] = key } }
	   One weapon gets its own animation for a step or situation; everything else falls back to the type.

	Recipes
	  Change an animation for ALL swords ..... edit its `id` in the library (one line).
	  Change which animation a step uses ..... edit steps[i].animation (or add a library entry and point at it).
	  New situation (sprint, block, hurt) .... add library entry, add slots.sprint = "<key>", call playSlot(..., "sprint").
	  One weapon with its own swing .......... overrides.sword_legendary = { steps = { [4] = "legendary_finisher" } }.
	  New weapon type (spear, bow, ...) ...... copy CombatConfig.sword, change weaponType, steps and slots.
	  Longer / shorter combo ................. add or remove entries in steps (the loop uses #steps).

	DAMAGE AND HIT DETECTION (server: DamageService; fired by WeaponManager at each step's hitFrame)
	  steps[i].reach        studs the swing reaches in front of the swinger (measured to the target's edge)
	  steps[i].arc          degrees of the cone in front of the swinger that can be hit (total width)
	  steps[i].damageMult   multiplier on this step's damage (the finisher hits hardest)
	  steps[i].knockback    horizontal push on the target (studs/second, scaled by its mass)
	  steps[i].maxTargets   how many targets one swing may hit (nearest first)
	  CombatConfig.damage   the formula numbers, see below
	  CombatConfig.hit      what a hit looks like (flash, damage number styles, rise / life)
	  CombatConfig.dummy    the training dummies (DummyService)

	FX AND SOUND (same layering: library -> type -> per-weapon override)
	  CombatConfig.sounds[key] = { id, volume, pitch = {min, max} }   id "" = silent; ids can be rbxassetid:// or rbxasset://
	  CombatConfig.fx[key]     = { trail = {...}, burst = {...} }      the swing trail ribbon and the spark burst
	  steps[i].sound / critSound      sound keys played when the swing HITS something (not on a miss): the normal one, or the
	                                  crit one when that hit was a crit (falls back to `sound` when no critSound)
	  steps[i].trail = { from, to }   seconds (at attack speed 1) the trail ribbon is visible
	  type.fx                          fx key every weapon of the type uses
	  type.slotSounds[name]            sound key for a situation ("equip", later "impact", ...)
	  overrides[weaponId].fx / .stepSounds[i] / .slotSounds[name]   one weapon with its own look or sound
	  The trail attaches itself to ANY weapon's Handle (blade axis and tip are detected), so future swords need no setup.

	API
	  CombatConfig.get(weaponType)                          -> type config or nil
	  CombatConfig.swingTime(step, attackSpeed)             -> seconds a swing locks the player for
	  CombatConfig.stepAnimation(type, stepIndex, weaponId, crash?) -> library entry or nil (crash slam first, override, then type)
	  CombatConfig.slotAnimation(type, slot, weaponId)      -> library entry or nil
	  CombatConfig.stepSound(type, stepIndex, weaponId, crit?) -> sound entry or nil
	  CombatConfig.slotSound(type, slot, weaponId)          -> sound entry or nil
	  CombatConfig.fxFor(type, weaponId)                    -> fx entry (and its key) or nil
	  CombatConfig.types()                                  -> list of weaponType strings that have a config
	  CombatConfig.libraryKeysFor(type)                     -> every library key a type can use (for preloading)

	Type fields
	  comboWindow               seconds after a swing ends in which the next click continues the combo (else step 1)
	  moveSpeedFactor           WalkSpeed multiplier while swinging
	  finisherMoveSpeedFactor   same for the last step of the combo
	  bufferTime                a click this close to the end of a swing is remembered and fires when it ends
	  holdToAttack              true = holding left click keeps swinging and the whole combo loops; each swing waits until the attack
	                            bar is FULL again (CombatConfig.chargeTime), unlike spam-clicking which swings as soon as the swing ends
	  steps[i].duration         animation length in seconds at attack speed 1
	  steps[i].hitFrame         seconds into the swing where damage will be applied (hook: WeaponManager.onSwingHit)
	  steps[i].recovery         extra seconds after the animation before the next swing may start
	The real swing time is (duration + recovery) / attackSpeed, attackSpeed coming from the weapon's definition.
--]]

local CombatConfig = {}

-- ===================== DAMAGE / HIT / DUMMY NUMBERS =====================
-- damage = (weapon Damage x rarity scaling + flatBase) x (1 + Strength x strengthScale) x step.damageMult
-- crit   = rolls against CritChance (percent, capped at critChanceCap); a crit multiplies by 1 + (critBase + CritIncrease) x critScale
-- Strength / CritChance / CritIncrease = the player's stat chain value + the held weapon's own stat of that name.
CombatConfig.damage = {
	flatBase = 5,
	strengthScale = 0.01, -- +1% per Strength
	critBase = 50, -- every crit already deals +50% before CritIncrease
	critScale = 0.01, -- +1% per CritIncrease point
	critChanceCap = 100,
	verticalTolerance = 7, -- studs above / below the swinger a target may be and still be hit
	lineOfSight = true, -- a wall between swinger and target blocks the hit
	aoeMult = 0.33, -- the damage share of anything hit by an AoE rather than directly (Crash hit AoE; future AoEs)
}

-- CRASH HIT: click while airborne and the swing is held back until you land (movement is never locked in the air);
-- on landing it plays and hits as a Crash. The server decides all of it (WeaponManager.Click / TrySwing).
--   step             combo step whose timings (and animation, when no dedicated one) a crash uses: "last" or a number
--   animation        key in CombatConfig.animations for a dedicated ground-slam; an empty id = the step's own animation
--   queueSeconds     a click in the air waits at most this long for the landing, then is dropped
--   damageMult       x final damage, after the crit multiplier (a crash can also crit)
--   aoeRadius        studs around the primary target (the nearest enemy in the swing's cone); others in it take the AoE share
--   aoeMaxTargets / aoeKnockbackMult   how many others are hit, and their knockback relative to the swing's
-- The AoE damage share is CombatConfig.damage.aoeMult (33%, the shared rule for any AoE). Look: hit.crash below +
-- EnemyConfig.fx.hit_crash.
CombatConfig.crash = {
	step = "last",
	animation = "sword_crash",
	sounds = { "sword_crash", "sword_crash2", "sword_crash3", "sword_crash4" }, -- CombatConfig.sounds keys; one picked at random (equal chance) per crash hit
	-- the landing look (CombatFX.crashImpact), at the ground under the hit: two shockwave rings, a dust cloud and a spark spray
	fx = {
		rings = {
			{ color = Color3.fromRGB(255, 244, 215), from = 2, to = 15, time = 0.42, thickness = 0.25 },
			{ color = Color3.fromRGB(255, 185, 90), from = 4, to = 24, time = 0.6, thickness = 0.12 },
		},
		dust = { texture = "rbxasset://textures/particles/smoke_main.dds", color = Color3.fromRGB(225, 210, 185), count = 22, life = { 0.6, 1.1 }, speed = { 6, 16 }, spread = 85, size = { 2.4, 5.5 }, transparency = 0.4, accel = Vector3.new(0, -8, 0), drag = 3 },
		sparks = { texture = "rbxasset://textures/particles/sparkles_main.dds", color = Color3.fromRGB(255, 232, 160), count = 30, life = { 0.25, 0.6 }, speed = { 28, 62 }, spread = 70, size = { 0.9, 0 }, accel = Vector3.new(0, -70, 0), light = 1 },
	},
	queueSeconds = 1.5,
	damageMult = 1.25,
	aoeRadius = 8,
	aoeMaxTargets = 8,
	aoeKnockbackMult = 0.5,
}

-- SWING TIMING (Minecraft-style charge): the time since your previous swing picks a tier. `upTo` is seconds at attack speed 1
-- (divided by the weapon's attackSpeed); the last tier has no upTo. `mult` multiplies the damage of the swing and ONLY
-- the swing (Crit, Crash and Full are separate flags with their own multipliers); `full = true` marks a Full hit (bar
-- full); `color` tints the HUD bar. A swing after a long rest is Full.
CombatConfig.timing = {
	tiers = {
		{ upTo = 0.6, mult = 0.8, color = "#AAAAAA" },
		{ upTo = 1.2, mult = 1.0, color = "#FFFF55" },
		{ mult = 1.2, full = true, color = "#FFAA00" },
	},
}

CombatConfig.hit = {
	flashColor = Color3.fromRGB(255, 255, 255), -- Highlight fill on the target
	flashTime = 0.18,
	numberRise = 3.5, -- studs a damage number floats up
	numberTime = 0.9, -- seconds it lives
	numberSpread = 1.2, -- random sideways offset so stacked hits do not overlap
	normal = { color = "#FFFFFF", stroke = "#555555", scale = 1 },
	-- crit: blue number with the Crit Increase stat icon behind it (template child CritBadge; sheet cell { 3, 0 } of the
	-- stat spritesheet, 170px cells = ProfileConfig / TooltipModule Style.SPRITE), darker blue and a little transparent
	crit = {
		color = "#5555FF", stroke = "#0000AA", scale = 1.45,
		badge = { color = "#0000AA", transparency = 0.45 },
	},
	-- crash: the crit layout in red (it wins over the blue crit when a hit is both)
	crash = {
		color = "#FF5555", stroke = "#AA0000", scale = 1.45, prefix = "Crash",
		badge = { color = "#AA0000", transparency = 0.45 },
	},
	-- full: a hit with the charge bar full (independent of crit / crash): gold number with a star; when it is also a
	-- crit or crash the stronger style keeps its colour and gets the star in front (`star`)
	full = { color = "#FFD700", stroke = "#AA5500", scale = 1.15 },
	star = "★",
	-- taken: damage a player takes, floating over them
	taken = { color = "#FF5555", stroke = "#550000", scale = 1.25 },
	aoeScale = 0.75, -- AoE hits (Crash splash) are drawn smaller
	stackOffset = 0.9, -- studs each number made on the same target within stackWindow is lifted, so they never overlap
	stackWindow = 0.45,
	popFrom = 0.55, -- a number pops in from this scale (of its final size) with a small overshoot
	popTime = 0.16,
}

CombatConfig.dummy = {
	health = 1000,
	respawnSeconds = 3,
	returnHomeAfter = 2, -- seconds without a hit before a knocked-away dummy walks back to its marker
}

-- ===================== 1. LIBRARY =====================
-- Paste the published animation ids here as "rbxassetid://123". Keys are free-form; steps and slots refer to them.
CombatConfig.animations = {
	-- sword combo (authored in Blender, R6; see assets/blender/combat/)
	sword_combo1 = { id = "rbxassetid://94936991830299", priority = "Action", fade = 0.06 }, -- slash down-left
	sword_combo2 = { id = "rbxassetid://121132140735511", priority = "Action", fade = 0.06 }, -- slash down-right
	sword_combo3 = { id = "rbxassetid://107854592014324", priority = "Action", fade = 0.06 }, -- fence jab
	sword_combo4 = { id = "rbxassetid://92264070348960", priority = "Action", fade = 0.06 }, -- overhead slash

	-- the Crash hit's dedicated ground-slam (CombatConfig.crash.animation); empty = the crash uses the last combo step's animation
	sword_crash = { id = "", priority = "Action", fade = 0.06 },

	-- situations (no animation yet; fill in an id and it plays)
	sword_equip = { id = "", priority = "Action", fade = 0.1 },
	sword_idle = { id = "", priority = "Idle", fade = 0.2, looped = true },
}

-- Sounds. Defaults are Roblox's own bundled sword sounds (free, nothing to upload). To use your own audio, upload it
-- to Creator Hub and put "rbxassetid://<id>" here. Please keep to audio you own or that is licensed for games.
CombatConfig.sounds = {
	-- one attack sound per combo step. They are 3D sounds on the sword: minDistance = full volume within that many
	-- studs, silent beyond maxDistance, so anyone nearby hears them from the blade.
	sword_atk1 = { id = "rbxassetid://87733479853952", volume = 0.8, pitch = { 0.97, 1.03 }, minDistance = 12, maxDistance = 90 },
	sword_atk2 = { id = "rbxassetid://83101665211645", volume = 0.8, pitch = { 0.97, 1.03 }, minDistance = 12, maxDistance = 90 },
	sword_atk3 = { id = "rbxassetid://109876336137523", volume = 0.8, pitch = { 0.97, 1.03 }, minDistance = 12, maxDistance = 90 },
	sword_atk4 = { id = "rbxassetid://120264723935510", volume = 0.9, pitch = { 0.97, 1.03 }, minDistance = 14, maxDistance = 100 },
	-- the same four steps when the hit is a crit (they replace the normal one; steps[i].critSound)
	sword_crit1 = { id = "rbxassetid://97881726980530", volume = 0.9, pitch = { 0.97, 1.03 }, minDistance = 14, maxDistance = 100 },
	sword_crit2 = { id = "rbxassetid://82383170249566", volume = 0.9, pitch = { 0.97, 1.03 }, minDistance = 14, maxDistance = 100 },
	sword_crit3 = { id = "rbxassetid://127769468592171", volume = 0.9, pitch = { 0.97, 1.03 }, minDistance = 14, maxDistance = 100 },
	sword_crit4 = { id = "rbxassetid://90751268932745", volume = 1.0, pitch = { 0.97, 1.03 }, minDistance = 16, maxDistance = 110 },
	-- the Crash hit (a click in the air that lands): replaces the step's sound, crit or not. One is picked at random per hit
	-- from CombatConfig.crash.sounds
	sword_crash = { id = "rbxassetid://119510799018421", volume = 1.0, pitch = { 0.95, 1.05 }, minDistance = 16, maxDistance = 110 },
	sword_crash2 = { id = "rbxassetid://133601296259995", volume = 1.0, pitch = { 0.95, 1.05 }, minDistance = 16, maxDistance = 110 },
	sword_crash3 = { id = "rbxassetid://81940494770825", volume = 1.0, pitch = { 0.95, 1.05 }, minDistance = 16, maxDistance = 110 },
	sword_crash4 = { id = "rbxassetid://134113758425541", volume = 1.0, pitch = { 0.95, 1.05 }, minDistance = 16, maxDistance = 110 },
	sword_equip = { id = "rbxasset://sounds/unsheath.wav", volume = 0.45, pitch = { 0.95, 1.05 } },
	sword_impact = { id = "", volume = 0.7, pitch = { 0.9, 1.1 } }, -- reserved for the damage system
}

-- Visual FX. trail = ribbon behind the blade; burst = sparks thrown off the tip at the hit frame.
CombatConfig.fx = {
	sword_default = {
		trail = {
			color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 235, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 170, 255)),
			}),
			lifetime = 0.22, -- seconds a point of the ribbon lives
			lightEmission = 0.85,
			minLength = 0.02,
			bladeFrom = 0.35, -- ribbon spans the blade from this fraction (0 = pommel, 1 = tip) out to the tip
			transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
			width = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) }),
		},
		burst = {
			count = 7,
			color = ColorSequence.new(Color3.fromRGB(210, 245, 255), Color3.fromRGB(110, 190, 255)),
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) }),
			lifetime = NumberRange.new(0.25, 0.45),
			speed = NumberRange.new(6, 14),
			lightEmission = 1,
		},
	},
}

-- ===================== 2. WEAPON TYPES =====================
CombatConfig.sword = {
	weaponType = "sword",
	comboWindow = 0.7,
	moveSpeedFactor = 0.6,
	finisherMoveSpeedFactor = 0.4,
	bufferTime = 0.35,
	holdToAttack = true,
	steps = {
		{ name = "SlashDownLeft", animation = "sword_combo1", duration = 0.50, hitFrame = 0.20, recovery = 0.05,
			reach = 9, arc = 130, damageMult = 1.0, knockback = 14, maxTargets = 4,
			sound = "sword_atk1", critSound = "sword_crit1", trail = { from = 0.10, to = 0.36 } },
		{ name = "SlashDownRight", animation = "sword_combo2", duration = 0.50, hitFrame = 0.20, recovery = 0.05,
			reach = 9, arc = 130, damageMult = 1.0, knockback = 14, maxTargets = 4,
			sound = "sword_atk2", critSound = "sword_crit2", trail = { from = 0.10, to = 0.36 } },
		{ name = "Jab", animation = "sword_combo3", duration = 0.47, hitFrame = 0.17, recovery = 0.05,
			reach = 12, arc = 40, damageMult = 1.1, knockback = 20, maxTargets = 2,
			sound = "sword_atk3", critSound = "sword_crit3", trail = { from = 0.12, to = 0.30 } },
		{ name = "OverheadSlash", animation = "sword_combo4", duration = 0.70, hitFrame = 0.32, recovery = 0.30,
			reach = 10, arc = 150, damageMult = 1.5, knockback = 30, maxTargets = 6,
			sound = "sword_atk4", critSound = "sword_crit4", trail = { from = 0.18, to = 0.46 } },
	},
	slots = {
		equip = "sword_equip",
		idle = "sword_idle",
	},
	fx = "sword_default",
	slotSounds = {
		equip = "sword_equip",
		impact = "sword_impact",
	},
}

-- ===================== 3. PER-WEAPON OVERRIDES =====================
-- [weaponId] = { steps = { [stepIndex] = "libraryKey" }, slots = { [slotName] = "libraryKey" } }
-- Extra per-weapon keys: fx = "<fx key>", stepSounds = { [stepIndex] = "<sound key>" }, slotSounds = { [name] = "<sound key>" }
CombatConfig.overrides = {}

-- ===================== LOOKUPS =====================
function CombatConfig.get(weaponType: string?): any?
	if not weaponType then
		return nil
	end
	local cfg = (CombatConfig :: any)[weaponType]
	if type(cfg) == "table" and cfg.steps then
		return cfg
	end
	return nil
end

function CombatConfig.types(): { string }
	local out = {}
	for key, value in pairs(CombatConfig :: any) do
		if type(value) == "table" and value.steps and value.weaponType == key then
			table.insert(out, key)
		end
	end
	return out
end

--- Seconds a swing locks the player for (animation + recovery, scaled by attack speed).
function CombatConfig.swingTime(step: any, attackSpeed: number?): number
	return (step.duration + step.recovery) / math.max(0.5, attackSpeed or 1)
end

local function entryOf(key: string?): any?
	if not key or key == "" then
		return nil
	end
	return CombatConfig.animations[key]
end

function CombatConfig.stepAnimation(weaponType: string?, stepIndex: number, weaponId: string?, crash: boolean?): any?
	if crash then
		local slam = entryOf(CombatConfig.crash.animation)
		if slam and slam.id and slam.id ~= "" then
			return slam, CombatConfig.crash.animation
		end
	end
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.steps and override.steps[stepIndex]
	if not key then
		local cfg = CombatConfig.get(weaponType)
		local step = cfg and cfg.steps[stepIndex]
		key = step and step.animation
	end
	return entryOf(key), key
end

function CombatConfig.slotAnimation(weaponType: string?, slot: string, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.slots and override.slots[slot]
	if not key then
		local cfg = CombatConfig.get(weaponType)
		key = cfg and cfg.slots and cfg.slots[slot]
	end
	return entryOf(key), key
end

local function soundEntry(key: string?): any?
	if not key or key == "" then
		return nil
	end
	local entry = CombatConfig.sounds[key]
	if entry and entry.id and entry.id ~= "" then
		return entry
	end
	return nil
end

function CombatConfig.stepSound(weaponType: string?, stepIndex: number, weaponId: string?, crit: boolean?, crash: boolean?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key
	if crash then
		local pool = CombatConfig.crash.sounds
		key = pool[math.random(#pool)]
	elseif crit then
		key = override and override.stepCritSounds and override.stepCritSounds[stepIndex]
		if not key then
			local cfg = CombatConfig.get(weaponType)
			local step = cfg and cfg.steps[stepIndex]
			key = step and step.critSound
		end
	end
	if not key then
		key = override and override.stepSounds and override.stepSounds[stepIndex]
	end
	if not key then
		local cfg = CombatConfig.get(weaponType)
		local step = cfg and cfg.steps[stepIndex]
		key = step and step.sound
	end
	return soundEntry(key), key
end

function CombatConfig.slotSound(weaponType: string?, slot: string, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.slotSounds and override.slotSounds[slot]
	if not key then
		local cfg = CombatConfig.get(weaponType)
		key = cfg and cfg.slotSounds and cfg.slotSounds[slot]
	end
	return soundEntry(key), key
end

function CombatConfig.fxFor(weaponType: string?, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.fx
	if not key then
		local cfg = CombatConfig.get(weaponType)
		key = cfg and cfg.fx
	end
	return key and CombatConfig.fx[key], key
end

function CombatConfig.libraryKeysFor(weaponType: string): { string }
	local cfg = CombatConfig.get(weaponType)
	local seen, out = {}, {}
	local function add(key)
		if key and key ~= "" and not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	if cfg then
		for _, step in ipairs(cfg.steps) do
			add(step.animation)
		end
		for _, key in pairs(cfg.slots or {}) do
			add(key)
		end
	end
	for _, override in pairs(CombatConfig.overrides) do
		for _, key in pairs(override.steps or {}) do
			add(key)
		end
		for _, key in pairs(override.slots or {}) do
			add(key)
		end
	end
	return out
end

--- The timing tier for a swing made `sinceLast` seconds after the previous one: { mult, full, color, index }.
function CombatConfig.timingTier(sinceLast: number, attackSpeed: number?): any
	local speed = math.max(0.5, attackSpeed or 1)
	local tiers = CombatConfig.timing.tiers
	for i, tier in ipairs(tiers) do
		if not tier.upTo or sinceLast < tier.upTo / speed then
			return { mult = tier.mult, full = tier.full == true, color = tier.color, index = i }
		end
	end
	local last = tiers[#tiers]
	return { mult = last.mult, full = last.full == true, color = last.color, index = #tiers }
end

--- Seconds after a swing ends in which the next swing still continues the combo. A held button waits for the full charge bar, so for
--- holdToAttack weapons the window is at least the time the bar needs after the swing (+ a margin): the combo never drops while held.
function CombatConfig.comboWindowFor(typeConfig: any, swingTime: number, attackSpeed: number?): number
	local window = typeConfig.comboWindow
	if typeConfig.holdToAttack then
		window = math.max(window, CombatConfig.chargeTime(attackSpeed) - swingTime + 0.35)
	end
	return window
end

--- Seconds of rest at `attackSpeed` for the charge bar to be full (where the last tier starts).
function CombatConfig.chargeTime(attackSpeed: number?): number
	local tiers = CombatConfig.timing.tiers
	local boundary = tiers[math.max(1, #tiers - 1)].upTo or 0
	return boundary / math.max(0.5, attackSpeed or 1)
end

return CombatConfig
