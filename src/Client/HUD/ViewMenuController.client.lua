--[[
	ViewMenuController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	The info rows of the hand-made StarterGui.ViewMenu > View [CanvasGroup] (bottom right): DPS, FPS, PING, SERVER, UP,
	VERSION ... as listed in ViewMenuConfig.order, stacked UPWARD above the Cursor / POV labels that CameraController
	drives. Every row is a TextLabel named by its row id inside View (placeholders built by tools/studio/build_view_rows.luau
	as copies of the Cursor label, so the layout shows in Studio and can be restyled by hand); a missing one is cloned from
	ReplicatedStorage.GUI.ViewRow. Same format as Cursor and POV: WORD — value, the dash gray (ViewMenuConfig.format).

	  U (ViewMenuConfig.toggleKey)  shows / hides all info rows (session only; POV and Cursor stay)
	  idleFade rows (DPS)           leave while their number is 0 and come back on the next non-zero
	  View.Scale (UIScale)          sized from the viewport so the widest row fits the free right quarter of the screen
	  View.Size                     grown upward to hold the rows (View is a CanvasGroup, it clips)

	The rows live inside View, so they follow its fade when a menu opens (CameraController). Desktop only: on a touch-only
	device CameraController does not show the View at all, so this script does nothing either.

	Add a row type: ViewMenuConfig (data) and, for a new kind of value, one function in PROVIDERS below.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"):WaitForChild("ViewMenuConfig")) :: any
local GameVersion = require(Modules:WaitForChild("Config"):WaitForChild("GameVersion")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MOVE = TweenInfo.new(Config.rowMove, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(Config.fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

-- ===================== VALUE PROVIDERS =====================
-- provider(row) -> value text, number (the number drives colours and idle fading; nil = no number)
local fpsFrames, fpsSince, fpsValue = 0, os.clock(), 60

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	elseif m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

local PROVIDERS: { [string]: (any) -> (string, number?) } = {
	dps = function()
		local value = player:GetAttribute(Config.dps.attribute)
		value = type(value) == "number" and value or 0
		return MoneyLib.DealWithPoints(math.floor(value)), value
	end,
	fps = function()
		return tostring(math.floor(fpsValue + 0.5)), fpsValue
	end,
	ping = function()
		local ms = math.floor(player:GetNetworkPing() * 1000 + 0.5)
		return ms .. "ms", ms
	end,
	players = function()
		local count = #Players:GetPlayers()
		return count .. "/" .. Players.MaxPlayers, count
	end,
	uptime = function()
		local start = workspace:GetAttribute("ServerStart")
		if type(start) ~= "number" then
			return "...", nil
		end
		local seconds = workspace:GetServerTimeNow() - start
		return duration(seconds), seconds
	end,
	version = function()
		return string.format("%s / v%d", GameVersion.version, game.PlaceVersion), nil
	end,
}

local function colorFor(def: any, number: number?): string
	if def.valueColors and number then
		local atLeast = def.valueColors.mode == "atLeast"
		for _, step in ipairs(def.valueColors.steps) do
			if (atLeast and number >= step[1]) or (not atLeast and number <= step[1]) then
				return step[2]
			end
		end
	end
	return def.valueColor or "#FFFF55"
end

-- ===================== ROWS =====================
local rows: { any } = {} -- { id, def, label, stroke, nextAt, text, number, idleSince, visible, y }
local group: CanvasGroup? = nil
local scaleObject: UIScale? = nil
local infoEnabled = true
local lastWidest, lastViewport, lastCount = -1, Vector2.zero, -1

local function setVisible(row: any, visible: boolean, instant: boolean?)
	if row.visible == visible and not instant then
		return
	end
	row.visible = visible
	local goal = visible and 0 or 1
	if instant then
		row.label.TextTransparency = goal
		if row.stroke then
			row.stroke.Transparency = goal
		end
		return
	end
	TweenService:Create(row.label, FADE, { TextTransparency = goal }):Play()
	if row.stroke then
		TweenService:Create(row.stroke, FADE, { Transparency = goal }):Play()
	end
end

local function refreshRow(row: any, now: number)
	local def = row.def
	local text, number = PROVIDERS[def.provider](row)
	local line = Config.format(def.word, def.wordColor, text, colorFor(def, number))
	if line ~= row.text then
		row.text = line
		row.label.Text = line
	end
	if def.idleFade then
		if number and number > 0 then
			row.idleSince = nil
		elseif not row.idleSince then
			row.idleSince = now
		end
	end
end

--- Row wanted on screen right now (the U toggle and the idle fade)?
local function wanted(row: any, now: number): boolean
	if not infoEnabled then
		return false
	end
	local idle = row.def.idleFade
	if idle and row.idleSince and now - row.idleSince >= idle.after then
		return false
	end
	return true
end

--- Stack the wanted rows upward above Cursor, fit View to them and scale it into the free right quarter.
local function layout(instant: boolean?)
	local view, scale = group, scaleObject
	if not (view and scale) then
		return
	end
	local now = os.clock()
	local count, widest = 0, 0
	for _, row in ipairs(rows) do
		local want = wanted(row, now)
		setVisible(row, want, instant)
		if want then
			count += 1
			local y = -(Config.baseHeight + count * Config.rowHeight)
			if row.y ~= y then
				row.y = y
				local goal = UDim2.new(1, 0, 1, y)
				if instant or row.placed ~= true then
					row.label.Position = goal
					row.placed = true
				else
					TweenService:Create(row.label, MOVE, { Position = goal }):Play()
				end
			end
			widest = math.max(widest, row.label.AbsoluteSize.X / math.max(scale.Scale, 0.01))
		end
	end
	view.Size = UDim2.fromOffset(math.max(Config.minWidth, math.ceil(widest) + 4), Config.baseHeight + count * Config.rowHeight)

	local camera = workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		local s = Config.scale
		local available = viewport.X * s.freeWidthFraction - s.margin
		local byWidth = widest > 0 and available / widest or s.max
		scale.Scale = math.clamp(math.min(viewport.Y / s.referenceHeight, byWidth), s.min, s.max)
		lastViewport = viewport
	end
	lastWidest, lastCount = widest, count
end

-- ===================== BINDING =====================
local function bind(gui: Instance)
	local view = gui:WaitForChild("View", 10)
	local template = ReplicatedStorage:WaitForChild("GUI", 10) and ReplicatedStorage.GUI:WaitForChild("ViewRow", 10)
	if not (view and view:IsA("CanvasGroup") and template) then
		warn("[ViewMenu] StarterGui.ViewMenu.View (CanvasGroup) or ReplicatedStorage.GUI.ViewRow is missing")
		return
	end
	local scale = view:FindFirstChildOfClass("UIScale")
	if not scale then
		warn("[ViewMenu] View needs a UIScale (run tools/studio/build_view_rows.luau)")
		return
	end

	table.clear(rows)
	group, scaleObject = view, scale

	-- keep the two hand-made labels at the bottom whatever height View grows to
	local cursor, pov = view:FindFirstChild("Cursor"), view:FindFirstChild("POV")
	if cursor and cursor:IsA("GuiObject") then
		cursor.Position = UDim2.new(1, 0, 1, -Config.baseHeight)
	end
	if pov and pov:IsA("GuiObject") then
		pov.Position = UDim2.new(1, 0, 1, -(Config.baseHeight - Config.rowHeight))
	end

	for index, id in ipairs(Config.order) do
		local def = Config.get(id)
		if def and PROVIDERS[def.provider] then
			-- the placeholder label the builder put in View (restyle it in Studio); a missing one is cloned from the template
			local label = view:FindFirstChild(id)
			if not (label and label:IsA("TextLabel")) then
				label = template:Clone()
				label.Name = id
				label.Position = UDim2.new(1, 0, 1, -Config.baseHeight)
				label.Parent = view
			end
			label.RichText = true
			label.LayoutOrder = index
			local row = {
				id = id,
				def = def,
				label = label,
				stroke = label:FindFirstChildOfClass("UIStroke"),
				nextAt = 0,
				text = "",
				visible = nil,
			}
			table.insert(rows, row)
			refreshRow(row, os.clock())
		else
			warn("[ViewMenu] unknown row or provider: " .. tostring(id))
		end
	end
	layout(true)
end

local existing = playerGui:FindFirstChild("ViewMenu")
if existing then
	task.spawn(bind, existing)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "ViewMenu" then
		task.spawn(bind, child)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or player:GetAttribute("IntroActive") or input.KeyCode ~= Config.toggleKey then
		return
	end
	infoEnabled = not infoEnabled
	layout(false)
end)

local layoutAt = 0
RunService.Heartbeat:Connect(function(dt)
	-- FPS: frames over the last half second
	fpsFrames += 1
	local now = os.clock()
	if now - fpsSince >= 0.5 then
		fpsValue = fpsFrames / (now - fpsSince)
		fpsFrames, fpsSince = 0, now
	end

	local changed = false
	for _, row in ipairs(rows) do
		if now >= row.nextAt then
			row.nextAt = now + row.def.refresh
			local before = row.text
			refreshRow(row, now)
			changed = changed or row.text ~= before
		end
		if row.def.idleFade and row.visible ~= wanted(row, now) then
			changed = true
		end
	end
	local camera = workspace.CurrentCamera
	local viewportChanged = camera ~= nil and camera.ViewportSize ~= lastViewport
	if changed or viewportChanged or now >= layoutAt then
		layoutAt = now + 0.25 -- widths settle one frame after the text, so re-measure a little later too
		layout(false)
	end
end)
