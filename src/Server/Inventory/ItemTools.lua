--[[
	ItemTools (ModuleScript, Server)
	Place inside: ServerScriptService

	Every inventory item is a Tool in the player's Backpack. Instead of
	hand-building each Tool in ServerStorage, this builds them from the item
	definitions (Modules/Items/Defs) on demand. A Tool you place in
	ServerStorage yourself (with a real Handle/model) always wins.

	  ItemTools.ensure(toolName) -> Tool or nil   (finds or creates)
	  ItemTools.ensureAll()      -> number created
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Items = require(Modules:WaitForChild("Items")) :: any
local ItemIcons = require(Modules:WaitForChild("ItemIcons")) :: any
local ItemModels = require(Modules:WaitForChild("ItemModels")) :: any

local ItemTools = {}

local function stamp(tool: Tool, def: any)
	tool:SetAttribute("Rarity", def.rarity or 0)
	tool:SetAttribute("ItemId", def.id)
	if type(def.custom) == "string" then
		tool:SetAttribute("Custom", def.custom) -- reserved: per-item customization data
	end
	if def.category == "weapon" then
		tool:SetAttribute("WeaponId", def.id) -- WeaponInit / WeaponManager key
	end
end

local function applyGrip(tool: Tool, grip: any)
	if not grip then
		return
	end
	tool.GripPos = grip.pos or tool.GripPos
	tool.GripForward = grip.forward or tool.GripForward
	tool.GripUp = grip.up or tool.GripUp
	tool.GripRight = grip.right or tool.GripRight
end

--- Flat sprite Handle: SPRITE_PIXELS thin, the item icon on both faces (invisible part, visible SurfaceGuis).
local function addSpriteHandle(tool: Tool, def: any)
	local size = ItemModels.SPRITE_SIZE
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(size, size, size / ItemModels.SPRITE_PIXELS)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CastShadow = false
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Sprite" .. face.Name
		gui.Face = face
		gui.LightInfluence = 0
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 80
		gui.Parent = handle
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.ScaleType = Enum.ScaleType.Fit
		if face == Enum.NormalId.Back then
			-- a SurfaceGui reads un-mirrored from behind, so a spinning sprite would "flip" at 180 degrees;
			-- mirror the back image so it matches what the other side of a flat sprite really looks like
			img.Size = UDim2.fromScale(-1, 1)
			img.Position = UDim2.fromScale(1, 0)
		end
		ItemIcons.apply(img, def)
		img.Parent = gui
	end
	handle.Parent = tool
	applyGrip(tool, ItemModels.SPRITE_GRIP)
end

--- Real model Handle from ServerStorage.ItemModels. Returns false when the template is missing.
local function addModelHandle(tool: Tool, entry: any): boolean
	local folder = ServerStorage:FindFirstChild("ItemModels")
	local template = folder and folder:FindFirstChild(entry.template)
	if not template then
		warn("[ItemTools] missing model template ServerStorage.ItemModels." .. tostring(entry.template))
		return false
	end
	local clone = template:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- free-asset models can carry scripts
		end
	end
	if clone:IsA("Model") and entry.scale and entry.scale ~= 1 then
		clone:ScaleTo(entry.scale)
	end
	local handle = if clone:IsA("BasePart") then clone else clone:FindFirstChild("Handle", true)
	if not (handle and handle:IsA("BasePart")) then
		warn("[ItemTools] template has no Handle part: " .. tostring(entry.template))
		clone:Destroy()
		return false
	end
	for _, part in ipairs(clone:IsA("BasePart") and { clone } or clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
			if part ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = part
				weld.Parent = part
			end
		end
	end
	for _, part in ipairs(clone:IsA("BasePart") and { clone } or clone:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Parent = tool
		end
	end
	if clone.Parent == nil and clone ~= handle then
		clone:Destroy()
	end
	applyGrip(tool, entry.grip)
	return true
end

local function build(def: any): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.toolName
	tool.CanBeDropped = false -- drops go through ItemDrops (inventory UI / Q key), not Roblox's backspace drop
	tool.RequiresHandle = true
	tool.ToolTip = def.displayName
	stamp(tool, def)
	local entry = ItemModels.get(def)
	if not (entry and addModelHandle(tool, entry)) then
		addSpriteHandle(tool, def)
	end
	tool.Parent = ServerStorage
	return tool
end

function ItemTools.ensure(toolName: string): Tool?
	local existing = ServerStorage:FindFirstChild(toolName)
	local def = Items.getByToolName(toolName)
	if existing and existing:IsA("Tool") then
		if def then
			stamp(existing, def)
		end
		return existing
	end
	if def then
		return build(def)
	end
	return nil
end

function ItemTools.ensureAll(): number
	local created = 0
	for _, def in pairs(Items.Items) do
		if def.toolName and def.toolName ~= "" then
			local before = ServerStorage:FindFirstChild(def.toolName)
			ItemTools.ensure(def.toolName)
			if not before then
				created += 1
			end
		end
	end
	if created > 0 then
		print("[ItemTools] Created " .. created .. " Tool instances in ServerStorage")
	end
	return created
end

return ItemTools
