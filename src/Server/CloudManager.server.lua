-- CloudManager.lua
-- Server script that orchestrates the cloud system
-- Placed in ServerScriptService

local CloudConfig = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("CloudConfig")
)
local CloudSystem = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("CloudSystem"))

local RunService = game:GetService("RunService")
local Workspace = game.Workspace

-- ===== INITIALIZE =====
CloudSystem.initialize()

-- ===== SCAN AND CREATE CLOUDS FROM FOLDER =====
local function scanAndCreateClouds()
	local cloudsFolder = Workspace:FindFirstChild(CloudConfig.CLOUDS_FOLDER)

	if not cloudsFolder then
		warn("CloudManager: Folder '" .. CloudConfig.CLOUDS_FOLDER .. "' not found in Workspace. No clouds created.")
		return
	end

	local cloudParts = cloudsFolder:GetChildren()

	for _, part in ipairs(cloudParts) do
		if part:IsA("BasePart") then
			CloudSystem.createCloudFromPart(part)
		end
	end

	print("CloudManager: Created clouds for " .. CloudSystem.getTotalCloudCount() .. " parts")
end

-- ===== GET EFFECTIVE CAMERA POSITION =====
-- [PLACEHOLDER] Future: Use client-sent camera position via RemoteEvent for more accuracy
-- For now, use nearest player character position
local function getEffectiveCameraPosition()
	local players = game:GetService("Players"):GetPlayers()

	if #players > 0 then
		local player = players[1]
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			-- Use head position if available, else HumanoidRootPart
			local head = player.Character:FindFirstChild("Head")
			return (head or player.Character.HumanoidRootPart).Position
		end
	end

	-- Fallback: use world origin if no players
	return Vector3.new(0, 0, 0)
end

-- ===== MAIN HEARTBEAT LOOP (LOD UPDATES) =====
local heartbeatConn
heartbeatConn = RunService.Heartbeat:Connect(function()
	local cameraPos = getEffectiveCameraPosition()
	CloudSystem.updateLOD(cameraPos)

	-- [PLACEHOLDER] Future: Log debug stats
	-- print(string.format("[Clouds] Active: %d / %d", CloudSystem.getActiveCloudCount(), CloudSystem.getTotalCloudCount()))
end)

-- ===== STARTUP =====
scanAndCreateClouds()

-- ===== CLEANUP ON SHUTDOWN =====
game:BindToClose(function()
	if heartbeatConn then
		heartbeatConn:Disconnect()
	end
	CloudSystem.destroy()
end)

print("CloudManager: System initialized and ready")
