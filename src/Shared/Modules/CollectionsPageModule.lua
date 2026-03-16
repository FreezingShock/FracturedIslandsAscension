--[[
	CollectionsPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Client-side rendering for the Collections drill-down:
	  CollectionsMenu2 → per-skill stat grid (clones StatSlot)
	  CollectionsMenu3 → 28 collection tiers for one stat (clones CollectionLevelSlot)

	Piggybacks on StatisticsUpdated RemoteEvent for lifetime data.
	Uses TooltipModule progress bar for tier progress display.

	API:
	  init(sharedRefs, menu2Frame, menu3Frame)
	  openSkill(skillName)
	  openStat(skillName, statKey)
	  closeMenu2()
	  closeMenu3()
	  close()
	  reset()
	  getActiveSkill()
	  getActiveStat()
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("CollectionsConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

local STAT_CHAINS = Config.STAT_CHAINS
local SKILL_COLORS = Config.SKILL_COLORS
local statConfigLookup = Config.statConfigLookup
local COLLECTION_TIERS = Config.COLLECTION_TIERS
local COLLECTION_REWARDS = Config.COLLECTION_REWARDS
local TIER_COLORS = Config.TIER_COLORS
local ROMAN_NUMERALS = Config.ROMAN_NUMERALS

local COLUMNS = Config.COLUMNS
local M2_LAYOUT = Config.MENU2_LAYOUT
local M2_STAT_ROWS = Config.MENU2_STAT_ROWS
local M2_STATS_PER_ROW = Config.MENU2_STATS_PER_ROW

local M3_LAYOUT = Config.MENU3_LAYOUT
local M3_TIER_ROWS = Config.MENU3_TIER_ROWS
local M3_TIERS_PER_ROW = Config.MENU3_TIERS_PER_ROW

local player = Players.LocalPlayer

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")

-- ===================== STATE =====================
local shared = nil
local TooltipModule = nil
local menu2Frame = nil -- CollectionsMenu2
local menu3Frame = nil -- CollectionsMenu3
local statSlotTemplate = nil
local collectionLevelSlotTemplate = nil
local blankSlotTemplate = nil
local selectedSkillFrame = nil -- SelectedSkill in Menu2
local selectedStatFrame = nil -- SelectedStatistic in Menu3 (cloned dynamically per openStat)

local currentSkill = nil
local currentStatKey = nil
local cachedData = nil

-- Dynamic children for cleanup
local menu2Dynamic = {}
local menu3Dynamic = {}
local menu2SlotRefs = {} -- statKey → { frame, countLabel }
local menu3SlotRefs = {} -- tierLevel → { frame, levelLabel }

local hoveredStatKey = nil -- Menu2 hover
local hoveredTierLevel = nil -- Menu3 hover

-- ===================== REMOTES =====================
local StatisticsUpdated = ReplicatedStorage:WaitForChild("StatisticsUpdated")

-- ===================== MODULE =====================
local M = {}

-- ===================== HELPERS =====================
local function formatNumber(n)
	if n == math.floor(n) then
		return MoneyLib.DealWithPoints(n)
	end
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

--- Returns the highest completed tier index (0 if none completed).
local function getHighestCompletedTier(lifetime)
	local highest = 0
	for i, tier in ipairs(COLLECTION_TIERS) do
		if lifetime >= tier.threshold then
			highest = i
		else
			break
		end
	end
	return highest
end

--- Returns the "collection level" for display (0 = none, 1-28 = completed tiers).
local function getCollectionLevel(lifetime)
	return getHighestCompletedTier(lifetime)
end

--- Returns the next tier the player is progressing toward (or nil if all complete).
local function getNextTier(lifetime)
	local highest = getHighestCompletedTier(lifetime)
	if highest < #COLLECTION_TIERS then
		return COLLECTION_TIERS[highest + 1]
	end
	return nil
end

--- Convert tier level to Roman numeral string.
local function toRoman(level)
	return ROMAN_NUMERALS[level] or tostring(level)
end

-- ===================== SLOT VISUALS =====================
--- Applies color + icon to a cloned StatSlot (same pattern as StatisticsPageModule).
local function applySlotVisuals(slot, item)
	local color = hexToColor3(item.color or "#FFFFFF")

	slot.BackgroundColor3 = color

	local bg = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
	end

	local icon = slot:FindFirstChild("Icon")
	if icon then
		icon.Image = (item.icon and item.icon ~= "") and item.icon or ""
	end
end

--- Applies tier status color to a CollectionLevelSlot.
--- colorHex → BackgroundColor3, BG.ImageColor3, BG.UIStroke.Color
local function applyTierColor(slot, colorHex)
	local color = hexToColor3(colorHex)

	slot.BackgroundColor3 = color

	local bg = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
	end
end

-- ===================== CLONE HELPERS =====================
local function cloneBlankTo(parent, layoutOrder, dynamicList)
	if not blankSlotTemplate then
		return nil
	end
	local blank = blankSlotTemplate:Clone()
	blank.LayoutOrder = layoutOrder
	blank.Visible = true
	blank.Parent = parent
	table.insert(dynamicList, blank)
	return blank
end

-- ===================== SELECTED SKILL VISUALS (Menu2) =====================
local function updateSelectedSkill(skillName)
	if not selectedSkillFrame then
		return
	end
	selectedSkillFrame.LayoutOrder = M2_LAYOUT.selectedSkillOrder

	local collectionsMenu1 = menu2Frame.Parent:FindFirstChild("CollectionsMenu1")
	if not collectionsMenu1 then
		return
	end

	local skillButton = collectionsMenu1:FindFirstChild(skillName .. "Collections")
	if not skillButton then
		return
	end

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

-- (SelectedStatistic is cloned dynamically in openStat — no static update function needed)

-- ===================== TOOLTIP: Menu2 stat slot =====================
local function buildMenu2Tooltip(skillName, statKey)
	local config = statConfigLookup[skillName] and statConfigLookup[skillName][statKey]
	if not config then
		return nil
	end

	local data = getStatData(skillName, statKey)
	local itemColor = config.color or (SKILL_COLORS[skillName] or "#FFFFFF")
	local lifetime = data.lifetime or 0
	local collLevel = getCollectionLevel(lifetime)

	local title = string.format(
		'<font color="%s"><b>%s</b></font> %s',
		itemColor,
		config.name,
		collLevel > 0 and toRoman(collLevel) or "0"
	)

	local lines = {}

	table.insert(
		lines,
		string.format(
			'<font color="#FFFFFF">Total Earned: <b>%s</b></font>  ' .. '<font color="#AAAAAA">(Session: %s)</font>',
			formatNumber(lifetime),
			formatNumber(data.session or 0)
		)
	)

	table.insert(
		lines,
		string.format('<font color="#55FF55">Multiplier: <b>×%s</b></font>', formatNumber(data.multiplier or 1))
	)

	table.insert(lines, "")
	table.insert(
		lines,
		string.format(
			'<font color="#AAAAAA">Collection Level: </font><font color="#FFFF55"><b>%s</b></font><font color="#AAAAAA"> (%d / %d)</font>',
			collLevel > 0 and toRoman(collLevel) or "0",
			collLevel,
			#COLLECTION_TIERS
		)
	)

	local desc = table.concat(lines, "\n")
	local click = '<font color="#FFFF55">Click to view collection!</font>'

	return { title = title, desc = desc, click = click }
end

--- Shows Menu2 tooltip with progress bar toward next tier.
local function showMenu2Tooltip(skillName, statKey)
	local tooltipData = buildMenu2Tooltip(skillName, statKey)
	if not tooltipData then
		return
	end

	local data = getStatData(skillName, statKey)
	local lifetime = data.lifetime or 0
	local nextTier = getNextTier(lifetime)
	local highestCompleted = getHighestCompletedTier(lifetime)

	TooltipModule.show(tooltipData)

	local refs = TooltipModule.refs
	if nextTier then
		local prevThreshold = highestCompleted > 0 and COLLECTION_TIERS[highestCompleted].threshold or 0
		local range = nextTier.threshold - prevThreshold
		local progress = math.clamp((lifetime - prevThreshold) / range, 0, 1)
		local pctDisplay = math.floor(progress * 100)

		refs.ProgressLabel.Text = string.format(
			'<font color="#AAAAAA">Progress: </font><font color="#FFFF55">%d</font><font color="#FFAA00">%%</font>',
			pctDisplay
		)
		refs.ProgressLabel.Visible = true
		refs.ProgressBL.Text = string.format(
			'<font color="#FFFF55">%s</font><font color="#FFAA00">/</font><font color="#FFFF55">%s</font>',
			formatNumber(lifetime),
			formatNumber(nextTier.threshold)
		)
		refs.ProgressBL.Visible = true
		refs.ProgressOuter.Visible = true
		TooltipModule.tweenProgressFill(progress)
		refs.Divider3.Visible = true
	else
		refs.ProgressLabel.Text = '<font color="#55FF55">All collection tiers completed!</font>'
		refs.ProgressLabel.Visible = true
		refs.ProgressBL.Text = ""
		refs.ProgressBL.Visible = false
		refs.ProgressOuter.Visible = true
		TooltipModule.tweenProgressFill(1)
		refs.Divider3.Visible = true
	end
end

-- ===================== TOOLTIP: Menu3 tier slot =====================
local function showMenu3TierTooltip(skillName, statKey, tierIndex)
	local tier = COLLECTION_TIERS[tierIndex]
	if not tier then
		return
	end

	local config = statConfigLookup[skillName] and statConfigLookup[skillName][statKey]
	local data = getStatData(skillName, statKey)
	local lifetime = data.lifetime or 0

	local highestCompleted = getHighestCompletedTier(lifetime)
	local statusColor
	local statusText
	if tierIndex <= highestCompleted then
		statusColor = TIER_COLORS.completed
		statusText = "Completed"
	elseif tierIndex == highestCompleted + 1 then
		statusColor = TIER_COLORS.inProgress
		statusText = "In Progress"
	else
		statusColor = TIER_COLORS.locked
		statusText = "Locked"
	end

	local statName = config and config.name or statKey
	local statColor = config and config.color or "#FFFFFF"

	local title = string.format('<font color="%s"><b>Collection %s</b></font>', statusColor, toRoman(tier.level))

	local lines = {}

	table.insert(
		lines,
		string.format('<font color="#AAAAAA">Status: </font><font color="%s"><b>%s</b></font>', statusColor, statusText)
	)
	table.insert(lines, "")
	table.insert(
		lines,
		string.format(
			'<font color="#AAAAAA">Requirement: </font><font color="#%s"><b>%s</b> %s</font>',
			statColor,
			formatNumber(tier.threshold),
			statName
		)
	)
	local desc = table.concat(lines, "\n")

	-- Build rewards text for RewardsLabel
	local rewardLines = {}
	local rewards = COLLECTION_REWARDS[tier.level]
	if rewards and #rewards > 0 then
		table.insert(rewardLines, '<font color="#AAAAAA">Rewards:</font>')
		for _, reward in ipairs(rewards) do
			if reward.type == "stat" then
				local rConfig = statConfigLookup[reward.skill] and statConfigLookup[reward.skill][reward.target]
				local rName = rConfig and rConfig.name or reward.target
				local rColor = rConfig and rConfig.color or "#FFFFFF"
				table.insert(
					rewardLines,
					string.format(
						'  <font color="#55FF55">+%d%%</font> <font color="%s">%s</font>',
						reward.pct,
						rColor,
						rName
					)
				)
			elseif reward.type == "gameStat" then
				table.insert(
					rewardLines,
					string.format('  <font color="#FF55FF">+%s %s</font>', tostring(reward.flat), reward.target)
				)
			end
		end
	else
		table.insert(rewardLines, '<font color="#555555">Rewards: Coming Soon</font>')
	end

	-- Show tooltip (no click label for tier slots)
	TooltipModule.show({ title = title, desc = desc, click = "" })

	-- Set RewardsLabel + Divider2
	local refs = TooltipModule.refs
	refs.Rewards.Text = table.concat(rewardLines, "\n")
	refs.Rewards.Visible = true
	refs.Divider2.Visible = true

	-- Progress bar for THIS specific tier
	local progress = math.clamp(lifetime / tier.threshold, 0, 1)
	local pctDisplay = math.floor(progress * 100)

	refs.ProgressLabel.Text = string.format(
		'<font color="#AAAAAA">Progress: </font><font color="#FFFF55">%d</font><font color="#FFAA00">%%</font>',
		pctDisplay
	)
	refs.ProgressLabel.Visible = true
	refs.ProgressBL.Text = string.format(
		'<font color="#FFFF55">%s</font><font color="#FFAA00">/</font><font color="#FFFF55">%s</font>',
		formatNumber(lifetime),
		formatNumber(tier.threshold)
	)
	refs.ProgressBL.Visible = true
	refs.ProgressOuter.Visible = true
	TooltipModule.tweenProgressFill(progress)
	refs.Divider3.Visible = false
end

-- ===================== TOOLTIP: SelectedStatistic (Menu3 header) =====================
--- Shows stat info without progress bar or click label.
local function showSelectedStatTooltip(skillName, statKey)
	local config = statConfigLookup[skillName] and statConfigLookup[skillName][statKey]
	if not config then
		return
	end

	local data = getStatData(skillName, statKey)
	local itemColor = config.color or (SKILL_COLORS[skillName] or "#FFFFFF")
	local lifetime = data.lifetime or 0

	local title = string.format('<font color="%s"><b>%s</b></font>', itemColor, config.name)

	local lines = {}

	table.insert(lines, string.format('<font color="#FFFFFF">Total Earned: <b>%s</b></font>', formatNumber(lifetime)))
	table.insert(
		lines,
		string.format('<font color="#AAAAAA">Session: <b>%s</b></font>', formatNumber(data.session or 0))
	)
	table.insert(
		lines,
		string.format('<font color="#55FF55">Multiplier: <b>×%s</b></font>', formatNumber(data.multiplier or 1))
	)

	local collLevel = getCollectionLevel(lifetime)
	table.insert(lines, "")
	table.insert(
		lines,
		string.format(
			'<font color="#AAAAAA">Collection Level: </font><font color="#FFFF55"><b>%s</b></font><font color="#AAAAAA"> (%d / %d)</font>',
			collLevel > 0 and toRoman(collLevel) or "0",
			collLevel,
			#COLLECTION_TIERS
		)
	)

	local desc = table.concat(lines, "\n")

	-- No click label, no progress bar
	TooltipModule.show({ title = title, desc = desc, click = "" })
end

-- ===================== CLEANUP =====================
local function clearMenu2Dynamic()
	for _, child in ipairs(menu2Dynamic) do
		if child and child.Parent then
			child:Destroy()
		end
	end
	menu2Dynamic = {}
	menu2SlotRefs = {}
end

local function clearMenu3Dynamic()
	for _, child in ipairs(menu3Dynamic) do
		if child and child.Parent then
			child:Destroy()
		end
	end
	menu3Dynamic = {}
	menu3SlotRefs = {}
end

-- ===================== REFRESH (silent live update) =====================
local function refreshMenu2Counts()
	if not currentSkill then
		return
	end
	for statKey, ref in pairs(menu2SlotRefs) do
		if ref.countLabel then
			local data = getStatData(currentSkill, statKey)
			local collLevel = getCollectionLevel(data.lifetime or 0)
			ref.countLabel.Text = collLevel > 0 and toRoman(collLevel) or "0"
		end
	end

	-- Live-refresh tooltip if hovering
	if hoveredStatKey and menu2SlotRefs[hoveredStatKey] then
		showMenu2Tooltip(currentSkill, hoveredStatKey)
	end
end

local function refreshMenu3Tiers()
	if not currentSkill or not currentStatKey then
		return
	end
	local data = getStatData(currentSkill, currentStatKey)
	local lifetime = data.lifetime or 0
	local highestCompleted = getHighestCompletedTier(lifetime)

	for tierLevel, ref in pairs(menu3SlotRefs) do
		local colorHex
		if tierLevel <= highestCompleted then
			colorHex = TIER_COLORS.completed
		elseif tierLevel == highestCompleted + 1 then
			colorHex = TIER_COLORS.inProgress
		else
			colorHex = TIER_COLORS.locked
		end
		applyTierColor(ref.frame, colorHex)
	end

	-- Live-refresh tooltip if hovering
	if hoveredTierLevel and menu3SlotRefs[hoveredTierLevel] then
		showMenu3TierTooltip(currentSkill, currentStatKey, hoveredTierLevel)
	end
end

-- ===================== OPEN SKILL (Menu2) =====================
function M.openSkill(skillName)
	clearMenu2Dynamic()
	currentSkill = skillName
	currentStatKey = nil

	local chain = STAT_CHAINS[skillName]
	if not chain then
		warn("[CollectionsPageModule] No chain defined for " .. tostring(skillName))
		return
	end

	-- ── Update SelectedSkill visuals ──
	updateSelectedSkill(skillName)

	-- ── Row 0: header blanks ──
	for i = 0, M2_LAYOUT.headerBlanksBefore - 1 do
		cloneBlankTo(menu2Frame, i, menu2Dynamic)
	end
	for i = 1, M2_LAYOUT.headerBlanksAfter do
		cloneBlankTo(menu2Frame, M2_LAYOUT.selectedSkillOrder + i, menu2Dynamic)
	end

	-- ── Rows 1-4: stat slots ──
	local statIndex = 1
	for row = 0, M2_STAT_ROWS - 1 do
		local rowBase = M2_LAYOUT.statRowBaseOrder + (row * COLUMNS)

		-- Left pad blanks
		for pad = 0, M2_LAYOUT.statRowPadCount - 1 do
			cloneBlankTo(menu2Frame, rowBase + pad, menu2Dynamic)
		end

		-- Stat slots or blank fills
		for col = M2_LAYOUT.statRowPadCount, M2_LAYOUT.statRowPadCount + M2_STATS_PER_ROW - 1 do
			local lo = rowBase + col
			if statIndex <= #chain then
				local item = chain[statIndex]

				local slot = statSlotTemplate:Clone()
				slot.Name = "Coll_" .. item.key
				slot.LayoutOrder = lo
				slot.Visible = true
				slot.Parent = menu2Frame

				applySlotVisuals(slot, item)

				-- Show collection level as Roman numeral
				local countLabel = slot:FindFirstChild("ItemCount")
				if countLabel then
					local data = getStatData(skillName, item.key)
					local collLevel = getCollectionLevel(data.lifetime or 0)
					countLabel.Text = collLevel > 0 and toRoman(collLevel) or "0"
				end

				menu2SlotRefs[item.key] = {
					frame = slot,
					countLabel = countLabel,
				}

				-- Hover tooltip
				local capturedKey = item.key
				slot.MouseEnter:Connect(function()
					hoveredStatKey = capturedKey
					UIClick3:Play()
					showMenu2Tooltip(skillName, capturedKey)
				end)
				slot.MouseLeave:Connect(function()
					if hoveredStatKey == capturedKey then
						hoveredStatKey = nil
					end
					TooltipModule.hide()
				end)

				-- Click → open Menu3 for this stat
				slot.MouseButton1Click:Connect(function()
					UIClick:Play()
					M.openStat(skillName, capturedKey)
				end)

				table.insert(menu2Dynamic, slot)
				statIndex = statIndex + 1
			else
				cloneBlankTo(menu2Frame, lo, menu2Dynamic)
			end
		end
	end

	-- ── Row 5: footer ──
	local backBtn = menu2Frame:FindFirstChild("BackButton")
	if backBtn then
		backBtn.LayoutOrder = M2_LAYOUT.backButtonOrder
	end
	local closeBtn = menu2Frame:FindFirstChild("CloseSlot")
	if closeBtn then
		closeBtn.LayoutOrder = M2_LAYOUT.closeSlotOrder
	end

	for i = 0, M2_LAYOUT.footerBlanksBefore - 1 do
		cloneBlankTo(menu2Frame, M2_LAYOUT.footerRowStart + i, menu2Dynamic)
	end
	for i = 1, M2_LAYOUT.footerBlanksAfter do
		cloneBlankTo(menu2Frame, M2_LAYOUT.closeSlotOrder + i, menu2Dynamic)
	end
end

-- ===================== OPEN STAT (Menu3) =====================
function M.openStat(skillName, statKey)
	clearMenu3Dynamic()
	currentStatKey = statKey

	local config = statConfigLookup[skillName] and statConfigLookup[skillName][statKey]
	if not config then
		warn("[CollectionsPageModule] No config for " .. tostring(skillName) .. "." .. tostring(statKey))
		return
	end

	-- Navigate grid
	local GridMenuModule = shared.GridMenuModule
	if GridMenuModule then
		GridMenuModule.navigateToGrid("CollectionsMenu3")
		shared.typewriteTitle(config.name .. " Collection")
	end

	-- ── Update SelectedStatistic (clone from StatSlot) ──
	if statSlotTemplate then
		selectedStatFrame = statSlotTemplate:Clone()
		selectedStatFrame.Name = "SelectedStatistic"
		selectedStatFrame.LayoutOrder = M3_LAYOUT.selectedStatOrder
		selectedStatFrame.Visible = true
		selectedStatFrame.Parent = menu3Frame
		table.insert(menu3Dynamic, selectedStatFrame)

		-- Apply stat color + icon
		local color = hexToColor3(config.color or "#FFFFFF")
		selectedStatFrame.BackgroundColor3 = color
		local bg = selectedStatFrame:FindFirstChild("BG")
		if bg then
			bg.ImageColor3 = color
			local stroke = bg:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = color
			end
		end
		local icon = selectedStatFrame:FindFirstChild("Icon")
		if icon then
			icon.Image = (config.icon and config.icon ~= "") and config.icon or ""
		end

		-- Tooltip (same as Menu2 stat tooltip, no click label)
		selectedStatFrame.MouseEnter:Connect(function()
			if currentSkill and currentStatKey then
				showSelectedStatTooltip(currentSkill, currentStatKey)
			end
		end)
		selectedStatFrame.MouseLeave:Connect(function()
			TooltipModule.hide()
		end)
	end

	-- ── Row 0: header blanks (group-style: all at same LO) ──
	for _ = 1, M3_LAYOUT.headerBlanksBeforeCount do
		cloneBlankTo(menu3Frame, M3_LAYOUT.headerBlanksBeforeOrder, menu3Dynamic)
	end
	for _ = 1, M3_LAYOUT.headerBlanksAfterCount do
		cloneBlankTo(menu3Frame, M3_LAYOUT.headerBlanksAfterOrder, menu3Dynamic)
	end

	-- ── Rows 1-4: tier slots (28 tiers = 4 rows × 7) ──
	local data = getStatData(skillName, statKey)
	local lifetime = data.lifetime or 0
	local highestCompleted = getHighestCompletedTier(lifetime)

	local tierIndex = 1
	for row = 0, M3_TIER_ROWS - 1 do
		local rowBase = M3_LAYOUT.tierRowBaseOrder + (row * COLUMNS)

		-- Left pad blanks
		for pad = 0, M3_LAYOUT.tierRowPadCount - 1 do
			cloneBlankTo(menu3Frame, rowBase + pad, menu3Dynamic)
		end

		-- Tier slots
		for col = M3_LAYOUT.tierRowPadCount, M3_LAYOUT.tierRowPadCount + M3_TIERS_PER_ROW - 1 do
			local lo = rowBase + col
			if tierIndex <= #COLLECTION_TIERS then
				local tier = COLLECTION_TIERS[tierIndex]

				local slot = collectionLevelSlotTemplate:Clone()
				slot.Name = "Tier_" .. tier.level
				slot.LayoutOrder = lo
				slot.Visible = true
				slot.Parent = menu3Frame

				-- Apply icon from stat config
				local icon = slot:FindFirstChild("Icon")
				if icon then
					icon.Image = (config.icon and config.icon ~= "") and config.icon or ""
				end

				-- Set level label (LevelLabel is inside BG)
				local bg = slot:FindFirstChild("BG")
				local levelLabel = bg and bg:FindFirstChild("LevelLabel")
				if levelLabel then
					levelLabel.Text = toRoman(tier.level)
				end

				-- Apply tier status color
				local colorHex
				if tierIndex <= highestCompleted then
					colorHex = TIER_COLORS.completed
				elseif tierIndex == highestCompleted + 1 then
					colorHex = TIER_COLORS.inProgress
				else
					colorHex = TIER_COLORS.locked
				end
				applyTierColor(slot, colorHex)

				-- Count label shows threshold formatted via MoneyLib
				local countLabel = slot:FindFirstChild("ItemCount")
				if countLabel then
					countLabel.Text = formatNumber(tier.threshold)
				end

				menu3SlotRefs[tierIndex] = {
					frame = slot,
					levelLabel = levelLabel,
				}

				-- Hover tooltip
				local capturedTier = tierIndex
				slot.MouseEnter:Connect(function()
					hoveredTierLevel = capturedTier
					UIClick3:Play()
					showMenu3TierTooltip(skillName, statKey, capturedTier)
				end)
				slot.MouseLeave:Connect(function()
					if hoveredTierLevel == capturedTier then
						hoveredTierLevel = nil
					end
					TooltipModule.hide()
				end)

				table.insert(menu3Dynamic, slot)
				tierIndex = tierIndex + 1
			else
				cloneBlankTo(menu3Frame, lo, menu3Dynamic)
			end
		end
	end

	-- ── Row 5: footer ──
	local backBtn = menu3Frame:FindFirstChild("BackButton")
	if backBtn then
		backBtn.LayoutOrder = M3_LAYOUT.backButtonOrder
	end
	local closeBtn = menu3Frame:FindFirstChild("CloseSlot")
	if closeBtn then
		closeBtn.LayoutOrder = M3_LAYOUT.closeSlotOrder
	end

	for i = 0, M3_LAYOUT.footerBlanksBefore - 1 do
		cloneBlankTo(menu3Frame, M3_LAYOUT.footerRowStart + i, menu3Dynamic)
	end
	for i = 1, M3_LAYOUT.footerBlanksAfter do
		cloneBlankTo(menu3Frame, M3_LAYOUT.closeSlotOrder + i, menu3Dynamic)
	end
end

-- ===================== CLOSE =====================
function M.closeMenu2()
	hoveredStatKey = nil
	TooltipModule.hide()
end

function M.closeMenu3()
	hoveredTierLevel = nil
	clearMenu3Dynamic()
	selectedStatFrame = nil
	currentStatKey = nil
	TooltipModule.hide()
end

function M.close()
	hoveredStatKey = nil
	hoveredTierLevel = nil
	TooltipModule.hide()
end

function M.reset()
	hoveredStatKey = nil
	hoveredTierLevel = nil
	clearMenu2Dynamic()
	clearMenu3Dynamic()
	currentSkill = nil
	currentStatKey = nil
	TooltipModule.forceHide()

	-- Reset SelectedSkill visuals
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

	-- selectedStatFrame is a dynamic child — cleared by clearMenu3Dynamic() above
	selectedStatFrame = nil
end

-- ===================== GETTERS =====================
function M.getActiveSkill()
	return currentSkill
end

function M.getActiveStat()
	return currentStatKey
end

-- ===================== INIT =====================
function M.init(sharedRefs, m2Frame, m3Frame)
	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule
	menu2Frame = m2Frame
	menu3Frame = m3Frame

	local CentralizedMenu = player.PlayerGui:WaitForChild("CentralizedAscensionMenu")
	local TemporaryMenus = CentralizedMenu:WaitForChild("TemporaryMenus")

	statSlotTemplate = TemporaryMenus:FindFirstChild("StatSlot")
	if not statSlotTemplate then
		warn("[CollectionsPageModule] StatSlot template NOT FOUND in TemporaryMenus")
	end

	collectionLevelSlotTemplate = TemporaryMenus:FindFirstChild("CollectionLevelSlot")
	if not collectionLevelSlotTemplate then
		warn("[CollectionsPageModule] CollectionLevelSlot template NOT FOUND in TemporaryMenus")
	end

	blankSlotTemplate = TemporaryMenus:FindFirstChild("BlankSlot")
	if not blankSlotTemplate then
		warn("[CollectionsPageModule] BlankSlot template NOT FOUND in TemporaryMenus")
	end

	selectedSkillFrame = menu2Frame:FindFirstChild("SelectedSkill")
	-- selectedStatFrame is cloned dynamically in openStat(), not pre-built

	-- ── Tooltip on SelectedSkill (Menu2 header) ──
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

	-- ── Listen for StatisticsUpdated — refresh live data ──
	StatisticsUpdated.OnClientEvent:Connect(function(payload)
		cachedData = payload
		refreshMenu2Counts()
		refreshMenu3Tiers()
	end)

	-- ── Preload stat icons ──
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
			print("[CollectionsPageModule] Preloaded " .. #preloadList .. " stat icons ✓")
		end)
	end

	print("[CollectionsPageModule] Initialized ✓")
end

return M
