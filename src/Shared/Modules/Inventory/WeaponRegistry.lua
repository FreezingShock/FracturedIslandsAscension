-- ============================================================
--  WeaponRegistry (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Combat-facing VIEW of the weapons defined in Items/Defs/Weapons.
--  Weapons are NOT defined here any more: add or edit them in Defs/Weapons and
--  this module re-derives the combat fields from the item's stats:
--
--     baseDamage     = stats.Damage
--     critChance     = stats.CritChance / 100        (0-1)
--     critMultiplier = 1 + stats.CritIncrease / 100
--     attackSpeed, knockback, range, weaponType = item.weapon
--
--  API (unchanged):
--    WeaponRegistry.get(weaponId) → weapon config or nil
--    WeaponRegistry.exists(weaponId) → bool
--    WeaponRegistry.getByToolName(toolName) → weapon config or nil
--    WeaponRegistry.getRarityScaling(rarity) → stat multiplier
--    WeaponRegistry.getScaledDamage(baseDamage, rarity)
-- ============================================================

local Items = require(script.Parent:WaitForChild("Items"))

local WeaponRegistry = {}

-- Damage multiplier by rarity tier (applied by WeaponManager on top of baseDamage).
WeaponRegistry.RarityScaling = {
	[0] = 1.0,
	[1] = 1.15,
	[2] = 1.35,
	[3] = 1.65,
	[4] = 2.0,
	[5] = 2.5,
}

WeaponRegistry.Weapons = {}
WeaponRegistry._toolNameToWeapon = {}

local function plainText(text: string?): string
	local stripped = (text or ""):gsub("<[^>]+>", "")
	return stripped
end

for _, def in ipairs(Items.list("weapon")) do
	local stats = def.stats or {}
	local weapon = def.weapon or {}

	local abilities = {}
	for _, ability in ipairs(def.abilities or {}) do
		table.insert(abilities, {
			name = ability.name,
			type = ability.type,
			cooldown = ability.cooldown,
			key = ability.key,
			damage = ability.damage,
			effect = plainText(ability.text),
		})
	end

	local config = {
		id = def.id,
		displayName = def.displayName,
		description = def.description,
		rarity = def.rarity,
		toolName = def.toolName,
		weaponType = weapon.weaponType,

		baseDamage = stats.Damage or 0,
		critChance = (type(stats.CritChance) == "number" and stats.CritChance or 0) / 100,
		critMultiplier = 1 + (type(stats.CritIncrease) == "number" and stats.CritIncrease or 0) / 100,
		attackSpeed = weapon.attackSpeed,
		knockback = weapon.knockback,
		range = weapon.range,

		abilities = abilities,
	}

	WeaponRegistry.Weapons[def.id] = config
	WeaponRegistry._toolNameToWeapon[def.toolName] = config
end

function WeaponRegistry.get(weaponId: string)
	return WeaponRegistry.Weapons[weaponId]
end

function WeaponRegistry.exists(weaponId: string): boolean
	return WeaponRegistry.Weapons[weaponId] ~= nil
end

function WeaponRegistry.getByToolName(toolName: string)
	return WeaponRegistry._toolNameToWeapon[toolName]
end

function WeaponRegistry.getRarityScaling(rarity: number): number
	return WeaponRegistry.RarityScaling[math.clamp(rarity or 0, 0, 5)] or 1.0
end

function WeaponRegistry.getScaledDamage(baseDamage: number, rarity: number): number
	return baseDamage * WeaponRegistry.getRarityScaling(rarity)
end

return WeaponRegistry
