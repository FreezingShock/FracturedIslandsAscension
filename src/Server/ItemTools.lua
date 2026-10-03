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

local Items = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Items")) :: any

local ItemTools = {}

local function stamp(tool: Tool, def: any)
	tool:SetAttribute("Rarity", def.rarity or 0)
	tool:SetAttribute("ItemId", def.id)
	if def.category == "weapon" then
		tool:SetAttribute("WeaponId", def.id) -- WeaponInit / WeaponManager key
	end
end

local function build(def: any): Tool
	local tool = Instance.new("Tool")
	tool.Name = def.toolName
	tool.CanBeDropped = true
	tool.RequiresHandle = false
	tool.ToolTip = def.displayName
	stamp(tool, def)
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
