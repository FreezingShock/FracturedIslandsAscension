--[[
	DeathController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Plays the death look (DeathFX: glitch, then a burst of glowing triangles) when the server says something died
	(RemoteEvent EntityDeath { model, kind, deathType, seed } from DeathService; the client never sends anything).
	When the dead one is you, nothing extra is needed for the camera: CameraController keeps following the (frozen) body, so the
	view stays on the spot where you fell until you respawn.
	The nameplate's own glitch + shards run in EnemyNameplateController from the same message.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DeathFX = require(Modules:WaitForChild("DeathFX")) :: any
local remote = ReplicatedStorage:WaitForChild("EntityDeath") :: RemoteEvent

remote.OnClientEvent:Connect(function(model, kind, deathType, seed)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	if type(kind) ~= "string" or (type(deathType) ~= "string" and deathType ~= nil) then
		return
	end
	DeathFX.play(model, kind, deathType, type(seed) == "number" and seed or nil)
end)
