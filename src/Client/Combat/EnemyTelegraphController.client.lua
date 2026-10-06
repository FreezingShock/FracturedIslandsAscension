--[[
	EnemyTelegraphController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Warns the player before an enemy attack lands: while an Enemy-tagged model has the attribute Telegraph (= the windup
	seconds, set by EnemyService), its body pulses red (a Highlight), brightest right when the hit lands.
--]]

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local COLOR = Color3.fromRGB(255, 50, 50)

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local function onChanged()
		local windup = model:GetAttribute("Telegraph")
		local existing = model:FindFirstChild("TelegraphFlash")
		if type(windup) ~= "number" then
			if existing then
				existing:Destroy()
			end
			return
		end
		if existing then
			existing:Destroy()
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "TelegraphFlash"
		highlight.FillColor = COLOR
		highlight.OutlineColor = COLOR
		highlight.FillTransparency = 0.85
		highlight.OutlineTransparency = 0.4
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model
		TweenService:Create(highlight, TweenInfo.new(windup, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			FillTransparency = 0.25,
			OutlineTransparency = 0,
		}):Play()
	end
	model:GetAttributeChangedSignal("Telegraph"):Connect(onChanged)
	onChanged()
end

for _, model in ipairs(CollectionService:GetTagged("Enemy")) do
	watch(model)
end
CollectionService:GetInstanceAddedSignal("Enemy"):Connect(watch)
