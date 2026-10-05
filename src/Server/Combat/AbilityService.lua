--[[
	AbilityService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by AbilityInit.server.lua)

	Server-authoritative key abilities (AbilityConfig: Overload, Holy Nova, ...). The client only says "I pressed this key"
	on the AbilityCast remote; it never sends a target, a position or an ability id. The server decides:

	  1. the player holds a weapon whose item lists an ability bound to that key (AbilityConfig.byKey)
	  2. alive, the ability is off cooldown, fewer than AbilityConfig.maxZonesPerPlayer zones are running
	  3. enough Mana (ResourceService.Spend; mana regenerates by itself after the last spend)
	Then it locks the combo for castTime, broadcasts the cast (every client plays the animation-free effects: sound, ring,
	embers), and at `hitFrame` hits whatever the ability's shape covers (DamageService.strike: Strength and crit apply).
	An ability with a `zone` keeps striking every tickInterval until its duration ends (following the caster if asked).

	AbilityCast remote
	  client -> server   FireServer(keyName)                     "Q", "RMB", ...
	  server -> clients  { caster = Player, abilityId, weaponId, cooldown, readyAt }   readyAt is workspace:GetServerTimeNow()

	API
	  AbilityService.cast(player, keyName) -> ok, reason    reason: no_weapon | no_ability | dead | cooldown | zones | mana
	  AbilityService.cooldownLeft(player, abilityId)        -> seconds
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AbilityConfig = require(Modules:WaitForChild("AbilityConfig")) :: any
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry")) :: any
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter")) :: any
local WeaponManager = require(ServerScriptService:WaitForChild("WeaponManager")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any
local ResourceService = require(ServerScriptService:WaitForChild("ResourceService")) :: any

local AbilityService = {}

local CastEvent = ReplicatedStorage:FindFirstChild("AbilityCast") :: RemoteEvent?
if not CastEvent then
	CastEvent = Instance.new("RemoteEvent")
	CastEvent.Name = "AbilityCast"
	CastEvent.Parent = ReplicatedStorage
end
local castEvent = CastEvent :: RemoteEvent

-- [userId] = { [abilityId] = readyAtClock }
local cooldowns: { [number]: { [string]: number } } = {}
-- [userId] = zones currently running
local zoneCount: { [number]: number } = {}

local function alive(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and player.Parent == Players
end

function AbilityService.cooldownLeft(player: Player, abilityId: string): number
	local readyAt = cooldowns[player.UserId] and cooldowns[player.UserId][abilityId]
	return readyAt and math.max(0, readyAt - os.clock()) or 0
end

--- A zone: strike now (if tickOnCast) and then every tickInterval until `duration` has passed.
local function runZone(player: Player, ability: any, weaponId: string, weaponStats: any)
	local zone = ability.zone
	local startedAt = os.clock()
	local nextTick = zone.tickOnCast == false and zone.tickInterval or 0
	while true do
		local elapsed = os.clock() - startedAt
		if elapsed >= zone.duration - 1e-3 or not alive(player) then
			break
		end
		if elapsed >= nextTick then
			nextTick += zone.tickInterval
			DamageService.strike(player, ability, weaponId, weaponStats)
		end
		task.wait(0.1)
	end
	zoneCount[player.UserId] = math.max(0, (zoneCount[player.UserId] or 1) - 1)
end

function AbilityService.cast(player: Player, keyName: string): (boolean, string?)
	local weaponId = WeaponManager.GetEquipped(player)
	local weapon = weaponId and WeaponRegistry.get(weaponId)
	local character = player.Character
	if not (weapon and character and character:FindFirstChild(weapon.toolName)) then
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
	local userId = player.UserId
	if ability.zone and (zoneCount[userId] or 0) >= AbilityConfig.maxZonesPerPlayer then
		return false, "zones"
	end
	if not ResourceService.Spend(player, "Mana", ability.manaCost or 0) then
		return false, "mana"
	end

	-- accepted
	local cooldown = ability.cooldown or 0
	cooldowns[userId] = cooldowns[userId] or {}
	cooldowns[userId][abilityId] = os.clock() + cooldown
	WeaponManager.Lock(player, ability.castTime or 0.5)
	if ability.zone then
		zoneCount[userId] = (zoneCount[userId] or 0) + 1
	end

	castEvent:FireAllClients({
		caster = player,
		abilityId = abilityId,
		weaponId = weaponId,
		cooldown = cooldown,
		readyAt = workspace:GetServerTimeNow() + cooldown,
	})

	local weaponStats = WeaponManager.GetStats(player)
	task.delay(ability.hitFrame or 0.25, function()
		if not alive(player) or WeaponManager.GetEquipped(player) ~= weaponId then
			if ability.zone then
				zoneCount[userId] = math.max(0, (zoneCount[userId] or 1) - 1)
			end
			return
		end
		if ability.zone then
			runZone(player, ability, weaponId, weaponStats)
		else
			DamageService.strike(player, ability, weaponId, weaponStats)
		end
	end)
	return true, nil
end

local allowed = RateLimiter.new(4, 3)
castEvent.OnServerEvent:Connect(function(player, keyName)
	if type(keyName) ~= "string" or #keyName > 12 or not allowed(player) then
		return
	end
	AbilityService.cast(player, keyName)
end)

Players.PlayerRemoving:Connect(function(player)
	cooldowns[player.UserId] = nil
	zoneCount[player.UserId] = nil
end)

return AbilityService
