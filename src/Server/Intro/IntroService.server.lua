--[[
	IntroService (Script)
	Place inside: ServerScriptService

	The server owns the join shield. The first character of every session gets the player attribute IntroShield = true,
	and DamageService.hurtPlayer deals nothing to a shielded player (enemies cannot hurt you through the loading screen).
	The client only asks to end it (IntroDone); the server drops the shield once that arrives, and on its own after
	SHIELD_MAX_SECONDS, so a client that never sends IntroDone cannot keep the shield forever.
	Respawns are not shielded: the intro is for joining, not for every death.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SHIELD_MAX_SECONDS = 180

local introDone = ReplicatedStorage:FindFirstChild("IntroDone")
if not introDone then
	introDone = Instance.new("RemoteEvent")
	introDone.Name = "IntroDone"
	introDone.Parent = ReplicatedStorage
end

local shielded: { [Player]: boolean } = {}
local claimed: { [Player]: boolean } = {} -- the first character of the session is the only shielded one

local function unshield(player: Player)
	if shielded[player] then
		shielded[player] = nil
		player:SetAttribute("IntroShield", nil)
	end
end

local function onCharacter(player: Player)
	if claimed[player] then
		return
	end
	claimed[player] = true
	shielded[player] = true
	player:SetAttribute("IntroShield", true)
	task.delay(SHIELD_MAX_SECONDS, function()
		unshield(player)
	end)
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function()
		onCharacter(player)
	end)
	if player.Character then
		onCharacter(player)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, player)
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(player)
	shielded[player] = nil
	claimed[player] = nil
end)

-- no arguments are read: the only thing a client can do is say "I am out of the intro"
introDone.OnServerEvent:Connect(function(player: Player)
	unshield(player)
end)
