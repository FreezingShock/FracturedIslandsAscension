--[[
	DeathService (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyInit.server.lua; it needs no other wiring)

	Takes over how anything with a Humanoid dies, so the native Roblox collapse never plays: every "Enemy" / "Damageable"
	model (mobs, training dummies) and every player character. On Humanoid.Died (any cause: hits, burns, falling):
	  * the body is frozen where it stands (root anchored; BreakJointsOnDeath is turned off when it is watched),
	  * RemoteEvent EntityDeath { model, kind, deathType, seed } goes to every player within DeathConfig caps.maxDistance
	    (and to the dead player); clients only draw the glitch and the triangle burst (DeathFX, DeathController).
	  * players respawn DeathConfig.respawnSeconds() after dying (Players.RespawnTime); the new body is held still for
	    DeathConfig.revealSeconds() while RemoteEvent EntityRespawn { model, seed } has clients play the reveal (DeathFX.playReverse); mobs and dummies are removed and
	    respawned by EnemyService / DummyService, which use DeathService.timeline() so the loot pays out when the burst starts
	    and the body is removed after the whole sequence.
	Looks, timings and caps: Modules/Config/DeathConfig.

	  DeathService.timeline(kind, enemyEntry) -> { glitch, burst, total }   seconds for that kind of death
	  DeathService.watch(model)                                              start watching a model (done automatically)
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DeathConfig = require(Modules:WaitForChild("Config"):WaitForChild("DeathConfig")) :: any
local EnemyConfig = require(Modules:WaitForChild("EnemyConfig")) :: any

local remote = ReplicatedStorage:FindFirstChild("EntityDeath") :: RemoteEvent?
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "EntityDeath"
	remote.Parent = ReplicatedStorage
end

local respawnRemote = ReplicatedStorage:FindFirstChild("EntityRespawn") :: RemoteEvent?
if not respawnRemote then
	respawnRemote = Instance.new("RemoteEvent")
	respawnRemote.Name = "EntityRespawn"
	respawnRemote.Parent = ReplicatedStorage
end

local DeathService = {}

local hasDied: { [Player]: boolean } = {} -- a player's first spawn has no reveal; every one after a death does

local GHOST_GROUP = "DeadBody"
local PhysicsService = game:GetService("PhysicsService")
pcall(function()
	PhysicsService:RegisterCollisionGroup(GHOST_GROUP)
end)
for _, other in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
	PhysicsService:CollisionGroupSetCollidable(GHOST_GROUP, other.name, false)
end

local watched: { [Model]: boolean } = {}

local function kindOf(model: Model): string
	if Players:GetPlayerFromCharacter(model) then
		return "player"
	end
	return model:GetAttribute("EnemyType") == "dummy" and "dummy" or "enemy"
end

local function entryOf(model: Model, kind: string): any?
	if kind == "player" then
		return nil
	end
	local enemyType = model:GetAttribute("EnemyType")
	return type(enemyType) == "string" and EnemyConfig.get(enemyType) or nil
end

function DeathService.timeline(kind: string?, enemyEntry: any?): { glitch: number, burst: number, total: number }
	local timeline = DeathConfig.resolve(kind, enemyEntry).timeline
	return { glitch = timeline.glitch, burst = timeline.burst, total = timeline.glitch + timeline.burst }
end

local function freeze(model: Model)
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("ForceField") then
			child:Destroy() -- the spawn bubble must not stay around a body that is about to burst
		end
	end
	-- a dying body is a ghost: nothing walks into or stands on it, until the model is removed at respawn. The Humanoid
	-- switches collision back on for its own parts, so every part is held at false (change signal) for the model's life.
	local function ghost(part: Instance)
		if part:IsA("BasePart") then
			part.CollisionGroup = GHOST_GROUP -- the Humanoid never rewrites this, unlike CanCollide
			part.CanCollide = false
			part:GetPropertyChangedSignal("CanCollide"):Connect(function()
				if part.CanCollide then
					part.CanCollide = false
				end
			end)
		end
	end
	for _, part in ipairs(model:GetDescendants()) do
		ghost(part)
	end
	model.DescendantAdded:Connect(ghost)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		root.Anchored = true
	end
end

local function onDied(model: Model, kind: string)
	local entry = entryOf(model, kind)
	local config = DeathConfig.resolve(kind, entry)
	freeze(model)
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = root and root.Position or model:GetPivot().Position
	local deathType = (entry and entry.death and entry.death.deathType) or "default"
	local seed = math.random(1, 1000000)
	local owner = Players:GetPlayerFromCharacter(model)
	if owner then
		hasDied[owner] = true
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local theirRoot = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if player == owner or (theirRoot and (theirRoot.Position - origin).Magnitude <= config.caps.maxDistance) then
			(remote :: RemoteEvent):FireClient(player, model, kind, deathType, seed)
		end
	end
end

function DeathService.watch(model: Instance)
	if not model:IsA("Model") or watched[model] then
		return
	end
	local humanoid = model:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid or watched[model] then
		return
	end
	watched[model] = true
	humanoid.BreakJointsOnDeath = false -- the native collapse never plays
	local kind = kindOf(model)
	humanoid.Died:Once(function()
		onDied(model, kind)
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			watched[model] = nil
		end
	end)
end

-- every Enemy / Damageable model, as it appears
for _, tag in ipairs({ "Enemy", "Damageable" }) do
	for _, model in ipairs(CollectionService:GetTagged(tag)) do
		task.spawn(DeathService.watch, model)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		task.spawn(DeathService.watch, model)
	end)
end

-- every player character
Players.RespawnTime = DeathConfig.respawnSeconds("player")

-- The new body of a player who died is held still (and hidden by the clients) while the camera glides to it, then it
-- materializes (DeathFX.playReverse); the hold lasts DeathConfig.revealSeconds, then the body is released.
local function reveal(player: Player, character: Model)
	local cfg = DeathConfig.resolve("player", nil)
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then
		return
	end
	root.Anchored = true
	local seed = math.random(1, 1000000)
	for _, other in ipairs(Players:GetPlayers()) do
		local theirRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if other == player or (theirRoot and (theirRoot.Position - root.Position).Magnitude <= cfg.caps.maxDistance) then
			(respawnRemote :: RemoteEvent):FireClient(other, character, seed)
		end
	end
	task.delay(DeathConfig.revealSeconds("player"), function()
		if character.Parent and humanoid.Health > 0 and root.Parent then
			root.Anchored = false
		end
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(DeathService.watch, character)
		if hasDied[player] then
			task.spawn(reveal, player, character)
		end
	end)
	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(game) then
			hasDied[player] = nil
		end
	end)
	if player.Character then
		task.spawn(DeathService.watch, player.Character)
	end
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

return DeathService
