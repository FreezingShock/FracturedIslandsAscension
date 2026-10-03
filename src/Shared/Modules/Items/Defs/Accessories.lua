--[[
	Items/Defs/Accessories (category = accessory)

	Slot = Cloak | Gloves | Necklace | Belt.
	A stat can be a flat number or a multiplier: Strength = { mult = 0.05 } is +5%.
--]]

return {

	lucky_cloak = {
		name = "Lucky Cloak",
		description = "Fortune favors whoever wears it.",
		rarity = 2,
		slot = "Cloak",
		stats = { MagicFind = 10 },
	},

	swift_gloves = {
		name = "Swift Gloves",
		description = "Your fingers have never felt so quick.",
		rarity = 2,
		slot = "Gloves",
		stats = { PressSpeed = 0.2 },
	},

	sapphire_amulet = {
		name = "Sapphire Amulet",
		description = "A cold gem that sharpens your aim.",
		rarity = 3,
		slot = "Necklace",
		stats = { CritChance = 5, Strength = { mult = 0.05 } },
	},

	warriors_belt = {
		name = "Warrior's Belt",
		description = "Cinched tight for the long fight ahead.",
		rarity = 1,
		slot = "Belt",
		stats = { Strength = 10 },
	},
}
