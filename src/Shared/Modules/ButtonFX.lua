--[[
	ButtonFX (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	Client-side juice for world-button presses. Called by ButtonClientManager
	each time the server confirms a purchase (ButtonPurchaseResult):

	  ButtonFX.onPurchase(data)   -- data = { skill, statKey, gain, owned, costs }

	Finds the pad the player is standing on, then:
	  - bursts colored sparkles off the pad (native ParticleEmitter)
	  - floats a "+gain Name" label up from the pad and fades it out

	Pure visuals: the server never trusts or reads any of this.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local Modules = ReplicatedStorage:WaitForChild("Modules")
local StatisticsConfig = require(Modules:WaitForChild("StatisticsConfig")) :: any
local MoneyLib = require(Modules:WaitForChild("MoneyLib")) :: any

local ButtonFX = {}

-- ===================== CONFIG =====================
local MAX_PAD_DISTANCE = 5 -- studs (horizontal) from the player to count as "standing on" a pad
local BURST_COUNT = 5
local FLOAT_TIME = 0.9
local FLOAT_RISE = 4 -- studs
local MIN_LABEL_GAP = 0.12 -- seconds; throttles labels per pad
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dna"

-- ===================== PAD CACHE =====================
local pads = {} -- [Top part] = { emitter = ParticleEmitter?, lastLabel = number }

local function isPadTop(inst: Instance): boolean
	return inst:IsA("BasePart") and inst.Name == "Top" and inst.Parent ~= nil and string.sub(inst.Parent.Name, 1, 7) == "Button."
end

local function register(top: BasePart)
	if not pads[top] then
		pads[top] = { emitter = nil, lastLabel = 0 }
	end
end

local buttons = workspace:WaitForChild("Buttons")
for _, d in ipairs(buttons:GetDescendants()) do
	if isPadTop(d) then
		register(d)
	end
end
buttons.DescendantAdded:Connect(function(d)
	-- Name/parent may not be final on the frame the descendant is added.
	task.defer(function()
		if isPadTop(d) then
			register(d)
		end
	end)
end)
buttons.DescendantRemoving:Connect(function(d)
	pads[d] = nil
end)

local function findPadUnderPlayer(): BasePart?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return nil
	end
	local best, bestDist = nil, MAX_PAD_DISTANCE
	for top in pairs(pads) do
		local d = Vector2.new(top.Position.X - hrp.Position.X, top.Position.Z - hrp.Position.Z).Magnitude
		if d < bestDist and math.abs(top.Position.Y - hrp.Position.Y) < 8 then
			best, bestDist = top, d
		end
	end
	return best
end

-- ===================== EFFECTS =====================
local function getEmitter(top: BasePart, color: Color3): ParticleEmitter
	local entry = pads[top]
	local emitter = entry.emitter
	if not emitter or not emitter.Parent then
		emitter = Instance.new("ParticleEmitter")
		emitter.Name = "PressSparkle"
		emitter.Texture = SPARKLE_TEXTURE
		emitter.Rate = 0
		emitter.Lifetime = NumberRange.new(0.5, 0.9)
		emitter.Speed = NumberRange.new(6, 11)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Acceleration = Vector3.new(0, -8, 0)
		emitter.LightEmission = 1
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = top
		entry.emitter = emitter
	end
	emitter.Color = ColorSequence.new(color)
	return emitter
end

local function floatLabel(top: BasePart, text: string, color: Color3)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PressPopup"
	gui.Adornee = top
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(180, 30)
	gui.StudsOffset = Vector3.new((math.random() - 0.5) * 1.5, 2.5, 0)
	gui.LightInfluence = 0
	gui.Parent = top

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.RichText = true
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	local info = TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, info, { StudsOffset = gui.StudsOffset + Vector3.new(0, FLOAT_RISE, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	}):Play()
	task.delay(FLOAT_TIME + 0.05, function()
		gui:Destroy()
	end)
end

-- ===================== PUBLIC =====================
function ButtonFX.onPurchase(data)
	if type(data) ~= "table" then
		return
	end
	local top = findPadUnderPlayer()
	if not top then
		return
	end

	local cfg = StatisticsConfig.statConfigLookup[data.skill] and StatisticsConfig.statConfigLookup[data.skill][data.statKey]
	local ok, color = pcall(Color3.fromHex, cfg and cfg.color or "#FFFFFF")
	if not ok then
		color = Color3.new(1, 1, 1)
	end

	getEmitter(top, color):Emit(BURST_COUNT)

	local entry = pads[top]
	local now = os.clock()
	if now - entry.lastLabel >= MIN_LABEL_GAP then
		entry.lastLabel = now
		floatLabel(top, "+" .. MoneyLib.DealWithPoints(math.floor(data.gain or 0)), color)
	end
end

return ButtonFX
