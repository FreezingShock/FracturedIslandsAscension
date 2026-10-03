-- CloudConfig.lua
-- Centralized configuration for the volumetric cloud system
-- Placed in ReplicatedStorage.Config

local CloudConfig = {}

-- ===== FOLDER & SCANNING =====
CloudConfig.CLOUDS_FOLDER = "Clouds" -- Folder name in Workspace to scan for cloud parts

-- ===== LOD & CULLING =====
CloudConfig.LOD_DISTANCES = {
	ACTIVE_RANGE = 500, -- Distance to fully render clouds (studs)
	FADE_START = 350, -- Distance to begin fading (studs)
	FADE_END = 500, -- Distance to completely hide (studs)
	CHECK_INTERVAL = 0.5, -- Seconds between distance checks
}

-- ===== POOLING & PERFORMANCE =====
CloudConfig.POOLING = {
	MAX_ACTIVE_EMITTERS = 400, -- Far fewer emitters needed
	EMITTER_POOL_SIZE = 600, -- Smaller pool, fewer emitters
	REUSE_THRESHOLD = 200,
}

-- ===== PARTICLE EMITTER SETTINGS =====
-- These are applied to all emitters created within cloud parts
-- Multiple emitters per part positioned in grid for cohesive cloud shape
CloudConfig.EMITTER_TEMPLATES = {
	CLOUD_CORE = {
		-- Long-lived particles: emit rarely, live long
		Enabled = true,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.28),
			NumberSequenceKeypoint.new(0.1, 0.32),
			NumberSequenceKeypoint.new(0.7, 0.42),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(28, 40), -- Much longer (was 12-18)
		Rate = 0,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-2, 2),

		Speed = NumberRange.new(0.001, 0.02),
		Acceleration = Vector3.new(0, 0.0005, 0),
		Drag = 2.0,
		VelocityInheritance = 0,

		Texture = "rbxasset://textures/Particles/smoke_main.dds",
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 12),
			NumberSequenceKeypoint.new(0.3, 16),
			NumberSequenceKeypoint.new(0.7, 20),
			NumberSequenceKeypoint.new(1, 28),
		}),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),

		EmissionDirection = Enum.NormalId.Bottom,
		Enabled = true,
	},

	CLOUD_OUTER = {
		-- Long-lived particles: emit rarely, live long
		Enabled = true,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.32),
			NumberSequenceKeypoint.new(0.1, 0.38),
			NumberSequenceKeypoint.new(0.7, 0.48),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Lifetime = NumberRange.new(25, 38), -- Much longer (was 10-16)
		Rate = 0,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-4, 4),

		Speed = NumberRange.new(0.005, 0.05),
		Acceleration = Vector3.new(0, 0.001, 0),
		Drag = 1.8,
		VelocityInheritance = 0,

		Texture = "rbxasset://textures/Particles/smoke_main.dds",
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 10),
			NumberSequenceKeypoint.new(0.2, 13),
			NumberSequenceKeypoint.new(0.6, 16),
			NumberSequenceKeypoint.new(1, 20),
		}),
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),

		EmissionDirection = Enum.NormalId.Bottom,
		Enabled = true,
	},
}

-- ===== SCALING RULES =====
-- Intelligent scaling: particles stay reasonable size, rate fills volume density
CloudConfig.SCALE_RULES = {
	BASE_SCALE = 1.0,
	-- For large parts: cap particle size growth, boost rate quadratically
	-- A 50-stud part gets many small particles instead of few huge ones
	MAX_PARTICLE_SIZE_SCALE = 2.0, -- Particles never grow beyond 2x base size
	-- Rate scales to compensate: (volume growth / size growth)^2
	-- Ensures particle density stays constant across all part sizes
}

-- ===== COLOR & CUSTOMIZATION PLACEHOLDERS =====
CloudConfig.CUSTOMIZATION = {
	-- [PLACEHOLDER] Future: Allow per-cloud color tint
	CLOUD_COLOR = Color3.fromRGB(220, 220, 220),

	-- [PLACEHOLDER] Future: Wind/drift animation
	DRIFT_ENABLED = false,
	DRIFT_SPEED = 5,

	-- [PLACEHOLDER] Future: Different cloud types by tag
	CLOUD_TYPES = {
		-- SMALL = { rate = 20, lifetime = 4 },
		-- MEDIUM = { rate = 40, lifetime = 6 },
		-- LARGE = { rate = 80, lifetime = 10 },
	},
}

return CloudConfig
