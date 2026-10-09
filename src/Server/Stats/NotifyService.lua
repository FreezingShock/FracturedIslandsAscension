--[[
	NotifyService (ModuleScript, Server)
	Place inside: ServerScriptService

	Sends NOTIFICATION CARDS to a player (the bottom-left stack, NotificationController on the client, look and timings in
	Modules/Config/NotificationConfig). Server-authoritative: the client only displays and sends nothing. One RemoteEvent "Notify"
	(server -> client) carries a list of payloads; sends are batched per frame-ish (FLUSH seconds) so a burst is one message.

	  NotifyService.pickup(player, key, label, amount, colorHex?, icon?)   "+3 Rotten Flesh"; same key while showing merges (x2, x3 ...)
	  NotifyService.system(player, text, colorHex?, sub?, key?)             "Your inventory is full!"; the same key while showing stacks (x2, x3 ...)
	  NotifyService.levelUp(player, skill, from, to, rewardList)           SKILL LEVEL UP card
	  NotifyService.collection(player, skill, name, from, to, rewardList)  COLLECTION TIER UP card
	  NotifyService.describeRewards(entries)                                [{ reward, ctx }] -> [{ text, color }] through CollectionRewards.describe

	Called from: InventoryDataManager.AddItem, WalletService.add and LootService (item / stat / Coins gains), LootService (inventory full), SkillRewardService and
	CollectionService (level / tier ups).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CollectionRewards = require(Modules:WaitForChild("CollectionRewards")) :: any

local NotifyService = {}

local FLUSH = 0.1
local MAX_BATCH = 40

local remote = ReplicatedStorage:FindFirstChild("Notify")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Notify"
	remote.Parent = ReplicatedStorage
end

local pending: { [Player]: { any } } = {}

local function queue(player: Player, payload: any)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local list = pending[player]
	if not list then
		list = {}
		pending[player] = list
	end
	if #list < MAX_BATCH then
		table.insert(list, payload)
	end
end

local function isHex(value: any): boolean
	return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

function NotifyService.pickup(player: Player, key: string, label: string, amount: number, color: string?, icon: string?)
	if type(key) ~= "string" or type(label) ~= "string" or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	queue(player, { kind = "pickup", key = key, label = label, amount = amount, color = isHex(color) and color or nil, icon = icon })
end

function NotifyService.system(player: Player, text: string, color: string?, sub: string?, key: string?)
	if type(text) ~= "string" then
		return
	end
	queue(player, { kind = "system", text = text, color = isHex(color) and color or nil, sub = type(sub) == "string" and sub or nil, key = type(key) == "string" and key or nil })
end

--- [{ reward, ctx }] -> [{ text, color }]: one plain line per reward, from the same describe() the reward pages use.
function NotifyService.describeRewards(entries: { any }): { any }
	local lines = {}
	for _, entry in ipairs(entries) do
		local d = CollectionRewards.describe(entry.reward, entry.ctx)
		local short = tostring(d.short or "")
		local name = tostring(d.name or "")
		local text
		if short:sub(1, 1) == "+" then
			text = short .. " " .. name -- "+4 Defense"
		elseif short:sub(1, 1) == "x" then
			text = name .. " " .. short -- "Oak Plank x3"
		else
			text = name -- "Recipe Zombie Brew", "Slime Cave unlocked"
		end
		table.insert(lines, { text = text, color = isHex(d.color) and d.color or "#FFFFFF" })
	end
	return lines
end

function NotifyService.levelUp(player: Player, skill: string, from: number, to: number, rewards: { any })
	if type(skill) ~= "string" or type(from) ~= "number" or type(to) ~= "number" then
		return
	end
	queue(player, { kind = "levelup", skill = skill, from = from, to = to, rewards = rewards })
end

function NotifyService.collection(player: Player, skill: string, name: string, from: number, to: number, rewards: { any })
	if type(name) ~= "string" or type(from) ~= "number" or type(to) ~= "number" then
		return
	end
	queue(player, { kind = "collection", skill = skill, name = name, from = from, to = to, rewards = rewards })
end

task.spawn(function()
	while true do
		task.wait(FLUSH)
		for player, list in pairs(pending) do
			pending[player] = nil
			if player.Parent == Players and #list > 0 then
				remote:FireClient(player, list)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	pending[player] = nil
end)

return NotifyService
