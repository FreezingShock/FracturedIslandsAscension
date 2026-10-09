--[[
	TooltipModule (ModuleScript)
	ReplicatedStorage > Modules > TooltipModule  (folder-style: init + Style, Rich, Items)

	ONE data-driven tooltip for the whole game. It is built from the design in
	StarterGui > TooltipMenu > Template: at runtime the module clones that
	Template into its own ScreenGui, pulls the repeating pieces out as
	prototypes (tag badge, stat row, ability block, click pill) and fills them
	from a config table. Restyle the Template in Studio and every tooltip
	follows - no code changes.

	USAGE
	  local Tooltip = require(Modules.TooltipModule)
	  Tooltip.show(config, source?)   -- source = who owns it (default "generic")
	  Tooltip.hide(source?)           -- with a source: only hides if that source owns it
	  Tooltip.forceHide()             -- hide regardless of owner
	  Tooltip.isActiveSource(source)

	CONFIG (every field optional; missing = that part of the tooltip is hidden)
	  title        rich text
	  titleColor   hex | Color3            (default white)
	  icon         { image=, sprite={col,row}, rectOffset=, rectSize=, color= }
	               or a "rbxassetid://" string. Shows the 50x50 icon box.
	  stack        number | string         -> "X64"
	  tags         { {text=, color=}, ... }  badges under the title
	  description  rich text
	  level        string | { text= }      -> level bar ("LV. 5")
	  progress     { pct=0..1, label=, color=, animate= }
	  statsTitle   string | false          header text; false = plain line
	  stats        { {name=, value=, color=, icon=}, ... }
	  blocks       { {title=, key=, text=, cooldown=, color=, align=}, ... }
	  sections     { {type=, title=, rows=/text=, collapsible=, summary=}, ... }
	               data-driven extra sections (see TooltipModule/Sections); hold SHIFT
	               to expand collapsible ones
	               (ability / rewards / breakdown sections)
	  footer       small-caps note below the blocks
	  details      { {key=, value=, color=, keyColor=}, ... }  small pixel-font key/value lines under the footer
	               (Obtained: ..., Source: ...), like SkyBlock's bottom lines
	  click        string | {text=, color=, icon="lmb"|"rmb"} | array of those
	  dividers     { d1=, d2=, d3= } force a divider on/off (default automatic)

	LEGACY SHAPE still accepted: { title=, desc=, click="<rich string>" }.

	Order top -> bottom (taken from the Template's LayoutOrders):
	  TitleFrame, Description, Divider1, LevelBar, ProgressBar, Divider2
	  (stats header), Stats, Divider3, Rewards (blocks + footer), ClickFrame.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Style = require(script:WaitForChild("Style"))
local Rich = require(script:WaitForChild("Rich"))
local Items = require(script:WaitForChild("Items"))
local Sections = require(script:WaitForChild("Sections"))
local Build = require(script:WaitForChild("Build"))

local API = {}
API.Style = Style
API.Rich = Rich
API.Sections = Sections
API.Items = Items
API.Build = Build -- Tooltip.Build.stat / rewardList / progress / tag / row (see TooltipModule/Build)
API.STAT_SPRITESHEET = Style.SPRITE -- kept for modules that draw their own stat icons

-- ===================== CONFIG =====================
local CURSOR_OFFSET_X = 18
local CURSOR_OFFSET_Y = 12
local PROGRESS_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ===================== INERT FALLBACK =====================
-- If the Template is missing, never yield forever (that froze every menu
-- script that requires this module). Warn once and turn into a no-op.
local function noop() end

local function installInert(reason: string)
	warn("[TooltipModule] " .. reason .. " - tooltips are disabled until this is fixed.")
	API.show = noop
	API.hide = noop
	API.forceHide = noop
	API.isActiveSource = function()
		return false
	end
	API.isVisible = function()
		return false
	end
	API.registerHover = noop
	API.unregisterHover = noop
	API.recheckPointer = function()
		return false
	end
	API.getFrame = function()
		return nil
	end
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local sourceGui = playerGui:WaitForChild("TooltipMenu", 15)
local template = sourceGui and sourceGui:WaitForChild("Template", 15)
if not template then
	installInert("StarterGui.TooltipMenu.Template not found")
	return API
end

-- ===================== HOST + LIVE FRAME =====================
-- Our own ScreenGui: ResetOnSpawn=false so the cached references survive
-- respawns (the source TooltipMenu is re-created on every respawn).
local host = Instance.new("ScreenGui")
host.Name = "TooltipHost"
host.ResetOnSpawn = false
host.DisplayOrder = sourceGui.DisplayOrder
host.IgnoreGuiInset = sourceGui.IgnoreGuiInset
host.ZIndexBehavior = sourceGui.ZIndexBehavior
host.Parent = playerGui

local frame = template:Clone()
frame.Name = "TooltipFrame"
frame.Visible = false
frame.Parent = host

-- The design-time Template must never show in a running game.
sourceGui.Enabled = false
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TooltipMenu" and child:IsA("ScreenGui") then
		child.Enabled = false
	end
end)

-- ===================== REFERENCES =====================
local function child(parent: Instance?, name: string): Instance?
	local inst = parent and parent:FindFirstChild(name)
	if not inst then
		warn("[TooltipModule] Template is missing '" .. name .. "'" .. (parent and (" under " .. parent.Name) or ""))
	end
	return inst
end

local titleFrame = child(frame, "TitleFrame")
local titleLabel = child(titleFrame, "TitleLabel")
local itemIcon = child(titleFrame, "ItemIcon")
local itemTags = child(titleFrame, "ItemTags")
local stackLabel = child(titleFrame, "StackLabel")
local descLabel = child(frame, "DescriptionLabel")
local div1 = child(frame, "Divider1")
local div2 = child(frame, "Divider2")
local div3 = child(frame, "Divider3")
local div4 = frame:FindFirstChild("Divider4")
-- The template's Divider4 is an empty 0-width stub (it sits between the blocks and the click pills).
-- Give it Divider3's look so a tooltip can ask for a divider under its list (dividers = { d4 = true }).
if div3 and div4 and div3 ~= div4 then
	local order = div4.LayoutOrder
	div4:Destroy()
	div4 = div3:Clone()
	div4.Name = "Divider4"
	div4.LayoutOrder = order
	div4.Visible = false
	div4.Parent = frame
end
local levelBar = child(frame, "LevelBar")
local levelLabel = levelBar and levelBar:FindFirstChild("LevelLabel", true)
local progressBar = child(frame, "ProgressBar")
local progressFill = progressBar and progressBar:FindFirstChild("Progress", true)
local progressLabel = progressBar and progressBar:FindFirstChild("ProgressLabel", true)
local statsFrame = child(frame, "Stats")
local rewardsFrame = child(frame, "Rewards")
local clickFrame = child(frame, "ClickFrame")

-- ===================== PROTOTYPES =====================
-- The repeating pieces are lifted out of the live frame (so the sample
-- content never shows) and cloned on demand.
local protos: { [string]: Instance } = {}

if itemTags then
	local sample = itemTags:FindFirstChild("Rarity") or itemTags:FindFirstChildWhichIsA("Frame")
	if sample then
		protos.tag = sample:Clone()
	end
	for _, c in ipairs(itemTags:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

if statsFrame then
	local sample = statsFrame:FindFirstChild("Damage") or statsFrame:FindFirstChildWhichIsA("Frame")
	if sample then
		protos.statRow = sample:Clone()
	end
	for _, c in ipairs(statsFrame:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

if rewardsFrame then
	local abilityFrames, footer = {}, nil
	for _, c in ipairs(rewardsFrame:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(abilityFrames, c)
		elseif c:IsA("TextLabel") then
			footer = c
		end
	end
	for _, f in ipairs(abilityFrames) do
		local title = f:FindFirstChild("Title")
		if title and not protos.blockTitle then
			protos.blockTitle = title:Clone()
		end
		for _, t in ipairs(f:GetChildren()) do
			if t:IsA("TextLabel") then
				if t.Size.X.Scale >= 0.95 and not protos.blockText then
					protos.blockText = t:Clone()
				elseif t.Size.X.Scale < 0.95 and not protos.blockCooldown then
					protos.blockCooldown = t:Clone()
				end
			end
		end
	end
	if footer then
		protos.footer = footer:Clone()
	end
	for _, f in ipairs(abilityFrames) do
		f:Destroy()
	end
	if footer then
		footer:Destroy()
	end
end
if not protos.blockText and descLabel then
	protos.blockText = descLabel:Clone()
end

local clickLine
if clickFrame then
	local sample = clickFrame:FindFirstChild("Equip") or clickFrame:FindFirstChild("View")
	if sample then
		protos.pill = sample:Clone()
	end
	for _, name in ipairs({ "Equip", "View" }) do
		local c = clickFrame:FindFirstChild(name)
		if c then
			c:Destroy()
		end
	end
	clickLine = clickFrame:FindFirstChild("Line")
	if clickLine then
		clickLine.LayoutOrder = 1000 -- always after the pills
	end
end

-- Divider2 holds two variants: a titled header ("STATS") and a plain line.
local d2Titled, d2Plain, d2Label
if div2 then
	for _, c in ipairs(div2:GetChildren()) do
		if c:IsA("Frame") then
			if c:FindFirstChildWhichIsA("TextLabel", true) then
				d2Titled = c
			else
				d2Plain = c
			end
		end
	end
	d2Label = d2Titled and d2Titled:FindFirstChildWhichIsA("TextLabel", true)
end

-- Progress bar: the fill is revealed by a UIGradient transparency mask.
local fillGradient
if progressFill then
	for _, g in ipairs(progressFill:GetChildren()) do
		if g:IsA("UIGradient") then
			if not fillGradient then
				fillGradient = g
			else
				g.Enabled = false -- extra template gradients would fight the mask
			end
		end
	end
end

-- Title-area layout read from the Template (so the module follows your edits).
local titleBaseX = titleLabel and titleLabel.Position.X.Offset or 60
local tagsBaseX = itemTags and itemTags.Position.X.Offset or 58
local titleBaseY = titleLabel and titleLabel.Position.Y.Offset or 3
local tagsBaseY = itemTags and itemTags.Position.Y.Offset or 28

-- Icon box: strokes + a single reusable image
local iconStrokes = {}
local iconImage
if itemIcon then
	for _, c in ipairs(itemIcon:GetChildren()) do
		if c:IsA("UIStroke") then
			table.insert(iconStrokes, { stroke = c, default = c.Color })
		end
	end
	iconImage = Instance.new("ImageLabel")
	iconImage.Name = "ItemImage"
	iconImage.BackgroundTransparency = 1
	iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImage.Position = UDim2.fromScale(0.5, 0.5)
	iconImage.Size = UDim2.new(1, -10, 1, -10)
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.ZIndex = itemIcon.ZIndex + 1
	iconImage.Visible = false
	iconImage.Parent = itemIcon
end

-- ===================== LIQUID GLASS (optional) =====================
local glass
do
	local modules = script.Parent
	local glassModule = modules and modules:FindFirstChild("LiquidGlassHandler")
	if glassModule then
		local ok, handler = pcall(require, glassModule)
		if ok and handler then
			local applied, handle = pcall(function()
				return handler.apply(frame, {
					Stroke = { enabled = false },
					SeparatedBorderOutline = { enabled = false },
				})
			end)
			if applied and handle then
				glass = handle
				glass.setEnabled(false)
			end
		end
	end
end

-- ===================== POOLS =====================
local pools = {
	tag = { items = {}, used = 0 },
	stat = { items = {}, used = 0 },
	pill = { items = {}, used = 0 },
}

local function resetPool(kind: string)
	pools[kind].used = 0
end

local function take(kind: string, proto: Instance?, parent: Instance?): Instance?
	if not proto or not parent then
		return nil
	end
	local pool = pools[kind]
	pool.used += 1
	local inst = pool.items[pool.used]
	if not inst then
		inst = proto:Clone()
		inst.Parent = parent
		pool.items[pool.used] = inst
	end
	inst.Visible = true
	return inst
end

local function finishPool(kind: string)
	local pool = pools[kind]
	for i = pool.used + 1, #pool.items do
		pool.items[i].Visible = false
	end
end

-- ===================== SMALL HELPERS =====================
local function setVisible(inst: Instance?, visible: boolean)
	if inst then
		(inst :: any).Visible = visible
	end
end

local function nonEmpty(value: any): boolean
	return value ~= nil and value ~= false and value ~= ""
end

--- Apply an icon spec to an ImageLabel. Returns true if an image was set.
local function applyIcon(img: ImageLabel?, icon: any, tint: any): boolean
	if not img or not icon then
		return false
	end
	local sheet = Style.SPRITE
	if type(icon) == "string" then
		if icon == "" then
			return false
		end
		img.Image = icon
		img.ImageRectOffset = Vector2.zero
		img.ImageRectSize = Vector2.zero
	elseif type(icon) == "table" then
		local sprite = icon.sprite or ((type(icon[1]) == "number") and icon or nil)
		if sprite then
			local cs = sheet.cellSize
			img.Image = sheet.assetId
			img.ImageRectOffset = Vector2.new((sprite[1] or 0) * cs, (sprite[2] or 0) * cs)
			img.ImageRectSize = Vector2.new(cs, cs)
		elseif icon.image and icon.image ~= "" then
			img.Image = icon.image
			img.ImageRectOffset = icon.rectOffset or Vector2.zero
			img.ImageRectSize = icon.rectSize or Vector2.zero
		else
			return false
		end
		-- `imageColor` tints only the picture; `color` is the legacy shared tint (also used for strokes)
		tint = icon.imageColor or icon.color or tint
		img.ResampleMode = icon.imageColor and Enum.ResamplerMode.Pixelated or Enum.ResamplerMode.Default
	else
		return false
	end
	img.ImageColor3 = tint and Style.color3(tint) or Color3.new(1, 1, 1)
	img.ImageTransparency = 0
	return true
end

-- ===================== PROGRESS =====================
local function maskSequence(p: number): NumberSequence
	p = math.clamp(p, 0, 1)
	if p <= 0 then
		return NumberSequence.new(1)
	elseif p >= 1 then
		return NumberSequence.new(0)
	end
	p = math.min(p, 0.995)
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(p, 0),
		NumberSequenceKeypoint.new(p + 0.004, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local fillValue = Instance.new("NumberValue")
local fillTween
fillValue.Changed:Connect(function(v)
	if fillGradient then
		fillGradient.Transparency = maskSequence(v)
	end
end)

local function setProgress(p: number, animate: boolean)
	p = math.clamp(p or 0, 0, 1)
	if fillTween then
		fillTween:Cancel()
		fillTween = nil
	end
	if animate then
		fillTween = TweenService:Create(fillValue, PROGRESS_TWEEN, { Value = p })
		fillTween:Play()
	else
		fillValue.Value = p
		if fillGradient then
			fillGradient.Transparency = maskSequence(p) -- Changed does not fire when the value is unchanged
		end
	end
end

-- ===================== SECTION RENDERERS =====================

local function renderTitle(cfg)
	if not titleFrame then
		return
	end
	local hasTitle = nonEmpty(cfg.title)
	local iconSpec = cfg.icon
	local hasIcon = iconSpec ~= nil and iconSpec ~= false
	local hasTags = cfg.tags and #cfg.tags > 0
	local hasStack = nonEmpty(cfg.stack)

	titleFrame.Visible = hasTitle or hasIcon or hasTags or hasStack
	if not titleFrame.Visible then
		return
	end

	-- Title
	if titleLabel then
		titleLabel.Visible = hasTitle
		if hasTitle then
			titleLabel.Text = tostring(cfg.title)
			local titleSpec = cfg.titleColor or Style.DEFAULT_TITLE_COLOR
			titleLabel.TextColor3 = Style.color3(titleSpec)
			-- the title's text stroke: a darker shade of the same colour (the rarity colour on drops)
			local titleStroke = titleLabel:FindFirstChildOfClass("UIStroke")
			if titleStroke then
				-- palette colours use their Minecraft dark pair; greys / whites (Nexus tiers 1-10) get the same grey at 20%
				-- brightness, because Style.dark turns #AAAAAA into a lighter stroke
				-- the colour the title text actually shows: the first colour tag in a rich title (main menu buttons), else titleColor
				local shown = type(cfg.title) == "string" and cfg.title:match("color=[\"']?(#%x%x%x%x%x%x)") or titleSpec
				local titleRgb = Style.color3(shown)
				local _, sat = titleRgb:ToHSV()
				if sat < 0.12 then
					titleStroke.Color = Color3.new(titleRgb.R * 0.2, titleRgb.G * 0.2, titleRgb.B * 0.2)
				else
					titleStroke.Color = Style.color3(Style.dark(shown))
				end
			end
		end
	end

	-- Icon box
	if itemIcon then
		itemIcon.Visible = hasIcon
		if hasIcon then
			local tint = type(iconSpec) == "table" and iconSpec.color or nil
			for i, entry in ipairs(iconStrokes) do
				if tint then
					entry.stroke.Color = Style.color3(i == 1 and tint or Style.dark(tint))
				else
					entry.stroke.Color = entry.default
				end
			end
			local drewImage = applyIcon(iconImage, iconSpec, nil)
			if iconImage then
				iconImage.Visible = drewImage
			end
		end
	end

	-- Slide text left when there is no icon box
	local shift = hasIcon and 0 or -titleBaseX
	if titleLabel then
		titleLabel.Position = UDim2.fromOffset(titleBaseX + shift, titleBaseY)
	end
	if itemTags then
		itemTags.Position = UDim2.fromOffset(tagsBaseX + shift, hasTitle and tagsBaseY or titleBaseY)
	end

	-- Stack count
	if stackLabel then
		stackLabel.Visible = hasStack
		if hasStack then
			local s = tostring(cfg.stack)
			stackLabel.Text = (s:sub(1, 1):upper() == "X") and s or ("X" .. s)
		end
	end
end

local function styleTag(tag: Instance, spec: any)
	local base = Style.hex(spec.color or "#AAAAAA")
	local dark = Style.hex(spec.dark or Style.dark(base))
	local light = Style.hex(spec.light or Style.light(base))
	if base == "#AAAAAA" then
		light = "#FFFFFF"
	end
	local tagFrame: any = tag
	tagFrame.BackgroundColor3 = Style.color3(base)
	local darkStroke = tag:FindFirstChild("UISDark")
	if darkStroke then
		darkStroke.Color = Style.color3(dark)
	end
	local lightStroke = tag:FindFirstChild("UISLight")
	if lightStroke then
		lightStroke.Color = Style.color3(light)
	end
	local label = tag:FindFirstChild("TagLabel")
	if label then
		label.Text = tostring(spec.text or "?"):upper()
		label.TextColor3 = Style.color3(spec.textColor or light)
		local ls = label:FindFirstChildOfClass("UIStroke")
		if ls then
			ls.Color = Style.color3(dark)
		end
	end
end

local function renderTags(cfg)
	resetPool("tag")
	if itemTags and cfg.tags then
		for i, spec in ipairs(cfg.tags) do
			local tag = take("tag", protos.tag, itemTags)
			if tag then
				(tag :: any).LayoutOrder = i
				styleTag(tag, spec)
			end
		end
	end
	finishPool("tag")
	setVisible(itemTags, cfg.tags ~= nil and #cfg.tags > 0)
end

local function renderDescription(cfg): boolean
	local has = nonEmpty(cfg.description)
	if descLabel then
		descLabel.Visible = has
		if has then
			descLabel.Text = tostring(cfg.description)
		end
	end
	return has
end

local function renderLevel(cfg): boolean
	local spec = cfg.level
	local has = nonEmpty(spec)
	setVisible(levelBar, has)
	if has and levelLabel then
		levelLabel.Text = type(spec) == "table" and tostring(spec.text or "") or tostring(spec)
	end
	return has
end

local function renderProgress(cfg): boolean
	local spec = cfg.progress
	local has = type(spec) == "table"
	setVisible(progressBar, has)
	if not has then
		return false
	end
	if progressLabel then
		progressLabel.Text = tostring(spec.label or "")
	end
	if fillGradient and spec.color then
		fillGradient.Color = ColorSequence.new(Style.color3(Style.light(spec.color)), Style.color3(Style.dark(spec.color)))
	end
	setProgress(spec.pct or 0, spec.animate == true)
	return true
end

local function styleStatRow(row: Instance, spec: any, order: number)
	local color = Style.hex(spec.color or "#FFFFFF")
	local dark = Style.dark(color)
	local rowFrame: any = row
	rowFrame.LayoutOrder = order

	local outline = row:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = Style.color3(color)
	end

	local iconFrame = row:FindFirstChild("Icon")
	local iconLabel = iconFrame and iconFrame:FindFirstChild("IconLabel")
	local hasIcon = applyIcon(iconLabel, spec.icon, color)
	if iconFrame then
		iconFrame.Visible = hasIcon
	end

	local nameFrame = row:FindFirstChild("Name")
	local nameLabel = nameFrame and nameFrame:FindFirstChild("NameLabel")
	if nameLabel then
		nameLabel.Text = tostring(spec.name or "")
	end

	local valueFrame = row:FindFirstChild("Value")
	local valueLabel = valueFrame and valueFrame:FindFirstChild("ValueLabel")
	if valueLabel then
		valueLabel.Text = tostring(spec.value or "")
		valueLabel.TextColor3 = Style.color3(spec.valueColor or color)
		local vs = valueLabel:FindFirstChildOfClass("UIStroke")
		if vs then
			vs.Color = Style.color3(dark)
		end
	end
end

local function renderStats(cfg): boolean
	resetPool("stat")
	local has = cfg.stats ~= nil and #cfg.stats > 0
	if has and statsFrame then
		for i, spec in ipairs(cfg.stats) do
			local row = take("stat", protos.statRow, statsFrame)
			if row then
				styleStatRow(row, spec, i)
			end
		end
	end
	finishPool("stat")
	setVisible(statsFrame, has)
	return has
end

local function renderStatsHeader(cfg, hasStats: boolean)
	if not div2 then
		return
	end
	div2.Visible = hasStats
	if not hasStats then
		return
	end
	local titled = cfg.statsTitle ~= false
	setVisible(d2Titled, titled)
	setVisible(d2Plain, not titled)
	if titled and d2Label then
		local color = cfg.statsColor or Style.DEFAULT_STATS_COLOR
		d2Label.Text = tostring(cfg.statsTitle or Style.DEFAULT_STATS_TITLE)
		d2Label.TextColor3 = Style.color3(color)
		local s = d2Label:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = Style.color3(color)
		end
	end
end

local function clearBlocks()
	if not rewardsFrame then
		return
	end
	for _, c in ipairs(rewardsFrame:GetChildren()) do
		if c.Name:sub(1, 6) == "Block_" or c.Name == "Footer" then
			c:Destroy()
		end
	end
end

local function buildBlock(spec: any, order: number): Instance
	local block = Instance.new("Frame")
	block.Name = "Block_" .. order
	block.BackgroundTransparency = 1
	block.Size = UDim2.new(1, 0, 0, 0)
	block.AutomaticSize = Enum.AutomaticSize.Y
	block.LayoutOrder = order

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 3)
	layout.Parent = block

	local color = spec.color or Style.DEFAULT_BLOCK_COLOR
	local titleText = spec.title or spec.name
	if nonEmpty(titleText) and protos.blockTitle then
		local t = protos.blockTitle:Clone()
		t.LayoutOrder = 1
		local label = t:FindFirstChildWhichIsA("TextLabel")
		if label then
			local text = tostring(titleText)
			if nonEmpty(spec.key) then
				text = text .. " " .. Rich.dash() .. " " .. Rich.key(spec.key)
			end
			label.Text = text
			label.TextColor3 = Style.color3(color)
			local s = label:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = Style.color3(color)
			end
		end
		t.Parent = block
	end

	local bodyText = spec.text or spec.description
	if nonEmpty(bodyText) and protos.blockText then
		local d = protos.blockText:Clone()
		d.Position = UDim2.new()
		d.AnchorPoint = Vector2.zero
		d.Size = UDim2.new(1, 0, 0, 0)
		d.AutomaticSize = Enum.AutomaticSize.Y
		d.LayoutOrder = 2
		d.Text = tostring(bodyText)
		if spec.dynamic then
			-- Dynamic sections: pixel font, centered, comfortable size, wrapped.
			d.FontFace = Font.new(Style.FONT_DYNAMIC)
			d.TextSize = spec.size or Style.DYNAMIC_TEXT_SIZE
			d.TextWrapped = true
			d.RichText = true
		end
		if spec.align == "Left" then
			d.TextXAlignment = Enum.TextXAlignment.Left
		elseif spec.align == "Center" then
			d.TextXAlignment = Enum.TextXAlignment.Center
		end
		d.Parent = block
	end

	if nonEmpty(spec.cooldown) and protos.blockCooldown then
		local c = protos.blockCooldown:Clone()
		c.Position = UDim2.new()
		c.AnchorPoint = Vector2.zero
		c.LayoutOrder = 3
		if type(spec.cooldown) == "number" then
			c.Text = Rich.sc("CoolDown: " .. spec.cooldown .. "s")
		else
			c.Text = tostring(spec.cooldown)
		end
		c.Parent = block
	end

	return block
end

local function renderBlocks(cfg): boolean
	clearBlocks()
	local hasBlocks = cfg.blocks ~= nil and #cfg.blocks > 0
	local hasFooter = nonEmpty(cfg.footer)
	if not rewardsFrame then
		return false
	end
	if hasBlocks then
		for i, spec in ipairs(cfg.blocks) do
			buildBlock(spec, i).Parent = rewardsFrame
		end
	end
	if hasFooter and protos.footer then
		local f = protos.footer:Clone()
		f.Name = "Footer"
		f.Position = UDim2.new()
		f.AnchorPoint = Vector2.zero
		f.LayoutOrder = 1000
		local text = tostring(cfg.footer)
		f.Text = text:find("<sc>", 1, true) and text or Rich.sc(text)
		f.Parent = rewardsFrame
	end
	local hasDetails = type(cfg.details) == "table" and #cfg.details > 0
	if hasDetails and protos.blockText then
		local lines = {}
		for _, line in ipairs(cfg.details) do
			table.insert(
				lines,
				string.format(
					'<font color="%s">%s: </font><font color="%s">%s</font>',
					Style.hex(line.keyColor or "#AAAAAA"),
					tostring(line.key),
					Style.hex(line.color or "#FFFFFF"),
					tostring(line.value)
				)
			)
		end
		local d = protos.blockText:Clone()
		d.Name = "Block_details"
		d.Position = UDim2.new()
		d.AnchorPoint = Vector2.zero
		d.Size = UDim2.new(1, 0, 0, 0)
		d.AutomaticSize = Enum.AutomaticSize.Y
		d.LayoutOrder = 1001
		d.FontFace = Font.new(Style.FONT_DYNAMIC)
		d.TextSize = Style.SIZE.details
		d.TextWrapped = true
		d.RichText = true
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.Text = table.concat(lines, "\n")
		d.Parent = rewardsFrame
	end
	rewardsFrame.Visible = hasBlocks or hasFooter or hasDetails
	return hasBlocks
end

local function stylePill(pill: Instance, spec: any)
	local base = Style.hex(spec.color or Style.DEFAULT_CLICK_COLOR)
	local dark = Style.dark(base)
	local light = Style.light(base)
	local pillFrame: any = pill
	pillFrame.BackgroundColor3 = Style.color3(dark)

	local strokes = {}
	for _, c in ipairs(pill:GetChildren()) do
		if c:IsA("UIStroke") then
			table.insert(strokes, c)
		end
	end
	if strokes[1] then
		strokes[1].Color = Style.color3(dark)
	end
	if strokes[2] then
		strokes[2].Color = Style.color3(light)
	end

	local label = pill:FindFirstChildWhichIsA("TextLabel")
	if label then
		label.Text = tostring(spec.text or "")
		label.TextColor3 = Style.color3(base)
		local ls = label:FindFirstChildOfClass("UIStroke")
		if ls then
			ls.Color = Style.color3(dark)
		end
	end

	local padding = pill:FindFirstChildOfClass("UIPadding")
	local img = pill:FindFirstChildWhichIsA("ImageLabel")
	local iconData = spec.icon and Style.CLICK_ICONS[spec.icon]
	if img then
		img.Visible = iconData ~= nil
		if iconData then
			img.ImageRectOffset = iconData.offset
			img.ImageRectSize = iconData.size
		end
	end
	if padding then
		padding.PaddingLeft = UDim.new(0, iconData and 16 or 4)
	end
end

local function renderClick(cfg): boolean
	resetPool("pill")
	local specs = cfg.click
	local has = specs ~= nil and #specs > 0
	if has and clickFrame then
		for i, spec in ipairs(specs) do
			local pill = take("pill", protos.pill, clickFrame)
			if pill then
				local pillFrame: any = pill
				pillFrame.LayoutOrder = i
				stylePill(pill, spec)
			end
		end
	end
	finishPool("pill")
	setVisible(clickFrame, has)
	return has
end

local function renderDividers(cfg, hasDesc, hasLevel, hasProgress, hasStats, hasBlocks)
	local over = cfg.dividers or {}
	local function pick(key: string, auto: boolean): boolean
		if over[key] ~= nil then
			return over[key] == true
		end
		return auto
	end
	setVisible(div1, pick("d1", hasDesc and (hasLevel or hasProgress or (hasBlocks and not hasStats))))
	setVisible(div3, pick("d3", hasBlocks and (hasStats or hasLevel or hasProgress)))
	setVisible(div4, pick("d4", false))
end

-- ===================== NORMALIZE (legacy support) =====================
local function normalizeClick(click: any): { any }?
	if click == nil or click == false or click == "" then
		return nil
	end
	if type(click) == "string" then
		local plain = Rich.strip(click)
		if plain == "" then
			return nil
		end
		return { { text = plain:upper(), color = Rich.firstColor(click) or Style.DEFAULT_CLICK_COLOR } }
	end
	if type(click) == "table" then
		if click.text ~= nil then
			return { click }
		end
		if #click > 0 then
			local out = {}
			for _, entry in ipairs(click) do
				if type(entry) == "string" then
					local n = normalizeClick(entry)
					if n then
						table.insert(out, n[1])
					end
				else
					table.insert(out, entry)
				end
			end
			return #out > 0 and out or nil
		end
	end
	return nil
end

local shiftHeld = false

local function normalize(cfg: any)
	local n = {}
	for k, v in pairs(cfg) do
		n[k] = v
	end
	if n.description == nil and n.desc ~= nil then
		n.description = n.desc
	end
	if type(n.stats) == "string" then
		-- legacy: free-text stats block
		n.description = (nonEmpty(n.description) and (tostring(n.description) .. "\n") or "") .. n.stats
		n.stats = nil
	end
	if n.blocks == nil and n.abilities ~= nil then
		n.blocks = n.abilities
	end
	if type(n.level) == "number" then
		n.level = { text = "LV. " .. n.level }
	end
	-- legacy "Coming Soon" click line -> the red footer (no click pill: nothing happens on click)
	if type(n.click) == "string" and Rich.strip(n.click):lower():find("coming soon", 1, true) then
		n.footer = n.footer or '<font color="#FF5555">COMING SOON</font>'
		n.click = nil
	end
	-- dark gray text is never readable on the tooltip: every text field gets the readable partner
	for _, field in ipairs({ "title", "description", "footer", "statsTitle" }) do
		n[field] = Style.readable(n[field])
	end
	if type(n.level) == "table" then
		n.level = { text = Style.readable(n.level.text) }
	end
	Sections.resolve(n, shiftHeld)
	n.click = normalizeClick(n.click)
	return n
end

-- ===================== RENDER =====================
local function render(cfg: any)
	renderTitle(cfg)
	renderTags(cfg)
	local hasDesc = renderDescription(cfg)
	local hasLevel = renderLevel(cfg)
	local hasProgress = renderProgress(cfg)
	local hasStats = renderStats(cfg)
	renderStatsHeader(cfg, hasStats)
	local hasBlocks = renderBlocks(cfg)
	renderClick(cfg)
	renderDividers(cfg, hasDesc, hasLevel, hasProgress, hasStats, hasBlocks)
end

-- ===================== ANCHOR SAFETY NET =====================
-- A tooltip may be tied to the GuiObject it describes (`anchor`). If that
-- object is destroyed, hidden, or inside a disabled ScreenGui, the tooltip
-- hides itself. This covers the lost-MouseLeave cases (menu closing, slots
-- being rebuilt or destroyed) that otherwise leave a tooltip stuck on screen,
-- including live-refresh loops re-showing a tooltip nobody is hovering.
-- (Cursor exits are still handled by each caller's normal MouseLeave.)

--- True if `gui` and all of its ancestors are actually being rendered.
function API.isShown(gui: Instance?): boolean
	if not gui or not gui:IsDescendantOf(game) then
		return false
	end
	local node: Instance? = gui
	while node and node ~= game do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		if node:IsA("LayerCollector") and not (node :: any).Enabled then
			return false
		end
		node = node.Parent
	end
	return true
end

-- ===================== CURSOR FOLLOW =====================
local following = false
local lastConfig: any = nil
local activeSource: string? = nil
local activeAnchor: GuiObject? = nil

-- A freshly shown tooltip has not been laid out yet (its AutomaticSize frame still reports the PREVIOUS
-- tooltip's size), so positioning it right away makes it pop in the wrong place for a frame. It is parked
-- off-screen for LAYOUT_FRAMES frames first, then follows the cursor.
local LAYOUT_FRAMES = 2
local layoutWait = 0
local OFFSCREEN = UDim2.fromOffset(-10000, -10000)

local function positionToMouse()
	if layoutWait > 0 then
		frame.Position = OFFSCREEN
		return
	end
	local mouse = UserInputService:GetMouseLocation()
	local cam = workspace.CurrentCamera
	local viewport = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local size = frame.AbsoluteSize
	local x = mouse.X + CURSOR_OFFSET_X
	local y = mouse.Y + CURSOR_OFFSET_Y
	if size.X > 0 and x + size.X > viewport.X then
		x = mouse.X - size.X - CURSOR_OFFSET_X -- flip to the cursor's left instead of covering it
	end
	if size.Y > 0 and y + size.Y > viewport.Y then
		y = viewport.Y - size.Y
	end
	frame.Position = UDim2.fromOffset(math.max(0, x), math.max(0, y))
end

RunService.RenderStepped:Connect(function()
	if following then
		if activeAnchor and not API.isShown(activeAnchor) then
			API.hide(nil)
			return
		end
		if layoutWait > 0 then
			layoutWait -= 1
		end
		positionToMouse()
	end
end)

-- Collapsible sections: hold SHIFT to expand them while a tooltip is open.
local function onShiftChanged(down: boolean)
	if shiftHeld == down then
		return
	end
	shiftHeld = down
	if following and frame.Visible and lastConfig then
		render(normalize(lastConfig))
		positionToMouse()
	end
end

UserInputService.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		onShiftChanged(true)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		onShiftChanged(false)
	end
end)

-- ===================== HOVER REGISTRY (pointer recognition) =====================
-- MouseEnter only fires when the mouse MOVES onto an element. If the element under a stationary cursor is
-- replaced (a click changes the page, the inventory refreshes, a slot is rebuilt) the new element never gets
-- a MouseEnter, so the tooltip vanished or an old one lingered until the mouse moved again.
-- Owners register "what to show for this element"; recheckPointer() looks at what is under the cursor RIGHT
-- NOW and shows its tooltip (or hides ours if the cursor is over nothing that has one).
local hoverEnter: { [GuiObject]: () -> () } = setmetatable({}, { __mode = "k" }) :: any

--- enterFn is what MouseEnter would do for `gui` (without sounds). Registered elements are looked up by
--- walking up from the GuiObjects under the cursor, so registering a container covers its children.
function API.registerHover(gui: GuiObject, enterFn: () -> ())
	hoverEnter[gui] = enterFn
end

function API.unregisterHover(gui: GuiObject)
	hoverEnter[gui] = nil
end

--- Show the tooltip of whatever registered element is under the cursor. Returns true if one was found.
--- `hideIfNone`: also hide the tooltip when nothing registered is under the cursor (used after refreshes).
function API.recheckPointer(hideIfNone: boolean?): boolean
	-- GetMouseLocation includes the top bar (GuiInset); GetGuiObjectsAtPosition / AbsolutePosition do not
	local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)
	end)
	if ok then
		for _, object in ipairs(objects) do
			if object:IsDescendantOf(host) then
				continue
			end
			local node: Instance? = object
			while node and node ~= playerGui do
				local enter = hoverEnter[node :: GuiObject]
				if enter then
					enter()
					return true
				end
				node = node.Parent
			end
		end
	end
	if hideIfNone then
		API.hide(nil)
	end
	return false
end

-- ===================== PUBLIC API =====================

--- Show a tooltip.
---   source : who owns it, so a stale hide() from another system can't close it.
---   anchor : optional GuiObject the tooltip describes; the tooltip auto-hides
---            when the anchor goes away or the cursor leaves it.
function API.show(config: any, source: string?, anchor: GuiObject?)
	if type(config) ~= "table" then
		return
	end
	if anchor and not API.isShown(anchor) then
		return -- the thing being described isn't on screen (e.g. a stale live-refresh)
	end
	activeSource = source or "generic"
	activeAnchor = anchor
	lastConfig = config
	render(normalize(config))
	following = true
	if not frame.Visible then
		layoutWait = LAYOUT_FRAMES -- fresh show: wait for the layout pass before placing it
	end
	positionToMouse()
	frame.Visible = true
	if glass then
		glass.setEnabled(true)
	end
end

--- Hide the tooltip. With a source, only hides if that source owns it.
function API.hide(source: string?)
	if source and activeSource ~= source then
		return
	end
	frame.Visible = false
	following = false
	activeSource = nil
	activeAnchor = nil
	if glass then
		glass.setEnabled(false)
	end
end

function API.forceHide()
	API.hide(nil)
end

function API.isActiveSource(source: string): boolean
	return activeSource == source
end

function API.isVisible(): boolean
	return frame.Visible
end

function API.getFrame(): Frame
	return frame
end

return API
