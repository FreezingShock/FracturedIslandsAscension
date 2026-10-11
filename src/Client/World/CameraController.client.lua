--[[
	CameraController (LocalScript)
	Place inside: StarterPlayerScripts

	Minecraft-style view:
	  * First person by default, mouse look with the cursor locked to the middle of the screen.
	  * R cycles three phases, blended smoothly: first person -> third person over the shoulder
	    (character faces where you look) -> free camera, just like Roblox (cursor free, hold right mouse to look
	    around, wheel zooms, character turns to its walking direction). R from the free camera returns to first
	    person with the cursor locked again.
	  * T toggles the cursor in the first two phases (first person and over the shoulder). The cursor is also free while a menu / the inventory is
	    open, while typing, and while Roblox's own menu is open.
	  * While the cursor is free the camera stands still (except the free camera while right mouse is held).

	The camera is Scriptable (own mouse look + collision) so the phase blend is smooth and the lock logic has
	exactly one owner. Desktop only: touch-only devices keep Roblox's default camera.

	GUI: ReplicatedStorage-free. The view labels are hand-made in Studio
	(StarterGui.ViewMenu > View [CanvasGroup] > POV [TextLabel] and Cursor [TextLabel]); this script only sets their
	rich text, eases POV's main text colour between perspectives and fades the Cursor label (phases 1-2 only).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MenuBridge = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MenuBridge")) :: any
local MovementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MovementConfig")) :: any
local ViewMenuConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("ViewMenuConfig")) :: any
local UserGameSettings = UserSettings():GetService("UserGameSettings")
local CameraConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("CameraConfig")) :: any
local CameraFeel = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CameraFeel")) :: any

-- ===================== CONFIG =====================
local PHASES = {
	-- fov = vertical field of view in degrees (Roblox default 70, max 120); it blends between phases like the distance
	{ name = "first", distance = 0, shoulder = 0, faceCamera = true, fov = 100 },
	{ name = "shoulder", distance = 8, shoulder = 2.4, faceCamera = true, fov = 75 },
	{ name = "free", distance = 11, shoulder = 0, faceCamera = false, fov = 70 }, -- distance follows the wheel zoom
}
local FREE_PHASE = 3
local FREE_ZOOM_MIN, FREE_ZOOM_MAX, FREE_ZOOM_STEP = 3, 30, 1.5
local BLEND_SPEED = 9 -- higher = snappier phase blend
local RADIANS_PER_PIXEL = 0.0035 -- times Roblox's mouse sensitivity setting
local GAMEPAD_SPEED = Vector2.new(2.8, 2.2) -- radians per second at full stick
local MAX_PITCH = math.rad(80)
local FIRST_PERSON_BELOW = 0.4 -- camera distance where the body is fully hidden
local THIRD_PERSON_ABOVE = 1.7 -- camera distance where the body is fully visible
local HEAD_TO_CHEST = Vector3.new(0, 1.6, 0) -- third person focus above the root part
local SKIP_FRAMES_AFTER_LOCK = 2 -- ignore the mouse jump when the cursor locks again

-- view labels: rich text for the POV label per phase (the label's own TextColor3 is the main colour and eases between them;
-- the gray dash and the coloured keyword are rich-text spans from ViewMenuConfig.format: WORD — value) and the two states of the Cursor label
local POV_STYLE = {
	{ text = "FIRST PERSON", color = Color3.fromRGB(85, 85, 255) },
	{
		text = ViewMenuConfig.format("THIRD PERSON", nil, "OTS", "#FFAA00"),
		color = Color3.fromRGB(255, 85, 255),
	},
	{
		text = ViewMenuConfig.format("THIRD PERSON", nil, "FREE", "#55FF55"),
		color = Color3.fromRGB(170, 0, 170),
	},
}
local CURSOR_LOCKED = ViewMenuConfig.format("CURSOR LOCKED", "#55FF55", "T", "#FFFF55")
local CURSOR_UNLOCKED = ViewMenuConfig.format("CURSOR UNLOCKED", "#55FFFF", "T", "#FFFF55")
local COLOR_EASE = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad)

-- ===================== STATE =====================
local phase = 1
player:SetAttribute("CameraMode", PHASES[1].name) -- read by DropTooltipController (idleNearestModes)
player:SetAttribute("FirstPersonFov", PHASES[1].fov) -- DeathController ends its respawn swing at exactly this view
local distance = PHASES[1].distance -- smoothed values
local shoulder = PHASES[1].shoulder
local fov = PHASES[1].fov
local sprintFov = 0 -- extra field of view while sprinting (MovementConfig.sprint.fovBonus), eased in and out
local yaw, pitch = 0, 0
local cursorFree = false -- toggled with T
local rightMouseDown = false -- the free camera looks around while right mouse is held
local locked = false -- the mouse currently drives the camera
local skipFrames = 0
local lean = 0 -- the body's tilt in radians (CameraConfig.defaults.lean), eased
local tilt = 0 -- the camera's roll into the strafe in radians (CameraConfig.defaults.lean.rollDegrees), eased
local drift = Vector3.zero -- the over-the-shoulder camera's drift in camera space (CameraConfig.defaults.drift), eased
local leanJoint: Motor6D? = nil -- the joint that tilts the upper body (Waist for R15, RootJoint for R6)
local leanBase: CFrame? = nil -- that joint's resting C0
local focusPoint: Vector3? = nil -- where the camera looks, eased toward the body (CameraConfig.defaults.follow)

local character: Model? = nil
local bodyParts: { BasePart } = {}
local lastFade = -1

-- ===================== CHARACTER =====================
-- Exact names only: accessories are parts called "Handle", which must stay hidden with the head
local ARM_PARTS = {
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
	["Left Arm"] = true, -- R6
	["Right Arm"] = true,
}
local function isArm(part: BasePart): boolean
	return ARM_PARTS[part.Name] == true and not part:FindFirstAncestorOfClass("Accessory")
end

local function collectBodyParts()
	table.clear(bodyParts)
	lastFade = -1
	if not character then
		return
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") and not d:FindFirstAncestorOfClass("Tool") and not isArm(d) then
			table.insert(bodyParts, d)
		end
	end
end

-- the joint that tilts the upper body (R15 Waist, R6 RootJoint); lean is only applied when one exists
local function findLeanJoint(char: Model): (Motor6D?, CFrame?)
	local joint = char:FindFirstChild("Waist", true)
	if not (joint and joint:IsA("Motor6D")) then
		joint = char:FindFirstChild("RootJoint", true)
	end
	if joint and joint:IsA("Motor6D") then
		return joint, joint.C0
	end
	return nil, nil
end

local function onCharacter(char: Model)
	character = char
	lean, tilt, drift = 0, 0, Vector3.zero
	-- every new body starts in first person, looking where it faces, cursor locked
	phase = 1
	player:SetAttribute("CameraMode", PHASES[1].name)
	distance, shoulder, fov = PHASES[1].distance, PHASES[1].shoulder, PHASES[1].fov
	cursorFree = false
	collectBodyParts()
	leanJoint, leanBase = findLeanJoint(char)
	char.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and not d:FindFirstAncestorOfClass("Tool") and not isArm(d) then
			table.insert(bodyParts, d)
			lastFade = -1
		end
	end)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	if root then
		local _, y = (root :: BasePart).CFrame:ToOrientation()
		yaw, pitch = y, 0
	end
	skipFrames = SKIP_FRAMES_AFTER_LOCK
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	task.spawn(onCharacter, player.Character)
end

-- ===================== VIEW LABELS (hand-made in Studio) =====================
local viewGroup: CanvasGroup? = nil
local povLabel: TextLabel? = nil
local cursorLabel: TextLabel? = nil
local cursorStroke: UIStroke? = nil
task.spawn(function()
	local gui = playerGui:WaitForChild("ViewMenu", 10)
	if not gui then
		warn("[CameraController] StarterGui.ViewMenu is missing: no view labels will be shown")
		return
	end
	local group = gui:WaitForChild("View") :: CanvasGroup
	local pov = group:WaitForChild("POV") :: TextLabel
	local cursor = group:WaitForChild("Cursor") :: TextLabel
	pov.RichText = true
	cursor.RichText = true
	cursorStroke = cursor:FindFirstChildOfClass("UIStroke")
	group.GroupTransparency = 1
	povLabel, cursorLabel, viewGroup = pov, cursor, group
end)

local tweens: { [string]: Tween } = {}
local function play(key: string, object: Instance, info: TweenInfo, goal: { [string]: any })
	if tweens[key] then
		tweens[key]:Cancel()
	end
	tweens[key] = TweenService:Create(object, info, goal)
	tweens[key]:Play()
end

local shownGroup: boolean? = nil
local shownCursor: boolean? = nil
local shownPhase: number? = nil
local shownCursorFree: boolean? = nil
local function updateView(showGroup: boolean)
	local group, pov, cursor = viewGroup, povLabel, cursorLabel
	if not (group and pov and cursor) then
		return
	end
	if shownGroup ~= showGroup then
		shownGroup = showGroup
		play("group", group, FADE, { GroupTransparency = showGroup and 0 or 1 })
	end
	if shownPhase ~= phase then
		shownPhase = phase
		local style = POV_STYLE[phase]
		pov.Text = style.text
		play("povColor", pov, COLOR_EASE, { TextColor3 = style.color }) -- eases the main colour between perspectives
	end
	if shownCursorFree ~= cursorFree then
		shownCursorFree = cursorFree
		cursor.Text = cursorFree and CURSOR_UNLOCKED or CURSOR_LOCKED
	end
	local cursorVisible = phase ~= FREE_PHASE -- the free camera always has a free cursor, so T means nothing there
	if shownCursor ~= cursorVisible then
		shownCursor = cursorVisible
		play("cursor", cursor, FADE, { TextTransparency = cursorVisible and 0 or 1 })
		if cursorStroke then
			play("cursorStroke", cursorStroke, FADE, { Transparency = cursorVisible and 0 or 1 })
		end
	end
end

-- ===================== INPUT =====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		phase = phase % #PHASES + 1
		player:SetAttribute("CameraMode", PHASES[phase].name)
		cursorFree = false -- every phase change starts with the cursor locked (the free camera ignores it)
	elseif input.KeyCode == Enum.KeyCode.T then
		if phase ~= FREE_PHASE and not MenuBridge.isOpen() then
			cursorFree = not cursorFree
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouseDown = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		rightMouseDown = false
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseWheel and not gameProcessed and phase == FREE_PHASE and not MenuBridge.isOpen() then
		PHASES[FREE_PHASE].distance = math.clamp(PHASES[FREE_PHASE].distance - input.Position.Z * FREE_ZOOM_STEP, FREE_ZOOM_MIN, FREE_ZOOM_MAX)
	end
end)

local function readLookDelta(dt: number): Vector2
	local delta = UserInputService:GetMouseDelta()
	local look = Vector2.new(delta.X, delta.Y) * (UserGameSettings.MouseSensitivity * RADIANS_PER_PIXEL)
	for _, state in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if state.KeyCode == Enum.KeyCode.Thumbstick2 then
			local p = state.Position
			if math.abs(p.X) > 0.15 or math.abs(p.Y) > 0.15 then
				look += Vector2.new(p.X * GAMEPAD_SPEED.X * dt, -p.Y * GAMEPAD_SPEED.Y * dt)
			end
		end
	end
	return look
end

-- ===================== CAMERA =====================
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

--- How the mouse should behave right now. Phases 1-2: cursor locked to the centre unless T / a menu / typing
--- frees it. Free camera: cursor always free; holding right mouse freezes it in place and looks around.
local function wantedMouseBehavior(): Enum.MouseBehavior
	if player:GetAttribute("IntroActive") or MenuBridge.isOpen() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil then
		return Enum.MouseBehavior.Default
	end
	if phase == FREE_PHASE then
		return rightMouseDown and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
	end
	return cursorFree and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
end

local function updateCamera(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if player:GetAttribute("IntroActive") then
		return -- the loading screen's cutscene owns the camera until Play
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	if player:GetAttribute("DeathCam") then
		return -- DeathController drives the camera while your own death plays
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and humanoid and root) then
		return
	end

	-- look
	if locked then
		if skipFrames > 0 then
			skipFrames -= 1
			UserInputService:GetMouseDelta() -- drain the jump
		else
			local look = readLookDelta(dt)
			yaw -= look.X
			pitch = math.clamp(pitch - look.Y, -MAX_PITCH, MAX_PITCH)
		end
	end

	-- phase blend
	local target = PHASES[phase]
	local alpha = 1 - math.exp(-dt * BLEND_SPEED)
	distance += (target.distance - distance) * alpha
	shoulder += (target.shoulder - shoulder) * alpha
	fov += (target.fov - fov) * alpha
	local sprintTarget = player:GetAttribute("Sprinting") and MovementConfig.sprint.fovBonus or 0
	sprintFov += (sprintTarget - sprintFov) * (1 - math.exp(-dt * MovementConfig.sprint.fovSpeed))
	if math.abs(sprintFov - sprintTarget) < 0.01 then
		sprintFov = sprintTarget
	end
	if math.abs(distance - target.distance) < 0.005 then
		distance = target.distance
	end

	-- focus: the eyes in first person, the upper body in third person
	local head = character:FindFirstChild("Head") :: BasePart?
	local eyes = head and head.Position or (root.Position + Vector3.new(0, 1.5, 0))
	local chest = root.Position + HEAD_TO_CHEST
	local thirdBlend = math.clamp(distance / 2.5, 0, 1)
	local bodyFocus = eyes:Lerp(chest, thirdBlend)

	-- feel: the spring kicks, whip and punch come from CameraFeel (one sample per frame)
	local feel = CameraFeel.sample(dt, target.name)
	-- the focus follows the body closely; while a dash trails, it lags, so the camera slides after you instead of snapping
	local followConfig = CameraConfig.defaults.follow
	if not focusPoint or (bodyFocus - focusPoint).Magnitude > followConfig.teleportStuds then
		focusPoint = bodyFocus -- first frame, a respawn or a teleport too big to ease: snap
	end
	local followSpeed = feel.trailing and followConfig.trailSpeed or followConfig.speed
	focusPoint = (focusPoint :: Vector3):Lerp(bodyFocus, 1 - math.exp(-dt * followSpeed))
	local focus = focusPoint :: Vector3

	local viewRotation = CFrame.fromOrientation(pitch + feel.pitch, yaw + feel.yaw, 0) -- no tilt: input directions use this
	local modeScale = CameraConfig.modes[target.name] or { lean = 1, roll = 1, drift = 1 }
	local leanConfig = CameraConfig.defaults.lean
	local driftConfig = CameraConfig.defaults.drift

	-- Movement intent: the key direction in camera space drives the tilt, so a start and a stop read at once. The measured
	-- speed only decides whether you are moving at all (no tilt while standing still).
	local velocity = root.AssemblyLinearVelocity
	local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local intent = viewRotation:VectorToObjectSpace(humanoid.MoveDirection)
	local strafe = math.clamp(intent.X, -1, 1)
	local forward = math.clamp(-intent.Z, -1, 1)
	local engaged = moving > leanConfig.deadzone and 1 or 0

	-- the body leans into the strafe, and the camera rolls into it (the tilt you see in first person)
	if not (leanJoint and leanJoint.Parent) then
		leanJoint, leanBase = findLeanJoint(character) -- the rig's joints can appear a moment after the character spawns
	end
	local smoothing = 1 - math.exp(-dt * leanConfig.speed)
	local leanTarget = -strafe * math.rad(leanConfig.maxDegrees) * modeScale.lean * engaged
	local tiltTarget = -strafe * math.rad(leanConfig.rollDegrees) * modeScale.roll * engaged
	lean += (leanTarget - lean) * smoothing
	tilt += (tiltTarget - tilt) * smoothing
	if leanJoint and leanBase then
		leanJoint.C0 = leanBase * CFrame.Angles(0, 0, lean)
	end
	local rotation = CFrame.fromOrientation(pitch + feel.pitch, yaw + feel.yaw, feel.roll + tilt)

	-- the over-the-shoulder camera drifts a little toward the way you move (lagged, eased)
	local driftTarget = Vector3.new(strafe * driftConfig.maxStuds, 0, -forward * driftConfig.maxStuds * 0.4) * modeScale.drift * engaged
	drift = drift:Lerp(driftTarget, 1 - math.exp(-dt * driftConfig.speed))

	local position = focus
	if distance > 0.01 then
		local desired = focus + rotation:VectorToWorldSpace(Vector3.new(shoulder, 0, distance) + drift)
		rayParams.FilterDescendantsInstances = { character }
		local offset = desired - focus
		local hit = workspace:Raycast(focus, offset, rayParams)
		position = hit and (hit.Position - offset.Unit * 0.4) or desired
	end
	camera.CFrame = CFrame.new(position + rotation:VectorToWorldSpace(feel.offset)) * rotation
	camera.Focus = CFrame.new(focus)
	camera.FieldOfView = fov + sprintFov + feel.fov

	-- hide the body in first person (arms and held items stay), fade it back in as the camera pulls away
	local fade = math.clamp((THIRD_PERSON_ABOVE - distance) / (THIRD_PERSON_ABOVE - FIRST_PERSON_BELOW), 0, 1)
	if math.abs(fade - lastFade) > 0.002 then
		lastFade = fade
		for _, part in ipairs(bodyParts) do
			part.LocalTransparencyModifier = fade
		end
	end

	-- body orientation
	if target.faceCamera then
		if humanoid.AutoRotate then
			humanoid.AutoRotate = false
		end
		if locked and humanoid.Health > 0 and not humanoid.Sit then
			root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
		end
	elseif not humanoid.AutoRotate then
		humanoid.AutoRotate = true
	end
end

-- Camera feel listens to what already happens: sword blows and deaths. Ability shakes come from AbilityController.
local weaponHit = ReplicatedStorage:WaitForChild("WeaponHit") :: RemoteEvent
weaponHit.OnClientEvent:Connect(function(data)
	if type(data) == "table" and typeof(data.position) == "Vector3" then
		CameraFeel.shake("hit", typeof(data.point) == "Vector3" and data.point or data.position)
	end
end)

local entityDeath = ReplicatedStorage:WaitForChild("EntityDeath") :: RemoteEvent
entityDeath.OnClientEvent:Connect(function(model, _kind, deathType)
	-- your own death: DeathController's glitch owns the shake (DeathCam is on), so nothing is added here
	if player:GetAttribute("DeathCam") or model == player.Character then
		return
	end
	if typeof(model) == "Instance" and model:IsA("Model") then
		CameraFeel.shake(CameraFeel.shakeFor(deathType), model:GetPivot().Position)
	end
end)

RunService:BindToRenderStep("FIACameraController", Enum.RenderPriority.Camera.Value + 1, function(dt)
	updateCamera(dt)
end)

-- The cursor lock runs last so nothing else (Roblox's own camera scripts) overrides it for the frame.
RunService:BindToRenderStep("FIACursorLock", Enum.RenderPriority.Last.Value, function()
	local behavior = wantedMouseBehavior()
	local shouldLock = behavior ~= Enum.MouseBehavior.Default
	if shouldLock and not locked then
		skipFrames = SKIP_FRAMES_AFTER_LOCK
	end
	locked = shouldLock
	UserInputService.MouseBehavior = behavior
	UserInputService.MouseIconEnabled = not shouldLock
	updateView(not MenuBridge.isOpen())
end)
