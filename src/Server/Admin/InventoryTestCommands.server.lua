-- ============================================================
--  InventoryTestCommands (Script)
--  Place inside: ServerScriptService
--
--  Admin slash commands. They work from the chat box (Chatted) and from
--  AdminCommandEvent (the in-game command bar). Everything goes through the
--  normal systems (InventoryDataManager, EquipmentService, AttributeStatManager).
--
--  ADD A COMMAND: add one entry to COMMANDS below. `usage` + `help` feed /help
--  automatically; `aliases` are extra names for the same command.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryDataManager = require(ServerScriptService:WaitForChild("InventoryDataManager")) :: any
local EquipmentService = require(ServerScriptService:WaitForChild("EquipmentService")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
local StatisticsDataManager = require(ServerScriptService:WaitForChild("StatisticsDataManager")) :: any
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Items = require(Modules:WaitForChild("Items")) :: any
local Attributes = require(Modules:WaitForChild("Attributes")) :: any
local AdminConfig = require(Modules:WaitForChild("AdminConfig")) :: any
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any

-- ===================== CONFIG =====================
local isAdmin = AdminConfig.isAdmin -- admin ids live in AdminConfig

local CATEGORIES = { weapon = true, armor = true, accessory = true, material = true, consumable = true, misc = true }

local function say(player, text: string)
	print(string.format("[Cmd:%s] %s", player.Name, text))
end

local function findAttribute(player, name: string?)
	local def = name and Attributes.find(name)
	if not def then
		say(player, "Unknown attribute '" .. tostring(name) .. "'. Try /stats for the list.")
	end
	return def
end

--- Give `count` of an item definition. Returns how many were added.
local function giveItem(player, def, count: number): number
	return InventoryDataManager.AddItem(player, def.toolName, count)
end

-- ===================== COMMANDS =====================
local COMMANDS: { [string]: any } = {}

COMMANDS.give = {
	usage = "/give <itemId|category|all> [count]",
	help = "Give items. Category: weapon, armor, accessory, material, consumable, misc.",
	aliases = { "item" },
	run = function(player, args)
		local target, count = args[1], tonumber(args[2]) or 1
		if not target then
			return say(player, "Usage: " .. COMMANDS.give.usage)
		end
		if target == "all" or CATEGORIES[target] then
			local given = 0
			for _, def in ipairs(Items.list(target ~= "all" and target or nil)) do
				given += InventoryDataManager.AddItem(player, def.toolName, count)
			end
			return say(player, string.format("Gave %d items (%s, %dx each)", given, target, count))
		end
		local def = Items.get(target)
		if not def then
			return say(player, "Unknown item '" .. target .. "'. Use /items to list ids.")
		end
		local added = giveItem(player, def, count)
		say(player, string.format("Gave %dx %s (%s)", added, def.displayName, def.id))
	end,
}

COMMANDS.items = {
	usage = "/items [category]",
	help = "List item ids.",
	run = function(player, args)
		local lines = {}
		for _, def in ipairs(Items.list(args[1])) do
			table.insert(lines, string.format("  %-20s %-10s r%d %s", def.id, def.category, def.rarity, def.slot or ""))
		end
		say(player, "Items (" .. #lines .. "):\n" .. table.concat(lines, "\n"))
	end,
}

COMMANDS.equip = {
	usage = "/equip <armor/accessory itemId>",
	help = "Give the item and equip it.",
	run = function(player, args)
		local def = args[1] and Items.get(args[1])
		if not def or not def.slot then
			return say(player, "Usage: " .. COMMANDS.equip.usage)
		end
		if InventoryDataManager.AddItem(player, def.toolName, 1) < 1 then
			return say(player, "Could not add the item (inventory full?)")
		end
		local ok, err = EquipmentService.Equip(player, def.id, def.slot)
		say(player, ok and ("Equipped " .. def.displayName) or ("Equip failed: " .. tostring(err)))
	end,
}

COMMANDS.unequip = {
	usage = "/unequip <slot|all>",
	help = "Take armor / accessories off (slots: " .. table.concat(Items.Slots.Order, ", ") .. ").",
	run = function(player, args)
		local slot = args[1]
		if slot == "all" then
			EquipmentService.ClearAll(player)
			return say(player, "Unequipped everything")
		end
		if slot and Items.Slots.exists(slot) then
			local ok, err = EquipmentService.Unequip(player, slot)
			return say(player, ok and ("Unequipped " .. slot) or ("Unequip failed: " .. tostring(err)))
		end
		say(player, "Usage: " .. COMMANDS.unequip.usage)
	end,
}

COMMANDS.set = {
	usage = "/set <attribute> <amount>",
	help = "Set a debug flat bonus on an attribute (shows as 'Admin' in its breakdown).",
	run = function(player, args)
		local def, amount = findAttribute(player, args[1]), tonumber(args[2])
		if not def or not amount then
			return def and say(player, "Usage: " .. COMMANDS.set.usage)
		end
		AttributeStatManager.SetAdminBoost(player, def.key, amount)
		say(player, string.format("%s admin bonus = %s", def.name, Attributes.format(def.key, amount)))
	end,
}

COMMANDS.add = {
	usage = "/add <attribute> <amount>",
	help = "Add to the debug flat bonus on an attribute (negative numbers work).",
	run = function(player, args)
		local def, amount = findAttribute(player, args[1]), tonumber(args[2])
		if not def or not amount then
			return def and say(player, "Usage: " .. COMMANDS.add.usage)
		end
		local total = AttributeStatManager.GetAdminBoost(player, def.key) + amount
		AttributeStatManager.SetAdminBoost(player, def.key, total)
		say(player, string.format("%s admin bonus = %s", def.name, Attributes.format(def.key, total)))
	end,
}

COMMANDS.stats = {
	usage = "/stats [attribute]",
	help = "Print an attribute's breakdown, or every attribute that isn't zero.",
	run = function(player, args)
		local function describe(def, detailed)
			local raw = AttributeStatManager.GetAttributeBreakdown(player, def.key)
			if not raw then
				return nil
			end
			local bd = Attributes.breakdown(def.key, {
				base = raw.baseValue,
				final = raw.finalValue,
				flatBoosts = raw.flatBoosts,
				multipliers = raw.multipliers,
			})
			local line = string.format("%s = %s", def.name, Attributes.format(def.key, bd.final))
			if detailed then
				for _, source in ipairs(bd.sources) do
					line ..= string.format("\n    %s  %s", source.label, Attributes.amountText(def.key, source))
				end
			end
			return line, bd
		end

		if args[1] then
			local def = findAttribute(player, args[1])
			if def then
				say(player, (describe(def, true)))
			end
			return
		end
		local lines = {}
		for _, def in pairs(Attributes.all()) do
			local line, bd = describe(def, false)
			if line and (bd.final ~= 0 or bd.base ~= 0) then
				table.insert(lines, line)
			end
		end
		table.sort(lines)
		say(player, "Attributes:\n  " .. table.concat(lines, "\n  "))
	end,
}

COMMANDS.reset = {
	usage = "/reset [stats|items|all]",
	help = "stats (default): clear /set and /add bonuses. items: remove all items. all: both.",
	run = function(player, args)
		local what = args[1] or "stats"
		if what == "stats" or what == "all" then
			AttributeStatManager.ClearAdminBoosts(player)
		end
		if what == "items" or what == "all" then
			EquipmentService.ClearAll(player)
			for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character }) do
				if container then
					for _, child in ipairs(container:GetChildren()) do
						if child:IsA("Tool") then
							child:Destroy()
						end
					end
				end
			end
			local invData = SkillsDataManager.GetInventoryData(player)
			if invData then
				invData.hotbarSlots = {}
			end
			InventoryDataManager.EnsurePinned(player) -- the Nexus Star always comes back
			InventoryDataManager.SendUpdate(player)
		end
		say(player, "Reset " .. what)
	end,
}

COMMANDS.clear = {
	usage = "/clear",
	help = "Same as /reset items.",
	run = function(player)
		COMMANDS.reset.run(player, { "items" })
	end,
}

COMMANDS.cap = {
	usage = "/cap <number>",
	help = "Set your max inventory capacity.",
	run = function(player, args)
		local newCap = tonumber(args[1])
		if not newCap or newCap < 1 then
			return say(player, "Usage: " .. COMMANDS.cap.usage)
		end
		local invData = SkillsDataManager.GetInventoryData(player)
		if invData then
			invData.maxCapacity = newCap
			InventoryDataManager.SendUpdate(player)
			say(player, "Max capacity = " .. newCap)
		end
	end,
}

COMMANDS.help = {
	usage = "/help",
	help = "List all commands.",
	run = function(player)
		local names = {}
		for name in pairs(COMMANDS) do
			table.insert(names, name)
		end
		table.sort(names)
		local lines = {}
		for _, name in ipairs(names) do
			local c = COMMANDS[name]
			table.insert(lines, string.format("  %-34s %s", c.usage, c.help))
		end
		say(player, "Commands:\n" .. table.concat(lines, "\n"))
	end,
}

-- alias -> command
local ALIASES = {}
for name, command in pairs(COMMANDS) do
	for _, alias in ipairs(command.aliases or {}) do
		ALIASES[alias] = name
	end
end

local function run(player, cmd: string, args)
	if not isAdmin(player) then
		return
	end
	local command = COMMANDS[cmd] or COMMANDS[ALIASES[cmd]]
	if not command then
		return say(player, "Unknown command '/" .. cmd .. "'. Try /help")
	end
	local ok, err = pcall(command.run, player, args or {})
	if not ok then
		warn("[Cmd] /" .. cmd .. " failed: " .. tostring(err))
	end
end

-- ===================== CHAT LISTENER =====================
local function hook(player)
	player.Chatted:Connect(function(message)
		local cmd, rest = message:match("^/(%S+)%s*(.*)$")
		if not cmd then
			return
		end
		local args = {}
		for word in rest:gmatch("%S+") do
			table.insert(args, word)
		end
		run(player, cmd:lower(), args)
	end)
end

Players.PlayerAdded:Connect(hook)
for _, player in ipairs(Players:GetPlayers()) do
	hook(player)
end

-- ===================== REMOTE COMMAND LISTENER =====================
task.spawn(function()
	local event = ReplicatedStorage:WaitForChild("AdminCommandEvent", 15)
	if not event then
		warn("[InventoryTestCommands] AdminCommandEvent not found; chat commands only")
		return
	end
	event.OnServerEvent:Connect(function(player, cmd, args)
		if type(cmd) == "string" and (args == nil or type(args) == "table") then
			run(player, cmd:lower(), args)
		end
	end)
end)

-- ===================== ADMIN PANEL REMOTE =====================
-- One RemoteFunction for the Nexus admin panel. Every call re-checks the admin id
-- and validates its inputs against config; the client is never trusted.
local ACTIONS: { [string]: (any, any) -> (boolean, string, any?) } = {}

local function wholeNumber(value: any, min: number, max: number): number?
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return nil
	end
	return math.clamp(math.floor(value), min, max)
end

local function realNumber(value: any, limit: number): number?
	if type(value) ~= "number" or value ~= value or math.abs(value) > limit then
		return nil
	end
	return value
end

local VALID_SKILL = {}
for _, skill in ipairs(StatisticsConfig.SKILL_NAMES) do
	VALID_SKILL[skill] = true
end

ACTIONS.give = function(player, p)
	local def = type(p.itemId) == "string" and Items.get(p.itemId)
	local count = wholeNumber(p.count, 1, AdminConfig.MAX_GIVE)
	if not def or not count then
		return false, "Unknown item or bad count"
	end
	local added = giveItem(player, def, count)
	return added > 0, string.format("Gave %dx %s", added, def.displayName)
end

ACTIONS.setStat = function(player, p)
	local count = wholeNumber(p.count, 0, AdminConfig.MAX_STAT)
	if type(p.skill) ~= "string" or not VALID_SKILL[p.skill] or type(p.key) ~= "string" or not count then
		return false, "Bad stat or amount"
	end
	local ok, reason = StatisticsDataManager.AdminSetCount(player, p.skill, p.key, count)
	return ok, ok and string.format("%s.%s = %d", p.skill, p.key, count) or tostring(reason)
end

ACTIONS.maxStats = function(player)
	local ok, reason = StatisticsDataManager.AdminSetAll(player, AdminConfig.MAX_STAT)
	return ok, ok and "All statistics maxed" or tostring(reason)
end

ACTIONS.restoreStats = function(player)
	local ok, reason = StatisticsDataManager.AdminRestore(player)
	return ok, ok and "Statistics restored" or tostring(reason)
end

ACTIONS.addBonus = function(player, p)
	local def = type(p.attr) == "string" and Attributes.get(p.attr)
	local amount = realNumber(p.amount, AdminConfig.MAX_BONUS_AMOUNT)
	local duration = wholeNumber(p.duration, 0, AdminConfig.MAX_BONUS_DURATION)
	if not def or not amount or not duration or amount == 0 then
		return false, "Bad attribute, amount or duration"
	end
	local id, reason = AttributeStatManager.AddTempBonus(player, def.key, p.mode, amount, duration)
	return id ~= nil, id and string.format("%s %s%s", def.name, p.mode == "pct" and "+" or "", amount) or tostring(reason)
end

ACTIONS.removeBonus = function(player, p)
	local ok = type(p.id) == "string" and AttributeStatManager.RemoveTempBonus(player, p.id)
	return ok, ok and "Bonus removed" or "No such bonus"
end

ACTIONS.listBonuses = function(player)
	return true, "ok", AttributeStatManager.ListTempBonuses(player)
end

ACTIONS.clearBonuses = function(player)
	AttributeStatManager.ClearTempBonuses(player)
	AttributeStatManager.ClearAdminBoosts(player)
	return true, "All bonuses cleared"
end

ACTIONS.clearItems = function(player)
	COMMANDS.clear.run(player)
	return true, "Inventory cleared"
end

ACTIONS.setCap = function(player, p)
	local cap = wholeNumber(p.cap, 1, 1000000)
	if not cap then
		return false, "Bad capacity"
	end
	COMMANDS.cap.run(player, { tostring(cap) })
	return true, "Max capacity = " .. cap
end

local AdminAction = ReplicatedStorage:FindFirstChild("AdminAction")
if not AdminAction then
	AdminAction = Instance.new("RemoteFunction")
	AdminAction.Name = "AdminAction"
	AdminAction.Parent = ReplicatedStorage
end

AdminAction.OnServerInvoke = function(player, action, payload)
	if not isAdmin(player) then
		warn(string.format("[AdminAction] %s (%d) is not an admin", player.Name, player.UserId))
		return { ok = false, msg = "Not authorized" }
	end
	local handler = type(action) == "string" and ACTIONS[action]
	if not handler or (payload ~= nil and type(payload) ~= "table") then
		return { ok = false, msg = "Unknown action" }
	end
	local success, ok, msg, data = pcall(handler, player, payload or {})
	if not success then
		warn("[AdminAction] " .. action .. " failed: " .. tostring(ok))
		return { ok = false, msg = "Server error" }
	end
	return { ok = ok, msg = msg, data = data }
end

print("[InventoryTestCommands] Loaded ✓ (/help lists commands; AdminAction remote ready)")
