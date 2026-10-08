--[[
	DeathConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	How anything with a Humanoid dies (mobs, training dummies, players): a Sword Art Online style sequence.
	  1. GLITCH  the frozen body flickers blue, jitters and slices; its nameplate glitches with it
	  2. BURST   the body is gone and a dense cloud of glowing aqua-green triangles poofs out, spins, shrinks and floats up;
	             the nameplate breaks into small triangles too
	The server (DeathService) freezes the body, tells nearby clients (RemoteEvent EntityDeath { model, kind, deathType, seed }),
	pays out loot when the burst starts and removes the body after the sequence. The client (DeathFX) only draws.

	LAYERS (each overrides the one before, per field):
	  1. DeathConfig.library                     the defaults
	  2. DeathConfig.kinds[kind]                 kind = "enemy" | "dummy" | "player"
	  3. DeathConfig.types[deathType]            deathType = "default" | "fast" | "boss" | your own
	  4. EnemyConfig.enemies[type].death         a table of overrides for one enemy: { deathType = "fast" } or any field below,
	                                             e.g. death = { timeline = { glitch = 1.0, burst = 2.6 }, burst = { colors = {...} } }
	  DeathConfig.resolve(kind, enemyType) -> the merged table (cached per combination).

	RECIPES
	  Faster mobs:      EnemyConfig.enemies.<key>.death = { deathType = "fast" }
	  A boss:           EnemyConfig.enemies.<key>.death = { deathType = "boss" }
	  New death type:   add DeathConfig.types.<name> = { ...fields to change... } and reference it with deathType
	  Another colour:   death = { burst = { colors = { Color3..., ... } }, glitch = { tint = Color3... } }
	  Sounds:           library.sounds.glitch.id / burst.id = "rbxassetid://..."  (silent until set)
--]]

local DeathConfig = {}

-- ===================== TEXTURES (tools/fx/gen_death_textures.py, assets/death_fx/ids.json) =====================
DeathConfig.textures = {
	triangles = "rbxassetid://88874298201257", -- 2x2 flipbook of four glowing triangles
	glow = "rbxassetid://135016841256423",
}

-- ===================== 1. LIBRARY =====================
DeathConfig.library = {
	timeline = { glitch = 0.6, burst = 1.8 }, -- seconds. Loot pays out when the burst starts; the body is removed after both

	glitch = {
		tint = Color3.fromRGB(40, 190, 255), -- the body turns this blue
		tintStart = 0.15, -- fraction of the glitch at which the blue begins (ramps to full)
		jitterStuds = 0.5, -- peak random offset of each part (grows over the glitch)
		slices = 3, -- parts thrown sideways at once during a slice frame
		sliceStuds = 1.4,
		sliceChance = 0.35, -- chance per frame (late in the glitch) of a slice
		flickerStart = 0.1, -- flicker chance rises from this fraction of the glitch
		highlight = true, -- an outline fill that pulses cyan (only while 3 or fewer deaths are playing)
		scanBars = 2, -- thin neon bars sweeping up and down the body
		scanSweeps = 2.5, -- up-and-down passes during the glitch
	},

	burst = {
		count = 120, -- triangles in total (scaled down automatically under the client caps)
		texture = "triangles",
		colors = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 255, 255), Color3.fromRGB(70, 235, 255), Color3.fromRGB(60, 255, 170) },
		size = { 0.35, 1.5 }, -- studs at birth (min, max); they shrink to 0
		speed = { 5, 22 }, -- studs/s outward from the body
		rise = 7, -- upward acceleration: the cloud floats up
		drag = 1.6,
		life = { 1.0, 1.8 },
		rotSpeed = 360, -- degrees/s, either direction
		waves = { { at = 0, share = 0.5 }, { at = 0.12, share = 0.25 }, { at = 0.3, share = 0.25 } }, -- dense start, then a trickle
		slivers = 14, -- thin streaks that fly out fast
		glow = { size = 9, life = 0.5, transparency = 0.55 }, -- the soft disc at the centre
		light = { color = Color3.fromRGB(110, 255, 230), brightness = 5, range = 18, time = 0.6 }, -- point light pulse
		lingerSeconds = 1.0, -- extra time the emitters stay before cleanup
	},

	-- the nameplate: glitches for the glitch seconds, then breaks into shards (GUI.EnemyNameplate_Shard clones)
	hud = {
		jitterPixels = 6,
		sliceChance = 0.4,
		slicePixels = 18,
		flickerStart = 0.1,
		tint = Color3.fromRGB(40, 190, 255),
		echo = true,
		echoPixels = 3,
		shards = 24,
		shardDistance = { 30, 90 }, -- pixels the pieces fly
		shardSize = { 8, 20 },
		shardLife = { 0.8, 1.4 },
		shardRise = 40, -- extra upward drift
	},

	-- client caps so a pack of deaths cannot melt a phone
	caps = {
		maxDistance = 160, -- farther deaths just hide the body
		reduceAt = 4, -- death effects alive at once: from this many on, a lighter version plays (no echo / outline, fewer triangles)
		reducedShare = 0.4, -- fraction of the particles in the lighter version
		hardCap = 14, -- past this many alive at once only the body vanishes
	},

	sounds = { -- silent until you set an id; 3D at the body
		glitch = { id = "", volume = 0.8, pitch = { 0.95, 1.05 } },
		burst = { id = "", volume = 1, pitch = { 0.95, 1.05 } },
	},

	player = {
		respawnSeconds = 3, -- Players.RespawnTime
	},

	-- when the dead one is YOU: the screen and camera go with the body (DeathController)
	selfDeath = {
		glitchTint = Color3.fromRGB(150, 215, 255), -- the screen cools to this during the glitch
		glitchSaturation = -0.55,
		glitchContrast = 0.18,
		flash = 0.4, -- brightness kick as the triangles go off, easing back to 0
		flashSeconds = 0.9,
		bloom = 1.1, -- bloom pulse at the burst, fading over the burst time
		shake = 0.45, -- studs of camera shake at the end of the glitch
		pullBack = 7, -- studs the camera drifts away
		rise = 4, -- and up
		orbitDegrees = 35, -- a slow turn around the spot
		fovBonus = 9,
	},
}

-- ===================== 2. KINDS =====================
DeathConfig.kinds = {
	enemy = {},
	dummy = {},
	player = {},
}

-- ===================== 3. TYPES =====================
DeathConfig.types = {
	default = {},
	fast = { timeline = { glitch = 0.35, burst = 1.2 }, burst = { count = 80 } },
	boss = { timeline = { glitch = 1.0, burst = 2.8 }, burst = { count = 220, size = { 0.5, 2.4 } } },
}

-- ===================== RESOLVE =====================
local function merge(base: any, override: any): any
	if type(override) ~= "table" then
		return base
	end
	local out = {}
	for key, value in pairs(base) do
		out[key] = value
	end
	for key, value in pairs(override) do
		if type(value) == "table" and type(out[key]) == "table" and getmetatable(value) == nil and #value == 0 and next(value) ~= nil then
			out[key] = merge(out[key], value)
		else
			out[key] = value
		end
	end
	return out
end

local cache: { [string]: any } = {}

--- The merged death settings for a kind ("enemy" | "dummy" | "player") and an optional EnemyConfig entry (its `death` field).
function DeathConfig.resolve(kind: string?, enemyEntry: any?): any
	local override = enemyEntry and enemyEntry.death
	local typeName = (override and override.deathType) or "default"
	local key = (kind or "enemy") .. "|" .. typeName .. "|" .. tostring(override)
	local cached = cache[key]
	if cached then
		return cached
	end
	local merged = merge(DeathConfig.library, DeathConfig.kinds[kind or "enemy"])
	merged = merge(merged, DeathConfig.types[typeName])
	merged = merge(merged, override)
	cache[key] = merged
	return merged
end

--- Seconds of the whole sequence for a kind and enemy entry.
function DeathConfig.total(kind: string?, enemyEntry: any?): number
	local timeline = DeathConfig.resolve(kind, enemyEntry).timeline
	return timeline.glitch + timeline.burst
end

return DeathConfig
