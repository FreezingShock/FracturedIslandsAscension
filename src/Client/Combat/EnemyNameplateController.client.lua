--[[
	EnemyNameplateController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	The nameplate over every model tagged "Enemy" (every enemy has one unless its EnemyConfig entry says nameplate = false):
	name, level badge, health bar with the HP number, and a row of tag chips (element, debuffs, active effects).
	Cloned from the hand-made templates ReplicatedStorage.GUI.EnemyNameplate and EnemyNameplate_Tag (restyle them in Studio,
	tools/studio/build_enemy_nameplate.luau lists the names this script looks up). No UI is built here. All numbers: Config/NameplateConfig.

	Reads only server state: Humanoid health, the model attributes EnemyLevel / EnemyName / EnemyType and Tag_<id>
	("stacks|expiry", written by EnemyTags on the server). One shared loop (distance fades, tag timers, HP counting) runs for every plate.
	Level badge tint = enemy level vs the player's Combat level (SkillUpdated payload).
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local EnemyConfig = require(Modules:WaitForChild("EnemyConfig")) :: any
local CFG = require(Modules:WaitForChild("Config"):WaitForChild("NameplateConfig")) :: any
local DeathConfig = require(Modules:WaitForChild("Config"):WaitForChild("DeathConfig")) :: any
local guiFolder = ReplicatedStorage:WaitForChild("GUI")
local template = guiFolder:WaitForChild("EnemyNameplate") :: BillboardGui
local tagTemplate = guiFolder:WaitForChild("EnemyNameplate_Tag") :: Frame
local groupTemplate = guiFolder:WaitForChild("EnemyNameplate_TagGroup") :: Frame
local shardTemplate = guiFolder:WaitForChild("EnemyNameplate_Shard") :: ImageLabel

local TAG_PREFIX = "Tag_"
local combatLevel = 1

type Plate = {
	model: Model,
	gui: BillboardGui,
	humanoid: Humanoid,
	head: BasePart,
	title: CanvasGroup,
	titlePad: UIPadding?,
	titleScale: UIScale?,
	barHeight: number,
	fullAt: number?,
	nameLabel: TextLabel?,
	levelLabel: TextLabel?,
	badgeStroke: UIStroke?,
	badgeGradient: UIGradient?,
	barGroup: CanvasGroup,
	barScale: UIScale?,
	fill: Frame,
	ghost: Frame,
	hpLabel: TextLabel?,
	tagsGroup: CanvasGroup?,
	tagsPad: UIPadding?,
	tagsBase: number,
	tweens: { [string]: Tween },
	nameShown: boolean,
	barShown: boolean,
	tagsShown: boolean,
	dead: boolean,
	gen: number,
	fillFrac: number,
	shownHp: number,
	count: { from: number, to: number, start: number }?,
	level: number,
	chips: { [string]: { chip: Frame, expiry: number, stacks: number, token: number } },
	chipCount: number,
	groups: { [string]: Frame },
}

local plates: { [Model]: Plate } = {}
local counting: { [Plate]: boolean } = {}

-- ===================== HELPERS =====================
local function find(root: Instance, name: string): Instance?
	return root:FindFirstChild(name, true)
end

local function play(plate: Plate, key: string, instance: Instance?, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	if not instance then
		return nil
	end
	local old = plate.tweens[key]
	if old then
		old:Cancel()
	end
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), props)
	plate.tweens[key] = tween
	tween:Play()
	return tween
end

local function formatHp(value: number): string
	value = math.max(value, 0)
	for _, unit in ipairs(CFG.hp.units) do
		if value >= unit[1] then
			local text = string.format("%.1f", math.floor(value / unit[1] * 10) / 10)
			return (string.gsub(text, "%.0$", "")) .. unit[2]
		end
	end
	return tostring(math.ceil(value))
end

local function hpText(plate: Plate, value: number): string
	local text = formatHp(value)
	if CFG.hp.showMax then
		text ..= "/" .. formatHp(plate.humanoid.MaxHealth)
	end
	return text
end

local function tintFor(level: number): any
	local difference = level - combatLevel
	for _, row in ipairs(CFG.levelTints) do
		if difference <= row.upTo then
			return row
		end
	end
	return CFG.levelTints[#CFG.levelTints]
end

-- ===================== VISIBILITY (name / bar / tags) =====================
local function setName(plate: Plate, on: boolean, seconds: number?)
	if plate.nameShown == on then
		return
	end
	plate.nameShown = on
	local intro = CFG.intro
	local rise = UDim.new(0, intro.nameRise)
	if on then
		play(plate, "titleFade", plate.title, intro.nameSeconds, { GroupTransparency = 0 })
		play(plate, "titlePos", plate.titlePad, intro.nameSeconds, { PaddingTop = UDim.new(0, 0) }, Enum.EasingStyle.Back)
	else
		local time = seconds or intro.hideSeconds
		play(plate, "titleFade", plate.title, time, { GroupTransparency = 1 })
		play(plate, "titlePos", plate.titlePad, time, { PaddingTop = rise })
	end
end

local function setBar(plate: Plate, on: boolean, seconds: number?)
	if plate.barShown == on then
		return
	end
	plate.barShown = on
	local intro = CFG.intro
	-- the slot between the name and the tags is 0 high while hidden: opening it pushes the two apart
	if on then
		play(plate, "barSlot", plate.barGroup, intro.barSeconds, { Size = UDim2.new(1, 0, 0, plate.barHeight), GroupTransparency = 0 })
		play(plate, "barScale", plate.barScale, intro.barSeconds, { Scale = 1 }, Enum.EasingStyle.Back)
	else
		local time = seconds or intro.barCloseSeconds
		play(plate, "barSlot", plate.barGroup, time, { Size = UDim2.new(1, 0, 0, 0), GroupTransparency = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		play(plate, "barScale", plate.barScale, time, { Scale = intro.barStartScale })
	end
end

-- the tag row animates in as you get close: it rises and fades in while its chips pop in one by one; past the range it goes back
local function setTags(plate: Plate, on: boolean, seconds: number?)
	if plate.tagsShown == on or not plate.tagsGroup then
		return
	end
	plate.tagsShown = on
	local intro = CFG.intro
	local chips = {}
	for _, entry in pairs(plate.chips) do
		table.insert(chips, entry.chip)
	end
	table.sort(chips, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	if on then
		play(plate, "tagsFade", plate.tagsGroup, intro.tagSeconds, { GroupTransparency = 0 })
		play(plate, "tagsRise", plate.tagsPad, intro.tagSeconds + 0.1, { PaddingTop = UDim.new(0, plate.tagsBase) }, Enum.EasingStyle.Back)
		for index, chip in ipairs(chips) do
			local scale = chip:FindFirstChildOfClass("UIScale")
			if scale then
				task.delay((index - 1) * intro.tagStagger, function()
					if plate.tagsShown and scale.Parent then
						TweenService:Create(scale, TweenInfo.new(intro.tagSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
					end
				end)
			end
		end
	else
		local time = seconds or intro.tagHideSeconds
		play(plate, "tagsFade", plate.tagsGroup, time, { GroupTransparency = 1 })
		play(plate, "tagsRise", plate.tagsPad, time, { PaddingTop = UDim.new(0, plate.tagsBase + intro.tagRise) })
		for _, chip in ipairs(chips) do
			local scale = chip:FindFirstChildOfClass("UIScale")
			if scale then
				TweenService:Create(scale, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = intro.tagStartScale }):Play()
			end
		end
	end
end

-- ===================== LEVEL =====================
local function applyTint(plate: Plate, animate: boolean)
	local row = tintFor(plate.level)
	local seconds = animate and CFG.tintSeconds or 0
	if plate.badgeGradient then
		plate.badgeGradient.Color = ColorSequence.new(Color3.fromHex(row.top), Color3.fromHex(row.bottom)) -- a ColorSequence cannot be tweened
	end
	if plate.badgeStroke then
		play(plate, "tintStroke", plate.badgeStroke, seconds, { Color = Color3.fromHex(row.stroke) }, Enum.EasingStyle.Linear)
	end
	if plate.levelLabel then
		play(plate, "tintText", plate.levelLabel, seconds, { TextColor3 = Color3.fromHex(row.text) }, Enum.EasingStyle.Linear)
	end
end

local function updateLevel(plate: Plate)
	local attribute = plate.model:GetAttribute("EnemyLevel")
	plate.level = type(attribute) == "number" and attribute or EnemyConfig.statsFor(plate.model:GetAttribute("EnemyType")).level
	if plate.levelLabel then
		plate.levelLabel.Text = "LV " .. plate.level
	end
	applyTint(plate, false)
end

-- ===================== TAGS =====================
local function parseTag(value: any): (number?, number?)
	if type(value) ~= "string" then
		return nil, nil
	end
	local stacks, expiry = string.match(value, "^(%d+)|([%d%.]+)$")
	return tonumber(stacks), tonumber(expiry)
end

-- the chips of one kind sit together in a small pill (EnemyNameplate_TagGroup), like the reference
local function groupFor(plate: Plate, kind: string): Frame?
	local existing = plate.groups[kind]
	if existing and existing.Parent then
		return existing
	end
	local row = plate.tagsGroup
	if not row then
		return nil
	end
	local group = groupTemplate:Clone()
	group.Name = "Group_" .. kind
	local kindColors = CFG.tagKinds[kind]
	local strokeGradient = group:FindFirstChild("StrokeGradient", true) :: UIGradient?
	if kindColors and strokeGradient then
		strokeGradient.Color = ColorSequence.new(Color3.fromHex(kindColors.top), Color3.fromHex(kindColors.bottom))
	end
	group.LayoutOrder = CFG.tagsCfg.kindOrder[kind] or 9
	group.Parent = row
	plate.groups[kind] = group
	return group
end

local function pruneGroup(plate: Plate, group: Instance?)
	if not group or not group.Parent then
		return
	end
	for _, child in ipairs(group:GetChildren()) do
		if child:IsA("GuiObject") then
			return
		end
	end
	for kind, g in pairs(plate.groups) do
		if g == group then
			plate.groups[kind] = nil
		end
	end
	group:Destroy()
end

local function removeChip(plate: Plate, id: string)
	local entry = plate.chips[id]
	if not entry then
		return
	end
	plate.chips[id] = nil
	plate.chipCount -= 1
	entry.token += 1
	local chip = entry.chip
	local scale = chip:FindFirstChildOfClass("UIScale")
	if scale and chip.Parent then
		local tween = TweenService:Create(scale, TweenInfo.new(CFG.intro.tagSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Scale = 0 })
		tween.Completed:Connect(function()
			local group = chip.Parent
			chip:Destroy()
			pruneGroup(plate, group)
		end)
		tween:Play()
	else
		local group = chip.Parent
		chip:Destroy()
		pruneGroup(plate, group)
	end
end

local function createChip(plate: Plate, id: string, def: any, stacks: number, expiry: number)
	local group = groupFor(plate, def.kind)
	if not group then
		return
	end
	local chip = tagTemplate:Clone()
	chip.Name = TAG_PREFIX .. id
	local color = Color3.fromHex(def.color)
	local icon = chip:FindFirstChild("Icon") :: Frame?
	if icon then
		local glyph = icon:FindFirstChild("Glyph") :: TextLabel?
		local image = icon:FindFirstChild("IconImage") :: ImageLabel?
		if def.icon and def.icon ~= "" and image then
			image.Image = def.icon
			image.Visible = true
			icon.BackgroundTransparency = 1
			if glyph then
				glyph.Visible = false
			end
		else
			icon.BackgroundColor3 = color
			if glyph then
				glyph.Text = def.glyph or "?"
			end
		end
	end
	local scale = chip:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = CFG.intro.tagStartScale
	end
	chip.Parent = group
	if scale and plate.tagsShown then
		TweenService:Create(scale, TweenInfo.new(CFG.intro.tagSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	plate.chips[id] = { chip = chip, expiry = expiry, stacks = stacks, token = 0 }
	plate.chipCount += 1
end

local function refreshTags(plate: Plate)
	local now = workspace:GetServerTimeNow()
	local seen: { [string]: boolean } = {}
	for name, value in pairs(plate.model:GetAttributes()) do
		if string.sub(name, 1, #TAG_PREFIX) == TAG_PREFIX then
			local id = string.sub(name, #TAG_PREFIX + 1)
			local def = CFG.tags[id]
			local stacks, expiry = parseTag(value)
			if def and stacks and expiry and (expiry == 0 or expiry > now) then
				seen[id] = true
				local entry = plate.chips[id]
				if entry then
					entry.stacks, entry.expiry = stacks, expiry
				else
					createChip(plate, id, def, stacks, expiry)
				end
			end
		end
	end
	for id in pairs(plate.chips) do
		if not seen[id] then
			removeChip(plate, id)
		end
	end
	-- order: element, effect, debuff; extras past maxVisible are hidden
	local ids = {}
	for id in pairs(plate.chips) do
		table.insert(ids, id)
	end
	table.sort(ids, function(a, b)
		local ka, kb = CFG.tagsCfg.kindOrder[CFG.tags[a].kind] or 9, CFG.tagsCfg.kindOrder[CFG.tags[b].kind] or 9
		if ka ~= kb then
			return ka < kb
		end
		return a < b
	end)
	for index, id in ipairs(ids) do
		local chip = plate.chips[id].chip
		chip.LayoutOrder = index
		chip.Visible = index <= CFG.tagsCfg.maxVisible
	end
end

local function updateTimers(plate: Plate, now: number)
	for id, entry in pairs(plate.chips) do
		local count = entry.chip:FindFirstChild("Count") :: TextLabel?
		if entry.expiry > 0 and entry.expiry <= now then
			removeChip(plate, id)
		elseif count then
			local parts = {}
			if entry.stacks > 1 then
				table.insert(parts, "x" .. entry.stacks)
			end
			local left = entry.expiry > 0 and (entry.expiry - now) or nil
			if left then
				table.insert(parts, string.format("%ds", math.ceil(left)))
			end
			count.Visible = #parts > 0
			count.Text = table.concat(parts, " ")
			count.TextColor3 = (left and left <= CFG.tagsCfg.lowTimeSeconds) and Color3.fromHex(CFG.tagsCfg.lowTimeColor) or Color3.new(1, 1, 1)
		end
	end
end

-- ===================== HEALTH =====================
local function setFraction(plate: Plate)
	return math.clamp(plate.humanoid.Health / math.max(plate.humanoid.MaxHealth, 1), 0, 1)
end

-- DEATH: the plate glitches for the same seconds as the body (DeathConfig.timeline.glitch), then breaks into small triangles
local function playDeath(plate: Plate)
	if plate.dead then
		return
	end
	plate.dead = true
	counting[plate] = nil
	for _, tween in pairs(plate.tweens) do
		tween:Cancel()
	end
	local model, gui = plate.model, plate.gui
	local stack = find(gui, "Stack") :: Frame?
	local enemyType = model:GetAttribute("EnemyType")
	local kind = enemyType == "dummy" and "dummy" or "enemy"
	local cfg = DeathConfig.resolve(kind, type(enemyType) == "string" and EnemyConfig.get(enemyType) or nil)
	local hud = cfg.hud
	local glitchSeconds = cfg.timeline.glitch
	if not (stack and gui.Parent) then
		gui.Enabled = false
		return
	end

	-- two tinted copies of the stack behind it: the double image
	local echoes: { Frame } = {}
	if hud.echo then
		for index, color in ipairs({ Color3.fromRGB(255, 70, 220), hud.tint }) do
			local copy = stack:Clone()
			copy.Name = "DeathEcho" .. index
			for _, item in ipairs(copy:GetDescendants()) do
				if item:IsA("CanvasGroup") then
					item.GroupColor3 = color
					item.GroupTransparency = math.max(item.GroupTransparency, 0.15) + 0.4
				end
			end
			copy.Parent = gui
			table.insert(echoes, copy)
		end
	end
	local groups: { CanvasGroup } = {}
	for _, item in ipairs(stack:GetDescendants()) do
		if item:IsA("CanvasGroup") then
			table.insert(groups, item)
		end
	end
	local barRoot = find(stack, "BarRoot") :: Frame?
	local titlePad = plate.titlePad
	local tagsPad = plate.tagsPad
	local titleLeft, tagsLeft = titlePad and titlePad.PaddingLeft or UDim.new(0, 0), tagsPad and tagsPad.PaddingLeft or UDim.new(0, 0)
	local barBase = barRoot and barRoot.Position or UDim2.new()
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / math.max(glitchSeconds, 0.05), 0, 1)
		local intensity = t ^ 1.3
		stack.Position = UDim2.new(0.5, math.random(-100, 100) / 100 * hud.jitterPixels * intensity, 0.5, math.random(-100, 100) / 100 * hud.jitterPixels * 0.5 * intensity)
		local alpha = math.clamp((t - 0.1) / 0.9, 0, 1)
		local flicker = math.random() < math.clamp((t - hud.flickerStart) * 1.2, 0, 1) * 0.55
		for _, group in ipairs(groups) do
			group.GroupColor3 = Color3.new(1, 1, 1):Lerp(hud.tint, alpha)
			group.GroupTransparency = (flicker and math.random() < 0.7) and 0.5 + math.random() * 0.45 or 0
		end
		-- slices: a part of the plate jumps sideways for a frame
		local slice = t > 0.3 and math.random() < hud.sliceChance
		local push = (math.random() < 0.5 and -1 or 1) * hud.slicePixels
		if titlePad then
			titlePad.PaddingLeft = slice and UDim.new(0, math.max(push, 0) * math.random()) or titleLeft
			titlePad.PaddingTop = UDim.new(0, 0)
		end
		if tagsPad then
			tagsPad.PaddingLeft = (slice and math.random() < 0.6) and UDim.new(0, math.max(-push, 0) * math.random()) or tagsLeft
			tagsPad.PaddingTop = UDim.new(0, plate.tagsBase)
		end
		if barRoot then
			barRoot.Position = (slice and math.random() < 0.6) and barBase + UDim2.fromOffset(push * math.random(), 0) or barBase
		end
		for index, copy in ipairs(echoes) do
			local side = (index == 1 and -1 or 1) * hud.echoPixels * (0.4 + intensity) * (math.random() < 0.5 and 1 or -1)
			copy.Position = UDim2.new(0.5, side, 0.5, math.random(-100, 100) / 100)
		end
		if t < 1 then
			return
		end
		connection:Disconnect()

		-- BURST: the plate is gone, small triangles scatter, spin, shrink and fade
		for _, copy in ipairs(echoes) do
			copy:Destroy()
		end
		stack.Visible = false
		local halfW, halfH = 110, 34
		local colors = cfg.burst.colors
		for _ = 1, hud.shards do
			local shard = shardTemplate:Clone()
			local size = math.random(hud.shardSize[1], hud.shardSize[2])
			local life = hud.shardLife[1] + math.random() * (hud.shardLife[2] - hud.shardLife[1])
			local angle = math.random() * math.pi * 2
			local distance = hud.shardDistance[1] + math.random() * (hud.shardDistance[2] - hud.shardDistance[1])
			local from = UDim2.new(0.5, math.random(-halfW, halfW), 0.5, math.random(-halfH, halfH))
			shard.Size = UDim2.fromOffset(size, size)
			shard.Position = from
			shard.Rotation = math.random(0, 360)
			shard.ImageColor3 = colors[math.random(1, #colors)]
			shard.ImageRectOffset = Vector2.new(math.random(0, 1) * 128, math.random(0, 1) * 128)
			shard.ZIndex = 20
			shard.Parent = gui
			local to = from + UDim2.fromOffset(math.cos(angle) * distance, math.sin(angle) * distance * 0.6 - hud.shardRise)
			local info = TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			TweenService:Create(shard, info, { Position = to, Rotation = shard.Rotation + (math.random() < 0.5 and -1 or 1) * math.random(180, 540) }):Play()
			local fade = TweenService:Create(shard, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.fromOffset(0, 0), ImageTransparency = 1 })
			fade.Completed:Connect(function()
				shard:Destroy()
			end)
			fade:Play()
		end
		task.delay(hud.shardLife[2] + 0.2, function()
			if gui.Parent then
				gui.Enabled = false
			end
		end)
	end)
end

local function onHealth(plate: Plate)
	local humanoid = plate.humanoid
	if humanoid.Health <= 0 then
		-- the EntityDeath message normally starts it a moment earlier (same timeline as the body); this is the fallback
		task.delay(0.15, function()
			playDeath(plate)
		end)
		return
	end
	local fraction = setFraction(plate)
	local healing = fraction > plate.fillFrac
	plate.fillFrac = fraction
	plate.gen += 1
	local gen = plate.gen
	local size = UDim2.fromScale(fraction, 1)
	play(plate, "fill", plate.fill, healing and CFG.hp.healSeconds or CFG.hp.fillSeconds, { Size = size })
	if healing then
		play(plate, "ghost", plate.ghost, CFG.hp.healSeconds, { Size = size })
	else
		task.delay(CFG.hp.ghostDelay, function()
			if plate.gen == gen and not plate.dead and plate.ghost.Parent then
				play(plate, "ghost", plate.ghost, CFG.hp.ghostSeconds, { Size = size })
			end
		end)
	end
	plate.count = { from = plate.shownHp, to = humanoid.Health, start = os.clock() }
	counting[plate] = true
end

local function stepCount(plate: Plate, now: number)
	local count = plate.count
	if not count then
		counting[plate] = nil
		return
	end
	local alpha = math.clamp((now - count.start) / CFG.hp.countSeconds, 0, 1)
	alpha = 1 - (1 - alpha) ^ 3
	plate.shownHp = count.from + (count.to - count.from) * alpha
	if plate.hpLabel then
		plate.hpLabel.Text = hpText(plate, plate.shownHp)
	end
	if alpha >= 1 then
		plate.count = nil
		counting[plate] = nil
	end
end

-- ===================== ATTACH =====================
local function attach(model: Instance)
	if not model:IsA("Model") or plates[model] or model:FindFirstChild("EnemyNameplate") then
		return
	end
	local entry = EnemyConfig.get(model:GetAttribute("EnemyType"))
	local humanoid = model:WaitForChild("Humanoid", 5) :: Humanoid?
	local head = model:WaitForChild("Head", 5) :: BasePart?
	if entry.nameplate == false or not (humanoid and head) or plates[model] then
		return
	end

	local gui = template:Clone()
	gui.Name = "EnemyNameplate"
	gui.Adornee = head
	gui.MaxDistance = CFG.show.nameDistance + 10
	gui.StudsOffsetWorldSpace = Vector3.new(0, CFG.show.heightOffset, 0)
	local title = find(gui, "Title") :: CanvasGroup?
	local barGroup = find(gui, "BarGroup") :: CanvasGroup?
	local fill = find(gui, "Fill") :: Frame?
	local ghost = find(gui, "Ghost") :: Frame?
	if not (title and barGroup and fill and ghost) then
		warn("[EnemyNameplateController] EnemyNameplate template is missing Title / BarGroup / Fill / Ghost")
		gui:Destroy()
		return
	end

	local plate: Plate = {
		model = model,
		gui = gui,
		humanoid = humanoid,
		head = head,
		title = title,
		titlePad = title:FindFirstChildOfClass("UIPadding"),
		titleScale = title:FindFirstChildOfClass("UIScale"),
		barHeight = barGroup.Size.Y.Offset,
		nameLabel = find(gui, "NameLabel") :: TextLabel?,
		levelLabel = find(gui, "LevelLabel") :: TextLabel?,
		badgeStroke = find(gui, "BadgeStroke") :: UIStroke?,
		badgeGradient = find(gui, "BadgeGradient") :: UIGradient?,
		barGroup = barGroup,
		barScale = (find(gui, "BarRoot") and find(gui, "BarRoot"):FindFirstChildOfClass("UIScale")) :: UIScale?,
		fill = fill,
		ghost = ghost,
		hpLabel = find(gui, "HpLabel") :: TextLabel?,
		tagsGroup = find(gui, "Tags") :: CanvasGroup?,
		tagsPad = (find(gui, "Tags") and find(gui, "Tags"):FindFirstChildOfClass("UIPadding")) :: UIPadding?,
		tagsBase = 0,
		tweens = {},
		nameShown = false,
		barShown = false,
		tagsShown = false,
		dead = false,
		gen = 0,
		fillFrac = 1,
		shownHp = humanoid.Health,
		count = nil,
		level = 1,
		chips = {},
		chipCount = 0,
		groups = {},
	}
	plates[model] = plate

	-- start hidden: the loop fades the parts in when the player gets close
	title.GroupTransparency = 1
	if plate.titlePad then
		plate.titlePad.PaddingTop = UDim.new(0, CFG.intro.nameRise)
	end
	barGroup.GroupTransparency = 1
	barGroup.Size = UDim2.new(1, 0, 0, 0)
	if plate.barScale then
		plate.barScale.Scale = CFG.intro.barStartScale
	end
	if plate.tagsGroup then
		plate.tagsGroup.GroupTransparency = 1
	end
	if plate.tagsPad then
		plate.tagsBase = plate.tagsPad.PaddingTop.Offset
		plate.tagsPad.PaddingTop = UDim.new(0, plate.tagsBase + CFG.intro.tagRise)
	end

	if plate.nameLabel then
		plate.nameLabel.Text = model:GetAttribute("EnemyName") or entry.name
	end
	updateLevel(plate)
	local fraction = setFraction(plate)
	plate.fillFrac = fraction
	fill.Size = UDim2.fromScale(fraction, 1)
	ghost.Size = UDim2.fromScale(fraction, 1)
	if plate.hpLabel then
		plate.hpLabel.Text = hpText(plate, humanoid.Health)
	end
	refreshTags(plate)
	if humanoid.Health <= 0 then
		plate.dead = true
	end

	humanoid.HealthChanged:Connect(function()
		onHealth(plate)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		onHealth(plate)
	end)
	model.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, #TAG_PREFIX) == TAG_PREFIX then
			refreshTags(plate)
		elseif name == "EnemyLevel" or name == "EnemyType" then
			updateLevel(plate)
		elseif name == "EnemyName" and plate.nameLabel then
			plate.nameLabel.Text = model:GetAttribute("EnemyName") or entry.name
		end
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(game) then
			plates[model] = nil
			counting[plate] = nil
			plate.dead = true
		end
	end)
	gui.Parent = model
end

-- the server's EntityDeath message starts the plate's death in sync with the body's glitch
task.spawn(function()
	local remote = ReplicatedStorage:WaitForChild("EntityDeath", 30) :: RemoteEvent?
	if remote then
		remote.OnClientEvent:Connect(function(model)
			local plate = typeof(model) == "Instance" and plates[model :: Model]
			if plate then
				playDeath(plate)
			end
		end)
	end
end)

-- ===================== SHARED LOOP =====================
local accumulator = 0
local timerAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	if next(counting) then
		local now = os.clock()
		for plate in pairs(counting) do
			stepCount(plate, now)
		end
	end
	accumulator += dt
	if accumulator < CFG.show.checkInterval then
		return
	end
	local step = accumulator
	accumulator = 0
	timerAccumulator += step
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local cameraPosition = camera.CFrame.Position
	local show = CFG.show
	local doTimers = timerAccumulator >= CFG.tagsCfg.timerStep
	if doTimers then
		timerAccumulator = 0
	end
	local serverNow = workspace:GetServerTimeNow()
	for _, plate in pairs(plates) do
		if not plate.dead then
			local distance = (plate.head.Position - cameraPosition).Magnitude
			local hysteresis = show.hysteresis
			local nameRange = show.nameDistance + (plate.nameShown and hysteresis or 0)
			local barRange = show.barDistance + (plate.barShown and hysteresis or 0)
			local tagRange = show.tagDistance + (plate.tagsShown and hysteresis or 0)
			local damaged = plate.humanoid.Health < plate.humanoid.MaxHealth - 0.5
			setName(plate, distance <= nameRange)
			if damaged then
				plate.fullAt = nil
			elseif not plate.fullAt then
				plate.fullAt = os.clock()
			end
			-- the bar only exists while the enemy is hurt (and a moment after it is whole again)
			local keep = damaged or (plate.barShown and plate.fullAt ~= nil and os.clock() - plate.fullAt < show.fullHideDelay)
			setBar(plate, keep and distance <= barRange)
			setTags(plate, plate.chipCount > 0 and distance <= tagRange)
			if doTimers and plate.chipCount > 0 then
				updateTimers(plate, serverNow)
			end
		end
	end
end)

-- ===================== PLAYER COMBAT LEVEL (tint) =====================
local function retint()
	for _, plate in pairs(plates) do
		applyTint(plate, true)
	end
end
task.spawn(function()
	local skillUpdated = ReplicatedStorage:WaitForChild("SkillUpdated", 30)
	if not skillUpdated then
		return
	end
	(skillUpdated :: RemoteEvent).OnClientEvent:Connect(function(data)
		local combat = type(data) == "table" and data.Combat
		local level = type(combat) == "table" and combat.level
		if type(level) == "number" and level ~= combatLevel then
			combatLevel = level
			retint()
		end
	end)
end)
Players.LocalPlayer.CharacterAdded:Connect(function() end) -- keeps the module a LocalScript with a player dependency

for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
	task.spawn(attach, model)
end
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(model)
	task.spawn(attach, model)
end)
