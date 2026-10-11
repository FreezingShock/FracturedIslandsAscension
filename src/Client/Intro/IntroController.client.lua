--[[
	IntroController (LocalScript)
	Place inside: StarterPlayerScripts > Client > Intro

	Runs the loading screen that IntroLoader (ReplicatedFirst) put in PlayerGui. Everything tunable is in
	Config/LoadingConfig; the names it looks up are listed in that file's header.

	  TOUR      the camera (Scriptable, locked) flies each shot along a smooth path over real ground. Each shot
	            waits for its surroundings to stream in, then fades in, moves, and fades out to the next. Captions name
	            the place. Hold click on the empty screen to jump to the last shot.
	  PRELOAD   combat animations and sounds (CombatConfig) plus LoadingConfig.preload are loaded. The bar fills,
	            Play unlocks at 100%. A stalled preload unlocks Play after stallTimeout with a warning.
	  MENUS     LoadingConfig.menus open as slide-in panels. One panel at a time; clicking the open button closes it.
	  PLAY      letterbox away, the camera glides from the tour's last frame to your character's eyes, the world's
	            sounds fade back in, the overlay fades out, and the server is told the intro is over (IntroDone).

	While IntroActive is true every key and mouse button is sunk (ContextActionService), CameraController and the
	input controllers ignore input, and the world's sounds are muted (each Sound's Volume, restored on the handover). The server's join shield
	(IntroService) keeps enemies from hurting you until IntroDone.
]]

local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = Modules:WaitForChild("Config")
local LoadingConfig = require(Config:WaitForChild("LoadingConfig")) :: any
local GameVersion = require(Config:WaitForChild("GameVersion")) :: any
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any

local screen = playerGui:WaitForChild("IntroScreen", 10)
if not (screen and screen:IsA("ScreenGui")) then
	player:SetAttribute("IntroActive", false)
	return
end

local TIMINGS = LoadingConfig.timings
local CAMERA_STEP = "FIAIntroCamera"
local SINK_ACTION = "FIAIntroSink"
local FIRST_PERSON_FOV = 100 -- CameraController's first-person field of view: the handover lands on it
local introDone = ReplicatedStorage:WaitForChild("IntroDone", 10)

-- ===================== UI (by name) =====================
local ui = {
	fade = screen:FindFirstChild("Fade", true),
	letterTop = screen:FindFirstChild("LetterTop", true),
	letterBottom = screen:FindFirstChild("LetterBottom", true),
	overlay = screen:FindFirstChild("Overlay", true),
	skipSurface = screen:FindFirstChild("SkipSurface", true),
	skipRing = screen:FindFirstChild("SkipRing", true),
	skipFill = nil :: any,
	titleMain = screen:FindFirstChild("Main", true),
	titleSub = screen:FindFirstChild("Sub", true),
	caption = screen:FindFirstChild("Caption", true),
	captionName = nil :: any,
	captionIndex = nil :: any,
	tip = screen:FindFirstChild("Tip", true),
	status = screen:FindFirstChild("StatusLabel", true),
	progressFill = nil :: any,
	playButton = screen:FindFirstChild("PlayButton", true),
	menuBar = screen:FindFirstChild("MenuBar", true),
	menuPanel = screen:FindFirstChild("MenuPanel", true),
	templates = screen:FindFirstChild("Templates", true),
}
do
	local bar = screen:FindFirstChild("ProgressBar", true)
	ui.progressFill = bar and bar:FindFirstChild("Fill")
	local ring = ui.skipRing
	ui.skipFill = ring and ring:FindFirstChild("Fill")
	if ui.caption then
		ui.captionName = ui.caption:FindFirstChild("Name", true)
		ui.captionIndex = ui.caption:FindFirstChild("Index", true)
	end
end

-- ===================== SETTINGS (session only) =====================
local settingDefs: { [string]: any } = {}
local settings: { [string]: any } = {}
for _, def in ipairs(LoadingConfig.settings) do
	settingDefs[def.key] = def
	settings[def.key] = def.default
end

local function cycleSetting(key: string)
	local def = settingDefs[key]
	if not def then
		return
	end
	if def.kind == "toggle" then
		settings[key] = not settings[key]
	elseif def.kind == "cycle" then
		local index = table.find(def.values, settings[key]) or 1
		settings[key] = def.values[(index % #def.values) + 1]
	end
end

local function tourSpeed(): number
	return math.max(tonumber(settings.speed) or 1, 0.1)
end

-- ===================== STATE =====================
local state = "LOADING"
local progress = 0
local expected = 1
local completed = 0
local startTime = os.clock()
local nextRequested = false -- a click on the caption or a full hold on SkipSurface: go to the next scene now
local manualNext = false -- that transition is manual, so the buttons tween out and back in
local leaving = false -- Play pressed: the tour stops and the handover takes the camera
local tourDone = false
local holdStart: number? = nil
local hidden: { [ScreenGui]: boolean } = {} -- ScreenGuis switched off for the intro, put back on DONE
local shots: { any } = {}
local live = { shot = nil :: any, alpha = 0, handover = nil :: any }
local music: Sound? = nil
local mutedSounds: { [Sound]: number } = {} -- world sound -> its own volume, restored on the handover
local muteWatch: RBXScriptConnection? = nil
local locationCursor = 0
local menuButtons: { [string]: GuiButton } = {}
local menuModules: { [string]: any } = {}
local initialised: { [any]: boolean } = {}
local openKey: string? = nil
local loops: { Tween } = {} -- repeating tweens (shimmer, Play pulse), stopped on DONE

local function setState(newState: string)
	state = newState
	player:SetAttribute("IntroState", newState)
end

local function playSound(id: string)
	if id == "" then
		return
	end
	local sound = Instance.new("Sound") -- a sound, not GUI
	sound.SoundId = id
	sound.Parent = screen
	sound:Play()
	Debris:AddItem(sound, 8)
end

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?): Tween
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- ===================== PROGRESS & PLAY =====================
-- Minecraft colour pairs (bright on top, the shade below); paint() sets a button's fill and its gradient together
local CODE = {
	gold = { Color3.fromHex("#FFAA00"), Color3.fromHex("#AA5500") }, -- &6
	green = { Color3.fromHex("#55FF55"), Color3.fromHex("#00AA00") }, -- &a / &2
	aqua = { Color3.fromHex("#55FFFF"), Color3.fromHex("#00AAAA") }, -- &b / &3
	red = { Color3.fromHex("#FF5555"), Color3.fromHex("#AA0000") }, -- &c / &4
	gray = { Color3.fromHex("#AAAAAA"), Color3.fromHex("#555555") }, -- &7 / &8
	purple = { Color3.fromHex("#FF55FF"), Color3.fromHex("#AA00AA") }, -- &d / &5
	blue = { Color3.fromHex("#5555FF"), Color3.fromHex("#0000AA") }, -- &9 / &1
	yellow = { Color3.fromHex("#FFFF55"), Color3.fromHex("#AAAA00") }, -- &e
}

local function paint(target: GuiObject?, pair: { Color3 })
	if not target then
		return
	end
	target.BackgroundColor3 = pair[1]
	local gradient = target:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Color = ColorSequence.new(pair[1], pair[2])
	end
end

local function refreshUi()
	if ui.progressFill then
		tween(ui.progressFill, 0.25, { Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1) })
	end
	if ui.status then
		ui.status.Text = progress >= 1 and "READY" or string.format("LOADING  %d%%", math.floor(progress * 100))
	end
	local button = ui.playButton
	if button and button:IsA("TextButton") then
		local ready = state == "READY"
		button.Active = ready
		button.Text = ready and "PLAY" or "LOADING..."
		paint(button, ready and CODE.green or CODE.gray)
	end
end

local function startPulse()
	local outline = ui.playButton and ui.playButton:FindFirstChildOfClass("UIStroke")
	if outline and not settings.reduceMotion then
		local pulse = TweenService:Create(outline, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 5 })
		pulse:Play()
		table.insert(loops, pulse)
	end
end

local function checkReady()
	if state == "LOADING" and progress >= 1 and os.clock() - startTime >= TIMINGS.minLoadTime then
		setState("READY")
		refreshUi()
		startPulse()
	end
end

local function setProgress(value: number)
	progress = math.clamp(value, 0, 1)
	player:SetAttribute("IntroProgress", progress)
	refreshUi()
	checkReady()
end

local function addDone(count: number)
	completed += count
	setProgress(completed / math.max(expected, 1))
end

-- ===================== PRELOAD =====================
local function collectAssets(): { Instance }
	local list: { Instance } = {}
	local seen: { [string]: boolean } = {}
	local function add(id: any, className: string, property: string)
		if typeof(id) ~= "string" or id == "" or seen[id] then
			return
		end
		seen[id] = true
		local instance = Instance.new(className) -- preload handles only, never shown
		;(instance :: any)[property] = id
		table.insert(list, instance)
	end
	for _, anim in pairs(CombatConfig.animations or {}) do
		add(anim.id, "Animation", "AnimationId")
	end
	for _, sound in pairs(CombatConfig.sounds or {}) do
		add(sound.id, "Sound", "SoundId")
	end
	for _, id in ipairs(LoadingConfig.preload.extraIds) do
		add(id, "Decal", "Texture")
	end
	for _, id in pairs(LoadingConfig.sounds) do
		add(id, "Sound", "SoundId")
	end
	return list
end

-- ===================== TOUR SHOTS =====================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function groundAt(x: number, z: number): Vector3?
	rayParams.FilterDescendantsInstances = if player.Character then { player.Character } else {}
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), rayParams)
	if hit and hit.Normal.Y > 0.5 and hit.Position.Y >= LoadingConfig.shots.minGroundY then
		return hit.Position
	end
	return nil
end

local function randomSpot(): Vector3?
	local area = LoadingConfig.area
	for _ = 1, LoadingConfig.shots.tries do
		local x = area.min.X + math.random() * (area.max.X - area.min.X)
		local z = area.min.Z + math.random() * (area.max.Z - area.min.Z)
		local spot = groundAt(x, z)
		if spot then
			return spot
		end
	end
	return nil
end

local function nextLocation(): string
	local list = LoadingConfig.locations
	if #list == 0 then
		return ""
	end
	locationCursor += 1
	return list[((locationCursor - 1) % #list) + 1]
end

-- library (LoadingConfig.shot) -> scene overrides -> this shot
local function buildShot(spot: Vector3, overrides: { [string]: any }?, name: string): any
	local o = table.clone(LoadingConfig.shot)
	for key, value in pairs(overrides or {}) do
		o[key] = value
	end
	local startAngle = math.random() * math.pi * 2
	local sweep = o.sweep * (if math.random() < 0.5 then 1 else -1)
	local height = o.heightMin + math.random() * (o.heightMax - o.heightMin)
	local count = math.max(2, o.points)
	local points: { Vector3 } = {}
	for i = 1, count do
		local angle = startAngle + sweep * ((i - 1) / (count - 1))
		points[i] = spot + Vector3.new(math.cos(angle) * o.radius, height, math.sin(angle) * o.radius)
	end
	return {
		name = name,
		center = spot,
		points = points,
		target = spot + Vector3.new(0, o.lookHeight, 0),
		duration = o.duration,
		fade = o.fade,
		easing = o.easing,
		fov = o.fov,
	}
end

-- Catmull-Rom through the path points, so the camera glides through each one with no corners. t runs 0..1.
local function pathPoint(points: { Vector3 }, t: number): Vector3
	local n = #points
	if n == 1 then
		return points[1]
	end
	local seg = math.clamp(t, 0, 1) * (n - 1)
	local i = math.min(math.floor(seg), n - 2) -- 0-based segment
	local u = seg - i
	local p0 = points[math.max(i, 1)]
	local p1 = points[i + 1]
	local p2 = points[i + 2]
	local p3 = points[math.min(i + 3, n)]
	return 0.5
		* ((p1 * 2) + (p2 - p0) * u + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * (u * u) + (p3 - p0 + (p1 - p2) * 3) * (u * u * u))
end

-- A hand-placed scene: scene.cameras = { { pos = Vector3, look = Vector3 }, ... } flies the camera through the
-- positions in order, turning from each look target to the next. Its first position is where it streams first.
local function buildHandShot(scene: any): any
	local o = table.clone(LoadingConfig.shot)
	for key, value in pairs(scene.overrides or {}) do
		o[key] = value
	end
	local points: { Vector3 } = {}
	local looks: { Vector3 } = {}
	for i, camera in ipairs(scene.cameras) do
		points[i] = camera.pos
		looks[i] = camera.look
	end
	return {
		name = scene.name or nextLocation(),
		center = points[1],
		points = points,
		looks = looks,
		target = looks[1],
		duration = o.duration,
		fade = o.fade,
		easing = o.easing,
		fov = o.fov,
	}
end

local function buildTour(): { any }
	local list = {}
	for _, scene in ipairs(LoadingConfig.scenes) do
		if scene.cameras and #scene.cameras > 0 then
			table.insert(list, buildHandShot(scene))
		else
			local spot = scene.spot or randomSpot()
			if spot then
				table.insert(list, buildShot(spot, scene.overrides, scene.name or nextLocation()))
			end
		end
	end
	local wanted = math.random(LoadingConfig.shots.min, LoadingConfig.shots.max)
	for _ = 1, wanted do
		local spot = randomSpot()
		if spot then
			table.insert(list, buildShot(spot, nil, nextLocation()))
		end
	end
	if #list == 0 then
		-- no ground found in the box: tour the character's own spot instead of showing nothing
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			table.insert(list, buildShot(root.Position, nil, "Spawn"))
		end
	end
	return list
end

-- ===================== CAMERA =====================
-- One render step owns the camera while the intro is up: the tour's shot, then the handover to the player's eyes.
RunService:BindToRenderStep(CAMERA_STEP, Enum.RenderPriority.Camera.Value + 1, function()
	local cam = workspace.CurrentCamera
	if not cam or state == "DONE" then
		return
	end
	cam.CameraType = Enum.CameraType.Scriptable
	local handover = live.handover
	if handover then
		local t = math.clamp((os.clock() - handover.started) / handover.duration, 0, 1)
		local a = TweenService:GetValue(t, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		local character = player.Character
		local head = character and character:FindFirstChild("Head") :: BasePart?
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local target = handover.from
		if head and root then
			target = CFrame.lookAt(head.Position, head.Position + root.CFrame.LookVector)
		end
		cam.CFrame = handover.from:Lerp(target, a)
		cam.FieldOfView = handover.fovFrom + (FIRST_PERSON_FOV - handover.fovFrom) * a
		return
	end
	local shot = live.shot
	if not shot then
		return
	end
	local eased = TweenService:GetValue(math.clamp(live.alpha, 0, 1), shot.easing, Enum.EasingDirection.InOut)
	local look = if shot.looks then pathPoint(shot.looks, eased) else shot.target
	cam.CFrame = CFrame.lookAt(pathPoint(shot.points, eased), look)
	cam.FieldOfView = shot.fov
end)

local function fadeTo(opacity: number, seconds: number)
	if ui.fade then
		tween(ui.fade, seconds, { BackgroundTransparency = 1 - opacity }, Enum.EasingStyle.Sine)
	end
end

local function setLetterbox(on: boolean)
	local seconds = settings.reduceMotion and 0 or TIMINGS.letterbox
	if ui.letterTop then
		tween(ui.letterTop, seconds, { Position = if on then UDim2.new(0, 0, 0, 0) else UDim2.new(0, 0, -0.12, 0) }, Enum.EasingStyle.Quint)
	end
	if ui.letterBottom then
		tween(ui.letterBottom, seconds, { Position = if on then UDim2.new(0, 0, 1, 0) else UDim2.new(0, 0, 1.12, 0) }, Enum.EasingStyle.Quint)
	end
end

local function showCaption(shot: any, index: number, count: number)
	if not ui.caption then
		return
	end
	ui.caption.Visible = settings.captions ~= false
	if ui.captionName and ui.captionName:IsA("TextLabel") then
		ui.captionName.Text = shot.name
		ui.captionName.MaxVisibleGraphemes = 0
		tween(ui.captionName, 0.9, { MaxVisibleGraphemes = #shot.name }, Enum.EasingStyle.Linear)
	end
	if ui.captionIndex and ui.captionIndex:IsA("TextLabel") then
		ui.captionIndex.Text = string.format("%02d / %02d", index, count)
	end
end

-- Moves the camera along one shot's path. Returns early when the next scene is requested or Play is pressed.
local function moveAlong(shot: any)
	local duration = shot.duration / tourSpeed()
	local started = os.clock()
	while not (nextRequested or leaving) do
		local t = (os.clock() - started) / duration
		if t >= 1 then
			live.alpha = 1
			return
		end
		live.alpha = t
		RunService.RenderStepped:Wait()
	end
end

-- The scene box (the caption plate) shrinks in when clicked and springs back out on the new scene.
local function tweenCaption(show: boolean)
	local caption = ui.caption
	local scale = caption and caption:FindFirstChild("Scale")
	if not (scale and scale:IsA("UIScale")) then
		return
	end
	if show then
		tween(scale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		tween(scale, 0.18, { Scale = 0.86 }, Enum.EasingStyle.Quint)
	end
end

-- a click on the caption, or a full hold on SkipSurface: the tour moves on to the next scene
local function requestNext()
	if tourDone or leaving or state == "ENTERING" or state == "DONE" then
		return
	end
	nextRequested = true
	manualNext = true
end

-- Streams one shot's surroundings in (StreamingEnabled: far terrain is empty until it arrives). Runs ahead of the tour
-- so every shot is ready by the time it plays; each shot counts once toward the preload bar.
local function streamShot(shot: any)
	pcall(function()
		player:RequestStreamAroundAsync(shot.center, TIMINGS.streamTimeout)
	end)
	shot.ready = true
	addDone(1)
end

local function streamAll()
	for _, shot in ipairs(shots) do
		streamShot(shot)
	end
end

-- The tour loops: after the last scene it starts again from the first.
local function runTour()
	local count = #shots
	if count == 0 then
		tourDone = true
		return
	end
	local index = 0
	while not leaving do
		index = index % count + 1
		local shot = shots[index]
		-- wait (briefly) for this shot's streaming, so the frames are not empty terrain
		local waitStart = os.clock()
		while not shot.ready and os.clock() - waitStart < TIMINGS.streamTimeout do
			task.wait(0.1)
		end
		live.shot = shot
		live.alpha = 0
		player:SetAttribute("IntroScene", index)
		showCaption(shot, index, count)
		if manualNext then
			tweenCaption(true)
		end
		fadeTo(0, if manualNext then 0.35 else shot.fade) -- from black into the shot while the camera starts moving
		manualNext = false
		nextRequested = false
		moveAlong(shot)
		if leaving then
			break
		end
		-- out: a manual change is quick and takes the buttons with it; an automatic one fades slowly
		if nextRequested then
			manualNext = true
		end
		fadeTo(1, if manualNext then 0.3 else shot.fade)
		if manualNext then
			tweenCaption(false)
			task.wait(0.2)
		else
			task.wait(shot.fade)
		end
		nextRequested = false
	end
	tourDone = true
end

-- ===================== INPUT =====================
-- Sink every key and mouse button while the intro is up: movement, abilities and menu keys stay quiet.
local SINK_INPUTS: { any } = { Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3 }
for _, key in ipairs(Enum.KeyCode:GetEnumItems()) do
	if key ~= Enum.KeyCode.Unknown then
		table.insert(SINK_INPUTS, key)
	end
end
ContextActionService:BindActionAtPriority(SINK_ACTION, function()
	return Enum.ContextActionResult.Sink
end, false, Enum.ContextActionPriority.High.Value, table.unpack(SINK_INPUTS))

local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

if ui.skipSurface then
	ui.skipSurface.Active = true
	ui.skipSurface.InputBegan:Connect(function(input)
		if isPress(input) and not tourDone and not nextRequested and not leaving and holdStart == nil then
			holdStart = os.clock()
			if ui.skipRing then
				ui.skipRing.Visible = true
			end
		end
	end)
end
UserInputService.InputEnded:Connect(function(input)
	if isPress(input) then
		holdStart = nil
		if ui.skipRing then
			ui.skipRing.Visible = false
		end
	end
end)

local hit = ui.caption and ui.caption:FindFirstChild("Hit")
if hit and hit:IsA("GuiButton") then
	hit.Activated:Connect(requestNext)
end

local holdConnection = RunService.Heartbeat:Connect(function()
	if not holdStart then
		return
	end
	local held = (os.clock() - holdStart) / TIMINGS.skipHold
	if ui.skipFill then
		ui.skipFill.Size = UDim2.fromScale(math.clamp(held, 0, 1), 1)
	end
	if held >= 1 then
		holdStart = nil
		requestNext()
		if ui.skipRing then
			ui.skipRing.Visible = false
		end
	end
end)

-- ===================== GAMEPLAY GUI =====================
-- Every other ScreenGui (HUD, notifications, scoreboard, menus), including ones scripts add later, is switched off
-- for the intro, and only the ones that were on are put back on Play. CoreGui stays off for good: the game has its own.
local function holdGui(gui: Instance)
	if gui == screen or not gui:IsA("ScreenGui") then
		return
	end
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if state ~= "DONE" and gui.Enabled then
			hidden[gui] = true
			gui.Enabled = false
		end
	end)
	if gui.Enabled then
		hidden[gui] = true
		gui.Enabled = false
	end
end
for _, child in ipairs(playerGui:GetChildren()) do
	holdGui(child)
end
playerGui.ChildAdded:Connect(holdGui)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

-- ===================== MENUS =====================
local shared: any = {
	templates = ui.templates,
	getSetting = function(key: string)
		return settings[key]
	end,
	cycleSetting = cycleSetting,
}

local function resolveRows(rows: any): { any }
	if rows == "settings" then
		local list = {}
		for _, def in ipairs(LoadingConfig.settings) do
			table.insert(list, { kind = def.kind, key = def.key, label = def.label, suffix = def.suffix })
		end
		return list
	elseif rows == "changelog" then
		local list = { { kind = "heading", text = `Version {GameVersion.version}  -  {GameVersion.date}` } }
		table.insert(list, { kind = "text", text = GameVersion.commit })
		for _, group in ipairs({ { "Added", GameVersion.summary.added }, { "Changed", GameVersion.summary.changed }, { "Fixed", GameVersion.summary.fixed } }) do
			if #group[2] > 0 then
				table.insert(list, { kind = "heading", text = group[1] })
				for _, line in ipairs(group[2]) do
					table.insert(list, { kind = "text", text = "- " .. line })
				end
			end
		end
		return list
	end
	return rows or {}
end

local function setActiveButton(key: string?)
	for buttonKey, button in pairs(menuButtons) do
		-- every menu keeps its own colour (set at creation); the open one shows the accent bar
		local accent = button:FindFirstChild("Accent")
		if accent and accent:IsA("GuiObject") then
			accent.Visible = buttonKey == key
		end
	end
end

local function closeMenu()
	if not openKey then
		return
	end
	local mod = menuModules[openKey]
	openKey = nil
	if mod then
		mod.close()
	end
	setActiveButton(nil)
end
shared.closeMenu = closeMenu

-- clicking the open menu's button closes it; clicking another one swaps the panel
local function toggleMenu(entry: any)
	if openKey == entry.key then
		closeMenu()
		return
	end
	local mod = menuModules[entry.key]
	if not mod then
		return
	end
	if openKey then
		menuModules[openKey].reset()
	end
	openKey = entry.key
	setActiveButton(entry.key)
	mod.open({ title = entry.title or entry.label, rows = resolveRows(entry.rows) })
	playSound(LoadingConfig.sounds.click)
end

local function hoverScale(button: GuiButton, target: number)
	local scale = button:FindFirstChild("Scale")
	if scale and scale:IsA("UIScale") then
		tween(scale, 0.2, { Scale = target }, Enum.EasingStyle.Back)
	end
end

for _, entry in ipairs(LoadingConfig.menus) do
	local ok, mod = pcall(function()
		return require(Modules:WaitForChild(entry.module, 5))
	end)
	local template = ui.templates and ui.templates:FindFirstChild("MenuButton")
	if not ok or not ui.menuPanel then
		warn(`[IntroController] menu "{entry.key}" unavailable: {tostring(mod)}`)
	else
		if not initialised[mod] then
			initialised[mod] = true
			mod.init(shared, ui.menuPanel)
		end
		menuModules[entry.key] = mod
		if template and template:IsA("GuiButton") and ui.menuBar then
			local button = template:Clone()
			button.Name = entry.key
			button.Text = entry.label
			button.Visible = true
			button.Parent = ui.menuBar
			menuButtons[entry.key] = button
			paint(button, CODE[entry.color or "aqua"] or CODE.aqua)
			button.MouseEnter:Connect(function()
				hoverScale(button, 1.06)
				playSound(LoadingConfig.sounds.hover)
			end)
			button.MouseLeave:Connect(function()
				hoverScale(button, 1)
			end)
			button.Activated:Connect(function()
				hoverScale(button, 0.94)
				task.delay(0.12, function()
					hoverScale(button, 1.06)
				end)
				toggleMenu(entry)
			end)
		end
	end
end

-- ===================== TIPS & TITLE =====================
local function startTips()
	local tip = ui.tip
	local tips = LoadingConfig.tips
	if not (tip and tip:IsA("TextLabel")) or #tips == 0 then
		return
	end
	task.spawn(function()
		local index = 1
		while state ~= "DONE" do
			tip.Text = tips[index]
			tween(tip, 0.5, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
			task.wait(TIMINGS.tipEvery)
			if state == "DONE" then
				break
			end
			tween(tip, 0.4, { TextTransparency = 1 }, Enum.EasingStyle.Sine)
			task.wait(0.45)
			index = index % #tips + 1
		end
	end)
end

local function animateTitle()
	local main = ui.titleMain
	if main and main:IsA("GuiObject") and not settings.reduceMotion then
		local target = main.Position
		main.Position = target - UDim2.fromScale(0, 0.12)
		tween(main, 1.1, { Position = target }, Enum.EasingStyle.Back)
	end
	local sub = ui.titleSub
	if sub and sub:IsA("TextLabel") then
		sub.TextTransparency = 1
		task.delay(0.6, function()
			tween(sub, 0.9, { TextTransparency = 0 }, Enum.EasingStyle.Sine)
		end)
	end
end

local function startShimmer()
	local fill = ui.progressFill
	local gradient = fill and fill:FindFirstChild("Shimmer")
	if gradient and not settings.reduceMotion then
		local shimmer = TweenService:Create(gradient, TweenInfo.new(1.4, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Offset = Vector2.new(1, 0) })
		shimmer:Play()
		table.insert(loops, shimmer)
	end
end

-- ===================== PLAY =====================
local function finish()
	setState("DONE")
	RunService:UnbindFromRenderStep(CAMERA_STEP)
	ContextActionService:UnbindAction(SINK_ACTION)
	holdConnection:Disconnect()
	for _, loop in ipairs(loops) do
		loop:Cancel()
	end
	if music then
		music:Stop()
	end
	for gui in pairs(hidden) do
		if gui.Parent then
			gui.Enabled = true
		end
	end
	hidden = {}
	player:SetAttribute("IntroActive", false)
	if introDone and introDone:IsA("RemoteEvent") then
		introDone:FireServer()
	end
	screen:Destroy()
end

local function enter()
	if state ~= "READY" then
		return
	end
	setState("ENTERING")
	leaving = true
	if ui.playButton then
		ui.playButton.Active = false
	end
	closeMenu()
	playSound(LoadingConfig.sounds.play)
	playSound(LoadingConfig.sounds.click)
	setLetterbox(false)
	fadeTo(0, 0.4) -- clear any black still up from the tour

	local cam = workspace.CurrentCamera
	local seconds = TIMINGS.handover
	live.handover = {
		from = cam and cam.CFrame or CFrame.new(),
		fovFrom = cam and cam.FieldOfView or 70,
		started = os.clock(),
		duration = seconds,
	}
	-- the world's sounds were muted for the tour: bring them back as the camera lands
	if muteWatch then
		muteWatch:Disconnect()
		muteWatch = nil
	end
	for sound, volume in pairs(mutedSounds) do
		if sound.Parent then
			tween(sound, seconds, { Volume = volume }, Enum.EasingStyle.Sine)
		end
	end
	mutedSounds = {}
	if ui.overlay and ui.overlay:IsA("CanvasGroup") then
		tween(ui.overlay, seconds * 0.6, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
	end
	task.delay(seconds, finish)
end

if ui.playButton and ui.playButton:IsA("GuiButton") then
	ui.playButton.MouseEnter:Connect(function()
		if state == "READY" then
			hoverScale(ui.playButton :: GuiButton, 1.08)
			playSound(LoadingConfig.sounds.hover)
		end
	end)
	ui.playButton.MouseLeave:Connect(function()
		hoverScale(ui.playButton :: GuiButton, 1)
	end)
	ui.playButton.Activated:Connect(enter)
end

-- ===================== START =====================
player:SetAttribute("IntroActive", true)
setState("LOADING")
player:SetAttribute("IntroProgress", 0)
setLetterbox(true)
animateTitle()
startTips()
startShimmer()
refreshUi()

if LoadingConfig.sounds.music ~= "" then
	local sound = Instance.new("Sound")
	sound.SoundId = LoadingConfig.sounds.music
	sound.Looped = true
	sound.Parent = screen
	sound:Play()
	music = sound
end
-- the world's sounds stay silent until Play (SoundService has no master volume, so each Sound is muted and remembered)
local function muteSound(sound: Sound)
	if sound:IsDescendantOf(screen) or mutedSounds[sound] ~= nil then
		return
	end
	mutedSounds[sound] = sound.Volume
	sound.Volume = 0
end
for _, descendant in ipairs(game:GetDescendants()) do
	if descendant:IsA("Sound") then
		muteSound(descendant)
	end
end
muteWatch = game.DescendantAdded:Connect(function(descendant)
	if state ~= "DONE" and descendant:IsA("Sound") then
		muteSound(descendant)
	end
end)

local assets = collectAssets()
-- progress: the assets, then one step for the tour being built, then one per shot streamed in
expected = #assets + 1

-- StreamingEnabled: at join the terrain around the map is not on the client yet, so the raycasts for spots find
-- nothing. Stream the map box first, then build the tour, retrying while the world is still arriving.
task.spawn(function()
	local area = LoadingConfig.area
	local centre = (area.min + area.max) / 2
	pcall(function()
		player:RequestStreamAroundAsync(Vector3.new(centre.X, 100, centre.Z), TIMINGS.streamTimeout)
	end)
	for _ = 1, 15 do
		local ok, result = pcall(buildTour)
		if ok and #result > 0 then
			shots = result
			break
		end
		if not ok then
			warn("[IntroController] tour could not be built: " .. tostring(result))
			break
		end
		task.wait(1)
	end
	if #shots == 0 then
		warn("[IntroController] no tour shots found: the cutscene is skipped")
	end
	expected += #shots
	addDone(1)
	if #shots == 0 then
		tourDone = true
		return
	end
	task.spawn(streamAll)
	local ok, err = xpcall(runTour, debug.traceback)
	if not ok then
		warn("[IntroController] tour failed: " .. tostring(err))
		tourDone = true
	end
end)

task.spawn(function()
	if #assets > 0 then
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(assets, function()
				addDone(1)
			end)
		end)
		if not ok then
			warn("[IntroController] preload error: " .. tostring(err))
		end
	end
	for _, asset in ipairs(assets) do
		asset:Destroy()
	end
end)

-- a stalled preload must not lock Play forever: after stallTimeout, unlock with a warning
task.delay(TIMINGS.stallTimeout, function()
	if progress < 1 then
		warn("[IntroController] preload stalled after " .. TIMINGS.stallTimeout .. "s: unlocking Play")
		completed = expected
		setProgress(1)
	end
end)
task.delay(TIMINGS.minLoadTime, checkReady)
