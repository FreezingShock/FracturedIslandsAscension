--[[
	CollectionsPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Client-side rendering of the Collections drill-down. Every grid is a pooled grid (GridMenuModule): the engine clones the
	template into a buffer on every navigation (also when going BACK) and runs the grid's onPopulate hook, so each page is
	built from `state` and survives Back. The handlers die with their slots (Destroy disconnects them): nothing to clean.

	  CollectionsGrid   hub: one button per skill (CentralizedMenuController -> openSkill)
	  CollectionsMenu2  the statistics of one skill        (StatSlot / CollectionStatSlot)
	  CollectionsMenu3  the 28 tiers of one statistic      (CollectionLevelSlot)
	  CollectionsMenu4  one tier: the tier numeral and its rewards on one row   (TierTitle / RewardSlot)

	All grids are 9 x 6 cells placed by cell index (Config.LAYOUT); blanks fill every unused cell. Tier maths is CollectionMath,
	rewards come from CollectionsConfig.getRewards and are shown through CollectionRewards.describe, so a new reward type
	needs no change here. The server (CollectionService) grants the rewards; this module only displays them.

	API:
	  init(sharedRefs)
	  openSkill(skill) / openStat(statKey) / openTier(tier)     navigate one level down
	  back()                                                    the ONE back handler of Menu2, Menu3 and Menu4
	  populateSkill(frame) / populateStat(frame) / populateTier(frame)   pooled-grid onPopulate hooks
	  showSkillTooltip(skill, anchor) / hideSkillTooltip()      hub tooltip (tiers completed)
	  reset() / close()                                         menu closed
	  getActiveSkill() / getActiveStat() / getActiveTier()
--]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("CollectionsConfig")) :: any
local CollectionMath = require(Modules:WaitForChild("CollectionMath")) :: any
local CollectionRewards = require(Modules:WaitForChild("CollectionRewards")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any
local StatisticLogModule = require(Modules:WaitForChild("StatisticLogModule")) :: any

local STAT_CHAINS = Config.STAT_CHAINS
local SKILL_COLORS = Config.SKILL_COLORS
local statConfigLookup = Config.statConfigLookup
local TIER_COLORS = Config.TIER_COLORS
local ROMAN = Config.ROMAN_NUMERALS
local TIER_COUNT = Config.TIER_COUNT
local LAYOUT = Config.LAYOUT

local TOOLTIP_SOURCE = "collections"
local TOAST_SECONDS = 4

local player = Players.LocalPlayer
local UISounds = workspace:WaitForChild("UISounds")
local UIClick = UISounds:WaitForChild("Click")
local UIClick3 = UISounds:WaitForChild("Click3")

local StatisticsUpdated = ReplicatedStorage:WaitForChild("StatisticsUpdated")
local TierUnlocked = ReplicatedStorage:WaitForChild("CollectionTierUnlocked")

local sharedRefs: any = nil
local TooltipModule: any = nil
local templates: { [string]: Instance? } = {}
local cachedData: any = nil

-- What the pages show. Survives Back because every page is rebuilt from it.
local state = { skill = nil :: string?, statKey = nil :: string?, tier = nil :: number? }
-- Live slots of the page on screen, for in-place refreshes: [key] = { slot, ... }
local views = { stats = {}, tiers = {}, rewards = {} } :: { [string]: { [any]: any } }
local hovered = { stat = nil :: string?, tier = nil :: number? }

local M = {}

-- ===================== HELPERS =====================
local function formatNumber(n: number): string
	if n == math.floor(n) or n >= 1000 then
		return MoneyLib.DealWithPoints(math.floor(n))
	end
	return string.format("%.2f", n)
end

local function hexToColor3(hex: string): Color3
	hex = hex:gsub("#", "")
	return Color3.fromRGB(
		tonumber(hex:sub(1, 2), 16) or 255,
		tonumber(hex:sub(3, 4), 16) or 255,
		tonumber(hex:sub(5, 6), 16) or 255
	)
end

local function roman(tier: number): string
	return tier > 0 and ROMAN[tier] or "0"
end

local function getStatData(skill: string, statKey: string)
	local skillData = cachedData and cachedData.skills and cachedData.skills[skill]
	return skillData and skillData[statKey] or { count = 0, lifetime = 0, session = 0, multiplier = 1 }
end

local function statConfig(skill: string?, statKey: string?)
	return skill and statKey and statConfigLookup[skill] and statConfigLookup[skill][statKey]
end

local function alive(slot: Instance?): boolean
	return slot ~= nil and slot.Parent ~= nil
end

--- StatSlot / CollectionLevelSlot / RewardSlot colouring: Background, BG image + stroke, Icon.
local function paint(slot: any, colorHex: string, icon: string?)
	local color = hexToColor3(colorHex)
	slot.BackgroundColor3 = color
	local bg: any = slot:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		local stroke = bg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
		end
	end
	if icon ~= nil then
		local image: any = slot:FindFirstChild("Icon")
		if image then
			image.Image = icon
		end
	end
end

--- The text label of a slot: Amount (reward), LevelLabel (inside BG) or ItemCount.
local function setLabel(slot: Instance, text: string)
	local label = slot:FindFirstChild("Amount", true)
		or slot:FindFirstChild("LevelLabel", true)
		or slot:FindFirstChild("ItemCount", true)
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function bind(slot: Instance, onEnter: (() -> ())?, onLeave: (() -> ())?, onClick: (() -> ())?)
	local button = slot :: any
	if onEnter then
		button.MouseEnter:Connect(onEnter)
	end
	if onLeave then
		button.MouseLeave:Connect(onLeave)
	end
	if onClick then
		button.MouseButton1Click:Connect(onClick)
	end
end

local function hideTip()
	if TooltipModule then
		TooltipModule.hide(TOOLTIP_SOURCE)
	end
end

local function showTip(config: any, anchor: Instance)
	TooltipModule.show(config, TOOLTIP_SOURCE, anchor)
end

-- ===================== GRID BUILDING =====================
local function cell(row: number, col: number): number
	return row * LAYOUT.columns + col
end

local function cloneTemplate(name: string, fallback: string?): any
	local template = templates[name] or (fallback and templates[fallback])
	return template and template:Clone() or nil
end

local function place(frame: Instance, occupied: { [number]: Instance }, index: number, slot: any)
	slot.LayoutOrder = index
	slot.Visible = true
	slot.Parent = frame
	occupied[index] = slot
end

--- Adds the footer buttons that come from the grid template, then fills every free cell with a BlankSlot.
local function finishGrid(frame: Instance, occupied: { [number]: Instance })
	local back: any = frame:FindFirstChild("BackButton")
	if back then
		back.LayoutOrder = cell(LAYOUT.footerRow, LAYOUT.backCol)
		occupied[cell(LAYOUT.footerRow, LAYOUT.backCol)] = back
	end
	local close: any = frame:FindFirstChild("CloseSlot")
	if close then
		close.LayoutOrder = cell(LAYOUT.footerRow, LAYOUT.closeCol)
		occupied[cell(LAYOUT.footerRow, LAYOUT.closeCol)] = close
	end
	local blank = templates.blank
	if not blank then
		return
	end
	for index = 0, LAYOUT.columns * LAYOUT.rows - 1 do
		if not occupied[index] then
			local clone = blank:Clone() :: any
			clone.LayoutOrder = index
			clone.Visible = true
			clone.Parent = frame
		end
	end
end

--- Row/column of the n-th content slot (7 per row, rows 1-4).
local function contentCell(n: number): number
	local per = LAYOUT.contentPerRow
	return cell(LAYOUT.contentRows[1] + (n - 1) // per, LAYOUT.contentFirstCol + (n - 1) % per)
end

-- ===================== TOOLTIPS =====================
local function rewardLine(reward: any, skill: string, statKey: string, tier: number): string
	return CollectionRewards.describe(reward, { skill = skill, key = statKey, tier = tier }).text
end

local function nextRewardText(skill: string, statKey: string, lifetime: number): string?
	local nextTier = CollectionMath.nextTier(lifetime)
	if not nextTier then
		return nil
	end
	local lines = {}
	for _, reward in ipairs(Config.getRewards(skill, statKey, nextTier.level)) do
		table.insert(lines, rewardLine(reward, skill, statKey, nextTier.level))
	end
	if #lines == 0 then
		return nil
	end
	return string.format(
		'<font color="#AAAAAA">Next reward (%s): </font>%s',
		roman(nextTier.level),
		table.concat(lines, '<font color="#AAAAAA">, </font>')
	)
end

local function progressLabel(lifetime: number, target: number, pct: number, color: string): any
	return {
		pct = pct,
		color = color,
		label = string.format(
			'<font color="#FFFF55">%s</font><font color="#FFAA00">/</font><font color="#FFFF55">%s</font> <font color="#AAAAAA">(%d%%)</font>',
			formatNumber(lifetime),
			formatNumber(target),
			math.floor(pct * 100)
		),
	}
end

local function statTooltip(skill: string, statKey: string, withClick: boolean): any?
	local config = statConfig(skill, statKey)
	if not config then
		return nil
	end
	local data = getStatData(skill, statKey)
	local lifetime = data.lifetime or 0
	local level = CollectionMath.highestTier(lifetime)
	local color = config.color or SKILL_COLORS[skill] or "#FFFFFF"

	local lines = {
		string.format(
			'<font color="#FFFFFF">Total Earned: <b>%s</b></font>  <font color="#AAAAAA">(Session: %s)</font>',
			formatNumber(lifetime),
			formatNumber(data.session or 0)
		),
		string.format('<font color="#55FF55">Multiplier: <b>x%s</b></font>', formatNumber(data.multiplier or 1)),
		"",
		string.format(
			'<font color="#AAAAAA">Collection Level: </font><font color="#FFFF55"><b>%s</b></font><font color="#AAAAAA"> (%d / %d)</font>',
			roman(level),
			level,
			TIER_COUNT
		),
	}
	local nextText = nextRewardText(skill, statKey, lifetime)
	if nextText then
		table.insert(lines, nextText)
	end

	local tooltip: any = {
		title = string.format('<font color="%s"><b>%s</b></font> %s', color, config.name, roman(level)),
		description = table.concat(lines, "\n"),
		click = withClick and '<font color="#FFFF55">Click to view collection!</font>' or "",
	}
	local nextTier = CollectionMath.nextTier(lifetime)
	if nextTier and withClick then
		tooltip.progress = progressLabel(lifetime, nextTier.threshold, CollectionMath.progress(lifetime), "#FFFF55")
	elseif withClick then
		tooltip.progress = { pct = 1, color = "#55FF55", label = '<font color="#55FF55">All tiers completed!</font>' }
	end
	return tooltip
end

local function tierTooltip(skill: string, statKey: string, tier: number): any
	local config = statConfig(skill, statKey)
	local lifetime = getStatData(skill, statKey).lifetime or 0
	local status = CollectionMath.status(tier, CollectionMath.highestTier(lifetime))
	local statusColor = TIER_COLORS[status]
	local statusText = ({ completed = "Completed", inProgress = "In Progress", locked = "Locked" })[status]
	local threshold = Config.threshold(tier)

	local rewardLines = {}
	for _, reward in ipairs(Config.getRewards(skill, statKey, tier)) do
		table.insert(rewardLines, rewardLine(reward, skill, statKey, tier))
	end
	if #rewardLines == 0 then
		table.insert(rewardLines, '<font color="#AAAAAA">No rewards</font>')
	end

	local progress = math.clamp(lifetime / threshold, 0, 1)
	return {
		title = string.format('<font color="%s"><b>Collection %s</b></font>', statusColor, roman(tier)),
		description = table.concat({
			string.format(
				'<font color="#AAAAAA">Status: </font><font color="%s"><b>%s</b></font>',
				statusColor,
				statusText
			),
			"",
			string.format(
				'<font color="#AAAAAA">Requirement: </font><font color="%s"><b>%s</b> %s</font>',
				config and config.color or "#FFFFFF",
				formatNumber(threshold),
				config and config.name or statKey
			),
		}, "\n"),
		click = '<font color="#FFFF55">Click to view rewards!</font>',
		progress = progressLabel(lifetime, threshold, progress, statusColor),
		blocks = { { title = "Rewards", text = table.concat(rewardLines, "\n") } },
	}
end

--- Hub tooltip: tiers completed over every statistic of the skill.
local function skillTotals(skill: string): (number, number)
	local done, total = 0, 0
	for _, item in ipairs(STAT_CHAINS[skill] or {}) do
		done += CollectionMath.highestTier(getStatData(skill, item.key).lifetime or 0)
		total += TIER_COUNT
	end
	return done, total
end

function M.showSkillTooltip(skill: string, anchor: Instance)
	if not TooltipModule then
		return
	end
	UIClick3:Play()
	local done, total = skillTotals(skill)
	local pct = total > 0 and done / total or 0
	local color = SKILL_COLORS[skill] or "#FFFFFF"
	showTip({
		title = string.format(
			'<font color="%s"><b>%s</b></font><font color="#55FF55"> Collections</font>',
			color,
			skill
		),
		description = string.format(
			'<font color="#AAAAAA">Tiers completed: </font><font color="#FFFF55"><b>%d</b></font><font color="#AAAAAA"> / %d</font>',
			done,
			total
		),
		click = '<font color="#FFFF55">Click to view!</font>',
		progress = {
			pct = pct,
			color = "#55FF55",
			label = string.format(
				'<font color="#55FF55">%d%%</font> <font color="#AAAAAA">complete</font>',
				math.floor(pct * 100)
			),
		},
	}, anchor)
end

function M.hideSkillTooltip()
	hideTip()
end

-- ===================== MENU 2: statistics of a skill =====================
function M.populateSkill(frame: Instance)
	table.clear(views.stats)
	hovered.stat = nil
	local skill = state.skill
	local chain = skill and STAT_CHAINS[skill]
	local occupied: { [number]: Instance } = {}
	if not chain then
		warn("[CollectionsPageModule] no skill selected for CollectionsMenu2")
		finishGrid(frame, occupied)
		return
	end

	-- header: the skill
	local header = cloneTemplate("statSlot")
	if header then
		paint(header, SKILL_COLORS[skill] or "#FFFFFF", "")
		place(frame, occupied, cell(0, LAYOUT.headerCol), header)
		bind(header, function()
			local done, total = skillTotals(skill)
			showTip({
				title = string.format('<font color="%s"><b>%s</b></font>', SKILL_COLORS[skill] or "#FFFFFF", skill),
				description = string.format(
					'<font color="#AAAAAA">Tiers completed: </font><font color="#FFFF55">%d / %d</font>',
					done,
					total
				),
				click = "",
			}, header)
		end, hideTip)
	end

	for n, item in ipairs(chain) do
		if n > LAYOUT.contentPerRow * (LAYOUT.contentRows[2] - LAYOUT.contentRows[1] + 1) then
			warn("[CollectionsPageModule] " .. skill .. " has more statistics than the grid holds")
			break
		end
		local slot = cloneTemplate("collectionStatSlot", "statSlot")
		if slot then
			slot.Name = "Coll_" .. item.key
			paint(slot, item.color or "#FFFFFF", item.icon or "")
			local level = CollectionMath.highestTier(getStatData(skill, item.key).lifetime or 0)
			setLabel(slot, roman(level))
			place(frame, occupied, contentCell(n), slot)
			views.stats[item.key] = { slot = slot, level = level }
			local key = item.key
			bind(slot, function()
				hovered.stat = key
				UIClick3:Play()
				local tip = statTooltip(skill, key, true)
				if tip then
					showTip(tip, slot)
				end
			end, function()
				if hovered.stat == key then
					hovered.stat = nil
				end
				hideTip()
			end, function()
				UIClick:Play()
				M.openStat(key)
			end)
		end
	end

	if #chain == 0 then -- a skill without statistics: one dim slot in the middle explains it
		local empty = cloneTemplate("statSlot")
		if empty then
			paint(empty, "#555555", "")
			place(frame, occupied, cell(LAYOUT.rewardRow, LAYOUT.headerCol), empty)
			bind(empty, function()
				showTip(
					{
						title = '<font color="#AAAAAA"><b>No collections yet</b></font>',
						description = "This skill has no statistics.",
						click = "",
					},
					empty
				)
			end, hideTip)
		end
	end

	finishGrid(frame, occupied)
end

-- ===================== MENU 3: tiers of a statistic =====================
function M.populateStat(frame: Instance)
	table.clear(views.tiers)
	hovered.tier = nil
	local skill, statKey = state.skill, state.statKey
	local config = statConfig(skill, statKey)
	local occupied: { [number]: Instance } = {}
	if not (skill and statKey and config) then
		warn("[CollectionsPageModule] no statistic selected for CollectionsMenu3")
		finishGrid(frame, occupied)
		return
	end

	local header = cloneTemplate("statSlot")
	if header then
		header.Name = "SelectedStatistic"
		paint(header, config.color or "#FFFFFF", config.icon or "")
		place(frame, occupied, cell(0, LAYOUT.headerCol), header)
		bind(header, function()
			local tip = statTooltip(skill, statKey, false)
			if tip then
				showTip(tip, header)
			end
		end, hideTip)
	end

	local highest = CollectionMath.highestTier(getStatData(skill, statKey).lifetime or 0)
	local levelSlot = templates.levelSlot
	if levelSlot then
		for tier = 1, TIER_COUNT do
			local slot = levelSlot:Clone() :: any
			slot.Name = "Tier_" .. tier
			setLabel(slot, roman(tier))
			local status = CollectionMath.status(tier, highest)
			paint(slot, TIER_COLORS[status])
			place(frame, occupied, contentCell(tier), slot)
			views.tiers[tier] = { slot = slot, status = status }
			bind(slot, function()
				hovered.tier = tier
				UIClick3:Play()
				showTip(tierTooltip(skill, statKey, tier), slot)
			end, function()
				if hovered.tier == tier then
					hovered.tier = nil
				end
				hideTip()
			end, function()
				UIClick:Play()
				M.openTier(tier)
			end)
		end
	end

	finishGrid(frame, occupied)
end

-- ===================== MENU 4: the rewards of one tier =====================
function M.populateTier(frame: Instance)
	table.clear(views.rewards)
	local skill, statKey, tier = state.skill, state.statKey, state.tier
	local config = statConfig(skill, statKey)
	local occupied: { [number]: Instance } = {}
	if not (skill and statKey and tier and config) then
		warn("[CollectionsPageModule] no tier selected for CollectionsMenu4")
		finishGrid(frame, occupied)
		return
	end

	local lifetime = getStatData(skill, statKey).lifetime or 0
	local status = CollectionMath.status(tier, CollectionMath.highestTier(lifetime))

	local title = cloneTemplate("tierTitle", "levelSlot")
	if title then
		title.Name = "TierTitle"
		setLabel(title, roman(tier))
		paint(title, TIER_COLORS[status])
		place(frame, occupied, cell(0, LAYOUT.headerCol), title)
		views.rewards.title = { slot = title, status = status }
		bind(title, function()
			showTip(tierTooltip(skill, statKey, tier), title)
		end, hideTip)
	end

	local rewards = Config.getRewards(skill, statKey, tier)
	if #rewards > LAYOUT.maxRewards then
		warn(
			string.format(
				"[CollectionsPageModule] %s.%s tier %d has %d rewards, showing %d",
				skill,
				statKey,
				tier,
				#rewards,
				LAYOUT.maxRewards
			)
		)
	end
	local columns = CollectionMath.rewardColumns(#rewards)
	for i, column in ipairs(columns) do
		local reward = rewards[i]
		local info = CollectionRewards.describe(reward, { skill = skill, key = statKey, tier = tier })
		local slot = cloneTemplate("rewardSlot", "statSlot")
		if slot then
			slot.Name = "Reward_" .. i
			paint(slot, info.color or "#FFFFFF", info.icon or "")
			setLabel(slot, info.short or "")
			place(frame, occupied, cell(LAYOUT.rewardRow, column), slot)
			bind(slot, function()
				UIClick3:Play()
				showTip({
					title = string.format(
						'<font color="%s"><b>%s</b></font>',
						info.color or "#FFFFFF",
						info.name or "Reward"
					),
					description = info.text,
					click = "",
				}, slot)
			end, hideTip)
		end
	end

	finishGrid(frame, occupied)
end

-- ===================== LIVE REFRESH =====================
--- StatisticsUpdated arrives about 10x/s while stats change: only touch slots whose state really changed.
local function refresh()
	local skill, statKey = state.skill, state.statKey

	for key, view in pairs(views.stats) do
		if not alive(view.slot) then
			views.stats[key] = nil
		elseif skill then
			local level = CollectionMath.highestTier(getStatData(skill, key).lifetime or 0)
			if level ~= view.level then
				view.level = level
				setLabel(view.slot, roman(level))
			end
		end
	end
	local hoveredStat = hovered.stat and views.stats[hovered.stat]
	if hoveredStat and skill then
		local tip = statTooltip(skill, hovered.stat :: string, true)
		if tip then
			showTip(tip, hoveredStat.slot)
		end
	end

	if skill and statKey then
		local highest = CollectionMath.highestTier(getStatData(skill, statKey).lifetime or 0)
		for tier, view in pairs(views.tiers) do
			if not alive(view.slot) then
				views.tiers[tier] = nil
			else
				local status = CollectionMath.status(tier, highest)
				if status ~= view.status then
					view.status = status
					paint(view.slot, TIER_COLORS[status])
				end
			end
		end
		local hoveredTier = hovered.tier and views.tiers[hovered.tier]
		if hoveredTier then
			showTip(tierTooltip(skill, statKey, hovered.tier :: number), hoveredTier.slot)
		end

		local title = views.rewards.title
		if title and alive(title.slot) and state.tier then
			local status = CollectionMath.status(state.tier, highest)
			if status ~= title.status then
				title.status = status
				paint(title.slot, TIER_COLORS[status])
			end
		end
	end
end

-- ===================== NAVIGATION =====================
local function gridTitle(gridKey: string?): string?
	local config = statConfig(state.skill, state.statKey)
	if gridKey == "CollectionsMenu2" and state.skill then
		return state.skill .. " Collections"
	elseif gridKey == "CollectionsMenu3" and config then
		return config.name .. " Collection"
	elseif gridKey == "CollectionsMenu4" and config and state.tier then
		return config.name .. " " .. roman(state.tier)
	end
	return nil
end

local function navigate(gridKey: string)
	sharedRefs.GridMenuModule.navigateToGrid(gridKey)
	local title = gridTitle(gridKey)
	if title then
		sharedRefs.typewriteTitle(title)
	end
end

function M.openSkill(skill: string)
	if not STAT_CHAINS[skill] then
		warn("[CollectionsPageModule] unknown skill " .. tostring(skill))
		return
	end
	state.skill, state.statKey, state.tier = skill, nil, nil
	navigate("CollectionsMenu2")
end

function M.openStat(statKey: string)
	if not statConfig(state.skill, statKey) then
		warn("[CollectionsPageModule] no config for " .. tostring(state.skill) .. "." .. tostring(statKey))
		return
	end
	state.statKey, state.tier = statKey, nil
	navigate("CollectionsMenu3")
end

function M.openTier(tier: number)
	if not (state.statKey and tier >= 1 and tier <= TIER_COUNT) then
		return
	end
	state.tier = tier
	navigate("CollectionsMenu4")
end

--- The one Go back handler of Menu2, Menu3 and Menu4: pop one grid. The engine rebuilds the page we return to from `state`
--- (onPopulate), so it is never blank; only afterwards is the state we left cleared.
function M.back()
	local grids = sharedRefs.GridMenuModule
	if not grids.navigateBack() then
		return
	end
	local key = grids.getActiveGridKey()
	local title = gridTitle(key)
	if title then
		sharedRefs.typewriteTitle(title)
	end
	if key == "CollectionsMenu3" then
		state.tier = nil
	elseif key == "CollectionsMenu2" then
		state.statKey, state.tier = nil, nil
	elseif key == "CollectionsGrid" then
		state.skill, state.statKey, state.tier = nil, nil, nil
	end
end

function M.close()
	table.clear(hovered)
	hideTip()
end

function M.reset()
	state.skill, state.statKey, state.tier = nil, nil, nil
	for _, group in pairs(views) do
		table.clear(group)
	end
	table.clear(hovered)
	if TooltipModule then
		TooltipModule.forceHide()
	end
end

function M.getActiveSkill()
	return state.skill
end

function M.getActiveStat()
	return state.statKey
end

function M.getActiveTier()
	return state.tier
end

-- ===================== TOAST =====================
local function onTierUnlocked(info: any)
	if
		type(info) ~= "table"
		or type(info.skill) ~= "string"
		or type(info.key) ~= "string"
		or type(info.tier) ~= "number"
	then
		return
	end
	local config = statConfig(info.skill, info.key)
	if not config or info.tier < 1 or info.tier > TIER_COUNT then
		return
	end
	local parts = {}
	for _, reward in ipairs(Config.getRewards(info.skill, info.key, info.tier)) do
		table.insert(parts, rewardLine(reward, info.skill, info.key, info.tier))
	end
	local extra = (type(info.count) == "number" and info.count > 1)
			and string.format(' <font color="#AAAAAA">(+%d tiers)</font>', info.count - 1)
		or ""
	StatisticLogModule.log(
		string.format(
			'<font color="#55FFFF"><b>COLLECTION</b></font> <font color="%s">%s</font> <font color="#FFFF55"><b>%s</b></font>%s  %s',
			config.color or "#FFFFFF",
			config.name,
			roman(info.tier),
			extra,
			table.concat(parts, '<font color="#AAAAAA">, </font>')
		),
		TOAST_SECONDS
	)
	UIClick3:Play()
end

-- ===================== INIT =====================
function M.init(refs: any)
	sharedRefs = refs
	TooltipModule = refs.TooltipModule

	local temporary =
		player:WaitForChild("PlayerGui"):WaitForChild("CentralizedAscensionMenu"):WaitForChild("TemporaryMenus")
	templates.statSlot = temporary:FindFirstChild("StatSlot")
	templates.collectionStatSlot = temporary:FindFirstChild("CollectionStatSlot") -- StatSlot + LevelLabel (build_collection_rewards)
	templates.levelSlot = temporary:FindFirstChild("CollectionLevelSlot")
	templates.blank = temporary:FindFirstChild("BlankSlot")
	templates.tierTitle = temporary:FindFirstChild("TierTitle") -- optional, falls back to CollectionLevelSlot
	templates.rewardSlot = temporary:FindFirstChild("RewardSlot") -- optional, falls back to StatSlot
	for name, required in pairs({ statSlot = "StatSlot", levelSlot = "CollectionLevelSlot", blank = "BlankSlot" }) do
		if not templates[name] then
			warn("[CollectionsPageModule] TemporaryMenus." .. required .. " is missing")
		end
	end
	if not (templates.tierTitle and templates.rewardSlot) then
		warn(
			"[CollectionsPageModule] TierTitle / RewardSlot templates missing: run tools/studio/build_collection_rewards.luau"
		)
	end

	StatisticsUpdated.OnClientEvent:Connect(function(payload)
		cachedData = payload
		refresh()
	end)
	TierUnlocked.OnClientEvent:Connect(onTierUnlocked)

	-- preload the statistic icons so the grids do not pop in
	local preload = {}
	for _, chain in pairs(STAT_CHAINS) do
		for _, item in ipairs(chain) do
			if item.icon and item.icon ~= "" then
				local image = Instance.new("ImageLabel")
				image.Image = item.icon
				table.insert(preload, image)
			end
		end
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(preload)
		for _, image in ipairs(preload) do
			image:Destroy()
		end
	end)
end

return M
