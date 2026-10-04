-- ============================================================
--  ButtonVisibilityController (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  For every workspace part tagged "ClickableButton":
--    • Look up its registry config via ButtonId attribute
--    • Populate BB's labels (Name, Reward, SkillTag, IfResetTag)
--    • Tween in when player enters radius
--    • Tween out when player leaves radius
--
--  One controller for all buttons. Heartbeat-driven.
--  Per-button state is tracked in the `tracked` table.
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ButtonRegistry =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Button"):WaitForChild("ButtonRegistry"))

local TAG = "ClickableButton"

-- ===================== TUNING =====================
local CHECK_INTERVAL = 0.1 -- seconds between distance sweeps (10/sec is plenty)
local TWEEN_OFFSET = UDim2.fromScale(0, 0.4) -- how far below labels start before sliding up

local tweenInfoIn = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local tweenInfoOut = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- ===================== STATE =====================
-- tracked[part] = {
--   config          = merged ButtonRegistry config,
--   bb              = BillboardGui ref,
--   nameRewardFrame = ref,
--   tagsFrame       = ref,
--   inRange         = bool,
--   tweens          = { [Instance] = Tween },   -- active tweens per element
--   originalPositions = { [Instance] = UDim2 }, -- restore targets
-- }
local tracked = {}

local localPlayer = Players.LocalPlayer

-- ===================== HELPERS =====================

local function safeFindFirstChild(parent, name)
	return parent and parent:FindFirstChild(name) or nil
end

-- Cancel any in-flight tween for a given element (and the label fades that run with it).
local function cancelTween(entry, element)
	local t = entry.tweens[element]
	if t then
		t:Cancel()
		entry.tweens[element] = nil
	end
	local labelTweens = entry.labelTweens[element]
	if labelTweens then
		for _, lt in ipairs(labelTweens) do
			lt:Cancel()
		end
		entry.labelTweens[element] = nil
	end
end

-- Text labels under an element, cached (the tween paths used to GetDescendants every time).
local function labelsOf(entry, element)
	local cached = entry.labels[element]
	if not cached then
		cached = {}
		for _, d in ipairs(element:GetDescendants()) do
			if d:IsA("TextLabel") then
				table.insert(cached, d)
			end
		end
		entry.labels[element] = cached
	end
	return cached
end

local function fadeLabels(entry, element, info, transparency)
	local list = {}
	for _, label in ipairs(labelsOf(entry, element)) do
		local tw = TweenService:Create(label, info, {
			TextTransparency = transparency,
			TextStrokeTransparency = transparency,
		})
		tw:Play()
		table.insert(list, tw)
	end
	entry.labelTweens[element] = list
end

-- Populate BB labels from the registry config. Runs once per button.
local function populateLabels(entry)
	local cfg = entry.config
	local theme = ButtonRegistry.getTheme(cfg.skill)

	-- Name
	local nameFrame = safeFindFirstChild(entry.nameRewardFrame, "Name")
	if nameFrame then
		local label = nameFrame:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = string.format("%s  %s", cfg.displayName, ButtonRegistry.toRoman(cfg.tier or 1))
		end
	end

	-- Reward (just shows first reward for now; extend if multi-reward needed)
	local rewardFrame = safeFindFirstChild(entry.nameRewardFrame, "Reward")
	if rewardFrame then
		local label = rewardFrame:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			local rewardText = ""
			for itemId, amount in pairs(cfg.reward) do
				rewardText = rewardText .. string.format("+%d %s  ", amount, itemId)
			end
			for itemId, amount in pairs(cfg.cost) do
				rewardText = string.format("-%d %s  ", amount, itemId) .. rewardText
			end
			label.Text = rewardText
		end
	end

	-- Skill tag
	local skillTag = safeFindFirstChild(entry.tagsFrame, "SkillTag")
	if skillTag then
		local label = skillTag:FindFirstChildWhichIsA("TextLabel", true)
		if label then
			label.Text = theme.display
			label.TextColor3 = theme.color
		end
	end

	-- Reset tag (visible only when resetsOnRebirth == false)
	local resetTag = safeFindFirstChild(entry.tagsFrame, "IfResetTag")
	if resetTag then
		resetTag.Visible = (cfg.resetsOnRebirth == false)
	end
end

-- Cache the resting positions of animated elements so tween-in restores cleanly.
local function captureOriginalPositions(entry)
	for _, child in ipairs(entry.bb:GetDescendants()) do
		if child:IsA("Frame") and (child.Name == "NameReward" or child.Name == "Tags") then
			entry.originalPositions[child] = child.Position
		end
	end
end

-- ===================== TWEEN PATHS =====================

local function tweenIn(entry)
	if not entry.bb then
		return
	end
	entry.bb.Enabled = true

	for element, restPos in pairs(entry.originalPositions) do
		cancelTween(entry, element)

		-- Snap to offset position, then tween back to rest
		element.Position = restPos + TWEEN_OFFSET
		for _, label in ipairs(labelsOf(entry, element)) do
			label.TextTransparency = 1
			label.TextStrokeTransparency = 1
		end

		local t = TweenService:Create(element, tweenInfoIn, { Position = restPos })
		entry.tweens[element] = t
		t:Play()

		-- Fade in labels in parallel (tracked, so a quick leave cancels them instead of fighting them)
		fadeLabels(entry, element, tweenInfoIn, 0)
	end
end

local function tweenOut(entry)
	if not entry.bb then
		return
	end

	local longestTween
	for element, restPos in pairs(entry.originalPositions) do
		cancelTween(entry, element)

		local t = TweenService:Create(element, tweenInfoOut, {
			Position = restPos + TWEEN_OFFSET,
		})
		entry.tweens[element] = t
		t:Play()
		longestTween = t

		fadeLabels(entry, element, tweenInfoOut, 1)
	end

	if longestTween then
		longestTween.Completed:Once(function(state)
			-- Only hide if we're still out of range (player may have re-entered)
			if state == Enum.PlaybackState.Completed and not entry.inRange then
				entry.bb.Enabled = false
			end
		end)
	end
end

-- ===================== TRACKING =====================

local function registerButton(part)
	if tracked[part] then
		return
	end

	local buttonId = part:GetAttribute("ButtonId")
	if not buttonId then
		warn(("[ButtonVisibility] Part %s tagged %s but has no ButtonId attribute"):format(part:GetFullName(), TAG))
		return
	end

	local config = ButtonRegistry.get(buttonId)
	if not config then
		warn(("[ButtonVisibility] ButtonId '%s' not found in registry (part %s)"):format(buttonId, part:GetFullName()))
		return
	end

	-- Find BB anywhere under the part
	local bb
	for _, d in ipairs(part:GetDescendants()) do
		if d:IsA("BillboardGui") and d.Name == "BB" then
			bb = d
			break
		end
	end
	if not bb then
		warn(("[ButtonVisibility] Part %s missing BB BillboardGui"):format(part:GetFullName()))
		return
	end

	local entry = {
		config = config,
		bb = bb,
		nameRewardFrame = bb:FindFirstChild("NameReward"),
		tagsFrame = bb:FindFirstChild("Tags"),
		inRange = false,
		tweens = {},
		labelTweens = {}, -- [element] = { Tween } (the label fades that accompany each slide)
		labels = {}, -- [element] = { TextLabel } cache
		originalPositions = {},
	}

	captureOriginalPositions(entry)
	populateLabels(entry)

	-- Start hidden
	entry.bb.Enabled = false

	tracked[part] = entry
end

local function unregisterButton(part)
	local entry = tracked[part]
	if not entry then
		return
	end
	for element in pairs(entry.originalPositions) do
		cancelTween(entry, element)
	end
	tracked[part] = nil
end

-- ===================== DISTANCE LOOP =====================

local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < CHECK_INTERVAL then
		return
	end
	accum = 0

	local char = localPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local playerPos = hrp.Position

	for part, entry in pairs(tracked) do
		if not part.Parent then
			unregisterButton(part)
			continue
		end

		local distance = (playerPos - part.Position).Magnitude
		local maxDist = part:GetAttribute("VisibilityDistance") or entry.config.visibilityDistance

		if distance <= maxDist then
			if not entry.inRange then
				entry.inRange = true
				tweenIn(entry)
			end
		else
			if entry.inRange then
				entry.inRange = false
				tweenOut(entry)
			end
		end
	end
end)

-- ===================== TAG HOOKUP =====================

for _, part in ipairs(CollectionService:GetTagged(TAG)) do
	registerButton(part)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(registerButton)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(unregisterButton)

