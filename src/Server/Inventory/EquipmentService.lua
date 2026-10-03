--[[
	EquipmentService (ModuleScript, Server)
	Place inside: ServerScriptService

	Server-authoritative armor / accessory equipping.

	  - Equipping takes the item out of the inventory (its Tool is removed) and
	    puts the item id in the slot. If the slot is full the old piece goes
	    back to the inventory (swap).
	  - Unequipping puts the Tool back in the inventory.
	  - Equipped state lives in the inventory profile (ProfileService):
	    SkillsDataManager.GetInventoryData(player).equippedSlots = { Helmet = "iron_helmet" }
	  - Whenever it changes, the equipped items' `stats` are pushed into the
	    player's attributes via AttributeStatManager.ApplyEquipment.

	API:
	  EquipmentService.Equip(player, itemId, slotId?) -> ok, errorMessage?
	  EquipmentService.Unequip(player, slotId)        -> ok, errorMessage?
	  EquipmentService.GetEquipped(player)            -> { [slotId] = itemId }
	  EquipmentService.ClearAll(player)               -> returns everything to the inventory

	Remotes (created here):
	  EquipItem        RemoteFunction (slotId, itemId) -> ok
	  UnequipItem      RemoteFunction (slotId)         -> ok
	  GetEquipped      RemoteFunction ()               -> { [slotId] = itemId }
	  UpdateEquipped   RemoteEvent    (equipped)  server -> client
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Items = require(Modules:WaitForChild("Items")) :: any
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
local InventoryDataManager = require(ServerScriptService:WaitForChild("InventoryDataManager")) :: any

local EquipmentService = {}

-- ===================== REMOTES =====================
local function ensureRemote(className: string, name: string)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	local remote = Instance.new(className)
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
end

local EquipItemFunc = ensureRemote("RemoteFunction", "EquipItem")
local UnequipItemFunc = ensureRemote("RemoteFunction", "UnequipItem")
local GetEquippedFunc = ensureRemote("RemoteFunction", "GetEquipped")
local UpdateEquippedEvent = ensureRemote("RemoteEvent", "UpdateEquipped")

-- ===================== DATA =====================
local function getSlots(player): { [string]: string }?
	local inv = SkillsDataManager.GetInventoryData(player)
	if not inv then
		return nil
	end
	if type(inv.equippedSlots) ~= "table" then
		inv.equippedSlots = {}
	end
	return inv.equippedSlots
end

function EquipmentService.GetEquipped(player): { [string]: string }
	return getSlots(player) or {}
end

local function snapshot(equipped: { [string]: string }): { [string]: string }
	local copy = {}
	for slotId, itemId in pairs(equipped) do
		copy[slotId] = itemId
	end
	return copy
end

-- ===================== STATS =====================
local function applyStats(player)
	local equipped = getSlots(player)
	if not equipped or not AttributeStatManager.IsLoaded(player) then
		return
	end

	local entries = {}
	for _, slotId in ipairs(Items.Slots.Order) do
		local itemId = equipped[slotId]
		local def = itemId and Items.get(itemId)
		if def then
			local flat, mult = Items.Stats.split(def.stats)
			table.insert(entries, {
				slotId = slotId,
				itemId = def.id,
				sourceType = "equipment",
				label = def.displayName,
				color = Items.getRarity(def.rarity).hexColor,
				flat = flat,
				mult = mult,
			})
		end
	end
	AttributeStatManager.ApplyEquipment(player, entries)
end

local function push(player)
	local equipped = getSlots(player)
	if equipped then
		UpdateEquippedEvent:FireClient(player, snapshot(equipped))
	end
end

-- ===================== EQUIP / UNEQUIP =====================
--- Returns the Tool-name to inventory-count conversion helper result.
local function hasInInventory(player, toolName: string): boolean
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child.Name == toolName then
					return true
				end
			end
		end
	end
	return false
end

function EquipmentService.Unequip(player, slotId: string): (boolean, string?)
	local equipped = getSlots(player)
	if not equipped then
		return false, "Data not loaded"
	end
	local itemId = equipped[slotId]
	if not itemId then
		return false, "Nothing equipped"
	end

	local def = Items.get(itemId)
	if def then
		local added = InventoryDataManager.AddItem(player, def.toolName, 1)
		if added < 1 then
			return false, "Inventory full"
		end
	end

	equipped[slotId] = nil
	applyStats(player)
	push(player)
	return true
end

function EquipmentService.Equip(player, itemId: string, slotId: string?): (boolean, string?)
	local equipped = getSlots(player)
	if not equipped then
		return false, "Data not loaded"
	end

	local def = Items.get(itemId)
	if not def or not def.slot then
		return false, "Not equippable"
	end
	if slotId and slotId ~= def.slot then
		return false, "Wrong slot"
	end
	local slot = def.slot

	if not hasInInventory(player, def.toolName) then
		return false, "Item not in inventory"
	end

	-- Take the new piece out of the inventory first so a full inventory
	-- still has room for the piece it replaces.
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:UnequipTools() -- if it was in hand, move it to the backpack
	end
	if InventoryDataManager.RemoveItem(player, def.toolName, 1) < 1 then
		return false, "Could not remove item"
	end

	local previous = equipped[slot]
	if previous then
		local prevDef = Items.get(previous)
		if prevDef then
			InventoryDataManager.AddItem(player, prevDef.toolName, 1)
		end
	end

	equipped[slot] = itemId
	applyStats(player)
	push(player)
	return true
end

function EquipmentService.ClearAll(player)
	local equipped = getSlots(player)
	if not equipped then
		return
	end
	for _, slotId in ipairs(Items.Slots.Order) do
		if equipped[slotId] then
			EquipmentService.Unequip(player, slotId)
		end
	end
end

-- ===================== REMOTES =====================
EquipItemFunc.OnServerInvoke = function(player, slotId, itemId)
	if type(itemId) ~= "string" or (slotId ~= nil and type(slotId) ~= "string") then
		return false
	end
	return (EquipmentService.Equip(player, itemId, slotId))
end

UnequipItemFunc.OnServerInvoke = function(player, slotId)
	if type(slotId) ~= "string" or not Items.Slots.exists(slotId) then
		return false
	end
	return (EquipmentService.Unequip(player, slotId))
end

GetEquippedFunc.OnServerInvoke = function(player)
	local attempts = 0
	while not SkillsDataManager.IsLoaded(player) and attempts < 40 do
		task.wait(0.25)
		attempts += 1
	end
	return snapshot(EquipmentService.GetEquipped(player))
end

-- Clicking an armor / accessory in the inventory routes here.
InventoryDataManager.SetEquipHandler(function(player, def)
	return (EquipmentService.Equip(player, def.id, def.slot))
end)

-- ===================== PLAYER LIFECYCLE =====================
local function onPlayer(player)
	local waited = 0
	while
		(not SkillsDataManager.IsLoaded(player) or not AttributeStatManager.IsLoaded(player))
		and waited < 60
		and player.Parent
	do
		task.wait(0.25)
		waited += 0.25
	end
	if not player.Parent or not SkillsDataManager.IsLoaded(player) then
		return
	end

	-- Drop ids that no longer exist (renamed / removed items) instead of crashing on them.
	local equipped = getSlots(player)
	if equipped then
		for slotId, itemId in pairs(equipped) do
			local def = Items.get(itemId)
			if not def or def.slot ~= slotId then
				warn(string.format("[EquipmentService] dropping invalid %s=%s for %s", slotId, tostring(itemId), player.Name))
				equipped[slotId] = nil
			end
		end
	end

	applyStats(player)
	push(player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(onPlayer, player)
end)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, player)
end

print("[EquipmentService] Loaded ✓")
return EquipmentService
