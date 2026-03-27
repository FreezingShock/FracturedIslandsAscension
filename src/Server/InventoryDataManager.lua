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
--    - Building client payloads (hotbar + 27-slot grid + overflow)
--    - Hotbar assignment, swapping, unassignment
--    - Grid slot assignment (27 persistent slots, Minecraft-style)
--    - Auto-fill: overflow items auto-condense into empty grid slots
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
local GRID_SLOTS = 27
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
local AssignGridSlotFunc = ensureRemote("RemoteFunction", "AssignGridSlot")
local DropItemFunc = ensureRemote("RemoteFunction", "DropItem")
local MoveToEndFunc = ensureRemote("RemoteFunction", "MoveToEnd")

-- ===================== PER-PLAYER RUNTIME STATE =====================
-- Mirrors _Inventory profile data at runtime for fast access.
local playerState = {} -- [userId] = { toolOrder, nextOrderIndex, hotbarSlots, gridSlots }

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

--- Build rich toolInfo from a toolName and count info.
local function buildToolInfo(toolName, info)
	local regItem = ItemRegistry.getByToolName(toolName)
	local itemId = regItem and regItem.id or toolName
	local displayName = regItem and regItem.displayName or toolName
	local rarity = regItem and regItem.rarity or info.rarity
	local description = regItem and regItem.description or ""

	return {
		name = toolName, -- Tool.Name (used for equip/swap/drop)
		itemId = itemId, -- registry key
		displayName = displayName,
		count = math.min(info.count, MAX_STACK),
		rarity = rarity,
		description = description,
	}
end

--- Find the first empty grid slot index (1-27), or nil if all full.
local function findFirstEmptyGridSlot(state)
	for i = 1, GRID_SLOTS do
		if not state.gridSlots[i] then
			return i
		end
	end
	return nil
end

--- Find which grid slot a toolName occupies, or nil.
local function findGridSlotForTool(state, toolName)
	for i = 1, GRID_SLOTS do
		if state.gridSlots[i] == toolName then
			return i
		end
	end
	return nil
end

--- Find which hotbar slot a toolName occupies, or nil.
local function findHotbarSlotForTool(state, toolName)
	for i = 1, MAX_HOTBAR_SLOTS do
		if state.hotbarSlots[i] == toolName then
			return i
		end
	end
	return nil
end

--- Auto-fill empty grid slots from overflow items.
--- Call this before building the client payload.
--- Uses toolOrder for priority when multiple overflow items exist.
local function autoFillGrid(player)
	local state = playerState[player.UserId]
	if not state then
		return
	end

	local toolInfo = countTools(player)

	-- Build set of tool names already placed (hotbar or grid)
	local placed = {}
	for i = 1, MAX_HOTBAR_SLOTS do
		if state.hotbarSlots[i] then
			placed[state.hotbarSlots[i]] = true
		end
	end
	for i = 1, GRID_SLOTS do
		if state.gridSlots[i] then
			placed[state.gridSlots[i]] = true
		end
	end

	-- Collect unplaced tools (overflow), sorted by toolOrder
	local unplaced = {}
	for name, _ in pairs(toolInfo) do
		if not placed[name] then
			table.insert(unplaced, name)
		end
	end
	table.sort(unplaced, function(a, b)
		return (state.toolOrder[a] or math.huge) < (state.toolOrder[b] or math.huge)
	end)

	-- Fill empty grid slots with unplaced items
	local unplacedIdx = 1
	for i = 1, GRID_SLOTS do
		if not state.gridSlots[i] and unplacedIdx <= #unplaced then
			state.gridSlots[i] = unplaced[unplacedIdx]
			unplacedIdx = unplacedIdx + 1
		end
	end
end

--- Clean up grid/hotbar slots that reference tools no longer in inventory.
local function pruneStaleSlots(player)
	local state = playerState[player.UserId]
	if not state then
		return
	end

	local toolInfo = countTools(player)

	for i = 1, GRID_SLOTS do
		if state.gridSlots[i] and not toolInfo[state.gridSlots[i]] then
			state.gridSlots[i] = nil
		end
	end

	for i = 1, MAX_HOTBAR_SLOTS do
		if state.hotbarSlots[i] and not toolInfo[state.hotbarSlots[i]] then
			state.hotbarSlots[i] = nil
		end
	end
end

-- ===================== SEND UPDATE TO CLIENT =====================
--- Fires UpdateInventory with hotbar + grid slots + overflow data.
function InventoryDataManager.SendUpdate(player)
	local state = playerState[player.UserId]
	if not state then
		return
	end

	-- Prune stale references, then auto-fill grid from overflow
	pruneStaleSlots(player)
	autoFillGrid(player)

	local toolInfo = countTools(player)
	local invData = SkillsDataManager.GetInventoryData(player)
	local maxCapacity = invData and invData.maxCapacity or 1000

	-- Ensure toolOrder indices exist for all tools
	for name, _ in pairs(toolInfo) do
		if not state.toolOrder[name] then
			state.toolOrder[name] = state.nextOrderIndex
			state.nextOrderIndex = state.nextOrderIndex + 1
			if invData then
				invData.nextOrderIndex = state.nextOrderIndex
			end
		end
	end

	-- Build hotbar payload: { [1..9] = toolInfoOrFalse }
	local hotbarTools = {}
	for i = 1, MAX_HOTBAR_SLOTS do
		hotbarTools[i] = false
		local toolName = state.hotbarSlots[i]
		if toolName and toolInfo[toolName] then
			hotbarTools[i] = buildToolInfo(toolName, toolInfo[toolName])
		else
			state.hotbarSlots[i] = nil
		end
	end

	-- Build grid payload: { [1..27] = toolInfoOrFalse }
	-- CRITICAL: every index must be explicit (false for blanks) so Roblox
	-- serializes a dense array. Sparse tables (nil gaps) get truncated
	-- at the first nil by RemoteEvent serialization.
	local gridTools = {}
	local inHotbarOrGrid = {}

	-- Mark hotbar items
	for i = 1, MAX_HOTBAR_SLOTS do
		if state.hotbarSlots[i] then
			inHotbarOrGrid[state.hotbarSlots[i]] = true
		end
	end

	for i = 1, GRID_SLOTS do
		gridTools[i] = false -- default: blank
		local toolName = state.gridSlots[i]
		if toolName and toolInfo[toolName] and not inHotbarOrGrid[toolName] then
			gridTools[i] = buildToolInfo(toolName, toolInfo[toolName])
			inHotbarOrGrid[toolName] = true
		else
			-- Clear invalid grid slot (tool in hotbar or doesn't exist)
			if toolName and (inHotbarOrGrid[toolName] or not toolInfo[toolName]) then
				state.gridSlots[i] = nil
			end
		end
	end

	-- Build overflow: everything not in hotbar or grid, sorted by toolOrder
	local overflowTools = {}
	for name, info in pairs(toolInfo) do
		if not inHotbarOrGrid[name] then
			table.insert(overflowTools, buildToolInfo(name, info))
		end
	end
	table.sort(overflowTools, function(a, b)
		return (state.toolOrder[a.name] or math.huge) < (state.toolOrder[b.name] or math.huge)
	end)

	-- Total items across all tools
	local totalItems = 0
	for _, info in pairs(toolInfo) do
		totalItems = totalItems + info.count
	end

	UpdateInventoryEvent:FireClient(player, {
		hotbar = hotbarTools,
		gridSlots = gridTools,
		overflow = overflowTools,
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

	-- Auto-assign to first empty grid slot if this is a new tool type
	local state = playerState[player.UserId]
	if state and not existing[toolName] then
		-- New tool type — assign grid slot if not already placed
		if not findGridSlotForTool(state, toolName) and not findHotbarSlotForTool(state, toolName) then
			local emptySlot = findFirstEmptyGridSlot(state)
			if emptySlot then
				state.gridSlots[emptySlot] = toolName
			end
		end
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

	-- If tool type is fully gone, clear grid slot
	-- (pruneStaleSlots in SendUpdate handles this, but do it eagerly)
	if removed > 0 then
		local remaining = countTools(player)
		if not remaining[toolName] then
			local state = playerState[player.UserId]
			if state then
				local gridIdx = findGridSlotForTool(state, toolName)
				if gridIdx then
					state.gridSlots[gridIdx] = nil
				end
				local hotbarIdx = findHotbarSlotForTool(state, toolName)
				if hotbarIdx then
					state.hotbarSlots[hotbarIdx] = nil
				end
			end
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

	-- Clear hotbar and grid slots for this tool
	local state = playerState[player.UserId]
	if state then
		local hotbarIdx = findHotbarSlotForTool(state, toolName)
		if hotbarIdx then
			state.hotbarSlots[hotbarIdx] = nil
		end
		local gridIdx = findGridSlotForTool(state, toolName)
		if gridIdx then
			state.gridSlots[gridIdx] = nil
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

	-- Validate both tools exist
	local tools = countTools(player)
	if not tools[sourceName] or not tools[targetName] then
		return false
	end

	-- Locate each tool: hotbar, grid, or overflow (nil for both)
	local srcHotbar = findHotbarSlotForTool(state, sourceName)
	local srcGrid = findGridSlotForTool(state, sourceName)
	local tgtHotbar = findHotbarSlotForTool(state, targetName)
	local tgtGrid = findGridSlotForTool(state, targetName)

	local swapped = false

	-- Case: both in hotbar
	if srcHotbar and tgtHotbar then
		state.hotbarSlots[srcHotbar], state.hotbarSlots[tgtHotbar] =
			state.hotbarSlots[tgtHotbar], state.hotbarSlots[srcHotbar]
		swapped = true

	-- Case: both in grid
	elseif srcGrid and tgtGrid then
		state.gridSlots[srcGrid], state.gridSlots[tgtGrid] = state.gridSlots[tgtGrid], state.gridSlots[srcGrid]
		swapped = true

	-- Case: hotbar ↔ grid (both have items)
	elseif srcHotbar and tgtGrid then
		state.hotbarSlots[srcHotbar] = targetName
		state.gridSlots[tgtGrid] = sourceName
		swapped = true
	elseif srcGrid and tgtHotbar then
		state.gridSlots[srcGrid] = targetName
		state.hotbarSlots[tgtHotbar] = sourceName
		swapped = true

	-- Case: one in hotbar, other in overflow
	elseif srcHotbar and not tgtGrid then
		-- Target is overflow → put target in hotbar, source becomes overflow
		state.hotbarSlots[srcHotbar] = targetName
		swapped = true
	elseif tgtHotbar and not srcGrid then
		state.hotbarSlots[tgtHotbar] = sourceName
		swapped = true

	-- Case: one in grid, other in overflow
	elseif srcGrid and not tgtHotbar then
		-- Target is overflow → put target in grid slot, source becomes overflow
		state.gridSlots[srcGrid] = targetName
		swapped = true
	elseif tgtGrid and not srcHotbar then
		state.gridSlots[tgtGrid] = sourceName
		swapped = true

	-- Case: both in overflow → swap display order
	else
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

	-- Remove from any grid slot (item moves to hotbar)
	local gridIdx = findGridSlotForTool(state, toolName)
	if gridIdx then
		state.gridSlots[gridIdx] = nil
	end

	state.hotbarSlots[slotIndex] = toolName
	InventoryDataManager.SendUpdate(player)
	return true
end

-- ===================== ASSIGN GRID SLOT =====================
--- Place a tool into a specific grid slot (1-27).
--- Clears the tool from hotbar/other grid slot if it was there.
--- Target grid slot must be empty.
local function assignGridSlot(player, gridIndex: number, toolName: string): boolean
	local state = playerState[player.UserId]
	if not state then
		return false
	end

	-- Validate grid index
	if type(gridIndex) ~= "number" or gridIndex < 1 or gridIndex > GRID_SLOTS or math.floor(gridIndex) ~= gridIndex then
		return false
	end

	-- Validate tool exists
	local tools = countTools(player)
	if not tools[toolName] then
		return false
	end

	-- Target must be empty
	if state.gridSlots[gridIndex] then
		return false
	end

	-- Clear from hotbar if present
	local hotbarIdx = findHotbarSlotForTool(state, toolName)
	if hotbarIdx then
		state.hotbarSlots[hotbarIdx] = nil
	end

	-- Clear from any other grid slot
	local oldGridIdx = findGridSlotForTool(state, toolName)
	if oldGridIdx then
		state.gridSlots[oldGridIdx] = nil
	end

	state.gridSlots[gridIndex] = toolName
	InventoryDataManager.SendUpdate(player)
	return true
end

-- ===================== MOVE TO END (hotbar → grid/overflow) =====================
--- Remove tool from hotbar and auto-assign to first empty grid slot.
--- If no empty grid slot, tool becomes overflow.
local function moveToEnd(player, toolName: string): boolean
	local state = playerState[player.UserId]
	if not state then
		return false
	end

	-- Find and clear the hotbar slot
	local hotbarIdx = findHotbarSlotForTool(state, toolName)
	if not hotbarIdx then
		return false
	end

	state.hotbarSlots[hotbarIdx] = nil

	-- Auto-assign to first empty grid slot
	local emptySlot = findFirstEmptyGridSlot(state)
	if emptySlot then
		state.gridSlots[emptySlot] = toolName
	end
	-- If no empty slot, tool becomes overflow (autoFillGrid in SendUpdate handles edge cases)

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
	invData.gridSlots = state.gridSlots
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
		gridSlots = invData.gridSlots or {},
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

	-- ── Migration: existing players without gridSlots ──
	-- If gridSlots is empty but items exist, auto-assign them in toolOrder.
	local state = playerState[player.UserId]
	local hasAnyGridSlot = false
	for i = 1, GRID_SLOTS do
		if state.gridSlots[i] then
			hasAnyGridSlot = true
			break
		end
	end

	if not hasAnyGridSlot then
		-- Auto-fill grid from all non-hotbar items
		autoFillGrid(player)
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

AssignGridSlotFunc.OnServerInvoke = function(player, gridIndex, toolName)
	if type(gridIndex) ~= "number" or type(toolName) ~= "string" then
		return false
	end
	return assignGridSlot(player, gridIndex, toolName)
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
