--[[
	RateLimiter (ModuleScript, Server)
	Place inside: ServerScriptService

	Per-player token buckets so a client can't flood a RemoteFunction/RemoteEvent
	(every inventory call walks the backpack and pushes a full UpdateInventory).

	  local limit = RateLimiter.new(burst, perSecond)
	  if not limit(player) then return false end      -- inside OnServerInvoke / OnServerEvent

	Buckets are dropped when the player leaves. Normal play never gets near the
	limits (a fast drag-and-drop is a handful of calls per second).
--]]

local Players = game:GetService("Players")

local RateLimiter = {}

local buckets: { [any]: { [number]: { tokens: number, at: number } } } = {}

--- Returns a function(player, cost?) -> boolean (true = allowed).
function RateLimiter.new(burst: number, perSecond: number)
	local mine = {}
	buckets[mine] = mine
	return function(player: Player, cost: number?): boolean
		local now = os.clock()
		local bucket = mine[player.UserId]
		if not bucket then
			bucket = { tokens = burst, at = now }
			mine[player.UserId] = bucket
		end
		bucket.tokens = math.min(burst, bucket.tokens + (now - bucket.at) * perSecond)
		bucket.at = now
		local need = cost or 1
		if bucket.tokens < need then
			return false
		end
		bucket.tokens -= need
		return true
	end
end

Players.PlayerRemoving:Connect(function(player)
	for _, mine in pairs(buckets) do
		mine[player.UserId] = nil
	end
end)

return RateLimiter
