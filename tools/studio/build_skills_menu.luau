--[[
	RETIRED (3.89.0): the SkillDescFrame breakdown is replaced by the SkillsMenu2 grid. Do not run this. It is kept as
	the record of the old page; build_skills_menu2.luau builds the new templates.

	build_skills_menu.luau - run through the Studio MCP (execute_luau, Edit datamodel, Play stopped).

	Reworks the GUI of the Skills page (SkillsPageModule looked everything up BY NAME, before 3.89.0):
	  StarterGui.CentralizedAscensionMenu...SkillsMenu.SkillDescFrame
	    SkillLevels.ScrollingFrame   the 25 reusable level slots are renamed from I..XXV to Level1..Level25 (the script sets
	                                 text, colors, milestone stroke); the 15 empty spacer Frames that shifted the grid are removed
	    XpBar                        a clone of the tooltip's ProgressBar (ProgressBar > Progress + ProgressLabel) with Left / Right level numerals
	    WisdomLabel                  "<Skill> Wisdom +N% XP"
	    NextReward                   the next level's rewards
	    LayoutOrder: StatNameVal 1, Desc 2, XpBar 3, WisdomLabel 4, NextReward 5, SkillLevels 6
	  ReplicatedStorage.GridTemplates.SkillsMenu1.CarpentrySkills   the sixth hub button (copy of CombatSkills, green;
	                                 the icon is Combat's placeholder until a Carpentry icon exists)

	Polish (idempotent, safe to re-run): every text in SkillDescFrame gets the pixel font (Silkscreen) and a black text stroke; the
	level strip loses its UIGridLayout (SkillsPageModule places the slots along the snake path of SkillsConfig.SNAKE) and gets
	a fixed height with the page toggle underneath.

	Restyle freely, but keep the names. Idempotent: existing pieces are left alone; set FORCE = true to rebuild the new ones.
]]

local FORCE = false
local REMOVE_SPACERS = true

local menu = game:GetService("StarterGui"):WaitForChild("CentralizedAscensionMenu")
local desc = menu:FindFirstChild("SkillDescFrame", true)
assert(desc, "SkillDescFrame not found")
local levels = desc.SkillLevels
local scroll = levels.ScrollingFrame
local done = {}

-- 1. the 25 level slots become Level1..Level25, one each. The old buttons (I..XXV) had hand-made LayoutOrders (they made the snake),
--    so names are assigned by sorting, never by LayoutOrder, and a re-run repairs duplicates or gaps.
local buttons = {}
for index, child in ipairs(scroll:GetChildren()) do
	if child:IsA("TextButton") then
		table.insert(buttons, { button = child, key = tonumber(child.Name:match("%d+")) or child.LayoutOrder, index = index })
	end
end
table.sort(buttons, function(a, b)
	if a.key ~= b.key then
		return a.key < b.key
	end
	return a.index < b.index
end)
local renamed = 0
for i, entry in ipairs(buttons) do
	if i <= 25 then
		if entry.button.Name ~= "Level" .. i then
			entry.button.Name = "Level" .. i
			renamed += 1
		end
		entry.button.LayoutOrder = i
	end
end
if renamed > 0 then
	table.insert(done, "renamed " .. renamed .. " level slots")
end

-- 2. the empty spacer Frames (transparent, no children) shifted the grid by 15 cells
if REMOVE_SPACERS then
	local removed = 0
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("Frame") and child.BackgroundTransparency >= 1 and #child:GetChildren() == 0 then
			child:Destroy()
			removed += 1
		end
	end
	if removed > 0 then
		table.insert(done, "removed " .. removed .. " spacer frames")
	end
end

-- 3. XpBar / WisdomLabel / NextReward
local source = desc.Desc.DescLabel

local function recreate(name)
	local old = desc:FindFirstChild(name)
	if old and not FORCE then
		return false
	end
	if old then
		old:Destroy()
	end
	return true
end

local function textLabel(name, order)
	local label = source:Clone()
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.RichText = true
	label.TextWrapped = true
	label.MaxVisibleGraphemes = -1
	label.Text = ""
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = desc
	return label
end

local PIXEL_FONT = Font.new("rbxassetid://12187371840", Enum.FontWeight.Regular, Enum.FontStyle.Normal)

local function pixelText(label, size, align, strokeThickness)
	label.FontFace = PIXEL_FONT
	label.TextSize = size
	label.TextXAlignment = align
	label.BackgroundTransparency = 1
	label.Text = ""
	label.MaxVisibleGraphemes = -1
	local stroke = label:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = strokeThickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
end

local old = desc:FindFirstChild("XpBar")
if old and (FORCE or not old:FindFirstChild("ProgressBar")) then
	old:Destroy()
	old = nil
end
if not old then
	-- the same bar the tooltips use: a clone of TooltipMenu.Template.ProgressBar (track image + masked fill + label)
	local tooltipGui = game:GetService("StarterGui"):FindFirstChild("TooltipMenu")
	local template = tooltipGui and tooltipGui:FindFirstChild("ProgressBar", true)
	assert(template, "StarterGui.TooltipMenu.Template.ProgressBar not found")
	local bar = template:Clone()
	bar.Name = "XpBar"
	bar.Visible = true
	bar.LayoutOrder = 3
	bar.AnchorPoint = Vector2.zero
	bar.Position = UDim2.new()
	bar.Size = UDim2.new(1, 0, 0, 44)
	bar.ZIndex = 1

	local inner = bar.ProgressBar
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.new(0.5, 0, 0.5, 0)
	inner.Size = UDim2.new(1, -150, 0, 30)
	inner.Visible = true
	inner.ProgressLabel.FontFace = PIXEL_FONT
	inner.ProgressLabel.TextSize = 18

	local left = source:Clone()
	left.Name = "Left"
	left.AnchorPoint = Vector2.new(0, 0.5)
	left.Position = UDim2.new(0, 0, 0.5, 0)
	left.Size = UDim2.new(0, 64, 1, 0)
	left.AutomaticSize = Enum.AutomaticSize.None
	left.TextColor3 = Color3.new(1, 1, 1)
	left.RichText = false
	pixelText(left, 26, Enum.TextXAlignment.Center, 2)
	left.Parent = bar

	local right = left:Clone()
	right.Name = "Right"
	right.AnchorPoint = Vector2.new(1, 0.5)
	right.Position = UDim2.new(1, 0, 0.5, 0)
	right.TextColor3 = Color3.fromRGB(170, 170, 170)
	right.Parent = bar

	bar.Parent = desc
	table.insert(done, "XpBar")
end

if recreate("WisdomLabel") then
	textLabel("WisdomLabel", 4)
	table.insert(done, "WisdomLabel")
end
if recreate("NextReward") then
	textLabel("NextReward", 5)
	table.insert(done, "NextReward")
end

desc.StatNameVal.LayoutOrder = 1
desc.Desc.LayoutOrder = 2
levels.LayoutOrder = 6

-- 4. polish: pixel font + black text stroke everywhere, the strip without a grid layout
local function style(label, size)
	label.FontFace = PIXEL_FONT
	if size then
		label.TextSize = size
	end
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.Parent = label
	end
	stroke.Thickness = math.max(stroke.Thickness, 2)
end

style(desc.StatNameVal.StatName, 36)
style(desc.StatNameVal.StatValue, 36)
style(desc.Desc.DescLabel, 20)
style(desc.WisdomLabel, 20)
style(desc.NextReward, 20)
for i = 1, 25 do
	local slot = scroll:FindFirstChild("Level" .. i)
	if slot then
		local slotLabel = slot.Label
		slotLabel.TextScaled = true
		style(slotLabel)
	end
end
style(levels.PageToggle.Label, 20)

local grid = scroll:FindFirstChildOfClass("UIGridLayout")
if grid then
	grid:Destroy()
end
local padding = scroll:FindFirstChildOfClass("UIPadding")
if padding then
	padding:Destroy() -- the snake positions include their own padding
end
local rows, cell, gapY, pad = 4, 65, 7, 10
local stripHeight = pad * 2 + rows * cell + (rows - 1) * gapY
scroll.AutomaticSize = Enum.AutomaticSize.None
scroll.Size = UDim2.new(1, 0, 0, stripHeight)
scroll.ScrollBarThickness = 0
scroll.ClipsDescendants = true
levels.AutomaticSize = Enum.AutomaticSize.None
levels.Size = UDim2.new(1, 0, 0, stripHeight + 60)
local toggle = levels.PageToggle
toggle.AutomaticSize = Enum.AutomaticSize.None
toggle.Size = UDim2.new(0, 320, 0, 44)
toggle.Label.AutomaticSize = Enum.AutomaticSize.None
toggle.Label.Size = UDim2.fromScale(1, 1)
toggle.Label.TextWrapped = false
toggle.Label.RichText = true
levels.PageToggle.AnchorPoint = Vector2.new(0.5, 0)
levels.PageToggle.Position = UDim2.new(0.5, 0, 0, stripHeight + 5)
table.insert(done, "polished fonts/strokes and the strip")

-- 5. the sixth hub button
local hub = game:GetService("ReplicatedStorage"):WaitForChild("GridTemplates"):WaitForChild("SkillsMenu1")
local carpentry = hub:FindFirstChild("CarpentrySkills")
if carpentry and FORCE then
	carpentry:Destroy()
	carpentry = nil
end
if not carpentry then
	local color = Color3.fromHex("55FF55")
	local copy = hub.CombatSkills:Clone()
	copy.Name = "CarpentrySkills"
	copy.BackgroundColor3 = color
	local bg = copy:FindFirstChild("BG")
	if bg then
		bg.ImageColor3 = color
		local bgStroke = bg:FindFirstChildOfClass("UIStroke")
		if bgStroke then
			bgStroke.Color = color
		end
	end
	copy.LayoutOrder = 7
	copy.Parent = hub
	table.insert(done, "CarpentrySkills hub button")
end

return #done == 0 and "nothing to do (everything exists)" or table.concat(done, "; ")
