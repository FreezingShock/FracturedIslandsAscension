--[[
	Items/Defs/Debug (category = misc)

	Rarity test shards for checking rarity colors. rarity_test_1 also shows
	display-only stat rows (displayStats) with a custom skill tag.
--]]

return {
	rarity_test_0 = { name = "Common Shard", toolName = "RarityTest0", description = "A test item — Common tier.", rarity = 0 },
	rarity_test_1 = {
		name = "Uncommon Shard",
		toolName = "RarityTest1",
		description = "A test item — Uncommon tier.",
		rarity = 1,
		typeTag = "Crafting Material",
		skillTag = "Crafting",
		displayStats = {
			{ name = "Value", value = "50 Gold", color = "#FFAA00" },
			{ name = "Yield", value = "2x", color = "#55FF55" },
		},
		clickHint = "Use in crafting recipes",
	},
	rarity_test_2 = { name = "Rare Shard", toolName = "RarityTest2", description = "A test item — Rare tier.", rarity = 2 },
	rarity_test_3 = { name = "Epic Shard", toolName = "RarityTest3", description = "A test item — Epic tier.", rarity = 3 },
	rarity_test_4 = { name = "Legendary Shard", toolName = "RarityTest4", description = "A test item — Legendary tier.", rarity = 4 },
	rarity_test_5 = { name = "Mythic Shard", toolName = "RarityTest5", description = "A test item — Mythic tier.", rarity = 5 },
}
