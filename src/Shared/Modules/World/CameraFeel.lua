--[[
	CameraFeel (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > World

	The impulses behind the camera feel: shake, swing kick, blink whip and FOV punch. Hooks (WeaponController,
	AbilityController, CameraController) only call the functions below. CameraController is the only thing that writes
	the camera: once per frame it calls sample(dt, mode) and adds the result to its own CFrame and FieldOfView.

	  CameraFeel.shake(preset, origin?)   tiered shake; falls off with distance from `origin` to the local character
	  CameraFeel.kick(pitch, roll?)       small spring kick, in radians (the view turns up and rolls)
	  CameraFeel.whip(direction)          turns the view toward a world direction, then springs back (blink)
	  CameraFeel.punchFov(degrees)        short field-of-view kick, springs back
	  CameraFeel.sample(dt, mode) -> { offset, pitch, yaw, roll, fov }
	  CameraFeel.shakeFor(name)           the shake preset name for an ability or a death type (nil = none)

	Springs are critically damped: a kick peaks at the value you give it and settles without overshoot. Shakes are smooth
	noise that fades with the square of time, so there is no jitter at the end.
--]]

local Players = game:GetService("Players")

local CameraConfig = require(script.Parent:WaitForChild("Config"):WaitForChild("CameraConfig")) :: any

local CameraFeel = {}

local player = Players.LocalPlayer
local E = math.exp(1)

-- ===================== SPRINGS =====================
-- A spring is { x, v, omega }: x is the offset, v its speed. An impulse adds speed so the offset peaks at `peak`.
type Spring = { x: number, v: number, omega: number }

local function newSpring(omega: number): Spring
	return { x = 0, v = 0, omega = omega }
end

local function kickSpring(spring: Spring, peak: number)
	spring.v += peak * spring.omega * E -- for a critically damped spring this peaks at exactly `peak`
end

local function stepSpring(spring: Spring, dt: number)
	-- a few substeps keep it stable at the 60 fps step and at high stiffness
	local steps = 4
	local h = dt / steps
	for _ = 1, steps do
		local acceleration = -spring.omega * spring.omega * spring.x - 2 * spring.omega * spring.v
		spring.v += acceleration * h
		spring.x += spring.v * h
	end
end

local pitchSpring = newSpring(CameraConfig.swing.omega)
local rollSpring = newSpring(CameraConfig.swing.omega)
local yawSpring = newSpring(CameraConfig.blink.omega)
local fovSpring = newSpring(CameraConfig.blink.omega)

-- ===================== SHAKE =====================
local shakeMagnitude = 0
local shakeStart = 0
local shakeDuration = 0
local shakeSeed = 0

local function presetFor(name: any): any?
	if type(name) == "table" then
		return name -- a literal preset: { magnitude, duration, radius }
	end
	return type(name) == "string" and CameraConfig.shake.presets[name] or nil
end

--- The shake a named death type plays (EntityDeath's deathType), or nil if none.
function CameraFeel.shakeFor(name: string?): string?
	return name and CameraConfig.deathPresets[name] or CameraConfig.deathPresets.default
end

--- A shake from `origin` (a world position), or the character's own position when no origin is given. Strongest one wins.
function CameraFeel.shake(preset: any, origin: Vector3?)
	local config = presetFor(preset)
	if not config then
		return
	end
	local falloff = 1
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if origin and root then
		falloff = math.clamp(1 - (origin - root.Position).Magnitude / config.radius, 0, 1)
	end
	if falloff <= 0 then
		return
	end
	local now = os.clock()
	local current = 0
	if now - shakeStart < shakeDuration then
		local progress = (now - shakeStart) / shakeDuration
		current = shakeMagnitude * (1 - progress) ^ 2
	end
	local magnitude = config.magnitude * falloff
	if magnitude > current then
		shakeMagnitude = magnitude
		shakeStart = now
		shakeDuration = config.duration
		shakeSeed = math.random() * 1000
	end
end

-- ===================== KICK / WHIP / PUNCH =====================
--- A swing starts: the view kicks (pitch up, roll to one side). Degrees come from CameraConfig.swing.
function CameraFeel.kick(pitch: number, roll: number?)
	kickSpring(pitchSpring, pitch)
	if roll then
		kickSpring(rollSpring, roll)
	end
end

--- A blink dash: the view turns toward `direction` (a world vector) and springs back.
function CameraFeel.whip(direction: Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local side = flat.Unit:Dot(camera.CFrame.RightVector)
	if math.abs(side) < 0.05 then
		return -- straight ahead or straight back: no sideways whip, the punch still plays
	end
	-- yaw decreases to turn right (mouse right does the same in CameraController)
	kickSpring(yawSpring, -math.sign(side) * math.rad(CameraConfig.blink.whipDegrees))
end

--- A short field-of-view kick, in degrees.
function CameraFeel.punchFov(degrees: number)
	kickSpring(fovSpring, degrees)
end

local trailUntil = 0

--- The camera trails the body for `seconds` (its focus eases slowly, so a teleport like a dash slides instead of snapping).
function CameraFeel.trail(seconds: number)
	trailUntil = math.max(trailUntil, os.clock() + seconds)
end

-- ===================== SAMPLE =====================
local MODE_SHAKE = CameraConfig.modes

--- Advance every spring and the shake by dt and return the offsets for this frame. Call once per rendered frame.
function CameraFeel.sample(dt: number, mode: string?): { offset: Vector3, pitch: number, yaw: number, roll: number, fov: number }
	local step = math.min(dt, 1 / 30)
	stepSpring(pitchSpring, step)
	stepSpring(rollSpring, step)
	stepSpring(yawSpring, step)
	stepSpring(fovSpring, step)

	local now = os.clock()
	local offset = Vector3.zero
	local age = now - shakeStart
	if age < shakeDuration and shakeMagnitude > 0 then
		local fade = (1 - age / shakeDuration) ^ 2
		local amount = shakeMagnitude * fade * ((MODE_SHAKE[mode or ""] or { shake = 1 }).shake or 1)
		local f = CameraConfig.defaults.shakeFrequency
		local t = now * f
		offset = Vector3.new(
			math.noise(t, shakeSeed, 0) * 2,
			math.noise(t, shakeSeed + 17, 0) * 2,
			math.noise(t, shakeSeed + 41, 0) * 2
		) * amount
	end

	return {
		offset = offset,
		pitch = pitchSpring.x,
		yaw = yawSpring.x,
		roll = rollSpring.x,
		fov = fovSpring.x,
		trailing = now < trailUntil,
	}
end

return CameraFeel
