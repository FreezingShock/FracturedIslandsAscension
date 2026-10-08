--[[
	ItemDrops (ModuleScript, Server) — Minecraft-style items on the ground.

	The server owns everything real: a drop is a Model (invisible physics Body + the item's
	visual parts welded to it) in workspace.ItemDrops, tagged "ItemDrop". It falls with real
	physics, then settles (anchored, BasePos attribute = resting centre). The client
	(ItemDropRenderer) only adds the hover / bob / spin on top of BasePos.

	  ItemDrops.spawn(opts) -> dropId?   opts: toolName, count, position, velocity?, ownerId?, custom?
	  ItemDrops.setGrantHandler(fn)      fn(player, toolName, count) -> number actually added
	  ItemDrops.count() / ItemDrops.get(id) / ItemDrops.list()

	Pickup is polled server-side (no Touched, no client input). The record is removed before the
	item is granted, so one drop can never be taken twice; a full inventory leaves the rest on the floor.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ServerScriptService = game:GetService("ServerScriptService")
local ItemTools = require(ServerScriptService:WaitForChild("ItemTools")) :: any
local Items = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Items")) :: any
local STACK = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("DropStackConfig")) :: any

local ItemDrops = {}

-- ===================== CONFIG =====================
local MAX_DROPS = 200 -- oldest drop is removed past this
local DESPAWN_SECONDS = 300
local PICKUP_RADIUS = 8 -- studs from the player's root part
local PICKUP_DELAY = 0.5 -- everyone, after spawning
local OWNER_DELAY = 2 -- the player who dropped it
local FULL_RETRY = 1 -- seconds before retrying a pickup that did not fit
local MERGE_INTERVAL = 0.5
local MAX_DROP_STACK = STACK.maxStack -- merge radii, fly time and layer look: Config/DropStackConfig

--- Gear (maxStack 1) never clumps into one drop; resources clump up to MAX_DROP_STACK.
local function dropStackLimit(toolName: string): number
	local def = Items.getByToolName(toolName)
	return math.min(MAX_DROP_STACK, def and def.maxStack or MAX_DROP_STACK)
end
local LAYER_STEPS = STACK.layers -- count <= step -> that many layers; above the last -> one more
local MERGE_TAG = "ItemDropMerge" -- an item flying into a stack (client animates it, the server destroys it on arrival)
local TICK = 0.2
local BODY_SIZE = 1.2
local SETTLE_SPEED = 1.5
local SETTLE_TIME = 0.3
local MAX_FALL_TIME = 6
local TAG = "ItemDrop"

-- ===================== STATE =====================
local drops: { [number]: any } = {} -- [id] = record
local falling: { [number]: any } = {} -- records still simulating
local nextId = 0
local total = 0
local grant: ((Player, string, number) -> number)? = nil

local folder = workspace:FindFirstChild("ItemDrops") or Instance.new("Folder")
folder.Name = "ItemDrops"
folder.Parent = workspace

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- ===================== BUILD =====================
local updateLayers: (any) -> () -- defined below buildModel

local function updateLabel(rec)
	local body = rec.body
	local gui = body:FindFirstChild("CountLabel")
	if rec.count > 1 then
		if not gui then
			gui = Instance.new("BillboardGui")
			gui.Name = "CountLabel"
			gui.Size = UDim2.fromOffset(60, 22)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 0.2, 0)
			gui.AlwaysOnTop = false
			gui.MaxDistance = 40
			gui.Adornee = body
			local label = Instance.new("TextLabel")
			label.Name = "Text"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.GothamBold
			label.TextSize = 16
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0
			label.Parent = gui
			gui.Parent = body
		end
		gui.Text.Text = "x" .. rec.count
	elseif gui then
		gui:Destroy()
	end
	rec.model:SetAttribute("Count", rec.count)
	updateLayers(rec)
end

--- Visual parts of the item's Tool, re-parented into a Model centred on the Body.
local function buildModel(toolName: string, position: Vector3)
	local tool = ItemTools.ensure(toolName)
	if not tool then
		return nil
	end
	local clone = tool:Clone()
	local visual = Instance.new("Model")
	local handle = clone:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		clone:Destroy()
		return nil
	end
	for _, child in ipairs(clone:GetChildren()) do
		if child:IsA("BasePart") then
			child.Parent = visual
		end
	end
	clone:Destroy()
	visual.PrimaryPart = handle

	-- centre the visual's bounding box on the origin of the drop (Body centre)
	local boxCF, boxSize = visual:GetBoundingBox()
	local model = Instance.new("Model")
	model.Name = "Drop_" .. toolName

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(BODY_SIZE, BODY_SIZE, BODY_SIZE)
	body.Transparency = 1
	body.CFrame = CFrame.new(position)
	body.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.8, 0.15, 1, 1)
	body.CanCollide = true -- only while it falls to the floor; settle() turns it off
	body.CanTouch = false
	body.Parent = model
	model.PrimaryPart = body

	local template = {} -- unwelded copies + body-relative pose, used to build extra stack layers
	for _, part in ipairs(visual:GetChildren()) do
		if part:IsA("BasePart") then
			local rel = boxCF:ToObjectSpace(part.CFrame)
			part.CFrame = body.CFrame * rel
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			table.insert(template, { part = part:Clone(), rel = rel })
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
			part.Parent = model
		end
	end
	visual:Destroy()
	return model, body, boxSize.Y / 2, template
end

--- Minecraft-style stack look: more items on the floor show as more layered, slightly offset copies.
local function layersFor(count: number): number
	for i, limit in ipairs(LAYER_STEPS) do
		if count <= limit then
			return i
		end
	end
	return #LAYER_STEPS + 1
end

updateLayers = function(rec)
	local want = layersFor(rec.count)
	local have = rec.layers or 1
	if want == have then
		return
	end
	rec.layers = want
	for _, inst in ipairs(rec.model:GetChildren()) do
		local layer = inst:GetAttribute("StackLayer")
		if layer and layer > want then
			inst:Destroy()
		end
	end
	-- the rng is drawn for every layer so a layer keeps its place as the stack grows; only NEW layers are built
	local rng = Random.new(rec.id * 7919)
	for layer = 2, #LAYER_STEPS + 1 do
		local offset = Vector3.new(
			(rng:NextNumber() - 0.5) * STACK.layerSpread[1],
			(rng:NextNumber() - 0.5) * STACK.layerSpread[2],
			(rng:NextNumber() - 0.5) * STACK.layerSpread[1]
		)
		local turn = CFrame.Angles(0, (rng:NextNumber() - 0.5) * 0.6, 0)
		if layer > have and layer <= want then
			for _, entry in ipairs(rec.template) do
				local part = entry.part:Clone()
				local rel = CFrame.new(offset) * turn * entry.rel
				part:SetAttribute("StackLayer", layer)
				part:SetAttribute("Rel", rel) -- the client re-seats a late layer on its own posed Body from this
				part.CFrame = rec.body.CFrame * rel
				part.Anchored = rec.base ~= nil
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rec.body
				weld.Part1 = part
				weld.Parent = part
				part.Parent = rec.model
			end
		end
	end
end

--- An item that merges does not pop out of existence: it keeps its model, loses its drop identity and flies into
--- the stack (ItemDropRenderer animates it, the server destroys it once it has arrived).
local function fly(model: Model, keepId: number, color: any)
	model:SetAttribute("MergeInto", keepId)
	model:SetAttribute("DropColor", color)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
		end
	end
	CollectionService:RemoveTag(model, TAG)
	CollectionService:RemoveTag(model, "DropTooltip")
	CollectionService:AddTag(model, MERGE_TAG)
	task.delay(STACK.flyTime + 0.2, function()
		model:Destroy()
	end)
end

--- Add `count` to a stack. The count / layers / punch land when the flying item arrives, so it reads as one beat.
local function absorb(keep, count: number, from: Model?)
	keep.count += count
	if from then
		fly(from, keep.id, keep.model:GetAttribute("DropColor"))
	end
	task.delay(from and STACK.flyTime or 0, function()
		if drops[keep.id] ~= keep then
			return
		end
		updateLabel(keep)
		keep.model:SetAttribute("MergeSeq", (keep.model:GetAttribute("MergeSeq") or 0) + 1)
	end)
end

-- ===================== LIFECYCLE =====================
local function remove(id: number)
	local rec = drops[id]
	if not rec then
		return
	end
	drops[id] = nil
	falling[id] = nil
	total -= 1
	rec.model:Destroy()
end

local function oldestId(): number?
	local best, bestTime
	for id, rec in pairs(drops) do
		if not bestTime or rec.spawnedAt < bestTime then
			best, bestTime = id, rec.spawnedAt
		end
	end
	return best
end

local function settle(rec)
	falling[rec.id] = nil
	local body = rec.body
	local pos = body.Position
	local filter = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(filter, p.Character)
		end
	end
	rayParams.FilterDescendantsInstances = filter
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), rayParams)
	local groundY = hit and hit.Position.Y or (pos.Y - BODY_SIZE / 2)
	local base = Vector3.new(pos.X, groundY + rec.halfHeight, pos.Z)

	for _, part in ipairs(rec.model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	rec.model:PivotTo(CFrame.new(base))
	body.CanCollide = false
	rec.base = base
	rec.model:SetAttribute("BasePos", base)
	rec.model:SetAttribute("Settled", true)
end

--- Spawn a drop. Merges into a nearby identical drop when possible.
function ItemDrops.spawn(opts: any): number?
	local toolName, count, position = opts.toolName, opts.count or 1, opts.position
	if type(toolName) ~= "string" or typeof(position) ~= "Vector3" or count < 1 then
		return nil
	end
	local def = Items.getByToolName(toolName)
	local now = os.clock()

	-- a new item never starts its own motion next to a matching stack: it flies straight into it (thrown ones too)
	local limit = dropStackLimit(toolName)
	local target, targetDist
	for _, rec in pairs(drops) do
		if rec.toolName == toolName and rec.custom == opts.custom and rec.count + count <= limit then
			local d = ((rec.base or rec.body.Position) - position).Magnitude
			if d <= STACK.spawnRadius and (not targetDist or d < targetDist) then
				target, targetDist = rec, d
			end
		end
	end
	if target then
		local ghost = buildModel(toolName, position)
		target.spawnedAt = now
		target.ownerId = opts.ownerId
		target.ownerUntil = now + OWNER_DELAY
		target.pickupAt = now + PICKUP_DELAY
		if ghost then
			ghost.Name = "Merge_" .. toolName
			for _, part in ipairs(ghost:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
			ghost.Parent = folder
		end
		absorb(target, count, ghost)
		return target.id
	end

	while total >= MAX_DROPS do
		local id = oldestId()
		if not id then
			break
		end
		remove(id)
	end

	local model, body, halfHeight, template = buildModel(toolName, position)
	if not model then
		return nil
	end
	nextId += 1
	local id = nextId
	local rec = {
		id = id,
		toolName = toolName,
		itemId = def and def.id or toolName,
		count = count,
		custom = opts.custom,
		ownerId = opts.ownerId,
		ownerUntil = now + OWNER_DELAY,
		pickupAt = now + PICKUP_DELAY,
		spawnedAt = now,
		model = model,
		body = body,
		halfHeight = halfHeight,
		template = template,
		stillFor = 0,
		nextTry = 0,
	}
	drops[id] = rec
	falling[id] = rec
	total += 1

	body:SetAttribute("DropId", id)
	model:SetAttribute("DropId", id)
	model:SetAttribute("ItemId", rec.itemId)
	model:SetAttribute("DropKind", "item")
	model:SetAttribute("DropName", def and (def.displayName or def.name) or toolName)
	model:SetAttribute("Rarity", def and def.rarity or 0)
	local rarityDef = def and Items.getRarity(def.rarity)
	if rarityDef and rarityDef.color then
		model:SetAttribute("DropColor", rarityDef.color:ToHex()) -- the colour DropFXController glows in
	end
	model:SetAttribute("Phase", math.random() * math.pi * 2)
	model:SetAttribute("Settled", false)
	updateLabel(rec)
	model.Parent = folder
	CollectionService:AddTag(model, TAG)
	CollectionService:AddTag(model, "DropTooltip") -- read by DropTooltipController (client), attributes above
	body:SetNetworkOwner(nil)
	if typeof(opts.velocity) == "Vector3" then
		body.AssemblyLinearVelocity = opts.velocity
	end
	return id
end

-- ===================== PICKUP / DESPAWN =====================
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = { folder }
overlap.MaxParts = 40

local function tryPickup(player: Player, rec, now: number)
	if not grant or now < rec.pickupAt or now < rec.nextTry then
		return
	end
	if rec.ownerId == player.UserId and now < rec.ownerUntil then
		return
	end
	local id, toolName, count = rec.id, rec.toolName, rec.count
	-- detach first: while the grant runs, nobody else can find this drop (no double pickup)
	drops[id] = nil
	falling[id] = nil
	total -= 1
	local ok, result = pcall(grant, player, toolName, count)
	local added = ok and tonumber(result) or 0
	if added >= count then
		rec.model:Destroy()
		return
	end
	-- did not all fit (full inventory, stack cap, error): keep the rest on the floor
	rec.count = count - added
	rec.nextTry = now + FULL_RETRY
	drops[id] = rec
	total += 1
	if not rec.base then
		falling[id] = rec
	end
	updateLabel(rec)
	if not ok then
		warn("[ItemDrops] grant failed: " .. tostring(result))
	end
end

--- Clump settled identical drops that ended up close together (Minecraft item merging).
local function mergeSettled()
	local list = {}
	for _, rec in pairs(drops) do
		if rec.base then
			table.insert(list, rec)
		end
	end
	for i = 1, #list do
		local a = list[i]
		if drops[a.id] then
			for j = i + 1, #list do
				local b = list[j]
				if
					drops[b.id]
					and a.toolName == b.toolName
					and a.custom == b.custom
					and a.count + b.count <= dropStackLimit(a.toolName)
					and (a.base - b.base).Magnitude <= STACK.mergeRadius
				then
					local keep, gone = a, b
					if b.count > a.count then
						keep, gone = b, a
					end
					keep.pickupAt = math.max(keep.pickupAt, gone.pickupAt)
					keep.spawnedAt = math.max(keep.spawnedAt, gone.spawnedAt)
					drops[gone.id] = nil
					falling[gone.id] = nil
					total -= 1
					local gui = gone.body:FindFirstChild("CountLabel")
					if gui then
						gui:Destroy()
					end
					absorb(keep, gone.count, gone.model)
					if gone == a then
						break
					end
				end
			end
		end
	end
end

local function step()
	local now = os.clock()
	for id, rec in pairs(drops) do
		if now - rec.spawnedAt > DESPAWN_SECONDS then
			remove(id)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 and total > 0 then
			local seen = {}
			for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, PICKUP_RADIUS, overlap)) do
				local id = part:GetAttribute("DropId")
				if id and not seen[id] and part.Name == "Body" then
					seen[id] = true
					local rec = drops[id]
					if rec then
						tryPickup(player, rec, now)
					end
				end
			end
		end
	end
end

task.spawn(function()
	local nextMerge = 0
	while true do
		task.wait(TICK)
		local ok, err = pcall(step)
		if not ok then
			warn("[ItemDrops] step failed: " .. tostring(err))
		end
		if os.clock() >= nextMerge then
			nextMerge = os.clock() + MERGE_INTERVAL
			local mok, merr = pcall(mergeSettled)
			if not mok then
				warn("[ItemDrops] merge failed: " .. tostring(merr))
			end
		end
	end
end)

-- falling drops: settle once they stop (or fall out of the world)
RunService.Heartbeat:Connect(function(dt)
	if next(falling) == nil then
		return
	end
	local now = os.clock()
	for id, rec in pairs(falling) do
		local body = rec.body
		if body.Position.Y < workspace.FallenPartsDestroyHeight + 20 then
			remove(id)
		else
			if body.AssemblyLinearVelocity.Magnitude < SETTLE_SPEED then
				rec.stillFor += dt
			else
				rec.stillFor = 0
			end
			if rec.stillFor >= SETTLE_TIME or now - rec.spawnedAt > MAX_FALL_TIME then
				settle(rec)
			end
		end
	end
end)

-- ===================== API =====================
function ItemDrops.setGrantHandler(fn)
	grant = fn
end

function ItemDrops.count(): number
	return total
end

function ItemDrops.get(id: number)
	return drops[id]
end

function ItemDrops.list(): { any }
	local out = {}
	for _, rec in pairs(drops) do
		table.insert(out, rec)
	end
	return out
end

return ItemDrops
