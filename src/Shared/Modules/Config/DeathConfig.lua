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
	  Sounds:           library.sounds.glitch.id / burst.id = "rbxassetid://..."  (silent until set); library.sounds.sao = the death sound
	                    (forward on death, its reversed copy on the reveal; see the comment there)
	  Respawn reveal:   library.respawn (timeline, radius, sounds) + library.selfRespawn (camera / screen); a player's reveal is
	                    the death played backwards, so burst.* and glitch.* shape it too. Players.RespawnTime = respawnSeconds().
--]]

local DeathConfig = {}

-- ===================== TEXTURES (tools/fx/gen_death_textures.py, assets/death_fx/ids.json) =====================
DeathConfig.textures = {
	triangles = "rbxassetid://88874298201257", -- 2x2 flipbook of four glowing triangles
	glow = "rbxassetid://135016841256423",
}

-- ===================== 1. LIBRARY =====================
DeathConfig.library = {
	timeline = { glitch = 0.8, burst = 1.8 }, -- seconds. Loot pays out when the burst starts; the body is removed after both

	glitch = {
		tintStart = 0.04, -- fraction of the glitch at which the blue / purple / green flicker begins
		tintRamp = 0.2, -- ... and how much of the glitch it takes to reach full colour
		jitterStuds = 0.5, -- peak random offset of each part (grows over the glitch)
		slices = 3, -- parts thrown sideways at once during a slice frame
		sliceStuds = 1.4,
		sliceChance = 0.35, -- chance per frame (late in the glitch) of a slice
		flickerStart = 0.1, -- flicker chance rises from this fraction of the glitch
		highlight = true, -- an outline fill that flickers through the palette and brightens with the glow (only while 3 or fewer deaths are playing)
		colors = { Color3.fromRGB(40, 160, 255), Color3.fromRGB(150, 70, 255), Color3.fromRGB(60, 255, 150) }, -- blue, purple, green
		recolorChance = 0.28, -- per frame, per body part: jump to another colour of the palette
		glowStart = 0.35, -- fraction of the glitch: each body part picks a random moment in [glowStart, glowEnd] to start glowing
		glowEnd = 0.65, -- (+ glowRamp = every part is white-hot just before the burst)
		glowRamp = 0.3, -- fraction of the glitch a part takes to go from its colour to white-hot
		glowColor = Color3.fromRGB(215, 255, 255),
		glowSwell = 0.12, -- a glowing part grows by this much
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
		lodDistance = 70, -- farther than this (to the camera) a death / reveal draws a thin version: few particles, no glow disc, light or outline
		lodShare = 0.25, -- fraction of the particles in that thin version
		hardCap = 14, -- past this many alive at once only the body vanishes
	},

	sounds = { -- silent until you set an id; 3D at the body
		glitch = { id = "", volume = 0.8, pitch = { 0.95, 1.05 } },
		burst = { id = "", volume = 1, pitch = { 0.95, 1.05 } },
		-- The death sound: plays FORWARD when the death starts and fitted to the death sequence, and its REVERSED copy plays when the
		-- reveal starts (Roblox cannot play a sound backwards: upload the audio reversed, e.g. Audacity > Effect > Reverse, and put its id in
		-- reverseId; until then the reveal is silent). fit = change the playback speed (between minSpeed and maxSpeed) so the sound lasts
		-- exactly as long as the animation; if it is still longer, it fades out over `fade` seconds when the animation ends.
		-- To silence it for one kind: kinds.enemy = { sounds = { sao = { id = "", reverseId = "" } } }.
		sao = { id = "rbxassetid://128025726296262", reverseId = "", volume = 1, rolloff = 110, fit = true, minSpeed = 0.75, maxSpeed = 1.5, fade = 0.4 },
	},

	player = {
		respawnSeconds = false, -- Players.RespawnTime; false = exactly as long as the death sequence (glitch + burst), or a number
	},

	-- the reverse of the death, for a player who died: the new body waits hidden while the camera glides to it (travel), the
	-- triangles converge on it (converge), it glitches in (solidify), then the camera swings into its head (swing). Count / colours / sizes come from `burst`,
	-- the flicker / glow / jitter from `glitch`: editing the death edits the respawn.
	respawn = {
		timeline = { travel = 1.0, converge = 0.9, solidify = 1.1, swing = 0.9 }, -- swing: the camera dives into the head (first person)
		radius = 9, -- studs: the triangles start on a sphere this big around the body and fly in
		sizeStart = 0.35, -- fraction of the burst size the triangles have when they start (they grow to full size as they arrive)
		light = { color = Color3.fromRGB(110, 255, 230), brightness = 5, range = 18, time = 0.7 }, -- pulse as they merge
		sounds = { -- silent until you set an id; 3D at the body
			converge = { id = "", volume = 1, pitch = { 0.95, 1.05 } },
			glitchIn = { id = "", volume = 0.8, pitch = { 0.95, 1.05 } },
		},
	},

	-- when the revealed one is YOU: the camera glides from the death view to the new body, the screen starts cool and clears
	selfRespawn = {
		tint = Color3.fromRGB(150, 215, 255),
		saturation = -0.55,
		contrast = 0.18,
		flash = 0.35, -- brightness kick as the triangles merge, easing back to 0
		bloom = 1.0, -- bloom pulse at the merge, fading over solidify
		distance = 12, -- studs the camera ends up from the new body, on the side it was looking from
		rise = 2, -- and above it
		swingArc = 3, -- studs the swing bows out sideways on its way into the head
		lockSeconds = 0.22, -- the robotic lock-in after the swing: a dip in the field of view, a tiny nod, a flash
		lockFov = 9, -- degrees the view narrows at the lock
		lockNod = 3, -- degrees the view nods
		lockFlash = 0.12,
		lockSound = { id = "", volume = 1 }, -- silent until set
		failsafeSeconds = 4, -- if the server never says the reveal started, give the camera back after this long
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
	fast = { timeline = { glitch = 0.5, burst = 1.2 }, burst = { count = 80 } },
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

--- Seconds a player takes to respawn (Players.RespawnTime): the player.respawnSeconds override, else the death sequence.
function DeathConfig.respawnSeconds(kind: string?): number
	local cfg = DeathConfig.resolve(kind or "player", nil)
	if type(cfg.player.respawnSeconds) == "number" then
		return cfg.player.respawnSeconds
	end
	return cfg.timeline.glitch + cfg.timeline.burst
end

--- Seconds a new body is held while its reveal plays: converge + solidify, and for a player also the camera glide, swing and lock-in.
function DeathConfig.revealSeconds(kind: string?, enemyEntry: any?): number
	local cfg = DeathConfig.resolve(kind or "player", enemyEntry)
	local timeline = cfg.respawn.timeline
	local seconds = timeline.converge + timeline.solidify
	if kind == "player" or kind == nil then
		seconds += timeline.travel + timeline.swing + cfg.selfRespawn.lockSeconds
	end
	return seconds
end

return DeathConfig
