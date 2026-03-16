-- ============================================================
--  InventoryDataManager (ModuleScript)
--  Place inside: ServerScriptService
--
--  Server-authoritative inventory system using Tool instances
--  as the runtime source of truth. Saves/loads through the
--  shared ProfileStore managed by SkillsDataManager (data lives
--  under profile.Data._Inventory).
--
--  Handles:
--    - Loading saved inventory → spawning Tool clones in Backpack
--    - Building client payloads (hotbar + overflow inventory)
--    - Hotbar assignment, swapping, unassignment
--    - Equip/unequip via Humanoid
--    - Drop to world (entire stack, Tool clones at character pos)
--    - Saving on PlayerRemoving (Tool instances → profile data)
--    - Firing UpdateInventory RemoteEvent on every mutation
--
--  API (for other server scripts):
--    InventoryDataManager.AddItem(player, toolName, count?)
--    InventoryDataManager.RemoveItem(player, toolName, count?)
--    InventoryDataManager.GetTotalItems(player) → number
--    InventoryDataManager.SendUpdate(player)
--
--  RemoteFunction/Event handlers are wired internally.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ItemRegistry = require(Modules:WaitForChild("ItemRegistry")) :: any

local InventoryDataManager = {}

-- ===================== CONSTANTS =====================
local MAX_HOTBAR_SLOTS = 9
local MAX_STACK = 999
local DROP_FORWARD_OFFSET = 5 -- studs in front of character when dropping

-- ===================== REMOTES =====================
-- Pre-create in Studio for production. Fallback Instance.new for dev.
local function ensureRemote(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local UpdateInventoryEvent = ensureRemote("RemoteEvent", "UpdateInventory")
local PlayEquipSound = ensureRemote("RemoteEvent", "PlayEquipSound")
local EquipToolFunc = ensureRemote("RemoteFunction", "EquipTool")
local EquipToolByNameFunc = ensureRemote("RemoteFunction", "EquipToolByName")
local SwapItemsFunc = ensureRemote("RemoteFunction", "SwapItems")
local AssignHotbarFunc = ensureRemote("RemoteFunction", "AssignHotbar")
local DropItemFunc = ensureRemote("RemoteFunction", "DropItem")
local MoveToEndFunc = ensureRemote("RemoteFunction", "MoveToEnd")

-- ===================== PER-PLAYER RUNTIME STATE =====================
-- Mirrors _Inventory profile data at runtime for fast access.
-- toolOrder and hotbarSlots are live references into profile.Data._Inventory.
local playerState = {} -- [userId] = { toolOrder, nextOrderIndex, hotbarSlots }

-- ===================== HELPERS =====================

--- Get all Tool-holding containers for a player.
local function getContainers(player)
	local containers = {}
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		table.insert(containers, backpack)
	end
	if player.Character then
		table.insert(containers, player.Character)
	end
	return containers
end

--- Count tools across Backpack + Character, grouped by Tool.Name.
--- Returns: { [toolName] = { count=N, rarity=R } }
local function countTools(player)
	local result = {}
	for _, container in ipairs(getContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				local name = child.Name
				if not result[name] then
					local rarity = child:GetAttribute("Rarity") or 0
					result[name] = { count = 1, rarity = rarity }
				else
					result[name].count = result[name].count + 1
				end
			end
		end
	end
	return result
end

--- Get total item count across all containers.
function InventoryDataManager.GetTotalItems(player): number
	local total = 0
	for _, container in ipairs(getContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") then
				total = total + 1
			end
		end
	end
	return total
end

--- Build the sorted inventory list (respecting toolOrder).
local function buildSortedInventory(player)
	local state = playerState[player.UserId]
	if not state then
		return {}
	end

	local toolInfo = countTools(player)

	-- Assign order indices to new tool types
	for name, _ in pairs(toolInfo) do
		if not state.toolOrder[name] then
			state.toolOrder[name] = state.nextOrderIndex
			state.nextOrderIndex = state.nextOrderIndex + 1
			-- Keep profile in sync
			local invData = SkillsDataManager.GetInventoryData(player)
			if invData then
				invData.nextOrderIndex = state.nextOrderIndex
			end
		end
	end

	-- Build sorted array
	local sorted = {}
	for name, info in pairs(toolInfo) do
		if info.count > 0 then
			-- Resolve registry data for richer client info
			local regItem = ItemRegistry.getByToolName(name)
			local itemId = regItem and regItem.id or name
			local displayName = regItem and regItem.displayName or name
			local rarity = regItem and regItem.rarity or info.rarity
			local description = regItem and regItem.description or ""

			table.insert(sorted, {
				name = name, -- Tool.Name (used for equip/swap/drop)
				itemId = itemId, -- registry key
				displayName = displayName,
				count = math.min(info.count, MAX_STACK),
				rarity = rarity,
				description = description,
			})
		end
	end

	table.sort(sorted, function(a, b)
		return (state.toolOrder[a.name] or math.huge) < (state.toolOrder[b.name] or math.huge)
	end)

	return sorted
end

-- ===================== SEND UPDATE TO CLIENT =====================
--- Fires UpdateInventory with hotbar + overflow inventory data.
function InventoryDataManager.SendUpdate(player)
	local state = playerState[player.UserId]
	if not state then
		return
	end

	local fullInventory = buildSortedInventory(player)
	local invData = SkillsDataManager.GetInventoryData(player)
	local maxCapacity = invData and invData.maxCapacity or 1000

	-- Build hotbar payload: { [1..9] = toolInfoOrFalse }
	local hotbarTools = {}
	for i = 1, MAX_HOTBAR_SLOTS do
		hotbarTools[i] = false
		local toolName = state.hotbarSlots[i]
		if toolName then
			for _, info in ipairs(fullInventory) do
				if info.name == toolName then
					hotbarTools[i] = info
					break
				end
			end
			-- If tool no longer exists, clear the slot
			if hotbarTools[i] == false then
				state.hotbarSlots[i] = nil
			end
		end
	end

	-- Build overflow inventory: everything NOT in hotbar
	local inventoryTools = {}
	for _, info in ipairs(fullInventory) do
		local inHotbar = false
		for _, hb in pairs(hotbarTools) do
			if type(hb) == "table" and hb.name == info.name then
				inHotbar = true
				break
			end
		end
		if not inHotbar then
			table.insert(inventoryTools, info)
		end
	end

	local totalItems = 0
	for _, info in ipairs(fullInventory) do
		totalItems = totalItems + info.count
	end

	UpdateInventoryEvent:FireClient(player, {
		hotbar = hotbarTools,
		inventory = inventoryTools,
		max_capacity = maxCapacity,
		total_items = totalItems,
	})
end

-- ===================== ADD ITEM =====================
--- Add Tool instances to player's Backpack.
--- toolName must match a Tool.Name in ServerStorage.
--- Returns number of items actually added (may be < count if at capacity).
function InventoryDataManager.AddItem(player, toolName: string, count: number): number
	count = count or 1
	local invData = SkillsDataManager.GetInventoryData(player)
	if not invData then
		return 0
	end

	local tool = ServerStorage:FindFirstChild(toolName)
	if not tool or not tool:IsA("Tool") then
		warn("[InventoryDataManager] Tool not found in ServerStorage: " .. tostring(toolName))
		return 0
	end

	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return 0
	end

	-- Check capacity
	local currentTotal = InventoryDataManager.GetTotalItems(player)
	local maxCap = invData.maxCapacity
	local canAdd = math.min(count, maxCap - currentTotal)

	-- Check per-tool stack limit
	local existing = countTools(player)
	local currentCount = existing[toolName] and existing[toolName].count or 0
	canAdd = math.min(canAdd, MAX_STACK - currentCount)

	if canAdd <= 0 then
		return 0
	end

	for _ = 1, canAdd do
		local clone = tool:Clone()
		clone.Parent = backpack
	end

	-- Update is fired by ChildAdded listener, but force one to be safe
	InventoryDataManager.SendUpdate(player)
	return canAdd
end

-- ===================== REMOVE ITEM =====================
--- Remove Tool instances from player's Backpack (not Character).
--- Returns number actually removed.
function InventoryDataManager.RemoveItem(player, toolName: string, count: number?): number
	count = count or 1
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return 0
	end

	local removed = 0
	for _, child in ipairs(backpack:GetChildren()) do
		if removed >= count then
			break
		end
		if child:IsA("Tool") and child.Name == toolName then
			child:Destroy()
			removed = removed + 1
		end
	end

	InventoryDataManager.SendUpdate(player)
	return removed
end

-- ===================== DROP ITEM =====================
--- Drop entire stack of a tool to the world at the player's position.
--- Returns true if anything was dropped.
local function dropItem(player, toolName: string): boolean
	local character = player.Character
	if not character then
		return false
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	-- Unequip first if this tool is equipped
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") and child.Name == toolName then
				humanoid:UnequipTools()
				break
			end
		end
	end

	-- Gather all instances of this tool from Backpack + Character
	local toDrop = {}
	for _, container in ipairs(getContainers(player)) do
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child.Name == toolName then
				table.insert(toDrop, child)
			end
		end
	end

	if #toDrop == 0 then
		return false
	end

	-- Calculate drop position
	local dropPos = rootPart.Position + rootPart.CFrame.LookVector * DROP_FORWARD_OFFSET + Vector3.new(0, 2, 0)

	for _, tool in ipairs(toDrop) do
		tool.Parent = workspace
		if tool:FindFirstChild("Handle") then
			tool.Handle.CFrame = CFrame.new(dropPos)
		end
	end

	-- Clear hotbar slot if this tool was assigned
	local state = playerState[player.UserId]
	if state then
		for i = 1, MAX_HOTBAR_SLOTS do
			if state.hotbarSlots[i] == toolName then
				state.hotbarSlots[i] = nil
				break
			end
		end
	end

	InventoryDataManager.SendUpdate(player)
	return true
end

-- ===================== EQUIP / UNEQUIP =====================
local function equipBySlot(player, slotNumber: number): boolean
	local state = playerState[player.UserId]
	if not state or not state.hotbarSlots[slotNumber] then
		return false
	end

	local toolName = state.hotbarSlots[slotNumber]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	-- Check if already equipped → toggle off
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child.Name == toolName then
			humanoid:UnequipTools()
			PlayEquipSound:FireClient(player, "unequip")
			InventoryDataManager.SendUpdate(player)
			return true
		end
	end

	-- Find in backpack and equip
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child.Name == toolName then
				humanoid:EquipTool(child)
				PlayEquipSound:FireClient(player, "equip")
				InventoryDataManager.SendUpdate(player)
				return true
			end
		end
	end

	return false
end

local function equipByName(player, toolName: string): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	-- Toggle off if already equipped
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child.Name == toolName then
			humanoid:UnequipTools()
			PlayEquipSound:FireClient(player, "unequip")
			InventoryDataManager.SendUpdate(player)
			return true
		end
	end

	-- Equip from backpack
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child.Name == toolName then
				humanoid:EquipTool(child)
				PlayEquipSound:FireClient(player, "equip")
				InventoryDataManager.SendUpdate(player)
				return true
			end
		end
	end

	return false
end

-- ===================== SWAP / ASSIGN =====================
local function swapItems(player, sourceName: string, targetName: string): boolean
	local state = playerState[player.UserId]
	if not state or not sourceName or not targetName or sourceName == targetName then
		return false
	end

	local slotA, slotB
	for i = 1, MAX_HOTBAR_SLOTS do
		if state.hotbarSlots[i] == sourceName then
			slotA = i
		end
		if state.hotbarSlots[i] == targetName then
			slotB = i
		end
	end

	local swapped = false

	if slotA and slotB then
		-- Both in hotbar → swap slots
		state.hotbarSlots[slotA], state.hotbarSlots[slotB] = state.hotbarSlots[slotB], state.hotbarSlots[slotA]
		swapped = true
	elseif slotA then
		-- Source in hotbar, target in inventory → replace source with target
		state.hotbarSlots[slotA] = targetName
		swapped = true
	elseif slotB then
		-- Target in hotbar, source in inventory → replace target with source
		state.hotbarSlots[slotB] = sourceName
		swapped = true
	else
		-- Both in inventory → swap display order
		local orderA = state.toolOrder[sourceName]
		local orderB = state.toolOrder[targetName]
		if orderA and orderB then
			state.toolOrder[sourceName] = orderB
			state.toolOrder[targetName] = orderA
			swapped = true
		end
	end

	if swapped then
		InventoryDataManager.SendUpdate(player)
	end
	return swapped
end

local function assignHotbar(player, slotIndex: number, toolName: string): boolean
	local state = playerState[player.UserId]
	if not state then
		return false
	end

	-- Validate slot
	if
		type(slotIndex) ~= "number"
		or slotIndex < 1
		or slotIndex > MAX_HOTBAR_SLOTS
		or math.floor(slotIndex) ~= slotIndex
	then
		return false
	end

	-- Validate tool exists in inventory
	local tools = countTools(player)
	if not tools[toolName] then
		return false
	end

	-- Remove from any existing hotbar slot
	for i = 1, MAX_HOTBAR_SLOTS do
		if state.hotbarSlots[i] == toolName then
			state.hotbarSlots[i] = nil
		end
	end

	state.hotbarSlots[slotIndex] = toolName
	InventoryDataManager.SendUpdate(player)
	return true
end

local function moveToEnd(player, toolName: string): boolean
	local state = playerState[player.UserId]
	if not state then
		return false
	end

	-- Find the hotbar slot
	local slot
	for i = 1, MAX_HOTBAR_SLOTS do
		if state.hotbarSlots[i] == toolName then
			slot = i
			break
		end
	end

	if not slot then
		return false
	end

	-- Remove and shift left
	state.hotbarSlots[slot] = nil
	for i = slot, MAX_HOTBAR_SLOTS - 1 do
		state.hotbarSlots[i] = state.hotbarSlots[i + 1]
	end
	state.hotbarSlots[MAX_HOTBAR_SLOTS] = nil

	InventoryDataManager.SendUpdate(player)
	return true
end

-- ===================== SAVE INVENTORY TO PROFILE =====================
local function saveInventoryToProfile(player)
	local invData = SkillsDataManager.GetInventoryData(player)
	if not invData then
		return
	end

	local state = playerState[player.UserId]
	if not state then
		return
	end

	-- Serialize current Tool instances → items array
	local toolCounts = countTools(player)
	local items = {}
	for name, info in pairs(toolCounts) do
		-- Store by Tool.Name so we can re-spawn them on load
		table.insert(items, {
			toolName = name,
			count = math.min(info.count, MAX_STACK),
			rarity = info.rarity,
		})
	end

	invData.items = items
	invData.hotbarSlots = state.hotbarSlots
	invData.toolOrder = state.toolOrder
	invData.nextOrderIndex = state.nextOrderIndex
end

-- ===================== LOAD INVENTORY FROM PROFILE =====================
local function loadInventoryFromProfile(player)
	local invData = SkillsDataManager.GetInventoryData(player)
	if not invData then
		return
	end

	-- Initialize runtime state
	playerState[player.UserId] = {
		toolOrder = invData.toolOrder or {},
		nextOrderIndex = invData.nextOrderIndex or 1,
		hotbarSlots = invData.hotbarSlots or {},
	}

	-- Spawn Tool clones from saved items
	local backpack = player:WaitForChild("Backpack")
	for _, entry in ipairs(invData.items) do
		local toolName = entry.toolName
		local count = math.min(entry.count or 1, MAX_STACK)
		local tool = ServerStorage:FindFirstChild(toolName)
		if tool and tool:IsA("Tool") then
			for _ = 1, count do
				local clone = tool:Clone()
				clone.Parent = backpack
			end
		else
			warn("[InventoryDataManager] Saved tool not found in ServerStorage: " .. tostring(toolName))
		end
	end
end

-- ===================== PLAYER LIFECYCLE =====================
local function onPlayerReady(player)
	-- Wait for SkillsDataManager to load the profile first
	local attempts = 0
	while not SkillsDataManager.IsLoaded(player) and attempts < 100 do
		task.wait(0.1)
		attempts = attempts + 1
	end

	if not SkillsDataManager.IsLoaded(player) then
		warn("[InventoryDataManager] Profile never loaded for " .. player.Name)
		return
	end

	loadInventoryFromProfile(player)

	-- Wire ChildAdded/Removed listeners for live updates
	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			InventoryDataManager.SendUpdate(player)
		end
	end)
	backpack.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			InventoryDataManager.SendUpdate(player)
		end
	end)

	-- Also listen on character for equip/unequip
	local function wireCharacter(char)
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				InventoryDataManager.SendUpdate(player)
			end
		end)
		char.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				InventoryDataManager.SendUpdate(player)
			end
		end)
	end

	if player.Character then
		wireCharacter(player.Character)
	end
	player.CharacterAdded:Connect(wireCharacter)

	-- Send initial update
	InventoryDataManager.SendUpdate(player)
	print("[InventoryDataManager] Loaded inventory for " .. player.Name)
end

local function onPlayerLeaving(player)
	saveInventoryToProfile(player)
	playerState[player.UserId] = nil
end

-- ===================== WIRE REMOTES =====================
EquipToolFunc.OnServerInvoke = function(player, slotNumber)
	if type(slotNumber) ~= "number" then
		return false
	end
	return equipBySlot(player, slotNumber)
end

EquipToolByNameFunc.OnServerInvoke = function(player, toolName)
	if type(toolName) ~= "string" then
		return false
	end
	return equipByName(player, toolName)
end

SwapItemsFunc.OnServerInvoke = function(player, sourceName, targetName)
	if type(sourceName) ~= "string" or type(targetName) ~= "string" then
		return false
	end
	return swapItems(player, sourceName, targetName)
end

AssignHotbarFunc.OnServerInvoke = function(player, slotIndex, toolName)
	if type(slotIndex) ~= "number" or type(toolName) ~= "string" then
		return false
	end
	return assignHotbar(player, slotIndex, toolName)
end

DropItemFunc.OnServerInvoke = function(player, toolName)
	if type(toolName) ~= "string" then
		return false
	end
	return dropItem(player, toolName)
end

MoveToEndFunc.OnServerInvoke = function(player, toolName)
	if type(toolName) ~= "string" then
		return false
	end
	return moveToEnd(player, toolName)
end

-- ===================== PLAYER HOOKS =====================
Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayerReady, player)
end)

Players.PlayerRemoving:Connect(function(player)
	onPlayerLeaving(player)
end)

-- Handle players already in game (Studio testing)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerReady, player)
end

print("[InventoryDataManager] Loaded ✓")
return InventoryDataManager
