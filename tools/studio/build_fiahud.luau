-- build_fiahud.luau
-- Builds the pixel HUD from the Figma file "FIA HUD - Health, Mana, XP, Hotbar" (all numbers and colours come from
-- ReplicatedStorage.Modules.Config.HudTheme):
--   StarterGui.FIAHUD (ScreenGui, ResetOnSpawn off)
--     Root (Frame 1088 x 276, flush with the screen bottom, UIScale)   ZIndex
--       Back     ribbons + HotbarTray (brown posts = the slot holders)                1
--       Strip    CanvasGroup: Ledge, Left/Right (track + Segments > Segment1..8 > Fill)   2   (Stamina)
--       (Strip, Wings, Stats, Badge and SelectorArrow are CanvasGroups: they fade out while a menu is open)
--       Wings    ribbon tabs behind the badge                                         3
--       Stats    CanvasGroup: Health / Mana panels (Bar.Fill, Value, ValueShadow, Icon) 4
--       Badge    hexagon + Level (Nexus Level)                                        5
--       Hotbar   HotbarBB > HotbarFrames (UIListLayout; InventoryController fills it)  6
--       Selector lavender ring that InventoryController slides between slots          7
--       SelectorArrow  green V under the badge tip                                    8
--       Name     the held-item name group, moved from StatsMenu if it is still there  9
--       (Vines is added by build_fiahud_vines.luau)                                   10
--   ReplicatedStorage.SlotTemplate: the pixel item slot (the previous template is kept as SlotTemplate_Legacy).
--     Children InventoryController and SlotLook use: Outline, Face, Highlight, Shade, Rarity (Bar, CL, CR), ItemImage,
--     ToolName, StackNum, SlotNum, RarityLabel (hidden), Swap, Select.
-- Run on the Edit datamodel with the Studio MCP (stop Play first). Skips what exists unless FORCE = true.
-- To remove the old StatsMenu once FIAHUD works: set REMOVE_STATSMENU = true (its Name group is moved first).
local FORCE = false
local REMOVE_STATSMENU = false

local RS = game.ReplicatedStorage
local T = require(RS.Modules.Config.HudTheme:Clone()) -- a clone, so a stale require cache never wins
local C, P, H, TR, SL, ST, BD, NM = T.colors, T.resourcePanel, T.hud, T.tray, T.slot, T.strip, T.badge, T.name
local FONT = Font.new(T.font, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local out = {}

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

local function label(parent, name, color, x, y, w, h, size, align)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = color
	l.Text = ""
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = parent
	return l
end

local function stroke(parent, thickness)
	local s = Instance.new("UIStroke")
	s.Color = C.textStroke
	s.Thickness = thickness
	s.Parent = parent
	return s
end

-- a shape made of vertical bands: bands = { {y0, y1, edge} }, edge = how far the open side is cut in; flip mirrors it
local function bandShape(parent, name, x, y, w, h, bands, flip, withHighlight)
	local g = frame(parent, name, x, y, w, h, nil)
	local outline = frame(g, "Outline", 0, 0, w, h, nil)
	local fill = frame(g, "Fill", 0, 0, w, h, nil)
	for i, b in ipairs(bands) do
		local y0, y1, edge = b[1], b[2], b[3]
		local ox = flip and -4 or edge - 4
		frame(outline, "O" .. i, ox, y0 - 4, w - edge + 8, (y1 - y0) + 8, C.panelBorder)
		frame(fill, "F" .. i, flip and 0 or edge, y0, w - edge, y1 - y0, C.panelFill)
	end
	if withHighlight then
		frame(g, "Highlight", flip and 16 or 4, 4, 44, 4, C.panelHighlight)
	end
	return g
end

local function hexRows(parent, name, w, h, x, y, color)
	local px, rows, cx = 4, h / 4, w / 2
	local holder = frame(parent, name, x, y, w, h, nil)
	for r = 0, rows - 1 do
		local yc = (r + 0.5) * px
		local a = yc < h / 4 and cx * (yc / (h / 4)) or (yc > 3 * h / 4 and cx * ((h - yc) / (h / 4)) or cx)
		local hw = math.max(px, math.floor(a / px + 0.5) * px)
		frame(holder, "r" .. r, cx - hw, r * px, 2 * hw, px, color)
	end
	return holder
end

local function pixelIcon(parent, spec, x, y)
	local cell, rows = spec.cell, spec.rows
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
				frame(icon, "px", (i - 1) * cell, (r - 1) * cell, (j - i) * cell, cell, v:sub(1, 1) == "#" and hex(v) or C[v])
				i = j
			end
		end
	end
	return icon
end

-- ===================== SLOT TEMPLATE =====================
local function buildSlotTemplate()
	local old = RS:FindFirstChild("SlotTemplate")
	if old then
		if old:FindFirstChild("Face") then
			if not FORCE then
				return "SlotTemplate: already pixel (FORCE to rebuild)"
			end
			old:Destroy()
		elseif not RS:FindFirstChild("SlotTemplate_Legacy") then
			old.Name = "SlotTemplate_Legacy"
		else
			old:Destroy()
		end
	end
	local size = SL.size
	local root = frame(RS, "SlotTemplate", 0, 0, size, size, nil)
	root.Size = UDim2.fromOffset(size, size)
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = root

	local function holder(name, inset, color, z)
		local g = Instance.new("Frame")
		g.Name = name
		g.BackgroundTransparency = 1
		g.BorderSizePixel = 0
		g.Position = UDim2.fromOffset(inset, inset)
		g.Size = UDim2.new(1, -2 * inset, 1, -2 * inset)
		g.ZIndex = z
		g.Parent = root
		local function band(n, px, py, sx, sy, ox, oy)
			local b = Instance.new("Frame")
			b.Name = n
			b.BorderSizePixel = 0
			b.BackgroundColor3 = color
			b.Position = UDim2.new(0, px, 0, py)
			b.Size = UDim2.new(sx, ox, sy, oy)
			b.ZIndex = z
			b.Parent = g
		end
		band("H", SL.outline, 0, 1, 1, -2 * SL.outline, 0)
		band("V", 0, SL.outline, 1, 1, 0, -2 * SL.outline)
		return g
	end
	holder("Outline", 0, C.slotBorder, 1)
	holder("Face", SL.outline, C.slotFill, 2)

	local function strip(name, px, py, color, z)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.Position = px
		f.Size = py
		f.ZIndex = z
		f.Parent = root
		return f
	end
	strip("Highlight", UDim2.new(0, 8, 0, 4), UDim2.new(1, -16, 0, 4), C.slotHighlight, 3)
	strip("Shade", UDim2.new(0, 8, 1, -8), UDim2.new(1, -16, 0, 4), C.slotShadow, 3)

	local rarity = Instance.new("Frame")
	rarity.Name = "Rarity"
	rarity.BackgroundTransparency = 1
	rarity.Size = UDim2.fromScale(1, 1)
	rarity.ZIndex = 4
	rarity.Visible = false
	rarity.Parent = root
	local rh = SL.rarityBarHeight
	for _, spec in ipairs({
		{ "Bar", UDim2.new(0, 12, 1, -18), UDim2.new(1, -24, 0, rh) },
		{ "CL", UDim2.new(0, 8, 1, -22), UDim2.fromOffset(4, 4) },
		{ "CR", UDim2.new(1, -12, 1, -22), UDim2.fromOffset(4, 4) },
	}) do
		local b = Instance.new("Frame")
		b.Name = spec[1]
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.Position = spec[2]
		b.Size = spec[3]
		b.ZIndex = 4
		b.Parent = rarity
	end

	local img = Instance.new("ImageLabel")
	img.Name = "ItemImage"
	img.BackgroundTransparency = 1
	img.AnchorPoint = Vector2.new(0.5, 0)
	img.Position = UDim2.fromScale(0.5, 0.1)
	img.Size = UDim2.fromScale(0.66, 0.66)
	img.ScaleType = Enum.ScaleType.Fit
	img.ResampleMode = Enum.ResamplerMode.Pixelated
	img.ZIndex = 5
	img.Visible = false
	local ir = Instance.new("UIAspectRatioConstraint")
	ir.Parent = img
	img.Parent = root

	local tn = label(root, "ToolName", C.text, 0, 0, 0, 0, 14)
	tn.Size = UDim2.fromScale(1, 1)
	tn.TextWrapped = true
	tn.TextYAlignment = Enum.TextYAlignment.Center
	tn.ZIndex = 5
	stroke(tn, 2)
	local sn = label(root, "StackNum", C.text, 0, 0, 38, 22, 16, Enum.TextXAlignment.Right)
	sn.Position = UDim2.new(1, -44, 1, -46)
	sn.TextYAlignment = Enum.TextYAlignment.Center
	sn.ZIndex = 6
	stroke(sn, 2)
	local num = label(root, "SlotNum", C.text, 8, 6, 24, 20, 16, Enum.TextXAlignment.Left)
	num.TextYAlignment = Enum.TextYAlignment.Top
	num.ZIndex = 6
	stroke(num, 2)
	local rl = label(root, "RarityLabel", C.text, 0, 0, 0, 0, 12)
	rl.Visible = false
	rl.RichText = true
	local swap = label(root, "Swap", C.text, 0, 0, 0, 0, 14)
	swap.Size = UDim2.fromScale(1, 1)
	swap.ZIndex = 7
	local sel = Instance.new("ImageButton")
	sel.Name = "Select"
	sel.BackgroundTransparency = 1
	sel.BorderSizePixel = 0
	sel.Image = ""
	sel.Size = UDim2.fromScale(1, 1)
	sel.ZIndex = 8
	sel.Parent = root
	return "SlotTemplate: built"
end

-- ===================== FIAHUD =====================
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

local function panel(parent, name, pos, kind)
	local w, h = P.size.X, P.size.Y
	local p = frame(parent, name, pos.X, pos.Y, w, h, nil)
	stepBox(p, "Outline", 0, 0, w, h, C.panelBorder, 4)
	stepBox(p, "Fill", 4, 4, w - 8, h - 8, C.panelFill, 4)
	frame(p, "Highlight", 8, 4, w - 16, 4, C.panelHighlight)
	frame(p, "Shade", 8, h - 8, w - 16, 4, C.panelShadow)
	frame(p, "EdgeLight", w - 8, 12, 4, h - 24, C.panelHighlight).BackgroundTransparency = 0.5
	for _, n in ipairs({ "ValueShadow", "Value" }) do
		local shadow = n == "ValueShadow"
		local l = label(p, n, shadow and C.textShadow or C.text, shadow and 2 or 0, P.textY + (shadow and 2 or 0), w, 40, P.textSize)
		l.Text = "0 / 0"
		l.ZIndex = shadow and 1 or 2
	end
	local barY = P.barY
	if kind == "health" then
		bar(p, 56, barY, C.hpTrack, C.hpFill, C.hpLight, C.hpDark, C.hpCap)
		local s = T.icons.heart
		pixelIcon(p, s, P.iconMargin, barY + P.barSize.Y / 2 - (#s.rows * s.cell) / 2)
	else
		local barX = 24
		bar(p, barX, barY, C.manaTrack, C.manaFill, C.manaLight, C.manaDark, C.manaCap)
		local s = T.icons.pencil
		pixelIcon(p, s, barX + P.barSize.X + P.iconGap, barY + P.barSize.Y / 2 - (#s.rows * s.cell) / 2)
	end
	return p
end

local function segment(parent, i)
	local sw, sh = ST.segmentSize.X, ST.segmentSize.Y
	local seg = frame(parent, "Segment" .. i, (i - 1) * (sw + ST.gap), 0, sw, sh, nil)
	local function art(holder, base, core, top)
		frame(holder, "Base", 0, 0, sw, sh, base)
		frame(holder, "Core", 4, 4, sw - 8, sh - 8, core)
		frame(holder, "Shade", 0, sh - 4, sw, 4, C.xpFullDark)
		local t = frame(holder, "Top", 0, 0, sw, 4, top)
		t.BackgroundTransparency = 0.65
	end
	art(frame(seg, "Empty", 0, 0, sw, sh, nil), C.xpEmpty, C.xpEmptyCore, C.xpEmptyCore)
	local fill = frame(seg, "Fill", 0, 0, sw, sh, nil)
	fill.ClipsDescendants = true
	fill.ZIndex = 2
	art(fill, C.xpFull, C.xpCore, C.xpCore)
	return seg
end

local function track(parent, name, x, segX)
	local t = frame(parent, name, x, ST.trackY, ST.trackSize.X, ST.trackSize.Y, nil)
	stepBox(t, "Outline", 0, 0, ST.trackSize.X, ST.trackSize.Y, C.panelBorder, 4)
	stepBox(t, "Fill", 4, 4, ST.trackSize.X - 8, ST.trackSize.Y - 8, C.panelTrack, 4)
	frame(t, "TopShade", 8, 4, ST.trackSize.X - 16, 4, C.panelShadow)
	local segments = frame(t, "Segments", segX, ST.segmentsY, ST.segments * (ST.segmentSize.X + ST.gap) - ST.gap, ST.segmentSize.Y, nil)
	for i = 1, ST.segments do
		segment(segments, i)
	end
	return t
end

local function z(inst, v)
	inst.ZIndex = v
	return inst
end

-- a CanvasGroup the controller can fade out while a menu is open
local function group(parent, name, x, y, w, h, zindex)
	local g = Instance.new("CanvasGroup")
	g.Name = name
	g.BackgroundTransparency = 1
	g.BorderSizePixel = 0
	g.Position = UDim2.fromOffset(x, y)
	g.Size = UDim2.fromOffset(w, h)
	g.ZIndex = zindex
	g.Parent = parent
	return g
end

local function buildHud()
	local StarterGui = game.StarterGui
	local oldGui = StarterGui:FindFirstChild("FIAHUD")
	if oldGui then
		if not FORCE then
			return "FIAHUD: already exists (FORCE to rebuild)"
		end
		oldGui:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "FIAHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets -- keeps the HUD clear of phone notches and home bars
	gui.DisplayOrder = 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = frame(gui, "Root", 0, 0, H.size.X, H.size.Y, nil)
	-- flush with the bottom of the screen at any UIScale: anchor on the tray's bottom edge, then sit that point at the bottom
	root.AnchorPoint = Vector2.new(0.5, (TR.pos.Y + TR.size.Y) / H.size.Y)
	root.Position = UDim2.new(0.5, 0, 1, 0)
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = root

	-- Back: ribbons + tray + posts
	local back = z(frame(root, "Back", 0, 0, H.size.X, H.size.Y, nil), 1)
	local RL = { { 0, 16, 0 }, { 16, 28, 8 }, { 28, 40, 16 }, { 40, 56, 24 }, { 56, 68, 16 }, { 68, 80, 8 }, { 80, 96, 0 } }
	bandShape(back, "RibbonLeft", TR.ribbonLeftX, TR.ribbonY, TR.ribbonSize.X, TR.ribbonSize.Y, RL, false, true)
	bandShape(back, "RibbonRight", TR.ribbonRightX, TR.ribbonY, TR.ribbonSize.X, TR.ribbonSize.Y, RL, true, true)
	local tray = frame(back, "HotbarTray", TR.pos.X, TR.pos.Y, TR.size.X, TR.size.Y, nil)
	stepBox(tray, "Outline", 0, 0, TR.size.X, TR.size.Y, C.panelBorder, 4)
	stepBox(tray, "Fill", 4, 4, TR.size.X - 8, TR.size.Y - 8, C.panelFill, 4)
	frame(tray, "Highlight", 8, 4, TR.size.X - 16, 4, C.panelHighlight)
	frame(tray, "Shade", 8, TR.size.Y - 8, TR.size.X - 16, 4, C.panelShadow)
	local pitch = SL.size + SL.gap
	for i = 0, SL.count do
		local px = TR.postInset + i * pitch
		local ends = i == 0 or i == SL.count
		frame(tray, "Post" .. (i + 1), px, 8, TR.postWidth, TR.size.Y - 16, C.postFill)
		frame(tray, "PostCap" .. (i + 1), ends and px or px - 4, 8, ends and TR.postWidth or TR.postCap.X, TR.postCap.Y, C.postCap)
	end

	-- Strip (Stamina)
	local strip = Instance.new("CanvasGroup")
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.BorderSizePixel = 0
	strip.Size = UDim2.fromOffset(H.size.X, H.size.Y)
	strip.ZIndex = 2
	strip.Parent = root
	local led = frame(strip, "Ledge", ST.ledgePos.X, ST.ledgePos.Y, ST.ledgeSize.X, ST.ledgeSize.Y, nil)
	frame(led, "Edge", 0, 0, ST.ledgeSize.X, ST.ledgeSize.Y, C.panelBorder)
	frame(led, "Fill", 0, 4, ST.ledgeSize.X, ST.ledgeSize.Y - 8, C.panelTrack)
	frame(led, "Top", 0, 4, ST.ledgeSize.X, 4, C.panelShadow)
	track(strip, "Left", ST.leftX, ST.leftSegmentsX)
	track(strip, "Right", ST.rightX, ST.rightSegmentsX)

	-- Wings (ribbon tabs behind the badge)
	local wings = group(root, "Wings", 0, 0, H.size.X, H.size.Y, 3)
	local WB = { { 0, 8, 0 }, { 8, 16, 8 }, { 16, 24, 16 }, { 24, 32, 8 }, { 32, 40, 0 } }
	bandShape(wings, "WingLeft", BD.wingLeftX, BD.wingY, BD.wingSize.X, BD.wingSize.Y, WB, false, true)
	bandShape(wings, "WingRight", BD.wingRightX, BD.wingY, BD.wingSize.X, BD.wingSize.Y, WB, true, true)

	-- Stats (Health / Mana)
	local stats = Instance.new("CanvasGroup")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.BorderSizePixel = 0
	stats.Size = UDim2.fromOffset(H.size.X, H.size.Y)
	stats.ZIndex = 4
	stats.Parent = root
	panel(stats, "Health", H.healthPos, "health")
	panel(stats, "Mana", H.manaPos, "mana")

	-- Badge
	local badge = group(root, "Badge", BD.pos.X, BD.pos.Y, BD.size.X, BD.size.Y, 5)
	hexRows(badge, "Outline", 112, 128, 0, 0, C.badgeBorder)
	hexRows(badge, "Rim", 104, 120, 4, 4, C.badgeWhite)
	hexRows(badge, "Face", 104, 112, 4, 12, C.badgeFill)
	hexRows(badge, "RingOuter", 80, 88, 16, 20, C.badgeRing)
	hexRows(badge, "RingInner", 72, 80, 20, 24, C.badgeFill)
	local level = label(badge, "Level", C.text, 0, 64 - 20, BD.size.X, 40, BD.textSize)
	level.Text = "0"
	level.TextYAlignment = Enum.TextYAlignment.Center
	level.ZIndex = 20
	stroke(level, 3)

	-- Hotbar
	local hotbarW = SL.count * SL.size + (SL.count - 1) * SL.gap
	local hotbar = z(frame(root, "Hotbar", SL.hotbarPos.X, SL.hotbarPos.Y, hotbarW, SL.size, nil), 6)
	local hbb = frame(hotbar, "HotbarBB", 0, 0, hotbarW, SL.size, nil)
	local frames = frame(hbb, "HotbarFrames", 0, 0, hotbarW, SL.size, nil)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, SL.gap)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = frames

	-- Selector ring
	local ring = SL.size + 2 * SL.selector.pad
	local t = SL.selector.thickness
	local selector = z(frame(root, "Selector", SL.hotbarPos.X - SL.selector.pad, SL.hotbarPos.Y - SL.selector.pad, ring, ring, nil), 7)
	local rc = C[SL.selector.colorKey]
	frame(selector, "Top", t, 0, ring - 2 * t, t, rc)
	frame(selector, "Bottom", t, ring - t, ring - 2 * t, t, rc)
	frame(selector, "Left", 0, t, t, ring - 2 * t, rc)
	frame(selector, "Right", ring - t, t, t, ring - 2 * t, rc)

	-- Selector arrow (under the badge tip)
	local arrow = group(root, "SelectorArrow", BD.arrowPos.X, BD.arrowPos.Y, 48, 28, 8)
	local rows = { { 0, 48 }, { 4, 40 }, { 8, 32 }, { 12, 24 }, { 16, 16 }, { 20, 8 } }
	for i, r in ipairs(rows) do
		frame(arrow, "O" .. i, r[1] - 4, (i - 1) * 4, r[2] + 8, 4, C.leafDark)
	end
	frame(arrow, "OTip", 16, 24, 16, 4, C.leafDark)
	for i, r in ipairs(rows) do
		frame(arrow, "F" .. i, r[1], (i - 1) * 4, r[2], 4, C.leafFill)
	end
	frame(arrow, "Highlight", 8, 0, 32, 4, C.leafLight).BackgroundTransparency = 0.4
	frame(arrow, "Dot", 20, 4, 8, 8, C.xpCore)

	-- Name (held-item label): move the hand-made group from StatsMenu if it is still there
	local old = StarterGui:FindFirstChild("StatsMenu")
	local nameGroup = old and old:FindFirstChild("Name")
	if nameGroup then
		nameGroup.Parent = root
	else
		nameGroup = Instance.new("CanvasGroup")
		nameGroup.Name = "Name"
		nameGroup.BackgroundTransparency = 1
		nameGroup.AutomaticSize = Enum.AutomaticSize.XY
		local l = label(nameGroup, "Label", C.text, 0, 0, 0, 50, 31)
		l.AutomaticSize = Enum.AutomaticSize.X
		stroke(l, 2)
		nameGroup.Parent = root
	end
	nameGroup.AnchorPoint = Vector2.new(0.5, 0)
	nameGroup.Position = UDim2.fromOffset(NM.pos.X, NM.pos.Y)
	nameGroup.ZIndex = 9

	gui.Parent = StarterGui
	return "FIAHUD: built"
end

table.insert(out, buildSlotTemplate())
table.insert(out, buildHud())
if REMOVE_STATSMENU then
	local old = game.StarterGui:FindFirstChild("StatsMenu")
	if old then
		old:Destroy()
		table.insert(out, "StatsMenu removed")
	end
end
return table.concat(out, "; ")
