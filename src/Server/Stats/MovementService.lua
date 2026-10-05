--[[
	MovementService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by MovementInit.server.lua)

	Owns the character's walk speed and sprinting.
	  * WalkSpeed = the Speed attribute from the stat chain (AttributeStatManager), times any speed factors other systems
	    register (combat slows the player while swinging). Nothing else should write Humanoid.WalkSpeed.
	  * Sprint: the client reports whether a sprint key is held (SetSprint remote, a boolean only). The server decides:
	    it needs the resource (Stamina), movement, and a living character. While sprinting it spends
	    MovementConfig.sprint.drainPerSecond per second and holds a session-only flat boost on the Speed attribute
	    (+speedBonus), so the stat chain itself reads 16 -> 32. The Player attribute `Sprinting` tells clients (FOV).

	API
	  MovementService.SetFactor(player, source, factor)   multiply walk speed by factor (nil removes it), e.g. ("combat", 0.6)
	  MovementService.IsSprinting(player)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MovementConfig = require(Modules:WaitForChild("MovementConfig")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
local ResourceService = require(ServerScriptService:WaitForChild("ResourceService")) :: any
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter")) :: any

local SPRINT = MovementConfig.sprint
local BOOST_ID = "session:sprint" -- "session:" boosts are never saved (see AttributeStatManager)
local STEP = 0.1 -- target seconds between sprint updates; the real elapsed time is what gets charged (task.wait runs long)

local MovementService = {}

-- [player] = { want = bool (a sprint key is held), sprinting = bool, exhausted = bool, factors = { [source] = number } }
local states: { [Player]: any } = {}

local SetSprintEvent = ReplicatedStorage:FindFirstChild("SetSprint")
if not SetSprintEvent then
	SetSprintEvent = Instance.new("RemoteEvent")
	SetSprintEvent.Name = "SetSprint"
	SetSprintEvent.Parent = ReplicatedStorage
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function applySpeed(player: Player)
	local state = states[player]
	local humanoid = humanoidOf(player)
	if not (state and humanoid) then
		return
	end
	local speed = tonumber(AttributeStatManager.GetFinalValue(player, SPRINT.speedStat)) or 16
	for _, factor in pairs(state.factors) do
		speed *= factor
	end
	humanoid.WalkSpeed = math.max(0, speed)
end

local function setSprinting(player: Player, on: boolean)
	local state = states[player]
	if not state or state.sprinting == on then
		return
	end
	if on then
		if not AttributeStatManager.AddFlatBoost(player, SPRINT.speedStat, "Sprint", SPRINT.speedBonus, "#FFAA00", BOOST_ID) then
			return -- stats not loaded yet; try again next step
		end
	else
		AttributeStatManager.ClearFlatBoosts(player, SPRINT.speedStat, BOOST_ID)
	end
	state.sprinting = on
	player:SetAttribute("Sprinting", on)
	applySpeed(player)
end

function MovementService.SetFactor(player: Player, source: string, factor: number?)
	local state = states[player]
	if not state then
		return
	end
	state.factors[source] = factor
	applySpeed(player)
end

function MovementService.IsSprinting(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.sprinting
end

-- ===================== PLAYERS =====================
local function onCharacter(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	state.factors = {}
	state.want = false
	setSprinting(player, false)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	applySpeed(player)
	humanoid.Died:Connect(function()
		state.want = false
		setSprinting(player, false)
	end)
end

local function onPlayer(player: Player)
	states[player] = { want = false, sprinting = false, factors = {} }
	player:SetAttribute("Sprinting", false)
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

-- the Speed attribute changed (equipment, boosts, our own sprint boost): re-apply
AttributeStatManager.Changed.Event:Connect(function(player)
	applySpeed(player)
end)

local allowed = RateLimiter.new(10, 8)
SetSprintEvent.OnServerEvent:Connect(function(player, held)
	if type(held) ~= "boolean" or not allowed(player) then
		return
	end
	local state = states[player]
	if state then
		state.want = held
	end
end)

-- ===================== SPRINT LOOP =====================
task.spawn(function()
	local last = os.clock()
	while true do
		task.wait(STEP)
		local now = os.clock()
		local dt = math.min(now - last, 0.5) -- charge the real elapsed time so the rate is exactly drainPerSecond
		last = now
		for player, state in pairs(states) do
			local humanoid = humanoidOf(player)
			local alive = humanoid ~= nil and humanoid.Health > 0
			local moving = alive and humanoid.MoveDirection.Magnitude > 0.1
			if not state.want then
				state.exhausted = false -- releasing the key clears "ran out"
			end
			if state.want and moving and not state.exhausted then
				local current = ResourceService.Get(player, SPRINT.resource)
				local canRun = state.sprinting or current >= SPRINT.minToStart
				if canRun and ResourceService.Spend(player, SPRINT.resource, SPRINT.drainPerSecond * dt) then
					setSprinting(player, true)
				else
					if state.sprinting then
						state.exhausted = true -- ran dry mid-sprint: release and press again to sprint again
					end
					setSprinting(player, false)
				end
			else
				setSprinting(player, false)
			end
		end
	end
end)

return MovementService
