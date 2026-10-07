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

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("FIANotifications")
local stack = gui:WaitForChild("Stack") :: Frame
local scale = stack:WaitForChild("Scale") :: UIScale
local list = stack:FindFirstChildOfClass("UIListLayout") :: UIListLayout
local templates = gui:WaitForChild("Templates")
local remote = ReplicatedStorage:WaitForChild("Notify") :: RemoteEvent

local DEFAULT = Config.library.default

type Entry = {
	kind: string,
	key: string?,
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
local function applyLayout()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local s = math.clamp(camera.ViewportSize.Y / DEFAULT.baseHeight, DEFAULT.minScale, DEFAULT.maxScale)
	scale.Scale = s
	stack.AnchorPoint = Vector2.new(0, 1)
	stack.Position = UDim2.new(0, math.floor(DEFAULT.margin * s), 1, -math.floor(DEFAULT.bottomOffset * s))
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

-- ===================== FILLING A CARD =====================
local function setIcon(card: Frame, image: string?, tint: string)
	local icon = card:FindFirstChild("Icon", true) :: Frame?
	if not icon then
		return
	end
	local gem = icon:FindFirstChild("Gem") :: Frame?
	local img = icon:FindFirstChild("Image") :: ImageLabel?
	if gem then
		gem.BackgroundColor3 = hex(tint)
		gem.Visible = not (image and image ~= "")
	end
	if img then
		img.Image = image or ""
		img.Visible = image ~= nil and image ~= ""
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
	local color = cfg.color
	local text = cfg.format
		:gsub("{amount}", function()
			return value(cfg.amountPrefix .. number(entry.amount), color, label.TextSize)
		end)
		:gsub("{label}", function()
			return value(payload.label, cfg.labelColor, label.TextSize)
		end)
	label.Text = text
	if entry.count > 1 then
		count.Visible = true
		count.Text = string.format("<font color=\"%s\">%s</font>", cfg.countColor, (cfg.countFormat:gsub("{count}", tostring(entry.count))))
	else
		count.Visible = false
	end
	body.Timer.Fill.BackgroundColor3 = hex(color)
	setIcon(card, cfg.icon or payload.icon, color)
end

local function fillSystem(entry: Entry)
	local card, cfg, payload = entry.card, entry.cfg, entry.payload
	local body = card:WaitForChild("Body")
	local color = payload.color or cfg.color
	local main = body.Row.Text.Main :: TextLabel
	local sub = body.Row.Text.Sub :: TextLabel
	main.Text = escape(payload.text)
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

local function pump()
	while #waiting > 0 and visibleCount() < DEFAULT.maxVisible do
		show(table.remove(waiting, 1))
	end
end

local function leave(entry: Entry)
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
	if kind == "levelup" or kind == "collection" then
		fillTier(entry, payload)
	elseif kind == "pickup" then
		fillPickup(entry)
	else
		fillSystem(entry)
	end
	card.Body.BackgroundTransparency = cfg.bodyTransparency
	card.BackgroundTransparency = cfg.borderTransparency
	table.insert(active, entry)
	startTimer(entry)

	TweenService:Create(card, tweenInfo(cfg.slideIn), { Position = UDim2.fromOffset(0, 0) }):Play()
	if cfg.sounds and cfg.sounds.show and os.clock() - lastShowSound > 0.1 then
		lastShowSound = os.clock()
		play(cfg.sounds.show)
	end
end

-- ===================== INCOMING =====================
local function insertWaiting(payload: any)
	local priority = Config.kinds[payload.kind] and Config.kinds[payload.kind].priority or 0
	local at = #waiting + 1
	for i, queued in ipairs(waiting) do
		local other = Config.kinds[queued.kind] and Config.kinds[queued.kind].priority or 0
		if other < priority then
			at = i
			break
		end
	end
	table.insert(waiting, at, payload)
end

local function merge(payload: any): boolean
	for _, entry in ipairs(active) do
		if entry.kind == "pickup" and entry.key == payload.key and not entry.leaving and not entry.dead then
			entry.count += 1
			entry.amount += payload.amount
			fillPickup(entry)
			startTimer(entry)
			local pop = entry.card:FindFirstChild("Pop") :: UIScale?
			if pop then
				pop.Scale = entry.cfg.pop.scale
				TweenService:Create(pop, TweenInfo.new(entry.cfg.pop.time, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
			return true
		end
	end
	for _, queued in ipairs(waiting) do
		if queued.kind == "pickup" and queued.key == payload.key then
			queued.count = (queued.count or 1) + 1
			queued.amount += payload.amount
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
