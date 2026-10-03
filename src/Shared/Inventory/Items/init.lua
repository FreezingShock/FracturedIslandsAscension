--[[
	Items (ModuleScript)  — the item system's single source of truth.
	Place inside: ReplicatedStorage > Modules

	Layout:
	  Items/init      this registry (API below)
	  Items/Define    spec -> normalized definition (+ validation warnings)
	  Items/Rarity    rarity tiers
	  Items/Slots     the 8 armor / accessory slots
	  Items/Stats     stat keys -> tooltip rows + attribute boosts
	  Items/Defs/*    ONE FILE PER CATEGORY — this is where items live

	ADDING AN ITEM: add an entry to the matching Defs file (see Weapons.lua's
	solar_blade for every option). That's it — the tool, tooltip, inventory
	slot, equip logic and admin /give all pick it up automatically.

	ADDING A CATEGORY: drop a new ModuleScript into Defs/ returning
	{ id = spec, ... } and, if it isn't one of the names in FILE_CATEGORY,
	set `category = "..."` on its specs (or add the file name below).

	API (client + server):
	  Items.get(id) / Items.exists(id)
	  Items.getByToolName(toolName) / Items.getIdFromToolName(toolName)
	  Items.getRarity(rarity)
	  Items.list(category?) -> array of defs sorted by id
	  Items.getEquipSlot(id) -> "Helmet" ... or nil
	  Items.register(id, spec, category?) -> def   (runtime / admin-made items)
	  Items.Items, Items.RarityConfig, Items.Slots, Items.Stats, Items.Define
--]]

local Define = require(script:WaitForChild("Define"))
local Rarity = require(script:WaitForChild("Rarity"))
local Slots = require(script:WaitForChild("Slots"))
local Stats = require(script:WaitForChild("Stats"))

local Items = {}

Items.Define = Define
Items.Slots = Slots
Items.Stats = Stats
Items.RarityConfig = Rarity.Config
Items.Items = {}
Items._toolNameToId = {}

-- Defs file name -> category for specs that don't set their own.
local FILE_CATEGORY = {
	Weapons = "weapon",
	Armor = "armor",
	Accessories = "accessory",
	Materials = "material",
	Consumables = "consumable",
	Debug = "misc",
}

function Items.register(id: string, spec: any, category: string?)
	if Items.Items[id] then
		warn("[Items] duplicate id '" .. id .. "' (overwriting)")
	end
	local def = Define.item(id, spec, category)
	Items.Items[id] = def
	if def.toolName and def.toolName ~= "" then
		local existing = Items._toolNameToId[def.toolName]
		if existing and existing ~= id then
			warn(string.format("[Items] toolName '%s' used by both %s and %s", def.toolName, existing, id))
		end
		Items._toolNameToId[def.toolName] = id
	end
	return def
end

-- ===================== LOAD Defs/* =====================
local count = 0
local defsFolder = script:WaitForChild("Defs")
for _, module in ipairs(defsFolder:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, specs = pcall(require, module)
		if ok and type(specs) == "table" then
			for id, spec in pairs(specs) do
				Items.register(id, spec, FILE_CATEGORY[module.Name])
				count += 1
			end
		else
			warn("[Items] failed to load Defs/" .. module.Name .. ": " .. tostring(specs))
		end
	end
end

-- ===================== API =====================
function Items.get(itemId: string)
	return Items.Items[itemId]
end

function Items.exists(itemId: string): boolean
	return Items.Items[itemId] ~= nil
end

function Items.getRarity(rarity: number?)
	return Rarity.get(rarity)
end

function Items.getIdFromToolName(toolName: string): string?
	return Items._toolNameToId[toolName]
end

function Items.getByToolName(toolName: string)
	local id = Items._toolNameToId[toolName]
	return id and Items.Items[id] or nil
end

function Items.getEquipSlot(itemId: string): string?
	local def = Items.Items[itemId]
	return def and def.slot or nil
end

function Items.list(category: string?): { any }
	local out = {}
	for _, def in pairs(Items.Items) do
		if not category or def.category == category then
			table.insert(out, def)
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

print(string.format("Items: Loaded ✓ (%d items)", count))
return Items
