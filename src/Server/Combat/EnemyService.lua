--[[
	EnemyService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by EnemyInit.server.lua)

	Spawns and removes mobs. One mob stands on every Part in Workspace.EnemySpawns (move, add or delete markers in Studio); the part's
	attribute EnemyType picks the EnemyConfig entry (default "placeholder_mob"). The body comes from EnemyRig (a ServerStorage
	template when it exists, else a tinted R6 rig, plus the mob.weapon sword). It is tagged "Damageable" (DamageService hits it) and
	"Enemy" (nameplate, telegraph), carries the model attributes EnemyType / EnemyLevel and respawns mob.respawnSeconds after the
	death sequence.

	The thinking is split: EnemyAI (state machine: idle, alert, chase, engage, return home) and EnemyAttacks (the moves: melee,
	combo, lunge, slam, parry; RemoteEvent EnemyAttack for the telegraphs). Their numbers are EnemyConfig (ai, attacks, enemies).

	Death: LootService.reward gives the killer the enemy's skill XP and drops.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EnemyConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyConfig")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any
local LootService = require(ServerScriptService:WaitForChild("LootService")) :: any
local EnemyTags = require(ServerScriptService:WaitForChild("EnemyTags")) :: any
local DeathService = require(ServerScriptService:WaitForChild("DeathService")) :: any
local EnemyRig = require(ServerScriptService:WaitForChild("EnemyRig")) :: any
local EnemyAI = require(ServerScriptService:WaitForChild("EnemyAI")) :: any
local EnemyAttacks = require(ServerScriptService:WaitForChild("EnemyAttacks")) :: any
local EnemyLocomotion = require(ServerScriptService:WaitForChild("EnemyLocomotion")) :: any

local STEP = 0.3
local DEFAULT_TYPE = "placeholder_mob"

local EnemyService = {}

local mobs: { [Model]: any } = {}

local function between(range: any): number
	return range[1] + math.random() * ((range[2] or range[1]) - range[1])
end

local revealOnSpawn = false

local function spawnMob(marker: BasePart)
	local attribute = marker:GetAttribute("EnemyType")
	local enemyType = type(attribute) == "string" and attribute or DEFAULT_TYPE
	local entry = EnemyConfig.enemies[enemyType]
	local cfg = entry and entry.mob
	if not cfg then
		warn(("[EnemyService] %s: EnemyType '%s' has no mob entry in EnemyConfig"):format(marker:GetFullName(), enemyType))
		return
	end
	local model = EnemyRig.build(cfg)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (model and humanoid and root) then
		warn("[EnemyService] no mob model could be built")
		return
	end
	model.Name = entry.name
	local stats = EnemyConfig.statsFor(enemyType) -- health, defense and level come from the gear (see EnemyConfig 1e)
	humanoid.MaxHealth = stats.maxHealth
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = cfg.walkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	model:PivotTo(marker.CFrame * CFrame.new(0, 3.1, 0)) -- roughly right; placeOnGround sets the exact height from the real floor
	EnemyRig.placeOnGround(model, marker)
	model:SetAttribute("EnemyType", enemyType)
	model:SetAttribute("EnemyLevel", stats.level) -- the nameplate shows it (estimated from the gear; it scales nothing)
	model:SetAttribute("Defense", stats.defense) -- DamageService: every hit the mob takes is x 100 / (100 + Defense)
	model.Parent = workspace
	EnemyTags.stamp(model, entry) -- after the parent: tags need a live model for their expiry timers
	CollectionService:AddTag(model, DamageService.TAG)
	CollectionService:AddTag(model, "Enemy")
	root:SetNetworkOwner(nil) -- the server owns the physics, so knockback is the same for everyone
	EnemyRig.attachWeapon(model, cfg.weapon)
	local holdUntil = revealOnSpawn and os.clock() + DeathService.revealBody(model, "enemy", entry) or 0 -- held still while it materializes

	local mob = {
		model = model,
		humanoid = humanoid,
		root = root,
		home = marker.Position,
		cfg = cfg,
		entry = entry,
		enemyType = enemyType,
		ai = EnemyConfig.aiFor(enemyType),
		level = stats.level,
		state = "idle",
		nextWander = 0,
		nextAttackAt = 0,
		cooldowns = {},
		tracks = {},
		baseC0 = {},
		attacking = false,
		returning = false,
		holdUntil = holdUntil,
	}
	mob.wake = function()
		if mobs[model] and os.clock() >= mob.holdUntil then
			EnemyAI.think(mob, os.clock())
		end
	end
	EnemyLocomotion.attach(model, humanoid, cfg.locomotion)
	EnemyAttacks.initCooldowns(mob, os.clock())
	model:SetAttribute("AIState", "idle")
	mobs[model] = mob
	humanoid.Died:Once(function()
		mobs[model] = nil
		-- the body glitches first (DeathService / DeathFX); loot pays out when the burst starts, the body goes after the sequence
		local timeline = DeathService.timeline("enemy", entry)
		task.delay(timeline.glitch, function()
			local ok, err = pcall(LootService.reward, model, enemyType)
			if not ok then
				warn("[EnemyService] reward failed: " .. tostring(err))
			end
		end)
		task.delay(timeline.total + cfg.respawnSeconds, function()
			model:Destroy()
			if marker.Parent then
				spawnMob(marker)
			end
		end)
	end)
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
	revealOnSpawn = true -- the first wave appears with the server; every respawn after it materializes
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
				if mob.humanoid.Health > 0 and mob.root.Parent and now >= mob.holdUntil then
					EnemyAI.think(mob, now)
				end
			end
		end
	end)
end

EnemyService.start()
return EnemyService
