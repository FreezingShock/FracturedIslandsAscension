--[[
	AbilityService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by AbilityInit.server.lua)

	Server-authoritative key abilities (AbilityConfig: Overload, Holy Nova, Blink Dash, Chain Lightning, Frost Nova ...).
	The client only says "I pressed this key" on the AbilityCast remote; it never sends a target, a position or an ability id.
	The server decides:

	  1. the player holds a weapon whose item lists an ability bound to that key (AbilityConfig.byKey; one weapon can list
	     several, one per key RMB / Z / X / C / V)
	  2. the press is not spam (AbilityConfig.minPressGap), the player is alive, THAT ability (by id, not by weapon) is off
	     cooldown, and the zone caps (per player and global) allow another zone
	  3. enough Mana (ResourceService.Spend; mana regenerates by itself after the last spend)
	Then it locks the combo for castTime, tells nearby clients (AbilityCast: animation + cooldown HUD) and at `hitFrame` hits
	whatever the ability covers (DamageService.query / strikeHits: Strength and crit apply):
	  * shape            circle / cone / line around the caster
	  * chain            the nearest enemy, then jumps to the nearest other enemy near the last one, each hit weaker
	  * dash             hit the line, then move the caster forward (stops short of walls)
	  * zone             keeps hitting every tickInterval; ALL zones run on one shared step (not a thread each) and stop when the
	                     caster dies, puts the weapon away or leaves
	  * effects          slow (EnemyService scales walk speed by the SlowMult / SlowUntil model attributes) and burn (damage over
	                     time, also on the shared step; one burn per target)
	and sends the visuals as one AbilityFx message to players within AbilityConfig.fxDistance of the caster.

	Remotes
	  AbilityCast  client -> server   FireServer(keyName)                       "RMB", "Z", ...
	               server -> clients  { caster = Player, abilityId, weaponId, cooldown, readyAt }   readyAt = workspace:GetServerTimeNow()
	  AbilityFx    server -> clients  { kind = "start", caster, abilityId, weaponId, origin, points?, duration? }
	                                  { kind = "end", caster, abilityId }       a zone was cut short (death / unequip / leave)

	API
	  AbilityService.cast(player, keyName) -> ok, reason    reason: spam | no_weapon | no_ability | dead | cooldown | zones | mana
	  AbilityService.cooldownLeft(player, abilityId)        -> seconds
	  AbilityService.stopAll(player)                        end every zone of this player
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AbilityConfig = require(Modules:WaitForChild("AbilityConfig")) :: any
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry")) :: any
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter")) :: any
local WeaponManager = require(ServerScriptService:WaitForChild("WeaponManager")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any
local ResourceService = require(ServerScriptService:WaitForChild("ResourceService")) :: any
local EnemyTags = require(ServerScriptService:WaitForChild("EnemyTags")) :: any

local AbilityService = {}

local function remote(name: string): RemoteEvent
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing :: RemoteEvent
	end
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end
local castEvent = remote("AbilityCast")
local fxEvent = remote("AbilityFx")

AbilityConfig.validate()

local STEP = 0.1 -- seconds between shared zone / burn steps

-- [userId] = { [abilityId] = readyAtClock }
local cooldowns: { [number]: { [string]: number } } = {}
-- [userId] = { [keyName] = clock of the last press }
local lastPress: { [number]: { [string]: number } } = {}

type Zone = {
	player: Player,
	abilityId: string,
	ability: any,
	weaponId: string,
	stats: any,
	origin: Vector3?, -- fixed centre (follow = false); nil = the caster's position each tick
	endsAt: number,
	nextTick: number,
}
local zones: { Zone } = {}
local zoneCount: { [number]: number } = {} -- [userId] = zones running

type Burn = { player: Player, weaponId: string, stats: any, damageMult: number, interval: number, endsAt: number, nextTick: number }
local burns: { [Model]: Burn } = {}
local burnCount = 0

local alive: (Player) -> boolean

-- ===================== HELPERS =====================
function alive(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and player.Parent == Players
end

local function frameOf(player: Player): (Model?, BasePart?, Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and root) then
		return nil, nil, nil
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	return character, root, look.Magnitude > 1e-3 and look.Unit or Vector3.zAxis
end

--- Send `data` on `event` to the caster and every player within AbilityConfig.fxDistance of `origin`.
local function broadcast(event: RemoteEvent, caster: Player, origin: Vector3, data: any)
	local range = AbilityConfig.fxDistance
	for _, other in ipairs(Players:GetPlayers()) do
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if other == caster or (root and (root.Position - origin).Magnitude <= range) then
			event:FireClient(other, data)
		end
	end
end

function AbilityService.cooldownLeft(player: Player, abilityId: string): number
	local readyAt = cooldowns[player.UserId] and cooldowns[player.UserId][abilityId]
	return readyAt and math.max(0, readyAt - os.clock()) or 0
end

-- ===================== SHARED STEP (zones + burns) =====================
local stepConnection: RBXScriptConnection? = nil
local step: (number) -> ()

local function ensureStep()
	if stepConnection then
		return
	end
	local accumulated = 0
	stepConnection = RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= STEP then
			accumulated = 0
			step(os.clock())
		end
	end)
end

local function idle()
	if stepConnection and #zones == 0 and burnCount == 0 then
		stepConnection:Disconnect()
		stepConnection = nil
	end
end

local function endZone(index: number, notify: boolean)
	local zone = zones[index]
	table.remove(zones, index)
	zoneCount[zone.player.UserId] = math.max(0, (zoneCount[zone.player.UserId] or 1) - 1)
	if notify and zone.player.Parent == Players then
		local _, root = frameOf(zone.player)
		broadcast(fxEvent, zone.player, zone.origin or (root and root.Position) or Vector3.zero, {
			kind = "end",
			caster = zone.player,
			abilityId = zone.abilityId,
		})
	end
end

local function endBurn(model: Model)
	if burns[model] then
		burns[model] = nil
		burnCount -= 1
	end
end

--- Slow / burn every target of a hit. A zone calls this each tick, so a slow is refreshed while the target stays inside.
local function applyEffects(player: Player, ability: any, weaponId: string, stats: any, hits: { any })
	if not ability.effects then
		return
	end
	local now = os.clock()
	for _, effect in ipairs(ability.effects) do
		for _, hit in ipairs(hits) do
			local model = hit.model :: Model
			if effect.kind == "slow" then
				local active = (model:GetAttribute("SlowUntil") or 0) > now
				if not active or (model:GetAttribute("SlowMult") or 1) >= effect.mult then
					model:SetAttribute("SlowMult", effect.mult)
				end
				model:SetAttribute("SlowUntil", math.max(model:GetAttribute("SlowUntil") or 0, now + effect.duration))
				EnemyTags.add(model, "slow", { duration = effect.duration })
			elseif effect.kind == "burn" then
				local existing = burns[model]
				EnemyTags.add(model, "burn", { duration = effect.duration })
				if existing then
					existing.endsAt = now + effect.duration -- refresh, never stack
				elseif burnCount < AbilityConfig.maxBurnsGlobal then
					burns[model] = {
						player = player,
						weaponId = weaponId,
						stats = stats,
						damageMult = ability.damageMult * effect.damageMult,
						interval = effect.interval,
						endsAt = now + effect.duration,
						nextTick = now + effect.interval,
					}
					burnCount += 1
				end
			end
		end
	end
	if burnCount > 0 then
		ensureStep()
	end
end

--- One strike of `ability` around `origin` (default: the caster). Returns the targets hit.
local function strike(player: Player, ability: any, weaponId: string, stats: any, origin: Vector3?): { any }
	local character, root, facing = frameOf(player)
	if not (character and root and facing and ability.shape) then
		return {}
	end
	local from = origin or root.Position
	local hits = DamageService.query(character, from, facing, ability.shape)
	local list = table.move(hits, 1, math.min(#hits, ability.maxTargets or 1), 1, {})
	DamageService.strikeHits(player, list, ability, weaponId, stats, from)
	applyEffects(player, ability, weaponId, stats, list)
	return list
end

function step(now: number)
	for index = #zones, 1, -1 do
		local zone = zones[index]
		if not alive(zone.player) or WeaponManager.GetEquipped(zone.player) ~= zone.weaponId then
			endZone(index, true) -- death / weapon put away: stop hitting and tell the clients to stop the effect
		elseif now >= zone.endsAt - 1e-3 then
			endZone(index, false) -- the client ends its own effect at the same time
		elseif now >= zone.nextTick then
			zone.nextTick += zone.ability.zone.tickInterval
			strike(zone.player, zone.ability, zone.weaponId, zone.stats, zone.origin)
		end
	end

	for model, burn in pairs(burns) do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if now >= burn.endsAt or not humanoid or humanoid.Health <= 0 or not model.Parent or not alive(burn.player) then
			endBurn(model)
		elseif now >= burn.nextTick then
			burn.nextTick += burn.interval
			local _, root = frameOf(burn.player)
			local hit = root and DamageService.hitFor(model, root.Position)
			if hit then
				DamageService.strikeHits(burn.player, { hit }, { damageMult = burn.damageMult, knockback = 0, maxTargets = 1 }, burn.weaponId, burn.stats, root.Position)
			else
				endBurn(model)
			end
		end
	end
	idle()
end

function AbilityService.stopAll(player: Player)
	for index = #zones, 1, -1 do
		if zones[index].player == player then
			endZone(index, true)
		end
	end
	for model, burn in pairs(burns) do
		if burn.player == player then
			endBurn(model)
		end
	end
	idle()
end

-- ===================== RESOLVING A CAST =====================
--- Where a dash from `from` along `facing` ends: `distance` studs, or short of the first wall.
local function dashEnd(character: Model, from: Vector3, facing: Vector3, distance: number): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	local wall = workspace:Raycast(from, facing * distance, params)
	local travelled = wall and math.max(0, wall.Distance - 2.5) or distance
	return from + facing * travelled
end

--- Chain lightning: the nearest target of the shape, then jumps. Returns the positions the bolt passes through.
local function chainStrike(player: Player, ability: any, weaponId: string, stats: any, root: BasePart, facing: Vector3): { Vector3 }
	local character = player.Character
	local chain = ability.chain
	local points: { Vector3 } = { root.Position }
	local first = DamageService.query(character, root.Position, facing, ability.shape)[1]
	if not first then
		table.insert(points, root.Position + facing * 10) -- a miss: a short bolt forward
		return points
	end
	local visited: { [Model]: boolean } = {}
	local current = first
	local damage = ability.damageMult
	for jump = 0, chain.jumps do
		visited[current.model] = true
		table.insert(points, current.root.Position)
		DamageService.strikeHits(player, { current }, { damageMult = damage, knockback = ability.knockback or 0, maxTargets = 1 }, weaponId, stats, root.Position)
		applyEffects(player, ability, weaponId, stats, { current })
		if jump == chain.jumps then
			break
		end
		local nextHit = nil
		for _, candidate in ipairs(DamageService.query(character, current.root.Position, facing, { kind = "circle", radius = chain.range, lineOfSight = false })) do
			if not visited[candidate.model] then
				nextHit = candidate -- query returns nearest first
				break
			end
		end
		if not nextHit then
			break
		end
		damage *= chain.falloff
		current = nextHit
	end
	return points
end

--- Everything that happens at the hit frame, then the visuals message. False when the caster is gone.
local function resolve(player: Player, ability: any, abilityId: string, weaponId: string, stats: any): boolean
	local character, root, facing = frameOf(player)
	if not (character and root and facing) then
		return false
	end
	local origin = root.Position
	local points: { Vector3 }? = nil
	local fixedOrigin: Vector3? = nil

	if ability.chain then
		points = chainStrike(player, ability, weaponId, stats, root, facing)
	elseif ability.dash then
		strike(player, ability, weaponId, stats, origin)
		local destination = dashEnd(character, origin, facing, ability.dash.distance)
		character:PivotTo(CFrame.lookAt(destination, destination + facing))
		points = { origin, destination }
	elseif ability.zone then
		if ability.zone.follow == false then
			fixedOrigin = origin
		end
		local now = os.clock()
		if ability.zone.tickOnCast ~= false then
			strike(player, ability, weaponId, stats, fixedOrigin)
		end
		table.insert(zones, {
			player = player,
			abilityId = abilityId,
			ability = ability,
			weaponId = weaponId,
			stats = stats,
			origin = fixedOrigin,
			endsAt = now + ability.zone.duration,
			nextTick = now + ability.zone.tickInterval,
		})
		ensureStep()
	else
		strike(player, ability, weaponId, stats, nil)
		if ability.shape and ability.shape.kind == "line" then
			points = { origin, origin + facing * ability.shape.length } -- the line's start and end, for its fx
		end
	end

	broadcast(fxEvent, player, origin, {
		kind = "start",
		caster = player,
		abilityId = abilityId,
		weaponId = weaponId,
		origin = origin,
		points = points,
		duration = ability.zone and ability.zone.duration or nil,
	})
	return true
end

function AbilityService.cast(player: Player, keyName: string): (boolean, string?)
	local userId = player.UserId
	local now = os.clock()
	local presses = lastPress[userId]
	if not presses then
		presses = {}
		lastPress[userId] = presses
	end
	local previous = presses[keyName]
	presses[keyName] = now -- a held / spammed key keeps itself blocked
	if previous and now - previous < AbilityConfig.minPressGap then
		return false, "spam"
	end

	local weaponId = WeaponManager.GetEquipped(player)
	local weapon = weaponId and WeaponRegistry.get(weaponId)
	local character = player.Character
	if not (weaponId and weapon and character and character:FindFirstChild(weapon.toolName)) then
		return false, "no_weapon"
	end
	local ability, abilityId = AbilityConfig.byKey(weaponId, keyName)
	if not (ability and abilityId) then
		return false, "no_ability"
	end
	if not alive(player) then
		return false, "dead"
	end
	if AbilityService.cooldownLeft(player, abilityId) > 0 then
		return false, "cooldown"
	end
	if ability.zone and ((zoneCount[userId] or 0) >= AbilityConfig.maxZonesPerPlayer or #zones >= AbilityConfig.maxZonesGlobal) then
		return false, "zones"
	end
	if not ResourceService.Spend(player, "Mana", ability.manaCost or 0) then
		return false, "mana"
	end

	-- accepted
	local cooldown = ability.cooldown or 0
	cooldowns[userId] = cooldowns[userId] or {}
	cooldowns[userId][abilityId] = now + cooldown
	WeaponManager.Lock(player, ability.castTime or 0.5)
	if ability.zone then
		zoneCount[userId] = (zoneCount[userId] or 0) + 1 -- reserved now so two quick casts cannot pass the cap
	end

	local _, root = frameOf(player)
	broadcast(castEvent, player, root and root.Position or Vector3.zero, {
		caster = player,
		abilityId = abilityId,
		weaponId = weaponId,
		cooldown = cooldown,
		readyAt = workspace:GetServerTimeNow() + cooldown,
	})

	local stats = WeaponManager.GetStats(player)
	task.delay(ability.hitFrame or 0.25, function()
		if not alive(player) or WeaponManager.GetEquipped(player) ~= weaponId then
			if ability.zone then
				zoneCount[userId] = math.max(0, (zoneCount[userId] or 1) - 1) -- the reserved slot is given back
			end
			return
		end
		if not resolve(player, ability, abilityId, weaponId, stats) and ability.zone then
			zoneCount[userId] = math.max(0, (zoneCount[userId] or 1) - 1)
		end
	end)
	return true, nil
end

local allowed = RateLimiter.new(4, 3)
castEvent.OnServerEvent:Connect(function(player, keyName)
	if type(keyName) ~= "string" or #keyName > 12 or not AbilityConfig.keys[keyName] or not allowed(player) then
		return
	end
	AbilityService.cast(player, keyName)
end)

Players.PlayerRemoving:Connect(function(player)
	AbilityService.stopAll(player)
	cooldowns[player.UserId] = nil
	lastPress[player.UserId] = nil
	zoneCount[player.UserId] = nil
end)

return AbilityService
