--[[
	EnemyRig (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyService)

	Builds the body of a mob: the ServerStorage[mob.template] model when it exists (drop your own R6 rig there; custom modelling
	later), else a plain tinted R6 rig. Then it equips the mob's weapon: mob.weapon = { item = "<Items id>" }. That is the REAL item:
	a clone of the item's Tool (ItemTools), so the sword model, grip and sword animations are the ones a player's copy of the item
	gets, and the item's abilities (AbilityConfig, listed on the item) are what the mob's "ability" attacks cast.

	The Tool's Handle carries the attachments TrailA / TrailB that the client (EnemyAttackFXController) turns into a swing trail.
	A rig that already holds a Tool keeps it.

	  EnemyRig.build(cfg) -> Model?
	  EnemyRig.attachWeapon(model, weapon)
	  EnemyRig.placeOnGround(model, marker)   stand the model's feet exactly on the floor under a spawn marker (no pop on release)
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Items = require(Modules:WaitForChild("Items")) :: any
local ItemTools = require(ServerScriptService:WaitForChild("ItemTools")) :: any

local EnemyRig = {}

function EnemyRig.build(cfg: any): Model?
	local made = ServerStorage:FindFirstChild(cfg.template)
	if made and made:IsA("Model") then
		return made:Clone()
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R6)
	end)
	if not (ok and rig) then
		return nil
	end
	local colors = rig:FindFirstChildOfClass("BodyColors") or Instance.new("BodyColors", rig)
	for _, key in ipairs({ "HeadColor3", "TorsoColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" }) do
		colors[key] = cfg.bodyColor
	end
	for _, item in ipairs(rig:GetChildren()) do
		if item:IsA("BasePart") and item.Name ~= "HumanoidRootPart" then
			item.Color = cfg.bodyColor
		end
	end
	return rig
end

--- Puts `model` (already near the marker) at the marker's X/Z with the lowest point of its body on the floor found by a raycast
--- down from the marker. Call it BEFORE the weapon is attached (a sword hangs below the feet). A rig dropped by height guesses
--- starts inside the floor or in the air, and the Humanoid snaps it to its real standing height the moment it is released.
function EnemyRig.placeOnGround(model: Model, marker: BasePart)
	local ignore: { Instance } = { model }
	if marker.Parent then
		table.insert(ignore, marker.Parent) -- the spawn markers
	end
	for _, tagged in ipairs(CollectionService:GetTagged("Enemy")) do
		table.insert(ignore, tagged)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(marker.Position + Vector3.new(0, 4, 0), Vector3.new(0, -80, 0), params)
	local floorY = hit and hit.Position.Y or (marker.Position.Y + marker.Size.Y / 2)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, floorY - bottom, 0))
end

--- Equips the item's own Tool in the mob's hand. The engine welds the Handle to the Right Arm with the item's grip, exactly as for
--- a player. Warns (and leaves the mob unarmed) when the item has no Tool.
function EnemyRig.attachWeapon(model: Model, weapon: any?)
	if not weapon or model:FindFirstChildOfClass("Tool") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local def = weapon.item and Items.get(weapon.item)
	local template = def and def.toolName and ItemTools.ensure(def.toolName)
	if not (humanoid and template) then
		warn(("[EnemyRig] %s: weapon item '%s' has no Tool (needs a toolName)"):format(model.Name, tostring(weapon.item)))
		return
	end
	local tool = template:Clone()
	tool.CanBeDropped = false
	tool.Parent = model
	humanoid:EquipTool(tool)

	-- the swing trail's two ends run along the blade (the mesh's long axis) from the guard to the tip
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if handle then
		local half = handle.Size.Y / 2
		local trailA = Instance.new("Attachment")
		trailA.Name = "TrailA"
		trailA.Position = Vector3.new(0, -half + 0.3, 0)
		trailA.Parent = handle
		local trailB = Instance.new("Attachment")
		trailB.Name = "TrailB"
		trailB.Position = Vector3.new(0, half, 0)
		trailB.Parent = handle
	end
end

return EnemyRig
