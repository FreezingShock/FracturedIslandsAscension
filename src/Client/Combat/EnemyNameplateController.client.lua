--[[
	EnemyNameplateController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	A name and health bar over the head of every model tagged "Enemy" whose EnemyConfig entry has nameplate = true.
	Cloned from the hand-made template ReplicatedStorage.GUI.EnemyNameplate (restyle it in Studio; the script only looks up
	these names): BillboardGui > NameLabel (TextLabel), Bar (Frame) > Fill (Frame, its width = health fraction).
	The name is the model attribute EnemyName, else EnemyConfig.enemies[EnemyType].name. No UI is built here.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local EnemyConfig = require(Modules:WaitForChild("EnemyConfig")) :: any
local template = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("EnemyNameplate") :: BillboardGui

local FILL_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function attach(model: Instance)
	if not model:IsA("Model") or model:FindFirstChild("EnemyNameplate") then
		return
	end
	local entry = EnemyConfig.get(model:GetAttribute("EnemyType"))
	local humanoid = model:WaitForChild("Humanoid", 5) :: Humanoid?
	local head = model:WaitForChild("Head", 5) :: BasePart?
	if not (entry.nameplate and humanoid and head) then
		return
	end

	local gui = template:Clone()
	gui.Name = "EnemyNameplate"
	gui.Adornee = head
	local nameLabel = gui:FindFirstChild("NameLabel") :: TextLabel?
	if nameLabel then
		nameLabel.Text = model:GetAttribute("EnemyName") or entry.name
	end
	local fill = gui:FindFirstChild("Bar") and gui.Bar:FindFirstChild("Fill") :: Frame?

	local function refresh()
		if humanoid.Health <= 0 then
			gui.Enabled = false
			return
		end
		if fill then
			local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
			TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(fraction, 1) }):Play()
		end
	end
	humanoid.HealthChanged:Connect(refresh)
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1), 1)
	end
	gui.Parent = model
end

for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
	task.spawn(attach, model)
end
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(model)
	task.spawn(attach, model)
end)
