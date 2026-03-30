-- ============================================================
--  TooltipModule (ModuleScript)
--  Place inside: TemporaryMenus
--
--  Provides a shared tooltip API used by:
--    - CentralizedMenuController (grid icon hover)
--    - SkillsPageModule (skill card + level box hover)
--    - ProfilePageModule (skill attribute icon tooltips)
--    - Future page modules
--
--  The tooltip follows the cursor via RenderStepped and supports
--  multiple "sources" so different systems don't clobber each other.
--
--  Icon stat lines:
--    Callers create icon stat lines via API.createIconStatLine().
--    All clones are auto-destroyed on hide/forceHide/show.
--    Tail elements (StatsLabel, RewardsLabel, Divider3, ClickLabel)
--    are bumped via API.adjustForIconCount(n) and reset on cleanup.
--
--  Icon title:
--    API.createIconTitle() clones IconTitleLabelTemplate into LO 0,
--    hides the native TitleLabel, and auto-cleans on hide/forceHide/show.
-- ============================================================

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================== TOOLTIP GUI REFERENCES =====================
local TooltipGui = playerGui:WaitForChild("TooltipMenu")
local TooltipFrame = TooltipGui:WaitForChild("TooltipFrame")
local TT_Title = TooltipFrame:WaitForChild("TitleLabel")
local TT_Desc = TooltipFrame:WaitForChild("DescriptionLabel")
local TT_Stats = TooltipFrame:WaitForChild("StatsLabel")
local TT_Click = TooltipFrame:WaitForChild("ClickLabel")
local TT_Divider1 = TooltipFrame:WaitForChild("Divider1")
local TT_Divider2 = TooltipFrame:WaitForChild("Divider2")
local TT_Divider3 = TooltipFrame:WaitForChild("Divider3")

local TT_ProgressOuter = TooltipFrame:WaitForChild("ProgressBar")
local TT_ProgressBar = TT_ProgressOuter:WaitForChild("ProgressBar")
local TT_ProgressFill = TT_ProgressBar:WaitForChild("Frame")
local TT_ProgressBL = TT_ProgressOuter:WaitForChild("ProgressBarLabel")
local TT_ProgressLabel = TooltipFrame:WaitForChild("ProgressLabel")
local TT_Rewards = TooltipFrame:WaitForChild("RewardsLabel")

-- ===================== ICON TEMPLATES =====================
local IconStatsTemplate = ReplicatedStorage:WaitForChild("IconStatsLabelTemplate")
local IconTitleTemplate = ReplicatedStorage:WaitForChild("IconTitleLabelTemplate")

-- ===================== LIQUID GLASS =====================
local Modules = ReplicatedStorage:WaitForChild("Modules")
local LiquidGlassHandler = require(Modules:WaitForChild("LiquidGlassHandler"))
local glassHandle = LiquidGlassHandler.apply(TooltipFrame, {
	Stroke = { enabled = false },
	SeparatedBorderOutline = { enabled = false },
})
if glassHandle then
	glassHandle.setEnabled(false) -- tooltip starts hidden
end
-- Static separated outline — always visible when tooltip is shown
local staticOutline = Instance.new("UIStroke")
staticOutline.Name = "TooltipOutline"
staticOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
staticOutline.LineJoinMode = Enum.LineJoinMode.Round
staticOutline.Thickness = 3
staticOutline.Color = Color3.fromRGB(213, 229, 255)
staticOutline.Transparency = 1 -- starts hidden
staticOutline.BorderOffset = UDim.new(0, 7)
staticOutline.Parent = TooltipFrame

-- ===================== CONFIG =====================
local TT_OFFSET_X = 18
local TT_OFFSET_Y = 12

-- ===================== LAYOUT ORDER CONSTANTS =====================
-- Base LayoutOrders when zero icon stat lines are present.
-- Icon clones occupy LO 6..6+N-1; tail elements shift by N.
local ICON_STATS_BASE_LO = 6

local DEFAULT_TAIL_ORDERS = {
	StatsLabel = 6,
	RewardsLabel = 7,
	Divider3 = 8,
	ClickLabel = 9,
}

-- ===================== STAT ICON SPRITESHEET =====================
-- Single spritesheet for all stat/attribute icons.
-- Icons are arranged in a grid of cellSize × cellSize px cells.
-- Callers pass { col, row } coordinates to createIconStatLine().
-- Upload the spritesheet PNG to Roblox and paste the asset ID here.
local STAT_SPRITESHEET = {
	assetId = "rbxassetid://132086377310489", -- TODO: replace with uploaded spritesheet asset ID
	cellSize = 170,
}

-- ===================== STATE =====================
local following = false
local activeSource = nil -- string key identifying who "owns" the tooltip right now
local activeIconTitle = nil -- tracked clone of IconTitleLabelTemplate (nil when not active)

-- ===================== INTERNAL CLEANUP =====================

--- Destroy all IconStatsLabel clones parented to TooltipFrame.
local function clearIconStats()
	for _, child in ipairs(TooltipFrame:GetChildren()) do
		if child.Name == "IconStatsLabel" then
			child:Destroy()
		end
	end
end

--- Destroy the IconTitleLabel clone and restore native TitleLabel.
local function clearIconTitle()
	if activeIconTitle then
		activeIconTitle:Destroy()
		activeIconTitle = nil
		TT_Title.Visible = true
	end
end

--- Reset tail element LayoutOrders to their defaults (no icon offset).
local function resetTailOrders()
	TT_Stats.LayoutOrder = DEFAULT_TAIL_ORDERS.StatsLabel
	TT_Rewards.LayoutOrder = DEFAULT_TAIL_ORDERS.RewardsLabel
	TT_Divider3.LayoutOrder = DEFAULT_TAIL_ORDERS.Divider3
	TT_Click.LayoutOrder = DEFAULT_TAIL_ORDERS.ClickLabel
end

--- Full cleanup — called by hide / forceHide / show.
local function cleanupIcons()
	clearIconStats()
	clearIconTitle()
	resetTailOrders()
end

-- ===================== CURSOR FOLLOW =====================
RunService.RenderStepped:Connect(function()
	if not following then
		return
	end
	local mousePos = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local vp = workspace.CurrentCamera.ViewportSize
	local fs = TooltipFrame.AbsoluteSize

	local fx = mousePos.X + TT_OFFSET_X
	local fy = mousePos.Y + TT_OFFSET_Y

	if fs.X > 0 and fs.Y > 0 then
		fx = math.clamp(fx, 0, vp.X - fs.X)
		fy = math.clamp(fy, 0, vp.Y - fs.Y)
	end

	TooltipFrame.Position = UDim2.fromOffset(fx, fy)
end)

-- ===================== API =====================
local API = {}

-- Exposed constant so callers know where icon LOs start.
API.ICON_STATS_BASE_LO = ICON_STATS_BASE_LO

-- Exposed spritesheet config so callers can reference it directly.
API.STAT_SPRITESHEET = STAT_SPRITESHEET

-- References to the tooltip frame children, exposed so page modules
-- can manipulate layout order, visibility, etc. directly when needed.
API.refs = {
	Frame = TooltipFrame,
	Title = TT_Title,
	Desc = TT_Desc,
	Stats = TT_Stats,
	Click = TT_Click,
	Divider1 = TT_Divider1,
	Divider2 = TT_Divider2,
	Divider3 = TT_Divider3,
	ProgressOuter = TT_ProgressOuter,
	ProgressBar = TT_ProgressBar,
	ProgressFill = TT_ProgressFill,
	ProgressBL = TT_ProgressBL,
	ProgressLabel = TT_ProgressLabel,
	Rewards = TT_Rewards,
}

-- ===================== ICON TITLE API =====================

--- Clone IconTitleLabelTemplate, configure icon + text, hide the
--- native TitleLabel, and parent the clone at LayoutOrder 0.
--- Auto-cleaned by hide/forceHide/show via cleanupIcons().
---
--- config fields:
---   icon  : table {col, row} for spritesheet OR string rbxassetid
---   color : string  — hex color (e.g. "#FF5555")
---   name  : string  — attribute display name
---   value : string  — formatted attribute value (shown in white)
function API.createIconTitle(config)
	-- Tear down any previous icon title clone first
	clearIconTitle()

	local clone = IconTitleTemplate:Clone()
	clone.Name = "IconTitleLabel"
	clone.LayoutOrder = 0 -- same slot as TitleLabel

	-- ── Icon (TitleIcon) ──
	local img = clone:FindFirstChild("TitleIcon")
	if img then
		local iconData = config.icon
		local hexColor = config.color or "#FFFFFF"

		if type(iconData) == "table" then
			local col = iconData[1] or 0
			local row = iconData[2] or 0
			local cs = STAT_SPRITESHEET.cellSize
			img.Image = STAT_SPRITESHEET.assetId
			img.ImageRectSize = Vector2.new(cs, cs)
			img.ImageRectOffset = Vector2.new(col * cs, row * cs)
			img.ImageColor3 = Color3.fromHex(hexColor)
			img.ImageTransparency = 0
		elseif type(iconData) == "string" and iconData ~= "" then
			img.Image = iconData
			img.ImageRectSize = Vector2.new(0, 0)
			img.ImageRectOffset = Vector2.new(0, 0)
			img.ImageColor3 = Color3.fromHex(hexColor)
			img.ImageTransparency = 0
		else
			img.ImageTransparency = 1
		end
	end

	-- ── Text (TitleLabel) ──
	local titleLabel = clone:FindFirstChild("TitleLabel")
	if titleLabel then
		titleLabel.RichText = true
		titleLabel.TextColor3 = Color3.fromHex(config.color or "#FFFFFF")
		titleLabel.Text = string.format('%s <font color="#FFFFFF">%s</font>', config.name or "", config.value or "0")
	end

	-- Hide the native TitleLabel and parent the clone
	TT_Title.Visible = false
	clone.Parent = TooltipFrame
	activeIconTitle = clone

	return clone
end

--- Manually tear down the icon title clone (callers rarely need this
--- directly — hide/forceHide/show handle it automatically).
function API.clearIconTitle()
	clearIconTitle()
end

-- ===================== ICON STAT LINE API =====================

--- Clone the IconStatsLabelTemplate, configure it, and parent it
--- to TooltipFrame.  Returns the clone.
---
--- config fields:
---   icon        : table {col, row} for spritesheet OR string rbxassetid (legacy)
---   color       : string  — hex color (e.g. "#FF5555")
---   name        : string  — stat display name
---   value       : string  — formatted stat value
---   layoutOrder : number  — LayoutOrder in TooltipFrame
function API.createIconStatLine(config)
	local clone = IconStatsTemplate:Clone()
	clone.Name = "IconStatsLabel"
	clone.LayoutOrder = config.layoutOrder or ICON_STATS_BASE_LO

	-- Icon image + tint (recursive find as safety net)
	local img = clone:FindFirstChild("ImageLabel", true)
	if img then
		local iconData = config.icon
		local hexColor = config.color or "#FFFFFF"

		if type(iconData) == "table" then
			-- Spritesheet coordinates: { col, row }
			local col = iconData[1] or 0
			local row = iconData[2] or 0
			local cs = STAT_SPRITESHEET.cellSize
			img.Image = STAT_SPRITESHEET.assetId
			img.ImageRectSize = Vector2.new(cs, cs)
			img.ImageRectOffset = Vector2.new(col * cs, row * cs)
			img.ImageColor3 = Color3.fromHex(hexColor)
			img.ImageTransparency = 0
		elseif type(iconData) == "string" and iconData ~= "" then
			-- Legacy direct asset ID
			img.Image = iconData
			img.ImageRectSize = Vector2.new(0, 0)
			img.ImageRectOffset = Vector2.new(0, 0)
			img.ImageColor3 = Color3.fromHex(hexColor)
			img.ImageTransparency = 0
		else
			-- No icon — hide
			img.ImageTransparency = 1
		end
	end

	-- Stat name + value text (recursive find as safety net)
	local statLabel = clone:FindFirstChild("StatLabel", true)
	if statLabel then
		statLabel.RichText = true
		statLabel.TextColor3 = Color3.fromHex(config.color or "#FFFFFF")
		statLabel.Text = string.format('%s <font color="#FFFFFF">%s</font>', config.name or "", config.value or "0")
	else
		warn("[TooltipModule] StatLabel not found in IconStatsLabelTemplate clone — check template hierarchy")
	end

	clone.Parent = TooltipFrame
	return clone
end

--- Shift tail elements (StatsLabel, RewardsLabel, Divider3, ClickLabel)
--- down by `n` to make room for `n` icon stat line clones.
function API.adjustForIconCount(n)
	TT_Stats.LayoutOrder = DEFAULT_TAIL_ORDERS.StatsLabel + n
	TT_Rewards.LayoutOrder = DEFAULT_TAIL_ORDERS.RewardsLabel + n
	TT_Divider3.LayoutOrder = DEFAULT_TAIL_ORDERS.Divider3 + n
	TT_Click.LayoutOrder = DEFAULT_TAIL_ORDERS.ClickLabel + n
end

--- Manually clear all icon stat clones (callers rarely need this
--- directly — hide/forceHide/show handle it automatically).
function API.clearIconStats()
	clearIconStats()
end

--- Manually reset tail LayoutOrders to defaults.
function API.resetTailOrders()
	resetTailOrders()
end

-- ===================== SHOW / HIDE API =====================

--- Show a simple tooltip (grid icons, sidebar, etc.)
--- data = { title, desc, stats?, click?, divider? (1 or 2) }
function API.show(data, source)
	-- Clean up any icon clones from a previous tooltip owner
	cleanupIcons()

	source = source or "generic"
	activeSource = source
	following = true

	TT_Title.Text = data.title or ""

	TT_Desc.Text = data.desc or ""
	TT_Desc.Visible = (data.desc ~= nil and data.desc ~= "")

	TT_Click.Text = data.click or ""
	TT_Click.Visible = (data.click ~= nil and data.click ~= "")

	if TT_Stats then
		TT_Stats.Text = data.stats or ""
		TT_Stats.Visible = (data.stats ~= nil and data.stats ~= "")
	end

	-- AFTER
	-- AFTER
	TT_Divider1.Visible = TT_Desc.Visible and TT_Click.Visible -- only show if both sections present
	TT_Divider2.Visible = false
	TT_Divider3.Visible = false

	-- Hide progress and rewards by default for simple tooltips
	TT_ProgressOuter.Visible = false
	TT_ProgressLabel.Visible = false
	TT_Rewards.Visible = false

	TooltipFrame.Visible = true

	if glassHandle then
		glassHandle.setEnabled(true)
	end
	staticOutline.Transparency = 0.15
end

--- Hide tooltip, but only if the caller is the current owner.
--- Pass source = nil to force-hide regardless.
function API.hide(source)
	if source and activeSource ~= source then
		return
	end
	TooltipFrame.Visible = false
	following = false
	activeSource = nil

	if glassHandle then
		glassHandle.setEnabled(false)
	end

	-- Clean up icon clones and reset layout
	cleanupIcons()

	-- Reset visibility of optional elements
	TT_ProgressOuter.Visible = false
	TT_ProgressLabel.Visible = false
	TT_Rewards.Visible = false
	TT_Divider3.Visible = false
end

--- Force hide from any source (used on menu close).
function API.forceHide()
	TooltipFrame.Visible = false
	following = false
	activeSource = nil

	if glassHandle then
		glassHandle.setEnabled(false)
	end
	staticOutline.Transparency = 1

	-- Clean up icon clones and reset layout
	cleanupIcons()

	TT_ProgressOuter.Visible = false
	TT_ProgressLabel.Visible = false
	TT_Rewards.Visible = false
	TT_Divider3.Visible = false
end

--- Show the tooltip with full manual control (for skill cards/levels).
--- The caller sets all labels directly via API.refs, then calls showRaw.
function API.showRaw(source)
	source = source or "raw"
	activeSource = source
	following = true
	TooltipFrame.Visible = true

	if glassHandle then
		glassHandle.setEnabled(true)
	end
	staticOutline.Transparency = 0.15
end

--- Check if a given source currently owns the tooltip.
function API.isActiveSource(source)
	return activeSource == source
end

--- Tween the progress fill bar.
function API.tweenProgressFill(pct)
	TweenService:Create(
		TT_ProgressFill,
		TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1) }
	):Play()
end

return API
