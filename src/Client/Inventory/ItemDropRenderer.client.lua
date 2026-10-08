--[[
	ItemDropRenderer (LocalScript)
	Place inside: StarterPlayerScripts

	Visual only. The server owns dropped items (Models tagged "ItemDrop" in workspace.ItemDrops).
	Once a drop has settled (attribute Settled, BasePos = resting centre) this adds the Minecraft
	hover / bob / spin by pivoting the model each frame. One Heartbeat loop for every drop, and
	drops far from the camera are skipped.

	STACKING (numbers in Config/DropStackConfig):
	  - an item that merges keeps its model, is re-tagged "ItemDropMerge" with attribute MergeInto = the stack's DropId, and
	    flies into the stack here (accelerating, arcing, spinning up, shrinking) for flyTime seconds;
	  - when it arrives the server bumps the stack's MergeSeq attribute: the stack POPS (scale punch that springs back, a
	    spin kick, harder for bigger stacks). DropFXController adds the burst on the same attribute;
	  - a PICKED-UP item (tag "ItemDropPickup", attribute PickupBy = the player's UserId) flies the same way into that player's
	    chest (DropStackConfig.pickup); DropFXController plays the pop and the coloured burst when it arrives.

	EDGES: a flat sprite is a thin slab with the icon on both faces; DropEdges adds its coloured thickness on this client for
	drops within EDGE_DISTANCE (a few builds per frame) and removes it again when you walk away.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local STACK = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("DropStackConfig")) :: any

local DropEdges = require(script.Parent:WaitForChild("DropEdges")) :: any

local TAG = "ItemDrop"
local MERGE_TAG = "ItemDropMerge"
local PICKUP_TAG = "ItemDropPickup"
local EDGE_DISTANCE = 40 -- studs: nearer drops get their coloured edge
local EDGE_BUILDS_PER_FRAME = 6
local EDGE_SETTLE_FRAMES = 3 -- frames after a drop settles in which its strips are re-seated on its Handle (the server moves the Handle at settle)
local HOVER = 0.7 -- studs above the resting centre
local BOB_AMPLITUDE = 0.18
local BOB_SPEED = 2.2 -- rad/s
local SPIN_SPEED = 1.6 -- rad/s
local CULL_DISTANCE = 80
local RISE_TIME = 0.4 -- seconds to ease up from the ground once settled
local FLY_SPIN = 14 -- rad/s an incoming item spins at, on top of the stack's spin
local FLY_SHRINK = 0.55 -- fraction of its size an incoming item loses on the way in

local drops: { [Model]: any } = {}
local byId: { [number]: Model } = {}
local flyers: { [Model]: any } = {}

local function startPunch(info: any, model: Model)
	local p = STACK.punch
	local count = model:GetAttribute("Count") or 1
	info.punchAt = os.clock()
	info.punchAmp = math.min(p.maxScale, p.scale + p.perCount * count) - 1
end

local function register(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local info = { phase = model:GetAttribute("Phase") or 0, yawAdd = 0 }
	drops[model] = info
	local id = model:GetAttribute("DropId")
	if id then
		byId[id] = model
	end
	info.seqConn = model:GetAttributeChangedSignal("MergeSeq"):Connect(function()
		startPunch(info, model)
		DropEdges.detach(model) -- a new stack layer appeared: the edges are rebuilt for it on the next frame
		info.edges = false
	end)
	-- a stack layer added later arrives posed by the server; seat it on this client's posed Body
	info.addConn = model.DescendantAdded:Connect(function(part)
		local rel = part:IsA("BasePart") and part:GetAttribute("Rel")
		local body = model.PrimaryPart
		if rel and body then
			part.CFrame = body.CFrame * rel
		end
	end)
end

local function unregister(model: Instance)
	local info = drops[model :: Model]
	if info then
		info.seqConn:Disconnect()
		info.addConn:Disconnect()
		drops[model :: Model] = nil
		local id = model:GetAttribute("DropId")
		if id and byId[id] == model then
			byId[id] = nil
		end
	end
end

local function registerFlyer(model: Instance)
	if not model:IsA("Model") then
		return
	end
	flyers[model] = {
		t0 = os.clock(),
		from = model:GetPivot(), -- the pose this client last drew it in (hovering, mid-spin) so it leaves from there
		scale = model:GetScale(),
		last = model:GetPivot().Position,
		userId = model:GetAttribute("PickupBy"), -- set for a picked-up item: it flies to that player instead of into a stack
	}
end

for _, model in ipairs(CollectionService:GetTagged(TAG)) do
	register(model)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(unregister)
for _, model in ipairs(CollectionService:GetTagged(MERGE_TAG)) do
	registerFlyer(model)
end
CollectionService:GetInstanceAddedSignal(MERGE_TAG):Connect(registerFlyer)
CollectionService:GetInstanceRemovedSignal(MERGE_TAG):Connect(function(model)
	flyers[model :: Model] = nil
end)
for _, model in ipairs(CollectionService:GetTagged(PICKUP_TAG)) do
	registerFlyer(model)
end
CollectionService:GetInstanceAddedSignal(PICKUP_TAG):Connect(registerFlyer)
CollectionService:GetInstanceRemovedSignal(PICKUP_TAG):Connect(function(model)
	flyers[model :: Model] = nil
end)

-- Pure functions of the clock (never of a tween or a counter), so the bob and spin loop with no seam.
-- Runs on PreRender so the pivot lands right before the frame is drawn.
RunService.PreRender:Connect(function()
	if next(drops) == nil and next(flyers) == nil then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local camPos = camera.CFrame.Position
	local t = os.clock()
	local punch = STACK.punch
	local edgeBuilds = 0
	for model, info in pairs(drops) do
		-- BasePos never changes once a drop has settled: read the attributes once, not 2x per drop per frame
		local base = info.base
		if not base and model:GetAttribute("Settled") then
			base = model:GetAttribute("BasePos")
			info.base = base
		end
		-- the coloured edge: built the moment a drop is near (also while it is still falling, where it follows the Handle),
		-- rebuilt when the drop settles (the server moved the Handle), removed when you walk away
		local pos = base or model:GetPivot().Position
		local away = (pos - camPos).Magnitude
		if base and not info.settledAt then
			DropEdges.detach(model)
			info.edges = false
			info.fixFrames = EDGE_SETTLE_FRAMES
		end
		if away <= EDGE_DISTANCE then
			if not info.edges and edgeBuilds < EDGE_BUILDS_PER_FRAME then
				edgeBuilds += 1
				info.edges = true
				DropEdges.attach(model)
			end
			if not base and info.edges then
				DropEdges.follow(model)
			end
		elseif info.edges and away > EDGE_DISTANCE + 10 then
			info.edges = false
			DropEdges.detach(model)
		end
		if base then
			if not info.settledAt then
				info.settledAt = t
			end
			if away <= CULL_DISTANCE then
				local rise = math.clamp((t - info.settledAt) / RISE_TIME, 0, 1)
				rise = rise * rise * (3 - 2 * rise) -- smoothstep: no snap from the ground pose
				local phase = info.phase
				local lift = (HOVER + math.sin(t * BOB_SPEED + phase) * BOB_AMPLITUDE) * rise
				local yaw = t * SPIN_SPEED + phase + info.yawAdd

				-- the stack pop: scale springs from 1 + amp back to 1, and the spin gets a kick that fades
				local punchAt = info.punchAt
				if punchAt then
					local u = (t - punchAt) / punch.time
					if u >= 1 then
						info.punchAt = nil
						info.yawAdd += punch.spin * punch.time / 3 -- keep the kick's turn: no snap back when it ends
						model:ScaleTo(1)
					else
						local s = 1 + info.punchAmp * math.exp(-5 * u) * math.cos(u * math.pi * 3)
						model:ScaleTo(math.max(s, 0.05))
						yaw += punch.spin * punch.time * (1 - (1 - u) ^ 3) / 3
						lift += info.punchAmp * 0.9 * math.exp(-5 * u) * math.max(0, math.cos(u * math.pi * 3))
					end
				end
				model:PivotTo(CFrame.new(base + Vector3.new(0, lift, 0)) * CFrame.Angles(0, yaw % (math.pi * 2), 0))
				if info.fixFrames and info.fixFrames > 0 and info.edges then
					info.fixFrames -= 1
					DropEdges.follow(model)
				end
			elseif info.punchAt then
				info.punchAt = nil
				info.yawAdd += punch.spin * punch.time / 3
				model:ScaleTo(1)
			end
		else
			info.settledAt = nil
		end
	end

	-- items flying into a stack: accelerate in along a small arc, spin up and shrink
	for model, f in pairs(flyers) do
		local pickup = f.userId ~= nil
		local flyTime = pickup and STACK.pickup.flyTime or STACK.flyTime
		local u = (t - f.t0) / flyTime
		if pickup then
			local who = Players:GetPlayerByUserId(f.userId)
			local root = who and who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				f.last = root.Position + Vector3.new(0, STACK.pickup.chest, 0)
			end
		else
			local target = byId[model:GetAttribute("MergeInto") or -1]
			if target and target.Parent then
				f.last = target:GetPivot().Position
			end
		end
		if u >= 1 then
			model:ScaleTo(0.02)
			model:PivotTo(CFrame.new(f.last))
			flyers[model] = nil
		else
			local e = u * u * (3 - 2 * u)
			e = e * (0.5 + 0.5 * u) + u * u * u * 0.35 -- eased out of the start, pulled hard at the end
			e = math.clamp(e, 0, 1)
			local start = f.from.Position
			local pos = start:Lerp(f.last, e) + Vector3.new(0, math.sin(u * math.pi) * (pickup and STACK.pickup.flyArc or STACK.flyArc), 0)
			model:ScaleTo(math.max(f.scale * (1 - (pickup and STACK.pickup.shrink or FLY_SHRINK) * e), 0.02))
			model:PivotTo(CFrame.new(pos) * (f.from.Rotation * CFrame.Angles(0, FLY_SPIN * (t - f.t0) * (0.4 + e), 0)))
		end
	end
end)
