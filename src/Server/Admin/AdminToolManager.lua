-- ============================================================
--  AdminToolManager (ModuleScript, Server)
--  ServerScriptService
--
--  Validates item creation, spawns dynamic items, and manages
--  the runtime item registry for testing.
--
--  All functions are admin-gated at the RemoteFunction level.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryDataManager = require(game:GetService("ServerScriptService"):WaitForChild("InventoryDataManager"))
local ItemRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemRegistry"))

local AdminToolManager = {}

-- ===================== ADMIN USER IDS =====================
-- Admin ids live in Modules/AdminConfig.
local AdminConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AdminConfig"))

-- ===================== RUNTIME ITEM STORAGE =====================
-- Items created during this session (not persisted between server restarts)
local runtimeItems = {}
local runtimeItemCounter = 0

-- ===================== VALIDATION =====================

local isAdmin = AdminConfig.isAdmin

local function validateItemData(itemData)
	-- Required fields
	if not itemData.displayName or itemData.displayName == "" then
		return false, "displayName is required"
	end
	if type(itemData.rarity) ~= "number" or itemData.rarity < 0 or itemData.rarity > 5 then
		return false, "rarity must be 0-5"
	end

	-- Optional fields with defaults
	itemData.description = itemData.description or ""
	itemData.icon = itemData.icon or ""
	itemData.statBonuses = itemData.statBonuses or {}
	itemData.ability = itemData.ability or "None"
	itemData.maxStack = itemData.maxStack or 999

	-- Validate stat bonuses structure
	if type(itemData.statBonuses) ~= "table" then
		return false, "statBonuses must be a table"
	end

	return true, itemData
end

-- ===================== ITEM CREATION =====================

--- Create a new item and register it in the runtime registry.
--- Returns: success (bool), itemId (string) or error message
function AdminToolManager.CreateItem(player, itemData)
	if not isAdmin(player) then
		return false, "Admin access required"
	end

	local valid, result = validateItemData(itemData)
	if not valid then
		return false, result
	end

	itemData = result

	-- Generate a unique item ID
	runtimeItemCounter = runtimeItemCounter + 1
	local itemId = "dev_item_" .. player.Name .. "_" .. runtimeItemCounter

	-- Create the full item registry entry
	local registryEntry = {
		id = itemId,
		displayName = itemData.displayName,
		description = itemData.description,
		rarity = itemData.rarity,
		icon = itemData.icon,
		maxStack = itemData.maxStack,
		statBonuses = itemData.statBonuses,
		ability = itemData.ability,
		isDynamic = true, -- Mark as dev-created
		createdBy = player.Name,
		createdAt = os.time(),
	}

	-- Register in runtime items (client-side will see this too)
	runtimeItems[itemId] = registryEntry

	-- Also register in ItemRegistry.Items for consistency
	ItemRegistry.Items[itemId] = registryEntry

	print(
		string.format(
			"[AdminToolManager] Created dynamic item: %s (id=%s, rarity=%d)",
			itemData.displayName,
			itemId,
			itemData.rarity
		)
	)

	return true, itemId
end

-- ===================== ITEM SPAWNING =====================

--- Spawn a dynamic item directly into the player's inventory.
--- itemId can be from ItemRegistry (static) or runtimeItems (dev).
function AdminToolManager.SpawnItem(player, itemId: string, count: number)
	if not isAdmin(player) then
		return false, "Admin access required"
	end

	count = count or 1
	if type(count) ~= "number" or count < 1 then
		count = 1
	end

	-- Validate item exists
	local itemEntry = ItemRegistry.Items[itemId]
	if not itemEntry then
		return false, "Item not found: " .. itemId
	end

	-- If it's a dynamic item, create a Tool instance on the fly
	-- (static items have pre-built Tools in ServerStorage)
	if itemEntry.isDynamic then
		-- Create a temporary Tool instance
		local tool = Instance.new("Tool")
		tool.Name = itemId
		tool.Grip = CFrame.new(0, 0, -5) -- Offset for visual clarity
		tool.ToolTip = itemEntry.displayName

		-- Attach a Handle part (required for Tools)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Shape = Enum.PartType.Ball
		handle.Material = Enum.Material.Neon
		handle.Size = Vector3.new(0.5, 0.5, 0.5)
		handle.CanCollide = false
		handle.Parent = tool

		-- Store item metadata as attributes (for server stat computation)
		tool:SetAttribute("ItemId", itemId)
		tool:SetAttribute("Rarity", itemEntry.rarity)
		tool:SetAttribute("DisplayName", itemEntry.displayName)

		tool.Parent = player:FindFirstChild("Backpack")

		print(
			string.format(
				"[AdminToolManager] Spawned dynamic item: %s (id=%s) into %s's inventory",
				itemEntry.displayName,
				itemId,
				player.Name
			)
		)
	else
		-- Use InventoryDataManager for static items (standard spawn)
		InventoryDataManager.AddItem(player, itemId, count)
	end

	return true
end

-- ===================== RUNTIME ITEM FETCHING =====================

--- Get all runtime (dev-created) items as a table.
function AdminToolManager.GetRuntimeItems(player)
	if not isAdmin(player) then
		return {}
	end

	-- Return a serializable copy (no functions)
	local result = {}
	for itemId, entry in pairs(runtimeItems) do
		table.insert(result, {
			id = entry.id,
			displayName = entry.displayName,
			rarity = entry.rarity,
			ability = entry.ability,
			createdBy = entry.createdBy,
		})
	end
	return result
end

-- ===================== REMOTES =====================

--- Wire the admin panel remotes
function AdminToolManager.WireRemotes()
	local CreateItemFunc = ReplicatedStorage:FindFirstChild("CreateItem")
	if not CreateItemFunc then
		CreateItemFunc = Instance.new("RemoteFunction")
		CreateItemFunc.Name = "CreateItem"
		CreateItemFunc.Parent = ReplicatedStorage
	end

	CreateItemFunc.OnServerInvoke = function(player, itemData)
		return AdminToolManager.CreateItem(player, itemData)
	end

	local SpawnItemFunc = ReplicatedStorage:FindFirstChild("SpawnItem")
	if not SpawnItemFunc then
		SpawnItemFunc = Instance.new("RemoteFunction")
		SpawnItemFunc.Name = "SpawnItem"
		SpawnItemFunc.Parent = ReplicatedStorage
	end

	SpawnItemFunc.OnServerInvoke = function(player, itemId, count)
		return AdminToolManager.SpawnItem(player, itemId, count)
	end

	local GetRuntimeItemsFunc = ReplicatedStorage:FindFirstChild("GetRuntimeItems")
	if not GetRuntimeItemsFunc then
		GetRuntimeItemsFunc = Instance.new("RemoteFunction")
		GetRuntimeItemsFunc.Name = "GetRuntimeItems"
		GetRuntimeItemsFunc.Parent = ReplicatedStorage
	end

	GetRuntimeItemsFunc.OnServerInvoke = function(player)
		return AdminToolManager.GetRuntimeItems(player)
	end

	print("[AdminToolManager] Remotes wired ✓")
end

print("[AdminToolManager] Loaded ✓")
return AdminToolManager
