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
	maxEmitters = 6, -- particle emitters alive at once (embers / snow); past it a zone shows only its ground ring
	maxParts = 60, -- effect parts alive at once
	poolSize = 14, -- parts kept ready per kind
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
	frost_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
}

-- Visuals (AbilityController builds them from these numbers).
--   nova = a flat ring that expands to the shape's radius      zone = embers drifting over the shape's area for the zone's duration
--   frost = a ground ring + snow over the area for the zone's duration (pinned where it was cast)
--   dash = a streak from where the caster started to where it ended      chain = jagged bolts caster -> target -> target ...
AbilityConfig.fx = {
	holy_nova = {
		kind = "nova",
		color = Color3.fromRGB(255, 225, 120),
		time = 0.45,
		height = 0.6,
	},
	overload = {
		kind = "zone",
		color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 70, 20)),
		rate = 90,
		speed = 8,
		size = 0.5,
	},
	blink = {
		kind = "dash",
		color = Color3.fromRGB(255, 225, 110),
		time = 0.35,
		width = 3,
		burst = Color3.fromRGB(255, 245, 190),
	},
	chain = {
		kind = "chain",
		color = Color3.fromRGB(150, 210, 255),
		time = 0.3,
		width = 0.5,
		segments = 5, -- jagged pieces per link
		jitter = 1.6, -- studs of sideways wobble
		linkDelay = 0.06, -- seconds between a link and the next
	},
	thunder_clap = {
		kind = "nova",
		color = Color3.fromRGB(150, 210, 255),
		time = 0.4,
		height = 0.6,
	},
	frost = {
		kind = "frost",
		color = Color3.fromRGB(170, 235, 255),
		time = 0.5, -- the ring spreads out over this long
		rate = 70,
		speed = 5,
		size = 0.45,
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
