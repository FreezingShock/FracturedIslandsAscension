--[[
	EnemyRig (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyService)

	Builds the body of a mob: the ServerStorage[mob.template] model when it exists (drop your own R6 rig there; custom modelling
	later), else a plain tinted R6 rig, then welds the mob.weapon (EnemyConfig) to the right hand.

	A sword is a Model "Sword" of Grip / Guard / Blade parts welded to the Right Arm, hanging along the arm like the player's Tool
	grip (so the player's R6 sword animations carry it correctly). The Blade carries the attachments TrailA / TrailB that the client
	(EnemyAttackFXController) turns into a swing trail. A rig that already has a "Sword" model keeps it.

	  EnemyRig.build(cfg) -> Model?
	  EnemyRig.attachWeapon(model, weapon)
	  EnemyRig.placeOnGround(model, marker)   stand the model's feet exactly on the floor under a spawn marker (no pop on release)
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

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

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function EnemyRig.attachWeapon(model: Model, weapon: any?)
	if not weapon or model:FindFirstChild("Sword") then
		return
	end
	local arm = model:FindFirstChild("Right Arm") :: BasePart?
	if not (arm and weapon.kind == "sword") then
		return
	end
	local length = weapon.bladeLength or 4
	local sword = Instance.new("Model")
	sword.Name = "Sword"

	-- the hand is the bottom of the arm; the blade runs on along the arm's -Y
	local hand = arm.CFrame * CFrame.new(0, -1, 0)
	local grip = part("Grip", Vector3.new(0.28, 0.9, 0.28), weapon.gripColor or Color3.fromRGB(50, 35, 30), Enum.Material.Wood)
	grip.CFrame = hand * CFrame.new(0, -0.05, 0)
	local guard = part("Guard", Vector3.new(1.5, 0.22, 0.45), weapon.guardColor or Color3.fromRGB(70, 60, 55), Enum.Material.Metal)
	guard.CFrame = hand * CFrame.new(0, -0.55, 0)
	local blade = part("Blade", Vector3.new(0.12, length, 0.5), weapon.bladeColor or Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
	blade.CFrame = hand * CFrame.new(0, -0.66 - length / 2, 0)

	local trailA = Instance.new("Attachment")
	trailA.Name = "TrailA"
	trailA.Position = Vector3.new(0, -length / 2 + 0.3, 0)
	trailA.Parent = blade
	local trailB = Instance.new("Attachment")
	trailB.Name = "TrailB"
	trailB.Position = Vector3.new(0, length / 2, 0)
	trailB.Parent = blade

	for _, piece in ipairs({ grip, guard, blade }) do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = arm
		weld.Part1 = piece
		weld.Parent = piece
		piece.Parent = sword
	end
	sword.PrimaryPart = blade
	sword.Parent = model
end

return EnemyRig
