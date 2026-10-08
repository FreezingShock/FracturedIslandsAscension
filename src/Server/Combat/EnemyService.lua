--[[
	EnemyService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by EnemyInit.server.lua)

	Basic mobs. One mob stands on every Part in Workspace.EnemySpawns (move, add or delete markers in Studio); the part's
	attribute EnemyType picks the EnemyConfig entry (default "placeholder_mob"). A mob is cloned from
	ServerStorage[mob.template] when that model exists (drop your own rig there), else a tinted plain R6 rig is built.
	It is tagged "Damageable" (DamageService hits it) and "Enemy" (nameplate, telegraph), carries the model attribute
	EnemyType (its hit effects and sounds, EnemyConfig) and respawns mob.respawnSeconds after dying.

	Behaviour (numbers in EnemyConfig.enemies[type].mob): chase the nearest player inside aggroRange, or whoever hit it in
	the last hitAggroSeconds; past leashRange from home it walks back; with nobody around it strolls inside wanderRadius.

	Attacks (EnemyConfig.enemies[type].attacks -> EnemyConfig.attacks): in range of its target and off cooldown the mob
	picks an attack by weight, stops, faces the target and sets the model attribute Telegraph = windup seconds (the client
	flashes its body red, EnemyTelegraphController); when the windup ends a "melee" attack hurts the target if it is still
	in range and in front (DamageService.hurtPlayer: Defense applies). The next attack comes after the entry's cooldown
	{ min, max } seconds, counted from the start of the previous one.

	Death: LootService.reward gives the killer the enemy's skill XP and drops.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local EnemyConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyConfig")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any
local LootService = require(ServerScriptService:WaitForChild("LootService")) :: any
local EnemyTags = require(ServerScriptService:WaitForChild("EnemyTags")) :: any

local STEP = 0.3
local DEFAULT_TYPE = "placeholder_mob"
local KNOCKBACK_PAUSE = 0.35 -- seconds after a hit the mob does not steer, so the knockback plays out

local EnemyService = {}

type Mob = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	home: Vector3,
	cfg: any,
	entry: any,
	enemyType: string,
	nextWander: number,
	nextAttack: number,
	attacking: boolean,
	damageMult: number,
}
local mobs: { [Model]: Mob } = {}

local function between(range: any): number
	return range[1] + math.random() * ((range[2] or range[1]) - range[1])
end

local function rigFor(cfg: any): Model?
	local made = ServerStorage:FindFirstChild(cfg.template)
	if made and made:IsA("Model") then
		return made:Clone()
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not (ok and rig) then
		return nil
	end
	local colors = rig:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors", rig)
	for _, key in ipairs({ "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }) do
		colors[key] = cfg.bodyColor
	end
	for _, item in ipairs(rig:GetChildren()) do
		if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" then
			item.Color = cfg.bodyColor
		end
	end
	return rig
end

local function spawnMob(marker: BasePart)
	local attribute = marker:GetAttribute("EnemyType")
	local enemyType = type(attribute) == "string" and attribute or DEFAULT_TYPE
	local entry = EnemyConfig.enemies[enemyType]
	local cfg = entry and entry.mob
	if not cfg then
		warn(("[EnemyService] %s: EnemyType '%s' has no mob entry in EnemyConfig"):format(marker:GetFullName(), enemyType))
		return
	end
	local model = rigFor(cfg)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (model and humanoid and root) then
		warn("[EnemyService] no mob model could be built")
		return
	end
	model.Name = entry.name
	local levelInfo = EnemyConfig.levelInfo(enemyType)
	humanoid.MaxHealth = cfg.health * levelInfo.hpMult
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = cfg.walkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	model:PivotTo(marker.CFrame * CFrame.new(0, 3.1, 0)) -- an R6 root sits about 3 studs above the ground
	model:SetAttribute("EnemyType", enemyType)
	model:SetAttribute("EnemyLevel", levelInfo.level) -- the nameplate shows it; with entry.scales it also scaled health / damage
	model.Parent = workspace
	EnemyTags.stamp(model, entry) -- after the parent: tags need a live model for their expiry timers
	CollectionService:AddTag(model, DamageService.TAG)
	CollectionService:AddTag(model, "Enemy")
	root:SetNetworkOwner(nil) -- the server owns the physics, so knockback is the same for everyone

	local first = entry.attacks and entry.attacks[1]
	mobs[model] = {
		model = model,
		humanoid = humanoid,
		root = root,
		home = marker.Position,
		cfg = cfg,
		entry = entry,
		enemyType = enemyType,
		damageMult = levelInfo.damageMult,
		nextWander = 0,
		nextAttack = os.clock() + (first and between(first.cooldown or { 3, 5 }) or math.huge),
		attacking = false,
	}
	humanoid.Died:Once(function()
		mobs[model] = nil
		local ok, err = pcall(LootService.reward, model, enemyType)
		if not ok then
			warn("[EnemyService] reward failed: " .. tostring(err))
		end
		task.delay(cfg.respawnSeconds, function()
			model:Destroy()
			if marker.Parent then
				spawnMob(marker)
			end
		end)
	end)
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
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

-- ===================== ATTACKS =====================
--- An attack that is off cooldown and in range of the target, picked by weight (nil when none).
local function pickAttack(mob: Mob, distance: number, now: number): (any?, any?)
	if now < mob.nextAttack then
		return nil, nil
	end
	local choices, total = {}, 0
	for _, option in ipairs(mob.entry.attacks or {}) do
		local attack = EnemyConfig.attacks[option.attack]
		if attack and distance <= attack.range then
			table.insert(choices, { option = option, attack = attack, weight = option.weight or 1 })
			total += option.weight or 1
		end
	end
	if #choices == 0 then
		return nil, nil
	end
	local pick = math.random() * total
	for _, choice in ipairs(choices) do
		pick -= choice.weight
		if pick <= 0 then
			return choice.option, choice.attack
		end
	end
	return choices[1].option, choices[1].attack
end

local function runAttack(mob: Mob, option: any, attack: any, targetPlayer: Player)
	mob.attacking = true
	mob.nextAttack = os.clock() + between(option.cooldown or { 3, 5 })
	local model, humanoid, root = mob.model, mob.humanoid, mob.root

	humanoid:MoveTo(root.Position) -- stop and face the target for the windup
	local targetRoot = playerRoot(targetPlayer)
	if targetRoot then
		local aim = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
		root.CFrame = CFrame.lookAt(root.Position, aim)
	end
	model:SetAttribute("Telegraph", attack.windup) -- the client flashes the body red for this long

	task.delay(attack.windup, function()
		model:SetAttribute("Telegraph", nil)
		if mob.humanoid.Health > 0 and model.Parent and attack.kind == "melee" then
			local victim = playerRoot(targetPlayer)
			if victim then
				local delta = Vector3.new(victim.Position.X - root.Position.X, 0, victim.Position.Z - root.Position.Z)
				local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				local inFront = delta.Magnitude < 0.5
					or look.Magnitude < 1e-3
					or math.acos(math.clamp(look.Unit:Dot(delta.Unit), -1, 1)) <= math.rad((attack.arc or 360) / 2)
				if delta.Magnitude <= attack.range + (attack.leeway or 0) and inFront then
					DamageService.hurtPlayer(targetPlayer, attack.damage * mob.damageMult, model)
				end
			end
		end
		task.delay(attack.recover or 0.4, function()
			mob.attacking = false
		end)
	end)
end

local function think(mob: Mob, now: number)
	local cfg = mob.cfg
	local model = mob.model
	local position = mob.root.Position
	if mob.attacking then
		return
	end
	local lastHit = model:GetAttribute("LastHit") or -1e9
	if now - lastHit < KNOCKBACK_PAUSE then
		return
	end

	-- who to chase: the nearest player in range, else whoever hit it recently
	local target: BasePart? = nil
	local targetPlayer: Player? = nil
	local best = cfg.aggroRange
	for _, player in ipairs(Players:GetPlayers()) do
		local root = playerRoot(player)
		local distance = root and flatDistance(position, root.Position)
		if root and distance and distance <= best then
			best, target, targetPlayer = distance, root, player
		end
	end
	if not target and now - lastHit < cfg.hitAggroSeconds then
		targetPlayer = Players:GetPlayerByUserId(model:GetAttribute("LastAttacker") or 0)
		target = playerRoot(targetPlayer)
	end

	local humanoid = mob.humanoid
	local fromHome = flatDistance(position, mob.home)
	if target and targetPlayer and fromHome <= cfg.leashRange then
		mob.baseSpeed = cfg.chaseSpeed
		local distance = flatDistance(position, target.Position)
		local option, attack = pickAttack(mob, distance, now)
		if option and attack then
			runAttack(mob, option, attack, targetPlayer)
		elseif distance > cfg.stopDistance then
			humanoid:MoveTo(target.Position)
		else
			humanoid:MoveTo(position) -- arrived: stand still
		end
	elseif fromHome > cfg.leashRange then
		mob.baseSpeed = cfg.chaseSpeed
		humanoid:MoveTo(Vector3.new(mob.home.X, position.Y, mob.home.Z))
	elseif now >= mob.nextWander then
		mob.baseSpeed = cfg.walkSpeed
		local angle, radius = math.random() * math.pi * 2, math.sqrt(math.random()) * cfg.wanderRadius
		humanoid:MoveTo(Vector3.new(mob.home.X + math.cos(angle) * radius, position.Y, mob.home.Z + math.sin(angle) * radius))
		mob.nextWander = now + cfg.wanderEvery[1] + math.random() * (cfg.wanderEvery[2] - cfg.wanderEvery[1])
	end

	-- a slow from an ability (AbilityService sets SlowMult / SlowUntil on the model) scales whatever the AI chose
	local slowUntil = model:GetAttribute("SlowUntil")
	local slow = (type(slowUntil) == "number" and os.clock() < slowUntil) and (model:GetAttribute("SlowMult") or 1) or 1
	humanoid.WalkSpeed = (mob.baseSpeed or cfg.walkSpeed) * slow
end

function EnemyService.start()
	local markers = workspace:WaitForChild("EnemySpawns", 10)
	if not markers then
		warn("[EnemyService] Workspace.EnemySpawns is missing: no mobs will spawn")
		return
	end
	for _, marker in ipairs(markers:GetChildren()) do
		if marker:IsA("BasePart") then
			spawnMob(marker)
		end
	end
	markers.ChildAdded:Connect(function(marker)
		if marker:IsA("BasePart") then
			spawnMob(marker)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(STEP)
			local now = os.clock()
			for _, mob in pairs(mobs) do
				if mob.humanoid.Health > 0 and mob.root.Parent then
					think(mob, now)
				end
			end
		end
	end)
end

EnemyService.start()
return EnemyService
