--[[
	Items/Defs/Core (category = misc)

	Items every player always has. `pinSlot` locks an item to a hotbar slot (it cannot be moved, dropped or trashed
	and is re-given if it ever goes missing); `onUse` is what a left click does while it is held.
--]]

return {

	nexus_star = {
		name = "Nexus Star",
		description = "The heart of the Nexus. Hold it and click to open the Nexus Menu and your inventory.",
		rarity = 6,
		equippable = true,
		maxStack = 1,
		pinSlot = 9,
		onUse = "nexusMenu",
		typeTag = "Menu",
		clickHint = { text = "LEFT CLICK TO OPEN THE NEXUS MENU", color = "#FFFF55" },
	},
}
