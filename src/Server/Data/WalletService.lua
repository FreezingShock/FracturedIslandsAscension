--[[
	WalletService (ModuleScript, Server)
	Place inside: ServerScriptService

	The purse: Coins, the REAL money of the game, completely separate from the Statistics. Saved in the player's profile under
	_Wallet = { coins = 0 } (SkillsDataManager's PROFILE_TEMPLATE; Reconcile backfills existing players).

	  WalletService.get(player)                      -> number (0 when not loaded)
	  WalletService.add(player, amount, source?)     -> the amount added (positive integers only); `source` is a free label
	                                                    (see CoinsConfig.sources)
	  WalletService.spend(player, amount)            -> true if the player had it and it was taken, false otherwise (never negative)

	The client never sends an amount: it only reads. The balance is mirrored to the player attribute `Coins` (the scoreboard's
	Purse line reads it) and the RemoteEvent `Wallet` fires (coins, delta) for the purse flash. Gains also show as a pickup notification (NotifyService).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
local NotifyService = require(ServerScriptService:WaitForChild("NotifyService")) :: any
local CoinsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("CoinsConfig")) :: any

local WalletService = {}

local MAX_COINS = 2 ^ 50

local remote = ReplicatedStorage:FindFirstChild("Wallet")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "Wallet"
	remote.Parent = ReplicatedStorage
end

local function wallet(player: Player): any?
	local data = SkillsDataManager.GetData(player)
	if not data then
		return nil
	end
	if type(data._Wallet) ~= "table" then
		data._Wallet = { coins = 0 }
	end
	return data._Wallet
end

local function publish(player: Player, delta: number)
	local w = wallet(player)
	local coins = w and w.coins or 0
	player:SetAttribute("Coins", coins)
	remote:FireClient(player, coins, delta)
end

function WalletService.get(player: Player): number
	local w = wallet(player)
	return w and w.coins or 0
end

function WalletService.add(player: Player, amount: number, source: string?): number
	local w = wallet(player)
	if not w or type(amount) ~= "number" or amount ~= amount or amount < 1 then
		return 0
	end
	amount = math.floor(amount)
	local before = w.coins
	w.coins = math.min(before + amount, MAX_COINS)
	local added = w.coins - before
	if added > 0 then
		NotifyService.pickup(player, "coins", "Coins", added, CoinsConfig.color)
		publish(player, added)
	end
	return added
end

function WalletService.spend(player: Player, amount: number): boolean
	local w = wallet(player)
	if not w or type(amount) ~= "number" or amount ~= amount or amount < 1 then
		return false
	end
	amount = math.floor(amount)
	if w.coins < amount then
		return false
	end
	w.coins -= amount
	publish(player, -amount)
	return true
end

-- mirror the saved balance onto the attribute once a profile has loaded
local function watch(player: Player)
	task.spawn(function()
		local waited = 0
		while player.Parent == Players and not SkillsDataManager.IsLoaded(player) and waited < 60 do
			waited += task.wait(0.5)
		end
		if player.Parent == Players and SkillsDataManager.IsLoaded(player) then
			local w = wallet(player)
			player:SetAttribute("Coins", w and w.coins or 0)
		end
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do
	watch(player)
end

return WalletService
