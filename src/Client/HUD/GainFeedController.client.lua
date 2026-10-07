--[[
	GainFeedController (LocalScript)
	Place inside: StarterPlayerScripts

	The J "Recently gained" foldable under the scoreboard (StarterGui.FIAScoreboard.Panel.Foldable: Chip, List, RowTemplate; built
	by tools/studio/build_scoreboard.luau). The server (GainFeedService) fires the RemoteEvent GainFeed with batches of
	{ key, label, amount, color }; this groups them per key, sums what was gained inside GainFeedConfig.window seconds, and shows
	the rows newest first, fading and shrinking their age bar as they get old. Everything is config (Modules/Config/GainFeedConfig).
	The J key only toggles the display: the client sends nothing.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CONFIG = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("GainFeedConfig")) :: any
local remote = ReplicatedStorage:WaitForChild("GainFeed") :: RemoteEvent

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FIAScoreboard")
local foldable = gui:WaitForChild("Panel"):WaitForChild("Foldable")
local chip = foldable:WaitForChild("Chip") :: Frame
local list = foldable:WaitForChild("List") :: CanvasGroup
local rowTemplate = foldable:WaitForChild("RowTemplate") :: CanvasGroup
local rowsFrame = list:WaitForChild("Body"):WaitForChild("Rows") :: Frame
local emptyLabel = list.Body:WaitForChild("Empty") :: TextLabel
local windowLabel = list.Body:WaitForChild("Header"):WaitForChild("Window") :: TextLabel
local countLabel = chip:WaitForChild("Body"):WaitForChild("Count") :: TextLabel
local pop = list:WaitForChild("Pop") :: UIScale

local FOLD = TweenInfo.new(CONFIG.fold.time, Enum.EasingStyle[CONFIG.fold.style], Enum.EasingDirection[CONFIG.fold.direction])
windowLabel.Text = CONFIG.window .. "s"

-- ===================== LOOK (GainFeedConfig.look) =====================
local LOOK = CONFIG.look
local function applyLook()
	chip.BackgroundTransparency = LOOK.borderTransparency
	chip.Body.BackgroundTransparency = LOOK.bodyTransparency
	list.BackgroundTransparency = LOOK.borderTransparency
	list.Body.BackgroundTransparency = LOOK.bodyTransparency
	for _, name in ipairs({ "Title", "Count", "Key" }) do
		chip.Body[name].TextSize = LOOK.chipSize
		chip.Body[name].Size = UDim2.fromOffset(0, LOOK.chipSize + 4)
	end
	local header = list.Body.Header
	header.Size = UDim2.new(1, 0, 0, LOOK.headerSize + 4)
	header.Title.TextSize = LOOK.headerSize
	windowLabel.TextSize = LOOK.ageSize
	emptyLabel.TextSize = LOOK.emptySize
	emptyLabel.Size = UDim2.new(1, 0, 0, 0)
	emptyLabel.AutomaticSize = Enum.AutomaticSize.Y
	rowTemplate.Size = UDim2.new(1, 0, 0, LOOK.rowSize + 8)
	rowTemplate.Gem.Position = UDim2.fromOffset(0, math.floor((LOOK.rowSize + 4 - 10) / 2))
	rowTemplate.Label.TextSize = LOOK.rowSize
	rowTemplate.Label.Position = UDim2.fromOffset(18, 0)
	rowTemplate.Label.Size = UDim2.new(1, -(LOOK.ageWidth + 22), 0, LOOK.rowSize + 4)
	rowTemplate.Age.TextSize = LOOK.ageSize
	rowTemplate.Age.Size = UDim2.fromOffset(LOOK.ageWidth, LOOK.rowSize + 4)
end
applyLook()

type Row = { key: string, frame: CanvasGroup, events: { { t: number, amount: number } }, label: string, color: string, last: number }
local rows: { [string]: Row } = {}
local open = false
local unseen = 0
local order = 0

-- ===================== SOUND =====================
local function play(id: string)
	if id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = CONFIG.sounds.volume
	s.Parent = SoundService -- not positional: this is a UI cue for this player only
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
end

-- ===================== ROWS =====================
local function colorOf(hex: string?): Color3
	local ok, c = pcall(Color3.fromHex, hex or CONFIG.fallbackColor)
	return ok and c or Color3.new(1, 1, 1)
end

local function formatAmount(n: number): string
	if n >= 1e6 then
		return ("%.1fM"):format(n / 1e6)
	elseif n >= 1e4 then
		return ("%.1fK"):format(n / 1e3)
	end
	return tostring(math.floor(n + 0.5))
end

local function addGain(entry: any)
	local now = os.clock()
	local row = rows[entry.key]
	if not row then
		local frame = rowTemplate:Clone()
		frame.Name = "Row_" .. entry.key
		frame.Visible = true
		local color = colorOf(entry.color)
		frame.Gem.BackgroundColor3 = color
		frame.Bar.Fill.BackgroundColor3 = color
		frame.Label.TextColor3 = color
		frame.Parent = rowsFrame
		row = { key = entry.key, frame = frame, events = {}, label = entry.label, color = entry.color, last = now }
		rows[entry.key] = row
	end
	table.insert(row.events, { t = now, amount = entry.amount })
	row.last = now
	order += 1
	row.frame.LayoutOrder = -order -- newest first
	if not open then
		unseen += 1
	end
end

local function refresh()
	local now = os.clock()
	local shown = 0
	for key, row in pairs(rows) do
		local total, count = 0, 0
		local keep = {}
		for _, e in ipairs(row.events) do
			if now - e.t <= CONFIG.window then
				total += e.amount
				count += 1
				table.insert(keep, e)
			end
		end
		if count == 0 then
			row.frame:Destroy()
			rows[key] = nil
		else
			row.events = keep
			local age = now - row.last
			local text = ("+%s %s"):format(formatAmount(total), row.label)
			if count > 1 then
				text ..= (" <font color='#AAAAAA'>x%d</font>"):format(count)
			end
			if row.frame.Label.Text ~= text then
				row.frame.Label.Text = text
			end
			row.frame.Age.Text = ("%ds"):format(math.floor(age))
			row.frame.Bar.Fill.Size = UDim2.fromScale(math.clamp(1 - age / CONFIG.window, 0.02, 1), 1)
			local fadeStart = CONFIG.window - CONFIG.fadeLast
			local fade = math.clamp((age - fadeStart) / math.max(CONFIG.fadeLast, 0.001), 0, 1)
			row.frame.GroupTransparency = fade * (1 - CONFIG.minOpacity)
			shown += 1
		end
	end
	-- only the newest maxRows are visible
	local sorted = {}
	for _, row in pairs(rows) do
		table.insert(sorted, row)
	end
	table.sort(sorted, function(a, b)
		return a.frame.LayoutOrder < b.frame.LayoutOrder
	end)
	for i, row in ipairs(sorted) do
		row.frame.Visible = i <= CONFIG.maxRows
	end
	emptyLabel.Visible = shown == 0
	countLabel.Visible = (not open) and unseen > 0
	countLabel.Text = "x" .. unseen
end

-- ===================== FOLD =====================
local function setOpen(value: boolean, silent: boolean?)
	if open == value then
		return
	end
	open = value
	if open then
		unseen = 0
		list.Visible = true
		list.GroupTransparency = 1
		pop.Scale = 0.92
		TweenService:Create(list, FOLD, { GroupTransparency = 0 }):Play()
		TweenService:Create(pop, FOLD, { Scale = 1 }):Play()
		chip.Visible = false
		if not silent then
			play(CONFIG.sounds.open)
		end
	else
		chip.Visible = true
		local t = TweenService:Create(list, FOLD, { GroupTransparency = 1 })
		t.Completed:Once(function()
			if not open then
				list.Visible = false
			end
		end)
		t:Play()
		TweenService:Create(pop, FOLD, { Scale = 0.92 }):Play()
		if not silent then
			play(CONFIG.sounds.close)
		end
	end
	refresh()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if input.KeyCode == Enum.KeyCode[CONFIG.key] then
		setOpen(not open)
	end
end)

remote.OnClientEvent:Connect(function(batch)
	if type(batch) ~= "table" then
		return
	end
	for _, entry in ipairs(batch) do
		if type(entry) == "table" and type(entry.key) == "string" and type(entry.amount) == "number" then
			addGain({ key = entry.key, label = tostring(entry.label or entry.key), amount = entry.amount, color = entry.color })
		end
	end
	refresh()
end)

list.Visible = false
if CONFIG.holdOpen then
	setOpen(true, true)
end
refresh()
local clock = 0
RunService.Heartbeat:Connect(function(dt)
	clock += dt
	if clock >= 0.1 then
		clock = 0
		refresh()
	end
end)
