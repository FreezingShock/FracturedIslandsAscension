--[[
	ButtonServerManager (Script)
	Place inside: ServerScriptService

	Handles:
	  - Scanning workspace.Buttons for button models
	  - Touch detection on Top/Hitbox parts
	  - Auto-repeat purchase loops at configurable interval
	  - Purchase validation via StatisticsDataManager.ProcessButtonPurchase
	  - Server-side tween animation (Top presses down/up)
	  - Firing ButtonPurchaseResult RemoteEvent to client for log display
	  - Per-player per-button touch counting for robust detection
	  - Grace period to survive physics jitter from tween
	  - Clean player disconnect cleanup
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ===================== MODULES =====================
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ButtonConfig = require(Modules:WaitForChild("ButtonConfig")) :: any
local StatisticsDataManager = require(ServerScriptService:WaitForChild("StatisticsDataManager")) :: any

-- ===================== REMOTE EVENT =====================
local function ensureRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local ButtonPurchaseResult = ensureRemote("ButtonPurchaseResult")

-- ===================== TWEEN CONFIG =====================
local PRESS_DEPTH = ButtonConfig.PRESS_DEPTH
local tweenDownInfo = TweenInfo.new(ButtonConfig.TWEEN_DOWN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local tweenUpInfo = TweenInfo.new(ButtonConfig.TWEEN_UP, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local GRACE_PERIOD = ButtonConfig.GRACE_PERIOD

-- ===================== STATE =====================
--- Per-player per-button tracking.
--- playerStates[userId][buttonId] = {
---   touchCount : number     — how many character parts are touching
---   active     : boolean    — is the purchase loop running
---   graceThread: thread?    — delayed stop thread (cancelled on re-touch)
--- }
local playerStates: { [number]: { [string]: any } } = {}

--- Per-button animation lock.  Prevents overlapping tweens from multiple players.
--- buttonAnimLock[buttonId] = true while a tween cycle is in progress.
local buttonAnimLock: { [string]: boolean } = {}

--- Original CFrame of each button's Top part, stored at startup.
local originalCFrames: { [string]: CFrame } = {}

-- ===================== HELPERS =====================
local function getButtonId(model: Model): string
	return model:GetFullName()
end

local function getPlayerFromHit(hit: BasePart): Player?
	local character = hit.Parent
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return Players:GetPlayerFromCharacter(character)
end

local function ensurePlayerState(userId: number, buttonId: string)
	if not playerStates[userId] then
		playerStates[userId] = {}
	end
	if not playerStates[userId][buttonId] then
		playerStates[userId][buttonId] = {
			touchCount = 0,
			active = false,
			graceThread = nil,
		}
	end
	return playerStates[userId][buttonId]
end

-- ===================== PURCHASE LOOP =====================
local function runPurchaseLoop(player: Player, buttonId: string, buttonConfig, tierConfig, topPart: BasePart)
	local userId = player.UserId
	local state = ensurePlayerState(userId, buttonId)
	local interval = tierConfig.interval or ButtonConfig.DEFAULT_INTERVAL

	local skill = buttonConfig.skill
	local statKey = buttonConfig.statKey
	local baseGain = tierConfig.baseGain
	local costEntries = tierConfig.cost

	local originalCF = originalCFrames[buttonId]
	local downCF = originalCF and (originalCF - Vector3.new(0, PRESS_DEPTH, 0)) or nil

	while state.active do
		-- ── Check player still valid ──
		if not player.Parent then
			state.active = false
			break
		end

		-- ── Process purchase ──
		local success, gain, costDetails, ownedAfter =
			StatisticsDataManager.ProcessButtonPurchase(player, skill, statKey, baseGain, costEntries)

		if success then
			-- ── Fire client feedback ──
			ButtonPurchaseResult:FireClient(player, {
				skill = skill,
				statKey = statKey,
				gain = gain,
				owned = ownedAfter,
				costs = costDetails,
			})

			-- ── Button press animation (shared lock) ──
			if originalCF and downCF and not buttonAnimLock[buttonId] then
				buttonAnimLock[buttonId] = true
				TweenService:Create(topPart, tweenDownInfo, { CFrame = downCF }):Play()
				task.wait(ButtonConfig.TWEEN_DOWN)
				TweenService:Create(topPart, tweenUpInfo, { CFrame = originalCF }):Play()
				task.wait(ButtonConfig.TWEEN_UP)
				buttonAnimLock[buttonId] = false
			else
				-- Another player is animating or no CFrame — just wait the interval
				task.wait(interval)
			end
		else
			-- ── Purchase failed (can't afford) — wait and retry ──
			task.wait(interval)
		end
	end
end

-- ===================== START / STOP LOGIC =====================
local function startLoop(player: Player, buttonId: string, buttonConfig, tierConfig, topPart: BasePart)
	local userId = player.UserId
	local state = ensurePlayerState(userId, buttonId)

	-- Cancel any pending grace-period stop
	if state.graceThread then
		task.cancel(state.graceThread)
		state.graceThread = nil
	end

	-- Already running — nothing to do
	if state.active then
		return
	end

	state.active = true
	task.spawn(runPurchaseLoop, player, buttonId, buttonConfig, tierConfig, topPart)
end

local function scheduleStop(player: Player, buttonId: string)
	local userId = player.UserId
	if not playerStates[userId] then
		return
	end
	local state = playerStates[userId][buttonId]
	if not state then
		return
	end

	-- Cancel any previous grace thread
	if state.graceThread then
		task.cancel(state.graceThread)
		state.graceThread = nil
	end

	state.graceThread = task.delay(GRACE_PERIOD, function()
		state.graceThread = nil
		state.active = false
	end)
end

-- ===================== WIRE BUTTON =====================
local function wireButton(buttonModel: Model)
	-- ── Parse name: Button.{ConfigKey}.{Tier} ──
	local parts = string.split(buttonModel.Name, ".")
	if #parts < 3 or parts[1] ~= "Button" then
		warn("[ButtonServerManager] Skipping model with invalid name: " .. buttonModel.Name)
		return
	end

	local configKey = parts[2]
	local tierNum = tonumber(parts[3])
	if not tierNum then
		warn("[ButtonServerManager] Invalid tier number in: " .. buttonModel.Name)
		return
	end

	local buttonDef = ButtonConfig.BUTTONS[configKey]
	if not buttonDef then
		warn("[ButtonServerManager] No ButtonConfig entry for: " .. configKey)
		return
	end

	local tierConfig = buttonDef.tiers[tierNum]
	if not tierConfig then
		warn("[ButtonServerManager] No tier " .. tierNum .. " in ButtonConfig for: " .. configKey)
		return
	end

	-- ── Find touch part: prefer Hitbox, fall back to Top ──
	local touchPart = buttonModel:FindFirstChild("Hitbox") or buttonModel:FindFirstChild("Top")
	if not touchPart or not touchPart:IsA("BasePart") then
		warn("[ButtonServerManager] No Hitbox or Top part in: " .. buttonModel.Name)
		return
	end

	-- ── Find Top for tween animation (always Top, not Hitbox) ──
	local topPart = buttonModel:FindFirstChild("Top")
	if topPart and topPart:IsA("BasePart") then
		local buttonId = getButtonId(buttonModel)
		originalCFrames[buttonId] = topPart.CFrame
	end

	local buttonId = getButtonId(buttonModel)

	-- ── Touch events (wired ONCE at startup) ──
	touchPart.Touched:Connect(function(hit)
		local player = getPlayerFromHit(hit)
		if not player then
			return
		end

		local state = ensurePlayerState(player.UserId, buttonId)
		state.touchCount = state.touchCount + 1

		-- Only start on first touching part
		if state.touchCount == 1 then
			startLoop(player, buttonId, buttonDef, tierConfig, topPart or touchPart)
		end
	end)

	touchPart.TouchEnded:Connect(function(hit)
		local player = getPlayerFromHit(hit)
		if not player then
			return
		end

		local state = ensurePlayerState(player.UserId, buttonId)
		state.touchCount = math.max(0, state.touchCount - 1)

		-- Only schedule stop when ALL parts have left
		if state.touchCount <= 0 then
			state.touchCount = 0
			scheduleStop(player, buttonId)
		end
	end)

	print("[ButtonServerManager] Wired: " .. buttonModel.Name .. " (tier " .. tierNum .. ")")
end

-- ===================== SCAN AND WIRE ALL BUTTONS =====================
local function wireDescendantButtons(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, 7) == "Button." then
			wireButton(child)
		elseif child:IsA("Folder") then
			wireDescendantButtons(child)
		end
	end

	-- Wire buttons added later at any depth
	container.DescendantAdded:Connect(function(desc)
		if desc:IsA("Model") and string.sub(desc.Name, 1, 7) == "Button." then
			task.defer(wireButton, desc)
		end
	end)
end

local function scanButtons()
	local folder = workspace:FindFirstChild(ButtonConfig.BUTTONS_FOLDER)
	if not folder then
		warn("[ButtonServerManager] Folder '" .. ButtonConfig.BUTTONS_FOLDER .. "' not found in workspace")
		return
	end
	wireDescendantButtons(folder)
end

-- ===================== PLAYER CLEANUP =====================
Players.PlayerRemoving:Connect(function(player)
	local userId = player.UserId
	if playerStates[userId] then
		for _, state in pairs(playerStates[userId]) do
			state.active = false
			if state.graceThread then
				task.cancel(state.graceThread)
				state.graceThread = nil
			end
		end
		playerStates[userId] = nil
	end
end)

-- ===================== CHARACTER DEATH → STOP ALL LOOPS =====================
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			local userId = player.UserId
			if not playerStates[userId] then
				return
			end
			for _, state in pairs(playerStates[userId]) do
				state.active = false
				state.touchCount = 0
				if state.graceThread then
					task.cancel(state.graceThread)
					state.graceThread = nil
				end
			end
		end)
	end)
end)

-- Handle players already in game (Studio testing)
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				local userId = player.UserId
				if not playerStates[userId] then
					return
				end
				for _, state in pairs(playerStates[userId]) do
					state.active = false
					state.touchCount = 0
					if state.graceThread then
						task.cancel(state.graceThread)
						state.graceThread = nil
					end
				end
			end)
		end
	end
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			local userId = player.UserId
			if not playerStates[userId] then
				return
			end
			for _, state in pairs(playerStates[userId]) do
				state.active = false
				state.touchCount = 0
				if state.graceThread then
					task.cancel(state.graceThread)
					state.graceThread = nil
				end
			end
		end)
	end)
end

-- ===================== INIT =====================
scanButtons()
print("ButtonServerManager: Ready ✓")
