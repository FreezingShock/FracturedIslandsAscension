--[[
	DummyService (ModuleScript, Server)
	Place inside: ServerScriptService   (started by DummyInit.server.lua)

	Training dummies to hit. One dummy stands on every Part in Workspace.DummySpawns (move, rotate or add markers in
	Studio). Each is cloned from ServerStorage.Dummy (restyle the template freely; if it is missing a plain R6 rig is built),
	tagged "Damageable" so DamageService can hit it, pays its killer through LootService.reward (Coins), and respawns CombatConfig.dummy.respawnSeconds after dying. A dummy
	that was knocked away walks back to its marker once it has gone CombatConfig.dummy.returnHomeAfter seconds unhit.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local CombatConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CombatConfig")) :: any
local DamageService = require(ServerScriptService:WaitForChild("DamageService")) :: any
local LootService = require(ServerScriptService:WaitForChild("LootService")) :: any
local EnemyConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyConfig")) :: any
local EnemyTags = require(ServerScriptService:WaitForChild("EnemyTags")) :: any
local DeathService = require(ServerScriptService:WaitForChild("DeathService")) :: any

local DUMMY = CombatConfig.dummy
local DummyService = {}

-- [model] = home position
local dummies: { [Model]: Vector3 } = {}

local function template(): Model?
	local made = ServerStorage:FindFirstChild("Dummy")
	if made and made:IsA("Model") then
		return made
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if ok and rig then
		warn("[DummyService] ServerStorage.Dummy is missing: using a plain R6 rig")
		rig.Name = "Dummy"
		rig.Parent = ServerStorage
		return rig
	end
	return nil
end

local function spawnDummy(marker: BasePart)
	local source = template()
	if not source then
		warn("[DummyService] no dummy template and no rig could be built")
		return
	end
	local dummy = source:Clone()
	dummy.Name = "TrainingDummy"
	local humanoid = dummy:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = dummy:FindFirstChild("HumanoidRootPart") :: BasePart
	if not (humanoid and root) then
		dummy:Destroy()
		return
	end
	humanoid.MaxHealth = DUMMY.health
	humanoid.Health = DUMMY.health
	humanoid.WalkSpeed = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	dummy:PivotTo(marker.CFrame * CFrame.new(0, 3.1, 0)) -- an R6 root sits about 3 studs above the ground
	dummy.Parent = workspace
	CollectionService:AddTag(dummy, DamageService.TAG)
	dummy:SetAttribute("EnemyType", "dummy") -- EnemyConfig key: its hit effects, sounds and nameplate
	dummy:SetAttribute("EnemyLevel", EnemyConfig.levelInfo("dummy").level)
	EnemyTags.stamp(dummy, EnemyConfig.get("dummy"))
	CollectionService:AddTag(dummy, "Enemy") -- the nameplate controller shows a health bar over every Enemy
	root:SetNetworkOwner(nil) -- the server owns the physics, so knockback is the same for everyone
	dummies[dummy] = marker.Position

	humanoid.Died:Once(function()
		dummies[dummy] = nil
		local timeline = DeathService.timeline("dummy", EnemyConfig.get("dummy"))
		task.delay(timeline.glitch, function() -- loot pays out when the burst starts
			local ok, err = pcall(LootService.reward, dummy, "dummy") -- Coins (CoinsConfig.enemies.dummy) for whoever killed it
			if not ok then
				warn("[DummyService] reward failed: " .. tostring(err))
			end
		end)
		task.delay(timeline.total + DUMMY.respawnSeconds, function()
			dummy:Destroy()
			if marker.Parent then
				spawnDummy(marker)
			end
		end)
	end)
end

function DummyService.start()
	local markers = workspace:WaitForChild("DummySpawns", 10)
	if not markers then
		warn("[DummyService] Workspace.DummySpawns is missing: no dummies will spawn")
		return
	end
	for _, marker in ipairs(markers:GetChildren()) do
		if marker:IsA("BasePart") then
			spawnDummy(marker)
		end
	end
	markers.ChildAdded:Connect(function(marker)
		if marker:IsA("BasePart") then
			spawnDummy(marker)
		end
	end)

	-- a dummy that got knocked off its marker walks home when it has been left alone
	task.spawn(function()
		while true do
			task.wait(0.5)
			for dummy, home in pairs(dummies) do
				local humanoid = dummy:FindFirstChildOfClass("Humanoid")
				local root = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
				if humanoid and root and humanoid.Health > 0 then
					local idle = os.clock() - (dummy:GetAttribute("LastHit") or 0) >= DUMMY.returnHomeAfter
					local away = Vector3.new(root.Position.X - home.X, 0, root.Position.Z - home.Z).Magnitude > 2
					if idle and away then
						humanoid.WalkSpeed = 12
						humanoid:MoveTo(Vector3.new(home.X, root.Position.Y, home.Z))
					elseif humanoid.WalkSpeed ~= 0 and not away then
						humanoid.WalkSpeed = 0
					end
				end
			end
		end
	end)
end

DummyService.start()
return DummyService
