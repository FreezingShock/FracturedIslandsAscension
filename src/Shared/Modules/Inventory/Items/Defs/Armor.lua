--[[
	Items/Defs/Armor (category = armor)

	Every armor piece needs `slot` = Helmet | Chestplate | Leggings | Boots.
	`stats` keys are ProfileConfig attribute keys; they are added to the
	player's attributes while the piece is equipped.
--]]

return {

	iron_helmet = {
		name = "Iron Helmet",
		description = "Dented, but it will keep your head attached.",
		rarity = 1,
		slot = "Helmet",
		stats = { Health = 20, Defense = 10 },
	},

	iron_chestplate = {
		name = "Iron Chestplate",
		description = "Heavy plating for the brave and the broke.",
		rarity = 1,
		slot = "Chestplate",
		stats = { Defense = 30, Strength = 15 },
	},

	iron_leggings = {
		name = "Iron Leggings",
		description = "Stiff at the knees, sturdy everywhere else.",
		rarity = 1,
		slot = "Leggings",
		stats = { Defense = 20 },
	},

	iron_boots = {
		name = "Iron Boots",
		description = "Clanks with every step.",
		rarity = 1,
		slot = "Boots",
		stats = { Defense = 10, Speed = 1 },
	},

	solar_crown = {
		name = "Solar Crown",
		description = "Worn by those who walk beside the sun.",
		rarity = 4,
		slot = "Helmet",
		skillTag = "Combat",
		stats = { Health = 100, Defense = 40, Strength = 25 },
		abilities = {
			{
				name = "Solar Aura",
				text = 'Nearby enemies burn for <font color="#FF5555" family="rbxassetid://12187371840">10 Damage</font> every second.',
			},
		},
		footer = "Set bonuses coming soon.",
	},

	golden_chestplate = {
		name = "Golden Chestplate",
		description = "Shiny, soft, and surprisingly stubborn.",
		rarity = 2,
		slot = "Chestplate",
		stats = { Defense = 45, Health = 30 },
	},

	golden_leggings = {
		name = "Golden Leggings",
		description = "A king's idea of practical.",
		rarity = 2,
		slot = "Leggings",
		stats = { Defense = 30, Health = 20 },
	},

	golden_boots = {
		name = "Golden Boots",
		description = "Every step announces you.",
		rarity = 2,
		slot = "Boots",
		stats = { Defense = 15, Speed = 2 },
	},

	diamond_helmet = {
		name = "Diamond Helmet",
		description = "Clear-headed protection.",
		rarity = 3,
		slot = "Helmet",
		stats = { Defense = 40, Health = 40, Strength = 10 },
	},
}
