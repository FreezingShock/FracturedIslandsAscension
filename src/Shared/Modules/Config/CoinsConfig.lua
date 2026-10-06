--[[
	CoinsConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	COINS are the real money of the game (the purse). They are NOT a Statistic: they live in the profile under _Wallet and
	only WalletService changes them. This file says where Coins come from, all server-side.

	LAYERS, each overriding the one before:
	  1. library.default            the base kill reward: amount range, number of coin drops, chance
	  2. enemies[<EnemyType>]       per enemy type (EnemyConfig key): a table of overrides, or false for "gives nothing"
	  3. enemies[<type>].weapons    reserved for per-weapon overrides (not read yet)
	CoinsConfig.forEnemy(enemyType) returns the merged table, or nil when the enemy gives no Coins.

	FIELDS: amount = { min, max } Coins in ONE drop; drops = how many coin drops (a number or { min, max }); chance = 0-1 per
	drop; pickupRadius = studs (LootService default when nil). Coins that land close together on the floor merge into one.

	`sources` is the table later systems plug into (selling crafted items, quest rewards, shops): the key is a free label and the
	value is documentation for now, WalletService.add(player, amount, source) accepts any label.

	RECIPES
	  A new enemy that pays Coins:   enemies.<EnemyType> = { amount = { 5, 9 } }
	  An enemy that never pays:      enemies.dummy = false
	  Rarer, bigger coin drops:      enemies.boss = { amount = { 50, 80 }, drops = 3, chance = 0.5 }
	  Everything pays double:        library.default.amount = { 2, 6 }
]]

local CoinsConfig = {}

CoinsConfig.library = {
	default = { amount = { 1, 3 }, drops = 1, chance = 1 },
}

CoinsConfig.enemies = {
	dummy = { amount = { 1, 3 } },
	placeholder_mob = { amount = { 2, 6 } },
}

-- documentation of the planned income sources (not read by code yet)
CoinsConfig.sources = {
	Kill = "enemy death, CoinsConfig.enemies",
	Sell = "selling crafted / stat items (planned)",
	Loot = "chests and world loot (planned)",
	Quest = "objective rewards (planned)",
}

-- the gold of a coin drop and of the Purse line
CoinsConfig.color = "#FFAA00"

local function merge(base: any, over: any): any
	local out = {}
	for k, v in pairs(base) do
		out[k] = v
	end
	for k, v in pairs(over) do
		out[k] = v
	end
	return out
end

function CoinsConfig.forEnemy(enemyType: string?): any?
	local over = enemyType and CoinsConfig.enemies[enemyType]
	if over == nil or over == false then
		return nil
	end
	return merge(CoinsConfig.library.default, over)
end

--- Roll the coin drops of one kill: a list of { count = <coins in this drop> } (empty when nothing drops).
function CoinsConfig.roll(enemyType: string?): { any }
	local cfg = CoinsConfig.forEnemy(enemyType)
	local out = {}
	if not cfg then
		return out
	end
	local drops = cfg.drops
	if type(drops) == "table" then
		drops = math.random(drops[1], drops[2] or drops[1])
	end
	for _ = 1, drops or 1 do
		if math.random() < (cfg.chance or 1) then
			local lo, hi = cfg.amount[1], cfg.amount[2] or cfg.amount[1]
			table.insert(out, { count = math.random(lo, hi), pickupRadius = cfg.pickupRadius })
		end
	end
	return out
end

return CoinsConfig
