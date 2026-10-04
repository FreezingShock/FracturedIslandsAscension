-- ============================================================
--  CloudManager (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  Clouds are purely visual, so each client builds and animates its own particle
--  emitters on the cloud parts in workspace.Clouds, with LOD from ITS camera.
--  (This used to run on the server: it rewrote every attachment position every frame,
--  replicating all of it to every client, and picked the LOD from the first player only.)
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CloudConfig = require(Modules:WaitForChild("Config"):WaitForChild("CloudConfig")) :: any
local CloudSystem = require(Modules:WaitForChild("CloudSystem")) :: any

CloudSystem.initialize()

local function addCloud(part: Instance)
	if part:IsA("BasePart") then
		CloudSystem.createCloudFromPart(part)
	end
end

local function watchFolder(folder: Instance)
	for _, part in ipairs(folder:GetChildren()) do
		addCloud(part)
	end
	-- StreamingEnabled: cloud parts stream in/out, so keep listening
	folder.ChildAdded:Connect(addCloud)
end

local folder = workspace:FindFirstChild(CloudConfig.CLOUDS_FOLDER)
if folder then
	watchFolder(folder)
else
	-- the folder itself can stream in after the script starts
	local conn
	conn = workspace.ChildAdded:Connect(function(child)
		if child.Name == CloudConfig.CLOUDS_FOLDER then
			conn:Disconnect()
			watchFolder(child)
		end
	end)
end

-- LOD from this player's camera (CloudSystem throttles the distance sweep itself)
RunService.Heartbeat:Connect(function()
	local camera = workspace.CurrentCamera
	if camera then
		CloudSystem.updateLOD(camera.CFrame.Position)
	end
end)
