--[[
	LootService (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyService; its pickup loop starts when it loads)

	What an enemy gives when it dies, all server-side:
	  LootService.reward(model, enemyType)   skill XP to the killer (the model's LastAttacker attribute) and the enemy's drops
	                                         (EnemyConfig.dropsFor), each spawned as a small physical drop
	  LootService.spawnDrop(position, drop, ownerId?)

	XP: EnemyConfig.enemies[type].xp = { skill, amount } through SkillsDataManager.AddXP(killer, skill, amount, "Kill"),
	with a chat line. Drops: each entry rolls its own chance (the killer's MagicFind multiplies it); pools pick by weight.

	DropTooltipController (client) shows a card over every drop tagged "DropTooltip" (attributes DropKind, ItemId, Count,
	Rarity, DropColor, DropSkill, DropName); the plain DropLabel hides while a card or chip is up.

	A drop is an anchored glowing cube at the kill point with a name label (ReplicatedStorage.GUI.DropLabel, hand-restylable:
	BillboardGui > Label). Only the killer can collect it for `OWNER_SECONDS`, then anyone; it despawns after `LIFETIME`.
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
local ChatService = require(ServerScriptService:WaitForChild("ChatService")) :: any

local OWNER_SECONDS = 15
local LIFETIME = 90
local PICKUP_RADIUS = 5
local SCAN_EVERY = 0.2
local SPREAD = 3 -- studs a drop lands from the kill point

local LootService = {}

type Drop = { part: BasePart, drop: any, ownerId: number?, ownerUntil: number, expiresAt: number, fullNoticeAt: number }
local drops: { [BasePart]: Drop } = {}

local function chat(player: Player, text: string, color: Color3)
	ChatService.BroadcastRaw({ text }, { [1] = color:ToHex() }, nil, "game", player)
end

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
		name = def.name,
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

function LootService.spawnDrop(position: Vector3, drop: any, ownerId: number?)
	local offset = Vector3.new((math.random() - 0.5) * 2 * SPREAD, 0, (math.random() - 0.5) * 2 * SPREAD)
	local part = Instance.new("Part")
	part.Name = "Drop"
	part.Size = Vector3.new(0.9, 0.9, 0.9)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Color = drop.color
	part.Position = position + offset
	part:SetAttribute("DropName", drop.name)
	-- read-only description for DropTooltipController (client builds the card from these, sends nothing back)
	part:SetAttribute("DropKind", drop.kind == "stat" and "stat" or "item")
	part:SetAttribute("ItemId", drop.id)
	part:SetAttribute("Count", drop.count)
	part:SetAttribute("Rarity", drop.rarity or 0)
	part:SetAttribute("DropColor", drop.color:ToHex())
	if drop.skill then
		part:SetAttribute("DropSkill", drop.skill)
	end
	CollectionService:AddTag(part, "DropTooltip")

	local light = Instance.new("PointLight")
	light.Color = drop.color
	light.Range = 8
	light.Brightness = 1.5
	light.Parent = part

	local guiFolder = ReplicatedStorage:FindFirstChild("GUI")
	local template = guiFolder and guiFolder:FindFirstChild("DropLabel")
	if template then
		local label = template:Clone()
		label.Adornee = part
		local text = label:FindFirstChild("Label") :: TextLabel?
		if text then
			text.Text = (drop.count > 1 and ("%dx "):format(drop.count) or "") .. drop.name
			text.TextColor3 = drop.color
		end
		label.Parent = part
	end

	part.Parent = workspace
	local now = os.clock()
	drops[part] = {
		part = part,
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
		local gained = SkillsDataManager.AddXP(killer, entry.xp.skill, entry.xp.amount, "Kill")
		if gained and gained > 0 then
			chat(killer, ("  +%d %s XP  (%s)"):format(gained, entry.xp.skill, entry.name), Color3.fromHex("#55FFFF"))
		end
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
end

local function collect(player: Player, state: Drop): boolean
	local drop = state.drop
	if drop.kind == "stat" then
		if not StatisticsDataManager.GrantStat(player, drop.skill, drop.id, drop.count) then
			return false
		end
	else
		local added = InventoryDataManager.AddItem(player, drop.toolName, drop.count)
		if added <= 0 then
			if os.clock() - state.fullNoticeAt > 3 then
				state.fullNoticeAt = os.clock()
				chat(player, "  Your inventory is full!", Color3.fromHex("#FF5555"))
			end
			return false
		end
	end
	chat(player, ("  You picked up %s%s"):format(drop.count > 1 and ("%dx "):format(drop.count) or "", drop.name), drop.color)
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
	for part, state in pairs(drops) do
		if not part.Parent or now >= state.expiresAt then
			drops[part] = nil
			part:Destroy()
		else
			for _, player in ipairs(players) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				local allowed = not state.ownerId or player.UserId == state.ownerId or now >= state.ownerUntil
				if allowed and root and humanoid and humanoid.Health > 0 and (root.Position - part.Position).Magnitude <= PICKUP_RADIUS then
					if collect(player, state) then
						drops[part] = nil
						part:Destroy()
						break
					end
				end
			end
		end
	end
end)

return LootService
