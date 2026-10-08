--[[
	LootService (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyService; its pickup loop starts when it loads)

	What an enemy gives when it dies, all server-side:
	  LootService.reward(model, enemyType)   skill XP to the killer (the model's LastAttacker attribute) and the enemy's drops
	                                         (EnemyConfig.dropsFor), each spawned as a small physical drop
	  LootService.spawnDrop(position, drop, ownerId?)

	XP: EnemyConfig.enemies[type].xp = { skill, amount } through SkillsDataManager.AddXP(killer, skill, amount, "Kill"),
	(shown by the action bar). Drops: each entry rolls its own chance (the killer's MagicFind multiplies it); pools pick by weight.

	DropTooltipController (client) shows a dot / folded tag / card over every drop tagged "DropTooltip" (attributes DropKind,
	ItemId, Count, Rarity, DropColor, DropSkill, DropName) and DropFXController (client) draws its glow and particles from the
	same attributes; the plain DropLabel stays hidden while they run.

	A drop is a THICK SPRITE (the item / stat / coin icon with a coloured edge) built by ItemDrops.spawnExternal: it is flung a few
	studs from the kill (Config/LootConfig), lands, hovers, bobs and spins like an item thrown on the floor, and when it is
	collected it flies into the player (rising-pitch pop, coloured burst). Only the killer can collect it for `OWNER_SECONDS`,
	then anyone; it despawns after `LIFETIME`.
	Collecting is a server distance check (PICKUP_RADIUS studs): the client sends nothing. Items and armor go to
	InventoryDataManager.AddItem (the drop stays when the inventory is full), stats to StatisticsDataManager.GrantStat.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local EnemyConfig = require(Modules:WaitForChild("EnemyConfig")) :: any
local Items = require(Modules:WaitForChild("Items")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
local InventoryDataManager = require(ServerScriptService:WaitForChild("InventoryDataManager")) :: any
local StatisticsDataManager = require(ServerScriptService:WaitForChild("StatisticsDataManager")) :: any
local NotifyService = require(ServerScriptService:WaitForChild("NotifyService")) :: any
local WalletService = require(ServerScriptService:WaitForChild("WalletService")) :: any
local CoinsConfig = require(Modules:WaitForChild("Config"):WaitForChild("CoinsConfig")) :: any
local LootConfig = require(Modules:WaitForChild("Config"):WaitForChild("LootConfig")) :: any
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
local ItemDrops = require(ServerScriptService:WaitForChild("ItemDrops")) :: any

local OWNER_SECONDS = 15
local LIFETIME = 90
local PICKUP_RADIUS = 5
local SCAN_EVERY = 0.2
local COIN_MERGE_RADIUS = 4 -- coin drops this close (same owner) clump into one

local LootService = {}

type Drop = { id: number, drop: any, ownerId: number?, ownerUntil: number, expiresAt: number, fullNoticeAt: number }
local drops: { [number]: Drop } = {} -- [ItemDrops id] = state

local function randomCount(count: any): number
	if type(count) == "table" then
		return math.random(count[1], count[2] or count[1])
	end
	return count or 1
end

--- Resolve an entry into what the drop part needs: { kind, name, color, toolName | skill, id, count }.
local function describe(entry: any): any?
	local count = randomCount(entry.count)
	if entry.kind == "stat" then
		return {
			kind = "stat",
			skill = entry.skill or "Combat",
			id = entry.id,
			name = entry.name or entry.id,
			color = Color3.fromHex(entry.color or "#FFFFFF"),
			count = count,
		}
	end
	local def = Items.get(entry.id)
	if not def then
		warn("[LootService] unknown drop item: " .. tostring(entry.id))
		return nil
	end
	return {
		kind = "item",
		id = entry.id,
		toolName = def.toolName,
		name = def.displayName or def.name or entry.id, -- item defs carry displayName, not name
		rarity = def.rarity or 0,
		color = Items.getRarity(def.rarity).color,
		count = count,
	}
end

--- Roll an enemy's drop entries for `killer` (their MagicFind raises each chance).
local function roll(enemyType: string?, killer: Player): { any }
	local magicFind = math.max(tonumber(AttributeStatManager.GetFinalValue(killer, "MagicFind")) or 0, 0)
	local luck = 1 + magicFind / 100
	local out = {}
	for _, entry in ipairs(EnemyConfig.dropsFor(enemyType)) do
		if math.random() < math.min((entry.chance or 1) * luck, 1) then
			if entry.kind == "pool" then
				local total = 0
				for _, option in ipairs(entry.entries) do
					total += option.weight or 1
				end
				local rolls = entry.rolls and randomCount(entry.rolls) or 1
				for _ = 1, rolls do
					local pick = math.random() * total
					for _, option in ipairs(entry.entries) do
						pick -= option.weight or 1
						if pick <= 0 then
							local described = describe(option)
							if described then
								table.insert(out, described)
							end
							break
						end
					end
				end
			else
				local described = describe(entry)
				if described then
					table.insert(out, described)
				end
			end
		end
	end
	return out
end

--- A statistic's entry (icon, colour) from StatisticsConfig, found by skill + key.
local function statEntry(skill: string, id: string): any?
	for _, entry in ipairs(StatisticsConfig.STAT_CHAINS[skill] or {}) do
		if entry.key == id then
			return entry
		end
	end
	return nil
end

--- What the sprite shows for a drop: { apply = function(label), image = content id, tint? }.
local function spriteFor(drop: any): any
	if drop.kind == "item" then
		local def = Items.get(drop.id)
		local spec = ItemIcons.resolve(def or drop.id)
		return {
			apply = function(label: ImageLabel)
				ItemIcons.apply(label, def or drop.id)
			end,
			image = spec.image,
			tint = spec.tint,
		}
	end
	local ref = drop.kind == "coins" and LootConfig.coinsIcon or { skill = drop.skill, id = drop.id }
	local entry = statEntry(ref.skill, ref.id)
	local image = entry and entry.icon or ItemIcons.resolve("barrier").image
	return {
		apply = function(label: ImageLabel)
			label.ResampleMode = Enum.ResamplerMode.Pixelated
			label.Image = image
		end,
		image = image,
	}
end

function LootService.spawnDrop(position: Vector3, drop: any, ownerId: number?)
	local look = LootConfig.resolve(drop.kind, drop)
	if drop.kind == "coins" then
		-- coins that land close together become one bigger pile (the pop and the tag are the same drop)
		for id, state in pairs(drops) do
			local at = ItemDrops.positionOf(id)
			if state.drop.kind == "coins" and state.ownerId == ownerId and at and (at - position).Magnitude <= COIN_MERGE_RADIUS then
				state.drop.count += drop.count
				ItemDrops.setCount(id, state.drop.count)
				state.expiresAt = os.clock() + LIFETIME
				return
			end
		end
	end
	-- flung a few studs in a random direction in a short arc: the horizontal speed is chosen so it lands `spread` away
	local gravity = workspace.Gravity
	local rise = math.sqrt(2 * gravity * look.arcHeight)
	local flight = 2 * rise / gravity
	local angle = math.random() * math.pi * 2
	local distance = look.spread * (0.5 + 0.5 * math.random())
	local velocity = Vector3.new(math.cos(angle) * distance / flight, rise, math.sin(angle) * distance / flight)

	local sprite = spriteFor(drop)
	local id = ItemDrops.spawnExternal({
		position = position,
		velocity = velocity,
		count = drop.count,
		name = drop.name,
		kind = (drop.kind == "stat" or drop.kind == "coins") and drop.kind or "item",
		itemId = drop.id,
		rarity = drop.rarity or 0,
		color = drop.color,
		skill = drop.skill,
		apply = sprite.apply,
		spriteImage = sprite.image,
		tint = sprite.tint,
	})
	if not id then
		return
	end
	local now = os.clock()
	drops[id] = {
		id = id,
		drop = drop,
		ownerId = ownerId,
		ownerUntil = now + OWNER_SECONDS,
		expiresAt = now + LIFETIME,
		fullNoticeAt = 0,
	}
end

--- XP and drops for whoever last hit this enemy. Nothing happens when nobody did (it died some other way).
function LootService.reward(model: Model, enemyType: string?)
	local killer = Players:GetPlayerByUserId(model:GetAttribute("LastAttacker") or 0)
	if not killer then
		return
	end
	local entry = EnemyConfig.get(enemyType)
	if entry.xp then
		SkillsDataManager.AddXP(killer, entry.xp.skill, entry.xp.amount, "Kill") -- the action bar shows it
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	-- the ground under the body, so drops do not float where the mob stood
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }
	local ground = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), params)
	local base = (ground and ground.Position or root.Position - Vector3.new(0, 3, 0)) + Vector3.new(0, 1.2, 0)
	for _, drop in ipairs(roll(enemyType, killer)) do
		LootService.spawnDrop(base, drop, killer.UserId)
	end
	for _, coin in ipairs(CoinsConfig.roll(enemyType)) do -- Coins: physical pickups, rolled here on the server
		LootService.spawnDrop(base, {
			kind = "coins",
			id = "coins",
			name = "Coins",
			color = Color3.fromHex(CoinsConfig.color),
			count = coin.count,
			rarity = 1,
			pickupRadius = coin.pickupRadius,
		}, killer.UserId)
	end
end

local function collect(player: Player, state: Drop): boolean
	local drop = state.drop
	if drop.kind == "stat" then
		if not StatisticsDataManager.GrantStat(player, drop.skill, drop.id, drop.count) then
			return false
		end
		NotifyService.pickup(player, "stat:" .. tostring(drop.id), drop.name, drop.count, "#" .. drop.color:ToHex())
	elseif drop.kind == "coins" then
		if WalletService.add(player, drop.count, "Kill") <= 0 then
			return false
		end
	else
		local added = InventoryDataManager.AddItem(player, drop.toolName, drop.count)
		if added <= 0 then
			if os.clock() - state.fullNoticeAt > 3 then
				state.fullNoticeAt = os.clock()
				NotifyService.system(player, "Your inventory is full!", "#FF5555", "Drop or stash items to pick up more.")
			end
			return false
		end
	end
	return true
end

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < SCAN_EVERY then
		return
	end
	accumulated = 0
	local now = os.clock()
	local players = Players:GetPlayers()
	for id, state in pairs(drops) do
		local at = ItemDrops.positionOf(id)
		if not at then
			drops[id] = nil -- ItemDrops removed it (past its drop limit)
		elseif now >= state.expiresAt then
			drops[id] = nil
			ItemDrops.discard(id)
		else
			for _, player in ipairs(players) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local allowed = not state.ownerId or player.UserId == state.ownerId or now >= state.ownerUntil
				if allowed and root and humanoid and humanoid.Health > 0 and (root.Position - at).Magnitude <= (state.drop.pickupRadius or PICKUP_RADIUS) then
					if collect(player, state) then
						drops[id] = nil
						ItemDrops.take(id, player) -- it flies into the player
						break
					end
				end
			end
		end
	end
end)

return LootService
