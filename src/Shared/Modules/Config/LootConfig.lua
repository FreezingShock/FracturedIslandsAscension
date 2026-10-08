--[[
	LootConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	How the loot of a killed enemy LOOKS and MOVES (LootService reads it; what drops and how often stays in EnemyConfig /
	CoinsConfig). Every loot drop is a floating, bobbing, spinning thick sprite, like an item thrown on the floor: it is flung a
	few studs from the kill in a short arc, lands on the real floor, settles and hovers (ItemDrops owns the physics, the
	renderer the hover).

	LAYERS, each overriding the one before:
	  1. library        spread  studs from the kill point the drop lands (it is flung in a random direction)
	                    arcHeight  studs it rises on its way
	  2. kinds[kind]    kind = "item" | "stat" | "coins": per kind overrides
	  3. a drop entry's own `sprite = { ... }` in EnemyConfig (kind = "stat" / item entries): per drop overrides, e.g. a boss
	     drop that flies farther: { kind = "item", id = "...", sprite = { spread = 6, arcHeight = 5 } }
	LootConfig.resolve(kind, entry) -> the merged table.

	ICONS: items use their ItemIcons icon; stat drops use their StatisticsConfig icon (found by skill + id); coins use
	`coinsIcon` (a stat whose icon the coin pile shows). The coloured edge comes from ItemSpriteData (tools/gen_item_sprites.py);
	an icon without edge data gets a plain frame in the drop's colour.

	RECIPES
	  Loot that scatters wider:          library.spread = 5
	  Coins that barely move:            kinds.coins = { spread = 1, arcHeight = 1 }
	  Another icon for coins:            coinsIcon = { skill = "General", id = "SilverCoins" }
]]

local LootConfig = {}

LootConfig.library = {
	spread = 3,
	arcHeight = 2.5,
}

LootConfig.kinds = {
	item = {},
	stat = {},
	coins = { spread = 2 },
}

LootConfig.coinsIcon = { skill = "General", id = "BronzeCoins" }

local cache: { [string]: any } = {}

function LootConfig.resolve(kind: string?, entry: any?): any
	local override = entry and entry.sprite
	local key = (kind or "item") .. "|" .. tostring(override)
	local hit = cache[key]
	if hit then
		return hit
	end
	local merged = {}
	for _, layer in ipairs({ LootConfig.library, LootConfig.kinds[kind or "item"] or {}, override or {} }) do
		for field, value in pairs(layer) do
			merged[field] = value
		end
	end
	cache[key] = merged
	return merged
end

return LootConfig
