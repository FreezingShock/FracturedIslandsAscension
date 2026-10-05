--[[
	AbilityConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Every weapon ability (the ones cast with a key, not the combo) is data in this file. Same layering as CombatConfig:

	1. LIBRARY    AbilityConfig.abilities[id]   what an ability is and does
	2. WEAPON     Items/Defs/Weapons: abilities = { { name, text, ability = "<id>", key, cooldown } }
	              `ability` links a weapon to a library entry (the key / cooldown there are only for the tooltip, keep them equal)
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
	  animation          CombatConfig.animations key played on the caster ("" / nil = none). A placeholder until published.
	  sound / fx         AbilityConfig.sounds / AbilityConfig.fx keys. Sounds with id "" are silent.

	Recipes
	  New ability ................ add a library entry, add `ability = "<id>"` to a weapon in Defs/Weapons.
	  Real animation ............. publish it, add it to CombatConfig.animations, set `animation = "<key>"`.
	  Real sound ................. put the id in AbilityConfig.sounds[...].id.
	  One weapon casts it cheaper  overrides[weaponId] = { [abilityId] = { manaCost = 30 } }.

	API
	  AbilityConfig.get(abilityId, weaponId?)    -> merged ability table (with .id) or nil
	  AbilityConfig.forWeapon(weaponId)          -> list of merged abilities the weapon can cast
	  AbilityConfig.byKey(weaponId, keyName)     -> the weapon's ability bound to that key, or nil
	  AbilityConfig.animationKeys()              -> every animation key used (for preloading)
--]]

local AbilityConfig = {}

AbilityConfig.maxZonesPerPlayer = 2 -- active zones one player may keep running (exploit / performance cap)
AbilityConfig.minPressGap = 0.15 -- seconds between two accepted presses of the same key

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
}

-- Sounds (3D, played at the caster). id = "" is silent until you upload one.
AbilityConfig.sounds = {
	overload_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
	holy_nova_cast = { id = "", volume = 0.9, pitch = { 0.95, 1.05 }, minDistance = 20, maxDistance = 120 },
}

-- Visuals (AbilityController builds them from these numbers).
--   nova = a flat ring that expands to the shape's radius      zone = embers drifting over the shape's area for the zone's duration
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

--- The abilities a weapon item can cast, in the order the item lists them.
function AbilityConfig.forWeapon(weaponId: string?): { any }
	local out = {}
	local WeaponRegistry = require(script.Parent:WaitForChild("WeaponRegistry")) :: any
	local weapon = weaponId and WeaponRegistry.get(weaponId)
	for _, entry in ipairs(weapon and weapon.abilities or {}) do
		local ability = entry.ability and AbilityConfig.get(entry.ability, weaponId)
		if ability then
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
