-- build_fiahud_vines.luau
-- Grows the vines of StarterGui.FIAHUD.Root.Vines (ZIndex 10: above the dark brown background, below the hotbar slots, selector and arrow; never blocks input): eight vines
-- along both edges of the HUD, each a stem of 4 px blocks with leaf sprites attached alternately. The left and right sides
-- use different routes and seeds, so they differ. Same algorithm and seeds as the Figma file. Colours: HudTheme leaf*.
-- Run on the Edit datamodel with the Studio MCP after build_fiahud.luau. Skips an existing Vines unless FORCE = true.
local FORCE = false

local T = require(game.ReplicatedStorage.Modules.Config.HudTheme:Clone())
local C, H = T.colors, T.hud
local gui = game.StarterGui:FindFirstChild("FIAHUD")
assert(gui, "build_fiahud.luau has not been run")
local root = gui.Root
local existing = root:FindFirstChild("Vines")
if existing then
	if not FORCE then
		return "Vines already exist (FORCE to regrow)"
	end
	existing:Destroy()
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
	f.Active = false
	f.Parent = parent
	return f
end

local LEAVES = {
	{ "..ddd.", ".dmmld", "dmmlmd", ".dmmd.", "..dd.." },
	{ ".dd.", "dmld", "dmmd", ".dd." },
	{ "..ddd..", ".dmmlmd", "dmmllmd", ".dmmmd.", "..ddd.." },
	{ "dd..", ".dm.", ".dmd", "..dd" },
	{ ".ddd.", "dmmmd", "dmlmd", ".dmd.", "..d.." },
}
local PALS = {
	{ m = C.leafFill, d = C.leafDark, l = C.leafLight },
	{ m = C.leafLight, d = C.leafFill, l = C.leafLight },
	{ m = C.leafFill, d = C.leafDark, l = C.leafFill },
}
local function rev(m)
	local r = {}
	for i, row in ipairs(m) do
		r[i] = row:reverse()
	end
	return r
end
local function flip(m)
	local r = {}
	for i = #m, 1, -1 do
		table.insert(r, m[i])
	end
	return r
end

local function grow(parent, name, pts, seed, dy)
	local s = seed
	local function rnd()
		s = (s * 1664525 + 1013904223) % 4294967296
		return s / 4294967296
	end
	local g = frame(parent, name, 0, dy or 0, H.size.X, H.size.Y, nil)
	local stem = frame(g, "Stem", 0, 0, H.size.X, H.size.Y, nil)
	local leaves = frame(g, "Leaves", 0, 0, H.size.X, H.size.Y, nil)
	local cells = {}
	for i = 1, #pts - 1 do
		local x, y = math.floor(pts[i][1] / 4 + 0.5) * 4, math.floor(pts[i][2] / 4 + 0.5) * 4
		local tx, ty = math.floor(pts[i + 1][1] / 4 + 0.5) * 4, math.floor(pts[i + 1][2] / 4 + 0.5) * 4
		local guard = 0
		while (x ~= tx or y ~= ty) and guard < 200 do
			guard += 1
			local dx, dyy = tx - x, ty - y
			local mx = math.abs(dx) > math.abs(dyy)
			if rnd() < 0.22 then
				mx = not mx
			end
			if mx and dx == 0 then
				mx = false
			end
			if not mx and dyy == 0 then
				mx = true
			end
			if mx then
				x += (dx > 0 and 4 or -4)
			else
				y += (dyy > 0 and 4 or -4)
			end
			table.insert(cells, { x, y, mx })
		end
	end
	for i, c in ipairs(cells) do
		frame(stem, "s", c[1], c[2], 4, 4, (i % 3 == 2) and C.leafFill or C.leafDark)
	end
	local side = rnd() < 0.5 and 1 or -1
	local i = 3
	while i <= #cells do
		local c = cells[i]
		local base = LEAVES[math.floor(rnd() * #LEAVES) + 1]
		local m = base
		if rnd() < 0.5 then
			m = rev(m)
		end
		if rnd() < 0.5 then
			m = flip(m)
		end
		local px = rnd() < 0.5 and 3 or 4
		local w, h = #m[1] * px, #m * px
		local pal = PALS[math.floor(rnd() * #PALS) + 1]
		side = -side
		local lx, ly = c[1] + 2 - w / 2, c[2] + 2 - h / 2
		if c[3] then
			ly += side * (h / 2 + 2)
		else
			lx += side * (w / 2 + 2)
		end
		lx, ly = math.floor(lx / px + 0.5) * px, math.floor(ly / px + 0.5) * px
		local leaf = frame(leaves, "Leaf", lx, ly, w, h, nil)
		for r, row in ipairs(m) do
			local a = 1
			while a <= #row do
				local ch = row:sub(a, a)
				if ch == "." then
					a += 1
				else
					local b = a
					while b <= #row and row:sub(b, b) == ch do
						b += 1
					end
					frame(leaf, "px", (a - 1) * px, (r - 1) * px, (b - a) * px, px, pal[ch])
					a = b
				end
			end
		end
		i += 2 + math.floor(rnd() * 3)
	end
	return #cells
end

local vines = Instance.new("Frame")
vines.Name = "Vines"
vines.BackgroundTransparency = 1
vines.BorderSizePixel = 0
vines.Active = false
vines.Size = UDim2.fromOffset(H.size.X, H.size.Y)
vines.ZIndex = 10
vines.Parent = root

local n = {}
n.L1 = grow(vines, "Left_Climb", { { 34, 206 }, { 22, 176 }, { 32, 146 }, { 20, 116 }, { 30, 88 }, { 18, 60 } }, 7)
n.L2 = grow(vines, "Left_TrayTop", { { 64, 152 }, { 100, 148 }, { 140, 154 }, { 176, 148 }, { 214, 156 }, { 256, 150 }, { 300, 158 }, { 336, 152 } }, 11, 14)
n.L3 = grow(vines, "Left_RibbonTail", { { 44, 244 }, { 26, 230 }, { 12, 212 }, { 16, 196 } }, 19)
n.L4 = grow(vines, "Left_BadgeSide", { { 410, 150 }, { 392, 160 }, { 372, 152 }, { 350, 160 } }, 31, 14)
n.R1 = grow(vines, "Right_Climb", { { 1056, 196 }, { 1068, 166 }, { 1054, 136 }, { 1066, 104 }, { 1052, 76 }, { 1064, 48 } }, 43)
n.R2 = grow(vines, "Right_TrayTop", { { 1024, 154 }, { 996, 148 }, { 960, 156 }, { 930, 150 }, { 888, 146 }, { 852, 154 } }, 59, 14)
n.R3 = grow(vines, "Right_RibbonTail", { { 1044, 252 }, { 1062, 238 }, { 1072, 218 }, { 1060, 200 } }, 71)
n.R4 = grow(vines, "Right_BadgeSide", { { 680, 152 }, { 704, 146 }, { 728, 156 }, { 752, 150 }, { 776, 158 } }, 83, 14)
return ("Vines grown: %d descendants, stem cells %s"):format(#vines:GetDescendants(), game:GetService("HttpService"):JSONEncode(n))
