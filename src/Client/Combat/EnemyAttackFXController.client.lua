--[[
	EnemyAttackFXController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Draws what an enemy's attack looks like, from the RemoteEvent EnemyAttack the server (EnemyAttacks) fires to every player in range.
	The client sends nothing and decides nothing: the payload says what to show.
	  telegraph  a flat marker on the ground (circle / line / cone-as-box) that fills up over the windup, so the player sees WHERE and
	             WHEN the hit lands (the body flash is EnemyTelegraphController)
	  swing      the sword's trail (the held Tool's Handle TrailA / TrailB attachments, built by EnemyRig) for the swing's duration
	  impact     an expanding ring on the ground (the slam)
	  parry      a blue guard outline on the enemy while it blocks
	Colours come from the move's telegraph.color (EnemyConfig.attacks); nothing here is per enemy.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local remote = ReplicatedStorage:WaitForChild("EnemyAttack") :: RemoteEvent

local MAX_MARKERS = 12 -- telegraphs alive at once
local live = 0

local function marker(color: Color3, transparency: number): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function isNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -1e6 and value < 1e6
end

local function telegraph(payload: any)
	local origin, dir, duration = payload.origin, payload.dir, payload.duration
	if typeof(origin) ~= "Vector3" or not isNumber(duration) or duration <= 0 or live >= MAX_MARKERS then
		return
	end
	local color = typeof(payload.color) == "Color3" and payload.color or Color3.fromRGB(255, 60, 60)
	local shape = payload.shape
	local lift = Vector3.new(0, 0.18, 0)
	local parts = {}
	local update: (number) -> ()

	if shape == "circle" and isNumber(payload.radius) then
		local diameter = payload.radius * 2
		local outer = marker(color, 0.82)
		outer.Shape = Enum.PartType.Cylinder
		outer.Size = Vector3.new(0.12, diameter, diameter)
		outer.CFrame = CFrame.new(origin + lift) * CFrame.Angles(0, 0, math.pi / 2)
		local fill = marker(color, 0.5)
		fill.Shape = Enum.PartType.Cylinder
		fill.CFrame = outer.CFrame
		parts = { outer, fill }
		update = function(t)
			local d = math.max(diameter * t, 0.1)
			fill.Size = Vector3.new(0.16, d, d)
		end
	elseif (shape == "line" or shape == "cone") and typeof(dir) == "Vector3" and isNumber(payload.length) then
		local length = payload.length
		local width = payload.width
		if not isNumber(width) then
			local arc = isNumber(payload.arc) and payload.arc or 90
			width = math.min(2 * length * math.sin(math.rad(arc / 2)) * 0.8, length * 1.6)
		end
		local forward = Vector3.new(dir.X, 0, dir.Z)
		if forward.Magnitude < 1e-3 then
			return
		end
		local base = CFrame.lookAt(origin + lift, origin + lift + forward.Unit)
		local outer = marker(color, 0.82)
		outer.Size = Vector3.new(width, 0.12, length)
		outer.CFrame = base * CFrame.new(0, 0, -length / 2)
		local fill = marker(color, 0.5)
		parts = { outer, fill }
		update = function(t)
			local l = math.max(length * t, 0.1)
			fill.Size = Vector3.new(width, 0.16, l)
			fill.CFrame = base * CFrame.new(0, 0, -l / 2)
		end
	else
		return
	end

	update(0)
	live += 1
	for _, part in ipairs(parts) do
		part.Parent = workspace
	end
	local started = os.clock()
	local connection: RBXScriptConnection
	connection = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - started) / duration, 0, 1)
		update(t)
		if t >= 1 then
			connection:Disconnect()
			live -= 1
			for _, part in ipairs(parts) do
				TweenService:Create(part, TweenInfo.new(0.15), { Transparency = 1 }):Play()
				task.delay(0.2, function()
					part:Destroy()
				end)
			end
		end
	end)
end

local function swing(model: Model, duration: number)
	local tool = model:FindFirstChildOfClass("Tool")
	local blade = tool and tool:FindFirstChild("Handle") :: BasePart?
	local a = blade and blade:FindFirstChild("TrailA") :: Attachment?
	local b = blade and blade:FindFirstChild("TrailB") :: Attachment?
	if not (blade and a and b) then
		return
	end
	local trail = blade:FindFirstChild("SwingTrail") :: Trail?
	if not trail then
		trail = Instance.new("Trail")
		trail.Name = "SwingTrail"
		trail.Attachment0 = a
		trail.Attachment1 = b
		trail.Lifetime = 0.28
		trail.LightEmission = 0.7
		trail.Color = ColorSequence.new(Color3.fromRGB(255, 235, 200), Color3.fromRGB(255, 120, 60))
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		trail.Parent = blade
	end
	trail.Enabled = true
	task.delay(duration, function()
		if trail.Parent then
			trail.Enabled = false
		end
	end)
end

local function impact(payload: any)
	local origin, radius = payload.origin, payload.radius
	if typeof(origin) ~= "Vector3" or not isNumber(radius) then
		return
	end
	local ring = marker(Color3.fromRGB(255, 200, 150), 0.1)
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 1, 1)
	ring.CFrame = CFrame.new(origin + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	local goal = radius * 2
	TweenService:Create(ring, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, goal, goal),
		Transparency = 1,
	}):Play()
	task.delay(0.45, function()
		ring:Destroy()
	end)
end

local function parry(model: Model, duration: number)
	local old = model:FindFirstChild("ParryGuard")
	if old then
		old:Destroy()
	end
	local color = Color3.fromRGB(110, 170, 255)
	local highlight = Instance.new("Highlight")
	highlight.Name = "ParryGuard"
	highlight.FillColor = color
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = model
	highlight.Parent = model
	TweenService:Create(highlight, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		FillTransparency = 1,
		OutlineTransparency = 0.6,
	}):Play()
	task.delay(duration, function()
		highlight:Destroy()
	end)
end

remote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		return
	end
	local model = payload.model
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model:IsDescendantOf(workspace) then
		return
	end
	if payload.kind == "telegraph" then
		telegraph(payload)
	elseif payload.kind == "swing" and isNumber(payload.duration) then
		swing(model, payload.duration)
	elseif payload.kind == "impact" then
		impact(payload)
	elseif payload.kind == "parry" and isNumber(payload.duration) then
		parry(model, payload.duration)
	end
end)
