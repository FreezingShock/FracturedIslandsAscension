--[[
	ItemDropRenderer (LocalScript)
	Place inside: StarterPlayerScripts

	Visual only. The server owns dropped items (Models tagged "ItemDrop" in workspace.ItemDrops).
	Once a drop has settled (attribute Settled, BasePos = resting centre) this adds the Minecraft
	hover / bob / spin by pivoting the model each frame. One Heartbeat loop for every drop, and
	drops far from the camera are skipped.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local TAG = "ItemDrop"
local HOVER = 0.7 -- studs above the resting centre
local BOB_AMPLITUDE = 0.18
local BOB_SPEED = 2.2 -- rad/s
local SPIN_SPEED = 1.6 -- rad/s
local CULL_DISTANCE = 80
local RISE_TIME = 0.4 -- seconds to ease up from the ground once settled

local drops: { [Model]: { phase: number, settledAt: number?, base: Vector3? } } = {}

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	drops[model] = { phase = model:GetAttribute("Phase") or 0 }
end

for _, model in ipairs(CollectionService:GetTagged(TAG)) do
	register(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(model)
	drops[model] = nil
end)

-- Pure functions of the clock (never of a tween or a counter), so the bob and spin loop with no seam.
-- Runs on PreRender so the pivot lands right before the frame is drawn.
RunService.PreRender:Connect(function()
	if next(drops) == nil then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	for model, info in pairs(drops) do
		-- BasePos never changes once a drop has settled: read the attributes once, not 2x per drop per frame
		local base = info.base
		if not base and model:GetAttribute("Settled") then
			base = model:GetAttribute("BasePos")
			info.base = base
		end
		if base then
			if not info.settledAt then
				info.settledAt = t
			end
			if (base - camPos).Magnitude <= CULL_DISTANCE then
				local rise = math.clamp((t - info.settledAt) / RISE_TIME, 0, 1)
				rise = rise * rise * (3 - 2 * rise) -- smoothstep: no snap from the ground pose
				local phase = info.phase
				local lift = (HOVER + math.sin(t * BOB_SPEED + phase) * BOB_AMPLITUDE) * rise
				model:PivotTo(CFrame.new(base + Vector3.new(0, lift, 0)) * CFrame.Angles(0, (t * SPIN_SPEED + phase) % (math.pi * 2), 0))
			end
		else
			info.settledAt = nil
		end
	end
end)
