-- ZoneNotifier.client.lua (LocalScript in StarterPlayer.StarterPlayerScripts)
-- Receives zone entry events from server and animates notifications
-- Single notification at a time: new zone requests overwrite queue (last-zone-wins)

local ZoneConfig = require(
	game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("ZoneConfig")
)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- SINGLE NOTIFICATION STATE: only one zone notification visible at a time
local currentNotification = nil -- {gui, notifData, mainTween, tabTweens, zoneName, _animatingOut}
local queuedNotification = nil -- Single queued notification (last-zone-wins: overwrites if new one comes in)
local queuedZoneName = nil -- Track which zone is queued to prevent duplicate requests

-- Lazy-loaded template reference
local templateCache = nil

-- Spam prevention: track when notifications are queued to prevent rapid-fire spam
-- {zoneName = lastShowTime}
local notificationCooldown = {}
local SPAM_COOLDOWN_DURATION = 0.05 -- Minimum time between notification attempts per zone

-- Track when current notification should be auto-dismissed
local notificationDismissTime = nil

local inSound = workspace.UISounds:FindFirstChild("In")
local outSound = workspace.UISounds:FindFirstChild("Out")

-- CRITICAL: Wait for RemoteEvent to be created by server before listening
local function getZoneNotifyEvent()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Events = ReplicatedStorage:WaitForChild("Events")
	local event = Events:WaitForChild("ZoneEntered") -- BLOCK until event exists
	print("[ZoneNotifier] Connected to ZoneEntered RemoteEvent ✓")
	return event
end

-- Lazy-load template (called on first notification)
local function getTemplate()
	if templateCache then
		return templateCache
	end

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local GUI = ReplicatedStorage:FindFirstChild("GUI")
	if not GUI then
		warn("[ZoneNotifier] ReplicatedStorage.GUI not found")
		return nil
	end

	local template = GUI:FindFirstChild("LocationNotif")
	if not template then
		warn("[ZoneNotifier] GUI.LocationNotif template not found")
		print("[ZoneNotifier] DEBUG: Contents of ReplicatedStorage.GUI:")
		for _, child in ipairs(GUI:GetChildren()) do
			print("  - " .. child.Name .. " (" .. child.ClassName .. ")")
		end
		return nil
	end

	templateCache = template
	print("[ZoneNotifier] Template loaded: " .. template:GetFullName())
	return templateCache
end

-- Typewriter effect for text (character by character reveal) with tick sound per character
local function typewriteText(textLabel, fullText, duration)
	if not textLabel or not textLabel.Parent then
		return
	end

	local characterCount = string.len(fullText)
	if characterCount == 0 then
		textLabel.Text = ""
		return
	end

	local startTime = tick()
	local connection
	local lastVisibleChars = 0 -- Track previous char count to detect new character reveal
	local clickSound = workspace:FindFirstChild("UISounds") and workspace.UISounds:FindFirstChild("Click3")

	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / duration, 1)
		local visibleChars = math.floor(characterCount * progress)

		textLabel.Text = string.sub(fullText, 1, visibleChars)

		-- Fire sound only when a new character is revealed
		if visibleChars > lastVisibleChars and clickSound then
			clickSound:Play()
			lastVisibleChars = visibleChars
		end

		if progress >= 1 then
			textLabel.Text = fullText
			connection:Disconnect()
		end
	end)
end

-- Reverse typewriter effect (character by character removal) with tick sound per character
local function untypewriteText(textLabel, duration)
	if not textLabel or not textLabel.Parent then
		return
	end

	local fullText = textLabel.Text
	local characterCount = string.len(fullText)
	if characterCount == 0 then
		return
	end

	local startTime = tick()
	local connection
	local lastVisibleChars = characterCount -- Start at full, track down
	local clickSound = workspace:FindFirstChild("UISounds") and workspace.UISounds:FindFirstChild("Click3")

	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / duration, 1)
		local visibleChars = math.floor(characterCount * (1 - progress))

		textLabel.Text = string.sub(fullText, 1, visibleChars)

		-- Fire sound only when a character is removed
		if visibleChars < lastVisibleChars and clickSound then
			clickSound:Play()
			lastVisibleChars = visibleChars
		end

		if progress >= 1 then
			textLabel.Text = ""
			connection:Disconnect()
		end
	end)
end

-- Cancel all tweens for a notification
local function cancelNotifTweens(notifRecord)
	if not notifRecord then
		return
	end

	if notifRecord.mainTween then
		notifRecord.mainTween:Cancel()
		notifRecord.mainTween = nil
	end

	if notifRecord.tabTweens then
		for _, tween in ipairs(notifRecord.tabTweens) do
			if tween then
				tween:Cancel()
			end
		end
		notifRecord.tabTweens = {}
	end
end

-- Animate notification IN from top with tabs sliding in from sides (delayed 0.5s)
local function animateNotificationIn(notifGui, notifRecord)
	if not notifGui or not notifGui.Parent then
		return
	end

	local boundingBox = notifGui:FindFirstChild("BoundingBox")
	if not boundingBox then
		warn("[ZoneNotifier] BoundingBox not found in template")
		return
	end

	-- Cancel any in-flight tweens first
	cancelNotifTweens(notifRecord)

	-- Set starting position (off-screen top, centered X)
	boundingBox.Position = UDim2.new(0.5, 0, -0.25, 0)

	local tweenInfo = TweenInfo.new(
		ZoneConfig.ANIMATION.ENTER_DURATION,
		ZoneConfig.ANIMATION.EASING,
		ZoneConfig.ANIMATION.EASING_DIRECTION
	)

	-- Tween main box to final position
	local mainTween = TweenService:Create(boundingBox, tweenInfo, {
		Position = UDim2.new(0.5, 0, 0.25, 0),
	})
	mainTween:Play()
	notifRecord.mainTween = mainTween

	print("[ZoneNotifier] Animating IN: " .. notifGui.Name)
	-- Animate ZoneName sliding in from left (0,0,0,50) → (0,300,0,50)
	local zoneFrame = boundingBox:FindFirstChild("ZoneFrame")
	local Underline = zoneFrame:FindFirstChild("ZoneName"):FindFirstChild("Underline")
	if zoneFrame then
		local zoneName = zoneFrame:FindFirstChild("ZoneName")
		if zoneName then
			zoneName.Size = UDim2.new(0, 0, 0, 50)
			local zoneNameTween = TweenService:Create(zoneName, tweenInfo, {
				Size = UDim2.new(0, 300, 0, 50),
			})
			zoneNameTween:Play()
			Underline.Visible = true
			table.insert(notifRecord.tabTweens, zoneNameTween)

			-- Typewriter effect on zone name text label (start after main slide begins)
			local zoneNameLabel = zoneFrame:FindFirstChild("ZoneNameLabel")
			if zoneNameLabel then
				task.delay(0.3, function()
					if zoneNameLabel and zoneNameLabel.Parent then
						-- Get zone name from zoneFrame attribute (stored in populateNotificationGui)
						local zoneNameData = zoneNameLabel:GetAttribute("ZoneName") or ""
						if zoneNameData ~= "" then
							print("[ZoneNotifier] Typewriting: " .. zoneNameData)
							typewriteText(zoneNameLabel, zoneNameData, 0.6)
						else
							print("[ZoneNotifier] WARNING: ZoneName attribute empty on zoneFrame")
						end
					end
				end)
			end
		end
	end

	-- Schedule tab tweens (0.5s delay after main tween starts)
	task.delay(0.5, function()
		if not notifGui or not notifGui.Parent then
			return
		end

		local tabs = boundingBox:FindFirstChild("Tabs")
		if not tabs then
			return
		end

		local tabTweens = {}

		-- Animate level tab sliding in from right
		local levelTabBB = tabs:FindFirstChild("LevelTabBB")
		if levelTabBB then
			local levelTab = levelTabBB:FindFirstChild("LevelTab")
			if levelTab then
				levelTab.Position = UDim2.new(1.1, 0, 0, 0) -- Start off-screen right
				local levelTabTween = TweenService:Create(
					levelTab,
					tweenInfo,
					{ Position = UDim2.new(0, 0, 0, 0) } -- Slide to center
				)
				levelTabTween:Play()
				table.insert(tabTweens, levelTabTween)
			end
		end

		-- Animate skill tab sliding in from left (if showSkillTab is true)
		local skillTabBB = tabs:FindFirstChild("SkillTabBB")
		if skillTabBB and skillTabBB.Visible then
			local skillTab = skillTabBB:FindFirstChild("SkillTab")
			if skillTab then
				skillTab.Position = UDim2.new(-1.1, 0, 0, 0) -- Start off-screen left
				local skillTabTween = TweenService:Create(
					skillTab,
					tweenInfo,
					{ Position = UDim2.new(0, 0, 0, 0) } -- Slide to center
				)
				skillTabTween:Play()
				table.insert(tabTweens, skillTabTween)
			end
		end
		inSound:Play()
		notifRecord.tabTweens = tabTweens
	end)
end

-- Animate notification OUT (slide down) with tabs sliding out to sides
local function animateNotificationOut(notifGui, notifRecord)
	if not notifGui or not notifGui.Parent then
		return
	end

	local boundingBox = notifGui:FindFirstChild("BoundingBox")
	if not boundingBox then
		return
	end

	-- Cancel in-flight tweens
	cancelNotifTweens(notifRecord)

	local tweenInfo = TweenInfo.new(ZoneConfig.ANIMATION.EXIT_DURATION, Enum.EasingStyle.Back, Enum.EasingDirection.In)

	-- Reverse typewriter on zone name (start immediately)
	local zoneFrame = boundingBox:FindFirstChild("ZoneFrame")
	if zoneFrame then
		local zoneName = zoneFrame:FindFirstChild("ZoneName")
		if zoneName then
			local zoneNameLabel = zoneFrame:FindFirstChild("ZoneNameLabel")
			if zoneNameLabel then
				untypewriteText(zoneNameLabel, 0.3)
			end
		end
	end
	local Underline = zoneFrame:FindFirstChild("ZoneName"):FindFirstChild("Underline")
	-- Animate ZoneName sliding out to left (0,300,0,50) → (0,0,0,50)
	if zoneFrame then
		local zoneName = zoneFrame:FindFirstChild("ZoneName")
		if zoneName then
			local zoneNameTween = TweenService:Create(zoneName, tweenInfo, {
				Size = UDim2.new(0, 0, 0, 50),
			})
			zoneNameTween:Play()
			Underline.Visible = false
			table.insert(notifRecord.tabTweens, zoneNameTween)
		end
	end

	-- Animate tabs out first (in parallel with main box)
	local tabs = boundingBox:FindFirstChild("Tabs")
	if tabs then
		local levelTabBB = tabs:FindFirstChild("LevelTabBB")
		if levelTabBB then
			local levelTab = levelTabBB:FindFirstChild("LevelTab")
			if levelTab then
				local levelTabTween = TweenService:Create(
					levelTab,
					tweenInfo,
					{ Position = UDim2.new(1.1, 0, 0, 0) } -- Slide out to right
				)
				levelTabTween:Play()
				table.insert(notifRecord.tabTweens, levelTabTween)
			end
		end

		local skillTabBB = tabs:FindFirstChild("SkillTabBB")
		if skillTabBB and skillTabBB.Visible then
			local skillTab = skillTabBB:FindFirstChild("SkillTab")
			if skillTab then
				local skillTabTween = TweenService:Create(
					skillTab,
					tweenInfo,
					{ Position = UDim2.new(-1.1, 0, 0, 0) } -- Slide out to left
				)
				skillTabTween:Play()
				table.insert(notifRecord.tabTweens, skillTabTween)
			end
		end
		outSound:Play()
	end

	print("[ZoneNotifier] Animating OUT: " .. notifGui.Name)
	-- Main box tween down (after 0.5s, so it slides out after tabs)
	task.delay(0.5, function()
		if not notifGui or not notifGui.Parent then
			return
		end

		local mainTween = TweenService:Create(boundingBox, tweenInfo, {
			Position = UDim2.new(0.5, 0, -0.25, 0),
		})
		mainTween:Play()
		notifRecord.mainTween = mainTween
	end)
end

-- Update GUI with notification data and apply zone colors
local function populateNotificationGui(notifGui, notifData)
	local boundingBox = notifGui:FindFirstChild("BoundingBox")
	if not boundingBox then
		warn("[ZoneNotifier] BoundingBox not found in cloned GUI")
		return
	end

	-- Convert hex colors to Color3
	local colorDark = ZoneConfig.hexToColor3(notifData.colorDark)
	local colorLight = ZoneConfig.hexToColor3(notifData.colorLight)

	print("[ZoneNotifier] Applying colors - Dark: " .. tostring(colorDark) .. ", Light: " .. tostring(colorLight))

	-- Update Zone Name (zone colors: dark for background, light for text/accent)
	local zoneFrame = boundingBox:FindFirstChild("ZoneFrame")
	if zoneFrame then
		local zoneName = zoneFrame:FindFirstChild("ZoneName")
		if zoneName then
			-- Apply zone colors to ZoneName frame and its children
			zoneName.BackgroundColor3 = colorDark -- ZoneName frame background (dark)
			print("[ZoneNotifier] ✓ Set ZoneName.BackgroundColor3 to dark zone color")

			local underline = zoneName:FindFirstChild("Underline")
			if underline then
				underline.BackgroundColor3 = colorLight -- Underline background (light)
				print("[ZoneNotifier] ✓ Set Underline.BackgroundColor3 to light zone color")
			else
				warn("[ZoneNotifier] Underline not found under ZoneName")
			end

			local zoneNameLabel = zoneFrame:FindFirstChild("ZoneNameLabel")
			if zoneNameLabel then
				-- START EMPTY — typewriter will fill it during animation
				zoneNameLabel.Text = ""
				-- Store zone name in an attribute for typewriter to use
				zoneNameLabel:SetAttribute("ZoneName", notifData.zoneName)
				-- Apply colors to text (light color)
				zoneNameLabel.TextColor3 = colorLight -- Text color (light)
				print("[ZoneNotifier] ✓ Set ZoneNameLabel.TextColor3 to light zone color")

				-- Apply color to UIStroke (dark color)
				local stroke = zoneNameLabel:FindFirstChild("UIStroke")
				if stroke then
					stroke.Color = colorDark -- Stroke color (dark)
					print("[ZoneNotifier] ✓ Set UIStroke.Color to dark zone color")
				end
			end
		end
	end

	-- Update Icon (Icon color = light zone color)
	local icon = zoneFrame:FindFirstChild("Icon")
	if icon then
		icon.ImageColor3 = colorLight -- Icon tinted to light zone color
		print("[ZoneNotifier] ✓ Set Icon.ImageColor3 to light zone color")
	else
		warn("[ZoneNotifier] Icon not found under ZoneFrame")
	end

	-- Update Skill Tab (skill colors only, independent of zone colors)
	local tabs = boundingBox:FindFirstChild("Tabs")
	if tabs then
		local skillTabBB = tabs:FindFirstChild("SkillTabBB")
		if skillTabBB then
			-- Set visibility based on showSkillTab
			skillTabBB.Visible = notifData.showSkillTab
			print("[ZoneNotifier] ✓ Set SkillTabBB.Visible to " .. tostring(notifData.showSkillTab))

			if notifData.showSkillTab then
				local skillTab = skillTabBB:FindFirstChild("SkillTab")
				if skillTab then
					-- SkillTabBB.SkillTab.UIStroke.Color = skillColor
					local skillTabStroke = skillTab:FindFirstChild("UIStroke")
					if skillTabStroke then
						skillTabStroke.Color = notifData.skillColor
						print("[ZoneNotifier] ✓ Set SkillTab.UIStroke.Color to skillColor")
					end

					-- SkillTabBB.SkillTab.SkillIcon = spritesheet with ImageRectOffset/Size
					local skillIcon = skillTab:FindFirstChild("SkillIcon")
					if skillIcon then
						skillIcon.Image = notifData.spriteSheetAssetId
						-- Compute ImageRect from sprite coordinates
						local imageRect = ZoneConfig.getImageRectFromSprite(notifData.spriteCoord)
						skillIcon.ImageRectOffset = Vector2.new(imageRect.Min.X, imageRect.Min.Y)
						skillIcon.ImageRectSize =
							Vector2.new(imageRect.Max.X - imageRect.Min.X, imageRect.Max.Y - imageRect.Min.Y)
						print("[ZoneNotifier] ✓ Set SkillIcon.Image to spritesheet")
						print(
							"[ZoneNotifier] ✓ Set SkillIcon.ImageRectOffset/Size to coords: "
								.. tostring(notifData.spriteCoord.x)
								.. ", "
								.. tostring(notifData.spriteCoord.y)
						)
					else
						warn("[ZoneNotifier] SkillIcon not found under SkillTab")
					end

					-- SkillTabBB.SkillTab.SkillLabel = skill name + colors
					local skillLabel = skillTab:FindFirstChild("SkillLabel")
					if skillLabel then
						skillLabel.Text = notifData.skill
						skillLabel.TextColor3 = notifData.skillColor
						print("[ZoneNotifier] ✓ Set SkillLabel.Text to: " .. notifData.skill)
						print("[ZoneNotifier] ✓ Set SkillLabel.TextColor3 to skillColor")

						-- SkillTabBB.SkillTab.SkillLabel.UIStroke.Color = skillColor
						local skillLabelStroke = skillLabel:FindFirstChild("UIStroke")
						if skillLabelStroke then
							skillLabelStroke.Color = notifData.skillColor
							print("[ZoneNotifier] ✓ Set SkillLabel.UIStroke.Color to skillColor")
						else
							warn("[ZoneNotifier] UIStroke not found under SkillLabel")
						end
					else
						warn("[ZoneNotifier] SkillLabel not found under SkillTab")
					end
				else
					warn("[ZoneNotifier] SkillTab not found under SkillTabBB")
				end
			end
		else
			warn("[ZoneNotifier] SkillTabBB not found under Tabs")
		end

		-- Update Level Tab
		local levelTabBB = tabs:FindFirstChild("LevelTabBB")
		if levelTabBB then
			local levelTab = levelTabBB:FindFirstChild("LevelTab")
			if levelTab then
				local levelLabel = levelTab:FindFirstChildOfClass("TextLabel")
				if levelLabel then
					levelLabel.Text = "Lv. " .. notifData.levelRange
					print("[ZoneNotifier] ✓ Set LevelTab text to: " .. notifData.levelRange)
				end
			end
		end
	end

	print("[ZoneNotifier] Populated GUI for zone: " .. notifData.zoneName)
end

-- Core: Create GUI, populate, animate in, and track
local function displayNotification(notifData)
	-- Load template
	local template = getTemplate()
	if not template then
		warn("[ZoneNotifier] Could not load template. Notification cancelled for: " .. notifData.zoneName)
		return
	end

	-- Clone template
	local notifGui = template:Clone()
	notifGui.Parent = playerGui
	notifGui.Name = "ZoneNotif_" .. notifData.zoneName

	print("[ZoneNotifier] Cloned template to playerGui: " .. notifGui:GetFullName())

	-- Create tracking data for this notification
	local notifRecord = {
		gui = notifGui,
		notifData = notifData,
		zoneName = notifData.zoneName,
		mainTween = nil,
		tabTweens = {},
		_animatingOut = false,
	}

	-- Populate with data (applies colors here)
	populateNotificationGui(notifGui, notifData)

	-- Animate in
	animateNotificationIn(notifGui, notifRecord)

	-- Track as current
	currentNotification = notifRecord

	-- Schedule auto-removal after 4 seconds
	local displayDuration = 4
	notificationDismissTime = tick() + displayDuration

	print(
		"[ZoneNotifier] Showed notification for zone: "
			.. notifData.zoneName
			.. " (auto-dismiss in "
			.. displayDuration
			.. "s)"
	)
end

-- Destroy current notification and swap to queued one (if any)
local function destroyCurrentAndProcessQueue()
	if currentNotification and currentNotification.gui then
		if currentNotification.gui.Parent then
			currentNotification.gui:Destroy()
		end
		print("[ZoneNotifier] Destroyed notification: " .. currentNotification.zoneName)
	end

	currentNotification = nil
	notificationDismissTime = nil

	-- Process queue: if there's a queued notification, show it
	if queuedNotification then
		print("[ZoneNotifier] Processing queued notification: " .. queuedNotification.zoneName)
		local nextNotifData = queuedNotification
		queuedNotification = nil
		queuedZoneName = nil
		displayNotification(nextNotifData)
	else
		print("[ZoneNotifier] Queue empty. Ready for next zone.")
	end
end

-- Request to show a zone notification
-- Handles single-slot queueing: last-zone-wins
local function requestZoneNotification(notifData)
	local zoneName = notifData.zoneName
	local currentTime = tick()

	-- SPAM PREVENTION: Check if we've shown a notification for this zone too recently
	local lastShowTime = notificationCooldown[zoneName] or 0
	if currentTime - lastShowTime < SPAM_COOLDOWN_DURATION then
		print("[ZoneNotifier] Spam blocked for: " .. zoneName)
		return
	end

	-- Update cooldown timer
	notificationCooldown[zoneName] = currentTime

	print("[ZoneNotifier] Notification requested for: " .. zoneName)

	-- If nothing is showing, display immediately
	if not currentNotification then
		print("[ZoneNotifier] No current notification. Displaying immediately.")
		displayNotification(notifData)
		return
	end

	-- If something is showing, queue the new one (overwrite if one already queued)
	if queuedZoneName == zoneName then
		-- Same zone already queued, don't add duplicate
		print("[ZoneNotifier] Zone " .. zoneName .. " already queued. Ignoring duplicate request.")
		return
	end

	print("[ZoneNotifier] Notification already showing (" .. currentNotification.zoneName .. "). Queuing: " .. zoneName)
	queuedNotification = notifData
	queuedZoneName = zoneName

	-- Trigger out-animation if not already animating out
	if not currentNotification._animatingOut then
		currentNotification._animatingOut = true
		local totalOutDuration = ZoneConfig.ANIMATION.EXIT_DURATION + 0.5 + 0.1 -- tabs + delay + buffer

		animateNotificationOut(currentNotification.gui, currentNotification)

		-- Schedule destruction and queue processing after out-animation completes
		task.delay(totalOutDuration, function()
			destroyCurrentAndProcessQueue()
		end)
	end
end

-- Listen for zone entry events from server
local function startListening()
	print("[ZoneNotifier] Waiting for ZoneEntered event...")
	local ZoneNotifyEvent = getZoneNotifyEvent()

	print("[ZoneNotifier] Connecting to ZoneEntered.OnClientEvent...")
	ZoneNotifyEvent.OnClientEvent:Connect(function(notifData)
		print("[ZoneNotifier] ✓ Received zone notification: " .. notifData.zoneName)
		requestZoneNotification(notifData)
	end)

	print("[ZoneNotifier] Listener ready ✓")
end

-- Heartbeat loop to check auto-dismiss timers
local function startAutoDismissLoop()
	RunService.Heartbeat:Connect(function()
		if notificationDismissTime and currentNotification then
			local currentTime = tick()
			if currentTime >= notificationDismissTime then
				print("[ZoneNotifier] Auto-dismissing current notification: " .. currentNotification.zoneName)

				currentNotification._animatingOut = true
				local totalOutDuration = ZoneConfig.ANIMATION.EXIT_DURATION + 0.5 + 0.1

				animateNotificationOut(currentNotification.gui, currentNotification)

				task.delay(totalOutDuration, function()
					destroyCurrentAndProcessQueue()
				end)

				notificationDismissTime = nil
			end
		end
	end)

	print("[ZoneNotifier] Auto-dismiss loop started ✓")
end

-- Initialize
startListening()
startAutoDismissLoop()
print("[ZoneNotifier] Script initialized ✓")
