-- ServerStorage.Dummy (training dummy template) + Workspace.DummySpawns (one marker Part per dummy), used by DummyService.
-- Dummy = plain R6 rig, straw coloured, 1000 hp (DummyService sets health from CombatConfig.dummy), no name / health bar.
-- Markers = flat translucent green Neon pads; move / add / delete them freely, one dummy stands on each.
-- Marker positions below are the original ones next to NewSpawn; change them if the spawn moves.
-- Edit datamodel. Refuses to overwrite either piece unless FORCE.
local FORCE = false
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local made = {}

if not ServerStorage:FindFirstChild("Dummy") or FORCE then
	if ServerStorage:FindFirstChild("Dummy") then
		ServerStorage.Dummy:Destroy()
	end
	local rig = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	rig.Name = "Dummy"
	local straw = Color3.new(0.745098, 0.666667, 0.509804)
	local colors = rig:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors", rig)
	for _, k in ipairs({ "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }) do
		colors[k] = straw
	end
	for _, name in ipairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
		local part = rig:FindFirstChild(name)
		if part then
			part.Color = straw
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = 1000
	humanoid.Health = 1000
	humanoid.WalkSpeed = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	rig.Parent = ServerStorage
	table.insert(made, "ServerStorage.Dummy")
end

local folder = workspace:FindFirstChild("DummySpawns")
if not folder or FORCE then
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DummySpawns"
	local positions = {
		Vector3.new(-954.66, 282.1, -839.168),
		Vector3.new(-944.66, 282.1, -839.168),
		Vector3.new(-934.66, 282.1, -839.168),
	}
	for i, position in ipairs(positions) do
		local marker = Instance.new("Part")
		marker.Name = "DummySpawn" .. i
		marker.Anchored = true
		marker.CanCollide = false
		marker.Size = Vector3.new(4, 0.2, 4)
		marker.Position = position
		marker.Color = Color3.new(0.333333, 1, 0.333333)
		marker.Material = Enum.Material.Neon
		marker.Transparency = 0.8
		marker.Parent = folder
	end
	folder.Parent = workspace
	table.insert(made, "Workspace.DummySpawns")
end
return #made > 0 and ("built " .. table.concat(made, ", ")) or "all exist (set FORCE = true to rebuild)"
