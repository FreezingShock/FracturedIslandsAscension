--[[
	CurrencyHUD (LocalScript)
	Place inside: StarterPlayerScripts

	Always-on currency bar so the player can see what they own without opening
	a menu. Built entirely in code (no Studio GUI needed), driven by the
	StatisticsUpdated payload the server already sends:
	  payload.skills[skill][statKey] = { count, lifetime, session, multiplier }

	Row 1: General coins   Row 2: Farming resources
	A chip appears once the player owns (or has ever owned) that stat, and
	"pops" whenever its amount goes up.

	Zero game logic: display only.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any
local StatisticsUpdated = ReplicatedStorage:WaitForChild("StatisticsUpdated")

-- ===================== CONFIG =====================
-- Which stats the HUD tracks. alwaysShow = how many leading chips are visible
-- even at zero so a brand-new player sees where their income appears.
local ROWS = {
	{
		skill = "General",
		keys = { "BronzeCoins", "SilverCoins", "GoldCoins", "PlatinumCoins", "DiamondCoins", "EmeraldCoins" },
		alwaysShow = 2,
	},
	{
		skill = "Farming",
		keys = { "Seeds", "Wheat", "Carrots", "Cactus" },
		alwaysShow = 0,
	},
}

-- Mirrors StatisticsDataManager PASSIVE_GRANTS (Bronze, per second, before multiplier).
local BRONZE_PASSIVE_BASE = 10

local FONT = Enum.Font.Arcade
local CHIP_HEIGHT = 34
local POP_INFO = TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- ===================== GUI SKELETON =====================
local gui = Instance.new("ScreenGui")
gui.Name = "CurrencyHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 2
gui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(0.5, 0)
container.Position = UDim2.new(0.5, 0, 0, 10)
container.Size = UDim2.fromOffset(0, 0)
container.AutomaticSize = Enum.AutomaticSize.XY
container.BackgroundTransparency = 1
container.Parent = gui

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.Padding = UDim.new(0, 6)
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Parent = container

-- ===================== HIDE WHILE THE MENU IS OPEN =====================
-- The bar sits over the menu's title bar, so it slides up out of the way while the menu/inventory is open.
local POS_SHOWN = UDim2.new(0.5, 0, 0, 10)
local POS_HIDDEN = UDim2.new(0.5, 0, 0, -140)
local SLIDE_INFO = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local slideTween: Tween? = nil

MenuBridge.onStateChanged(function(mode)
	if slideTween then
		slideTween:Cancel()
	end
	slideTween = TweenService:Create(container, SLIDE_INFO, { Position = mode and POS_HIDDEN or POS_SHOWN })
	slideTween:Play()
end)

-- ===================== CHIP FACTORY =====================
local chips = {} -- [skill .. "." .. key] = { frame, amount, scale, last, rate? }

local function hexToColor(hex: string?): Color3
	local ok, c = pcall(Color3.fromHex, hex or "#FFFFFF")
	return ok and c or Color3.new(1, 1, 1)
end

local function makeChip(parent: Instance, skill: string, key: string, order: number)
	local cfg = StatisticsConfig.statConfigLookup[skill] and StatisticsConfig.statConfigLookup[skill][key]
	local color = hexToColor(cfg and cfg.color)

	local frame = Instance.new("Frame")
	frame.Name = key
	frame.LayoutOrder = order
	frame.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	frame.BackgroundTransparency = 0.2
	frame.Visible = false
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 1.5
	stroke.Transparency = 0.15
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = frame

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = frame

	local scale = Instance.new("UIScale")
	scale.Parent = frame

	-- Icon (falls back to a colored dot when the stat has no icon asset)
	if cfg and cfg.icon and cfg.icon ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.LayoutOrder = 1
		icon.Size = UDim2.fromOffset(24, 24)
		icon.BackgroundTransparency = 1
		icon.Image = cfg.icon
		icon.ScaleType = Enum.ScaleType.Fit
		icon.Parent = frame
	else
		local dot = Instance.new("Frame")
		dot.Name = "Icon"
		dot.LayoutOrder = 1
		dot.Size = UDim2.fromOffset(14, 14)
		dot.BackgroundColor3 = color
		dot.Parent = frame
		local dc = Instance.new("UICorner")
		dc.CornerRadius = UDim.new(1, 0)
		dc.Parent = dot
	end

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.LayoutOrder = 2
	amount.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
	amount.AutomaticSize = Enum.AutomaticSize.X
	amount.BackgroundTransparency = 1
	amount.Font = FONT
	amount.TextSize = 18
	amount.TextColor3 = color
	amount.TextStrokeTransparency = 0.35
	amount.Text = "0"
	amount.Parent = frame

	local rate
	if key == "BronzeCoins" then
		rate = Instance.new("TextLabel")
		rate.Name = "Rate"
		rate.LayoutOrder = 3
		rate.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
		rate.AutomaticSize = Enum.AutomaticSize.X
		rate.BackgroundTransparency = 1
		rate.Font = FONT
		rate.TextSize = 13
		rate.TextColor3 = Color3.fromRGB(170, 170, 170)
		rate.Text = ""
		rate.Parent = frame
	end

	chips[skill .. "." .. key] = { frame = frame, amount = amount, scale = scale, last = nil, rate = rate }
end

for rowIndex, row in ipairs(ROWS) do
	local rowFrame = Instance.new("Frame")
	rowFrame.Name = row.skill
	rowFrame.LayoutOrder = rowIndex
	rowFrame.Size = UDim2.fromOffset(0, CHIP_HEIGHT)
	rowFrame.AutomaticSize = Enum.AutomaticSize.X
	rowFrame.BackgroundTransparency = 1
	rowFrame.Parent = container

	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.VerticalAlignment = Enum.VerticalAlignment.Center
	rowList.Padding = UDim.new(0, 6)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = rowFrame

	for i, key in ipairs(row.keys) do
		makeChip(rowFrame, row.skill, key, i)
	end
end

-- ===================== REFRESH =====================
local function refresh(payload)
	if not payload or not payload.skills then
		return
	end
	for _, row in ipairs(ROWS) do
		local skillData = payload.skills[row.skill]
		if skillData then
			for i, key in ipairs(row.keys) do
				local entry = skillData[key]
				local chip = chips[row.skill .. "." .. key]
				if entry and chip then
					local count = entry.count or 0
					local shouldShow = i <= row.alwaysShow or count > 0 or (entry.lifetime or 0) > 0
					chip.frame.Visible = shouldShow
					if shouldShow then
						chip.amount.Text = MoneyLib.DealWithPoints(math.floor(count))
						-- pop on increase (skip the very first paint)
						if chip.last ~= nil and count > chip.last then
							chip.scale.Scale = 1.15
							TweenService:Create(chip.scale, POP_INFO, { Scale = 1 }):Play()
						end
						chip.last = count
						if chip.rate then
							local perSec = math.floor(BRONZE_PASSIVE_BASE * (entry.multiplier or 1))
							chip.rate.Text = "+" .. MoneyLib.DealWithPoints(perSec) .. "/s"
						end
					end
				end
			end
		end
	end
end

StatisticsUpdated.OnClientEvent:Connect(refresh)
