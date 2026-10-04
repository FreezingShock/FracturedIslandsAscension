--[[
	CameraController (LocalScript)
	Place inside: StarterPlayerScripts

	Minecraft-style view:
	  * First person by default, mouse look with the cursor locked to the middle of the screen.
	  * R cycles three phases, blended smoothly: first person -> third person over the shoulder
	    (character faces where you look) -> free camera, just like Roblox (cursor free, hold right mouse to look
	    around, wheel zooms, character turns to its walking direction). R from the free camera returns to first
	    person with the cursor locked again.
	  * T toggles the cursor in the first two phases. The cursor is also free while a menu / the inventory is
	    open, while typing, and while Roblox's own menu is open.
	  * While the cursor is free the camera stands still (except the free camera while right mouse is held).

	The camera is Scriptable (own mouse look + collision) so the phase blend is smooth and the lock logic has
	exactly one owner. Desktop only: touch-only devices keep Roblox's default camera.

	GUI: ReplicatedStorage-free. The "Click T to Unlock Cursor" hint is hand-made in Studio
	(StarterGui.CursorHint > Hint [CanvasGroup] > Label); this script only fades it and sets its text.
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
local UserGameSettings = UserSettings():GetService("UserGameSettings")

-- ===================== CONFIG =====================
local PHASES = {
	{ name = "first", distance = 0, shoulder = 0, faceCamera = true },
	{ name = "shoulder", distance = 8, shoulder = 2.4, faceCamera = true },
	{ name = "free", distance = 11, shoulder = 0, faceCamera = false }, -- distance follows the wheel zoom
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

local HINT_LOCKED = 'Click <font color="#FFFF55">T</font> to <font color="#55FF55">Unlock Cursor</font>'
local HINT_FREE = 'Click <font color="#FFFF55">T</font> to <font color="#55FF55">Lock Cursor</font>'

-- ===================== STATE =====================
local phase = 1
local distance = PHASES[1].distance -- smoothed values
local shoulder = PHASES[1].shoulder
local yaw, pitch = 0, 0
local cursorFree = false -- toggled with T
local rightMouseDown = false -- the free camera looks around while right mouse is held
local locked = false -- the mouse currently drives the camera
local skipFrames = 0

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

local function onCharacter(char: Model)
	character = char
	collectBodyParts()
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

-- ===================== HINT LABEL (hand-made in Studio) =====================
local hintGroup: CanvasGroup? = nil
local hintLabel: TextLabel? = nil
task.spawn(function()
	local gui = playerGui:WaitForChild("CursorHint", 10)
	if not gui then
		warn("[CameraController] StarterGui.CursorHint is missing: no cursor hint will be shown")
		return
	end
	hintGroup = gui:WaitForChild("Hint") :: CanvasGroup
	hintLabel = (hintGroup :: CanvasGroup):WaitForChild("Label") :: TextLabel
	(hintLabel :: TextLabel).RichText = true
	;(hintGroup :: CanvasGroup).GroupTransparency = 1
end)

local hintShown: boolean? = nil
local hintTween: Tween? = nil
local function updateHint(show: boolean)
	if not hintGroup or not hintLabel then
		return
	end
	hintLabel.Text = cursorFree and HINT_FREE or HINT_LOCKED
	if hintShown == show then
		return
	end
	hintShown = show
	if hintTween then
		hintTween:Cancel()
	end
	hintTween = TweenService:Create(hintGroup, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { GroupTransparency = show and 0 or 1 })
	hintTween:Play()
end

-- ===================== INPUT =====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		phase = phase % #PHASES + 1
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
	if MenuBridge.isOpen() or GuiService.MenuIsOpen or UserInputService:GetFocusedTextBox() ~= nil then
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
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
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
	if math.abs(distance - target.distance) < 0.005 then
		distance = target.distance
	end

	-- focus: the eyes in first person, the upper body in third person
	local head = character:FindFirstChild("Head") :: BasePart?
	local eyes = head and head.Position or (root.Position + Vector3.new(0, 1.5, 0))
	local chest = root.Position + HEAD_TO_CHEST
	local thirdBlend = math.clamp(distance / 2.5, 0, 1)
	local focus = eyes:Lerp(chest, thirdBlend)

	local rotation = CFrame.fromOrientation(pitch, yaw, 0)
	local position = focus
	if distance > 0.01 then
		local desired = focus + rotation:VectorToWorldSpace(Vector3.new(shoulder, 0, distance))
		rayParams.FilterDescendantsInstances = { character }
		local offset = desired - focus
		local hit = workspace:Raycast(focus, offset, rayParams)
		position = hit and (hit.Position - offset.Unit * 0.4) or desired
	end
	camera.CFrame = CFrame.new(position) * rotation
	camera.Focus = CFrame.new(focus)

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
	updateHint(phase == 1 and not MenuBridge.isOpen())
end)
