--[[
	Items/Rarity (ModuleScript)

	Rarity tiers 0 (Common) -> 5 (Mythic), 6 = Game. Used by tooltips,
	inventory slots, armor slots and anything else that needs rarity styling.
--]]

local Rarity = {}

Rarity.Config = {
	[0] = {
		name = "Common",
		color = Color3.fromHex("#AAAAAA"),
		bgColor = Color3.fromHex("#555555"),
		hexColor = "#AAAAAA",
		display = "",
		tooltipPrefix = '<font color="#AAAAAA">',
	},
	[1] = {
		name = "Uncommon",
		color = Color3.fromHex("#55FF55"),
		bgColor = Color3.fromHex("#00AA00"),
		hexColor = "#55FF55",
		display = '<stroke color="#00AA00" joins="round" thickness=".5">★</stroke>',
		tooltipPrefix = '<font color="#55FF55">',
	},
	[2] = {
		name = "Rare",
		color = Color3.fromHex("#5555FF"),
		bgColor = Color3.fromHex("#0000AA"),
		hexColor = "#5555FF",
		display = '<stroke color="#0000AA" joins="round" thickness=".5">★★</stroke>',
		tooltipPrefix = '<font color="#5555FF">',
	},
	[3] = {
		name = "Epic",
		color = Color3.fromHex("#FF55FF"),
		bgColor = Color3.fromHex("#AA00AA"),
		hexColor = "#FF55FF",
		display = '<stroke color="#AA00AA" joins="round" thickness=".5">★★★</stroke>',
		tooltipPrefix = '<font color="#FF55FF">',
	},
	[4] = {
		name = "Legendary",
		color = Color3.fromHex("#FFAA00"),
		bgColor = Color3.fromHex("#FFFF55"),
		hexColor = "#FFAA00",
		display = '<stroke color="#AA5500" joins="round" thickness=".5">★★★★</stroke>',
		tooltipPrefix = '<font color="#FFAA00">',
	},
	[5] = {
		name = "Mythic",
		color = Color3.fromHex("#FF5555"),
		bgColor = Color3.fromHex("#AA0000"),
		hexColor = "#FF5555",
		display = '<stroke color="#AA0000" joins="round" thickness=".5">★★★★★</stroke>',
		tooltipPrefix = '<font color="#FF5555">',
	},
	[6] = {
		name = "Game",
		display = "✿",
		hexColor = "#FFFF55",
		color = Color3.fromHex("#FFAA00"),
		bgColor = Color3.fromHex("#FFFF55"),
		tooltipPrefix = '<font color="#FFFF55">',
	},
}

function Rarity.get(rarity: number?)
	return Rarity.Config[math.clamp(rarity or 0, 0, 6)]
end

return Rarity
