-- ============================================================
--  InventoryTestCommands (Script)
--  Place inside: ServerScriptService
--
--  Admin-only chat commands for testing the inventory system.
--  Uses InventoryDataManager.AddItem() so everything goes
--  through the proper pipeline.
--
--  Commands (type in Roblox chat):
--    /give <itemId> [count]   — give yourself items by registry id
--    /give all                — give 1 of every registered item
--    /give all <count>        — give <count> of every item
--    /clear                   — remove ALL items from your inventory
--    /cap <number>            — set your max inventory capacity
--
--  Examples:
--    /give coal_terrafruit 10
--    /give rarity_test_5 3
--    /give all 5
--    /clear
--    /cap 500
-- ============================================================

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryDataManager = require(ServerScriptService:WaitForChild("InventoryDataManager")) :: any
local ItemRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemRegistry")) :: any
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any

-- ===================== CONFIG =====================
local ADMIN_IDS = { 288851273 } -- your Roblox user ID

local function isAdmin(player)
	for _, id in ipairs(ADMIN_IDS) do
		if player.UserId == id then
			return true
		end
	end
	return false
end

-- ===================== ENSURE TOOLS EXIST IN SERVERSTORAGE =====================
-- Auto-create Tool instances for every ItemRegistry entry that has a toolName.
-- This way you don't need to manually build them in Studio for testing.
-- Each tool gets the Rarity attribute set so the existing system picks it up.

local function ensureToolsExist()
	local created = 0
	for id, config in pairs(ItemRegistry.Items) do
		local toolName = config.toolName
		if toolName and toolName ~= "" then
			local existing = ServerStorage:FindFirstChild(toolName)
			if not existing then
				local tool = Instance.new("Tool")
				tool.Name = toolName
				tool.CanBeDropped = true
				tool.RequiresHandle = false -- no handle needed for testing
				tool:SetAttribute("Rarity", config.rarity or 0)
				tool.Parent = ServerStorage
				created = created + 1
			else
				-- Ensure rarity attribute is correct
				existing:SetAttribute("Rarity", config.rarity or 0)
			end
		end
	end
	if created > 0 then
		print("[InventoryTestCommands] Auto-created " .. created .. " Tool instances in ServerStorage")
	end
end

ensureToolsExist()

-- ===================== COMMAND HANDLERS =====================

local function handleGive(player, args)
	local itemIdOrAll = args[1]
	if not itemIdOrAll then
		warn("[TestCmd] Usage: /give <itemId> [count] OR /give all [count]")
		return
	end

	if itemIdOrAll == "all" then
		local count = tonumber(args[2]) or 1
		local given = 0
		for id, config in pairs(ItemRegistry.Items) do
			if config.toolName and config.toolName ~= "" then
				local added = InventoryDataManager.AddItem(player, config.toolName, count)
				given = given + added
			end
		end
		print("[TestCmd] Gave " .. player.Name .. " " .. given .. " total items (all types, " .. count .. "x each)")
		return
	end

	-- Specific item
	local config = ItemRegistry.get(itemIdOrAll)
	if not config then
		warn("[TestCmd] Unknown itemId: '" .. itemIdOrAll .. "'. Check ItemRegistry.Items keys.")
		-- List available ids
		local ids = {}
		for id in pairs(ItemRegistry.Items) do
			table.insert(ids, id)
		end
		table.sort(ids)
		warn("[TestCmd] Available: " .. table.concat(ids, ", "))
		return
	end

	local count = tonumber(args[2]) or 1
	local toolName = config.toolName
	if not toolName or toolName == "" then
		warn("[TestCmd] Item '" .. itemIdOrAll .. "' has no toolName set")
		return
	end

	local added = InventoryDataManager.AddItem(player, toolName, count)
	print("[TestCmd] Gave " .. player.Name .. " " .. added .. "x " .. config.displayName .. " (" .. itemIdOrAll .. ")")
end

local function handleClear(player)
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end
	if player.Character then
		for _, child in ipairs(player.Character:GetChildren()) do
			if child:IsA("Tool") then
				child:Destroy()
			end
		end
	end
	-- Clear hotbar assignments
	local invData = SkillsDataManager.GetInventoryData(player)
	if invData then
		invData.hotbarSlots = {}
	end
	InventoryDataManager.SendUpdate(player)
	print("[TestCmd] Cleared all items for " .. player.Name)
end

local function handleCap(player, args)
	local newCap = tonumber(args[1])
	if not newCap or newCap < 1 then
		warn("[TestCmd] Usage: /cap <number>")
		return
	end
	local invData = SkillsDataManager.GetInventoryData(player)
	if invData then
		invData.maxCapacity = newCap
		InventoryDataManager.SendUpdate(player)
		print("[TestCmd] Set " .. player.Name .. "'s max capacity to " .. newCap)
	end
end

-- ===================== CHAT LISTENER =====================
local function onPlayerChatted(player, message)
	if not isAdmin(player) then
		return
	end

	local parts = {}
	for word in message:gmatch("%S+") do
		table.insert(parts, word)
	end

	local cmd = parts[1]
	if not cmd then
		return
	end

	local args = {}
	for i = 2, #parts do
		table.insert(args, parts[i])
	end

	if cmd == "/give" then
		handleGive(player, args)
	elseif cmd == "/clear" then
		handleClear(player)
	elseif cmd == "/cap" then
		handleCap(player, args)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(message)
		onPlayerChatted(player, message)
	end)
end)

-- Handle players already in game (Studio)
for _, player in ipairs(Players:GetPlayers()) do
	player.Chatted:Connect(function(message)
		onPlayerChatted(player, message)
	end)
end

print("[InventoryTestCommands] Loaded ✓")
