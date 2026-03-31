--[[
	StatisticsPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Client-side rendering for the per-skill statistics sub-grid
	(StatisticsMenu2).  Dynamically clones StatSlot templates and
	BlankSlots to fill a row-aligned grid.

	StatSlot hierarchy (in TemporaryMenus):
	  StatSlot (GuiButton)
	    UICorner
	    UIGradient
	    BG (ImageLabel)
	      UICorner
	      UIGradient
	      UIStroke
	    Icon (ImageLabel)

	API:
	  init(sharedRefs, statsMenu2Frame)
	  openSkill(skillName)
	  close()
	  reset()
	  getActiveSkill()
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("StatisticsConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

local ContentProvider = game:GetService("ContentProvider")

local STAT_CHAINS = Config.STAT_CHAINS
local SKILL_COLORS = Config.SKILL_COLORS
local statConfigLookup = Config.statConfigLookup
local LAYOUT = Config.LAYOUT
local COLUMNS = Config.COLUMNS
local STAT_ROWS = Config.STAT_ROWS
local STATS_PER_ROW = Config.STATS_PER_ROW

local player = Players.LocalPlayer

-- ===================== STATISTIC LOG INTEGRATION =====================
local StatisticLogModule = require(Modules:WaitForChild("StatisticLogModule")) :: any

local pendingPurchases = {} -- array of { skill = string, statKey = string, oldCount = number, costs = {{ skill, id, amount }} }

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")

-- ===================== STATE =====================
local shared = nil
local TooltipModule = nil
local statsFrame = nil
local statSlotTemplate = nil
local blankSlotTemplate = nil
local selectedSkillFrame = nil

local currentSkill = nil
local dynamicChildren = {}
local slotRefs = {}
local cachedData = nil
local hoveredStatKey = nil -- tracks which stat slot is currently hovered

-- ===================== REMOTES =====================
local StatisticsUpdated = ReplicatedStorage:WaitForChild("StatisticsUpdated")
local PurchaseStat = ReplicatedStorage:WaitForChild("PurchaseStat")

-- ===================== MODULE =====================
local M = {}

-- ===================== HELPERS =====================
local function formatNumber(n)
	if n == math.floor(n) then
		-- integer: always use MoneyLib
		return MoneyLib.DealWithPoints(n)
	end
	-- decimal: use MoneyLib if >= 1000, otherwise keep 2dp
	if n >= 1000 then
		return MoneyLib.DealWithPoints(math.floor(n))
	end
	return string.format("%.2f", n)
end

local function hexToColor3(hex)
	hex = hex:gsub("#", "")
	local r = tonumber(hex:sub(1, 2), 16) or 255
	local g = tonumber(hex:sub(3, 4), 16) or 255
	local b = tonumber(hex:sub(5, 6), 16) or 255
	return Color3.fromRGB(r, g, b)
end

local function getStatData(skill, statKey)
	if not cachedData or not cachedData.skills then
		return { count = 0, lifetime = 0, session = 0, multiplier = 1 }
	end
	local skillData = cachedData.skills[skill]
	if not skillData or not skillData[statKey] then
		return { count = 0, lifetime = 0, session = 0, multiplier = 1 }
	end
	return skillData[statKey]
end

-- ===================== CLONE BLANK SLOT =====================
local function cloneBlank(layoutOrder)
	if not blankSlotTemplate then
		return nil
	end
	local blank = blankSlotTemplate:Clone()
	blank.LayoutOrder = layoutOrder
	blank.Visible = true
	blank.Parent = statsFrame
	table.insert(dynamicChildren, blank)
	return blank
end

-- ===================== SLOT VISUALS =====================
--- Applies per-stat color theming and icon to a cloned StatSlot.
--- color → StatSlot.BackgroundColor3, BG.ImageColor3, BG.UIStroke.Color
--- icon  → Icon.Image
--- Applies color theming and icon to a cloned StatSlot.
--- Hierarchy: StatSlot > BG > UIStroke, StatSlot > Icon
local function applySlotVisuals(slot, item)
	local color = hexToColor3(item.color or "#FFFFFF")

	-- StatSlot.BackgroundColor3
	slot.BackgroundColor3 = color

	-- BG.ImageColor3 + BG.UIStroke.Color
	local bg = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
	end

	-- Icon image
	local icon = slot:FindFirstChild("Icon")
	if icon then
		if item.icon and item.icon ~= "" then
			icon.Image = item.icon
		else
			icon.Image = ""
		end
	end
end

-- ===================== TOOLTIP BUILDER =====================
local function buildStatTooltip(skill, statKey)
	local config = statConfigLookup[skill] and statConfigLookup[skill][statKey]
	if not config then
		return nil
	end

	local data = getStatData(skill, statKey)
	local skillColor = SKILL_COLORS[skill] or "#FFFFFF"
	local itemColor = config.color or skillColor

	-- Title (uses per-stat color)
	local title = string.format('<font color="%s"><b>%s</b></font>', itemColor, config.name)

	-- Description lines
	local lines = {}

	-- Counts
	table.insert(
		lines,
		string.format(
			'<font color="#FFFFFF">Owned: <b>%s</b></font>  '
				.. '<font color="#AAAAAA">(Lifetime: %s | Session: %s)</font>',
			formatNumber(data.count),
			formatNumber(data.lifetime),
			formatNumber(data.session)
		)
	)

	-- Multiplier
	table.insert(
		lines,
		string.format('<font color="#55FF55">Multiplier: <b>×%s</b></font>', formatNumber(data.multiplier))
	)

	table.insert(lines, "")

	-- Cost
	table.insert(lines, '<font color="#AAAAAA"><b>Cost:</b></font>')
	for _, costEntry in ipairs(config.cost or {}) do
		if costEntry.type == "stat" then
			local sConfig = statConfigLookup[costEntry.skill] and statConfigLookup[costEntry.skill][costEntry.id]
			local sName = sConfig and sConfig.name or costEntry.id
			local sColor = sConfig and sConfig.color or (SKILL_COLORS[costEntry.skill] or "#FFFFFF")
			local owned = getStatData(costEntry.skill, costEntry.id).count
			local afford = owned >= costEntry.amount
			local numColor = afford and "#55FF55" or "#FF5555"
			table.insert(
				lines,
				string.format(
					'  <font color="#FF5555">-</font><font color="%s">%s</font> <font color="%s">%s</font>',
					numColor,
					formatNumber(costEntry.amount),
					sColor,
					sName
				)
			)
		end
	end

	table.insert(lines, "")

	-- Rewards
	table.insert(lines, '<font color="#AAAAAA"><b>Rewards (per owned):</b></font>')
	for _, reward in ipairs(config.rewards or {}) do
		if reward.type == "stat" then
			local rConfig = statConfigLookup[reward.skill] and statConfigLookup[reward.skill][reward.target]
			local rName = rConfig and rConfig.name or reward.target
			local rColor = rConfig and rConfig.color or (SKILL_COLORS[reward.skill] or "#FFFFFF")
			table.insert(
				lines,
				string.format(
					'  <font color="#55FF55">+%d%%</font> <font color="%s">%s</font>',
					reward.pct,
					rColor,
					rName
				)
			)
		elseif reward.type == "gameStat" then
			table.insert(
				lines,
				string.format('  <font color="#FF55FF">+%s %s</font>', tostring(reward.flat), reward.target)
			)
		end
	end

	local desc = table.concat(lines, "\n")

	-- Click line
	local canAfford = true
	for _, costEntry in ipairs(config.cost or {}) do
		if costEntry.type == "stat" then
			if getStatData(costEntry.skill, costEntry.id).count < costEntry.amount then
				canAfford = false
				break
			end
		end
	end

	local click
	if config.passive then
		click = '<font color="#55FF55">Earned passively!</font>'
	elseif not config.cost or #config.cost == 0 then
		click = ""
	elseif canAfford then
		click = '<font color="#FFFF55">Click to purchase!</font>'
	else
		click = '<font color="#FF5555">Not enough resources!</font>'
	end

	return { title = title, desc = desc, click = click }
end

-- ===================== CLEANUP =====================
local function clearDynamicChildren()
	for _, child in ipairs(dynamicChildren) do
		if child and child.Parent then
			child:Destroy()
		end
	end
	dynamicChildren = {}
	slotRefs = {}
end

-- ===================== REFRESH COUNTS (silent) =====================
local function refreshSlotCounts()
	if not currentSkill then
		return
	end
	for statKey, ref in pairs(slotRefs) do
		local data = getStatData(currentSkill, statKey)
		if ref.countLabel then
			ref.countLabel.Text = formatNumber(data.count)
		end
	end

	-- Live-refresh the tooltip if hovering a stat slot
	if hoveredStatKey and slotRefs[hoveredStatKey] then
		local tooltipData = buildStatTooltip(currentSkill, hoveredStatKey)
		if tooltipData then
			TooltipModule.show(tooltipData)
		end
	end
end

-- ===================== OPEN SKILL =====================
function M.openSkill(skillName, activeFrame)
	-- Update frame reference if a new buffer was provided
	if activeFrame then
		statsFrame = activeFrame
		selectedSkillFrame = activeFrame:FindFirstChild("SelectedSkill")
		-- Wire tooltip on freshly cloned SelectedSkill (GC'd with instance)
		if selectedSkillFrame then
			selectedSkillFrame.MouseEnter:Connect(function()
				if currentSkill and shared.SkillsPageModule then
					shared.SkillsPageModule.showGridSkillTooltip(currentSkill, false)
				end
			end)
			selectedSkillFrame.MouseLeave:Connect(function()
				if shared.SkillsPageModule then
					shared.SkillsPageModule.hideGridSkillTooltip()
				end
			end)
		end
	end
	clearDynamicChildren()
	currentSkill = skillName

	local chain = STAT_CHAINS[skillName]
	if not chain then
		warn("[StatisticsPageModule] No chain defined for " .. tostring(skillName))
		return
	end

	-- ── Update SelectedSkill visuals (icon + colors) ──
	if selectedSkillFrame then
		selectedSkillFrame.LayoutOrder = LAYOUT.selectedSkillOrder

		local GridTemplates = ReplicatedStorage:FindFirstChild("GridTemplates")
		local statisticsMenu1 = GridTemplates and GridTemplates:FindFirstChild("StatisticsMenu1")
		if statisticsMenu1 then
			local skillButton = statisticsMenu1:FindFirstChild(skillName .. "Statistics")
			if skillButton then
				local sourceIcon = skillButton:FindFirstChild("Icon")
				local icon = selectedSkillFrame:FindFirstChild("Icon")
				if icon and sourceIcon then
					icon.Image = sourceIcon.Image
				end

				local sourceBg = skillButton:FindFirstChild("BG")
				if sourceBg then
					selectedSkillFrame.BackgroundColor3 = sourceBg.BackgroundColor3
					local bg = selectedSkillFrame:FindFirstChild("BG")
					if bg then
						bg.ImageColor3 = sourceBg.ImageColor3
						local bgStroke = bg:FindFirstChildOfClass("UIStroke")
						local sourceBgStroke = sourceBg:FindFirstChildOfClass("UIStroke")
						if bgStroke and sourceBgStroke then
							bgStroke.Color = sourceBgStroke.Color
						end
					end
				end
			end
		end
	end

	-- ── Row 0: header blanks ──
	for i = 0, LAYOUT.headerBlanksBefore - 1 do
		cloneBlank(i)
	end
	for i = 1, LAYOUT.headerBlanksAfter do
		cloneBlank(LAYOUT.selectedSkillOrder + i)
	end

	-- ── Rows 1-4: stat rows ──
	local statIndex = 1
	for row = 0, STAT_ROWS - 1 do
		local rowBase = LAYOUT.statRowBaseOrder + (row * COLUMNS)

		-- Left pad blanks
		for pad = 0, LAYOUT.statRowPadCount - 1 do
			cloneBlank(rowBase + pad)
		end

		-- Stat slots or blank fills
		for col = LAYOUT.statRowPadCount, LAYOUT.statRowPadCount + STATS_PER_ROW - 1 do
			local lo = rowBase + col
			if statIndex <= #chain then
				local item = chain[statIndex]

				local slot = statSlotTemplate:Clone()
				slot.Name = "Stat_" .. item.key
				slot.LayoutOrder = lo
				slot.Visible = true
				slot.Parent = statsFrame

				-- Apply color + icon from config
				applySlotVisuals(slot, item)

				local iconLabel = slot:FindFirstChild("Icon")
				local countLabel = slot:FindFirstChild("ItemCount")

				if countLabel then
					local data = getStatData(skillName, item.key)
					countLabel.Text = formatNumber(data.count)
				end

				slotRefs[item.key] = {
					frame = slot,
					iconLabel = iconLabel,
					countLabel = countLabel,
				}

				-- Hover tooltip (auto-disconnects on Destroy)
				slot.MouseEnter:Connect(function()
					hoveredStatKey = item.key
					UIClick3:Play()
					local tooltipData = buildStatTooltip(skillName, item.key)
					if tooltipData then
						TooltipModule.show(tooltipData)
					end
				end)
				slot.MouseLeave:Connect(function()
					hoveredStatKey = nil
					TooltipModule.hide()
				end)

				-- Purchase click + hold-to-repeat
				do
					local holding = false
					local holdConn = nil

					slot.MouseButton1Down:Connect(function()
						if item.passive then
							return
						end
						if not item.cost or #item.cost == 0 then
							return
						end

						holding = true

						local function firePurchase()
							UIClick:Play()
							local oldCount = getStatData(skillName, item.key).count

							-- Snapshot cost entries so we can log negatives on confirmation
							local costSnapshot = {}
							for _, costEntry in ipairs(item.cost) do
								if costEntry.type == "stat" then
									table.insert(costSnapshot, {
										skill = costEntry.skill,
										id = costEntry.id,
										amount = costEntry.amount,
									})
								end
							end

							table.insert(pendingPurchases, {
								skill = skillName,
								statKey = item.key,
								oldCount = oldCount,
								costs = costSnapshot,
							})
							PurchaseStat:FireServer(skillName, item.key)
						end

						-- Immediate first fire
						firePurchase()

						-- Hold repeat
						holdConn = task.spawn(function()
							while holding do
								task.wait(0.05)
								if not holding then
									break
								end
								firePurchase()
							end
						end)
					end)

					slot.MouseButton1Up:Connect(function()
						holding = false
					end)

					slot.MouseLeave:Connect(function()
						holding = false
					end)
				end

				table.insert(dynamicChildren, slot)
				statIndex = statIndex + 1
			else
				cloneBlank(lo)
			end
		end
	end

	-- ── Row 5: footer ──
	local backBtn = statsFrame:FindFirstChild("BackButton")
	if backBtn then
		backBtn.LayoutOrder = LAYOUT.backButtonOrder
	end
	local closeBtn = statsFrame:FindFirstChild("CloseSlot")
	if closeBtn then
		closeBtn.LayoutOrder = LAYOUT.closeSlotOrder
	end

	for i = 0, LAYOUT.footerBlanksBefore - 1 do
		cloneBlank(LAYOUT.footerRowStart + i)
	end

	for i = 1, LAYOUT.footerBlanksAfter do
		cloneBlank(LAYOUT.closeSlotOrder + i)
	end
end

-- ===================== CLOSE / RESET =====================
function M.close()
	hoveredStatKey = nil
	TooltipModule.hide()
end

function M.reset()
	hoveredStatKey = nil
	clearDynamicChildren()
	currentSkill = nil
	TooltipModule.forceHide()

	if selectedSkillFrame then
		selectedSkillFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		local bg = selectedSkillFrame:FindFirstChild("BG")
		if bg then
			bg.ImageColor3 = Color3.fromRGB(255, 255, 255)
			local bgStroke = bg:FindFirstChildOfClass("UIStroke")
			if bgStroke then
				bgStroke.Color = Color3.fromRGB(255, 255, 255)
			end
		end
		local icon = selectedSkillFrame:FindFirstChild("Icon")
		if icon then
			icon.Image = ""
		end
	end
end

-- ===================== GETTERS =====================
function M.getActiveSkill()
	return currentSkill
end

-- ===================== INIT =====================
function M.init(sharedRefs, menu2Frame)
	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule
	statsFrame = menu2Frame -- may be nil for pooled grids

	local CentralizedMenu = player.PlayerGui:WaitForChild("CentralizedAscensionMenu")
	local TemporaryMenus = CentralizedMenu:WaitForChild("TemporaryMenus")

	statSlotTemplate = TemporaryMenus:FindFirstChild("StatSlot")
	if not statSlotTemplate then
		warn("[StatisticsPageModule] StatSlot template NOT FOUND in TemporaryMenus")
	end

	blankSlotTemplate = TemporaryMenus:FindFirstChild("BlankSlot")
	if not blankSlotTemplate then
		warn("[StatisticsPageModule] BlankSlot template NOT FOUND in TemporaryMenus")
	end

	-- Frame-dependent setup (selectedSkillFrame, tooltip wiring)
	-- is now handled in openSkill() when the buffer frame is passed.
	-- StatisticsMenu1 button click wiring is handled by CMC callbacks
	-- via GridMenuModule — no longer needed here.

	if statsFrame then
		selectedSkillFrame = statsFrame:FindFirstChild("SelectedSkill")
	end

	-- Listen for StatisticsUpdated — process confirmed purchases, then refresh
	StatisticsUpdated.OnClientEvent:Connect(function(payload)
		-- Process pending purchases BEFORE updating cache
		-- Compare new payload counts against old cached counts
		local toRemove = {}
		print("[StatisticsPageModule] StatisticsUpdated received, pending count:", #pendingPurchases)
		for i, pending in ipairs(pendingPurchases) do
			local newSkillData = payload.skills and payload.skills[pending.skill]
			local newStatData = newSkillData and newSkillData[pending.statKey]
			local newCount = newStatData and newStatData.count or 0
			print(
				"[StatisticsPageModule] Checking pending:",
				pending.skill,
				pending.statKey,
				"old:",
				pending.oldCount,
				"new:",
				newCount
			)
			if newStatData and newStatData.count > pending.oldCount then
				-- Purchase confirmed — log the GAIN (positive)
				local config = statConfigLookup[pending.skill] and statConfigLookup[pending.skill][pending.statKey]
				if config then
					local gained = newStatData.count - pending.oldCount
					print("[StatisticsPageModule] CONFIRMED purchase:", config.name, "+", gained)
					StatisticLogModule.logStat(config.name, gained, config.color, newStatData.count)
				end

				-- Log each COST as a negative entry
				for _, costInfo in ipairs(pending.costs or {}) do
					local costConfig = statConfigLookup[costInfo.skill]
						and statConfigLookup[costInfo.skill][costInfo.id]
					if costConfig then
						local costStatData = payload.skills
							and payload.skills[costInfo.skill]
							and payload.skills[costInfo.skill][costInfo.id]
						local newOwned = costStatData and costStatData.count or 0
						StatisticLogModule.logStatNegative(costConfig.name, costInfo.amount, costConfig.color, newOwned)
					end
				end

				table.insert(toRemove, i)
			end
		end
		-- Remove confirmed entries (reverse to preserve indices)
		for j = #toRemove, 1, -1 do
			table.remove(pendingPurchases, toRemove[j])
		end

		-- Trim stale pending entries if queue grows too large (spam safety)
		if #pendingPurchases > 20 then
			local trimCount = math.floor(#pendingPurchases / 2)
			for _ = 1, trimCount do
				table.remove(pendingPurchases, 1)
			end
		end

		cachedData = payload
		refreshSlotCounts()
	end)

	-- Initialize the statistic log UI (StatisticLog is a separate ScreenGui)
	local statisticLog = player.PlayerGui:FindFirstChild("StatisticLog")
	if statisticLog then
		StatisticLogModule.init(statisticLog)
	else
		warn("[StatisticsPageModule] StatisticLog ScreenGui not found in PlayerGui")
	end

	-- ── Preload all stat icons ──
	local preloadList = {}
	for _, chain in pairs(STAT_CHAINS) do
		for _, item in ipairs(chain) do
			if item.icon and item.icon ~= "" then
				local img = Instance.new("ImageLabel")
				img.Image = item.icon
				table.insert(preloadList, img)
			end
		end
	end
	if #preloadList > 0 then
		task.spawn(function()
			ContentProvider:PreloadAsync(preloadList)
			for _, img in ipairs(preloadList) do
				img:Destroy()
			end
			print("[StatisticsPageModule] Preloaded " .. #preloadList .. " stat icons ✓")
		end)
	end

	print("[StatisticsPageModule] Initialized ✓")
end

return M
