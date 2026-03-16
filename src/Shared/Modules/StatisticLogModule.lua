--[[
	StatisticLogModule (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Displays animated purchase/obtainment notifications in the StatisticLog
	UI.  Entries slide in from the right, hold for a duration, then fade out
	and slide back right before being destroyed.

	NEGATIVE LOG (cost deductions):
	  A mirrored channel that slides in from the LEFT and out to the LEFT.
	  Amounts display as red "−X".  Uses BoundingBox2 > LayoutBox.
	  Same stacking, rescue, and force-remove behaviour as the positive log.

	Stack condensation: consecutive logStat calls for the same stat merge
	into the existing entry — amounts combine, owned updates, a (×N) counter
	appears, and the hold timer resets.  Stacks cap at MAX_STACK then flush
	to a new entry.

	Hierarchy expected (in the GUI):
	  StatisticLog (ScreenGui)
	    Template          (invisible container, holds the clonable)
	      LogTemplate     (CanvasGroup — ClipsDescendants, GroupTransparency)
	        BB            (Frame — Position tweens slide this in/out)
	          BG          (Frame — background, has UIGradient + UIPadding)
	            Notification (TextLabel — RichText message)
	    BoundingBox       (Frame — ClipsDescendants = true)  ← positive log
	      LayoutBox       (Frame — holds cloned entries)
	        UIListLayout
	    BoundingBox2      (Frame — ClipsDescendants = true)  ← negative log
	      LayoutBox       (Frame — holds cloned entries)
	        UIListLayout

	API:
	  .init(statisticLogFrame)
	  .log(message, duration)          -- raw message string (RichText OK)
	  .logStat(statName, amount, statColor, owned, duration)  -- stackable (positive)
	  .logStatNegative(statName, amount, statColor, owned, duration)  -- stackable (negative, slides left)
	  .clear()                         -- force-remove all visible entries (both channels)
--]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MoneyLib = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MoneyLib"))

-- ===================== CONSTANTS =====================
local MAX_VISIBLE = 4
local MAX_STACK = 100
local DEFAULT_DURATION = 5

-- Tween durations
local SLIDE_IN_TIME = 0.5
local FADE_IN_TIME = 0.45 -- GroupTransparency fade in

local SLIDE_OUT_TIME = 0.5
local FADE_OUT_TIME = 0.45 -- GroupTransparency fade out

local FORCE_FADE_TIME = 0.15
local FORCE_SLIDE_TIME = 0.15

-- Positions (applied to BB inside LogTemplate)
-- POSITIVE channel: slides in from right
local POS_HIDDEN_RIGHT = UDim2.fromScale(1.5, 0.5)
local POS_VISIBLE = UDim2.fromScale(0.5, 0.5)
-- NEGATIVE channel: slides in from left
local POS_HIDDEN_LEFT = UDim2.fromScale(-0.5, 0.5)

-- Easing
local EASE_SLIDE_IN = TweenInfo.new(SLIDE_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local EASE_SLIDE_OUT = TweenInfo.new(SLIDE_OUT_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In)
local EASE_FADE_IN = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local EASE_FADE_OUT = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local EASE_FORCE = TweenInfo.new(FORCE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local TextService = game:GetService("TextService")

-- Per-channel max widths
local maxWidthPositive = 0
local maxWidthNegative = 0

-- ===================== STATE =====================
local logTemplate = nil

-- Positive channel
local layoutBox = nil
local activeEntries = {}

-- Descending LayoutOrder counters (newest = lowest = top of list)
local layoutOrderPositive = 0
local layoutOrderNegative = 1000000

-- Negative channel
local layoutBoxNeg = nil
local activeEntriesNeg = {}

-- Shared sounds
local soundIn = nil
local soundOut = nil

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

local NOTIFICATION_FONT = Font.new("rbxassetid://11598121416")

local function _getTextWidth(notification)
	local params = Instance.new("GetTextBoundsParams")
	params.Text = notification.ContentText
	params.Font = NOTIFICATION_FONT
	params.Size = notification.TextSize
	params.Width = math.huge

	local success, bounds = pcall(function()
		return TextService:GetTextBoundsAsync(params)
	end)

	if success then
		return bounds.X + 30
	end
	return 100
end

local function _updateAllWidths(newWidth, entries, maxWidthRef)
	if newWidth <= maxWidthRef.value then
		return
	end
	maxWidthRef.value = newWidth
	for _, entry in ipairs(entries) do
		if entry.frame and entry.frame.Parent then
			entry.frame.Size = UDim2.fromOffset(maxWidthRef.value, 32)
		end
	end
end

-- ===================== STACK HELPERS =====================
--- Builds the full RichText string for a POSITIVE stat notification.
--- Appends (×N) only when stackCount > 1.
local function buildStatText(statName, totalAmount, statColor, ownedAmount, stackCount)
	local formattedAmount = formatNumber(totalAmount)
	local formattedOwned = ownedAmount and formatNumber(ownedAmount) or "?"
	local base = string.format(
		'<font color="#55FF55"><b>+%s</b></font> <font color="%s"><b>%s</b></font> <font color="#AAAAAA">(Owned: </font><font color="%s">%s</font><font color="#AAAAAA">)</font>',
		formattedAmount,
		statColor or "#FFFFFF",
		statName,
		statColor or "#FFFFFF",
		formattedOwned
	)
	if stackCount > 1 then
		base = base
			.. string.format(
				' <stroke color="#FFFFFF" thickness="1" joins="round"><font color="#555555">(×%d)</font></stroke>',
				stackCount
			)
	end
	return base
end

--- Builds the full RichText string for a NEGATIVE stat notification.
--- Shows red "−X" instead of green "+X".  Everything else identical.
local function buildStatTextNegative(statName, totalAmount, statColor, ownedAmount, stackCount)
	local formattedAmount = formatNumber(totalAmount)
	local formattedOwned = ownedAmount and formatNumber(ownedAmount) or "?"
	local base = string.format(
		'<font color="#FF5555"><b>−%s</b></font> <font color="%s"><b>%s</b></font> <font color="#AAAAAA">(Owned: </font><font color="%s">%s</font><font color="#AAAAAA">)</font>',
		formattedAmount,
		statColor or "#FFFFFF",
		statName,
		statColor or "#FFFFFF",
		formattedOwned
	)
	if stackCount > 1 then
		base = base
			.. string.format(
				' <stroke color="#FFFFFF" thickness="1" joins="round"><font color="#555555">(×%d)</font></stroke>',
				stackCount
			)
	end
	return base
end

--- Updates the Notification TextLabel on an existing entry's frame.
--- isNegative selects which text builder and which width tracker to use.
local function updateEntryText(entry, isNegative)
	local frame = entry.frame
	if not frame or not frame.Parent then
		return
	end
	local bb = frame:FindFirstChild("BB")
	local bg = bb and bb:FindFirstChild("BG")
	local notification = bg and bg:FindFirstChild("Notification")
	if notification then
		if isNegative then
			notification.Text = buildStatTextNegative(
				entry.statName,
				entry.totalAmount,
				entry.statColor,
				entry.ownedAmount,
				entry.stackCount
			)
		else
			notification.Text =
				buildStatText(entry.statName, entry.totalAmount, entry.statColor, entry.ownedAmount, entry.stackCount)
		end
		task.spawn(function()
			if notification and notification.Parent then
				local entries = isNegative and activeEntriesNeg or activeEntries
				local maxRef = isNegative and { value = maxWidthNegative } or { value = maxWidthPositive }
				local newW = _getTextWidth(notification)
				if newW > maxRef.value then
					maxRef.value = newW
					if isNegative then
						maxWidthNegative = maxRef.value
					else
						maxWidthPositive = maxRef.value
					end
					for _, e in ipairs(entries) do
						if e.frame and e.frame.Parent then
							e.frame.Size = UDim2.fromOffset(maxRef.value, 32)
						end
					end
				end
				frame.Size = UDim2.fromOffset(maxRef.value, 32)
			end
		end)
	end
end

--- Finds the most recent active entry matching statName + statColor
--- that has not yet reached MAX_STACK in the given entries list.
local function findMatchingEntry(statName, statColor, entries)
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if
			entry.statName
			and entry.statName == statName
			and entry.statColor == statColor
			and entry.stackCount < MAX_STACK
		then
			return entry
		end
	end
	return nil
end

-- ===================== FORCE REMOVE (fast) =====================
--- posHidden: the off-screen position to slide toward (right or left)
local function forceRemoveOldest(entries, posHidden)
	if #entries == 0 then
		return
	end

	local entry = table.remove(entries, 1)
	entry.cancelFlag.cancelled = true

	local frame = entry.frame -- LogTemplate (CanvasGroup)
	if not frame or not frame.Parent then
		return
	end

	local bb = frame:FindFirstChild("BB")

	task.spawn(function()
		if bb then
			TweenService:Create(
				bb,
				TweenInfo.new(FORCE_SLIDE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In),
				{ Position = posHidden }
			):Play()
		end
		TweenService:Create(frame, EASE_FORCE, { GroupTransparency = 1 }):Play()

		task.wait(FORCE_SLIDE_TIME)

		if frame and frame.Parent then
			frame:Destroy()
		end
	end)
end

-- ===================== ANIMATE ENTRY =====================
--- posHidden: the off-screen position (POS_HIDDEN_RIGHT or POS_HIDDEN_LEFT)
--- entries:   the activeEntries list this entry belongs to
local function animateEntry(entry, duration, posHidden, entries)
	local frame = entry.frame
	local cancelFlag = entry.cancelFlag
	local bb = frame:FindFirstChild("BB")

	-- ── Initial state: BB off-screen, fully transparent ──
	frame.Visible = true
	frame.GroupTransparency = 1
	if bb then
		bb.AnchorPoint = Vector2.new(0.5, 0.5)
		bb.Position = posHidden
	end

	-- ── PHASE 1: Slide in + fade in (simultaneous) ──
	if soundIn then
		soundIn:Play()
	end

	if bb then
		TweenService:Create(bb, EASE_SLIDE_IN, { Position = POS_VISIBLE }):Play()
	end
	TweenService:Create(frame, EASE_FADE_IN, { GroupTransparency = 0 }):Play()

	task.wait(SLIDE_IN_TIME)
	if cancelFlag.cancelled then
		return
	end

	-- ── PHASES 2+3: Hold → Slide out (looped for rescue) ──
	while true do
		-- ── PHASE 2: Hold ──
		entry.removing = false
		local holdStart = tick()
		while tick() - holdStart < duration do
			if cancelFlag.cancelled then
				return
			end
			if entry.resetHoldFlag then
				entry.resetHoldFlag = false
				holdStart = tick()
			end
			task.wait(0.1)
		end
		if cancelFlag.cancelled then
			return
		end

		-- ── PHASE 3: Slide out + fade out (simultaneous) ──
		entry.removing = true
		entry.rescueFlag = false

		if bb then
			TweenService:Create(bb, EASE_SLIDE_OUT, { Position = posHidden }):Play()
		end
		TweenService:Create(frame, EASE_FADE_OUT, { GroupTransparency = 1 }):Play()
		if soundOut then
			soundOut:Play()
		end

		task.wait(SLIDE_OUT_TIME)

		-- ── Post-slide-out: check rescue before destroying ──
		if entry.rescueFlag then
			if bb then
				bb.Position = POS_VISIBLE
			end
			frame.GroupTransparency = 0
			entry.rescueFlag = false
			entry.removing = false
			continue
		end

		-- ── Cleanup (no rescue — normal exit) ──
		if frame and frame.Parent then
			frame:Destroy()
		end

		for i, e in ipairs(entries) do
			if e.frame == frame then
				table.remove(entries, i)
				break
			end
		end
		break
	end
end

-- ===================== LOG (raw message — positive channel only) =====================
function M.log(message, duration)
	print("[StatisticLogModule] LOG CALLED:", message)

	if not logTemplate then
		warn("[StatisticLogModule] logTemplate is nil!")
		return
	end
	if not layoutBox then
		warn("[StatisticLogModule] layoutBox is nil!")
		return
	end

	duration = duration or DEFAULT_DURATION

	while #activeEntries >= MAX_VISIBLE do
		forceRemoveOldest(activeEntries, POS_HIDDEN_RIGHT)
	end

	local frame = logTemplate:Clone()
	frame.Visible = true

	layoutOrderPositive = layoutOrderPositive + 1
	frame.LayoutOrder = layoutOrderPositive

	local bb = frame:FindFirstChild("BB")
	local bg = bb and bb:FindFirstChild("BG")
	local notification = bg and bg:FindFirstChild("Notification")

	if notification then
		notification.RichText = true
		notification.Text = message
		task.defer(function()
			if notification and notification.Parent then
				local newW = _getTextWidth(notification)
				if newW > maxWidthPositive then
					maxWidthPositive = newW
					for _, e in ipairs(activeEntries) do
						if e.frame and e.frame.Parent then
							e.frame.Size = UDim2.fromOffset(maxWidthPositive, 32)
						end
					end
				end
				frame.Size = UDim2.fromOffset(maxWidthPositive, 32)
			end
		end)
	end

	if bb then
		bb.AnchorPoint = Vector2.new(0.5, 0.5)
		bb.Position = POS_HIDDEN_RIGHT
	end

	frame.Parent = layoutBox

	print(
		"[StatisticLogModule] Cloned → Parent:",
		frame.Parent and frame.Parent:GetFullName(),
		"| Visible:",
		frame.Visible
	)

	local cancelFlag = { cancelled = false }
	local entry = {
		frame = frame,
		cancelFlag = cancelFlag,
		statName = nil,
	}
	table.insert(activeEntries, entry)

	task.spawn(animateEntry, entry, duration, POS_HIDDEN_RIGHT, activeEntries)
end

-- ===================== LOG STAT (stackable — POSITIVE) =====================
function M.logStat(statName, amount, statColor, owned, duration)
	print("[StatisticLogModule] logStat:", statName, amount, statColor, owned)

	duration = duration or DEFAULT_DURATION

	-- ── Try to merge into existing entry ──
	local match = findMatchingEntry(statName, statColor, activeEntries)
	if match then
		match.totalAmount = match.totalAmount + amount
		match.ownedAmount = owned
		match.stackCount = match.stackCount + 1
		updateEntryText(match, false)

		if match.removing then
			match.rescueFlag = true
		else
			match.resetHoldFlag = true
		end
		return
	end

	-- ── No match or match at cap — create new entry ──
	if not logTemplate then
		warn("[StatisticLogModule] logTemplate is nil!")
		return
	end
	if not layoutBox then
		warn("[StatisticLogModule] layoutBox is nil!")
		return
	end

	while #activeEntries >= MAX_VISIBLE do
		forceRemoveOldest(activeEntries, POS_HIDDEN_RIGHT)
	end

	local frame = logTemplate:Clone()
	frame.Visible = true

	layoutOrderPositive = layoutOrderPositive + 1
	frame.LayoutOrder = layoutOrderPositive

	local bb = frame:FindFirstChild("BB")
	local bg = bb and bb:FindFirstChild("BG")
	local notification = bg and bg:FindFirstChild("Notification")

	local text = buildStatText(statName, amount, statColor or "#FFFFFF", owned, 1)
	if notification then
		notification.RichText = true
		notification.Text = text
		task.defer(function()
			if notification and notification.Parent then
				local newW = _getTextWidth(notification)
				if newW > maxWidthPositive then
					maxWidthPositive = newW
					for _, e in ipairs(activeEntries) do
						if e.frame and e.frame.Parent then
							e.frame.Size = UDim2.fromOffset(maxWidthPositive, 32)
						end
					end
				end
				frame.Size = UDim2.fromOffset(maxWidthPositive, 32)
			end
		end)
	end

	if bb then
		bb.AnchorPoint = Vector2.new(0.5, 0.5)
		bb.Position = POS_HIDDEN_RIGHT
	end

	frame.Parent = layoutBox

	local cancelFlag = { cancelled = false }
	local entry = {
		frame = frame,
		cancelFlag = cancelFlag,
		statName = statName,
		statColor = statColor or "#FFFFFF",
		totalAmount = amount,
		ownedAmount = owned,
		stackCount = 1,
		resetHoldFlag = false,
		rescueFlag = false,
		removing = false,
	}
	table.insert(activeEntries, entry)

	task.spawn(animateEntry, entry, duration, POS_HIDDEN_RIGHT, activeEntries)
end

-- ===================== LOG STAT NEGATIVE (stackable — slides LEFT) =====================
function M.logStatNegative(statName, amount, statColor, owned, duration)
	print("[StatisticLogModule] logStatNegative:", statName, amount, statColor, owned)

	duration = duration or DEFAULT_DURATION

	-- ── Try to merge into existing negative entry ──
	local match = findMatchingEntry(statName, statColor, activeEntriesNeg)
	if match then
		match.totalAmount = match.totalAmount + amount
		match.ownedAmount = owned
		match.stackCount = match.stackCount + 1
		updateEntryText(match, true)

		if match.removing then
			match.rescueFlag = true
		else
			match.resetHoldFlag = true
		end
		return
	end

	-- ── No match or match at cap — create new entry ──
	if not logTemplate then
		warn("[StatisticLogModule] logTemplate is nil!")
		return
	end
	if not layoutBoxNeg then
		warn("[StatisticLogModule] layoutBoxNeg (BoundingBox2) is nil!")
		return
	end

	while #activeEntriesNeg >= MAX_VISIBLE do
		forceRemoveOldest(activeEntriesNeg, POS_HIDDEN_LEFT)
	end

	local frame = logTemplate:Clone()
	frame.Visible = true

	layoutOrderNegative = layoutOrderNegative - 1
	frame.LayoutOrder = layoutOrderNegative

	local bb = frame:FindFirstChild("BB")
	local bg = bb and bb:FindFirstChild("BG")
	local notification = bg and bg:FindFirstChild("Notification")

	local text = buildStatTextNegative(statName, amount, statColor or "#FFFFFF", owned, 1)
	if notification then
		notification.RichText = true
		notification.Text = text
		task.defer(function()
			if notification and notification.Parent then
				local newW = _getTextWidth(notification)
				if newW > maxWidthNegative then
					maxWidthNegative = newW
					for _, e in ipairs(activeEntriesNeg) do
						if e.frame and e.frame.Parent then
							e.frame.Size = UDim2.fromOffset(maxWidthNegative, 32)
						end
					end
				end
				frame.Size = UDim2.fromOffset(maxWidthNegative, 32)
			end
		end)
	end

	if bb then
		bb.AnchorPoint = Vector2.new(0.5, 0.5)
		bb.Position = POS_HIDDEN_LEFT
	end

	frame.Parent = layoutBoxNeg

	local cancelFlag = { cancelled = false }
	local entry = {
		frame = frame,
		cancelFlag = cancelFlag,
		statName = statName,
		statColor = statColor or "#FFFFFF",
		totalAmount = amount,
		ownedAmount = owned,
		stackCount = 1,
		resetHoldFlag = false,
		rescueFlag = false,
		removing = false,
	}
	table.insert(activeEntriesNeg, entry)

	task.spawn(animateEntry, entry, duration, POS_HIDDEN_LEFT, activeEntriesNeg)
end

-- ===================== CLEAR ALL =====================
function M.clear()
	-- Positive channel
	for _, entry in ipairs(activeEntries) do
		entry.cancelFlag.cancelled = true
		if entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
	end
	activeEntries = {}
	maxWidthPositive = 0

	-- Negative channel
	for _, entry in ipairs(activeEntriesNeg) do
		entry.cancelFlag.cancelled = true
		if entry.frame and entry.frame.Parent then
			entry.frame:Destroy()
		end
	end
	activeEntriesNeg = {}
	maxWidthNegative = 0

	layoutOrderPositive = 1000000
	layoutOrderNegative = 1000000
end

-- ===================== INIT =====================
function M.init(statisticLogFrame)
	print("[StatisticLogModule] init() called with:", statisticLogFrame and statisticLogFrame:GetFullName())

	local template = statisticLogFrame:FindFirstChild("Template")
	if not template then
		warn("[StatisticLogModule] Template not found inside StatisticLog")
		return
	end

	logTemplate = template:FindFirstChild("LogTemplate")
	if not logTemplate then
		warn("[StatisticLogModule] LogTemplate not found inside Template")
		return
	end

	-- ── Positive channel: BoundingBox > LayoutBox ──
	local boundingBox = statisticLogFrame:FindFirstChild("BoundingBox1")
	if not boundingBox then
		warn("[StatisticLogModule] BoundingBox not found inside StatisticLog")
		return
	end

	layoutBox = boundingBox:FindFirstChild("LayoutBox")
	if not layoutBox then
		warn("[StatisticLogModule] LayoutBox not found inside BoundingBox")
		return
	end

	-- ── Negative channel: BoundingBox2 > LayoutBox ──
	local boundingBox2 = statisticLogFrame:FindFirstChild("BoundingBox2")
	if not boundingBox2 then
		warn("[StatisticLogModule] BoundingBox2 not found inside StatisticLog")
		return
	end

	layoutBoxNeg = boundingBox2:FindFirstChild("LayoutBox")
	if not layoutBoxNeg then
		warn("[StatisticLogModule] LayoutBox not found inside BoundingBox2")
		return
	end

	-- ── Sounds ──
	local uiSounds = workspace:FindFirstChild("UISounds")
	if uiSounds then
		soundIn = uiSounds:FindFirstChild("In")
		soundOut = uiSounds:FindFirstChild("Out")
	end

	print("[StatisticLogModule] logTemplate:", logTemplate:GetFullName())
	print("[StatisticLogModule] layoutBox (positive):", layoutBox:GetFullName())
	print("[StatisticLogModule] layoutBoxNeg (negative):", layoutBoxNeg:GetFullName())
	print("[StatisticLogModule] Initialized ✓")
end

return M
