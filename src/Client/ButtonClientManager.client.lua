--[[
	ButtonClientManager (LocalScript)
	Place inside: StarterPlayerScripts
 
	Handles:
	  - Scanning workspace.Buttons and populating BillboardGui labels
	  - Listening for ButtonPurchaseResult RemoteEvent
	  - Firing StatisticLogModule.logStat / logStatNegative for purchase feedback
	  - Formatting billboard labels with green (+gain) and red (-cost) text
	  - Initializing StatisticLogModule if not yet initialized
 
	This script does ZERO game logic.  All purchase validation and stat
	mutation happen server-side in ButtonServerManager / StatisticsDataManager.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================== MODULES =====================
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ButtonConfig = require(Modules:WaitForChild("ButtonConfig")) :: any
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any
local StatisticLogModule = require(Modules:WaitForChild("StatisticLogModule")) :: any

-- ===================== REMOTE EVENT =====================
local ButtonPurchaseResult = ReplicatedStorage:WaitForChild("ButtonPurchaseResult")

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")

-- ===================== AFFORD COLOR CONFIG =====================
local COLOR_TOP_AFFORD = Color3.fromHex("#55FF55")
local COLOR_BOTTOM_AFFORD = Color3.fromHex("#00AA00")
local COLOR_TOP_CANT = Color3.fromHex("#FF5555")
local COLOR_BOTTOM_CANT = Color3.fromHex("#AA0000")
local colorTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ===================== ENSURE LOG MODULE INITIALIZED =====================
-- StatisticLogModule requires .init() with the StatisticLog ScreenGui.
-- If another script already called init, this is safely idempotent.
task.spawn(function()
	local StatisticLog = playerGui:WaitForChild("StatisticLog", 10)
	if StatisticLog then
		StatisticLogModule.init(StatisticLog)
	else
		warn("[ButtonClientManager] StatisticLog ScreenGui not found — log entries may not display")
	end
end)

-- ===================== HELPERS =====================
local statConfigLookup = StatisticsConfig.statConfigLookup

--- Look up display name and color for a stat key.
local function getStatDisplay(skill: string, statKey: string): (string, string)
	local config = statConfigLookup[skill] and statConfigLookup[skill][statKey]
	if config then
		return config.name or statKey, config.color or "#FFFFFF"
	end
	return statKey, "#FFFFFF"
end

--- Format a number using MoneyLib for consistency with the rest of the UI.
local function formatNumber(n: number): string
	if n == math.floor(n) then
		return MoneyLib.DealWithPoints(n)
	end
	if n >= 1000 then
		return MoneyLib.DealWithPoints(math.floor(n))
	end
	return string.format("%.2f", n)
end

-- ===================== MULTIPLIER STATE =====================
--- Stores the latest StatisticsUpdated payload so we can read multipliers.
local latestPayload = nil

--- Registered buttons: list of { model, configKey, tierNum, gainedLabel, subtractedLabel, buyProperty, buttonDef, tierConfig }
--- Used to refresh labels when multipliers change.
local registeredButtons = {}

-- Remote for stat updates (multiplier changes)
local StatisticsUpdated = ReplicatedStorage:WaitForChild("StatisticsUpdated")

-- ===================== BILLBOARD POPULATION =====================
--- Populates the BillboardGui labels on a button model.
--- Reads current multiplier from latestPayload if available.
local function populateBillboard(buttonModel: Model, buttonDef, tierConfig)
	-- WaitForChild — descendants may not have replicated yet
	local billboard = nil
	local billboardParent = nil
	local top = buttonModel:WaitForChild("Top", 10)
	if top then
		billboard = top:WaitForChild("BillboardGui", 10)
		billboardParent = top
	end
	if not billboard then
		-- Fallback: search descendants
		for _, child in ipairs(buttonModel:GetDescendants()) do
			if child:IsA("BillboardGui") then
				billboard = child
				billboardParent = child.Parent
				break
			end
		end
	end
	if not billboard then
		warn("[ButtonClientManager] No BillboardGui found on: " .. buttonModel.Name)
		return
	end

	-- ── Clone into a client-owned copy so text changes are per-player ──
	local localBillboard = billboard:Clone()
	billboard:Destroy() -- destroys server copy locally (other clients keep theirs)
	localBillboard.Parent = billboardParent
	billboard = localBillboard

	-- ── Read current multiplier ──
	local multiplier = 1
	if latestPayload and latestPayload.skills then
		local skillData = latestPayload.skills[buttonDef.skill]
		if skillData and skillData[buttonDef.statKey] then
			multiplier = skillData[buttonDef.statKey].multiplier or 1
		end
	end

	-- ── Gained label (+green) — shows multiplied amount ──
	local gainedLabel = nil
	local gainedFrame = billboard:FindFirstChild("GainedAmount")
	if gainedFrame then
		gainedLabel = gainedFrame:FindFirstChild("GainedAmountLabel")
		if gainedLabel and gainedLabel:IsA("TextLabel") then
			local statName, statColor = getStatDisplay(buttonDef.skill, buttonDef.statKey)
			local displayGain = math.max(1, math.floor(tierConfig.baseGain * multiplier))
			local amount = formatNumber(displayGain)
			gainedLabel.RichText = true
			gainedLabel.Text = string.format(
				'<font color="#55FF55">+%s</font> <font weight="bold"color="%s">%s</font>',
				amount,
				statColor,
				statName
			)
		end
	end

	-- ── Subtracted label (-red) ──
	local subtractedFrame = billboard:FindFirstChild("SubtractedAmount")
	if subtractedFrame then
		local subtractedLabel = subtractedFrame:FindFirstChild("SubtractedAmountLabel")
		if subtractedLabel and subtractedLabel:IsA("TextLabel") then
			-- Show the first (primary) cost.  If multiple costs, show the largest.
			local costEntries = tierConfig.cost
			if costEntries and #costEntries > 0 then
				local primary = costEntries[1]
				local costName, _costColor = getStatDisplay(primary.skill, primary.id)
				local costAmount = formatNumber(primary.amount)
				subtractedLabel.RichText = true
				subtractedLabel.Text = string.format(
					'<font color="#FF5555">-%s</font> <font weight="bold" color="%s">%s</font>',
					costAmount,
					_costColor,
					costName
				)

				-- If multiple costs, append secondary costs
				if #costEntries > 1 then
					local parts = {}
					for i = 2, #costEntries do
						local c = costEntries[i]
						local cName = getStatDisplay(c.skill, c.id)
						table.insert(
							parts,
							string.format(
								'<font color="#FF5555">-%s</font> <font weight="bold" color="%s">%s</font>',
								formatNumber(c.amount),
								_costColor,
								cName
							)
						)
					end
					subtractedLabel.Text = subtractedLabel.Text .. "\n" .. table.concat(parts, "\n")
				end
			end
		end
	end

	-- ── Register for multiplier refresh ──
	local topPart = buttonModel:FindFirstChild("Top")
	local bottomPart = buttonModel:FindFirstChild("Bottom")
	table.insert(registeredButtons, {
		model = buttonModel,
		buttonDef = buttonDef,
		tierConfig = tierConfig,
		gainedLabel = gainedLabel,
		topPart = topPart,
		bottomPart = bottomPart,
		lastAfford = nil,
	})
end

-- ===================== AFFORD CHECK =====================
--- Returns true if the player can currently afford a button's cost.
local function canAfford(tierConfig)
	if not latestPayload or not latestPayload.skills then
		return false
	end
	for _, costEntry in ipairs(tierConfig.cost or {}) do
		local skillData = latestPayload.skills[costEntry.skill]
		if not skillData then
			return false
		end
		local statData = skillData[costEntry.id]
		if not statData or (statData.count or 0) < costEntry.amount then
			return false
		end
	end
	return true
end

--- Tweens Top and Bottom parts to afford/can't-afford colors.
local function tweenAffordColor(reg, afford)
	-- Skip if state hasn't changed
	if reg.lastAfford == afford then
		return
	end
	reg.lastAfford = afford

	local topColor = afford and COLOR_TOP_AFFORD or COLOR_TOP_CANT
	local bottomColor = afford and COLOR_BOTTOM_AFFORD or COLOR_BOTTOM_CANT

	if reg.topPart and reg.topPart:IsA("BasePart") then
		TweenService:Create(reg.topPart, colorTweenInfo, { Color = topColor }):Play()
	end
	if reg.bottomPart and reg.bottomPart:IsA("BasePart") then
		TweenService:Create(reg.bottomPart, colorTweenInfo, { Color = bottomColor }):Play()
	end
	local pointLight = reg.topPart and reg.topPart:FindFirstChildOfClass("PointLight")
	if pointLight then
		TweenService:Create(pointLight, colorTweenInfo, { Color = topColor }):Play()
	end
end

-- ===================== REFRESH ALL BILLBOARDS (multiplier + afford update) =====================
local function refreshAllBillboards()
	if not latestPayload or not latestPayload.skills then
		return
	end

	for _, reg in ipairs(registeredButtons) do
		local def = reg.buttonDef
		local tier = reg.tierConfig

		-- ── Update gained label ──
		local label = reg.gainedLabel
		if label and label.Parent then
			local multiplier = 1
			local skillData = latestPayload.skills[def.skill]
			if skillData and skillData[def.statKey] then
				multiplier = skillData[def.statKey].multiplier or 1
			end

			local displayGain = math.max(1, math.floor(tier.baseGain * multiplier))
			local statName = getStatDisplay(def.skill, def.statKey)
			label.Text = string.format('<font color="#55FF55">+%s</font> %s', formatNumber(displayGain), statName)
		end

		-- ── Update afford color ──
		tweenAffordColor(reg, canAfford(tier))
	end
end

-- ===================== SCAN AND POPULATE ALL BUTTONS =====================
local function tryPopulateButton(model)
	local parts = string.split(model.Name, ".")
	if #parts >= 3 and parts[1] == "Button" then
		local configKey = parts[2]
		local tierNum = tonumber(parts[3])
		local buttonDef = ButtonConfig.BUTTONS[configKey]
		if buttonDef and tierNum and buttonDef.tiers[tierNum] then
			task.spawn(populateBillboard, model, buttonDef, buttonDef.tiers[tierNum])
		end
	end
end

local function scanDescendantButtons(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, 7) == "Button." then
			tryPopulateButton(child)
		elseif child:IsA("Folder") then
			scanDescendantButtons(child)
		end
	end

	container.DescendantAdded:Connect(function(desc)
		if desc:IsA("Model") and string.sub(desc.Name, 1, 7) == "Button." then
			task.defer(tryPopulateButton, desc)
		end
	end)
end

local function scanButtons()
	local folder = workspace:FindFirstChild(ButtonConfig.BUTTONS_FOLDER)
	if not folder then
		warn("[ButtonClientManager] Folder '" .. ButtonConfig.BUTTONS_FOLDER .. "' not found in workspace")
		return
	end
	scanDescendantButtons(folder)
end

-- ===================== PURCHASE RESULT → LOG =====================
ButtonPurchaseResult.OnClientEvent:Connect(function(data)
	-- data = { skill, statKey, gain, owned, costs }
	-- costs = { { skill, id, amount, remaining }, ... }
	UIClick:Play()

	local statName, statColor = getStatDisplay(data.skill, data.statKey)

	-- ── Positive log: gained stat ──
	StatisticLogModule.logStat(statName, data.gain, statColor, data.owned)

	-- ── Negative log: each cost deducted ──
	if data.costs then
		for _, costEntry in ipairs(data.costs) do
			local costName, costColor = getStatDisplay(costEntry.skill, costEntry.id)
			StatisticLogModule.logStatNegative(costName, costEntry.amount, costColor, costEntry.remaining)
		end
	end
end)

-- ===================== STATISTICS UPDATED → REFRESH BILLBOARDS =====================
StatisticsUpdated.OnClientEvent:Connect(function(payload)
	latestPayload = payload
	refreshAllBillboards()
end)

-- ===================== INIT =====================
scanButtons()
print("ButtonClientManager: Ready ✓")
