-- ============================================================
--  WeaponFX (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Shared effects system for weapons.
--  - Damage numbers (floating text)
--  - Particle effects on hit
--  - Weapon trails
--  - Impact feedback (sound/vibration)
--
-- ============================================================

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local WeaponFX = {}

-- ===================== CONFIG =====================
local DAMAGE_NUMBER_CONFIG = {
	fadeTime = 1.5,
	riseDistance = 30,
	defaultColor = Color3.fromHex("#FFFFFF"),
	critColor = Color3.fromHex("#FF5555"),
	startSize = 32,
	endSize = 24,
}

local PARTICLE_CONFIG = {
	duration = 0.5,
	particleCount = 15,
}

-- ===================== DAMAGE NUMBERS =====================

--- Show floating damage number at world position.
--- Returns the TextLabel instance created.
function WeaponFX.ShowDamageNumber(worldPos, damage, isCrit)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	-- Only show on client
	if not UserInputService then
		return nil
	end

	-- Create ScreenGui if not exists
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end

	local damageGui = playerGui:FindFirstChild("DamageNumbers")
	if not damageGui then
		damageGui = Instance.new("ScreenGui")
		damageGui.Name = "DamageNumbers"
		damageGui.ResetOnSpawn = false
		damageGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		damageGui.Parent = playerGui
	end

	-- Create text label
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "DamageNumber_" .. tostring(tick()):gsub(".", "")
	textLabel.Text = tostring(math.ceil(damage))
	textLabel.TextSize = DAMAGE_NUMBER_CONFIG.startSize
	textLabel.TextStrokeTransparency = 0.5
	textLabel.BackgroundTransparency = 1
	textLabel.AnchorPoint = Vector2.new(0.5, 0.5)

	-- Color based on crit
	if isCrit then
		textLabel.TextColor3 = DAMAGE_NUMBER_CONFIG.critColor
		textLabel.Text = "CRIT! " .. textLabel.Text
	else
		textLabel.TextColor3 = DAMAGE_NUMBER_CONFIG.defaultColor
	end

	-- Position at world location
	local screenPos = camera:WorldToScreenPoint(worldPos)
	textLabel.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	textLabel.Size = UDim2.fromOffset(100, 40)
	textLabel.Parent = damageGui

	-- Tween animation
	local TweenService = game:GetService("TweenService")
	local tweenInfo = TweenInfo.new(
		DAMAGE_NUMBER_CONFIG.fadeTime,
		Enum.EasingStyle.Quint,
		Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(textLabel, tweenInfo, {
		TextTransparency = 1,
		TextSize = DAMAGE_NUMBER_CONFIG.endSize,
		Position = UDim2.fromOffset(screenPos.X, screenPos.Y - DAMAGE_NUMBER_CONFIG.riseDistance),
	})

	tween:Play()
	tween.Completed:Connect(function()
		textLabel:Destroy()
	end)

	return textLabel
end

-- ===================== PARTICLE EFFECTS =====================

--- Create explosion particle effect at position.
function WeaponFX.ParticleExplosion(position, radius, color, duration)
	color = color or Color3.fromHex("#FFAA00")
	radius = radius or 15
	duration = duration or PARTICLE_CONFIG.duration

	-- Spawn particles
	local particleCount = PARTICLE_CONFIG.particleCount
	for i = 1, particleCount do
		local angle = (i / particleCount) * math.pi * 2
		local speed = math.random(50, 150)

		-- Create a small part as particle
		local particle = Instance.new("Part")
		particle.Name = "Particle"
		particle.Shape = Enum.PartType.Ball
		particle.Size = Vector3.new(1, 1, 1)
		particle.CanCollide = false
		particle.CFrame = CFrame.new(position)
		particle.Color = color
		particle.Transparency = 0.3
		particle.TopSurface = Enum.SurfaceType.Smooth
		particle.BottomSurface = Enum.SurfaceType.Smooth
		particle.Parent = workspace

		-- Velocity
		local vx = math.cos(angle) * speed
		local vy = math.random(30, 100)
		local vz = math.sin(angle) * speed
		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Velocity = Vector3.new(vx, vy, vz)
		bodyVelocity.Parent = particle

		-- Fade out
		local TweenService = game:GetService("TweenService")
		local tween = TweenService:Create(
			particle,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)
		tween:Play()

		-- Cleanup
		task.delay(duration, function()
			particle:Destroy()
		end)
	end
end

-- ===================== WEAPON TRAILS =====================

--- Create a trail from a handle part (e.g., sword blade).
--- Returns Trail instance.
function WeaponFX.CreateWeaponTrail(handlePart, color, lifetime)
	if not handlePart then
		return nil
	end

	color = color or Color3.fromHex("#55FF55")
	lifetime = lifetime or 0.1

	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new(color)
	trail.Lifetime = lifetime
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.MinLength = 0
	trail.Parent = handlePart

	return trail
end

-- ===================== KNOCKBACK FEEDBACK =====================

--- Apply knockback to a character via BodyVelocity.
function WeaponFX.ApplyKnockback(character, direction, force, duration)
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		return
	end

	duration = duration or 0.2
	direction = direction.Unit

	-- Create BodyVelocity
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Velocity = direction * force
	bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	bodyVelocity.Parent = humanoidRootPart

	-- Clean up after duration
	task.delay(duration, function()
		bodyVelocity:Destroy()
	end)
end

-- ===================== IMPACT SOUND =====================

--- Play impact sound at position.
function WeaponFX.PlayImpactSound(position, isCrit)
	-- TODO: Find and play sound from workspace.Sounds
	-- Critical hits should use a different sound
end

return WeaponFX
