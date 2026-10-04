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
--    (Armor / accessory equipping lives in EquipmentService: the client right
--     clicks the item -> EquipItem remote. Number keys just hold it as a Tool.)
--    - Per-item stack cap from the registry (gear maxStack = 1)
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
local ItemTools = require(ServerScriptService:WaitForChild("ItemTools")) :: any
local ItemDrops = require(ServerScriptService:WaitForChild("ItemDrops")) :: any
local RateLimiter = require(ServerScriptService:WaitForChild("RateLimiter")) :: any
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ItemRegistry = require(Modules:WaitForChild("Items")) :: any

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
local RequestInventoryEvent = ensureRemote("RemoteEvent", "RequestInventory")
local TrashItemFunc = ensureRemote("RemoteFunction", "TrashItem")
local RestoreTrashFunc = ensureRemote("RemoteFunction", "RestoreTrash")

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

--- Most copies of one item the inventory may hold (gear is 1, resources 999).
local function stackLimit(toolName: string): number
	local def = ItemRegistry.getByToolName(toolName)
	return math.min(MAX_STACK, def and def.maxStack or MAX_STACK)
end

-- Slot keys. The first stack of an item is keyed by its Tool name; further stacks (every extra copy
-- of an unstackable item) get "Name#2", "Name#3"... so identical items can sit in different slots.
local function baseOf(key: string): string
	return key:match("^(.-)#%d+$") or key
end
local function keyIndex(key: string): number
	return tonumber(key:match("#(%d+)$")) or 1
end
local function keyFor(base: string, idx: number): string
	return idx == 1 and base or (base .. "#" .. idx)
end

--- Inventory entries, one per slot-able stack: [key] = { count, rarity, base }
local function countEntries(player)
	local result = {}
	for name, info in pairs(countTools(player)) do
		local limit = stackLimit(name)
		local left, idx = info.count, 1
		while left > 0 do
			local n = math.min(limit, left)
			result[keyFor(name, idx)] = { count = n, rarity = info.rarity, base = name }
			left -= n
			idx += 1
		end
	end
	return result
end

--- Build rich toolInfo for a slot key (see baseOf) and its entry.
local function buildToolInfo(key, info)
	local toolName = info.base or baseOf(key)
	local regItem = ItemRegistry.getByToolName(toolName)
	local itemId = regItem and regItem.id or toolName
	local displayName = regItem and regItem.displayName or toolName
	local rarity = regItem and regItem.rarity or info.rarity
	local description = regItem and regItem.description or ""

	return {
		name = key, -- slot key (used for equip/swap/drop; == toolName for the first stack)
		toolName = toolName, -- Tool.Name
		itemId = itemId, -- registry key
		displayName = displayName,
		count = info.count,
		unstackable = stackLimit(toolName) == 1, -- the client hides the "1x" label on these
		equippable = regItem == nil or regItem.equippable ~= false,
		rarity = rarity,
		description = description,
		category = regItem and regItem.category or nil,
		slot = regItem and regItem.slot or nil, -- armor / accessory slot id
	}
end

-- Trash slot: the last trashed stack stays here until the next trash or rejoin (never saved).
-- [userId] = { toolName, count, rarity, custom }
local trashBin = {}

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

	local toolInfo = countEntries(player)

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

	local toolInfo = countEntries(player)

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
local ensureSelectedHeld -- defined with the equip functions below (SendUpdate calls it)

--- The Tool the player is holding that belongs to `base` (Tool.Name), if any.
local function heldToolOf(player, base: string)
	local character = player.Character
	for _, child in ipairs(character and character:GetChildren() or {}) do
		if child:IsA("Tool") and child.Name == base then
			return child
		end
	end
	return nil
end

--- Fires UpdateInventory with hotbar + grid slots + overflow data.
function InventoryDataManager.SendUpdate(player)
	local state = playerState[player.UserId]
	if not state then
		return
	end

	-- Prune stale references, then auto-fill grid from overflow
	pruneStaleSlots(player)
	autoFillGrid(player)

	-- Forget the held slot when nothing of that item is in hand any more (put away, dropped, died...)
	if state.heldKey and os.clock() - (state.heldAt or 0) > 0.3 and not heldToolOf(player, baseOf(state.heldKey)) then
		state.heldKey = nil
	end

	local toolInfo = countEntries(player)
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

	local trashed = trashBin[player.UserId]
	UpdateInventoryEvent:FireClient(player, {
		trash = trashed and buildToolInfo(trashed.toolName, {
			base = trashed.toolName,
			count = trashed.count,
			rarity = trashed.rarity,
		}) or false,
		selected = state.selected or 1, -- selected hotbar slot (an empty slot = empty hand)
		held = state.heldKey or false, -- slot key of the item in hand
		hotbar = hotbarTools,
		gridSlots = gridTools,
		overflow = overflowTools,
		max_capacity = maxCapacity,
		total_items = totalItems,
	})
	task.defer(ensureSelectedHeld, player)
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

	local tool = ItemTools.ensure(toolName)
	if not tool then
		warn("[InventoryDataManager] Unknown item/tool: " .. tostring(toolName))
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

	-- Per-item cap (total capacity is checked above); extra copies of unstackable items get their own slots
	local existing = countTools(player)
	local before = existing[toolName] and existing[toolName].count or 0
	canAdd = math.min(canAdd, MAX_STACK - before)

	if canAdd <= 0 then
		return 0
	end

	for _ = 1, canAdd do
		local clone = tool:Clone()
		clone.Parent = backpack
	end

	-- New stacks: first empty hotbar item slot (1..8, 9 is the menu), then the first empty grid slot
	local state = playerState[player.UserId]
	if state then
		local limit = stackLimit(toolName)
		for idx = math.ceil(before / limit) + 1, math.ceil((before + canAdd) / limit) do
			local key = keyFor(toolName, idx)
			if not findGridSlotForTool(state, key) and not findHotbarSlotForTool(state, key) then
				local hotbarSlot
				local selected = state.selected
				if selected and not state.hotbarSlots[selected] then
					hotbarSlot = selected -- lands in the (empty) selected slot and is drawn at once
				else
					for i = 1, MAX_HOTBAR_SLOTS - 1 do
						if not state.hotbarSlots[i] then
							hotbarSlot = i
							break
						end
					end
				end
				if hotbarSlot then
					state.hotbarSlots[hotbarSlot] = key
				else
					local emptySlot = findFirstEmptyGridSlot(state)
					if emptySlot then
						state.gridSlots[emptySlot] = key
					end
				end
			end
		end
	end

	-- Update is fired by ChildAdded listener, but force one to be safe
	InventoryDataManager.SendUpdate(player)
	return canAdd
end

-- ===================== REMOVE ITEM =====================
--- Remove Tool instances from player's Backpack (not Character).
--- `key` is a Tool name or a slot key ("Name#2"); with a slot key of an unstackable item the
--- copy in THAT slot is the one that goes away (the others close up behind it).
--- Returns number actually removed.
local function compactKeys(state, base: string, clearKey: string?, entryCount: number)
	if clearKey then
		for i = 1, GRID_SLOTS do
			if state.gridSlots[i] == clearKey then
				state.gridSlots[i] = nil
			end
		end
		for i = 1, MAX_HOTBAR_SLOTS do
			if state.hotbarSlots[i] == clearKey then
				state.hotbarSlots[i] = nil
			end
		end
	end
	local refs = {}
	for i = 1, MAX_HOTBAR_SLOTS do
		local k = state.hotbarSlots[i]
		if k and baseOf(k) == base then
			table.insert(refs, { map = state.hotbarSlots, i = i, idx = keyIndex(k) })
		end
	end
	for i = 1, GRID_SLOTS do
		local k = state.gridSlots[i]
		if k and baseOf(k) == base then
			table.insert(refs, { map = state.gridSlots, i = i, idx = keyIndex(k) })
		end
	end
	table.sort(refs, function(a, b)
		return a.idx < b.idx
	end)
	for n, ref in ipairs(refs) do
		ref.map[ref.i] = n <= entryCount and keyFor(base, n) or nil
	end
end

function InventoryDataManager.RemoveItem(player, key: string, count: number?): number
	count = count or 1
	local base = baseOf(key)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		return 0
	end

	local removed = 0
	for _, child in ipairs(backpack:GetChildren()) do
		if removed >= count then
			break
		end
		if child:IsA("Tool") and child.Name == base then
			child:Destroy()
			removed = removed + 1
		end
	end

	-- Close up the slot keys (pruneStaleSlots in SendUpdate would also cope, but this keeps the
	-- slot you removed from, not just the last one)
	if removed > 0 then
		local state = playerState[player.UserId]
		if state then
			local left = countTools(player)[base]
			local limit = stackLimit(base)
			compactKeys(state, base, limit == 1 and key or nil, left and math.ceil(left.count / limit) or 0)
		end
	end

	InventoryDataManager.SendUpdate(player)
	return removed
end

-- ===================== DROP ITEM =====================
--- Drop entire stack of a tool to the world at the player's position.
--- Returns true if anything was dropped.
--- Drop items into the world as ItemDrops (Minecraft style). `all` = the whole stack, otherwise one.
--- The Tools are destroyed (and slots cleared by RemoveItem) BEFORE the drop is created.
local lastDropAt = {} -- [userId] = os.clock()

local function dropItem(player, key: string, all: boolean?): boolean
	local entry = countEntries(player)[key]
	if not entry then
		return false
	end
	local toolName = entry.base
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (rootPart and humanoid) or humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	if now - (lastDropAt[player.UserId] or 0) < 0.1 then
		return false
	end

	local backpackCount, heldCount = 0, 0
	local backpack = player:FindFirstChild("Backpack")
	for _, child in ipairs(backpack and backpack:GetChildren() or {}) do
		if child:IsA("Tool") and child.Name == toolName then
			backpackCount += 1
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child.Name == toolName then
			heldCount += 1
		end
	end
	local owned = backpackCount + heldCount
	if owned == 0 then
		return false
	end

	local amount = all and entry.count or 1
	local custom
	local sample = backpack and backpack:FindFirstChild(toolName) or character:FindFirstChild(toolName)
	if sample and sample:IsA("Tool") then
		custom = sample:GetAttribute("Custom")
	end

	-- RemoveItem only takes Backpack copies: put the held one back first when it has to go
	if heldCount > 0 and (all or backpackCount == 0) then
		humanoid:UnequipTools()
	end
	local removed = InventoryDataManager.RemoveItem(player, key, amount)
	if removed <= 0 then
		return false
	end
	lastDropAt[player.UserId] = now

	local look = rootPart.CFrame.LookVector
	local position = rootPart.Position + look * DROP_FORWARD_OFFSET + Vector3.new(0, 1.5, 0)
	local id = ItemDrops.spawn({
		toolName = toolName,
		count = removed,
		position = position,
		velocity = look * 14 + Vector3.new(0, 14, 0),
		ownerId = player.UserId,
		custom = custom,
	})
	if not id then
		InventoryDataManager.AddItem(player, toolName, removed) -- could not spawn: give it back
		return false
	end
	return true
end

-- ===================== TRASH =====================
--- Delete the whole stack in slot `key` (replacing whatever the trash slot held before).
local function trashItem(player, key: string): boolean
	local entry = countEntries(player)[key]
	if not entry then
		return false -- not owned: nothing to trash
	end
	local toolName = entry.base
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = player:FindFirstChild("Backpack")
	local sample = backpack and backpack:FindFirstChild(toolName) or (character and character:FindFirstChild(toolName))
	local custom = sample and sample:IsA("Tool") and sample:GetAttribute("Custom") or nil
	-- RemoveItem only takes Backpack copies: put the held one back first
	if humanoid then
		humanoid:UnequipTools()
	end
	local removed = InventoryDataManager.RemoveItem(player, key, entry.count)
	if removed <= 0 then
		return false
	end
	trashBin[player.UserId] = { toolName = toolName, count = removed, rarity = entry.rarity, custom = custom }
	InventoryDataManager.SendUpdate(player)
	return true
end

--- Give the trashed stack back (first free slot). Whatever did not fit stays in the trash slot.
local function restoreTrash(player): boolean
	local bin = trashBin[player.UserId]
	if not bin then
		return false
	end
	local added = InventoryDataManager.AddItem(player, bin.toolName, bin.count)
	if added <= 0 then
		return false
	end
	if bin.custom ~= nil then
		local backpack = player:FindFirstChild("Backpack")
		for _, child in ipairs(backpack and backpack:GetChildren() or {}) do
			if child:IsA("Tool") and child.Name == bin.toolName and child:GetAttribute("Custom") == nil then
				child:SetAttribute("Custom", bin.custom)
			end
		end
	end
	if added >= bin.count then
		trashBin[player.UserId] = nil
	else
		bin.count -= added
	end
	InventoryDataManager.SendUpdate(player)
	return true
end

-- ===================== EQUIP / UNEQUIP =====================
local EQUIP_SWITCH_DELAY = 0.18 -- gap between putting the old item away and drawing the new one

--- Draw the item in slot `key`, putting away whatever is in hand first (every switch, even between identical
--- copies, is put away -> short wait -> draw). The newest call wins. Which slot is held is tracked in
--- state.heldKey because copies of an unstackable item share a Tool name.
local function drawKey(player, key: string): boolean
	local state = playerState[player.UserId]
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not state or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if not countEntries(player)[key] then
		return false -- no such slot
	end
	local base = baseOf(key)

	local heldAny = character:FindFirstChildOfClass("Tool") ~= nil
	if heldAny and state.heldKey == key then
		return true -- already in hand
	end

	state.holdTicket = (state.holdTicket or 0) + 1
	local ticket = state.holdTicket
	state.drawing = true

	if heldAny then
		state.heldKey = nil
		humanoid:UnequipTools()
		PlayEquipSound:FireClient(player, "unequip")
		InventoryDataManager.SendUpdate(player)
		task.wait(EQUIP_SWITCH_DELAY)
		if state.holdTicket ~= ticket then
			return false -- a newer selection took over (it owns the drawing flag now)
		end
		if playerState[player.UserId] ~= state or humanoid.Health <= 0 then
			state.drawing = false
			return false
		end
	end

	local backpack = player:FindFirstChild("Backpack")
	for _, child in ipairs(backpack and backpack:GetChildren() or {}) do
		if child:IsA("Tool") and child.Name == base then
			humanoid:EquipTool(child)
			state.heldKey = key
			state.heldAt = os.clock()
			state.drawing = false
			PlayEquipSound:FireClient(player, "equip")
			InventoryDataManager.SendUpdate(player)
			return true
		end
	end
	state.drawing = false
	return false
end

--- Select hotbar slot 1..8. Like Minecraft one slot is always selected: an empty slot means an empty hand.
local function selectSlot(player, slot): boolean
	local state = playerState[player.UserId]
	if not state or type(slot) ~= "number" or slot ~= slot or slot % 1 ~= 0 or slot < 1 or slot > MAX_HOTBAR_SLOTS - 1 then
		return false
	end
	state.selected = slot
	local key = state.hotbarSlots[slot]
	if key then
		local ok = drawKey(player, key)
		InventoryDataManager.SendUpdate(player) -- also reports the new selection when the item was already in hand
		return ok
	end

	-- empty slot: cancel any pending draw and put the held item away
	state.holdTicket = (state.holdTicket or 0) + 1
	state.drawing = false
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and character:FindFirstChildOfClass("Tool") then
		state.heldKey = nil
		humanoid:UnequipTools()
		PlayEquipSound:FireClient(player, "unequip")
	end
	InventoryDataManager.SendUpdate(player)
	return true
end

--- Keep the selected slot's item in hand (spawn, respawn, a new item landing in the selected slot, the held item
--- being removed and another taking its place...). Called after every SendUpdate.
ensureSelectedHeld = function(player)
	local state = playerState[player.UserId]
	if not state or state.drawing or os.clock() - (state.heldAt or 0) < 0.4 then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local key = state.hotbarSlots[state.selected or 1]
	if not key then
		return -- empty hand selected
	end
	if character:FindFirstChildOfClass("Tool") and state.heldKey == key then
		return
	end
	task.spawn(drawKey, player, key)
end

local function equipBySlot(player, slotNumber: number): boolean
	return selectSlot(player, slotNumber)
end

--- By slot key. Only items on the hotbar can be held: tools in the inventory grid must be moved to the hotbar.
local function equipByName(player, key: string): boolean
	local state = playerState[player.UserId]
	if not state then
		return false
	end
	for i = 1, MAX_HOTBAR_SLOTS - 1 do
		if state.hotbarSlots[i] == key then
			return selectSlot(player, i)
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
	local tools = countEntries(player)
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
	local tools = countEntries(player)
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
	local tools = countEntries(player)
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

	-- Save slot maps with string keys: sparse numeric arrays aren't DataStore-safe.
	local function stringKeyed(t)
		local out = {}
		for k, v in pairs(t) do
			out[tostring(k)] = v
		end
		return out
	end

	invData.items = items
	invData.hotbarSlots = stringKeyed(state.hotbarSlots)
	invData.gridSlots = stringKeyed(state.gridSlots)
	invData.toolOrder = state.toolOrder
	invData.nextOrderIndex = state.nextOrderIndex
end

-- ===================== LOAD INVENTORY FROM PROFILE =====================
local function loadInventoryFromProfile(player)
	local invData = SkillsDataManager.GetInventoryData(player)
	if not invData then
		return
	end

	-- Sparse arrays come back from the DataStore with string keys ("2"), so
	-- turn them back into numeric slot indices.
	local function indexed(t)
		local out = {}
		for k, v in pairs(t or {}) do
			local n = tonumber(k)
			if n and type(v) == "string" then
				out[n] = v
			end
		end
		return out
	end

	-- Initialize runtime state
	playerState[player.UserId] = {
		toolOrder = invData.toolOrder or {},
		nextOrderIndex = invData.nextOrderIndex or 1,
		hotbarSlots = indexed(invData.hotbarSlots),
		gridSlots = indexed(invData.gridSlots),
	}

	-- Spawn Tool clones from saved items
	local backpack = player:WaitForChild("Backpack")
	for _, entry in ipairs(invData.items) do
		local toolName = entry.toolName
		local count = math.min(entry.count or 1, MAX_STACK)
		local tool = ItemTools.ensure(toolName)
		if tool then
			for _ = 1, count do
				local clone = tool:Clone()
				clone.Parent = backpack
			end
		else
			warn("[InventoryDataManager] Saved item no longer exists, skipping: " .. tostring(toolName))
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
	task.wait(0.1)

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
		-- a new character holds nothing: draw the selected slot's item again once it has spawned
		local fresh = playerState[player.UserId]
		if fresh then
			fresh.heldKey = nil
			fresh.drawing = false
			fresh.heldAt = nil
		end
		task.delay(0.6, function()
			if playerState[player.UserId] then
				InventoryDataManager.SendUpdate(player)
			end
		end)
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

	-- Start with the first filled hotbar slot selected (slot 1 when the hotbar is empty)
	local st = playerState[player.UserId]
	if st and not st.selected then
		st.selected = 1
		for i = 1, MAX_HOTBAR_SLOTS - 1 do
			if st.hotbarSlots[i] then
				st.selected = i
				break
			end
		end
	end

	-- Send initial updates
	InventoryDataManager.SendUpdate(player)
	task.delay(1, function()
		if playerState[player.UserId] then
			InventoryDataManager.SendUpdate(player) -- the character may not have been ready for the first draw
		end
	end)
	print("[InventoryDataManager] Loaded inventory for " .. player.Name)
end

local function onPlayerLeaving(player)
	saveInventoryToProfile(player) -- no-op if SkillsDataManager already released the profile (its hook saved first)
	playerState[player.UserId] = nil
	trashBin[player.UserId] = nil
	lastDropAt[player.UserId] = nil
end

-- The inventory slice of the profile is only a snapshot of the Tools. Write it before the profile is
-- released (leave) and every AUTOSAVE_SECONDS, so a server crash loses seconds, not the whole session.
local AUTOSAVE_SECONDS = 25
SkillsDataManager.OnBeforeRelease(saveInventoryToProfile)
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			if playerState[player.UserId] then
				local ok, err = pcall(saveInventoryToProfile, player)
				if not ok then
					warn("[InventoryDataManager] autosave failed for " .. player.Name .. ": " .. tostring(err))
				end
			end
		end
	end
end)

-- ===================== WIRE REMOTES =====================
-- Every remote is rate limited (token bucket): a client can burst a few calls, not flood the server.
local allow = RateLimiter.new(24, 12)

EquipToolFunc.OnServerInvoke = function(player, slotNumber)
	if not allow(player) or type(slotNumber) ~= "number" or slotNumber ~= slotNumber then
		return false
	end
	return equipBySlot(player, slotNumber)
end

EquipToolByNameFunc.OnServerInvoke = function(player, toolName)
	if not allow(player) or type(toolName) ~= "string" or #toolName > 100 then
		return false
	end
	return equipByName(player, toolName)
end

SwapItemsFunc.OnServerInvoke = function(player, sourceName, targetName)
	if not allow(player) or type(sourceName) ~= "string" or type(targetName) ~= "string" then
		return false
	end
	return swapItems(player, sourceName, targetName)
end

AssignHotbarFunc.OnServerInvoke = function(player, slotIndex, toolName)
	if not allow(player) or type(slotIndex) ~= "number" or type(toolName) ~= "string" then
		return false
	end
	return assignHotbar(player, slotIndex, toolName)
end

AssignGridSlotFunc.OnServerInvoke = function(player, gridIndex, toolName)
	if not allow(player) or type(gridIndex) ~= "number" or type(toolName) ~= "string" then
		return false
	end
	return assignGridSlot(player, gridIndex, toolName)
end

DropItemFunc.OnServerInvoke = function(player, toolName, all)
	if not allow(player) or type(toolName) ~= "string" or (all ~= nil and type(all) ~= "boolean") then
		return false
	end
	return dropItem(player, toolName, all)
end

-- Picked-up drops go through the normal AddItem path (first free slot, capacity and stack limits)
ItemDrops.setGrantHandler(function(player, toolName, count)
	return InventoryDataManager.AddItem(player, toolName, count)
end)

-- The client asks for its inventory once its listener is connected (the first push at join can arrive before
-- the client script has finished loading and would otherwise be lost)
RequestInventoryEvent.OnServerEvent:Connect(function(player)
	if allow(player) then
		InventoryDataManager.SendUpdate(player)
	end
end)

TrashItemFunc.OnServerInvoke = function(player, key)
	if not allow(player) or type(key) ~= "string" or #key > 100 then
		return false
	end
	return trashItem(player, key)
end

RestoreTrashFunc.OnServerInvoke = function(player)
	if not allow(player) then
		return false
	end
	return restoreTrash(player)
end

MoveToEndFunc.OnServerInvoke = function(player, toolName)
	if not allow(player) or type(toolName) ~= "string" then
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
