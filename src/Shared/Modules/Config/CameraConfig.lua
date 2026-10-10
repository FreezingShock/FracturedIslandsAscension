--[[
	CameraConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	Camera feel: lean, over-the-shoulder drift, shake, swing kick, blink whip and FOV punch. CameraController is the only
	writer of the camera; CameraFeel holds the impulses; both read these numbers. Same layering as AbilityConfig:

	1. DEFAULTS    CameraConfig.defaults                     the base numbers for every feel
	2. MODES       CameraConfig.modes[first | shoulder | free]   per-view multipliers on the defaults
	3. PRESETS     CameraConfig.shake.presets[name]          one shake: magnitude (studs), duration (s), radius (studs)
	4. ABILITY     AbilityConfig.fx.<id>.shake = "<preset>" | false   one ability's shake (absent = abilityPreset)

	Recipes
	  New shake for an ability ....... add shake = "explosion" (or any preset) to its AbilityConfig.fx entry
	  New shake for a death type ..... add a deathPresets.<deathType> = "<preset>" row here
	  Stronger lean in first person .. modes.first.lean = 1
	  Turn a feel off ................ set its multiplier to 0 in the mode (or the default for everywhere)

	Shakes do not stack: when a second one arrives while the first still runs, the stronger one wins.
--]]

local CameraConfig = {}

CameraConfig.defaults = {
	lean = {
		maxDegrees = 4, -- the body tilts this far into a full strafe (walk speed)
		rollDegrees = 4, -- the camera rolls this far into the same strafe (the tilt you see in first person)
		speed = 10, -- how quickly the lean follows the input (higher = snappier)
		deadzone = 0.5, -- studs/s: below this the body stands straight
	},
	drift = {
		maxStuds = 0.6, -- the over-the-shoulder camera drifts this far toward the way you move
		speed = 7, -- how quickly the drift follows (lower = more lag)
		deadzone = 0.5,
	},
	swing = {
		pitchDegrees = 1.2, -- the view kicks up this far when a swing starts
		rollDegrees = 1.5, -- and rolls this far, alternating sides each combo step
		omega = 24, -- spring stiffness (rad/s); higher snaps back faster
	},
	blink = {
		whipDegrees = 6, -- the view turns this far toward a sideways dash, then springs back
		punchFov = 4, -- degrees of field of view added on the dash, then eased out
		omega = 12, -- spring stiffness for the whip and the punch
		trailSeconds = 0.45, -- how long the camera trails the dash before catching up
	},
	follow = {
		speed = 30, -- how tightly the camera's focus follows the body (higher = closer)
		trailSpeed = 6, -- while a dash is trailing: the focus lags behind the body, so the camera slides after it
		teleportStuds = 60, -- a jump farther than this (respawn) snaps the focus instead of easing
	},
	shakeFrequency = 22, -- how fast the shake wobbles (noise cycles per second)
}

-- Multipliers per view (CameraController phases). 1 = as the defaults; 0 = off.
CameraConfig.modes = {
	first = { lean = 0.5, roll = 1, drift = 0.15, shake = 1 }, -- the body is hidden, so the camera roll carries the tilt
	shoulder = { lean = 1, roll = 1, drift = 1, shake = 1 },
	free = { lean = 0.4, roll = 0.4, drift = 0, shake = 1 }, -- the free camera stays put; the body still leans
}

CameraConfig.shake = {
	presets = {
		hit = { magnitude = 0.1, duration = 0.4, radius = 40 }, -- a sword blow lands
		ability = { magnitude = 0.3, duration = 0.4, radius = 60 }, -- an ability hits its frame
		explosion = { magnitude = 0.6, duration = 0.4, radius = 90 }, -- a heavy slam (Earthshatter) and boss deaths
		death = { magnitude = 0.3, duration = 0.4, radius = 60 }, -- an ordinary enemy dies nearby
	},
	abilityPreset = "ability", -- the shake for an AbilityConfig.fx entry that does not name one
}

-- EntityDeath deathType -> shake preset. Anything not listed uses "default".
CameraConfig.deathPresets = {
	default = "death",
	boss = "explosion",
}

-- Swing and blink feel (the numbers CameraFeel turns into springs).
CameraConfig.swing = CameraConfig.defaults.swing
CameraConfig.blink = CameraConfig.defaults.blink

return CameraConfig
