-- ============================================================
--  ItemRegistry (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Single source of truth for every item in the game.
--  Both client (tooltips, icons, rarity colors) and server
--  (validation, drop tables, stat computation) require this.
--
--  Adding a new item = adding one entry to Items table.
--  All fields have sensible defaults so only id + displayName
--  are strictly required.
--
--  API:
--    ItemRegistry.get(itemId)        → config table or nil
--    ItemRegistry.exists(itemId)     → bool
--    ItemRegistry.getRarity(rarity)  → rarity config table
--    ItemRegistry.Items              → full table (read-only use)
--    ItemRegistry.RarityConfig       → full table (read-only use)
-- ============================================================

local ItemRegistry = {}

-- ===================== RARITY TIERS =====================
-- Matches FIA design: 0=Common → 5=Mythic
-- Each tier defines display info used by tooltips, inventory slots,
-- and any future UI that needs rarity-aware styling.

ItemRegistry.RarityConfig = {
	[0] = {
		name = "Common",
		color = Color3.fromHex("#AAAAAA"), -- slot border / text
		bgColor = Color3.fromHex("#555555"), -- slot background tint
		hexColor = "#AAAAAA",
		display = "", -- no stars for Common
		tooltipPrefix = '<font color="#AAAAAA">', -- for rich text titles
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
		bgColor = Color3.fromHex("#00AA00"),
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
		color = Color3.fromHex("#FFFF55"),
		bgColor = Color3.fromHex("#FFAA00"),
		tooltipPrefix = '<font color="#FFFF55">',
	},
}

-- ===================== ITEM DEFINITIONS =====================
-- Every item in the game. Fields:
--   id          : string — unique key, must match table key
--   displayName : string — shown in UI
--   description : string — tooltip desc (empty = hidden for now)
--   rarity      : number 0-5
--   icon        : string — Roblox ImageId (empty = no icon yet)
--   maxStack    : number — per-slot stack cap (default 999)
--   toolName    : string — name of the Tool in ServerStorage
--                          (matches Tool.Name for the Tool-instance system)
--   statBonuses : table  — { statName = value } (empty for now)
--
-- IMPORTANT: `id` must equal the table key. `toolName` must match the
-- actual Tool instance name in ServerStorage exactly.

ItemRegistry.Items = {

	-- ── Farming ──
	coal_terrafruit = {
		id = "coal_terrafruit",
		displayName = "Coal Terrafruit",
		description = "",
		rarity = 0,
		icon = "",
		maxStack = 999,
		toolName = "Coal Terrafruit",
		statBonuses = {},
	},
	gold_terrafruit = {
		id = "gold_terrafruit",
		displayName = "Gold Terrafruit",
		description = "",
		rarity = 2,
		icon = "",
		maxStack = 999,
		toolName = "Gold Terrafruit",
		statBonuses = {},
	},
	iron_terrafruit = {
		id = "iron_terrafruit",
		displayName = "Iron Terrafruit",
		description = "",
		rarity = 1,
		icon = "",
		maxStack = 999,
		toolName = "Iron Terrafruit",
		statBonuses = {},
	},

	-- ── Test / Debug Items ──
	rarity_test_0 = {
		id = "rarity_test_0",
		displayName = "Common Shard",
		description = "A test item — Common tier.",
		rarity = 0,
		icon = "",
		maxStack = 999,
		toolName = "RarityTest0",
		statBonuses = {},
	},
	rarity_test_1 = {
		id = "rarity_test_1",
		displayName = "Uncommon Shard",
		description = "A test item — Uncommon tier.",
		rarity = 1,
		icon = "",
		maxStack = 999,
		toolName = "RarityTest1",
		statBonuses = {},
	},
	rarity_test_2 = {
		id = "rarity_test_2",
		displayName = "Rare Shard",
		description = "A test item — Rare tier.",
		rarity = 2,
		icon = "",
		maxStack = 999,
		toolName = "RarityTest2",
		statBonuses = {},
	},
	rarity_test_3 = {
		id = "rarity_test_3",
		displayName = "Epic Shard",
		description = "A test item — Epic tier.",
		rarity = 3,
		icon = "",
		maxStack = 999,
		toolName = "RarityTest3",
		statBonuses = {},
	},
	rarity_test_4 = {
		id = "rarity_test_4",
		displayName = "Legendary Shard",
		description = "A test item — Legendary tier.",
		rarity = 4,
		icon = "",
		maxStack = 999,
		toolName = "RarityTest4",
		statBonuses = {},
	},
	rarity_test_5 = {
		id = "rarity_test_5",
		displayName = "Mythic Shard",
		description = "A test item — Mythic tier.",
		rarity = 5,
		icon = "",
		maxStack = 999,
		toolName = "RarityTest5",
		statBonuses = {},
	},
}

-- ===================== REVERSE LOOKUP: toolName → itemId =====================
-- Built once at require-time so the server can map Tool.Name → registry entry.
ItemRegistry._toolNameToId = {}
for id, config in pairs(ItemRegistry.Items) do
	if config.toolName and config.toolName ~= "" then
		ItemRegistry._toolNameToId[config.toolName] = id
	end
end

-- ===================== API =====================

--- Get a full item config by its registry id.
function ItemRegistry.get(itemId: string)
	return ItemRegistry.Items[itemId]
end

--- Check if an item id exists.
function ItemRegistry.exists(itemId: string): boolean
	return ItemRegistry.Items[itemId] ~= nil
end

--- Get rarity config for a numeric tier.
function ItemRegistry.getRarity(rarity: number)
	return ItemRegistry.RarityConfig[math.clamp(rarity or 0, 0, 6)]
end

--- Resolve a Tool.Name string to its registry item id.
--- Returns nil if the tool has no registry entry.
function ItemRegistry.getIdFromToolName(toolName: string): string?
	return ItemRegistry._toolNameToId[toolName]
end

--- Get item config by Tool.Name (convenience wrapper).
function ItemRegistry.getByToolName(toolName: string)
	local id = ItemRegistry._toolNameToId[toolName]
	return id and ItemRegistry.Items[id] or nil
end

print("ItemRegistry: Loaded ✓ (" .. tostring(#ItemRegistry._toolNameToId) .. " tool mappings)")
return ItemRegistry
