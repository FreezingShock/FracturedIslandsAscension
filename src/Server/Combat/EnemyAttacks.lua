--[[
	EnemyAttacks (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyAI / EnemyService)

	What a mob does when it attacks. EnemyConfig.enemies[type].attacks lists { attack = "<id>", weight, cooldown } options; each id is an
	EnemyConfig.attacks entry whose `kind` picks a runner below (melee, combo, lunge, slam, parry). New kind = add a runner to RUNNERS.

	  pick(mob, targetPlayer, distance, now)   an option + attack whose cooldown is up, distance window fits, level / condition pass,
	                                           chosen by weight (the previous attack is penalised for variety)
	  anyReady(mob, now)                       an unconditional attack is off cooldown (the AI closes in instead of holding its ring)
	  run(mob, option, attack, targetPlayer)   starts the attack on its own thread; mob.attacking is true until it ends

	The server owns everything: hit shapes, damage (DamageService.hurtPlayer, Defense applies, damage x level multiplier), cooldowns.
	Clients only get the RemoteEvent EnemyAttack (payload tables, they send nothing) so every player in range SEES the telegraph, swing
	and impact (EnemyAttackFXController):
	  { kind = "telegraph", model, attackId, shape, color, origin, dir, range, arc, radius, length, width, duration }
	  { kind = "swing", model, duration }   { kind = "impact", model, origin, radius }   { kind = "parry", model, duration }

	Animation: a move's `animationId` (or `animation` key of CombatConfig.animations) is played on the mob's Animator; with neither,
	the procedural pose (EnemyConfig.poses, a Motor6D tween) is used. When the animation has the marker `hitMarker` the hit lands
	on it, else on the timing numbers (hitFrame). Sounds: `soundId` on a move is played from the mob (silent when empty).
	Model attributes written for the verifier / FX: Attack (current id), AttackCount_<id>, Blocking.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local EnemyConfig = require(Modules:WaitForChild("EnemyConfig")) :: any
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any

local VIEW_DISTANCE = 150 -- studs: players farther away do not get the effect messages
local SWING_HOLD = 0.35 -- seconds a pose is held after the hit before it relaxes

local EnemyAttacks = {}

local remote = ReplicatedStorage:FindFirstChild("EnemyAttack") :: RemoteEvent?
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "EnemyAttack"
	remote.Parent = ReplicatedStorage
end

-- ===================== HELPERS =====================
local function between(range: any): number
	return range[1] + math.random() * ((range[2] or range[1]) - range[1])
end

local function alive(mob: any): boolean
	return mob.humanoid.Health > 0 and mob.model.Parent ~= nil
end

--- Wait; false when the mob died meanwhile (every runner stops there).
local function pause(mob: any, seconds: number): boolean
	if seconds > 0 then
		task.wait(seconds)
	end
	return alive(mob)
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

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function broadcast(mob: any, payload: any)
	payload.model = mob.model
	local origin = mob.root.Position
	for _, player in ipairs(Players:GetPlayers()) do
		local root = playerRoot(player)
		if root and (root.Position - origin).Magnitude <= VIEW_DISTANCE then
			(remote :: RemoteEvent):FireClient(player, payload)
		end
	end
end

local function face(mob: any, targetRoot: BasePart?)
	if not targetRoot then
		return
	end
	local position = mob.root.Position
	mob.root.CFrame = CFrame.lookAt(position, Vector3.new(targetRoot.Position.X, position.Y, targetRoot.Position.Z))
end

local function groundPoint(mob: any): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { mob.model }
	local result = workspace:Raycast(mob.root.Position, Vector3.new(0, -8, 0), params)
	return result and result.Position or (mob.root.Position - Vector3.new(0, 3, 0))
end

local function hurt(mob: any, player: Player, attack: any, multiplier: number?)
	DamageService.hurtPlayer(player, attack.damage * mob.damageMult * (multiplier or 1), mob.model)
end

--- Players hit by a cone in front of the mob (range + leeway studs, arc degrees).
local function playersInCone(mob: any, attack: any): { Player }
	local hits = {}
	local origin = mob.root.Position
	local look = flat(mob.root.CFrame.LookVector)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = playerRoot(player)
		if root then
			local delta = flat(root.Position - origin)
			if delta.Magnitude <= attack.range + (attack.leeway or 0) and math.abs(root.Position.Y - origin.Y) <= 8 then
				local inFront = delta.Magnitude < 0.5
					or look.Magnitude < 1e-3
					or math.acos(math.clamp(look.Unit:Dot(delta.Unit), -1, 1)) <= math.rad((attack.arc or 360) / 2)
				if inFront then
					table.insert(hits, player)
				end
			end
		end
	end
	return hits
end

local function playersInRadius(origin: Vector3, radius: number): { Player }
	local hits = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local root = playerRoot(player)
		if root and flat(root.Position - origin).Magnitude <= radius and math.abs(root.Position.Y - origin.Y) <= 8 then
			table.insert(hits, player)
		end
	end
	return hits
end

-- ===================== ANIMATION / POSES =====================
local function animatorOf(mob: any): Animator
	local animator = mob.humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = mob.humanoid
	end
	return animator :: Animator
end

--- Plays the move's (or the step's) animation; nil when no id is set (the pose is the fallback).
local function playAnimation(mob: any, attack: any, key: string?): AnimationTrack?
	local id = attack.animationId
	local entry = key and CombatConfig.animations[key]
	if (id == nil or id == "") and entry then
		id = entry.id
	end
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local track = mob.tracks[id]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, loaded = pcall(function()
			return animatorOf(mob):LoadAnimation(animation)
		end)
		if not ok then
			return nil
		end
		track = loaded
		track.Priority = Enum.AnimationPriority.Action
		mob.tracks[id] = track
	end
	track:Play(entry and entry.fade or 0.1)
	return track
end

local function shoulder(mob: any, name: string): Motor6D?
	local torso = mob.model:FindFirstChild("Torso")
	local motor = torso and torso:FindFirstChild(name)
	if motor and motor:IsA("Motor6D") then
		if not mob.baseC0[motor] then
			mob.baseC0[motor] = motor.C0
		end
		return motor
	end
	return nil
end

--- Procedural pose: tween the shoulders to the named EnemyConfig.poses entry (nil = back to rest).
local function pose(mob: any, name: string?)
	local entry = name and EnemyConfig.poses[name]
	for _, motorName in ipairs({ "Right Shoulder", "Left Shoulder" }) do
		local motor = shoulder(mob, motorName)
		if motor then
			local key = motorName == "Right Shoulder" and "rightShoulder" or "leftShoulder"
			local euler = entry and entry[key]
			local target = mob.baseC0[motor]
			if euler then
				target = target * CFrame.Angles(math.rad(euler.X), math.rad(euler.Y), math.rad(euler.Z))
			end
			TweenService:Create(motor, TweenInfo.new(entry and entry.time or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = target }):Play()
		end
	end
end

--- Waits for the hit moment of a swing: the animation marker when the move names one and an animation plays, else the timing.
local function waitHit(mob: any, track: AnimationTrack?, marker: string?, fallback: number): boolean
	if track and marker then
		local reached = false
		local connection = track:GetMarkerReachedSignal(marker):Connect(function()
			reached = true
		end)
		local started = os.clock()
		while not reached and os.clock() - started < fallback * 2 + 0.3 and alive(mob) do
			task.wait()
		end
		connection:Disconnect()
		return alive(mob)
	end
	return pause(mob, fallback)
end

--- The player's own attack sounds (CombatConfig.sounds): `key` (a combo step's sound) or the move's `sound` key; 3D from the blade.
--- A raw `soundId` on the move still works. Silent when neither names an id.
local function playSound(mob: any, attack: any, key: string?)
	local entry = CombatConfig.sounds[key or attack.sound or ""]
	local id = entry and entry.id
	if type(id) ~= "string" or id == "" then
		id = attack.soundId
		entry = nil
	end
	if type(id) ~= "string" or id == "" then
		return
	end
	local sword = mob.model:FindFirstChild("Sword")
	local parent = (sword and sword:FindFirstChild("Blade")) or mob.root
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = entry and entry.volume or 0.8
	local pitch = entry and entry.pitch
	sound.PlaybackSpeed = pitch and (pitch[1] + math.random() * (pitch[2] - pitch[1])) or 1
	sound.RollOffMinDistance = entry and entry.minDistance or 12
	sound.RollOffMaxDistance = entry and entry.maxDistance or 90
	sound.Parent = parent
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

local function telegraph(mob: any, attack: any, attackId: string, windup: number, direction: Vector3)
	local info = attack.telegraph
	mob.model:SetAttribute("Telegraph", windup) -- the body flash (EnemyTelegraphController)
	if not info or info.shape == "none" then
		return
	end
	broadcast(mob, {
		kind = "telegraph",
		attackId = attackId,
		shape = info.shape,
		color = info.color,
		origin = groundPoint(mob),
		dir = direction,
		range = attack.range + (attack.leeway or 0),
		arc = attack.arc,
		radius = attack.radius,
		length = attack.dash and attack.dash.distance or attack.range,
		width = info.width,
		duration = windup,
	})
end

-- ===================== RUNNERS =====================
-- each runner(mob, attackId, attack, targetPlayer) runs on its own thread; return early when the mob died (pause() = false)
local RUNNERS: { [string]: (any, string, any, Player) -> () } = {}

--- Faces the target; with attack.missChance the swing is aimed 40-65 degrees off (a real miss: the telegraph shows it too).
local function aimAt(mob: any, targetPlayer: Player, attack: any?): Vector3
	local targetRoot = playerRoot(targetPlayer)
	face(mob, targetRoot)
	if attack and attack.missChance and math.random() < attack.missChance then
		local sign = math.random() < 0.5 and -1 or 1
		mob.root.CFrame *= CFrame.Angles(0, sign * math.rad(40 + math.random() * 25), 0)
	end
	local look = flat(mob.root.CFrame.LookVector)
	return look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
end

RUNNERS.melee = function(mob, attackId, attack, targetPlayer)
	local direction = aimAt(mob, targetPlayer, attack)
	telegraph(mob, attack, attackId, attack.windup, direction)
	if not pause(mob, attack.windup) then
		return
	end
	mob.model:SetAttribute("Telegraph", nil)
	playSound(mob, attack)
	for _, player in ipairs(playersInCone(mob, attack)) do
		hurt(mob, player, attack)
	end
	pause(mob, attack.recover or 0.4)
end

RUNNERS.combo = function(mob, attackId, attack, targetPlayer)
	local weaponType = CombatConfig[attack.weaponType or "sword"]
	local steps = weaponType and weaponType.steps
	if not steps then
		return
	end
	for index, step in ipairs(steps) do
		if not alive(mob) or not playerRoot(targetPlayer) then
			break
		end
		local direction = aimAt(mob, targetPlayer, attack)
		local windup = index == 1 and attack.windup or attack.chainWindup
		telegraph(mob, attack, attackId, windup, direction)
		if not pause(mob, windup) then
			return
		end
		mob.model:SetAttribute("Telegraph", nil)
		local track = playAnimation(mob, attack, step.animation)
		if not track then
			pose(mob, attack.pose or "raise")
		end
		broadcast(mob, { kind = "swing", duration = step.duration })
		-- a small step into the swing so the combo closes the gap a little
		local look = flat(mob.root.CFrame.LookVector)
		mob.root.AssemblyLinearVelocity = Vector3.new(look.X * 10, mob.root.AssemblyLinearVelocity.Y, look.Z * 10)
		if not waitHit(mob, track, attack.hitMarker, step.hitFrame) then
			return
		end
		playSound(mob, attack, step.sound) -- the player's sound for this step, at the moment the blade lands
		local multiplier = index == #steps and (attack.finisherMult or 1) or 1
		for _, player in ipairs(playersInCone(mob, attack)) do
			hurt(mob, player, attack, multiplier)
		end
		if not pause(mob, math.max(step.duration - step.hitFrame, 0) + (step.recovery or 0)) then
			return
		end
		if not track then
			pose(mob, nil)
		end
		-- keep swinging while the target is still close
		local victim = playerRoot(targetPlayer)
		if not victim or flat(victim.Position - mob.root.Position).Magnitude > attack.range * (attack.chainReach or 1.4) then
			break
		end
	end
	pose(mob, nil)
	pause(mob, attack.recover or 0.5)
end

RUNNERS.lunge = function(mob, attackId, attack, targetPlayer)
	local direction = aimAt(mob, targetPlayer, attack)
	telegraph(mob, attack, attackId, attack.windup, direction)
	pose(mob, attack.pose)
	if not pause(mob, attack.windup) then
		return
	end
	mob.model:SetAttribute("Telegraph", nil)
	broadcast(mob, { kind = "swing", duration = 0.4 })
	playSound(mob, attack)
	local speed = attack.dash.speed
	local duration = attack.dash.distance / speed
	local started = os.clock()
	local struck: { [Player]: boolean } = {}
	while os.clock() - started < duration and alive(mob) do
		local velocity = mob.root.AssemblyLinearVelocity
		mob.root.AssemblyLinearVelocity = Vector3.new(direction.X * speed, velocity.Y, direction.Z * speed)
		for _, player in ipairs(playersInRadius(mob.root.Position, attack.hitRadius)) do
			if not struck[player] then
				struck[player] = true
				hurt(mob, player, attack)
			end
		end
		RunService.Heartbeat:Wait()
	end
	if alive(mob) then
		mob.root.AssemblyLinearVelocity = Vector3.new(0, mob.root.AssemblyLinearVelocity.Y, 0)
	end
	if not pause(mob, SWING_HOLD) then
		return
	end
	pose(mob, nil)
	pause(mob, attack.recover or 0.6)
end

RUNNERS.slam = function(mob, attackId, attack, targetPlayer)
	aimAt(mob, targetPlayer)
	telegraph(mob, attack, attackId, attack.windup, Vector3.new(0, 0, -1))
	pose(mob, attack.pose)
	if not pause(mob, attack.windup) then
		return
	end
	mob.model:SetAttribute("Telegraph", nil)
	broadcast(mob, { kind = "swing", duration = 0.4 })
	broadcast(mob, { kind = "impact", origin = groundPoint(mob), radius = attack.radius })
	playSound(mob, attack)
	for _, player in ipairs(playersInRadius(mob.root.Position, attack.radius)) do
		hurt(mob, player, attack)
	end
	if not pause(mob, SWING_HOLD) then
		return
	end
	pose(mob, nil)
	pause(mob, attack.recover or 0.8)
end

RUNNERS.parry = function(mob, attackId, attack, targetPlayer)
	aimAt(mob, targetPlayer)
	pose(mob, attack.pose)
	if not pause(mob, attack.windup) then
		return
	end
	playSound(mob, attack)
	mob.model:SetAttribute("DamageTakenMult", attack.damageTaken) -- DamageService scales every hit it takes meanwhile
	mob.model:SetAttribute("Blocking", true)
	broadcast(mob, { kind = "parry", duration = attack.duration })
	local started = os.clock()
	while os.clock() - started < attack.duration and alive(mob) do
		face(mob, playerRoot(targetPlayer))
		task.wait(0.1)
	end
	mob.model:SetAttribute("DamageTakenMult", nil)
	mob.model:SetAttribute("Blocking", nil)
	if not alive(mob) then
		return
	end
	pose(mob, nil)
	pause(mob, attack.recover or 0.3)
end

-- ===================== PICK / RUN =====================
--- Sets every option's first cooldown (a mob does not open with its whole kit at the same moment it spawns).
function EnemyAttacks.initCooldowns(mob: any, now: number)
	for _, option in ipairs(mob.entry.attacks or {}) do
		mob.cooldowns[option.attack] = now + between(option.cooldown or { 3, 5 })
	end
end

local function swungRecently(player: Player): boolean
	local last = player:GetAttribute("LastSwing")
	return type(last) == "number" and workspace:GetServerTimeNow() - last <= 0.5
end

function EnemyAttacks.pick(mob: any, targetPlayer: Player, distance: number, now: number): (any?, any?, string?)
	if now < mob.nextAttackAt then
		return nil, nil, nil
	end
	local choices, total = {}, 0
	for _, option in ipairs(mob.entry.attacks or {}) do
		local attack = EnemyConfig.attacks[option.attack]
		if
			attack
			and (mob.cooldowns[option.attack] or 0) <= now
			and distance <= attack.range
			and distance >= (attack.minRange or 0)
			and (attack.minLevel == nil or mob.level >= attack.minLevel)
			and (attack.condition ~= "targetSwung" or swungRecently(targetPlayer))
		then
			local weight = (option.weight or 1) * (option.attack == mob.lastAttackId and mob.ai.repeatPenalty or 1)
			table.insert(choices, { option = option, attack = attack, weight = weight })
			total += weight
		end
	end
	if #choices == 0 then
		return nil, nil, nil
	end
	local pick = math.random() * total
	for _, choice in ipairs(choices) do
		pick -= choice.weight
		if pick <= 0 then
			return choice.option, choice.attack, choice.option.attack
		end
	end
	return choices[1].option, choices[1].attack, choices[1].option.attack
end

function EnemyAttacks.anyReady(mob: any, now: number): boolean
	if now < mob.nextAttackAt then
		return false
	end
	for _, option in ipairs(mob.entry.attacks or {}) do
		local attack = EnemyConfig.attacks[option.attack]
		if attack and attack.condition == nil and (mob.cooldowns[option.attack] or 0) <= now and (attack.minLevel == nil or mob.level >= attack.minLevel) then
			return true
		end
	end
	return false
end

function EnemyAttacks.run(mob: any, option: any, attack: any, attackId: string, targetPlayer: Player)
	local runner = RUNNERS[attack.kind]
	if not runner then
		warn("[EnemyAttacks] no runner for attack kind '" .. tostring(attack.kind) .. "' (" .. attackId .. ")")
		return
	end
	mob.attacking = true
	mob.lastAttackId = attackId
	mob.cooldowns[attackId] = os.clock() + between(option.cooldown or { 3, 5 })
	mob.humanoid:MoveTo(mob.root.Position) -- stand still for the move
	mob.model:SetAttribute("Attack", attackId)
	mob.model:SetAttribute("AttackCount_" .. attackId, (mob.model:GetAttribute("AttackCount_" .. attackId) or 0) + 1)
	task.spawn(function()
		local ok, err = pcall(runner, mob, attackId, attack, targetPlayer)
		if not ok then
			warn("[EnemyAttacks] " .. attackId .. " failed: " .. tostring(err))
		end
		if mob.model.Parent then
			mob.model:SetAttribute("Telegraph", nil)
			mob.model:SetAttribute("Attack", nil)
			mob.model:SetAttribute("DamageTakenMult", nil)
			mob.model:SetAttribute("Blocking", nil)
		end
		mob.nextAttackAt = os.clock() + mob.ai.attackGap
		mob.attacking = false
		if mob.wake and alive(mob) then
			mob.wake() -- decide the next move right now: no pause, no re-route between two attacks
		end
	end)
end

return EnemyAttacks
