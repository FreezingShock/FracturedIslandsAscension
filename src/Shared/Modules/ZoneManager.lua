-- ZoneManager.lua (ModuleScript in ReplicatedStorage.Modules)
-- Detects player entry/exit, fires notifications with state tracking
-- KEY FIX: RemoteEvent is created during initialize(), not at module require time

local ZoneConfig = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("ZoneConfig")
)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ZoneManager = {}

-- Player zone state tracking:
-- playerZoneStates[playerId][zoneName] = {
--   isCurrentlyInside = bool,
--   hasShownNotification = bool,
--   lastNotificationTime = number,
-- }
local playerZoneStates = {}

-- Lazy-loaded reference to ZoneNotifyEvent (created during initialize())
local ZoneNotifyEvent = nil

-- Get or create RemoteEvent for zone notifications
local function getZoneNotifyEvent()
	if ZoneNotifyEvent then
		return ZoneNotifyEvent
	end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Events = ReplicatedStorage:FindFirstChild("Events")
	if not Events then
		Events = Instance.new("Folder")
		Events.Name = "Events"
		Events.Parent = ReplicatedStorage
		print("[ZoneManager] Created Events folder in ReplicatedStorage")
	end

	local event = Events:FindFirstChild("ZoneEntered")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "ZoneEntered"
		event.Parent = Events
		print("[ZoneManager] Created ZoneEntered RemoteEvent ✓")
	end

	ZoneNotifyEvent = event
	return ZoneNotifyEvent
end

-- Find zone marker part in workspace.Zones with diagnostic logging
local function getZoneMarker(zoneName)
	local zonesFolder = workspace:FindFirstChild("Zones")
	if not zonesFolder then
		warn("[ZoneManager] workspace.Zones folder not found. Cannot detect zone: " .. zoneName)
		return nil
	end

	local marker = zonesFolder:FindFirstChild(zoneName)
	if not marker then
		warn("[ZoneManager] Zone marker not found for: " .. zoneName .. " in workspace.Zones")
		return nil
	end

	return marker
end

-- RADIUS DETECTION: check if player is within radius of a part
local function isPlayerInRadius(playerPosition, markerPart, radius)
	if not markerPart then
		return false
	end
	local distance = (playerPosition - markerPart.Position).Magnitude
	return distance <= radius
end

-- PART DETECTION: check if player is inside a part using bounding box
local function isPlayerInPart(playerPosition, markerPart)
	if not markerPart then
		return false
	end

	local partSize = markerPart.Size
	local partPos = markerPart.Position
	local partCFrame = markerPart.CFrame

	-- Convert player position to part's local space
	local relativePos = partCFrame:VectorToObjectSpace(playerPosition - partPos)

	-- Check if within bounding box
	local halfSize = partSize / 2
	return math.abs(relativePos.X) <= halfSize.X
		and math.abs(relativePos.Y) <= halfSize.Y
		and math.abs(relativePos.Z) <= halfSize.Z
end

-- Check if player is in zone based on detection method
local function isPlayerInZone(player, zoneConfig, zoneName)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local playerPos = character.HumanoidRootPart.Position
	local marker = getZoneMarker(zoneName)

	if not marker then
		-- getZoneMarker already logged the warning
		return false
	end

	-- SINGLE SOURCE OF TRUTH: detectionMethod is the only config key that matters
	local method = zoneConfig.detectionMethod or "radius"

	if method == "part" then
		return isPlayerInPart(playerPos, marker)
	else -- Default to radius
		local radius = marker:GetAttribute("Radius") or zoneConfig.radiusSize or 100
		return isPlayerInRadius(playerPos, marker, radius)
	end
end

-- Initialize player zone state
local function initializePlayerState(playerId)
	if not playerZoneStates[playerId] then
		playerZoneStates[playerId] = {}
	end

	for zoneName, _ in pairs(ZoneConfig.ZONES) do
		if not playerZoneStates[playerId][zoneName] then
			playerZoneStates[playerId][zoneName] = {
				isCurrentlyInside = false,
				hasShownNotification = false,
				lastNotificationTime = 0,
			}
		end
	end
end

-- Handle zone entry (fire notification once per visit)
local function onZoneEntry(player, zoneName)
	local zoneConfig = ZoneConfig.ZONES[zoneName]
	if not zoneConfig or not zoneConfig.enabled then
		return
	end

	local playerId = player.UserId
	initializePlayerState(playerId)

	local zoneState = playerZoneStates[playerId][zoneName]

	-- Only fire notification if we haven't shown one in this visit
	if zoneState.hasShownNotification then
		return
	end

	zoneState.hasShownNotification = true
	zoneState.isCurrentlyInside = true

	-- Get skill data from ZoneConfig.SKILLS index
	local skillData = ZoneConfig.getSkillData(zoneConfig.skill)

	-- Get zone colors (with skill fallback)
	local zoneColors = ZoneConfig.getZoneColors(zoneName)

	print("[ZoneManager] DEBUG: SPRITESHEET.assetId = " .. tostring(ZoneConfig.SPRITESHEET.assetId))

	-- Fire notification to client
	local notifData = {
		zoneName = zoneConfig.displayName,
		skill = zoneConfig.skill,
		skillColor = skillData.color,
		spriteSheetAssetId = ZoneConfig.SPRITESHEET.assetId,
		spriteCoord = skillData.spriteCoord,
		showSkillTab = zoneConfig.showSkillTab,
		levelRange = zoneConfig.levelRange,
		colorDark = zoneColors.colorDark,
		colorLight = zoneColors.colorLight,
	}

	print("[ZoneManager] DEBUG: notifData.spriteSheetAssetId = " .. tostring(notifData.spriteSheetAssetId))

	local event = getZoneNotifyEvent()
	event:FireClient(player, notifData)

	print("[ZoneManager] Fired zone notification for " .. player.Name .. " entering " .. zoneName)
end

-- Handle zone exit (reset notification flag so it can fire again on re-entry)
local function onZoneExit(player, zoneName)
	local playerId = player.UserId
	if not playerZoneStates[playerId] then
		return
	end

	local zoneState = playerZoneStates[playerId][zoneName]
	zoneState.isCurrentlyInside = false
	zoneState.hasShownNotification = false -- Reset so it fires again on re-entry
	zoneState.lastNotificationTime = tick()

	print("[ZoneManager] Player " .. player.Name .. " left " .. zoneName)
end

-- Main detection loop (runs every frame)
local function startDetectionLoop()
	local debugTickCounter = 0
	RunService.Heartbeat:Connect(function()
		for _, player in pairs(Players:GetPlayers()) do
			initializePlayerState(player.UserId)

			for zoneName, zoneConfig in pairs(ZoneConfig.ZONES) do
				if not zoneConfig.enabled then
					continue
				end

				local playerId = player.UserId
				local zoneState = playerZoneStates[playerId][zoneName]
				local isCurrentlyInZone = isPlayerInZone(player, zoneConfig, zoneName)

				-- Debug output every 60 frames (~1 second)
				debugTickCounter = debugTickCounter + 1
				if debugTickCounter >= 60 then
					local character = player.Character
					local playerPos = character
							and character:FindFirstChild("HumanoidRootPart")
							and character.HumanoidRootPart.Position
						or "NO CHARACTER"
				end

				-- Detect entry
				if isCurrentlyInZone and not zoneState.isCurrentlyInside then
					onZoneEntry(player, zoneName)
				-- Detect exit
				elseif not isCurrentlyInZone and zoneState.isCurrentlyInside then
					onZoneExit(player, zoneName)
				end
			end
		end
		if debugTickCounter >= 60 then
			debugTickCounter = 0
		end
	end)

	print("[ZoneManager] Detection loop started ✓")
end

-- Clean up state when player leaves
Players.PlayerRemoving:Connect(function(player)
	playerZoneStates[player.UserId] = nil
	print("[ZoneManager] Cleaned up state for " .. player.Name)
end)

-- Public API
function ZoneManager.initialize()
	-- Create RemoteEvent first (before detection loop starts)
	getZoneNotifyEvent()

	-- Then start detection
	startDetectionLoop()

	print("[ZoneManager] Initialized and listening for zone entries... ✓")
end

return ZoneManager
