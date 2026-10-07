--[[
	ActionBarClient (ModuleScript, Client)
	Place inside: StarterPlayerScripts   (started by ActionBarController)

	The ACTION BAR: the centered pixel-font line above the hotbar name row, StarterGui.FIAHUD.Root.ActionBar
	(CanvasGroup) > Label + Sub (built by tools/studio/build_actionbar.luau, restyle freely, names are what the code binds).
	Every number, colour and timing is Modules/Config/ActionBarConfig. The server decides WHAT to show (ActionBarService fires the
	RemoteEvent "ActionBar"); this module only draws it:
	  - a fresh message fades in while rising and TYPES in (MaxVisibleGraphemes), holds `hold` seconds, then fades out sinking;
	  - XP of the SAME skill while the line is up is summed into it (no retype: the number pops, the % tweens, the hold restarts);
	  - XP of ANOTHER skill fades the old line out first, then types the new one in;
	  - a level-up types "COMBAT LEVEL 12" after the XP line, then types CONGRATULATIONS underneath and flashes; nothing can
	    overwrite it until it is done.
	  ActionBarClient.show(text, opts?)   any rich text for opts.hold (default 5) seconds; ignored during a level-up
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"):WaitForChild("ActionBarConfig")) :: any
local SkillsConfig = require(Modules:WaitForChild("SkillsConfig")) :: any

local ActionBarClient = {}

local player = Players.LocalPlayer

-- bound GUI
local group: CanvasGroup?
local label: TextLabel?
local sub: TextLabel?
local pop: UIScale?
local intro: UIScale?
local subPop: UIScale?
local labelStroke: UIStroke?
local subStroke: UIStroke?
local basePos: UDim2 = UDim2.new()
local baseStroke = 1.5 -- the Stroke thickness in the template (read when binding)

-- state of the line on screen
local state = {
	token = 0, -- bumps whenever a NEW message starts (cancels typing / holds of the old one)
	holdId = 0, -- bumps whenever the hold timer restarts
	typingId = 0, -- bumps whenever typing must stop (a stacked update, a new message)
	pctId = 0,
	kind = nil :: string?,
	skill = nil :: string?,
	total = 0,
	pct = 0, -- the % currently drawn (0-1)
	pctTarget = 0, -- the real progress the % is heading for
	levelShown = nil :: number?, -- the level number drawn (ticks up during a level-up)
	levelTarget = nil :: number?,
	cycle = 0, -- bumps whenever a level-up cycle starts / is cancelled
	busy = false, -- a level-up cycle is running (other skills cannot replace the line)
	visible = false,
}

-- ===================== HELPERS =====================
local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function piece(text: string, color: string): string
	return ("<font color='%s'>%s</font>"):format(color, text)
end

local function plainLen(rich: string): number
	return utf8.len((rich:gsub("<[^>]+>", ""))) or 0
end

local function skillColor(skill: string): string
	local def = SkillsConfig.skills and SkillsConfig.skills[skill]
	return def and def.color or "#FFFFFF"
end

local function fill(format: string, tokens: { [string]: any }): string
	return (format:gsub("{(%w+)}", function(key)
		return tostring(tokens[key] or "")
	end))
end

local function play(sound: any, pitchOverride: number?)
	if not sound or sound.id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = sound.id
	s.Volume = sound.volume or 0.5
	s.PlaybackSpeed = pitchOverride or sound.pitch or 1
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
end

local function info(seconds: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	return TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
end

--- The XP line (rich text) for a running total and a 0-1 progress.
local function xpLine(cfg: any, skill: string, total: number, pct: number, level: number?): string
	local tokens = { gain = commas(total), skill = skill, SKILL = skill:upper(), pct = ("%.1f"):format(pct * 100), level = level }
	local parts = {}
	for _, key in ipairs(cfg.order) do
		local p = cfg.pieces[key]
		if p then
			table.insert(parts, piece(fill(p.format, tokens), p.color))
		end
	end
	return table.concat(parts)
end

-- ===================== SHOW / HIDE =====================
local function fadeIn(cfg: any)
	local g = group :: CanvasGroup
	local i = cfg.intro
	local style = Enum.EasingStyle[i.style] or Enum.EasingStyle.Back
	g.Position = basePos + UDim2.fromOffset(0, i.rise)
	g.GroupTransparency = 1
	TweenService:Create(g, info(i.fade), { GroupTransparency = 0 }):Play()
	TweenService:Create(g, TweenInfo.new(i.time, style, Enum.EasingDirection.Out), { Position = basePos }):Play()
	if intro then
		intro.Scale = i.scale
		TweenService:Create(intro, TweenInfo.new(i.time, style, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	-- the outline flares and settles: it reads as the text "landing"
	if labelStroke then
		labelStroke.Thickness = i.strokePulse
		TweenService:Create(labelStroke, info(i.time, Enum.EasingStyle.Quint), { Thickness = baseStroke }):Play()
	end
	state.visible = true
end

local function fadeOut(cfg: any, quick: boolean?)
	local g = group :: CanvasGroup
	local time = quick and cfg.replaceFade or cfg.fadeOut
	TweenService:Create(g, info(time), { GroupTransparency = 1, Position = basePos + UDim2.fromOffset(0, quick and 0 or cfg.sink) }):Play()
	state.visible = false
end

local function scheduleHide(cfg: any, hold: number)
	state.holdId += 1
	local id = state.holdId
	task.delay(hold, function()
		if state.holdId == id then
			fadeOut(cfg)
			local token = state.token
			task.delay(cfg.fadeOut, function()
				if state.token == token and not state.visible then
					state.kind, state.skill, state.total = nil, nil, 0
					state.levelShown, state.levelTarget, state.busy = nil, nil, false
					;(label :: TextLabel).Text = ""
					;(sub :: TextLabel).Text = ""
				end
			end)
		end
	end)
end

--- Type `target`'s graphemes from `from` to `to()` at `speed` chars/s; stops when typingId changes.
local function typeInto(target: TextLabel, from: number, to: () -> number, speed: number, cfg: any, done: (() -> ())?)
	state.typingId += 1
	local id = state.typingId
	local started = os.clock()
	local lastTick = from
	task.spawn(function()
		while state.typingId == id do
			local goal = to()
			local shown = math.min(goal, from + math.floor((os.clock() - started) * speed))
			target.MaxVisibleGraphemes = shown
			if shown - lastTick >= 3 then
				lastTick = shown
				play(cfg.sounds.tick)
			end
			if shown >= goal then
				target.MaxVisibleGraphemes = -1
				if done then
					done()
				end
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

--- Start a message from scratch (cancels whatever was on screen).
local function begin(cfg: any, rich: string, hold: number, onTyped: (() -> ())?)
	local l = label :: TextLabel
	state.token += 1
	state.pctId += 1
	state.holdId += 1
	l.Text = rich
	l.MaxVisibleGraphemes = 0
	;(sub :: TextLabel).Text = ""
	fadeIn(cfg)
	typeInto(l, 0, function()
		return plainLen(l.Text)
	end, cfg.typeSpeed, cfg, function()
		if onTyped then
			onTyped()
		else
			scheduleHide(cfg, hold)
		end
	end)
end

--- Fade the current line out quickly, then run `thenDo` (a different skill / a level-up replaces the line).
local function replace(cfg: any, thenDo: () -> ())
	if not state.visible then
		thenDo()
		return
	end
	state.token += 1
	state.typingId += 1
	state.holdId += 1
	local token = state.token
	fadeOut(cfg, true)
	task.delay(cfg.replaceFade, function()
		if state.token == token then
			thenDo()
		end
	end)
end

-- ===================== XP =====================
--- The line as it should read right now (XP total, % drawn, and the level piece while a level-up is on screen).
local function render()
	local l = label :: TextLabel
	local xpCfg = Config.kind("xp", state.skill)
	local rich = xpLine(xpCfg, state.skill :: string, state.total, state.pct, state.levelTarget)
	if state.levelShown then
		local cfg = Config.kind("levelup", state.skill)
		local color = cfg.levelColor == "skill" and skillColor(state.skill :: string) or cfg.levelColor
		local text = fill(cfg.levelFormat, { skill = state.skill, SKILL = (state.skill :: string):upper(), level = state.levelShown })
		local sep = xpCfg.pieces.sep
		rich ..= piece(sep.format, sep.color) .. piece(text, color)
	end
	l.Text = rich
	return rich
end

--- Move the drawn % to `to` over `time` seconds (blocking: call from a task). Stops if `ok()` goes false.
local function animatePct(to: number, time: number, ok: () -> boolean)
	state.pctId += 1
	local id = state.pctId
	local from = state.pct
	local started = os.clock()
	while state.pctId == id and ok() do
		local u = math.clamp((os.clock() - started) / math.max(time, 0.001), 0, 1)
		u = 1 - (1 - u) * (1 - u)
		state.pct = from + (to - from) * u
		render()
		if u >= 1 then
			return
		end
		RunService.Heartbeat:Wait()
	end
end

local function popLabel(cfg: any, scale: number?)
	local p = pop :: UIScale
	p.Scale = scale or cfg.pop.scale
	TweenService:Create(p, info(cfg.pop.time), { Scale = 1 }):Play()
end

--- The level-up cycle: % climbs to 100, rests a couple of seconds, drops to 0, the level ticks up one by one, CONGRATULATIONS
--- types in, then the % climbs to the real progress. Restarts (from the level on screen) if another level-up arrives.
local function startCycle()
	local cfg = Config.kind("levelup", state.skill)
	local lvl = cfg.congrats
	state.cycle += 1
	local id = state.cycle
	state.busy = true
	state.holdId += 1 -- no hide while the cycle runs
	local function alive()
		return state.cycle == id
	end
	task.spawn(function()
		animatePct(1, cfg.pctTween, alive)
		if not alive() then
			return
		end
		local waited = 0
		while alive() and waited < cfg.tickDelay do
			waited += task.wait(0.05)
		end
		if not alive() then
			return
		end
		animatePct(0, cfg.dropTime, alive)
		while alive() and (state.levelShown :: number) < (state.levelTarget :: number) do
			state.levelShown += 1
			render()
			popLabel(cfg, cfg.tickPop)
			play(cfg.sounds.levelup)
			task.wait(cfg.tickStep)
		end
		if not alive() then
			return
		end
		-- "! CONGRATULATIONS !" types in with an outline flash, then the marks grow on both sides: !! -> !!!
		local s = sub :: TextLabel
		local function flash()
			local stroke = subStroke :: UIStroke
			local original = Color3.new(0, 0, 0)
			stroke.Color = Color3.fromHex(lvl.flash)
			stroke.Thickness = baseStroke * 3
			TweenService:Create(stroke, info(lvl.flashTime), { Color = original, Thickness = baseStroke }):Play()
		end
		local function congrats(step: number): string
			local m = lvl.marks
			local bang = string.rep(m.char, m.steps[step])
			local function bold(text: string, color: string, isBold: boolean?)
				local t = piece(text, color)
				return isBold and ("<b>" .. t .. "</b>") or t
			end
			local marks = bold(bang, m.color, m.bold)
			return marks .. m.gap .. bold(lvl.text, lvl.color, lvl.bold) .. m.gap .. marks
		end
		s.Text = congrats(1)
		s.MaxVisibleGraphemes = 0
		flash()
		local typed, marksDone = false, false
		typeInto(s, 0, function()
			return plainLen(s.Text)
		end, lvl.typeSpeed, cfg, function()
			typed = true
		end)
		task.spawn(function()
			while alive() and not typed do
				task.wait(0.03)
			end
			for step = 2, #lvl.marks.steps do
				if not alive() then
					return
				end
				task.wait(lvl.marks.stepTime)
				if not alive() then
					return
				end
				s.Text = congrats(step)
				s.MaxVisibleGraphemes = -1
				flash()
				play(cfg.sounds.pop, 1 + 0.15 * step)
				if subPop then
					subPop.Scale = lvl.marks.pop
					TweenService:Create(subPop, info(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end
			end
			marksDone = true
		end)
		-- the % climbs to where you really are (more XP may arrive meanwhile: chase the newest target)
		repeat
			animatePct(state.pctTarget, cfg.fillTime, alive)
		until not alive() or math.abs(state.pct - state.pctTarget) < 0.0005
		while alive() and not marksDone do
			task.wait(0.05)
		end
		if not alive() then
			return
		end
		state.busy = false
		scheduleHide(cfg, lvl.hold)
	end)
end

local function stack(cfg: any, msg: any)
	state.total += msg.gain
	state.pctTarget = msg.pct
	state.typingId += 1 -- a half-typed line shows in full
	;(label :: TextLabel).MaxVisibleGraphemes = -1
	popLabel(cfg)
	play(cfg.sounds.pop)
	if state.busy then
		render() -- the cycle chases the new target itself
		return
	end
	task.spawn(function()
		animatePct(msg.pct, cfg.pctTween, function()
			return true
		end)
	end)
	scheduleHide(cfg, state.levelShown and Config.kind("levelup", state.skill).congrats.hold or cfg.hold)
end

--- XP that finished a level.
local function levelUp(msg: any)
	local cfg = Config.kind("levelup", msg.skill)
	local fromLevel = state.levelShown or msg.fromLevel or (msg.level - 1)
	if state.visible and state.skill == msg.skill then
		-- the line is already up: more XP, and the level piece types in after it, then the cycle starts
		state.total += msg.gain
		state.pctTarget = msg.pct
		state.levelTarget = msg.level
		state.typingId += 1
		local l = label :: TextLabel
		local prevLen = plainLen(l.Text)
		state.kind = "levelup"
		state.levelShown = fromLevel
		render()
		popLabel(cfg)
		play(cfg.sounds.pop)
		if state.busy then
			l.MaxVisibleGraphemes = -1
			startCycle()
			return
		end
		l.MaxVisibleGraphemes = math.min(prevLen, plainLen(l.Text))
		typeInto(l, l.MaxVisibleGraphemes, function()
			return plainLen(l.Text)
		end, cfg.levelTypeSpeed, cfg, startCycle)
		return
	end
	-- a fresh line: "+100 Combat XP - 100.0% - Combat Level 5" types in, then the cycle starts
	state.kind, state.skill, state.total = "levelup", msg.skill, msg.gain
	state.pct = 1
	state.levelShown = fromLevel
	state.levelTarget = msg.level
	state.pctTarget = msg.pct
	state.busy = true
	local rich = render()
	play(cfg.sounds.levelup)
	begin(cfg, rich, cfg.hold, startCycle)
end

-- ===================== MESSAGES =====================
local function onXp(msg: any)
	if state.busy and state.skill ~= msg.skill then
		return -- a level-up of another skill is playing
	end
	if msg.leveledUp then
		if state.visible and state.skill == msg.skill then
			levelUp(msg)
		else
			replace(Config.kind("levelup", msg.skill), function()
				levelUp(msg)
			end)
		end
		return
	end
	local cfg = Config.kind("xp", msg.skill)
	if state.visible and state.skill == msg.skill and (state.kind == "xp" or state.kind == "levelup") then
		stack(cfg, msg)
		return
	end
	replace(cfg, function()
		state.kind, state.skill, state.total, state.pct = "xp", msg.skill, msg.gain, msg.pct
		state.levelShown, state.levelTarget, state.busy = nil, nil, false
		state.cycle += 1
		begin(cfg, xpLine(cfg, msg.skill, msg.gain, msg.pct, msg.level), cfg.hold)
	end)
end

function ActionBarClient.show(text: string, opts: any?)
	if not group or state.busy or type(text) ~= "string" then
		return
	end
	local cfg = Config.kind("text")
	local hold = opts and type(opts.hold) == "number" and opts.hold or cfg.hold
	replace(cfg, function()
		state.kind, state.skill, state.total = "text", nil, 0
		state.levelShown, state.levelTarget, state.busy = nil, nil, false
		begin(cfg, text, hold)
	end)
end

local function onMessage(msg: any)
	if type(msg) ~= "table" or not group then
		return
	end
	if msg.kind == "xp" and type(msg.skill) == "string" and type(msg.gain) == "number" and type(msg.pct) == "number" then
		onXp(msg)
	elseif msg.kind == "text" and type(msg.text) == "string" then
		ActionBarClient.show(msg.text, { hold = msg.hold })
	end
end

-- ===================== BINDING =====================
local function bind(gui: Instance)
	local root = gui:WaitForChild("Root", 10)
	local g = root and root:WaitForChild("ActionBar", 10)
	if not g then
		warn("[ActionBar] FIAHUD.Root.ActionBar is missing (run tools/studio/build_actionbar.luau)")
		return
	end
	group = g :: CanvasGroup
	label = g:WaitForChild("Label") :: TextLabel
	sub = g:WaitForChild("Sub") :: TextLabel
	pop = label:WaitForChild("Pop") :: UIScale
	subStroke = sub:WaitForChild("Stroke") :: UIStroke
	subPop = sub:FindFirstChild("Pop") :: UIScale?
	labelStroke = label:FindFirstChild("Stroke") :: UIStroke?
	intro = group:FindFirstChild("Intro") :: UIScale?
	baseStroke = subStroke.Thickness
	basePos = group.Position
	group.GroupTransparency = 1
	label.Text = ""
	sub.Text = ""
	state.visible = false
end

function ActionBarClient.start()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("FIAHUD")
	if existing then
		task.spawn(bind, existing)
	end
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "FIAHUD" then
			task.spawn(bind, child)
		end
	end)
	ReplicatedStorage:WaitForChild("ActionBar").OnClientEvent:Connect(onMessage)
end

return ActionBarClient
