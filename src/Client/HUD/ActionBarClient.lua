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
local subStroke: UIStroke?
local basePos: UDim2 = UDim2.new()

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
	visible = false,
	lockedUntil = 0,
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
	g.Position = basePos + UDim2.fromOffset(0, cfg.rise)
	g.GroupTransparency = 1
	TweenService:Create(g, info(cfg.fadeIn), { GroupTransparency = 0, Position = basePos }):Play()
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
local function stack(cfg: any, msg: any)
	state.total += msg.gain
	local from, to = state.pct, msg.pct
	state.typingId += 1 -- a half-typed line shows in full
	;(label :: TextLabel).MaxVisibleGraphemes = -1
	-- the number pops once
	local p = pop :: UIScale
	p.Scale = cfg.pop.scale
	TweenService:Create(p, info(cfg.pop.time), { Scale = 1 }):Play()
	play(cfg.sounds.pop)
	-- the % moves to its new value
	state.pctId += 1
	local id = state.pctId
	local started = os.clock()
	task.spawn(function()
		while state.pctId == id do
			local u = math.clamp((os.clock() - started) / cfg.pctTween, 0, 1)
			u = 1 - (1 - u) * (1 - u)
			state.pct = from + (to - from) * u
			;(label :: TextLabel).Text = xpLine(cfg, msg.skill, state.total, state.pct, msg.level)
			if u >= 1 then
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
	scheduleHide(cfg, cfg.hold)
end

local function levelUp(msg: any)
	local cfg = Config.kind("levelup", msg.skill)
	local xpCfg = Config.kind("xp", msg.skill)
	local lvl = cfg.congrats
	local color = cfg.levelColor == "skill" and skillColor(msg.skill) or cfg.levelColor
	local base = xpLine(xpCfg, msg.skill, msg.gain, 1, msg.level)
	local sepPiece = xpCfg.pieces.sep
	local levelText = fill(cfg.levelFormat, { SKILL = msg.skill:upper(), skill = msg.skill, level = msg.level })
	local rich = base .. piece(sepPiece.format, sepPiece.color) .. piece(levelText, color)
	local baseLen = plainLen(base .. piece(sepPiece.format, sepPiece.color))
	-- nothing may overwrite the sequence: lock for its whole length
	local lockFor = plainLen(rich) / cfg.typeSpeed + (plainLen(levelText) / cfg.levelTypeSpeed) + (plainLen(lvl.text) / lvl.typeSpeed) + lvl.hold + 0.6
	state.lockedUntil = os.clock() + lockFor
	state.kind, state.skill, state.total, state.pct = "levelup", msg.skill, msg.gain, 1
	local l, s = label :: TextLabel, sub :: TextLabel
	state.token += 1
	state.pctId += 1
	state.holdId += 1
	local token = state.token
	l.Text = rich
	l.MaxVisibleGraphemes = 0
	s.Text = piece(lvl.text, lvl.color)
	s.MaxVisibleGraphemes = 0
	fadeIn(cfg)
	play(cfg.sounds.levelup)
	-- the XP line types at the normal speed, "COMBAT LEVEL 12" slower, then CONGRATULATIONS
	typeInto(l, 0, function()
		return baseLen
	end, cfg.typeSpeed, cfg, function()
		typeInto(l, baseLen, function()
			return plainLen(rich)
		end, cfg.levelTypeSpeed, cfg, function()
			if state.token ~= token then
				return
			end
			-- CONGRATULATIONS lands with an outline flash
			local stroke = subStroke :: UIStroke
			local original = stroke.Color
			stroke.Color = Color3.fromHex(lvl.flash)
			stroke.Thickness = 5
			TweenService:Create(stroke, info(lvl.flashTime), { Color = original, Thickness = 2 }):Play()
			typeInto(s, 0, function()
				return plainLen(s.Text)
			end, lvl.typeSpeed, cfg, function()
				if state.token == token then
					scheduleHide(cfg, lvl.hold)
				end
			end)
		end)
	end)
end

-- ===================== MESSAGES =====================
local function onXp(msg: any)
	if os.clock() < state.lockedUntil then
		return -- a level-up is playing
	end
	if msg.leveledUp then
		replace(Config.kind("levelup", msg.skill), function()
			levelUp(msg)
		end)
		return
	end
	local cfg = Config.kind("xp", msg.skill)
	if state.visible and state.kind == "xp" and state.skill == msg.skill then
		stack(cfg, msg)
		return
	end
	replace(cfg, function()
		state.kind, state.skill, state.total, state.pct = "xp", msg.skill, msg.gain, msg.pct
		begin(cfg, xpLine(cfg, msg.skill, msg.gain, msg.pct, msg.level), cfg.hold)
	end)
end

function ActionBarClient.show(text: string, opts: any?)
	if not group or os.clock() < state.lockedUntil or type(text) ~= "string" then
		return
	end
	local cfg = Config.kind("text")
	local hold = opts and type(opts.hold) == "number" and opts.hold or cfg.hold
	replace(cfg, function()
		state.kind, state.skill, state.total = "text", nil, 0
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
