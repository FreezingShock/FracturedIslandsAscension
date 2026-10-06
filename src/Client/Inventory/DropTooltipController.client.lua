--[[
	DropTooltipController (LocalScript)
	Place inside: StarterPlayerScripts

	Cards over dropped items. Every instance tagged "DropTooltip" (LootService parts, ItemDrops models) is watched; the
	ones within DropTooltipConfig showRadius of the player get a BillboardGui cloned from ReplicatedStorage.GUI:
	  nearest drop            -> focused DropCard (rarity ring, description line)
	  next maxCards - 1       -> dimmed DropCards
	  the rest (maxChips)     -> DropChip (rarity dot + name)
	Visual only: the server owns the drop and its pickup, the client sends nothing. The plain DropLabel (and any other
	billboard on the drop) hides while its card or chip is showing.

	Decisions run every scanEvery seconds with hysteresis (show at showRadius, hide past hideRadius); tweens run on their own.
	Every visual carries a `dead` flag, so a tween that finishes after its card was recycled does nothing.
	Content comes from TooltipModule/Items.fromDrop (the same item -> tooltip mapping as the inventory tooltip).
	Config and recipes: Modules/Config/DropTooltipConfig. Template: tools/studio/build_drop_card.luau.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TAG = "DropTooltip"

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Config"):WaitForChild("DropTooltipConfig")) :: any
local TooltipItems = require(Modules:WaitForChild("TooltipModule"):WaitForChild("Items")) :: any
local Style = require(Modules:WaitForChild("TooltipModule"):WaitForChild("Style")) :: any
local GUI = ReplicatedStorage:WaitForChild("GUI")
local CARD_TEMPLATE = GUI:WaitForChild("DropCard")
local CHIP_TEMPLATE = GUI:WaitForChild("DropChip")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local host = Instance.new("Folder")
host.Name = "DropTooltips"
host.Parent = playerGui

local ghosts = workspace:FindFirstChild("DropTooltipGhosts") or Instance.new("Folder")
ghosts.Name = "DropTooltipGhosts"
ghosts.Parent = workspace

-- ===================== STATE =====================
type Visual = { gui: BillboardGui, kind: string, entry: any, focused: boolean, dead: boolean, tweens: { Tween }, ghost: Part? }
local entries: { [Instance]: any } = {}
local pools: { card: { BillboardGui }, chip: { BillboardGui } } = { card = {}, chip = {} }
local lastFocus: Instance? = nil
local lastClick = 0

local function easing(spec: any)
	return TweenInfo.new(spec.time, Enum.EasingStyle[spec.style or "Quad"], Enum.EasingDirection[spec.direction or "Out"])
end

local function play(vis: Visual, target: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(target, info, goal)
	table.insert(vis.tweens, tween)
	tween:Play()
	return tween
end

local function cancel(vis: Visual)
	for _, tween in ipairs(vis.tweens) do
		tween:Cancel()
	end
	table.clear(vis.tweens)
end

-- ===================== CONTENT =====================
local function describe(entry: any)
	local inst = entry.inst
	local info = TooltipItems.fromDrop({
		kind = inst:GetAttribute("DropKind") or "item",
		itemId = inst:GetAttribute("ItemId"),
		name = inst:GetAttribute("DropName") or "Item",
		count = inst:GetAttribute("Count") or 1,
		rarity = inst:GetAttribute("Rarity") or 0,
		color = inst:GetAttribute("DropColor") and ("#" .. inst:GetAttribute("DropColor")) or nil,
		skill = inst:GetAttribute("DropSkill"),
	})
	entry.info = info
	entry.cfg = Config.resolve(inst:GetAttribute("Rarity") or 0, inst:GetAttribute("ItemId"))
	return info
end

-- same recolouring as TooltipModule.styleTag (a tag is its base colour, a dark outer ring and a light inner ring)
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

local function ringColors(info: any, focused: boolean, cfg: any)
	if focused then
		return Style.color3(info.dark or Style.dark(info.titleColor)), Style.color3(info.titleColor)
	end
	return Style.color3(cfg.neutralOuter), Style.color3(cfg.neutralInner)
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

local function showDescription(card: Frame, info: any, cfg: any, focused: boolean)
	local want = info.description ~= nil and (focused or not cfg.descriptionOnFocus)
	local desc = card:FindFirstChild("DescriptionLabel") :: TextLabel
	local divider = card:FindFirstChild("Divider1") :: GuiObject
	if want then
		desc.Text = info.description
	end
	desc.Visible = want
	divider.Visible = want
end

local function renderCard(vis: Visual, instantRings: boolean)
	local entry = vis.entry
	local info, cfg = entry.info or describe(entry), entry.cfg
	local card = (vis.gui :: any).Group.Card :: Frame
	local titleFrame = card.TitleFrame
	local title = titleFrame.TitleLabel :: TextLabel
	title.Text = info.title
	title.TextColor3 = Style.color3(info.titleColor)
	local titleStroke = title:FindFirstChildOfClass("UIStroke")
	if titleStroke then
		titleStroke.Color = Style.color3(info.dark or Style.dark(info.titleColor))
	end

	local tagsFrame = titleFrame.ItemTags
	for _, child in ipairs(tagsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local proto = (vis.gui :: any).TagTemplate :: Frame
	for i, spec in ipairs(info.tags or {}) do
		if i > cfg.maxTags then
			break
		end
		local tag = proto:Clone()
		tag.Visible = true
		tag.LayoutOrder = i
		styleTag(tag, spec)
		tag.Parent = tagsFrame
	end

	local stack = titleFrame:FindFirstChild("StackLabel") :: TextLabel?
	local padding = titleFrame:FindFirstChildOfClass("UIPadding")
	if stack then
		stack.Visible = info.stack ~= nil
		if info.stack then
			stack.Text = "X" .. tostring(info.stack)
		end
		if padding then
			-- the count hangs off the right edge: reserve its width so a long name never runs under it
			padding.PaddingRight = UDim.new(0, 3 + (info.stack and (stack.TextBounds.X + 8) or 0))
		end
	end

	local icon = titleFrame.ItemIcon
	applyIcon(icon.ItemImage, info.icon)

	showDescription(card, info, cfg, vis.focused)

	local outer, inner = ringColors(info, vis.focused, cfg)
	if instantRings then
		card.StrokeOuter.Color, card.StrokeInner.Color = outer, inner
		icon.IconStrokeA.Color, icon.IconStrokeB.Color = inner, outer
	end
end

local function renderChip(vis: Visual)
	local entry = vis.entry
	local info = entry.info or describe(entry)
	local chip = (vis.gui :: any).Group.Chip :: Frame
	local color = Style.color3(info.titleColor)
	local dark = Style.color3(info.dark or Style.dark(info.titleColor))
	chip.NameLabel.Text = info.title .. (info.stack and (" X" .. info.stack) or "")
	chip.NameLabel.TextColor3 = color
	local stroke = chip.NameLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = dark
	end
	chip.Dot.BackgroundColor3 = color
	local dotStroke = chip.Dot:FindFirstChildOfClass("UIStroke")
	if dotStroke then
		dotStroke.Color = dark
	end
end

-- ===================== POOL + MOTION =====================
local function take(kind: string): BillboardGui
	local gui = table.remove(pools[kind]) :: BillboardGui?
	if gui then
		return gui
	end
	return (kind == "card" and CARD_TEMPLATE or CHIP_TEMPLATE):Clone() :: BillboardGui
end

local function release(vis: Visual)
	vis.dead = true
	cancel(vis)
	local gui = vis.gui
	gui.Parent = nil
	gui.Adornee = nil
	if #pools[vis.kind] < 12 then
		table.insert(pools[vis.kind], gui)
	else
		gui:Destroy()
	end
	if vis.ghost then
		vis.ghost:Destroy()
	end
end

local function setHidden(entry: any, hidden: boolean)
	-- hide the drop's own labels (DropLabel, the ItemDrops count label) while a card or chip is up
	if hidden and not entry.hiddenGuis then
		entry.hiddenGuis = {}
		for _, d in ipairs(entry.inst:GetDescendants()) do
			if d:IsA("BillboardGui") and d.Enabled then
				d.Enabled = false
				table.insert(entry.hiddenGuis, d)
			end
		end
	elseif not hidden and entry.hiddenGuis then
		for _, gui in ipairs(entry.hiddenGuis) do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		entry.hiddenGuis = nil
	end
end

local function targetTransparency(vis: Visual)
	local cfg = vis.entry.cfg
	if vis.kind == "chip" then
		return cfg.transparency.chip
	end
	return vis.focused and cfg.transparency.focused or cfg.transparency.unfocused
end

local function enter(entry: any, kind: string, focused: boolean, delay: number): Visual
	local cfg = entry.cfg
	local vis: Visual = { gui = take(kind), kind = kind, entry = entry, focused = focused, dead = false, tweens = {}, ghost = nil }
	local gui = vis.gui
	gui.Adornee = entry.adornee
	gui.StudsOffsetWorldSpace = kind == "card" and cfg.offset or cfg.chipOffset
	gui.MaxDistance = cfg.maxDistance
	local group = (gui :: any).Group :: CanvasGroup
	local scale = group.Scale :: UIScale
	if kind == "card" then
		renderCard(vis, true)
	else
		renderChip(vis)
	end
	local e = cfg.enter
	group.GroupTransparency = 1
	scale.Scale = kind == "card" and e.scale or 1
	group.Position = UDim2.new(0.5, 0, 1, kind == "card" and e.rise or 0)
	gui.Parent = host

	local info = TweenInfo.new(
		kind == "card" and e.time or cfg.chipFade,
		Enum.EasingStyle[e.style],
		Enum.EasingDirection[e.direction],
		0,
		false,
		delay
	)
	play(vis, group, info, { GroupTransparency = targetTransparency(vis), Position = UDim2.fromScale(0.5, 1) })
	if kind == "card" then
		play(vis, scale, info, { Scale = 1 })
		if cfg.flash then
			local inner = (group :: any).Card.StrokeInner :: UIStroke
			local base = inner.Thickness
			inner.Thickness = base
			local up = play(vis, inner, TweenInfo.new(cfg.flashTime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay + e.time * 0.5), { Thickness = base + 2 })
			up.Completed:Connect(function()
				if not vis.dead then
					play(vis, inner, TweenInfo.new(cfg.flashTime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Thickness = base })
				end
			end)
		end
	end
	return vis
end

local function exit(vis: Visual, pop: boolean)
	if vis.dead then
		return
	end
	cancel(vis)
	local cfg = vis.entry.cfg
	local group = (vis.gui :: any).Group :: CanvasGroup
	local scale = group.Scale :: UIScale
	local info, goalScale, drop
	if pop then
		info = TweenInfo.new(cfg.pop.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		goalScale, drop = cfg.pop.scale, 0
	else
		info = easing(cfg.exit)
		goalScale, drop = cfg.exit.scale, cfg.exit.drop
	end
	if vis.kind == "chip" then
		goalScale, drop = 1, 0
		info = TweenInfo.new(cfg.chipFade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	local fade = play(vis, group, info, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 1, drop) })
	play(vis, scale, info, { Scale = goalScale })
	fade.Completed:Connect(function()
		release(vis)
	end)
end

local function tweenFocus(vis: Visual)
	local cfg = vis.entry.cfg
	local info = easing(cfg.focus)
	local group = (vis.gui :: any).Group :: CanvasGroup
	local card = group.Card :: Frame
	local outer, inner = ringColors(vis.entry.info, vis.focused, cfg)
	play(vis, group, info, { GroupTransparency = targetTransparency(vis) })
	play(vis, card.StrokeOuter, info, { Color = outer })
	play(vis, card.StrokeInner, info, { Color = inner })
	local icon = card.TitleFrame.ItemIcon
	play(vis, icon.IconStrokeA, info, { Color = inner })
	play(vis, icon.IconStrokeB, info, { Color = outer })
	showDescription(card, vis.entry.info, cfg, vis.focused)
end

-- ===================== ENTRIES =====================
local function adorneeOf(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function positionOf(entry: any): Vector3?
	local inst = entry.inst
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil
end

local function setTarget(entry: any, kind: string?, focused: boolean, delay: number)
	local vis: Visual? = entry.vis
	if vis and not vis.dead and vis.kind == kind then
		if kind == "card" and vis.focused ~= focused then
			vis.focused = focused
			tweenFocus(vis)
		end
		return
	end
	if vis then
		exit(vis, false)
		entry.vis = nil
	end
	if kind then
		entry.vis = enter(entry, kind, focused, delay)
		setHidden(entry, true)
	else
		setHidden(entry, false)
	end
end

local function register(inst: Instance)
	if entries[inst] or not (inst:IsA("BasePart") or inst:IsA("Model")) then
		return
	end
	local entry = { inst = inst, adornee = adorneeOf(inst), active = false, vis = nil, info = nil, cfg = nil }
	entries[inst] = entry
	describe(entry)
	inst:GetAttributeChangedSignal("Count"):Connect(function()
		describe(entry)
		local vis: Visual? = entry.vis
		if vis and not vis.dead then
			if vis.kind == "card" then
				renderCard(vis, false)
			else
				renderChip(vis)
			end
		end
	end)
end

local function unregister(inst: Instance)
	local entry = entries[inst]
	if not entry then
		return
	end
	entries[inst] = nil
	local vis: Visual? = entry.vis
	if vis and not vis.dead then
		-- the drop is gone (picked up / expired): keep the card alive on a ghost anchor for the pop
		local at = entry.lastPos
		if at then
			local ghost = Instance.new("Part")
			ghost.Anchored, ghost.CanCollide, ghost.CanQuery, ghost.CanTouch = true, false, false, false
			ghost.Transparency = 1
			ghost.Size = Vector3.one * 0.2
			ghost.Position = at
			ghost.Parent = ghosts
			vis.ghost = ghost
			vis.gui.Adornee = ghost
		end
		exit(vis, true)
	end
	entry.vis = nil
	setHidden(entry, false)
end

for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
	register(inst)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(unregister)

-- ===================== SCAN =====================
local function clickSound(cfg: any)
	local s = cfg.sounds
	if not s.useUiClick or os.clock() - lastClick < 0.12 then
		return
	end
	local ui = workspace:FindFirstChild("UISounds")
	local click = ui and ui:FindFirstChild("Click")
	if click and click:IsA("Sound") then
		lastClick = os.clock()
		click:Play()
	end
end

local function scan()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local candidates = {}
	if root then
		for _, entry in pairs(entries) do
			local pos = positionOf(entry)
			local cfg = entry.cfg
			if pos and cfg and not cfg.disabled and entry.adornee and entry.adornee.Parent then
				entry.lastPos = pos
				local dist = (pos - root.Position).Magnitude
				entry.active = dist <= (entry.active and cfg.hideRadius or cfg.showRadius)
				if entry.active then
					entry.dist = dist
					table.insert(candidates, entry)
				end
			else
				entry.active = false
			end
		end
	else
		for _, entry in pairs(entries) do
			entry.active = false
		end
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

	local defaults = Config.defaults
	local cards, chips, newCount = 0, 0, 0
	local keep = {}
	local focusInst: Instance? = nil
	for _, entry in ipairs(candidates) do
		local kind: string? = nil
		if entry.cfg.maxCards ~= 0 and cards < defaults.maxCards then
			kind = "card"
			cards += 1
		elseif chips < defaults.maxChips then
			kind = "chip"
			chips += 1
		end
		local focused = kind == "card" and cards == 1
		if focused then
			focusInst = entry.inst
		end
		keep[entry] = true
		local fresh = kind ~= nil and not (entry.vis and not entry.vis.dead and entry.vis.kind == kind)
		setTarget(entry, kind, focused, fresh and newCount * entry.cfg.enter.stagger or 0)
		if fresh then
			newCount += 1
		end
	end
	for _, entry in pairs(entries) do
		if not keep[entry] and entry.vis then
			setTarget(entry, nil, false, 0)
		end
	end
	if focusInst and focusInst ~= lastFocus then
		clickSound(entries[focusInst].cfg)
	end
	lastFocus = focusInst
end

local accumulated = 0
RunService.Heartbeat:Connect(function(dt)
	accumulated += dt
	if accumulated < Config.defaults.scanEvery then
		return
	end
	accumulated = 0
	scan()
end)
