--[[
	DropTooltipController (LocalScript)
	Place inside: StarterPlayerScripts

	The tag over every dropped item (instances tagged "DropTooltip": LootService parts, ItemDrops models). Three stages by
	distance, one pooled GUI.DropTag BillboardGui per visible drop with a layer for each:
	  dot       far            a rarity-coloured gem that shrinks and fades with distance
	  folded    near           a small tag: gem + name + count. Everything is folded by default.
	  unfolded  aimed at       the full card, for the closest AIMED drop only (cursor over the tag, or the camera pointing at it)
	The layers morph into each other (the card grows out of the folded tag), see DropTooltipConfig for every number.

	Visual only: the server owns the drop and its pickup, the client sends nothing. The drop's own labels (DropLabel, the
	ItemDrops count label) stay hidden, this controller replaces them. Stage decisions run every config.scanEvery seconds;
	the aim test and all motion run every frame on small hand-made tracks (no TweenService instances to leak).

	Studio test hooks: each drop gets a client-local attribute DropStage ("dot" | "folded" | "unfolded" | ""), and
	workspace:SetAttribute("DropAimOverride", Vector2) replaces the aim point (viewport pixels).
	Content comes from TooltipModule/Items.fromDrop (the same item -> tooltip mapping as the inventory tooltip).
--]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local TAG = "DropTooltip"
local DOT_GEM_PX = 14 -- the template gem is this big; the dot's size setting is in pixels
local LAYER_PAD = 10 -- UIPadding of the Folded and Card layers (keeps the outside rings inside the CanvasGroup)
local POOL_MAX = 40

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"):WaitForChild("DropTooltipConfig")) :: any
local TooltipItems = require(Modules:WaitForChild("TooltipModule"):WaitForChild("Items")) :: any
local Style = require(Modules:WaitForChild("TooltipModule"):WaitForChild("Style")) :: any
local TEMPLATE = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("DropTag")
local DEFAULTS = Config.defaults

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local host = Instance.new("Folder")
host.Name = "DropTags"
host.Parent = playerGui

local entries: { [Instance]: any } = {} -- one per tracked drop
local unfolded: { [any]: boolean } = {} -- entries whose card is open (at most maxUnfolded)
local activeTags: { [any]: boolean } = {} -- tags that are animating or showing
local pool: { any } = {}
local frameId = 0
local scanClock = 0
local lastClick = 0

-- ===================== TRACKS =====================
-- A track is one number that eases toward a target: go() retargets it from where it is NOW, so interrupting a motion
-- never jumps. Same easing styles as TweenService (TweenService:GetValue), no tween instances.
local function newTrack(v: number)
	return { v = v, from = v, to = v, t = 1, dur = 1, delay = 0, style = Enum.EasingStyle.Linear, dir = Enum.EasingDirection.Out }
end

local function go(tr: any, to: number, time: number, style: string?, direction: string?, delay: number?)
	tr.from, tr.to, tr.t, tr.dur, tr.delay = tr.v, to, 0, math.max(time, 0.001), delay or 0
	tr.style = Enum.EasingStyle[style or "Quad"]
	tr.dir = Enum.EasingDirection[direction or "Out"]
end

local function snap(tr: any, v: number)
	tr.v, tr.from, tr.to, tr.t, tr.delay = v, v, v, 1, 0
end

--- Advance one track. True while the track was moving (or waiting out its delay) this frame, so the owner re-applies it.
local function advance(tr: any, dt: number): boolean
	if tr.t >= 1 then
		return false
	end
	if tr.delay > 0 then
		tr.delay -= dt
		if tr.delay > 0 then
			return true
		end
		dt = -tr.delay
		tr.delay = 0
	end
	tr.t = math.min(1, tr.t + dt / tr.dur)
	if tr.t >= 1 then
		tr.v = tr.to
	else
		tr.v = tr.from + (tr.to - tr.from) * TweenService:GetValue(tr.t, tr.style, tr.dir)
	end
	return true
end

-- ===================== TEMPLATE FACTS =====================
local function measureLineHeight(): number
	local desc = TEMPLATE.Group.Card.Card.Details.DescriptionLabel :: TextLabel
	local ok, size = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = "Ag"
		params.Font = desc.FontFace
		params.Size = desc.TextSize
		params.Width = 10000
		return TextService:GetTextBoundsAsync(params)
	end)
	return ok and size.Y or desc.TextSize * 1.2
end
local LINE_HEIGHT = measureLineHeight()

-- ===================== CONTENT =====================
local function describe(e: any)
	local inst = e.inst
	local colorHex = inst:GetAttribute("DropColor")
	e.info = TooltipItems.fromDrop({
		kind = inst:GetAttribute("DropKind") or "item",
		itemId = inst:GetAttribute("ItemId"),
		name = inst:GetAttribute("DropName") or "Item",
		count = inst:GetAttribute("Count") or 1,
		rarity = inst:GetAttribute("Rarity") or 0,
		color = colorHex and ("#" .. colorHex) or nil,
		skill = inst:GetAttribute("DropSkill"),
	})
	e.cfg = Config.resolve(inst:GetAttribute("Rarity") or 0, inst:GetAttribute("ItemId"))
end

-- the same recolouring as TooltipModule.styleTag: a tag is a base colour with a dark outer and a light inner ring
local function styleTag(tag: Frame, spec: any)
	local base = Style.hex(spec.color or "#AAAAAA")
	local dark = Style.hex(spec.dark or Style.dark(base))
	local light = Style.hex(spec.light or Style.light(base))
	if base == "#AAAAAA" then
		light = "#FFFFFF"
	end
	tag.BackgroundColor3 = Style.color3(base)
	local darkStroke = tag:FindFirstChild("UISDark") :: UIStroke?
	if darkStroke then
		darkStroke.Color = Style.color3(dark)
	end
	local lightStroke = tag:FindFirstChild("UISLight") :: UIStroke?
	if lightStroke then
		lightStroke.Color = Style.color3(light)
	end
	local label = tag:FindFirstChild("TagLabel") :: TextLabel?
	if label then
		label.Text = tostring(spec.text or "?"):upper()
		label.TextColor3 = Style.color3(spec.textColor or light)
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Style.color3(dark)
		end
	end
end

local function applyIcon(img: ImageLabel, icon: any)
	local image = icon and icon.image
	if type(image) ~= "string" or image == "" then
		img.Visible = false
		return
	end
	img.Image = image
	img.ImageRectOffset = icon.rectOffset or Vector2.zero
	img.ImageRectSize = icon.rectSize or Vector2.zero
	img.ImageColor3 = icon.imageColor or Color3.new(1, 1, 1)
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.Visible = true
end

local function strokeOf(label: Instance): UIStroke?
	return label:FindFirstChildOfClass("UIStroke")
end

--- Fill every layer of a tag from the drop's summary (colours, text, tags, icon, description).
local function render(tag: any, e: any)
	local info, cfg = e.info, e.cfg
	local color = Style.color3(info.titleColor)
	local dark = Style.color3(info.dark or Style.dark(info.titleColor))
	tag.color, tag.dark = color, dark
	tag.neutralOuter, tag.neutralInner = Style.color3(cfg.neutralOuter), Style.color3(cfg.neutralInner)

	-- dot
	tag.halo.ImageColor3 = color
	tag.halo.ImageTransparency = cfg.stages.dot.haloTransparency
	tag.gem.BackgroundColor3 = color
	tag.gemStroke.Color = dark

	-- folded
	tag.chipDot.BackgroundColor3 = color
	tag.chipDotStroke.Color = dark
	tag.chipTitle.Text = info.title
	tag.chipTitle.TextColor3 = color
	local chipStroke = strokeOf(tag.chipTitle)
	if chipStroke then
		chipStroke.Color = dark
	end
	tag.chipCount.Visible = info.stack ~= nil
	if info.stack then
		tag.chipCount.Text = "X" .. tostring(info.stack)
	end
	tag.chip.StrokeOuter.Color, tag.chip.StrokeInner.Color = tag.neutralOuter, tag.neutralInner

	-- card
	tag.title.Text = info.title
	tag.title.TextColor3 = color
	local titleStroke = strokeOf(tag.title)
	if titleStroke then
		titleStroke.Color = dark
	end
	for _, child in ipairs(tag.itemTags:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i, spec in ipairs(info.tags or {}) do
		if i > cfg.layout.maxTags then
			break
		end
		local pill = tag.tagTemplate:Clone()
		pill.Visible = true
		pill.LayoutOrder = i
		styleTag(pill, spec)
		pill.Parent = tag.itemTags
	end
	tag.stack.Visible = info.stack ~= nil
	if info.stack then
		tag.stack.Text = "X" .. tostring(info.stack)
	end
	-- the count hangs off the right edge: reserve its width so a long name never runs under it
	tag.titlePadding.PaddingRight = UDim.new(0, 3 + (info.stack and (tag.stack.TextBounds.X + 8) or 0))
	applyIcon(tag.itemImage, info.icon)
	local hasDescription = type(info.description) == "string" and info.description ~= ""
	tag.hasDetails = hasDescription
	tag.details.Visible = hasDescription
	tag.desc.Text = hasDescription and info.description or ""
	tag.ring = -1 -- forces the next apply to repaint the rings
end

-- ===================== TAG OBJECTS =====================
local function newTag()
	local gui = TEMPLATE:Clone() :: any
	local group = gui.Group
	local dotLayer, foldedLayer, cardLayer = group.Dot, group.Folded, group.Card
	local card2 = cardLayer.Card
	local titleFrame = card2.TitleFrame
	local icon = titleFrame.ItemIcon
	local desc = card2.Details.DescriptionLabel
	local anchor = Instance.new("Attachment")
	anchor.Name = "DropTagAnchor"
	anchor.Parent = workspace.Terrain
	gui.Adornee = anchor

	-- a description is cut after layout.descriptionLines lines
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(math.huge, 12 + (DEFAULTS.layout.descriptionLines or 2) * LINE_HEIGHT)
	limit.Parent = desc
	desc.TextTruncate = Enum.TextTruncate.AtEnd

	return {
		gui = gui,
		anchor = anchor,
		tagTemplate = gui.TagTemplate,
		dot = dotLayer,
		dotScale = dotLayer.Scale,
		dotSize = dotLayer.Body.SizeScale,
		halo = dotLayer.Body.Halo,
		gem = dotLayer.Body.Gem,
		gemStroke = dotLayer.Body.Gem:FindFirstChildOfClass("UIStroke"),
		folded = foldedLayer,
		foldedScale = foldedLayer.Scale,
		chip = foldedLayer.Chip,
		chipDot = foldedLayer.Chip.Dot,
		chipDotStroke = foldedLayer.Chip.Dot:FindFirstChildOfClass("UIStroke"),
		chipTitle = foldedLayer.Chip.TitleLabel,
		chipCount = foldedLayer.Chip.CountLabel,
		cardLayer = cardLayer,
		cardScale = cardLayer.Scale,
		card2 = card2,
		titleFrame = titleFrame,
		titlePadding = titleFrame:FindFirstChildOfClass("UIPadding"),
		title = titleFrame.TitleLabel,
		itemTags = titleFrame.ItemTags,
		stack = titleFrame.StackLabel,
		itemImage = icon.ItemImage,
		iconStrokeA = icon.IconStrokeA,
		iconStrokeB = icon.IconStrokeB,
		details = card2.Details,
		detailsList = card2.Details:FindFirstChildOfClass("UIListLayout"),
		desc = desc,
		tr = {
			dotA = newTrack(0),
			dotS = newTrack(1),
			dotSize = newTrack(1),
			dotOp = newTrack(1),
			foldA = newTrack(0),
			foldS = newTrack(1),
			foldR = newTrack(0),
			cardA = newTrack(0),
			cardS = newTrack(1),
			ring = newTrack(0),
			reveal = newTrack(0),
			flash = newTrack(0),
		},
		want = { dot = false, folded = false, card = false },
		footprint = 0.85,
		detailsH = 0,
		hasDetails = false,
		ring = -1,
		closing = false,
	}
end

local function resetTag(tag: any)
	for _, tr in pairs(tag.tr) do
		snap(tr, 0)
	end
	snap(tag.tr.dotS, 1)
	snap(tag.tr.dotSize, 1)
	snap(tag.tr.dotOp, 1)
	snap(tag.tr.foldS, 1)
	snap(tag.tr.cardS, 1)
	tag.want.dot, tag.want.folded, tag.want.card = false, false, false
	tag.closing = false
	tag.measureAfter = nil
	tag.flashBack = false
	tag.lifted = false
	tag.losAt = 0
	tag.gui.AlwaysOnTop = false
	tag.dot.Visible, tag.folded.Visible, tag.cardLayer.Visible = false, false, false
end

local function acquire(e: any)
	local tag = table.remove(pool) or newTag()
	resetTag(tag)
	tag.entry = e
	tag.anchor.WorldPosition = e.anchorPos
	tag.anchorAt = e.anchorPos
	tag.gui.Parent = host -- in the DataModel before render, so text sizes (TextBounds) are known
	render(tag, e)
	activeTags[tag] = true
	return tag
end

local function release(tag: any)
	activeTags[tag] = nil
	tag.entry = nil
	tag.gui.Parent = nil
	if #pool < POOL_MAX then
		table.insert(pool, tag)
	else
		tag.anchor:Destroy()
		tag.gui:Destroy()
	end
end

-- ===================== APPLY (tracks -> instances) =====================
local function alphaToTransparency(a: number, atFull: number): number
	return 1 - a * (1 - atFull)
end

local function paintRings(tag: any, ring: number)
	local outer = tag.neutralOuter:Lerp(tag.dark, ring)
	local inner = tag.neutralInner:Lerp(tag.color, ring)
	tag.card2.StrokeOuter.Color, tag.card2.StrokeInner.Color = outer, inner
	tag.iconStrokeA.Color, tag.iconStrokeB.Color = inner, outer
end

local function apply(tag: any)
	local e = tag.entry
	local cfg = e and e.cfg or DEFAULTS
	local layout, trans, tr = cfg.layout, cfg.transparency, tag.tr

	local dotAlpha = tr.dotA.v * tr.dotOp.v
	tag.dot.Visible = dotAlpha > 0.003
	tag.dot.GroupTransparency = alphaToTransparency(dotAlpha, trans.dot)
	tag.dotScale.Scale = math.max(tr.dotS.v, 0.01)
	tag.dotSize.Scale = math.max(tr.dotSize.v, 0.01)
	tag.dot.Position = UDim2.new(0.5, 0, 0.5, -layout.dotLift)

	tag.folded.Visible = tr.foldA.v > 0.003
	tag.folded.GroupTransparency = alphaToTransparency(tr.foldA.v, trans.folded)
	tag.foldedScale.Scale = math.max(tr.foldS.v, 0.01)
	tag.folded.Position = UDim2.new(0.5, 0, 0.5, -layout.foldedLift + tr.foldR.v)

	local measuring = tag.measureAfter ~= nil
	tag.cardLayer.Visible = tr.cardA.v > 0.003 or measuring
	tag.cardLayer.GroupTransparency = alphaToTransparency(tr.cardA.v, trans.card)
	tag.cardScale.Scale = measuring and 1 or math.max(tr.cardS.v, 0.01)
	tag.cardLayer.Position = UDim2.new(0.5, 0, 0.5, -layout.cardLift)

	if math.abs(tr.ring.v - tag.ring) > 0.002 then
		tag.ring = tr.ring.v
		paintRings(tag, tr.ring.v)
	end
	if tag.hasDetails then
		tag.details.Size = UDim2.new(1, 0, 0, math.floor(tag.detailsH * tr.reveal.v + 0.5))
	end
	if tr.flash.v > 0.001 or tag.flashBack then
		tag.card2.StrokeInner.Thickness = 2 + 2 * tr.flash.v
	end
end

-- ===================== LAYER MOTION =====================
local function cue(tag: any, slot: string)
	local e = tag.entry
	local cfg = e and e.cfg or DEFAULTS
	local sounds = cfg.sounds
	local id = sounds[slot]
	if type(id) == "string" and id ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = id
		sound.Volume = sounds.volume
		sound.RollOffMaxDistance = 60
		sound.Parent = tag.anchor
		sound:Play()
		Debris:AddItem(sound, 5)
	end
	if slot == "unfold" and sounds.useUiClick and os.clock() - lastClick > 0.12 then
		local ui = workspace:FindFirstChild("UISounds")
		local click = ui and ui:FindFirstChild("Click")
		if click and click:IsA("Sound") then
			lastClick = os.clock()
			click:Play()
		end
	end
end

local function showDot(tag: any, delay: number)
	local m, tr = tag.entry.cfg.motion.dotIn, tag.tr
	if tr.dotA.v < 0.01 then
		snap(tr.dotS, m.scale)
	end
	go(tr.dotA, 1, m.time, m.style, m.direction, delay)
	go(tr.dotS, 1, m.time, m.style, m.direction, delay)
	cue(tag, "dotAppear")
end

local function hideDot(tag: any, delay: number)
	local m, tr = tag.entry.cfg.motion.dotOut, tag.tr
	go(tr.dotA, 0, m.time, m.style, m.direction, delay)
	go(tr.dotS, m.scale, m.time, m.style, m.direction, delay)
end

local function showFolded(tag: any, delay: number)
	local m, tr = tag.entry.cfg.motion.foldedIn, tag.tr
	if tr.foldA.v < 0.01 then
		snap(tr.foldS, m.scale)
		snap(tr.foldR, m.rise)
	end
	go(tr.foldA, 1, m.time, m.style, m.direction, delay)
	go(tr.foldS, 1, m.time, m.style, m.direction, delay)
	go(tr.foldR, 0, m.time, m.style, m.direction, delay)
	cue(tag, "foldedAppear")
end

local function hideFolded(tag: any, time: number?)
	local m, tr = tag.entry.cfg.motion.foldedOut, tag.tr
	local t = time or m.time
	go(tr.foldA, 0, t, m.style, m.direction)
	go(tr.foldS, m.scale, t, m.style, m.direction)
	go(tr.foldR, m.drop, t, m.style, m.direction)
end

--- The card is made visible first and measured one frame later (a hidden CanvasGroup has no layout yet), then startUnfold runs.
local function showCard(tag: any, delay: number)
	tag.measureAfter = frameId
	tag.unfoldDelay = delay
	tag.cardLayer.Visible = true
	tag.cardLayer.GroupTransparency = 1
	tag.cardScale.Scale = 1
	cue(tag, "unfold")
end

local function startUnfold(tag: any)
	tag.measureAfter = nil
	local e = tag.entry
	if not e then
		return
	end
	local cfg = e.cfg
	local m, tr = cfg.motion.unfold, tag.tr
	local cardW, chipW = tag.card2.AbsoluteSize.X, tag.chip.AbsoluteSize.X
	if m.fromFootprint and cardW > 1 and chipW > 1 then
		tag.footprint = math.clamp(chipW / cardW, m.minFrom, 0.95)
	else
		tag.footprint = 0.85
	end
	tag.detailsH = tag.hasDetails and tag.detailsList.AbsoluteContentSize.Y or 0
	local d = tag.unfoldDelay or 0
	snap(tr.cardA, 0)
	snap(tr.cardS, tag.footprint)
	go(tr.cardA, 1, m.time * 0.8, m.style, m.direction, d)
	go(tr.cardS, 1, m.time, m.style, m.direction, d)
	go(tr.ring, 1, m.ringTime, "Quad", "Out", d)
	snap(tr.reveal, 0)
	go(tr.reveal, 1, m.detailsTime, "Quad", "Out", d + m.detailsDelay)
	if cfg.flash then
		snap(tr.flash, 0)
		go(tr.flash, 1, cfg.flashTime * 0.5, "Quad", "Out", d + m.time * 0.5)
		tag.flashBack = true
	end
end

local function hideCard(tag: any)
	tag.measureAfter = nil
	local m, tr = tag.entry.cfg.motion.fold, tag.tr
	go(tr.cardA, 0, m.time, m.style, m.direction)
	go(tr.cardS, tag.footprint, m.time, m.style, m.direction)
	go(tr.ring, 0, m.time, "Quad", "Out")
	go(tr.reveal, 0, m.detailsTime, "Quad", "Out")
end

--- Move a tag to a stage; every layer that has to change starts its own motion (they overlap, so there is never a blank frame).
local function transition(tag: any, prev: string?, stage: string, delay: number)
	local m = tag.entry.cfg.motion
	local want = tag.want
	tag.closing = false
	local wantDot, wantFolded, wantCard = stage == "dot", stage == "folded", stage == "unfolded"
	if wantDot and not want.dot then
		showDot(tag, delay)
	elseif not wantDot and want.dot then
		hideDot(tag, 0)
	end
	if wantFolded and not want.folded then
		showFolded(tag, prev == "unfolded" and m.fold.foldedInDelay or delay)
	elseif not wantFolded and want.folded then
		hideFolded(tag, wantCard and m.unfold.foldedOut or nil)
	end
	if wantCard and not want.card then
		showCard(tag, delay)
	elseif not wantCard and want.card then
		hideCard(tag)
		cue(tag, "fold")
	end
	want.dot, want.folded, want.card = wantDot, wantFolded, wantCard
end

--- Take a tag off the screen: "exit" fades and sinks (left range), "pop" is the quick pop when the drop was picked up.
local function closeTag(tag: any, mode: string)
	local cfg = tag.entry.cfg
	local m, tr = cfg.motion, tag.tr
	tag.measureAfter = nil
	if mode == "pop" then
		local p = m.pop
		for _, pair in ipairs({ { tr.dotA, tr.dotS }, { tr.foldA, tr.foldS }, { tr.cardA, tr.cardS } }) do
			if pair[1].v > 0.003 or pair[1].to > 0.003 then
				go(pair[1], 0, p.time, "Quad", "Out")
				go(pair[2], p.scale, p.time, "Quad", "Out")
			end
		end
	else
		local x = m.exit
		if tag.want.dot then
			hideDot(tag, 0)
		end
		if tag.want.folded then
			go(tr.foldA, 0, x.time, x.style, x.direction)
			go(tr.foldS, x.scale, x.time, x.style, x.direction)
			go(tr.foldR, x.drop, x.time, x.style, x.direction)
		end
		if tag.want.card then
			go(tr.cardA, 0, x.time, x.style, x.direction)
			go(tr.cardS, x.scale, x.time, x.style, x.direction)
			go(tr.ring, 0, x.time, "Quad", "Out")
			go(tr.reveal, 0, x.time, "Quad", "Out")
		end
	end
	tag.want.dot, tag.want.folded, tag.want.card = false, false, false
	tag.closing = true
end

local function tagIdle(tag: any): boolean
	local tr = tag.tr
	return tr.dotA.t >= 1 and tr.foldA.t >= 1 and tr.cardA.t >= 1 and tr.dotA.v < 0.003 and tr.foldA.v < 0.003 and tr.cardA.v < 0.003
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude

--- True when nothing solid is between the camera and the anchor. People, mobs and other drops do not count as walls.
local function clearLine(from: Vector3, to: Vector3): boolean
	local excluded = { player.Character }
	losParams.FilterDescendantsInstances = excluded
	for _ = 1, 4 do
		local hit = workspace:Raycast(from, to - from, losParams)
		if not hit then
			return true
		end
		local model = hit.Instance:FindFirstAncestorOfClass("Model")
		local owner = model or hit.Instance
		if (model and model:FindFirstChildOfClass("Humanoid")) or CollectionService:HasTag(owner, TAG) or CollectionService:HasTag(hit.Instance, TAG) then
			table.insert(excluded, owner)
			losParams.FilterDescendantsInstances = excluded
		else
			return false
		end
	end
	return true
end

local function updateTag(tag: any, dt: number)
	if tag.measureAfter and frameId > tag.measureAfter then
		startUnfold(tag)
	end
	local moved = false
	for _, tr in pairs(tag.tr) do
		if advance(tr, dt) then
			moved = true
		end
	end
	if tag.flashBack and tag.tr.flash.t >= 1 then
		if tag.tr.flash.v > 0.5 then
			go(tag.tr.flash, 0, tag.entry and tag.entry.cfg.flashTime * 0.5 or 0.12, "Quad", "In")
		else
			tag.flashBack = false
			moved = true
		end
	end
	if moved or tag.dirty then
		tag.dirty = false
		apply(tag)
	end
	-- the open card sits on top of other tags and nameplates, but only while the drop is in view (never through a wall)
	local camera = workspace.CurrentCamera
	local open = tag.entry ~= nil and camera ~= nil and (tag.tr.cardA.v > 0.003 or tag.measureAfter ~= nil)
	if open and tag.entry.cfg.layout.cardAlwaysOnTop then
		local now = os.clock()
		if now - (tag.losAt or 0) > 0.1 then
			tag.losAt = now
			tag.gui.AlwaysOnTop = clearLine(camera.CFrame.Position, tag.anchorAt)
		end
		tag.lifted = true
	elseif tag.lifted then
		tag.gui.AlwaysOnTop = false
		tag.lifted = false
	end
	if tag.closing and tagIdle(tag) then
		release(tag)
	end
end

-- ===================== ENTRIES =====================
local function restOf(inst: Instance): Vector3
	if inst:IsA("Model") then
		local base = inst:GetAttribute("BasePos")
		if inst:GetAttribute("Settled") and typeof(base) == "Vector3" then
			return base
		end
		return inst:GetPivot().Position
	end
	return (inst :: BasePart).Position
end

local function setHidden(e: any, hidden: boolean)
	-- the drop's own labels (DropLabel, the ItemDrops count label) stay off while this controller draws the tag
	if hidden and not e.hiddenGuis then
		e.hiddenGuis = {}
		for _, d in ipairs(e.inst:GetDescendants()) do
			if d:IsA("BillboardGui") and d.Enabled then
				d.Enabled = false
				table.insert(e.hiddenGuis, d)
			end
		end
	elseif not hidden and e.hiddenGuis then
		for _, gui in ipairs(e.hiddenGuis) do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		e.hiddenGuis = nil
	end
end

local function setStage(e: any, stage: string?, delay: number)
	local prev = e.stage
	if prev == stage then
		return
	end
	e.stage = stage
	e.inst:SetAttribute("DropStage", stage or "")
	if not stage then
		if e.tag then
			closeTag(e.tag, "exit")
			e.tag = nil
		end
		return
	end
	if not e.tag then
		e.tag = acquire(e)
	end
	transition(e.tag, prev, stage, delay)
end

local function applyStage(e: any, delay: number?)
	local stage = e.base
	if stage == "folded" and unfolded[e] then
		stage = "unfolded"
	end
	setStage(e, stage, delay or 0)
end

local function dotLook(cfg: any, dist: number): (number, number)
	local s = cfg.stages.dot
	local u = math.clamp((dist - s.nearAt) / math.max(s.farAt - s.nearAt, 0.001), 0, 1)
	local px = s.size.near + (s.size.far - s.size.near) * u
	local opacity = s.opacity.near + (s.opacity.far - s.opacity.near) * u
	local edge = math.clamp((s.hide - dist) / math.max(s.fadeBand, 0.001), 0, 1)
	return px / DOT_GEM_PX, opacity * edge
end

local function scan()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local list = {}
	for _, e in pairs(entries) do
		e.rest = restOf(e.inst)
		e.anchorPos = e.rest + Vector3.new(0, e.cfg.layout.anchorLift, 0)
		if root then
			local d = (e.rest - root.Position).Magnitude
			e.dist = d
			local st = e.cfg.stages
			e.foldedActive = d <= (e.foldedActive and st.folded.hide or st.folded.show)
			e.dotActive = d <= (e.dotActive and st.dot.hide or st.dot.show)
			if not e.cfg.disabled and (e.foldedActive or e.dotActive) then
				table.insert(list, e)
			end
		else
			e.dist = math.huge
			e.foldedActive, e.dotActive = false, false
		end
		e.base = nil
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	local folded, dots, fresh = 0, 0, 0
	for _, e in ipairs(list) do
		if e.foldedActive and folded < DEFAULTS.stages.folded.max then
			e.base = "folded"
			folded += 1
		elseif e.dotActive and dots < DEFAULTS.stages.dot.max then
			e.base = "dot"
			dots += 1
		end
	end
	for _, e in pairs(entries) do
		if e.base ~= "folded" and unfolded[e] then
			unfolded[e] = nil
			e.selSince = nil
		end
		local delay = 0
		if e.base and not e.tag then
			delay = fresh * e.cfg.motion.stagger
			fresh += 1
		end
		applyStage(e, delay)
		local tag = e.tag
		if tag then
			if tag.anchorAt ~= e.anchorPos then
				tag.anchorAt = e.anchorPos
				tag.anchor.WorldPosition = e.anchorPos
			end
			if e.stage == "dot" then
				local size, opacity = dotLook(e.cfg, e.dist)
				local smooth = e.cfg.motion.sizeSmoothing
				go(tag.tr.dotSize, size, smooth, "Linear", "Out")
				go(tag.tr.dotOp, opacity, smooth, "Linear", "Out")
			end
		end
	end
end

-- ===================== AIM =====================
local function aimPoint(camera: Camera): Vector2
	if RunService:IsStudio() then
		local override = workspace:GetAttribute(DEFAULTS.debug.aimAttribute)
		if typeof(override) == "Vector2" then
			return override
		end
	end
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		return camera.ViewportSize * 0.5
	end
	return UserInputService:GetMouseLocation()
end

--- 0 = not aimed. With hoverFirst: 3 = the aim point is right on the drop's gem, 2 = inside its tag (or the open card),
--- 1 = pointed in the general direction (inside aimRadius). Without hoverFirst every hit is 1 (closest drop wins).
local function aimLevel(e: any, aim: Vector2, viewportHeight: number): number
	local u = e.cfg.stages.unfold
	local first = u.hoverFirst
	local dx, dy = aim.X - e.sx, aim.Y - e.sy
	local d2 = dx * dx + dy * dy
	local hover = u.hoverRadius * viewportHeight
	if d2 <= hover * hover then
		return first and 3 or 1
	end
	local tag = e.tag
	if tag then
		-- the folded tag (or the open card) counts too, so resting the cursor on it keeps it open
		local frame = e.stage == "unfolded" and tag.card2 or tag.chip
		local lift = e.stage == "unfolded" and e.cfg.layout.cardLift or e.cfg.layout.foldedLift
		local size = frame.AbsoluteSize
		local bottom = e.sy - lift - LAYER_PAD
		local rectTop = bottom - size.Y - u.aimPad
		if math.abs(dx) <= size.X * 0.5 + u.aimPad and aim.Y >= rectTop and aim.Y <= e.sy + u.aimPad then
			return first and 2 or 1
		end
	end
	local radius = u.aimRadius * viewportHeight * (e.stage == "unfolded" and u.stick or 1)
	return d2 <= radius * radius and 1 or 0
end

local function countKeys(t: { [any]: any }): number
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local function updateAim(now: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local slots = DEFAULTS.stages.unfold.maxUnfolded
	local aim = aimPoint(camera)
	local height = camera.ViewportSize.Y
	local aimed = {}
	for _, e in pairs(entries) do
		if e.stage == "folded" or e.stage == "unfolded" then
			local point, onScreen = camera:WorldToViewportPoint(e.anchorPos)
			e.sx, e.sy = point.X, point.Y
			e.aimLevel = 0
			if onScreen and point.Z > 0 and e.dist <= e.cfg.stages.unfold.range then
				e.aimLevel = aimLevel(e, aim, height)
			end
			if e.aimLevel > 0 then
				e.aimedUntil = now + e.cfg.stages.unfold.hold
				table.insert(aimed, e)
			end
		end
	end
	-- pointed AT beats pointed near; among equals the closest to the player wins
	table.sort(aimed, function(a, b)
		if a.aimLevel ~= b.aimLevel then
			return a.aimLevel > b.aimLevel
		end
		return a.dist < b.dist
	end)

	local desired = {}
	local count = 0
	for _, e in ipairs(aimed) do
		if count < slots then
			desired[e] = true
			count += 1
		end
	end
	for e in pairs(unfolded) do -- a card that lost the aim stays for `hold` seconds if there is room
		if count < slots and not desired[e] and now <= (e.aimedUntil or 0) then
			desired[e] = true
			count += 1
		end
	end
	if count == 0 and DEFAULTS.stages.unfold.idleNearest then
		local best
		for _, e in pairs(entries) do
			if e.stage == "folded" and e.dist <= DEFAULTS.stages.unfold.idleNearestRadius and (not best or e.dist < best.dist) then
				best = e
			end
		end
		if best then
			desired[best] = true
		end
	end

	for e in pairs(unfolded) do -- the hold ran out
		if not desired[e] and now > (e.aimedUntil or 0) then
			unfolded[e] = nil
			e.selSince = nil
			applyStage(e, 0)
		end
	end
	local switchDelay = DEFAULTS.stages.unfold.switchDelay
	for _, e in ipairs(aimed) do
		if desired[e] and not unfolded[e] then
			if countKeys(unfolded) < slots then
				unfolded[e] = true
				e.selSince = nil
				applyStage(e, 0)
			else
				e.selSince = e.selSince or now
				if now - e.selSince >= switchDelay then
					for victim in pairs(unfolded) do
						if not desired[victim] then
							unfolded[victim] = nil
							victim.selSince = nil
							applyStage(victim, 0)
							unfolded[e] = true
							e.selSince = nil
							applyStage(e, 0)
							break
						end
					end
				end
			end
		end
	end
	for _, e in pairs(entries) do
		if not desired[e] then
			e.selSince = nil
		end
	end
	if DEFAULTS.stages.unfold.idleNearest then
		for e in pairs(desired) do
			if not unfolded[e] and countKeys(unfolded) < slots then
				unfolded[e] = true
				applyStage(e, 0)
			end
		end
	end
end

-- ===================== LIFECYCLE =====================
local function register(inst: Instance)
	if entries[inst] or not (inst:IsA("BasePart") or inst:IsA("Model")) then
		return
	end
	local e: any = { inst = inst, dist = math.huge, born = os.clock() }
	local ok, err = pcall(describe, e)
	if not ok then
		warn("[DropTooltip] could not describe " .. inst:GetFullName() .. ": " .. tostring(err))
		return
	end
	e.rest = restOf(inst)
	e.anchorPos = e.rest + Vector3.new(0, e.cfg.layout.anchorLift, 0)
	entries[inst] = e
	setHidden(e, true)
	e.countConn = inst:GetAttributeChangedSignal("Count"):Connect(function()
		describe(e)
		local tag = e.tag
		if tag and not tag.closing then
			render(tag, e)
			tag.dirty = true
		end
	end)
end

local function unregister(inst: Instance)
	local e = entries[inst]
	if not e then
		return
	end
	entries[inst] = nil
	unfolded[e] = nil
	if e.countConn then
		e.countConn:Disconnect()
	end
	if e.tag then
		-- the drop is gone (picked up / expired): the tag pops where it stood, then releases itself
		cue(e.tag, "pickup")
		closeTag(e.tag, "pop")
		e.tag = nil
	end
	if inst.Parent then
		setHidden(e, false)
	end
end

for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
	register(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(unregister)

RunService.PreRender:Connect(function(dt)
	frameId += 1
	local now = os.clock()
	scanClock += dt
	if scanClock >= DEFAULTS.scanEvery then
		scanClock = 0
		scan()
	end
	updateAim(now)
	for tag in pairs(activeTags) do
		updateTag(tag, dt)
	end
end)
