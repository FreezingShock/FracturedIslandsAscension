-- ============================================================
--  TooltipModule (ModuleScript)
--  Place inside: TemporaryMenus
--
--  Provides a shared tooltip API used by:
--    - CentralizedMenuController (grid icon hover)
--    - SkillsPageModule (skill card + level box hover)
--    - Future page modules
--
--  The tooltip follows the cursor via RenderStepped and supports
--  multiple "sources" so different systems don't clobber each other.
-- ============================================================

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

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

-- ===================== CONFIG =====================
local TT_OFFSET_X = 18
local TT_OFFSET_Y = 12

-- ===================== STATE =====================
local following = false
local activeSource = nil -- string key identifying who "owns" the tooltip right now

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
	local fy = mousePos.Y - inset.Y + TT_OFFSET_Y

	if fs.X > 0 and fs.Y > 0 then
		fx = math.clamp(fx, 0, vp.X - fs.X)
		fy = math.clamp(fy, 0, vp.Y - fs.Y)
	end

	TooltipFrame.Position = UDim2.fromOffset(fx, fy)
end)

-- ===================== API =====================
local API = {}

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

--- Show a simple tooltip (grid icons, sidebar, etc.)
--- data = { title, desc, stats?, click?, divider? (1 or 2) }
function API.show(data, source)
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
