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
	end

	local event = Events:FindFirstChild("ZoneEntered")
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = "ZoneEntered"
		event.Parent = Events
	end

	ZoneNotifyEvent = event
	return ZoneNotifyEvent
end

-- Zone markers are looked up once and cached; a missing one warns once (not every check).
local markerCache = {} -- [zoneName] = Instance
local warnedMissing = {} -- [zoneName] = true

local function getZoneMarker(zoneName)
	local cached = markerCache[zoneName]
	if cached and cached.Parent then
		return cached
	end

	local zonesFolder = workspace:FindFirstChild("Zones")
	local marker = zonesFolder and zonesFolder:FindFirstChild(zoneName)
	if not marker then
		if not warnedMissing[zoneName] then
			warnedMissing[zoneName] = true
			warn("[ZoneManager] Zone marker not found in workspace.Zones: " .. zoneName)
		end
		return nil
	end

	warnedMissing[zoneName] = nil
	markerCache[zoneName] = marker
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

	local event = getZoneNotifyEvent()
	event:FireClient(player, notifData)

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
	zoneState.lastNotificationTime = os.clock()

end

-- Main detection loop. Zones are big areas, so 4 checks a second is plenty (was every frame).
local DETECT_INTERVAL = 0.25

local function startDetectionLoop()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < DETECT_INTERVAL then
			return
		end
		elapsed = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local playerId = player.UserId
			initializePlayerState(playerId)

			for zoneName, zoneConfig in pairs(ZoneConfig.ZONES) do
				if not zoneConfig.enabled then
					continue
				end

				local zoneState = playerZoneStates[playerId][zoneName]
				local isCurrentlyInZone = isPlayerInZone(player, zoneConfig, zoneName)

				if isCurrentlyInZone and not zoneState.isCurrentlyInside then
					onZoneEntry(player, zoneName)
				elseif not isCurrentlyInZone and zoneState.isCurrentlyInside then
					onZoneExit(player, zoneName)
				end
			end
		end
	end)
end

-- Clean up state when player leaves
Players.PlayerRemoving:Connect(function(player)
	playerZoneStates[player.UserId] = nil
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
