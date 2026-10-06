--[[
	ResourceBarsController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Drives the resource displays of StarterGui.FIAHUD (built by tools/studio/build_fiahud.luau) from the Player
	attributes ResourceService publishes (<Key> / Max<Key>). Which resources exist and how each is drawn comes from
	ResourceConfig; this script creates no UI.

	  display "panel"  FIAHUD.Root.Stats.<row> (Health, Mana): Bar.Fill is resized in 4 px steps and Value / ValueShadow
	                   show "current / max".
	  display "strip"  FIAHUD.Root.Strip (Stamina): Left.Segments and Right.Segments hold 8 Segment<i> frames each, every
	                   one with a clipped Fill. The 16 segments are ONE strip filled from the left, so it drains from the far
	                   right end toward the badge, then continues on the left half from the badge side outward. The segment
	                   being emptied shrinks in HudTheme.strip.partialStep px steps.
	  Badge            FIAHUD.Root.Badge.Level shows the Player attribute named by ResourceConfig.nexusLevelAttribute.

	The fills ease toward the real value. Stats and Strip (CanvasGroups) fade out while the Nexus Menu or the inventory is
	open (MenuBridge.isOpen) and fade back in when it closes, together with the Wings, Badge and SelectorArrow groups. Root carries a UIScale that shrinks the whole HUD on narrow
	screens (HudTheme.hud).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any
local HudTheme = require(Modules:WaitForChild("Config"):WaitForChild("HudTheme")) :: any

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local EASE_SPEED = 8 -- higher = the bar catches up faster
local FADE_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- a menu opens
local FADE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- the menu is gone
local PIXEL = 4 -- panel fills move in whole art pixels
-- the HUD parts that fade out while a menu is open (the hotbar, tray and vines stay)
local FADE_GROUPS = { "Stats", "Strip", "Wings", "Badge", "SelectorArrow" }

-- [key] = { entry, shown, target, ... } plus fill (panel) or segmentFills (strip)
local bars: { [string]: any } = {}

local function renderBar(bar: any)
	local fraction = math.clamp(bar.shown, 0, 1)
	if bar.fill then
		local steps = math.floor(fraction * bar.innerWidth / PIXEL + 0.5)
		if fraction > 0 and steps == 0 then
			steps = 1 -- never look empty while there is health left
		end
		bar.fill.Size = UDim2.new(0, steps * PIXEL, 1, 0)
		return
	end

	local segmentWidth = HudTheme.strip.segmentSize.X
	local step = HudTheme.strip.partialStep
	local total = #bar.segmentFills
	local filled = fraction * total
	for i, fill in ipairs(bar.segmentFills) do
		local amount = math.clamp(filled - (i - 1), 0, 1)
		local width = segmentWidth
		if amount < 1 then
			width = math.floor(amount * segmentWidth / step + 0.5) * step
			if amount > 0 and width == 0 then
				width = step
			end
		end
		if bar.widths[i] ~= width then
			bar.widths[i] = width
			fill.Size = UDim2.new(0, width, 1, 0)
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
	if bar.value then
		local text = string.format("%d / %d", math.round(current), math.round(max))
		bar.value.Text = text
		bar.shadow.Text = text
	end
end

-- ===================== FADE WITH THE MENUS =====================
local fadeGroups: { CanvasGroup } = {} -- see FADE_GROUPS
local menuHidden: boolean? = nil -- what the groups currently show (true = faded out)
local fadeTweens: { Tween } = {}

local function applyFade(instant: boolean?)
	if #fadeGroups == 0 then
		return
	end
	local hide = MenuBridge.isOpen()
	if menuHidden == hide and not instant then
		return
	end
	menuHidden = hide
	for _, tween in ipairs(fadeTweens) do
		tween:Cancel()
	end
	table.clear(fadeTweens)
	local goal = hide and 1 or 0
	for _, group in ipairs(fadeGroups) do
		if instant then
			group.GroupTransparency = goal
		else
			local tween = TweenService:Create(group, hide and FADE_OUT or FADE_IN, { GroupTransparency = goal })
			table.insert(fadeTweens, tween)
			tween:Play()
		end
	end
end

--- Scale the HUD down on narrow screens (1:1 from HudTheme.hud.fullScaleWidth up).
local function fitHud(root: Instance?)
	local scale = root and root:FindFirstChildOfClass("UIScale")
	local camera = workspace.CurrentCamera
	if scale and camera then
		scale.Scale = math.clamp(camera.ViewportSize.X / HudTheme.hud.fullScaleWidth, HudTheme.hud.minScale, 1)
	end
end

-- ===================== BINDING =====================
--- The 16 strip segments in order: left half first (outer end to the badge), then the right half.
local function collectSegmentFills(strip: Instance): { Frame }?
	local fills = {}
	for _, side in ipairs({ "Left", "Right" }) do
		local segments = strip:FindFirstChild(side) and strip[side]:FindFirstChild("Segments")
		if not segments then
			return nil
		end
		for i = 1, HudTheme.strip.segments do
			local segment = segments:FindFirstChild("Segment" .. i)
			local fill = segment and segment:FindFirstChild("Fill")
			if not (fill and fill:IsA("Frame")) then
				return nil
			end
			table.insert(fills, fill)
		end
	end
	return fills
end

local function bindBadge(root: Instance)
	local level = root:FindFirstChild("Badge") and root.Badge:FindFirstChild("Level")
	if not (level and level:IsA("TextLabel")) then
		warn("[ResourceBars] FIAHUD.Root.Badge.Level (TextLabel) is missing")
		return
	end
	local attribute = ResourceConfig.nexusLevelAttribute
	local function update()
		local value = player:GetAttribute(attribute)
		level.Text = tostring(type(value) == "number" and math.floor(value) or ResourceConfig.nexusLevelStart)
	end
	update()
	player:GetAttributeChangedSignal(attribute):Connect(update)
end

local function bind(gui: Instance)
	local root = gui:WaitForChild("Root", 10)
	if not root then
		warn("[ResourceBars] FIAHUD.Root is missing")
		return
	end
	table.clear(bars)
	table.clear(fadeGroups)
	local stats = root:WaitForChild("Stats", 10)
	local strip = root:WaitForChild("Strip", 10)
	for _, name in ipairs(FADE_GROUPS) do
		local group = root:FindFirstChild(name)
		if group and group:IsA("CanvasGroup") then
			table.insert(fadeGroups, group)
		end
	end
	menuHidden = nil
	applyFade(true) -- a freshly created GUI starts in the right state
	fitHud(root)
	bindBadge(root)

	for _, entry in ipairs(ResourceConfig.resources) do
		local bar: any
		if entry.display == "strip" then
			local fills = strip and collectSegmentFills(strip)
			if not fills then
				warn("[ResourceBars] FIAHUD.Root.Strip needs Left/Right.Segments with Segment1..8.Fill")
				continue
			end
			bar = { entry = entry, segmentFills = fills, widths = {} }
		else
			local panel = stats and stats:FindFirstChild(entry.row)
			local barFrame = panel and panel:FindFirstChild("Bar") -- the panel itself also has a "Fill" (its wood), so go through Bar
			local fill = barFrame and barFrame:FindFirstChild("Fill")
			local value = panel and panel:FindFirstChild("Value")
			local shadow = panel and panel:FindFirstChild("ValueShadow")
			if not (fill and value and shadow) then
				warn("[ResourceBars] Stats." .. entry.row .. " needs Bar.Fill, Value and ValueShadow")
				continue
			end
			bar = {
				entry = entry,
				fill = fill,
				value = value,
				shadow = shadow,
				innerWidth = HudTheme.resourcePanel.barSize.X - 8,
			}
		end
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

local function onViewportChanged()
	local gui = playerGui:FindFirstChild("FIAHUD")
	fitHud(gui and gui:FindFirstChild("Root"))
end
local function watchCamera()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(onViewportChanged)
	end
end
watchCamera()
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	watchCamera()
	onViewportChanged()
end)

local existing = playerGui:FindFirstChild("FIAHUD")
if existing then
	task.spawn(bind, existing)
end
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "FIAHUD" then
		task.spawn(bind, child) -- the GUI was recreated
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
