--[[
	Items/Defs/Weapons (category = weapon)

	One entry per weapon. `Damage` is the weapon's own damage; combat scales it
	with the player's Strength. Solar Blade is the reference entry: it uses every
	tooltip section (tags, description, stats, abilities, footer, click hint).
--]]

return {

	solar_blade = {
		name = "Solar Blade",
		description = "A blade forged in the heart of a dying star.",
		rarity = 4,
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.2, knockback = 15, range = 20 },
		stats = {
			Damage = 250,
			Strength = 50,
			Defense = 20,
			CritChance = 10,
			CritIncrease = 50,
		},
		abilities = {
			{
				name = "Solar Slash",
				key = "LMB",
				text = 'Slash with embers of sol dealing <font color="#FF5555" family="rbxassetid://12187371840">75 Damage</font>.',
			},
			{
				name = "Overload",
				key = "HOLD RMB",
				cooldown = 10,
				text = 'Release a cloud of embers rain around you dealing <font color="#FF5555" family="rbxassetid://12187371840">500 Damage</font> every 3 seconds, to any enemy within <font color="#55FF55" family="rbxassetid://12187371840">50 studs</font>.',
			},
		},
		footer = "All projectiles and stats scale with your power-ups and modifications.",
	},

	sword_basic = {
		name = "Iron Sword",
		description = "A reliable melee weapon.",
		rarity = 1,
		toolName = "SwordBasic",
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.2, knockback = 15, range = 20 },
		stats = { Damage = 15, CritChance = 10, CritIncrease = 50 },
		abilities = {
			{ name = "Slash Combo", text = "Every 3rd hit deals <font color=\"#FF5555\">+50% damage</font>." },
		},
	},

	sword_legendary = {
		name = "Excalibur",
		description = "A legendary sword imbued with holy power.",
		rarity = 4,
		toolName = "SwordLegendary",
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.0, knockback = 20, range = 22 },
		stats = { Damage = 25, CritChance = 25, CritIncrease = 100 },
		abilities = {
			{ name = "Holy Burst", text = "Heals <font color=\"#55FF55\">10%</font> of damage dealt." },
			{
				name = "Divine Strike",
				key = "Q",
				cooldown = 5,
				damage = 50,
				text = "Unleash a divine slash, dealing <font color=\"#FF5555\">2x damage</font> in a cone.",
			},
		},
	},

	spear_basic = {
		name = "Wooden Spear",
		description = "A nimble polearm weapon.",
		rarity = 0,
		toolName = "SpearBasic",
		skillTag = "Combat",
		weapon = { weaponType = "spear", attackSpeed = 1.8, knockback = 10, range = 28 },
		stats = { Damage = 12, CritChance = 8, CritIncrease = 30 },
		abilities = {
			{ name = "Quick Thrust", text = "Increased attack speed." },
		},
	},

	bow_basic = {
		name = "Wooden Bow",
		description = "A ranged weapon for hunters.",
		rarity = 0,
		toolName = "BowBasic",
		skillTag = "Combat",
		weapon = { weaponType = "bow", attackSpeed = 0.8, knockback = 5, range = 100 },
		stats = { Damage = 10, CritChance = 15, CritIncrease = 80 },
		abilities = {
			{
				name = "Pierce Shot",
				key = "T",
				cooldown = 3,
				damage = 30,
				text = "Fire an arrow that pierces enemies.",
			},
		},
	},

	staff_basic = {
		name = "Apprentice Staff",
		description = "A magical focus for casting spells.",
		rarity = 1,
		toolName = "StaffBasic",
		skillTag = "Combat",
		weapon = { weaponType = "staff", attackSpeed = 1.0, knockback = 8, range = 50 },
		stats = { Damage = 8, CritChance = 5, CritIncrease = 100 },
		abilities = {
			{ name = "Magic Missile", key = "Q", cooldown = 1.5, damage = 20, text = "Cast a magic missile." },
			{ name = "Mana Shield", key = "R", cooldown = 8, damage = 0, text = "Create a protective barrier." },
		},
	},
}
