--[[
	DamageTracker (ModuleScript, Server)
	Place inside: ServerScriptService

	Server-authoritative DPS. DamageService records every hit's final damage (DamageTracker.record); this module keeps a
	short per-player history and publishes the Player attribute named by ViewMenuConfig.dps.attribute ("DPS"):
	the damage dealt in the last `window` seconds divided by `window`, rounded, at most every `publish` seconds and only
	when it changed. Clients (the ViewMenu DPS row) only render the attribute.

	  DamageTracker.record(player, amount)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ViewMenuConfig = require(Modules:WaitForChild("Config"):WaitForChild("ViewMenuConfig")) :: any

local DPS = ViewMenuConfig.dps

local DamageTracker = {}

-- [player] = { times = {}, amounts = {}, head = 1, last = nil }
local history: { [Player]: any } = {}

local function stateOf(player: Player)
	local state = history[player]
	if not state then
		state = { times = {}, amounts = {}, head = 1, last = nil }
		history[player] = state
	end
	return state
end

function DamageTracker.record(player: Player, amount: number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	local state = stateOf(player)
	table.insert(state.times, os.clock())
	table.insert(state.amounts, amount)
end

local function currentDps(state: any, now: number): number
	local cutoff = now - DPS.window
	local times, amounts = state.times, state.amounts
	while state.head <= #times and times[state.head] < cutoff do
		state.head += 1
	end
	if state.head > 64 then -- compact the consumed front of the arrays
		local n = #times - state.head + 1
		table.move(times, state.head, #times, 1)
		table.move(amounts, state.head, #amounts, 1)
		for i = n + 1, #times do
			times[i] = nil
			amounts[i] = nil
		end
		state.head = 1
	end
	local sum = 0
	for i = state.head, #times do
		sum += amounts[i]
	end
	return math.floor(sum / DPS.window + 0.5)
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < DPS.publish then
		return
	end
	accumulator = 0
	local now = os.clock()
	for player, state in pairs(history) do
		local value = currentDps(state, now)
		if value ~= state.last then
			state.last = value
			player:SetAttribute(DPS.attribute, value)
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	player:SetAttribute(DPS.attribute, 0)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player:SetAttribute(DPS.attribute, 0)
end
Players.PlayerRemoving:Connect(function(player)
	history[player] = nil
end)

return DamageTracker
