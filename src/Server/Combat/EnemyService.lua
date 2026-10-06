--[[
	EnemyService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by EnemyInit.server.lua)

	Basic mobs. One mob stands on every Part in Workspace.EnemySpawns (move, add or delete markers in Studio); the part's
	attribute EnemyType picks the EnemyConfig entry (default "placeholder_mob"). A mob is cloned from
	ServerStorage[mob.template] when that model exists (drop your own rig there), else a tinted plain R6 rig is built.
	It is tagged "Damageable" (DamageService hits it) and "Enemy" (nameplate), carries the model attribute EnemyType
	(its hit effects and sounds, EnemyConfig) and respawns mob.respawnSeconds after dying.

	Behaviour (numbers in EnemyConfig.enemies[type].mob): chase the nearest player inside aggroRange, or whoever hit it
	in the last hitAggroSeconds, stop at stopDistance (no attacks yet); past leashRange from home it walks back; with
	nobody around it strolls inside wanderRadius. No loot, aggro tables or attacks: those are later slices.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local EnemyConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyConfig")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any

local STEP = 0.3
local DEFAULT_TYPE = "placeholder_mob"
local KNOCKBACK_PAUSE = 0.35 -- seconds after a hit the mob does not steer, so the knockback plays out

local EnemyService = {}

type Mob = { model: Model, humanoid: Humanoid, root: BasePart, home: Vector3, cfg: any, nextWander: number }
local mobs: { [Model]: Mob } = {}

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
	humanoid.MaxHealth = cfg.health
	humanoid.Health = cfg.health
	humanoid.WalkSpeed = cfg.walkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	model:PivotTo(marker.CFrame * CFrame.new(0, 3.1, 0)) -- an R6 root sits about 3 studs above the ground
	model:SetAttribute("EnemyType", enemyType)
	model.Parent = workspace
	CollectionService:AddTag(model, DamageService.TAG)
	CollectionService:AddTag(model, "Enemy")
	root:SetNetworkOwner(nil) -- the server owns the physics, so knockback is the same for everyone

	mobs[model] = { model = model, humanoid = humanoid, root = root, home = marker.Position, cfg = cfg, nextWander = 0 }
	humanoid.Died:Once(function()
		mobs[model] = nil
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

local function think(mob: Mob, now: number)
	local cfg = mob.cfg
	local model = mob.model
	local position = mob.root.Position
	local lastHit = model:GetAttribute("LastHit") or -1e9
	if now - lastHit < KNOCKBACK_PAUSE then
		return
	end

	-- who to chase: the nearest player in range, else whoever hit it recently
	local target: BasePart? = nil
	local best = cfg.aggroRange
	for _, player in ipairs(Players:GetPlayers()) do
		local root = playerRoot(player)
		local distance = root and flatDistance(position, root.Position)
		if root and distance and distance <= best then
			best, target = distance, root
		end
	end
	if not target and now - lastHit < cfg.hitAggroSeconds then
		target = playerRoot(Players:GetPlayerByUserId(model:GetAttribute("LastAttacker") or 0))
	end

	local humanoid = mob.humanoid
	local fromHome = flatDistance(position, mob.home)
	if target and fromHome <= cfg.leashRange then
		humanoid.WalkSpeed = cfg.chaseSpeed
		if flatDistance(position, target.Position) > cfg.stopDistance then
			humanoid:MoveTo(target.Position)
		else
			humanoid:MoveTo(position) -- arrived: stand still
		end
	elseif fromHome > cfg.leashRange then
		humanoid.WalkSpeed = cfg.chaseSpeed
		humanoid:MoveTo(Vector3.new(mob.home.X, position.Y, mob.home.Z))
	elseif now >= mob.nextWander then
		humanoid.WalkSpeed = cfg.walkSpeed
		local angle, radius = math.random() * math.pi * 2, math.sqrt(math.random()) * cfg.wanderRadius
		humanoid:MoveTo(Vector3.new(mob.home.X + math.cos(angle) * radius, position.Y, mob.home.Z + math.sin(angle) * radius))
		mob.nextWander = now + cfg.wanderEvery[1] + math.random() * (cfg.wanderEvery[2] - cfg.wanderEvery[1])
	end
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
