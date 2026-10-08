--[[
	ScoreboardController (LocalScript)
	Place inside: StarterPlayerScripts

	Drives StarterGui.FIAScoreboard.Panel (built by tools/studio/build_scoreboard.luau): the right-side scoreboard. Lines, zones and
	colours are data in Modules/Config/ScoreboardConfig; the calendar in ClockConfig. Visual only: it READS the player attributes
	Coins (WalletService), Zone (ZoneManager) and Objective, the workspace attributes Day / Month / Season (ClockService) and the
	server clock. Lines are cloned from Panel.Template (never built in code); a line is only rewritten when its text changed.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config")
local ScoreboardConfig = require(Config:WaitForChild("ScoreboardConfig")) :: any
local ClockConfig = require(Config:WaitForChild("ClockConfig")) :: any

if not ScoreboardConfig.enabled then
	return
end

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FIAScoreboard")
local panel = gui:WaitForChild("Panel") :: Frame
local linesFrame = panel:WaitForChild("Board"):WaitForChild("Lines") :: Frame
local template = panel:WaitForChild("Template") :: Frame
local scale = panel:WaitForChild("Scale") :: UIScale
local LAYOUT = ScoreboardConfig.layout

local rendered: { any } = {} -- { frame, label, def, text, spacer }
local builtFor: string? = nil
local lastCoins: number? = nil

-- ===================== LAYOUT =====================
local function applyLayout()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local s = math.clamp(camera.ViewportSize.Y / LAYOUT.baseHeight, LAYOUT.minScale, LAYOUT.maxScale)
	scale.Scale = s
	panel.AnchorPoint = Vector2.new(1, LAYOUT.anchorY)
	panel.Position = UDim2.new(1, -math.floor(LAYOUT.rightMargin * s), LAYOUT.yScale, 0)
	panel.Size = UDim2.fromOffset(LAYOUT.width, 0)
	linesFrame.BackgroundTransparency = LAYOUT.bodyTransparency
	panel.Board.BackgroundTransparency = LAYOUT.borderTransparency
end

-- ===================== VALUES =====================
local function commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function zonePlayers(zoneKey: string?): number
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("Zone") == zoneKey then
			n += 1
		end
	end
	return n
end

local function values(zoneKey: string?, zone: any): { [string]: string }
	local now = ClockConfig.at(workspace:GetServerTimeNow())
	local day = workspace:GetAttribute("Day") or now.day
	local month = workspace:GetAttribute("Month") or now.month
	local season = workspace:GetAttribute("Season") or now.season
	local jobId = game.JobId
	local server = jobId == "" and "LOCAL" or jobId:sub(1, ScoreboardConfig.serverIdLength):upper()
	return {
		fontValue = ScoreboardConfig.fonts.value,
		date = os.date("%m/%d/%y"),
		server = "s-" .. server,
		calendar = ("%s %s %s"):format(month, season, ClockConfig.ordinal(day)),
		time = ("%d:%02d%s"):format(now.hour12, now.minute, now.ampm),
		zone = zone.name,
		zoneColor = zone.color,
		zonePlayers = tostring(zonePlayers(zoneKey)),
		coins = commas(player:GetAttribute("Coins") or 0),
		objective = player:GetAttribute("Objective") or ScoreboardConfig.defaultObjective or "",
	}
end

-- ===================== BUILD =====================
local function clearLines()
	for _, line in ipairs(rendered) do
		line.frame:Destroy()
	end
	table.clear(rendered)
end

local function build(zoneKey: string?)
	clearLines()
	local key = ScoreboardConfig.zone(zoneKey)
	for i, spec in ipairs(ScoreboardConfig.linesFor(zoneKey)) do
		local frame = template:Clone()
		frame.Name = spec.id
		frame.LayoutOrder = i
		frame.Visible = true
		local label = frame:WaitForChild("Text") :: TextLabel
		if spec.spacer then
			frame.AutomaticSize = Enum.AutomaticSize.None
			frame.Size = UDim2.new(1, 0, 0, LAYOUT.spacerHeight)
			label.Visible = false
		else
			label.TextSize = LAYOUT.textSize
			label.TextXAlignment = spec.def.center and Enum.TextXAlignment.Center or Enum.TextXAlignment.Left
		end
		frame.Parent = linesFrame
		table.insert(rendered, { frame = frame, label = label, def = spec.def, spacer = spec.spacer, text = nil })
	end
	builtFor = key
end

local function refresh()
	local rawKey = player:GetAttribute("Zone")
	local key, zone = ScoreboardConfig.zone(rawKey)
	if key ~= builtFor then
		build(rawKey)
	end
	local v = values(rawKey, zone)
	for _, line in ipairs(rendered) do
		if not line.spacer then
			local def = line.def
			local shown = true
			if def.when and (v[def.when] == nil or v[def.when] == "") then
				shown = false
			end
			if line.frame.Visible ~= shown then
				line.frame.Visible = shown
			end
			if shown then
				local text = def.format:gsub("{(%w+)}", function(token)
					return v[token] or ""
				end)
				if text ~= line.text then
					line.text = text
					line.label.Text = text
				end
			end
		end
	end
end

-- the Purse line pulses when the balance changes
local function flashPurse(coins: number)
	if lastCoins ~= nil and coins ~= lastCoins then
		for _, line in ipairs(rendered) do
			if line.def and line.def.flashOnChange then
				line.label.TextTransparency = 0.7
				TweenService:Create(line.label, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
			end
		end
	end
	lastCoins = coins
end

-- ===================== WIRING =====================
applyLayout()
local camera = workspace.CurrentCamera
if camera then
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	applyLayout()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end)

player:GetAttributeChangedSignal("Zone"):Connect(refresh)
player:GetAttributeChangedSignal("Objective"):Connect(refresh)
player:GetAttributeChangedSignal("Coins"):Connect(function()
	refresh()
	flashPurse(player:GetAttribute("Coins") or 0)
end)

refresh()
lastCoins = player:GetAttribute("Coins") or 0
local clock = 0
RunService.Heartbeat:Connect(function(dt)
	clock += dt
	if clock >= LAYOUT.refreshEvery then
		clock = 0
		refresh()
	end
end)
