-- build_nexus_badge.luau
-- SURGICAL install of the Nexus Level badge's layers (Figma "Level Badge" component set, FIA HUD Design System).
-- Run on the Edit datamodel with the Studio MCP (stop Play first). Touches ONLY StarterGui.FIAHUD.Root.Badge: it replaces the
-- old hex layers (Outline, Rim, Face, RingOuter, RingInner) and keeps the Level label, the Badge group and everything else of the HUD.
--
-- Badge (112 x 128), bottom to top (all numbers/colours = ReplicatedStorage.Modules.Config.HudTheme.badge.xp):
--   Outline  dark brown hex            Stroke  thin light-brown ring (4px)        Trough  the empty xp (dark brown)
--   XpClip   Frame, ClipsDescendants, AnchorPoint (0,1) at the trough's bottom; its HEIGHT is the progress (NexusBadgeView tweens it)
--     XpHex  the full-size green pixel-gradient hex (never resized: the clip reveals it from the bottom up, clipped to the hex shape
--            by the row widths); 5 bands, a checker dither between bands
--   Face     the yellow hex, 4 shaded bands + dither rows (HudTheme.badge.xp.faceRows)       Level  (kept) the number
-- Idempotent: skips when XpClip exists unless FORCE = true. build_nexus_page.luau builds the SAME layers for the page's big badge.
local FORCE = false

local RS = game:GetService("ReplicatedStorage")
local XP = require(RS.Modules.Config.HudTheme:Clone()).badge.xp -- a clone, so a stale require cache never wins

local gui = game:GetService("StarterGui"):FindFirstChild("FIAHUD")
local badge = gui and gui:FindFirstChild("Root") and gui.Root:FindFirstChild("Badge")
if not badge then
	return "FIAHUD.Root.Badge not found (run tools/studio/build_fiahud.luau first)"
end
if badge:FindFirstChild("XpClip") and not FORCE then
	return "Badge already has XpClip (set FORCE = true to rebuild the layers)"
end

local PX = 4

local function frame(parent, name, x, y, w, h, color, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	if color then
		f.BackgroundColor3 = color
	else
		f.BackgroundTransparency = 1
	end
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

--- the hexagon as 4px rows: { x, y, w } per row (the same shape as build_fiahud's hexRows)
local function rowsOf(w, h)
	local rows, cx, out = h / PX, w / 2, {}
	for r = 0, rows - 1 do
		local yc = (r + 0.5) * PX
		local a = yc < h / 4 and cx * (yc / (h / 4)) or (yc > 3 * h / 4 and cx * ((h - yc) / (h / 4)) or cx)
		local hw = math.max(PX, math.floor(a / PX + 0.5) * PX)
		table.insert(out, { cx - hw, r * PX, 2 * hw })
	end
	return out
end

-- a flat hex; `pick(rowIndex, columnIndex)` may return a colour per 4px cell for rows that must be dithered (nil = the whole row is `color`)
local function hexRows(parent, name, w, h, x, y, color, z, pick)
	local holder = frame(parent, name, x, y, w, h, nil, z)
	for i, r in ipairs(rowsOf(w, h)) do
		local cells = pick and pick(i - 1, r)
		if cells then
			for cx = r[1], r[1] + r[3] - PX, PX do
				frame(holder, "p", cx, r[2], PX, PX, cells(cx // PX), z)
			end
		else
			frame(holder, "r" .. (i - 1), r[1], r[2], r[3], PX, color, z)
		end
	end
	return holder
end

-- clear the old layers (the Level label stays)
for _, name in ipairs({ "Outline", "Rim", "Face", "RingOuter", "RingInner", "Stroke", "Trough", "XpClip" }) do
	local old = badge:FindFirstChild(name)
	if old then
		old:Destroy()
	end
end

hexRows(badge, "Outline", 112, 128, 0, 0, XP.outline, 1)
hexRows(badge, "Stroke", XP.strokeSize.X, XP.strokeSize.Y, XP.strokePos.X, XP.strokePos.Y, XP.stroke, 2)
hexRows(badge, "Trough", XP.hexSize.X, XP.hexSize.Y, XP.hexPos.X, XP.hexPos.Y, XP.trough, 3)

-- XpClip: bottom-anchored, ClipsDescendants; XpHex is pinned to ITS bottom so it never moves while the clip grows
local clip = frame(badge, "XpClip", XP.hexPos.X, XP.hexPos.Y + XP.hexSize.Y, XP.hexSize.X, 0, nil, 4)
clip.AnchorPoint = Vector2.new(0, 1)
clip.ClipsDescendants = true
local xpHex = hexRows(clip, "XpHex", XP.hexSize.X, XP.hexSize.Y, 0, 0, XP.fillBands[3], 4, function(i, r)
	local n, bands = #rowsOf(XP.hexSize.X, XP.hexSize.Y), XP.fillBands
	local function band(row)
		return math.min(#bands, math.floor(row / n * #bands) + 1)
	end
	local b = band(i)
	local last = i + 1 < n and band(i + 1) ~= b
	local first = i > 0 and band(i - 1) ~= b
	if last then
		return function(col)
			return col % 2 == 0 and bands[b] or bands[b + 1]
		end
	elseif first then
		return function(col)
			return col % 2 == 0 and bands[b] or bands[b - 1]
		end
	end
	return nil -- a plain row
end)
xpHex.AnchorPoint = Vector2.new(0, 1)
xpHex.Position = UDim2.new(0, 0, 1, 0)
-- plain rows take their band colour (hexRows painted them with the middle band): repaint by band
do
	local n, bands = #rowsOf(XP.hexSize.X, XP.hexSize.Y), XP.fillBands
	for _, row in ipairs(xpHex:GetChildren()) do
		local i = tonumber(row.Name:match("^r(%d+)$"))
		if i then
			row.BackgroundColor3 = bands[math.min(#bands, math.floor(i / n * #bands) + 1)]
		end
	end
end

-- Face: the yellow hex with its shaded bands (faceRows: a band number, or { a, b } = a dither row)
hexRows(badge, "Face", XP.faceSize.X, XP.faceSize.Y, XP.facePos.X, XP.facePos.Y, XP.faceBands[2], 5, function(i)
	local spec = XP.faceRows[i + 1]
	if type(spec) == "table" then
		return function(col)
			return XP.faceBands[(col + i) % 2 == 0 and spec[1] or spec[2]]
		end
	end
	return nil
end)
for _, row in ipairs(badge.Face:GetChildren()) do
	local i = tonumber(row.Name:match("^r(%d+)$"))
	if i then
		row.BackgroundColor3 = XP.faceBands[XP.faceRows[i + 1]]
	end
end

local level = badge:FindFirstChild("Level")
if level then
	level.ZIndex = 20
end
return "Badge layers built: " .. #badge:GetDescendants() .. " instances"
