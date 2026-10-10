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
				ability = "overload", -- AbilityConfig library entry (cost, shape, damage, zone)
				key = "RMB",
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
				name = "Holy Nova",
				ability = "holy_nova", -- AbilityConfig library entry
				key = "Z",
				cooldown = 6,
				text = "Unleash a burst of holy light around you, dealing <font color=\"#FF5555\">300% damage</font> to every enemy within <font color=\"#55FF55\">18 studs</font> and knocking them back.",
			},
		},
	},

	blink_blade = {
		name = "Blink Blade",
		description = "Cuts the space between you and your target.",
		rarity = 2,
		toolName = "BlinkBlade",
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.4, knockback = 12, range = 20 },
		stats = { Damage = 80, Strength = 15, CritChance = 20, CritIncrease = 50 },
		abilities = {
			{
				name = "Blink Dash",
				ability = "blink_dash", -- AbilityConfig library entry
				key = "RMB",
				cooldown = 5,
				text = 'Dash <font color="#55FF55" family="rbxassetid://12187371840">22 studs</font> forward, slicing every enemy on the way for <font color="#FF5555" family="rbxassetid://12187371840">220% damage</font>.',
			},
		},
	},

	stormcaller = {
		name = "Stormcaller",
		description = "The sky answers when it is swung.",
		rarity = 3,
		toolName = "Stormcaller",
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.1, knockback = 15, range = 22 },
		stats = { Damage = 160, Strength = 30, CritChance = 12, CritIncrease = 70 },
		abilities = {
			{
				name = "Chain Lightning",
				ability = "chain_lightning",
				key = "RMB",
				cooldown = 7,
				text = 'Strike the nearest enemy for <font color="#FF5555" family="rbxassetid://12187371840">200% damage</font>, then jump to <font color="#55FF55" family="rbxassetid://12187371840">4 more</font> enemies nearby, each hit 20% weaker.',
			},
			{
				name = "Thunder Clap",
				ability = "thunder_clap",
				key = "Z",
				cooldown = 9,
				text = 'Shock every enemy within <font color="#55FF55" family="rbxassetid://12187371840">14 studs</font> for <font color="#FF5555" family="rbxassetid://12187371840">150% damage</font>, slowing and burning them.',
			},
		},
	},

	frostbrand = {
		name = "Frostbrand",
		description = "Cold enough to stop a charge.",
		rarity = 2,
		toolName = "Frostbrand",
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.2, knockback = 15, range = 20 },
		stats = { Damage = 70, Strength = 20, Defense = 15, CritChance = 8, CritIncrease = 50 },
		abilities = {
			{
				name = "Frost Nova",
				ability = "frost_nova",
				key = "RMB",
				cooldown = 12,
				text = 'Freeze the ground in <font color="#55FF55" family="rbxassetid://12187371840">20 studs</font> for 6 seconds, hitting enemies inside every 1.5 seconds for <font color="#FF5555" family="rbxassetid://12187371840">120% damage</font> and slowing them.',
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

	-- Basic swords (Common). Iron is sword_basic above.
	wood_sword = {
		name = "Wood Sword",
		description = "A plain sword cut from timber.",
		rarity = 0,
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.2, knockback = 12, range = 20 },
		stats = { Damage = 6, CritChance = 5, CritIncrease = 50 },
	},

	stone_sword = {
		name = "Stone Sword",
		description = "Chipped stone lashed to a wooden grip.",
		rarity = 0,
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.2, knockback = 13, range = 20 },
		stats = { Damage = 10, CritChance = 8, CritIncrease = 50 },
	},

	gold_sword = {
		name = "Gold Sword",
		description = "Soft gold that swings quickly but dulls fast.",
		rarity = 0,
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.5, knockback = 12, range = 20 },
		stats = { Damage = 18, CritChance = 12, CritIncrease = 50 },
	},

	diamond_sword = {
		name = "Diamond Sword",
		description = "Hard-cut diamond, the best plain blade you can make.",
		rarity = 0,
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.2, knockback = 15, range = 20 },
		stats = { Damage = 24, CritChance = 15, CritIncrease = 60 },
	},

	-- Unique weapons. Each has one ability with its own mechanic (see AbilityConfig).
	venomfang = {
		name = "Venomfang",
		description = "Its fangs drip with a slow, spreading poison.",
		rarity = 2,
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 1.3, knockback = 10, range = 20 },
		stats = { Damage = 90, Strength = 20, CritChance = 12, CritIncrease = 60 },
		abilities = {
			{
				name = "Venom Cloud",
				ability = "venom_cloud",
				key = "X",
				cooldown = 10,
				text = 'Leave a cloud of venom for <font color="#55FF55" family="rbxassetid://12187371840">8 seconds</font> that hits enemies inside every 2 seconds for <font color="#FF5555" family="rbxassetid://12187371840">60% damage</font> and burns them.',
			},
		},
	},

	earthshatter_greatsword = {
		name = "Earthshatter",
		description = "Heavy enough to split the ground it lands on.",
		rarity = 3,
		skillTag = "Combat",
		weapon = { weaponType = "sword", attackSpeed = 0.8, knockback = 25, range = 22 },
		stats = { Damage = 180, Strength = 40, Defense = 10, CritChance = 6, CritIncrease = 80 },
		abilities = {
			{
				name = "Earthshatter",
				ability = "earthshatter",
				key = "RMB",
				cooldown = 8,
				text = 'After a short delay, slam the ground for <font color="#FF5555" family="rbxassetid://12187371840">400% damage</font> to every enemy within <font color="#55FF55" family="rbxassetid://12187371840">12 studs</font>, knocking them back hard.',
			},
		},
	},

	gale_lance = {
		name = "Gale Lance",
		description = "Wind carries the spear straight through its targets.",
		rarity = 3,
		skillTag = "Combat",
		weapon = { weaponType = "spear", attackSpeed = 1.4, knockback = 12, range = 30 },
		stats = { Damage = 120, Strength = 30, CritChance = 15, CritIncrease = 60 },
		abilities = {
			{
				name = "Gale Lance",
				ability = "gale_lance",
				key = "V",
				cooldown = 4,
				text = 'Hurl a gust that pierces up to <font color="#55FF55" family="rbxassetid://12187371840">6 enemies</font> in a line <font color="#55FF55" family="rbxassetid://12187371840">30 studs</font> long, dealing <font color="#FF5555" family="rbxassetid://12187371840">160% damage</font> to each.',
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
			{ name = "Magic Missile", key = "Z", cooldown = 1.5, damage = 20, text = "Cast a magic missile." },
			{ name = "Mana Shield", key = "X", cooldown = 8, damage = 0, text = "Create a protective barrier." },
		},
	},
}
