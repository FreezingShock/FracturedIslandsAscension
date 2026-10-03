--[[
	StatisticsPageModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Client side of the Statistics menu. READ-ONLY: statistics are earned from
	world buttons (and passively), never by clicking a slot here.

	Two pages:
	  StatisticsGrid   hub - one button per skill. Each gets a dynamic tooltip
	                   (showSkillTooltip) summarising that skill's statistics.
	  StatisticsMenu2  one skill's statistics (up to 28 slots). Hover a slot for a
	                   Profile-style tooltip: Summary, Cost, Rewards, Boosted By.

	StatSlot hierarchy (TemporaryMenus.StatSlot):
	  StatSlot (GuiButton) > BG (ImageLabel > UIStroke), Icon (ImageLabel), ItemCount (TextLabel)

	Wiring (CentralizedMenuController):
	  setPendingSkill(skill)   before navigating to StatisticsMenu2
	  populate(frame)          grid onPopulate hook - builds the slots
	  depopulate()             grid onDepopulate hook - drops refs, hides tooltip
	  showSkillTooltip(skill, anchor) / hideSkillTooltip()   hub buttons
	  titleFor(skill)          rich-text page title
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("StatisticsConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any
local Attributes = require(Modules:WaitForChild("Attributes")) :: any

local STAT_CHAINS = Config.STAT_CHAINS
local SKILL_COLORS = Config.SKILL_COLORS
local statConfigLookup = Config.statConfigLookup
local boostLookup = Config.boostLookup
local LAYOUT = Config.LAYOUT
local COLUMNS = Config.COLUMNS
local STAT_ROWS = Config.STAT_ROWS
local STATS_PER_ROW = Config.STATS_PER_ROW

local player = Players.LocalPlayer

local TOOLTIP_SOURCE = "statistic"
local TOOLTIP_REFRESH = 0.25 -- min seconds between live tooltip refreshes
local ZERO = table.freeze({ count = 0, lifetime = 0, session = 0, multiplier = 1 })

-- ===================== AUDIO =====================
local UISounds = workspace:WaitForChild("UISounds")
local UIClick3 = UISounds:WaitForChild("Click3")

-- ===================== STATE =====================
local shared = nil
local TooltipModule = nil
local statSlotTemplate = nil
local blankSlotTemplate = nil

local statsFrame = nil -- active StatisticsMenu2 buffer (nil while closed)
local pendingSkill = nil -- set by the hub before navigating
local currentSkill = nil -- skill currently built into statsFrame
local slotRefs = {} -- [statKey] = { frame, countLabel, text }
local hoveredStatKey = nil
local tooltipRefreshQueued = false
local cachedData = nil

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

--- Text color for a stat: very dark stat colors (Void Coins) fall back to white
--- so names stay readable on the tooltip background.
local function textColor(hex)
	hex = hex or "#FFFFFF"
	local c = hexToColor3(hex)
	if (c.R * 0.299 + c.G * 0.587 + c.B * 0.114) < 0.28 then
		return "#FFFFFF"
	end
	return hex
end

local function getStatData(skill, statKey)
	local skills = cachedData and cachedData.skills
	local skillData = skills and skills[skill]
	return skillData and skillData[statKey] or ZERO
end

local function lookup(skill, key)
	local skillConfigs = statConfigLookup[skill]
	return skillConfigs and skillConfigs[key]
end

local function skillColor(skill)
	return SKILL_COLORS[skill] or "#FFFFFF"
end

function M.titleFor(skill)
	return string.format('<font color="%s">%s</font> Statistics', skillColor(skill), skill)
end

-- ===================== STAT TOOLTIP =====================
local OBTAIN_PILLS = {
	passive = { text = "EARNED PASSIVELY", color = "#55FF55" },
	button = { text = "OBTAINED FROM BUTTONS", color = "#FFFF55" },
	locked = { text = "UNOBTAINABLE", color = "#FF5555" },
}

local function costRows(config)
	local rows = {}
	for _, c in ipairs(config.cost or {}) do
		local cc = lookup(c.skill, c.id)
		local owned = getStatData(c.skill, c.id).count
		table.insert(rows, {
			label = cc and cc.name or c.id,
			labelColor = textColor(cc and cc.color),
			value = "-" .. formatNumber(c.amount),
			color = owned >= c.amount and "#55FF55" or "#FF5555",
			detail = string.format("(have %s)", formatNumber(owned)),
		})
	end
	return rows
end

local function rewardRows(skill, config)
	local rows = {}
	local topName, topValue
	for _, reward in ipairs(config.rewards or {}) do
		local row
		if reward.type == "stat" then
			local rs = reward.skill or skill
			local rc = lookup(rs, reward.target)
			row = {
				label = rc and rc.name or reward.target,
				labelColor = textColor(rc and rc.color),
				value = "+" .. formatNumber(reward.pct) .. "%",
				color = "#55FF55",
				detail = rs ~= skill and ("(" .. rs .. ")") or nil,
			}
		elseif reward.type == "gameStat" then
			local def = Attributes.find(reward.target)
			row = {
				label = def and def.name or reward.target,
				labelColor = def and def.color or "#FF55FF",
				value = "+" .. (def and Attributes.format(def.key, reward.flat) or tostring(reward.flat)),
				color = def and def.color or "#FF55FF",
				detail = "(Attribute)",
			}
		end
		if row then
			table.insert(rows, row)
			if not topName then
				topName, topValue = row.label, row.value
			end
		end
	end
	return rows, topName, topValue
end

local function boostRows(skill, key)
	local rows = {}
	local total = 0
	local boosts = boostLookup[skill] and boostLookup[skill][key] or {}
	for _, b in ipairs(boosts) do
		local sc = lookup(b.sourceSkill, b.sourceKey)
		local owned = getStatData(b.sourceSkill, b.sourceKey).count
		local contribution = owned * b.pct
		total += contribution
		table.insert(rows, {
			sort = contribution,
			label = sc and sc.name or b.sourceKey,
			labelColor = textColor(sc and sc.color),
			value = "+" .. formatNumber(contribution) .. "%",
			color = contribution > 0 and "#55FF55" or "#AAAAAA",
			detail = string.format("(%s x %s%%)", formatNumber(owned), formatNumber(b.pct)),
		})
	end
	table.sort(rows, function(a, b)
		return a.sort > b.sort
	end)
	return rows, total
end

--- Full Profile-style tooltip config for one statistic.
local function buildStatTooltip(skill, key)
	local config = lookup(skill, key)
	if not config then
		return nil
	end
	local data = getStatData(skill, key)
	local accent = textColor(config.color or skillColor(skill))

	local sections = {}

	-- Summary
	local multBonus = (data.multiplier - 1) * 100
	table.insert(sections, {
		type = "list",
		title = "Summary",
		color = accent,
		rows = {
			{ label = "Owned", value = formatNumber(data.count), labelColor = "#FFAA00" },
			{ label = "Lifetime", value = formatNumber(data.lifetime), labelColor = "#55FFFF" },
			{ label = "Session", value = formatNumber(data.session), labelColor = "#FFFF55" },
			{
				label = "Multiplier",
				value = string.format("%.2fx", data.multiplier),
				detail = multBonus > 0 and string.format("(+%s%%)", formatNumber(math.floor(multBonus + 0.5))) or nil,
				color = data.multiplier > 1 and "#55FF55" or "#FFFFFF",
				labelColor = "#55FF55",
			},
		},
	})

	-- Cost / income
	if config.passive then
		table.insert(sections, {
			type = "list",
			title = "Income",
			color = "#55FF55",
			rows = {
				{
					label = "Per second",
					value = "+" .. formatNumber(math.floor((config.passiveGain or 0) * data.multiplier)),
					color = "#55FF55",
					labelColor = "#AAAAAA",
				},
			},
		})
	else
		local rows = costRows(config)
		if #rows > 0 then
			table.insert(sections, { type = "list", title = "Cost per Purchase", color = "#FF5555", rows = rows })
		end
	end

	-- Rewards (per owned) - collapsed to a one-line summary until SHIFT is held
	local rewards, topName, topValue = rewardRows(skill, config)
	if #rewards > 0 then
		local summary = string.format("&f%d &7reward%s &7per owned", #rewards, #rewards == 1 and "" or "s")
		if topName then
			summary ..= string.format("\n&7First: &f%s &a%s", topName, topValue)
		end
		table.insert(sections, {
			type = "list",
			title = "Rewards",
			color = "#55FF55",
			rows = rewards,
			collapsible = true,
			summary = summary,
		})
	end

	-- Boosted By - which owned stats are multiplying this one
	local boosts, boostTotal = boostRows(skill, key)
	if #boosts > 0 then
		local summary = string.format("&f%d &7source%s &7· &a+%s%%", #boosts, #boosts == 1 and "" or "s", formatNumber(boostTotal))
		if boosts[1].sort > 0 then
			summary ..= string.format("\n&7Top: &f%s &a%s", boosts[1].label, boosts[1].value)
		end
		table.insert(sections, {
			type = "list",
			title = "Boosted By",
			color = "#55FFFF",
			rows = boosts,
			collapsible = true,
			summary = summary,
		})
	end

	local icon
	if config.icon and config.icon ~= "" then
		icon = { image = config.icon, color = config.color }
	end

	return {
		title = string.format(
			'<font color="%s">%s</font> <font color="#FFFFFF">%s</font>',
			accent,
			config.name,
			formatNumber(data.count)
		),
		icon = icon,
		description = config.description or Config.SKILL_BLURBS[skill],
		sections = sections,
		footer = skill .. " Statistic",
		click = OBTAIN_PILLS[config.obtain or "locked"],
	}
end

-- ===================== SKILL (HUB) TOOLTIP =====================
local function buildSkillTooltip(skill)
	local chain = STAT_CHAINS[skill]
	if not chain then
		return nil
	end
	local color = skillColor(skill)

	local discovered, obtainable, lifetimeTotal = 0, 0, 0
	local rows = {}
	local topItem, topLifetime = nil, 0
	for _, item in ipairs(chain) do
		local data = getStatData(skill, item.key)
		if data.lifetime > 0 then
			discovered += 1
		end
		if item.obtain ~= "locked" then
			obtainable += 1
		end
		lifetimeTotal += data.lifetime
		if data.lifetime > topLifetime then
			topItem, topLifetime = item, data.lifetime
		end
		table.insert(rows, {
			label = item.name,
			labelColor = textColor(item.color),
			value = formatNumber(data.count),
			color = data.count > 0 and "#FFFFFF" or "#AAAAAA",
		})
	end

	local sections = {
		{
			type = "list",
			title = "Summary",
			color = color,
			rows = {
				{ label = "Statistics", value = tostring(#chain), labelColor = "#FFAA00" },
				{ label = "Discovered", value = string.format("%d/%d", discovered, #chain), color = "#55FF55", labelColor = "#55FFFF" },
				{ label = "Obtainable", value = string.format("%d/%d", obtainable, #chain), color = obtainable > 0 and "#FFFF55" or "#FF5555", labelColor = "#FFFF55" },
				{ label = "Lifetime", value = formatNumber(lifetimeTotal), labelColor = "#55FF55" },
			},
		},
	}

	if #rows > 0 then
		local summary = string.format("&f%d &7statistics", #chain)
		if topItem then
			summary ..= string.format("\n&7Most earned: &f%s", topItem.name)
		end
		table.insert(sections, {
			type = "list",
			title = "Statistics",
			color = color,
			rows = rows,
			collapsible = true,
			summary = summary,
		})
	end

	return {
		title = string.format('<font color="%s">%s</font> Statistics', color, skill),
		description = Config.SKILL_BLURBS[skill],
		sections = sections,
		click = #chain > 0 and { text = "CLICK TO VIEW!", color = "#FFFF55" }
			or { text = "NO STATISTICS YET", color = "#FF5555" },
	}
end

function M.showSkillTooltip(skill, anchor)
	if not TooltipModule then
		return
	end
	UIClick3:Play()
	local cfg = buildSkillTooltip(skill)
	if cfg then
		TooltipModule.show(cfg, TOOLTIP_SOURCE, anchor)
	end
end

function M.hideSkillTooltip()
	if TooltipModule then
		TooltipModule.hide(TOOLTIP_SOURCE)
	end
end

-- ===================== SLOT VISUALS =====================
--- StatSlot.BackgroundColor3, BG.ImageColor3 + BG.UIStroke.Color, Icon.Image
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
		icon.Image = item.icon or ""
	end
end

local function cloneBlank(layoutOrder)
	if not blankSlotTemplate then
		return
	end
	local blank = blankSlotTemplate:Clone()
	blank.LayoutOrder = layoutOrder
	blank.Visible = true
	blank.Parent = statsFrame
end

-- ===================== LIVE REFRESH =====================
local function showHoveredTooltip()
	if hoveredStatKey and currentSkill and slotRefs[hoveredStatKey] then
		local cfg = buildStatTooltip(currentSkill, hoveredStatKey)
		if cfg then
			TooltipModule.show(cfg, TOOLTIP_SOURCE, slotRefs[hoveredStatKey].frame)
		end
	end
end

local function queueTooltipRefresh()
	if tooltipRefreshQueued then
		return
	end
	tooltipRefreshQueued = true
	task.delay(TOOLTIP_REFRESH, function()
		tooltipRefreshQueued = false
		showHoveredTooltip()
	end)
end

local function refreshSlots()
	if not currentSkill then
		return
	end
	for statKey, ref in pairs(slotRefs) do
		local text = formatNumber(getStatData(currentSkill, statKey).count)
		if ref.countLabel and ref.text ~= text then
			ref.text = text
			ref.countLabel.Text = text
		end
	end
	if hoveredStatKey then
		queueTooltipRefresh()
	end
end

-- ===================== POPULATE / DEPOPULATE =====================
function M.setPendingSkill(skill)
	pendingSkill = skill
end

--- StatisticsMenu2 onPopulate: builds the whole page into the buffer frame.
function M.populate(frame)
	local skill = pendingSkill
	local chain = skill and STAT_CHAINS[skill]
	if not chain then
		warn("[StatisticsPageModule] No chain for " .. tostring(skill))
		return
	end
	if not (statSlotTemplate and blankSlotTemplate) then
		warn("[StatisticsPageModule] Slot templates missing - cannot build page")
		return
	end

	statsFrame = frame
	currentSkill = skill
	hoveredStatKey = nil
	table.clear(slotRefs)

	-- ── Header: SelectedSkill icon + colors copied from the hub button ──
	local selected = frame:FindFirstChild("SelectedSkill")
	if selected then
		selected.LayoutOrder = LAYOUT.selectedSkillOrder

		local GridTemplates = ReplicatedStorage:FindFirstChild("GridTemplates")
		local hub = GridTemplates and GridTemplates:FindFirstChild("StatisticsMenu1")
		local skillButton = hub and hub:FindFirstChild(skill .. "Statistics")
		if skillButton then
			local sourceIcon = skillButton:FindFirstChild("Icon")
			local icon = selected:FindFirstChild("Icon")
			if icon and sourceIcon then
				icon.Image = sourceIcon.Image
			end
			local sourceBg = skillButton:FindFirstChild("BG")
			if sourceBg then
				selected.BackgroundColor3 = sourceBg.BackgroundColor3
				local bg = selected:FindFirstChild("BG")
				if bg then
					bg.ImageColor3 = sourceBg.ImageColor3
					local bgStroke = bg:FindFirstChildOfClass("UIStroke")
					local sourceStroke = sourceBg:FindFirstChildOfClass("UIStroke")
					if bgStroke and sourceStroke then
						bgStroke.Color = sourceStroke.Color
					end
				end
			end
		end

		selected.MouseEnter:Connect(function()
			if shared and shared.SkillsPageModule then
				shared.SkillsPageModule.showGridSkillTooltip(skill, false)
			end
		end)
		selected.MouseLeave:Connect(function()
			if shared and shared.SkillsPageModule then
				shared.SkillsPageModule.hideGridSkillTooltip()
			end
		end)
	end

	for i = 0, LAYOUT.headerBlanksBefore - 1 do
		cloneBlank(i)
	end
	for i = 1, LAYOUT.headerBlanksAfter do
		cloneBlank(LAYOUT.selectedSkillOrder + i)
	end

	-- ── Stat rows ──
	local statIndex = 1
	for row = 0, STAT_ROWS - 1 do
		local rowBase = LAYOUT.statRowBaseOrder + row * COLUMNS
		for pad = 0, LAYOUT.statRowPadCount - 1 do
			cloneBlank(rowBase + pad)
		end

		for col = LAYOUT.statRowPadCount, LAYOUT.statRowPadCount + STATS_PER_ROW - 1 do
			local lo = rowBase + col
			local item = chain[statIndex]
			if not item then
				cloneBlank(lo)
				continue
			end
			statIndex += 1

			local slot = statSlotTemplate:Clone()
			slot.Name = "Stat_" .. item.key
			slot.LayoutOrder = lo
			slot.Visible = true
			applySlotVisuals(slot, item)

			local countLabel = slot:FindFirstChild("ItemCount")
			local text = formatNumber(getStatData(skill, item.key).count)
			if countLabel then
				countLabel.Text = text
			end
			slotRefs[item.key] = { frame = slot, countLabel = countLabel, text = text }

			-- Hover tooltip only: slots are not clickable (no purchasing from the menu).
			slot.MouseEnter:Connect(function()
				hoveredStatKey = item.key
				UIClick3:Play()
				showHoveredTooltip()
			end)
			slot.MouseLeave:Connect(function()
				if hoveredStatKey == item.key then
					hoveredStatKey = nil
				end
				TooltipModule.hide(TOOLTIP_SOURCE)
			end)

			slot.Parent = frame
		end
	end

	-- ── Footer ──
	local backBtn = frame:FindFirstChild("BackButton")
	if backBtn then
		backBtn.LayoutOrder = LAYOUT.backButtonOrder
	end
	local closeBtn = frame:FindFirstChild("CloseSlot")
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

--- StatisticsMenu2 onDepopulate. The grid destroys the children itself; this only
--- drops our references and makes sure no tooltip is left hanging.
function M.depopulate()
	hoveredStatKey = nil
	statsFrame = nil
	currentSkill = nil
	table.clear(slotRefs)
	if TooltipModule then
		TooltipModule.forceHide()
	end
end

function M.getActiveSkill()
	return currentSkill
end

-- ===================== INIT =====================
function M.init(sharedRefs)
	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule

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

	-- Latest snapshot from the server (coalesced to ~10/sec). Missing entries mean
	-- "none owned", so only touched statistics are ever sent.
	StatisticsUpdated.OnClientEvent:Connect(function(payload)
		cachedData = payload
		refreshSlots()
	end)

	-- Preload stat icons without blocking.
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
		end)
	end

	print("[StatisticsPageModule] Initialized ✓")
end

return M
