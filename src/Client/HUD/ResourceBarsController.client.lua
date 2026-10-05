--[[
	ResourceBarsController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Binds the hand-made StarterGui.StatsMenu.Stats rows (one CanvasGroup per resource, each holding a Label and a
	Progress TextLabel) to the Player attributes that ResourceService publishes (<Key> / Max<Key>). Which rows exist and
	what colour they use comes from ResourceConfig; this script creates no UI.

	Progress is a row of identical glyphs (read from the label's own text, so the bar length is whatever you drew).
	The bar fills from the left:
	  * text   rich-text spans: filled glyphs in the resource colour, unfilled glyphs in a darkened copy
	  * stroke the UIGradient under Progress's UIStroke gets a hard colour stop at the fill fraction: white (the stroke's
	           own colour) up to it, a darker gray (stroke colour x gray) after it. Keep that gradient's Rotation at 0.
	The fill eases toward the real value; the Label always shows the exact number.

	The whole Stats group fades out while the Nexus Menu or the inventory is open (MenuBridge.isOpen) and fades back in
	when it closes.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local EASE_SPEED = 8 -- higher = the bar catches up faster
local FADE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- a menu opens
local FADE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- the menu is gone
local STOP_WIDTH = 0.0005 -- width of the hard colour stop in the stroke gradient (0..1)

local function toHex(color: Color3): string
	return string.format("#%02X%02X%02X", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

local function darkened(color: Color3, amount: number): Color3
	return Color3.new(color.R * amount, color.G * amount, color.B * amount)
end

-- [key] = { entry, label, progress, gradient, glyph, total, shown, target, lastFilled, lastStop }
local bars: { [string]: any } = {}

local function renderBar(bar: any)
	local entry = bar.entry
	local fraction = math.clamp(bar.shown, 0, 1)
	local filled = math.floor(fraction * bar.total + 0.5)
	if fraction > 0 and filled == 0 then
		filled = 1 -- never look empty while there is health left
	end
	if filled ~= bar.lastFilled then
		bar.lastFilled = filled
		local fillHex = toHex(entry.color)
		local emptyHex = toHex(darkened(entry.color, ResourceConfig.EMPTY_DARKEN))
		bar.progress.Text = string.format(
			'<font color="%s">%s</font><font color="%s">%s</font>',
			fillHex,
			string.rep(bar.glyph, filled),
			emptyHex,
			string.rep(bar.glyph, bar.total - filled)
		)
	end

	local gradient = bar.gradient
	if gradient and math.abs(fraction - (bar.lastStop or -1)) > 0.001 then
		bar.lastStop = fraction
		local gray = Color3.new(ResourceConfig.EMPTY_DARKEN, ResourceConfig.EMPTY_DARKEN, ResourceConfig.EMPTY_DARKEN)
		if fraction <= 0 then
			gradient.Color = ColorSequence.new(gray)
		elseif fraction >= 1 - STOP_WIDTH then
			gradient.Color = ColorSequence.new(Color3.new(1, 1, 1))
		else
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(fraction, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(fraction + STOP_WIDTH, gray),
				ColorSequenceKeypoint.new(1, gray),
			})
		end
	end
end

--- Read the attributes into the bar's target fraction and the exact-number label.
local function refresh(bar: any, snap: boolean?)
	local key = bar.entry.key
	local current = player:GetAttribute(key)
	local max = player:GetAttribute("Max" .. key)
	if type(current) ~= "number" or type(max) ~= "number" or max <= 0 then
		return
	end
	bar.target = math.clamp(current / max, 0, 1)
	if snap or bar.shown == nil then
		bar.shown = bar.target
		renderBar(bar)
	end
	if bar.label then
		bar.label.Text = string.format("%s: %d/%d", bar.entry.label, math.round(current), math.round(max))
	end
end

-- ===================== FADE WITH THE MENUS =====================
local statsGroup: CanvasGroup? = nil
local menuHidden: boolean? = nil -- what the Stats group currently shows (true = faded out)
local fadeTween: Tween? = nil

local function applyFade(instant: boolean?)
	local group = statsGroup
	if not group then
		return
	end
	local hide = MenuBridge.isOpen()
	if menuHidden == hide and not instant then
		return
	end
	menuHidden = hide
	if fadeTween then
		fadeTween:Cancel()
	end
	local goal = hide and 1 or 0
	if instant then
		group.GroupTransparency = goal
	else
		fadeTween = TweenService:Create(group, hide and FADE_OUT or FADE_IN, { GroupTransparency = goal })
		fadeTween:Play()
	end
end

local warned = false
local function bind(gui: Instance)
	local stats = gui:WaitForChild("Stats", 10)
	if not stats then
		warn("[ResourceBars] StatsMenu.Stats is missing")
		return
	end
	table.clear(bars)
	statsGroup = stats:IsA("CanvasGroup") and stats or nil
	menuHidden = nil
	applyFade(true) -- a freshly created GUI starts in the right state
	for _, entry in ipairs(ResourceConfig.resources) do
		local row = stats:WaitForChild(entry.row, 10)
		local label = row and row:FindFirstChild("Label")
		local progress = row and row:FindFirstChild("Progress")
		if not (row and progress and progress:IsA("TextLabel")) then
			warn("[ResourceBars] StatsMenu row '" .. entry.row .. "' needs a Progress TextLabel")
			continue
		end
		progress.RichText = true
		local original = progress.Text
		local stroke = progress:FindFirstChildOfClass("UIStroke")
		local gradient = stroke and stroke:FindFirstChildOfClass("UIGradient")
		if not gradient and not warned then
			warned = true
			warn("[ResourceBars] no UIGradient under Progress > UIStroke: the unfilled stroke will not darken")
		end
		local bar = {
			entry = entry,
			label = label and label:IsA("TextLabel") and label or nil,
			progress = progress,
			gradient = gradient,
			glyph = utf8.char(utf8.codepoint(original, 1)),
			total = utf8.len(original),
		}
		bars[entry.key] = bar
		refresh(bar, true)
		for _, name in ipairs({ entry.key, "Max" .. entry.key }) do
			player:GetAttributeChangedSignal(name):Connect(function()
				if bars[entry.key] == bar then
					refresh(bar)
				end
			end)
		end
	end
end

local existing = playerGui:FindFirstChild("StatsMenu")
if existing then
	task.spawn(bind, existing)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "StatsMenu" then
		task.spawn(bind, child) -- the GUI was recreated (respawn with ResetOnSpawn)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	applyFade(false)
	local alpha = 1 - math.exp(-dt * EASE_SPEED)
	for _, bar in pairs(bars) do
		if bar.shown ~= nil and bar.target ~= nil and bar.shown ~= bar.target then
			if math.abs(bar.target - bar.shown) < 0.0005 then
				bar.shown = bar.target
			else
				bar.shown += (bar.target - bar.shown) * alpha
			end
			renderBar(bar)
		end
	end
end)
