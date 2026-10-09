--[[
	NotificationController (LocalScript)
	Place inside: StarterPlayerScripts

	Drives StarterGui.FIANotifications (built by tools/studio/build_notifications.luau): the notification cards in the bottom-left
	corner. NotifyService (server) fires the RemoteEvent "Notify" with a list of payloads; this only displays them and sends nothing.
	Cards are CLONED from FIANotifications.Templates (Slot + CardLevelUp / CardCollection / CardPickup / CardSystem / RewardLine);
	all texts, colours, timings and sounds come from Modules/Config/NotificationConfig.

	A card lives in a Slot (a row of the bottom-up list). It slides in from the left edge, holds (a timer bar drains), then slides back
	out to the left and its slot closes so the cards above settle down. Pickups with the same key merge into the showing card (xN,
	timer restarts, small pop). At most `maxVisible` cards show; extra payloads wait in a priority queue (FIFO within a priority).
--]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"):WaitForChild("NotificationConfig")) :: any
local SkillsConfig = require(Modules:WaitForChild("SkillsConfig")) :: any
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
local ItemIconData = require(Modules:WaitForChild("ItemIconData")) :: { [string]: string }
local Items = require(Modules:WaitForChild("Items")) :: any
local CollectionsConfig = require(Modules:WaitForChild("CollectionsConfig")) :: any

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FIANotifications")
local stack = gui:WaitForChild("Stack") :: Frame
local scale = stack:WaitForChild("Scale") :: UIScale
local list = stack:FindFirstChildOfClass("UIListLayout") :: UIListLayout
local templates = gui:WaitForChild("Templates")
templates.Parent = nil -- the templates are only clone sources: left in the gui they draw as blank cards in the top-left corner
local remote = ReplicatedStorage:WaitForChild("Notify") :: RemoteEvent

local DEFAULT = Config.library.default

type Entry = {
	kind: string,
	key: string?,
	color: string,
	cfg: any,
	slot: Frame,
	card: Frame,
	width: number,
	hold: number,
	deadline: number,
	count: number,
	amount: number,
	payload: any,
	leaving: boolean,
	dead: boolean,
	gen: number,
}

local active: { Entry } = {}
local waiting: { any } = {} -- payloads waiting for a free slot
local order = 0
local lastShowSound = 0

-- ===================== HELPERS =====================
local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function tweenInfo(t: any, override: number?): TweenInfo
	return TweenInfo.new(
		override or t.time,
		Enum.EasingStyle[t.style or "Quint"],
		Enum.EasingDirection[t.direction or "Out"]
	)
end

--- Silkscreen value inside rich text (stats, items, Coins, counts).
local function value(text: string, color: string, base: number): string
	return string.format(
		"<font family=\"%s\" color=\"%s\" size=\"%d\">%s</font>",
		Config.fonts.value,
		color,
		math.max(8, math.floor(base * Config.fonts.valueScale + 0.5)),
		escape(text)
	)
end

--- An item / label name in Merriweather (bold), at the label's own size.
local function nameText(text: string, color: string): string
	local body = escape(text)
	if Config.fonts.nameBold then
		body = "<b>" .. body .. "</b>"
	end
	return string.format("<font face=\"%s\" color=\"%s\">%s</font>", Config.fonts.nameFace, color, body)
end

--- Roman numeral in Merriweather.
local function numeral(n: number, color: string): string
	return string.format("<font face=\"%s\" color=\"%s\">%s</font>", Config.fonts.numeralFace, color, SkillsConfig.roman(n))
end

local function number(n: number): string
	if math.abs(n - math.floor(n + 0.5)) < 0.001 then
		return tostring(math.floor(n + 0.5))
	end
	return tostring(math.floor(n * 100 + 0.5) / 100)
end

local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)

local function keypoints(...: Color3): ColorSequence
	local colors = { ... }
	local points = {}
	for i, c in ipairs(colors) do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(points)
end

--- Colours a whole card from one colour: dark shade for the 4px border, very dark tint for the body, light shade for the 2px stroke,
--- a soft top-to-bottom gradient on every text and a shine on the timer bar (all through the template's UIGradients).
local function applyTheme(card: Frame, colorHex: string, theme: any)
	local tint = hex(colorHex)
	local body = card:WaitForChild("Body") :: Frame
	local border = tint:Lerp(BLACK, theme.borderMix)
	local borderGradient = card:FindFirstChild("BorderGradient") :: UIGradient?
	if borderGradient then
		borderGradient.Color = keypoints(border, border:Lerp(tint, 0.35), border)
	end
	local base = tint:Lerp(BLACK, 1 - theme.bodyTint)
	card:SetAttribute("BodyBase", base)
	card:SetAttribute("Tint", tint)
	local bodyGradient = body:FindFirstChild("BodyGradient") :: UIGradient?
	if bodyGradient then
		bodyGradient.Color = ColorSequence.new(base)
		bodyGradient.Offset = Vector2.zero
	end
	local stroke = body:FindFirstChildOfClass("UIStroke")
	local strokeGradient = stroke and stroke:FindFirstChild("StrokeGradient") :: UIGradient?
	if strokeGradient then
		local light = tint:Lerp(WHITE, theme.strokeLight)
		strokeGradient.Color = keypoints(light, tint, light)
	end
	local textBottom = WHITE:Lerp(tint, theme.textShade)
	for _, d in ipairs(card:GetDescendants()) do
		if d:IsA("UIGradient") and d.Name == "TextGradient" then
			d.Enabled = theme.textGradient
			d.Color = keypoints(WHITE, textBottom)
		elseif d:IsA("UIGradient") and d.Name == "FillGradient" then
			d.Enabled = theme.fillShine
			d.Color = keypoints(tint, tint:Lerp(WHITE, 0.6), tint)
			if theme.fillShine then
				(d.Parent :: Frame).BackgroundColor3 = WHITE
			end
		end
	end
end

--- A bright band sweeps across the body (UIGradient offset) and the 2px stroke flares.
local function sheen(card: Frame, time: number, strength: number, pulse: number, pulseTime: number)
	local body = card:FindFirstChild("Body") :: Frame?
	local base = card:GetAttribute("BodyBase") :: Color3?
	local tint = card:GetAttribute("Tint") :: Color3?
	if not (body and base and tint) then
		return
	end
	local gradient = body:FindFirstChild("BodyGradient") :: UIGradient?
	if gradient and strength > 0 and time > 0 then
		local bright = base:Lerp(tint:Lerp(WHITE, 0.5), strength)
		gradient.Color = keypoints(base, base, bright, base, base)
		gradient.Offset = Vector2.new(-1, 0)
		TweenService:Create(gradient, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Offset = Vector2.new(1, 0) }):Play()
	end
	local stroke = body:FindFirstChildOfClass("UIStroke")
	if stroke and pulse > 0 then
		stroke.Thickness = pulse
		TweenService:Create(stroke, TweenInfo.new(pulseTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Thickness = 2 }):Play()
	end
end

local function pop(card: Frame, from: number, time: number)
	local scaleObj = card:FindFirstChild("Pop") :: UIScale?
	if scaleObj and from ~= 1 then
		scaleObj.Scale = from
		TweenService:Create(scaleObj, TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function play(slot: any)
	if not slot or not slot.id or slot.id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = slot.id
	s.Volume = slot.volume or 0.5
	s.PlaybackSpeed = slot.pitch or 1
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

-- ===================== LAYOUT =====================
local stackTarget: UDim2? = nil
local function applyLayout()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local s = math.clamp(camera.ViewportSize.Y / DEFAULT.baseHeight, DEFAULT.minScale, DEFAULT.maxScale)
	scale.Scale = s
	stack.AnchorPoint = Vector2.new(0, 1)
	-- the stack sits above the chat panel (FIAChatGui, bottom-left) while it is open, else at the bottom margin
	local above = 0
	local chat = player.PlayerGui:FindFirstChild("FIAChatGui")
	local panel = chat and chat:FindFirstChild("Panel")
	if chat and panel and chat:IsA("ScreenGui") and chat.Enabled then
		above = math.max(0, gui.AbsoluteSize.Y - (panel :: GuiObject).AbsolutePosition.Y) + DEFAULT.gap
	end
	local target = UDim2.new(0, math.floor(DEFAULT.margin * s), 1, -math.max(math.floor(DEFAULT.bottomOffset * s), math.floor(above)))
	if target ~= stackTarget then
		if stackTarget == nil then
			stack.Position = target
		else
			TweenService:Create(stack, tweenInfo(DEFAULT.restack), { Position = target }):Play() -- follows the chat opening / closing
		end
		stackTarget = target
	end
	list.Padding = UDim.new(0, DEFAULT.gap)
end

applyLayout()
local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
end
watchCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCamera()
	applyLayout()
end)

local layoutClock = 0
RunService.Heartbeat:Connect(function(dt) -- the chat can open, close or move
	layoutClock += dt
	if layoutClock >= 0.1 then
		layoutClock = 0
		applyLayout()
	end
end)

-- ===================== FILLING A CARD =====================
local statIcons: { [string]: string }? = nil

--- The icon of a pickup: the key's own override, the payload's icon, the item's ItemIcons icon ("item:<toolName>") or the statistic's
--- icon ("stat:<id>"). nil = no icon known: the card keeps its tinted diamond gem.
local function pickupIcon(key: string, payload: any, override: any): any?
	local function content(value: any): any?
		if type(value) ~= "string" or value == "" then
			return nil
		end
		if value:find("rbxasset", 1, true) or value:sub(1, 4) == "http" then
			return { image = value }
		end
		return ItemIconData[value] and { image = ItemIconData[value] } or nil
	end
	local found = content(override and override.icon) or content(payload.icon)
	if found then
		return found
	end
	local prefix, id = key:match("^(%a+):(.+)$")
	if prefix == "item" then
		local def = Items.getByToolName(id) or Items.get(id)
		if def then
			local spec = ItemIcons.resolve(def)
			if not spec.placeholder then
				return spec
			end
		end
	elseif prefix == "stat" then
		if not statIcons then
			statIcons = {}
			for _, byKey in pairs(CollectionsConfig.statConfigLookup) do
				for statKey, stat in pairs(byKey) do
					if stat.icon and stat.icon ~= "" and not (statIcons :: any)[statKey] then
						(statIcons :: any)[statKey] = stat.icon
					end
				end
			end
		end
		return content((statIcons :: any)[id])
	end
	return nil
end

local function setIcon(card: Frame, image: any, tint: string)
	local icon = card:FindFirstChild("Icon", true) :: Frame?
	if not icon then
		return
	end
	local gem = icon:FindFirstChild("Gem") :: Frame?
	local img = icon:FindFirstChild("Image") :: ImageLabel?
	if gem then
		gem.BackgroundColor3 = hex(tint)
		local spec = type(image) == "table" and image or { image = image }
		gem.Visible = not (type(spec.image) == "string" and spec.image ~= "")
	end
	if img then
		local spec = type(image) == "table" and image or { image = image }
		local has = type(spec.image) == "string" and spec.image ~= ""
		img.ResampleMode = Enum.ResamplerMode.Pixelated
		img.Image = has and spec.image or ""
		img.ImageRectOffset = spec.rectOffset or Vector2.zero
		img.ImageRectSize = spec.rectSize or Vector2.zero
		img.ImageColor3 = spec.tint or Color3.new(1, 1, 1)
		img.Visible = has
	end
end

local function fillTier(entry: Entry, payload: any)
	local card, cfg = entry.card, entry.cfg
	local body = card:WaitForChild("Body")
	local color = cfg.color
	local title = body.Header.Text.Title :: TextLabel
	local heading = body.Header.Text.Heading :: TextLabel
	title.Text = cfg.title.format
	title.TextColor3 = hex(cfg.title.color)
	local nameText
	if entry.kind == "levelup" then
		local def = SkillsConfig.skills[payload.skill]
		nameText = string.format("<font color=\"%s\">%s</font>", color, escape(def and def.name or payload.skill))
	else
		nameText = value(payload.name, color, heading.TextSize)
	end
	heading.Text = cfg.heading
		:gsub("{name}", function()
			return nameText
		end)
		:gsub("{from}", function()
			return numeral(payload.from, cfg.fromColor)
		end)
		:gsub("{to}", function()
			return numeral(payload.to, cfg.toColor)
		end)
	body.Rule.BackgroundColor3 = hex(color)
	body.Timer.Fill.BackgroundColor3 = hex(color)
	setIcon(card, cfg.icon, color)

	local rewardsTitle = body.RewardsTitle :: TextLabel
	local lines = body.Lines :: Frame
	local rewards = payload.rewards
	if type(rewards) ~= "table" or #rewards == 0 then
		rewardsTitle.Visible = false
		lines.Visible = false
	else
		rewardsTitle.Text = cfg.rewardsTitle.text
		rewardsTitle.TextColor3 = hex(cfg.rewardsTitle.color)
		local template = templates:WaitForChild("RewardLine") :: TextLabel
		local shown = math.min(#rewards, cfg.maxRewardLines)
		for i = 1, shown do
			local reward = rewards[i]
			local line = template:Clone()
			line.Name = "Line" .. i
			line.LayoutOrder = i
			local text = tostring(reward.text or "")
			local rewardColor = type(reward.color) == "string" and reward.color or "#FFFFFF"
			local plus = text:sub(1, 1) == "+"
			local body2 = plus and text:sub(2) or text
			local prefix = string.format("<font color=\"#55FF55\">+</font> ")
			local rich
			if text:match("^%+?%s*%d") then
				rich = prefix .. value((body2:gsub("^%s+", "")), rewardColor, line.TextSize) -- numbers and stats: Silkscreen
			else
				rich = prefix .. string.format("<font color=\"%s\">%s</font>", rewardColor, escape(body2))
			end
			line.Text = rich
			line.Parent = lines
		end
		if #rewards > shown then
			local line = template:Clone()
			line.LayoutOrder = shown + 1
			line.Text = string.format("<font color=\"#AAAAAA\">+%d more</font>", #rewards - shown)
			line.Parent = lines
		end
	end
	local flavor = body.Flavor :: TextLabel
	if cfg.flavor and cfg.flavor ~= "" and entry.kind == "levelup" then
		flavor.Text = cfg.flavor
	else
		flavor.Visible = false
	end
end

local function fillPickup(entry: Entry)
	local card, cfg, payload = entry.card, entry.cfg, entry.payload
	local body = card:WaitForChild("Body")
	local row = body.Row
	local label = row.Label :: TextLabel
	local count = row.Count :: TextLabel
	local color = entry.color
	local text = cfg.format
		:gsub("{amount}", function()
			return value(cfg.amountPrefix .. number(entry.amount), color, label.TextSize)
		end)
		:gsub("{label}", function()
			return nameText(payload.label, cfg.theme.labelTint and color or cfg.labelColor)
		end)
	label.Text = text
	if entry.count > 1 then
		count.Visible = true
		count.Text = string.format("<font color=\"%s\">%s</font>", cfg.countColor, (cfg.countFormat:gsub("{count}", tostring(entry.count))))
	else
		count.Visible = false
	end
	body.Timer.Fill.BackgroundColor3 = hex(color)
	setIcon(card, pickupIcon(payload.key, payload, Config.items[payload.key]), color)
end

local function fillSystem(entry: Entry)
	local card, cfg, payload = entry.card, entry.cfg, entry.payload
	local body = card:WaitForChild("Body")
	local color = payload.color or cfg.color
	local main = body.Row.Text.Main :: TextLabel
	local sub = body.Row.Text.Sub :: TextLabel
	local text = escape(payload.text)
	if entry.count > 1 then -- the same notice again: one card with a counter
		text ..= string.format("  <font color=\"%s\">%s</font>", cfg.countColor, (cfg.countFormat:gsub("{count}", tostring(entry.count))))
	end
	main.Text = text
	main.TextColor3 = hex(color)
	if payload.sub and payload.sub ~= "" then
		sub.Text = escape(payload.sub)
		sub.TextColor3 = hex(cfg.subColor)
	else
		sub.Visible = false
	end
	body.Timer.Fill.BackgroundColor3 = hex(color)
	setIcon(card, nil, color)
end

-- ===================== LIFECYCLE =====================
local function startTimer(entry: Entry)
	entry.deadline = os.clock() + entry.hold
	local fill = entry.card:FindFirstChild("Fill", true) :: Frame?
	if fill and entry.cfg.timerBar then
		fill.Size = UDim2.fromScale(1, 1)
		TweenService:Create(fill, TweenInfo.new(entry.hold, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
	end
end

local function visibleCount(): number
	local n = 0
	for _, entry in ipairs(active) do
		if not entry.leaving then
			n += 1
		end
	end
	return n
end

local show: (payload: any) -> ()

local function priorityOf(kind: string): number
	local def = Config.kinds[kind]
	return def and def.priority or 0
end

local leave: (entry: Entry) -> ()

--- Shows waiting cards while there is room. When the stack is full and the next card matters MORE than a showing one, the least
--- important (then oldest) showing card is pushed out to make room: level-ups never wait behind a flood of pickups.
local function pump()
	while #waiting > 0 do
		if visibleCount() < DEFAULT.maxVisible then
			show(table.remove(waiting, 1))
		else
			local need = priorityOf(waiting[1].kind)
			local victim: Entry? = nil
			if DEFAULT.evictLower then
				for _, entry in ipairs(active) do -- oldest first
					local p = priorityOf(entry.kind)
					if not entry.leaving and not entry.dead and p < need and (not victim or p < priorityOf(victim.kind)) then
						victim = entry
					end
				end
			end
			if not victim then
				break
			end
			leave(victim :: Entry) -- its slot frees, leave() pumps again and the waiting card takes the bottom
			return
		end
	end
end

leave = function(entry: Entry)
	if entry.leaving or entry.dead then
		return
	end
	entry.leaving = true
	entry.gen += 1
	local gen = entry.gen
	play(entry.cfg.sounds and entry.cfg.sounds.hide)
	local out = TweenService:Create(entry.card, tweenInfo(entry.cfg.slideOut), {
		Position = UDim2.fromOffset(-(entry.width + DEFAULT.margin + 40), 0),
	})
	local popScale = entry.card:FindFirstChild("Pop") :: UIScale?
	if popScale then
		TweenService:Create(popScale, tweenInfo(entry.cfg.slideOut), { Scale = entry.cfg.outro.scale }):Play()
	end
	out.Completed:Connect(function()
		if entry.dead or entry.gen ~= gen then
			return
		end
		-- close the slot: the cards above settle down
		local slot = entry.slot
		local height = slot.AbsoluteSize.Y / math.max(scale.Scale, 0.01)
		slot.AutomaticSize = Enum.AutomaticSize.None
		slot.Size = UDim2.new(1, 0, 0, height)
		local close = TweenService:Create(slot, tweenInfo(entry.cfg.restack), { Size = UDim2.new(1, 0, 0, 0) })
		close.Completed:Connect(function()
			if entry.dead then
				return
			end
			entry.dead = true
			local at = table.find(active, entry)
			if at then
				table.remove(active, at)
			end
			slot:Destroy()
		end)
		close:Play()
	end)
	out:Play()
	pump() -- a waiting card may take the freed place right away
end

show = function(payload: any)
	local kind = payload.kind
	local key = payload.key
	local cfgKey = kind == "levelup" and payload.skill or (kind == "pickup" and key or nil)
	local cfg = Config.kind(kind, cfgKey)
	local template = templates:FindFirstChild(cfg.template)
	local slotTemplate = templates:FindFirstChild("Slot")
	if not template or not slotTemplate then
		return
	end
	local slot = slotTemplate:Clone() :: Frame
	local card = template:Clone() :: Frame
	local width = card.Size.X.Offset
	order += 1
	slot.LayoutOrder = order
	card.Position = UDim2.fromOffset(-(width + DEFAULT.margin + 40), 0)
	card.Parent = slot
	slot.Parent = stack

	local entry: Entry = {
		kind = kind,
		key = key,
		color = cfg.color,
		cfg = cfg,
		slot = slot,
		card = card,
		width = width,
		hold = cfg.hold,
		deadline = 0,
		count = payload.count or 1,
		amount = payload.amount or 0,
		payload = payload,
		leaving = false,
		dead = false,
		gen = 0,
	}
	if kind == "pickup" then
		local override = Config.items[key :: string]
		entry.color = (override and override.color) or payload.color or cfg.color
	elseif kind == "system" then
		entry.color = payload.color or cfg.color
	end
	if kind == "levelup" or kind == "collection" then
		fillTier(entry, payload)
	elseif kind == "pickup" then
		fillPickup(entry)
	else
		fillSystem(entry)
	end
	card.Body.BackgroundTransparency = cfg.bodyTransparency
	card.BackgroundTransparency = cfg.borderTransparency
	applyTheme(card, entry.color, cfg.theme)
	table.insert(active, entry)
	startTimer(entry)
	local intro = cfg.intro
	pop(card, intro.popFrom, intro.popTime)
	sheen(card, intro.sheenTime, intro.sheenStrength, intro.strokePulse, intro.pulseTime)

	TweenService:Create(card, tweenInfo(cfg.slideIn), { Position = UDim2.fromOffset(0, 0) }):Play()
	if cfg.sounds and cfg.sounds.show and os.clock() - lastShowSound > 0.1 then
		lastShowSound = os.clock()
		play(cfg.sounds.show)
	end
end

-- ===================== INCOMING =====================
local function insertWaiting(payload: any)
	local priority = priorityOf(payload.kind)
	local at = #waiting + 1
	for i, queued in ipairs(waiting) do
		if priorityOf(queued.kind) < priority then
			at = i
			break
		end
	end
	table.insert(waiting, at, payload)
	-- a flood never builds a long backlog: the oldest card of the least important kind is dropped
	while #waiting > DEFAULT.maxQueue do
		local lowest = math.huge
		for _, queued in ipairs(waiting) do
			lowest = math.min(lowest, priorityOf(queued.kind))
		end
		for i, queued in ipairs(waiting) do
			if priorityOf(queued.kind) == lowest then
				table.remove(waiting, i)
				break
			end
		end
	end
end

local function merge(payload: any): boolean
	for _, entry in ipairs(active) do
		if (entry.kind == payload.kind) and entry.key == payload.key and not entry.leaving and not entry.dead then
			entry.count += 1
			if entry.kind == "pickup" then
				entry.amount += payload.amount
				fillPickup(entry)
			else
				fillSystem(entry)
			end
			applyTheme(entry.card, entry.color, entry.cfg.theme)
			startTimer(entry)
			local popScale = entry.card:FindFirstChild("Pop") :: UIScale?
			if popScale then
				popScale.Scale = entry.cfg.pop.scale
				TweenService:Create(popScale, TweenInfo.new(entry.cfg.pop.time, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			sheen(entry.card, entry.cfg.mergeFx.sheenTime, entry.cfg.intro.sheenStrength, entry.cfg.mergeFx.strokePulse, entry.cfg.intro.pulseTime)
			return true
		end
	end
	for _, queued in ipairs(waiting) do
		if queued.kind == payload.kind and queued.key == payload.key then
			queued.count = (queued.count or 1) + 1
			queued.amount = (queued.amount or 0) + (payload.amount or 0)
			return true
		end
	end
	return false
end

local function onPayload(payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" or not Config.kinds[payload.kind] then
		return
	end
	if payload.kind == "pickup" then
		if type(payload.key) ~= "string" or type(payload.label) ~= "string" or type(payload.amount) ~= "number" then
			return
		end
		if merge(payload) then
			return
		end
	elseif payload.kind == "system" and type(payload.key) == "string" and merge(payload) then
		return -- a repeated notice stacks into the card that is already showing / waiting
	end
	insertWaiting(payload)
	pump()
end

remote.OnClientEvent:Connect(function(batch)
	if type(batch) ~= "table" then
		return
	end
	for _, payload in ipairs(batch) do
		onPayload(payload)
	end
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, entry in ipairs(table.clone(active)) do
		if not entry.leaving and not entry.dead and now >= entry.deadline then
			leave(entry)
		end
	end
end)
