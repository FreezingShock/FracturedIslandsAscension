--[[
	DropEdges (ModuleScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts   (required by ItemDropRenderer)

	Gives a dropped flat sprite its THICK, coloured edge, like a Minecraft dropped item. The server's drop is a thin invisible slab
	with the icon on both faces (ItemTools.newSpriteHandle); this adds, on THIS client only and only for nearby drops, small
	strips along the outer pixels of the icon, each in the colour of the pixels it covers (ItemSpriteData, generated offline by
	tools/gen_item_sprites.py from the item icons and the Statistics icons). Nothing here replicates.

	Which picture's edge: the drop's attribute SpriteImage (mob loot: stat / coin icons), else the item def's icon (ItemId). An
	icon with no edge data yet gets a plain frame in the drop's DropColor, until tools/fetch_stat_icons.py has fetched it.

	  DropEdges.attach(model)   build the strips for every sprite Handle in the model (the first ItemModels.SPRITE_EDGE_LAYERS
	                            stack layers)
	  DropEdges.follow(model)   a drop that is still falling: put every strip back on its Handle (call each frame)
	  DropEdges.detach(model)   remove them again (the drop moved out of range, or settled and must be rebuilt in its new pose)

	The strips are children of the drop's Model, so a settled drop's PivotTo / ScaleTo and the merge / pickup flights carry them.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Items = require(Modules:WaitForChild("Items")) :: any
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
local ItemModels = require(Modules:WaitForChild("ItemModels")) :: any
local SpriteData = require(Modules:WaitForChild("ItemSpriteData")) :: any

local DropEdges = {}

local EDGE_TAG = "DropEdge"
local INSET = 0.004 -- studs the strips stop short of each face, so the icon on the face never fights them

-- a plain frame for an icon without edge data (pixels counted from the top-left: top, bottom, left, right)
local FRAME = { n = 16, s = { { 0, 0, 16, 1 }, { 0, 15, 16, 2 }, { 0, 1, 14, 3 }, { 15, 1, 14, 4 } } }

local built: { [Model]: { { part: BasePart, handle: BasePart, rel: CFrame } } } = {}

local function colorOf(hex: number, tint: Color3?): Color3
	local color = Color3.fromRGB(math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256)
	if tint then
		color = Color3.new(color.R * tint.R, color.G * tint.G, color.B * tint.B)
	end
	return color
end

local function hexColor(value: any): Color3?
	if type(value) ~= "string" then
		return nil
	end
	local ok, color = pcall(Color3.fromHex, value)
	return ok and color or nil
end

local function buildFor(model: Model, handle: BasePart, sprite: any, tint: Color3?, fallback: Color3?, list: { any })
	local size = handle.Size.X
	local thickness = handle.Size.Z - INSET * 2
	local pixel = size / sprite.n
	local half = size / 2 -- the picture on the Front face runs along local -X: pixel x -> local X = half - x * pixel
	for _, strip in ipairs(sprite.s) do
		local x, y, len, dir = strip[1], strip[2], strip[3], strip[4]
		local sizeVec, centre
		if dir <= 2 then -- a run along x on the top / bottom edge
			sizeVec = Vector3.new(len * pixel, pixel, thickness)
			centre = Vector3.new(half - (x + len / 2) * pixel, half - (y + 0.5) * pixel, 0)
		else -- a run along y on the left / right edge
			sizeVec = Vector3.new(pixel, len * pixel, thickness)
			centre = Vector3.new(half - (x + 0.5) * pixel, half - (y + len / 2) * pixel, 0)
		end
		local part = Instance.new("Part")
		part.Name = "Edge"
		part.Size = sizeVec
		part.Color = strip[5] and colorOf(strip[5], tint) or fallback or Color3.new(1, 1, 1)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		local rel = CFrame.new(centre)
		part.CFrame = handle.CFrame * rel
		part:AddTag(EDGE_TAG)
		part.Parent = model
		table.insert(list, { part = part, handle = handle, rel = rel })
	end
end

function DropEdges.attach(model: Model)
	if built[model] then
		return
	end
	local list = {}
	built[model] = list
	model.Destroying:Once(function()
		built[model] = nil
	end)
	local image = model:GetAttribute("SpriteImage")
	local tint = hexColor(model:GetAttribute("SpriteTint"))
	if type(image) ~= "string" or image == "" then
		local itemId = model:GetAttribute("ItemId")
		local def = itemId and Items.get(itemId)
		if def then
			local spec = ItemIcons.resolve(def)
			image = spec.image
			tint = tint or spec.tint
		end
	end
	local sprite = type(image) == "string" and SpriteData[image] or nil
	local fallback = hexColor(model:GetAttribute("DropColor"))
	if not sprite and not fallback then
		return -- nothing known about this drop: stays a plain sprite
	end
	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name == "Handle" and child:FindFirstChild("SpriteFront") then
			local layer = child:GetAttribute("StackLayer") or 1
			if layer <= ItemModels.SPRITE_EDGE_LAYERS then
				buildFor(model, child, sprite or FRAME, sprite and tint or nil, fallback, list)
			end
		end
	end
end

function DropEdges.follow(model: Model)
	local list = built[model]
	if not list then
		return
	end
	for _, entry in ipairs(list) do
		if entry.handle.Parent then
			entry.part.CFrame = entry.handle.CFrame * entry.rel
		end
	end
end

function DropEdges.detach(model: Model)
	local list = built[model]
	if not list then
		return
	end
	built[model] = nil
	for _, entry in ipairs(list) do
		entry.part:Destroy()
	end
end

function DropEdges.has(model: Model): boolean
	return built[model] ~= nil
end

return DropEdges
