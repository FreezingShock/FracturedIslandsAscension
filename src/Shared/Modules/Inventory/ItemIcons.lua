--[[
	ItemIcons (ModuleScript) — one place that turns an item def into an icon.

	  ItemIcons.resolve(defOrId) -> spec { image, rectOffset?, rectSize?, tint?, placeholder }
	  ItemIcons.apply(label, defOrId) -> boolean   sets an ImageLabel; true when a real icon (not the placeholder)
	  ItemIcons.ensureImage(parent, opts?) -> ImageLabel   the shared "ItemImage" child used by slots
	  ItemIcons.preload(priorityKeys?)     background-load every icon (call once on the client)

	Lookup order for an item: def.icon (key | "rbxassetid://" | spec table), ALIASES[def.id],
	ItemIconData[def.id], then the placeholder (warns once per item).

	Adding an icon: see tools/gen_icon_data.py. ItemIconData is generated; ALIASES and the
	tints below are the hand-edited part.
--]]

local ContentProvider = game:GetService("ContentProvider")

local Data = require(script.Parent:WaitForChild("ItemIconData")) :: { [string]: string }

local ItemIcons = {}

local PLACEHOLDER_KEY = "barrier"
local PRELOAD_BATCH = 50

-- item id -> icon key, for items whose id differs from the icon name.
-- A table entry { key = ..., tint = "rarity" } tints the icon with the item's rarity colour.
local ALIASES: { [string]: any } = {
	solar_blade = "golden_sword",
	sword_basic = "iron_sword",
	sword_legendary = "diamond_sword",
	spear_basic = "wooden_spear",
	bow_basic = "bow",
	staff_basic = "stick",
	coal_terrafruit = "coal",
	iron_terrafruit = "iron_ingot",
	gold_terrafruit = "gold_ingot",
	solar_crown = "golden_helmet",
	lucky_cloak = "elytra",
	swift_gloves = "leather",
	sapphire_amulet = "lapis_lazuli",
	warriors_belt = "lead",
	rarity_test_0 = { key = "amethyst_shard", tint = "rarity" },
	rarity_test_1 = { key = "amethyst_shard", tint = "rarity" },
	rarity_test_2 = { key = "amethyst_shard", tint = "rarity" },
	rarity_test_3 = { key = "amethyst_shard", tint = "rarity" },
	rarity_test_4 = { key = "amethyst_shard", tint = "rarity" },
	rarity_test_5 = { key = "amethyst_shard", tint = "rarity" },
}

local itemsModule: any = nil
local function items(): any
	if itemsModule == nil then
		local ok, result = pcall(function()
			return require(script.Parent:WaitForChild("Items"))
		end)
		itemsModule = ok and result or false
	end
	return itemsModule or nil
end

local cache: { [string]: any } = {}
local warned: { [string]: boolean } = {}

local function isContent(s: string): boolean
	return s:sub(1, 13) == "rbxassetid://" or s:sub(1, 11) == "rbxasset://" or s:sub(1, 4) == "http"
end

local function rarityTint(def: any): Color3?
	local Items = items()
	local rarity = Items and Items.getRarity(def.rarity)
	return rarity and rarity.color or nil
end

local function build(def: any): any
	local icon = def.icon
	local spec: any

	if type(icon) == "table" then
		if icon.image and icon.image ~= "" then
			spec = { image = Data[icon.image] or icon.image, rectOffset = icon.rectOffset, rectSize = icon.rectSize, tint = icon.tint }
		end
	elseif type(icon) == "string" and icon ~= "" then
		if isContent(icon) then
			spec = { image = icon }
		elseif Data[icon] then
			spec = { image = Data[icon] }
		end
	end

	if not spec then
		local alias = ALIASES[def.id]
		local key = type(alias) == "table" and alias.key or alias or def.id
		if Data[key] then
			spec = { image = Data[key] }
			if type(alias) == "table" and alias.tint == "rarity" then
				spec.tint = rarityTint(def)
			end
		end
	end

	if spec then
		spec.placeholder = false
		return spec
	end

	if not warned[def.id] then
		warned[def.id] = true
		warn(("[ItemIcons] no icon for item '%s' (add it to ALIASES or ItemIconData); using placeholder"):format(tostring(def.id)))
	end
	return { image = Data[PLACEHOLDER_KEY] or "", placeholder = true }
end

function ItemIcons.resolve(defOrId: any): any
	local def = defOrId
	if type(defOrId) == "string" then
		local Items = items()
		def = Items and Items.get(defOrId) or { id = defOrId }
	end
	if type(def) ~= "table" then
		return { image = Data[PLACEHOLDER_KEY] or "", placeholder = true }
	end
	local key = def.id or "?"
	local spec = cache[key]
	if not spec then
		spec = build(def)
		cache[key] = spec
	end
	return spec
end

function ItemIcons.apply(label: ImageLabel?, defOrId: any): boolean
	if not label then
		return false
	end
	local spec = ItemIcons.resolve(defOrId)
	local forId = type(defOrId) == "table" and defOrId.id or defOrId
	if forId and label:GetAttribute("IconFor") == forId then
		return not spec.placeholder -- already showing this item (slots re-render on every hover)
	end
	label:SetAttribute("IconFor", forId)
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.Image = spec.image
	label.ImageRectOffset = spec.rectOffset or Vector2.zero
	label.ImageRectSize = spec.rectSize or Vector2.zero
	label.ImageColor3 = spec.tint or Color3.new(1, 1, 1)
	label.ImageTransparency = 0
	return not spec.placeholder
end

--- The reusable icon child of a slot/button. `opts`: size (UDim2), position (UDim2), zIndex.
function ItemIcons.ensureImage(parent: Instance, opts: any?): ImageLabel
	local img = parent:FindFirstChild("ItemImage")
	if img and img:IsA("ImageLabel") then
		return img
	end
	opts = opts or {}
	local created = Instance.new("ImageLabel")
	created.Name = "ItemImage"
	created.BackgroundTransparency = 1
	created.AnchorPoint = Vector2.new(0.5, 0.5)
	created.Position = opts.position or UDim2.fromScale(0.5, 0.45)
	created.Size = opts.size or UDim2.fromScale(0.58, 0.58)
	created.ScaleType = Enum.ScaleType.Fit
	created.ResampleMode = Enum.ResamplerMode.Pixelated
	created.ZIndex = opts.zIndex or 2
	created.Visible = false
	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.Parent = created
	created.Parent = parent
	return created
end

local preloadStarted = false

--- Background-load every icon in batches. `priorityKeys` (icon keys or item ids) go first.
function ItemIcons.preload(priorityKeys: { string }?)
	if preloadStarted then
		return
	end
	preloadStarted = true

	local ordered, seen = {}, {}
	local function add(content: string?)
		if content and content ~= "" and not seen[content] then
			seen[content] = true
			table.insert(ordered, content)
		end
	end
	add(Data[PLACEHOLDER_KEY])
	for _, k in ipairs(priorityKeys or {}) do
		add(ItemIcons.resolve(k).image)
	end
	for _, content in pairs(Data) do
		add(content)
	end

	task.spawn(function()
		for i = 1, #ordered, PRELOAD_BATCH do
			pcall(ContentProvider.PreloadAsync, ContentProvider, table.move(ordered, i, math.min(i + PRELOAD_BATCH - 1, #ordered), 1, {}))
		end
	end)
end

--- Items whose icon would be the placeholder (used by verification).
function ItemIcons.missing(): { string }
	local out = {}
	local Items = items()
	for _, def in ipairs(Items and Items.list() or {}) do
		if ItemIcons.resolve(def).placeholder then
			table.insert(out, def.id)
		end
	end
	return out
end

return ItemIcons
