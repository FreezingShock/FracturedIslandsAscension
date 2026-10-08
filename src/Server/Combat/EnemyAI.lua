--[[
	EnemyAI (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyService, which calls EnemyAI.think for every living mob each step)

	The brain of a mob: a small state machine written to the model attribute AIState (so the verifier and FX can read it).
	  idle      strolls inside wanderRadius around home
	  alert     saw a target: stops and turns to it for ai.alertSeconds, then chases
	  chase     walks up to the target (attack ready) and attacks the moment one fits (EnemyAttacks.pick)
	  engage    attacks recharging: holds the ai.spacing ring around the target and circles it (ai.flank) instead of standing still
	  return    led past ai.leashRange: ignores everybody, walks home faster and heals over ai.returnHealSeconds
	Numbers: EnemyConfig.aiFor(type) (library EnemyConfig.ai < the mob table < mob.ai). A mob with no spacing walks up and stands
	still like before (the older mobs). While an attack runs (mob.attacking) the AI does nothing: EnemyAttacks owns the body.

	  EnemyAI.think(mob, now)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EnemyAttacks = require(ServerScriptService:WaitForChild("EnemyAttacks")) :: any

local STEP = 0.3 -- EnemyService's tick: the heal rate and the alert timer use it
local KNOCKBACK_PAUSE = 0.35 -- seconds after a hit the mob does not steer, so the knockback plays out

local EnemyAI = {}

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function playerRoot(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

local function setState(mob: any, state: string)
	if mob.state ~= state then
		mob.state = state
		mob.model:SetAttribute("AIState", state)
	end
end

--- The player to fight: the current one while it stays inside aggroRange * loseRange, else the nearest inside aggroRange,
--- else whoever hit the mob lately.
local function chooseTarget(mob: any, now: number): (Player?, BasePart?)
	local ai = mob.ai
	local position = mob.root.Position
	local keep = mob.targetPlayer
	local keepRoot = playerRoot(keep)
	if keep and keepRoot and flatDistance(position, keepRoot.Position) <= ai.aggroRange * ai.loseRange then
		return keep, keepRoot
	end
	local best, bestPlayer, bestRoot = ai.aggroRange, nil, nil
	for _, player in ipairs(Players:GetPlayers()) do
		local root = playerRoot(player)
		local distance = root and flatDistance(position, root.Position)
		if root and distance and distance <= best then
			best, bestPlayer, bestRoot = distance, player, root
		end
	end
	if bestPlayer then
		return bestPlayer, bestRoot
	end
	local lastHit = mob.model:GetAttribute("LastHit") or -1e9
	if now - lastHit < ai.hitAggroSeconds then
		local attacker = Players:GetPlayerByUserId(mob.model:GetAttribute("LastAttacker") or 0)
		return attacker, playerRoot(attacker)
	end
	return nil, nil
end

local function rotate(vector: Vector3, radians: number): Vector3
	local cos, sin = math.cos(radians), math.sin(radians)
	return Vector3.new(vector.X * cos - vector.Z * sin, 0, vector.X * sin + vector.Z * cos)
end

--- Holding the ring: back off when too close, circle (flank) while inside the ring, step in when too far.
local function hold(mob: any, targetRoot: BasePart, distance: number, now: number)
	local ai = mob.ai
	local position = mob.root.Position
	local toTarget = flat(targetRoot.Position - position)
	local away = toTarget.Magnitude > 0.1 and -toTarget.Unit or Vector3.new(0, 0, 1)
	if distance < ai.spacing.min * 0.5 then -- only backs off when REALLY close: attacks chain from melee range
		mob.baseSpeed = ai.walkSpeed
		mob.humanoid:MoveTo(position + away * 5)
	elseif distance > ai.spacing.max then
		mob.baseSpeed = ai.chaseSpeed
		mob.humanoid:MoveTo(targetRoot.Position)
	else
		local flank = ai.flank
		if flank then
			if now >= (mob.nextOrbitAt or 0) then
				mob.orbiting = math.random() < flank.chance
				mob.orbitDir = math.random() < 0.5 and -1 or 1
				local seconds = flank.orbitSeconds
				mob.nextOrbitAt = now + seconds[1] + math.random() * (seconds[2] - seconds[1])
			end
			if mob.orbiting then
				mob.baseSpeed = ai.walkSpeed
				-- `away` points from the target to the mob: the orbit point is on the same ring, turned a step along it
				local ringDistance = (ai.spacing.min + ai.spacing.max) / 2
				local point = targetRoot.Position + rotate(away, mob.orbitDir * 0.5) * ringDistance
				mob.humanoid:MoveTo(Vector3.new(point.X, position.Y, point.Z))
				return
			end
		end
		mob.humanoid:MoveTo(position) -- inside the ring and not circling: hold
	end
end

function EnemyAI.think(mob: any, now: number)
	local ai = mob.ai
	local model, humanoid, root = mob.model, mob.humanoid, mob.root
	if mob.attacking then
		return
	end
	local lastHit = model:GetAttribute("LastHit") or -1e9
	if now - lastHit < KNOCKBACK_PAUSE then
		return
	end
	local position = root.Position

	-- RETURN: led too far away. Nobody is fought until home is reached; the mob heals while it walks.
	if mob.returning then
		mob.baseSpeed = ai.chaseSpeed * ai.returnSpeedMult
		humanoid:MoveTo(Vector3.new(mob.home.X, position.Y, mob.home.Z))
		humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * STEP / ai.returnHealSeconds)
		if flatDistance(position, mob.home) <= ai.arriveDistance then
			mob.returning = false
			humanoid.Health = humanoid.MaxHealth
			setState(mob, "idle")
		end
	elseif flatDistance(position, mob.home) > ai.leashRange then
		mob.returning = true
		mob.targetPlayer = nil
		setState(mob, "return")
	else
		local targetPlayer, targetRoot = chooseTarget(mob, now)
		if targetPlayer and targetRoot then
			if mob.targetPlayer ~= targetPlayer then
				-- a new target: the alert beat (stop, turn, then go)
				mob.targetPlayer = targetPlayer
				mob.alertUntil = now + ai.alertSeconds
				setState(mob, "alert")
				humanoid:MoveTo(position)
				root.CFrame = CFrame.lookAt(position, Vector3.new(targetRoot.Position.X, position.Y, targetRoot.Position.Z))
			elseif mob.state == "alert" and now < mob.alertUntil then
				humanoid:MoveTo(position)
			else
				local distance = flatDistance(position, targetRoot.Position)
				local option, attack, attackId = EnemyAttacks.pick(mob, targetPlayer, distance, now)
				if option and attack and attackId then
					setState(mob, "chase")
					EnemyAttacks.run(mob, option, attack, attackId, targetPlayer)
					return
				end
				if ai.spacing and not EnemyAttacks.anyReady(mob, now) then
					setState(mob, "engage")
					hold(mob, targetRoot, distance, now)
				else
					setState(mob, "chase")
					mob.baseSpeed = ai.chaseSpeed
					if distance > ai.stopDistance then
						humanoid:MoveTo(targetRoot.Position)
					else
						humanoid:MoveTo(position)
					end
				end
			end
		else
			mob.targetPlayer = nil
			setState(mob, "idle")
			if now >= mob.nextWander then
				mob.baseSpeed = ai.walkSpeed
				local angle, radius = math.random() * math.pi * 2, math.sqrt(math.random()) * ai.wanderRadius
				humanoid:MoveTo(Vector3.new(mob.home.X + math.cos(angle) * radius, position.Y, mob.home.Z + math.sin(angle) * radius))
				mob.nextWander = now + ai.wanderEvery[1] + math.random() * (ai.wanderEvery[2] - ai.wanderEvery[1])
			end
		end
	end

	-- a slow from an ability (AbilityService sets SlowMult / SlowUntil on the model) scales whatever the AI chose
	local slowUntil = model:GetAttribute("SlowUntil")
	local slow = (type(slowUntil) == "number" and os.clock() < slowUntil) and (model:GetAttribute("SlowMult") or 1) or 1
	humanoid.WalkSpeed = (mob.baseSpeed or ai.walkSpeed) * slow
end

return EnemyAI
