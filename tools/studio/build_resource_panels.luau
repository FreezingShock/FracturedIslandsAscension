-- build_resource_panels.luau
-- Turns StarterGui.StatsMenu.Stats.Health and .Mana into the pixel panels from Figma "FIA HUD" (colors, sizes and
-- icons come from ReplicatedStorage.Modules.Config.HudTheme):
--   Stats > Health / Mana (Frame 356 x 96): Outline, Fill, Highlight, Shade, EdgeLight, ValueShadow, Value,
--           Bar (Outline, Track, Fill > Main / Highlight / Shade / EndCap), Icon (heart / pencil, one Frame per pixel run)
-- The old hand-made children (Icon, Label, Progress) are kept but renamed Legacy* and hidden. Stats gets a UIScale
-- (ResourceBarsController shrinks it on narrow screens) and the rows are ordered Health | Stamina | Mana.
-- ResourceBarsController finds a row's Bar and drives Bar.Fill and Value; rows without a Bar (Stamina) keep the old bar.
-- Run on the Edit datamodel with the Studio MCP. Skips a row that already has a Bar unless FORCE = true.
local FORCE = false

local T = require(game.ReplicatedStorage.Modules.Config.HudTheme:Clone()) -- a clone, so a stale require cache never wins
local gui = game.StarterGui:FindFirstChild("StatsMenu")
assert(gui, "StarterGui.StatsMenu is missing")
local stats = gui:FindFirstChild("Stats")
assert(stats, "StatsMenu.Stats is missing")
local font = stats.Health:FindFirstChild("LegacyLabel") and stats.Health.LegacyLabel.FontFace
	or stats.Health.Label.FontFace -- the game's HUD font

local C, P, H = T.colors, T.resourcePanel, T.hud
local BUILT = { "Outline", "Fill", "Highlight", "Shade", "EdgeLight", "ValueShadow", "Value", "Bar", "Icon" }

local function hex(h)
	local n = tonumber(h:sub(2), 16)
	return Color3.fromRGB(bit32.rshift(n, 16) % 256, bit32.rshift(n, 8) % 256, n % 256)
end

local function frame(parent, name, x, y, w, h, color)
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
	f.Parent = parent
	return f
end

-- rectangle with one-pixel notched corners (two overlapping bands)
local function stepBox(parent, name, x, y, w, h, color, c)
	local g = frame(parent, name, x, y, w, h, nil)
	frame(g, "H", c, 0, w - 2 * c, h, color)
	frame(g, "V", 0, c, w, h - 2 * c, color)
	return g
end

local function label(parent, name, color, y)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromOffset(P.size.X, 40)
	l.Position = UDim2.fromOffset(name == "ValueShadow" and 2 or 0, y + (name == "ValueShadow" and 2 or 0))
	l.FontFace = font
	l.TextSize = P.textSize
	l.TextColor3 = color
	l.Text = "0 / 0"
	l.ZIndex = name == "ValueShadow" and 1 or 2
	l.Parent = parent
	return l
end

local function pixelIcon(parent, spec, x, y)
	local cell = spec.cell
	local rows = spec.rows
	local icon = frame(parent, "Icon", x, y, #rows[1] * cell, #rows * cell, nil)
	for r, row in ipairs(rows) do
		local i = 1
		while i <= #row do
			local ch = row:sub(i, i)
			if ch == "." then
				i += 1
			else
				local j = i
				while j <= #row and row:sub(j, j) == ch do
					j += 1
				end
				local v = spec.palette[ch]
				local color = v:sub(1, 1) == "#" and hex(v) or C[v]
				frame(icon, "px", (i - 1) * cell, (r - 1) * cell, (j - i) * cell, cell, color)
				i = j
			end
		end
	end
	return icon
end

local function bar(parent, x, y, track, fill, light, dark, cap)
	local W, Hh = P.barSize.X, P.barSize.Y
	local b = frame(parent, "Bar", x, y, W, Hh, nil)
	frame(b, "Outline", 0, 0, W, Hh, C.barOutline)
	frame(b, "Track", 4, 4, W - 8, Hh - 8, track)
	local f = frame(b, "Fill", 4, 4, W - 8, Hh - 8, nil)
	f.ClipsDescendants = true
	local main = frame(f, "Main", 0, 0, 0, 0, fill)
	main.Size = UDim2.fromScale(1, 1)
	local hi = frame(f, "Highlight", 0, 0, 0, P.topFillPx, light)
	hi.Size = UDim2.new(1, 0, 0, P.topFillPx)
	local sh = frame(f, "Shade", 0, 0, 0, P.shadeFillPx, dark)
	sh.Position = UDim2.new(0, 0, 1, -P.shadeFillPx)
	sh.Size = UDim2.new(1, 0, 0, P.shadeFillPx)
	local ec = frame(f, "EndCap", 0, 0, P.capPx, 0, cap)
	ec.Position = UDim2.new(1, -P.capPx, 0, 0)
	ec.Size = UDim2.new(0, P.capPx, 1, 0)
	return b
end

local function buildRow(row, kind)
	if row:FindFirstChild("Bar") then
		if not FORCE then
			return row.Name .. ": already built (set FORCE = true to rebuild)"
		end
		for _, name in ipairs(BUILT) do
			local child = row:FindFirstChild(name)
			if child then
				child:Destroy()
			end
		end
	end
	-- keep the hand-made children, hidden and renamed so the new Icon does not clash
	for _, name in ipairs({ "Icon", "Label", "Progress" }) do
		local legacy = row:FindFirstChild(name)
		if legacy and legacy:IsA("GuiObject") then
			legacy.Name = "Legacy" .. name
			legacy.Visible = false
		end
	end
	row.AutomaticSize = Enum.AutomaticSize.None
	row.Size = UDim2.fromOffset(P.size.X, P.size.Y)
	row.BackgroundTransparency = 1

	local w, h = P.size.X, P.size.Y
	stepBox(row, "Outline", 0, 0, w, h, C.panelBorder, 4)
	stepBox(row, "Fill", 4, 4, w - 8, h - 8, C.panelFill, 4)
	frame(row, "Highlight", 8, 4, w - 16, 4, C.panelHighlight)
	frame(row, "Shade", 8, h - 8, w - 16, 4, C.panelShadow)
	frame(row, "EdgeLight", w - 8, 12, 4, h - 24, C.panelHighlight).BackgroundTransparency = 0.5
	label(row, "ValueShadow", C.textShadow, P.textY)
	label(row, "Value", C.text, P.textY)
	local barY = P.barY
	if kind == "health" then
		bar(row, 56, barY, C.hpTrack, C.hpFill, C.hpLight, C.hpDark, C.hpCap)
		local s = T.icons.heart
		pixelIcon(row, s, P.iconMargin, barY + P.barSize.Y / 2 - (#s.rows * s.cell) / 2)
	else
		local barX = 24
		bar(row, barX, barY, C.manaTrack, C.manaFill, C.manaLight, C.manaDark, C.manaCap)
		local s = T.icons.pencil
		pixelIcon(row, s, barX + P.barSize.X + P.iconGap, barY + P.barSize.Y / 2 - (#s.rows * s.cell) / 2)
	end
	return row.Name .. ": built"
end

local out = {}
local legacyRoot = gui:FindFirstChild("HudRoot") -- an earlier version of this builder made a separate HudRoot
if legacyRoot then
	legacyRoot:Destroy()
	table.insert(out, "removed old HudRoot")
end
table.insert(out, buildRow(stats.Health, "health"))
table.insert(out, buildRow(stats.Mana, "mana"))
for name, order in pairs(H.rowOrder) do
	local row = stats:FindFirstChild(name)
	if row then
		row.LayoutOrder = order
	end
end
if not stats:FindFirstChildOfClass("UIScale") then
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = stats
end
return table.concat(out, "; ")
