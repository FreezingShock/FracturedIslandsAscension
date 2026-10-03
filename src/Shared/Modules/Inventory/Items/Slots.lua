--[[
	Items/Slots (ModuleScript)

	The 8 equipment slots (4 armor + 4 accessories). A slot id is also the
	name of its button under CentralizedAscensionMenu...ArmorAccessories.
	An item goes in a slot by setting `slot = "Helmet"` in its definition.

	To add a slot: add an entry here AND a matching button in the GUI.
--]]

local Slots = {}

Slots.Defs = {
	Helmet = {
		id = "Helmet",
		displayName = "Helmet",
		type = "armor",
		color = "#FF5555",
		description = "Head armor.",
	},
	Chestplate = {
		id = "Chestplate",
		displayName = "Chestplate",
		type = "armor",
		color = "#55FF55",
		description = "Body armor.",
	},
	Leggings = {
		id = "Leggings",
		displayName = "Leggings",
		type = "armor",
		color = "#5555FF",
		description = "Leg armor.",
	},
	Boots = {
		id = "Boots",
		displayName = "Boots",
		type = "armor",
		color = "#FFFF55",
		description = "Foot armor.",
	},
	Cloak = {
		id = "Cloak",
		short = "CK", -- label shown on an empty slot
		displayName = "Cloak",
		type = "accessory",
		color = "#FF55FF",
		description = "Back accessory.",
	},
	Gloves = {
		id = "Gloves",
		short = "GL", -- label shown on an empty slot
		displayName = "Gloves",
		type = "accessory",
		color = "#00AAAA",
		description = "Hand accessory.",
	},
	Necklace = {
		id = "Necklace",
		short = "NK", -- label shown on an empty slot
		displayName = "Necklace",
		type = "accessory",
		color = "#FFAA00",
		description = "Neck accessory.",
	},
	Belt = {
		id = "Belt",
		short = "BT", -- label shown on an empty slot
		displayName = "Belt",
		type = "accessory",
		color = "#AA00AA",
		description = "Waist accessory.",
	},
}

-- Display / iteration order.
Slots.Order = { "Helmet", "Chestplate", "Leggings", "Boots", "Cloak", "Gloves", "Necklace", "Belt" }

Slots.ByType = {
	armor = { "Helmet", "Chestplate", "Leggings", "Boots" },
	accessory = { "Cloak", "Gloves", "Necklace", "Belt" },
}

function Slots.get(slotId: string)
	return Slots.Defs[slotId]
end

function Slots.exists(slotId: string): boolean
	return Slots.Defs[slotId] ~= nil
end

return Slots
