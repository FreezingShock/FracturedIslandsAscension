--[[
	ResourceService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by ResourceInit.server.lua)

	Server-authoritative Health / Mana / Stamina, driven entirely by ResourceConfig.
	  * Each resource is published as Player attributes: <Key> (current) and Max<Key> (maximum). Clients only read them.
	  * Health IS the character's Humanoid (Humanoid.Health / MaxHealth); the attribute mirrors it. Roblox's built-in
	    regeneration is removed and replaced by the HealthRegen stat (percent of max per second, after a no-damage delay).
	  * Maximums come from the stat chain (AttributeStatManager) and are recomputed whenever stats change. The fill
	    percentage is kept, so equipping +Defense never leaves you "at 100%" of a different number.
	  * Mana and Stamina sit at their maximum until spells / sprint spend them (API below).

	API
	  ResourceService.Get(player, key)            -> current, max
	  ResourceService.Spend(player, key, amount)  -> true if there was enough (and it was taken)
	  ResourceService.Restore(player, key, amount)
	  ResourceService.Refill(player, key?)        -> fills one resource, or all
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any

local ResourceService = {}

-- [player] = { values = { [key] = current }, max = { [key] = max }, lastHit = { [key] = clock }, lastHealth = number, applying = bool }
local states: { [Player]: any } = {}

local function statGetter(player: Player)
	return function(statKey: string): number
		return tonumber(AttributeStatManager.GetFinalValue(player, statKey)) or 0
	end
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function publish(player: Player, entry: any, state: any)
	local key = entry.key
	local humanoid = entry.source == "humanoid" and humanoidOf(player) or nil
	local current = humanoid and humanoid.Health or state.values[key] or 0
	player:SetAttribute(key, current)
	player:SetAttribute("Max" .. key, state.max[key] or 0)
end

--- Recompute every maximum from the stat chain, keep each resource's fill percentage, publish the attributes.
--- fill = true sets everything to full (spawn / respawn).
local function recompute(player: Player, fill: boolean?)
	local state = states[player]
	if not state then
		return
	end
	local stat = statGetter(player)
	for _, entry in ipairs(ResourceConfig.resources) do
		local key = entry.key
		local newMax = math.max(1, math.floor(entry.max(stat) + 0.5))
		local oldMax = state.max[key]
		state.max[key] = newMax

		if entry.source == "humanoid" then
			local humanoid = humanoidOf(player)
			if humanoid and (fill or humanoid.MaxHealth ~= newMax) then
				local pct = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
				state.applying = true
				humanoid.MaxHealth = newMax
				if humanoid.Health > 0 then
					humanoid.Health = (fill and entry.startFull ~= false) and newMax or newMax * pct
				end
				state.applying = false
				state.lastHealth = humanoid.Health
			end
		else
			local current = state.values[key]
			if current == nil or (fill and entry.startFull ~= false) then
				state.values[key] = newMax
			elseif oldMax and oldMax ~= newMax then
				state.values[key] = math.clamp(newMax * (current / oldMax), 0, newMax)
			else
				state.values[key] = math.clamp(current, 0, newMax)
			end
		end
		publish(player, entry, state)
	end
end

-- ===================== CHARACTER =====================
local function onCharacter(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end

	-- Roblox's own regeneration script would fight HealthRegen; ours replaces it
	local default = character:WaitForChild("Health", 2)
	if default and default:IsA("Script") then
		default:Destroy()
	end

	recompute(player, true)
	state.lastHealth = humanoid.Health
	state.lastHit.Health = 0

	humanoid.HealthChanged:Connect(function(health)
		if states[player] ~= state then
			return
		end
		if not state.applying and health < (state.lastHealth or health) - 1e-3 then
			state.lastHit.Health = os.clock() -- took damage: regeneration pauses
		end
		state.lastHealth = health
		player:SetAttribute("Health", health)
	end)
	humanoid.Died:Connect(function()
		player:SetAttribute("Health", 0)
	end)
end

local function onPlayer(player: Player)
	states[player] = { values = {}, max = {}, lastHit = {}, applying = false }
	-- Nexus Level (shown in the HUD badge): a placeholder until its progression is built, so it stays at the start value
	player:SetAttribute(ResourceConfig.nexusLevelAttribute, ResourceConfig.nexusLevelStart)
	recompute(player, true) -- attributes exist from the first moment (mana / stamina); health follows with the character
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, player)
end
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

-- stats changed (equipment, boosts, levelling): resize the maximums now
AttributeStatManager.Changed.Event:Connect(function(player)
	recompute(player, false)
end)

-- ===================== REGENERATION =====================
task.spawn(function()
	while true do
		task.wait(ResourceConfig.TICK)
		for player, state in pairs(states) do
			recompute(player, false) -- also catches any stat change that did not announce itself
			local stat = statGetter(player)
			for _, entry in ipairs(ResourceConfig.resources) do
				local regen = entry.regen
				if regen then
					local key = entry.key
					local amount = regen.stat and stat(regen.stat) or regen.amount or 0
					local idleFor = os.clock() - (state.lastHit[key] or 0)
					if amount > 0 and idleFor >= (regen.delay or 0) then
						local perTick = regen.unit == "percentPerSecond" and state.max[key] * amount / 100 or amount
						perTick *= ResourceConfig.TICK
						if entry.source == "humanoid" then
							local humanoid = humanoidOf(player)
							if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
								humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + perTick)
							end
						else
							state.values[key] = math.min(state.max[key], (state.values[key] or 0) + perTick)
							publish(player, entry, state)
						end
					end
				end
			end
		end
	end
end)

-- ===================== API =====================
function ResourceService.Get(player: Player, key: string): (number, number)
	local state = states[player]
	local entry = ResourceConfig.byKey[key]
	if not (state and entry) then
		return 0, 0
	end
	local humanoid = entry.source == "humanoid" and humanoidOf(player) or nil
	return humanoid and humanoid.Health or state.values[key] or 0, state.max[key] or 0
end

function ResourceService.Spend(player: Player, key: string, amount: number): boolean
	local state = states[player]
	local entry = ResourceConfig.byKey[key]
	if not (state and entry) or entry.source == "humanoid" or amount < 0 then
		return false -- health is spent by taking damage, not through this
	end
	local current = state.values[key] or 0
	if current < amount then
		return false
	end
	state.values[key] = current - amount
	state.lastHit[key] = os.clock() -- regeneration delay starts from the last spend
	publish(player, entry, state)
	return true
end

function ResourceService.Restore(player: Player, key: string, amount: number)
	local state = states[player]
	local entry = ResourceConfig.byKey[key]
	if not (state and entry) then
		return
	end
	if entry.source == "humanoid" then
		local humanoid = humanoidOf(player)
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + amount)
		end
	else
		state.values[key] = math.clamp((state.values[key] or 0) + amount, 0, state.max[key] or 0)
		publish(player, entry, state)
	end
end

function ResourceService.Refill(player: Player, key: string?)
	for _, entry in ipairs(ResourceConfig.resources) do
		if not key or entry.key == key then
			local state = states[player]
			if state then
				ResourceService.Restore(player, entry.key, state.max[entry.key] or 0)
			end
		end
	end
end

return ResourceService
