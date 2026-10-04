--[[
	TreeSway (LocalScript)
	Place inside: StarterPlayerScripts

	Leaf parts tagged "TreeSway" rock gently in the wind. This replaces the free-model Script that sat
	inside every Leaves part and ran `while true do ... wait() end` ON THE SERVER (30 CFrame writes a second
	per leaf, replicated to every client). Now each client animates the leaves it can see, in one
	Heartbeat loop, only for parts near the camera.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "TreeSway"
local SPEED = 3.6 -- phase units per second (the old script advanced 0.12 per ~1/30 s)
local CULL_DISTANCE = 250

local leaves: { [BasePart]: { base: Vector3, tall: number } } = {}

local function register(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	-- the old script lowered the pivot by 0.2 studs once and swayed around that point
	local pos = part.Position
	leaves[part] = { base = Vector3.new(pos.X, pos.Y - 0.2, pos.Z), tall = math.max(part.Size.Y / 2, 0.1) }
end

for _, part in ipairs(CollectionService:GetTagged(TAG)) do
	register(part)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(part)
	leaves[part] = nil
end)

RunService.PreRender:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera or next(leaves) == nil then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock() * SPEED
	for part, info in pairs(leaves) do
		if not part.Parent then
			leaves[part] = nil
		elseif (info.base - camPos).Magnitude <= CULL_DISTANCE then
			local base = info.base
			local x = base.X + (math.sin(t + base.X / 6) * math.sin(t / 9)) / 3
			local z = base.Z + (math.sin(t + base.Z / 7) * math.sin(t / 11)) / 4
			part.CFrame = CFrame.new(x, base.Y, z) * CFrame.Angles((z - base.Z) / info.tall, 0, (x - base.X) / -info.tall)
		end
	end
end)
