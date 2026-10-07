--[[
	GainFeedService (ModuleScript, Server)
	Place inside: ServerScriptService

	Tells a player what they just gained, for the J "Recently gained" foldable (GainFeedController, client). Server-authoritative:
	the client only displays. Gains are buffered per player and sent as ONE batch every FLUSH seconds, so a source that fires
	10 times a second costs one small message, not ten.

	  GainFeedService.Push(player, key, label, amount, colorHex?)
	      key    the grouping key (same key = one summed row), e.g. "xp:Combat", "coins", "item:Oak Wood"
	      label  what the row calls it ("Combat XP", "Coins", "Oak Wood")
	      amount a positive number
	  Remote "GainFeed" (RemoteEvent, server -> client): a list of { key, label, amount, color }.

	Every non-XP gain is also sent to NotifyService.pickup (a notification card replaces the old "You picked up" chat line).

	Called from: SkillsDataManager.AddXP, WalletService.add, InventoryDataManager.AddItem, LootService (stat drops).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NotifyService = require(script.Parent:WaitForChild("NotifyService")) :: any

local GainFeedService = {}

local FLUSH = 0.25
local MAX_BATCH = 30

local remote = ReplicatedStorage:FindFirstChild("GainFeed")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "GainFeed"
	remote.Parent = ReplicatedStorage
end

local pending: { [Player]: { any } } = {}

function GainFeedService.Push(player: Player, key: string, label: string, amount: number, color: string?)
	if typeof(player) ~= "Instance" or type(key) ~= "string" or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	if not key:match("^xp:") then -- XP has the action bar; everything else also gets a notification card
		NotifyService.pickup(player, key, label, amount, color)
	end
	local list = pending[player]
	if not list then
		list = {}
		pending[player] = list
	end
	for _, entry in ipairs(list) do
		if entry.key == key then
			entry.amount += amount
			return
		end
	end
	if #list < MAX_BATCH then
		table.insert(list, { key = key, label = label, amount = amount, color = color })
	end
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

return GainFeedService
