--[[
	DropFXConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The glow and particles on dropped items, drawn on every client by DropFXController from the drop's replicated attributes
	(Rarity, DropColor), so the server sends nothing. The light is a PointLight: it shines in ALL directions from one point
	(SurfaceLight shines out of one face and SpotLight in a cone, neither is right for a glowing item).

	LAYERS, each overriding the one before:
	  1. library[preset]               the shape of an effect: glow, motes, ring, pillar, flare, spawn, pickup
	  2. rarity[<0-6>][preset]         which presets a rarity uses (true, or a table of overrides). A preset that is not
	                                   listed is OFF for that rarity.
	  3. items[<itemId>][preset]       per item id: a table of overrides, or false to switch the preset off for it
	DropFXConfig.resolve(rarity, itemId) returns { [preset] = merged table } for the presets that are on.

	COLOURS: color = "rarity" (the drop's colour), "white", or "#RRGGBB". `brighten` (0-1) mixes the colour toward white.
	RANGES are { min, max }; sizes are { start, end } (or { start, mid, end }); transparencies likewise.
	TEXTURES are keys of EnemyConfig.textures (dot, ring, flare, streak, ...), so there are no new image assets.

	LIMITS (the whole client): maxLights lights on the nearest drops, maxEmitterDrops drops with particles, nothing past
	fxRange studs; rate and brightness fade out over the last fadeBand studs.

	RECIPES
	  Stronger Epic glow:        rarity[3].glow = { range = 12, brightness = 2 }
	  Give Rare a ring:          rarity[2].ring = true
	  Remove Mythic's pillar:    rarity[5].pillar = nil
	  One item without motes:    items.coal = { motes = false }
	  New effect:                add library.<name> (and a case for it in DropFXController), then list it in a rarity
	  Particles everywhere:      add motes = { rate = 2 } to rarity[0]
]]

local DropFXConfig = {}

DropFXConfig.limits = {
	maxLights = 8, -- PointLights on at once (the nearest drops)
	maxEmitterDrops = 12, -- drops that emit particles at once (the nearest)
	fxRange = 45, -- studs from the player; nothing is drawn past it
	fadeBand = 10, -- studs over which rate and brightness fade out before fxRange
	scanEvery = 0.15, -- seconds between choosing which drops get a light / particles
	rigLift = 0.35, -- studs above the drop's resting position where the glow sits
	groundOffset = -0.95, -- studs from the resting position down to the floor (ring and pillar start here)
	spawnWindow = 1.5, -- a drop gets its spawn burst only if it appeared this recently
	poolSize = 16, -- rigs kept ready
}

-- the item pop: one sound for a drop appearing, being picked up, and an item landing in a stack. Empty id = silent.
-- pitch = { low, high }: a random value per play; the stack pitch climbs from low (1 item) to high (full stack) instead.
DropFXConfig.sounds = {
	pop = { id = "rbxassetid://77099858882420", volume = 0.7, range = 60 },
	drop = { pitch = { 0.95, 1.1 } },
	pickup = { pitch = { 1.15, 1.35 } }, -- an item expiring
	-- picking items up in quick succession climbs in pitch: each pickup within `window` seconds of the last one by the same
	-- player steps the pitch up (after `steps` steps it is at the top), then it falls back to `pitch[1]` when you stop
	pickupStreak = { window = 1.2, steps = 10, pitch = { 1.0, 2.0 } },
	stack = { pitch = { 0.85, 1.7 } },
	learnWindow = 3, -- seconds after joining in which drops that already exist stay silent
}

DropFXConfig.library = {
	-- omnidirectional light that breathes a little
	glow = {
		range = 9,
		brightness = 1.4,
		pulse = { amount = 0.25, speed = 1.6 }, -- brightness swings by +-amount (fraction) at speed rad/s
		color = "rarity", -- exactly the drop's colour (no brighten), so the light always matches the rarity
	},
	-- small sparkles rising off the drop
	motes = {
		texture = "dot",
		rate = 4,
		lifetime = { 1.1, 2.0 },
		speed = { 0.5, 1.3 },
		size = { 0.26, 0 },
		transparency = { 0.15, 1 },
		spread = 30, -- degrees around straight up
		acceleration = 0.3, -- studs/s^2 upward
		color = "rarity",
		brighten = 0.35,
		lightEmission = 1,
	},
	-- a ground ring that pulses outward
	ring = {
		texture = "ring",
		rate = 0.55,
		lifetime = 1.7,
		size = { 0.4, 4.5 },
		transparency = { 0.35, 1 },
		color = "rarity",
		brighten = 0.15,
		lightEmission = 1,
	},
	-- a thin shaft of light straight up
	pillar = {
		height = 9,
		width = { 0.9, 0.25 }, -- at the bottom, at the top
		transparency = { 0.78, 1 },
		color = "rarity",
		brighten = 0.2,
		lightEmission = 1,
	},
	-- a slow starburst above the item
	flare = {
		texture = "flare",
		rate = 0.45,
		lifetime = 0.9,
		size = { 0, 3.2, 0 },
		transparency = { 0.4, 0.3, 1 },
		color = "rarity",
		brighten = 0.45,
		lightEmission = 1,
		lift = 1.0, -- studs above the glow point
	},
	-- one burst when a fresh drop appears
	spawn = {
		texture = "dot",
		count = 10,
		speed = { 5, 9 },
		lifetime = { 0.35, 0.7 },
		size = { 0.38, 0 },
		color = "rarity",
		brighten = 0.4,
		flareCount = 1, -- starbursts in the same moment (0 = none)
		flareSize = 4,
	},
	-- the burst when an item lands in a stack: count grows with the stack (count + perCount * stack, max maxCount),
	-- a starburst, a ground shock ring and a light flash. A full stack (DropStackConfig.maxStack) gets `full` on top.
	stack = {
		texture = "dot",
		count = 8,
		perCount = 0.2,
		maxCount = 30,
		speed = { 4, 8 },
		lifetime = { 0.3, 0.65 },
		size = { 0.34, 0 },
		color = "rarity",
		brighten = 0.45,
		flareCount = 1,
		flareSize = 3.2,
		flareGrow = 0.02, -- extra starburst size per stacked item
		ringSize = 3.5, -- ground shock ring (0 = none)
		flash = { brightness = 3.5, time = 0.3 }, -- extra light that decays
		full = { countMult = 2.5, flareCount = 3, flareSize = 6, ringSize = 7, flash = { brightness = 6, time = 0.6 } },
	},
	-- one burst when the drop is picked up or expires
	pickup = {
		texture = "dot",
		count = 12,
		speed = { 3, 7 },
		lifetime = { 0.3, 0.6 },
		size = { 0.3, 0 },
		color = "rarity",
		brighten = 0.5,
		flareCount = 0,
		flareSize = 3,
	},
}

-- which presets each rarity uses, and what it changes in them
DropFXConfig.rarity = {
	[0] = { stack = true, glow = { range = 6, brightness = 0.5, pulse = { amount = 0.12, speed = 1.2 } } }, -- Common: a faint glow in its grey
	[1] = { stack = true, glow = { range = 8, brightness = 0.9 }, motes = { rate = 3 }, pickup = true, spawn = { count = 8 } },
	[2] = { stack = true, glow = { range = 9, brightness = 1.2, pulse = { amount = 0.3, speed = 1.8 } }, motes = { rate = 5 }, pickup = true, spawn = true },
	[3] = { stack = true, glow = { range = 10, brightness = 1.5 }, motes = { rate = 7 }, ring = true, pickup = true, spawn = { count = 14 } },
	[4] = {
		stack = true,
		glow = { range = 12, brightness = 1.9 },
		motes = { rate = 10, color = "#FFD27A" },
		ring = { size = { 0.5, 5.5 } },
		pickup = { count = 16 },
		spawn = { count = 18, flareCount = 2 },
	},
	[5] = {
		stack = true,
		glow = { range = 14, brightness = 2.4, pulse = { amount = 0.3, speed = 2.2 } },
		motes = { rate = 14 },
		ring = { rate = 0.7, size = { 0.6, 6.5 } },
		pillar = true,
		flare = true,
		pickup = { count = 22, flareCount = 1 },
		spawn = { count = 24, flareCount = 3, flareSize = 5 },
	},
}

DropFXConfig.items = {
	-- example: coal = { motes = false },
}

local function merge(into: any, from: any)
	for key, value in pairs(from) do
		if type(value) == "table" and type(into[key]) == "table" and #value == 0 then
			merge(into[key], value)
		else
			into[key] = value
		end
	end
end

local function deepCopy(value: any)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = deepCopy(inner)
	end
	return copy
end

local cache: { [string]: any } = {}

--- The presets that are on for this rarity / item, each merged: { glow = {...}, motes = {...}, ... }
function DropFXConfig.resolve(rarity: number?, itemId: string?)
	local cacheKey = tostring(rarity) .. "|" .. tostring(itemId)
	local hit = cache[cacheKey]
	if hit then
		return hit
	end
	local out = {}
	local byRarity = DropFXConfig.rarity[rarity or 0] or {}
	local byItem = itemId and DropFXConfig.items[itemId] or {}
	for name, base in pairs(DropFXConfig.library) do
		local layer = byRarity[name]
		if layer ~= nil and layer ~= false and byItem[name] ~= false then
			local merged = deepCopy(base)
			if type(layer) == "table" then
				merge(merged, layer)
			end
			if type(byItem[name]) == "table" then
				merge(merged, byItem[name])
			end
			out[name] = merged
		end
	end
	cache[cacheKey] = out
	return out
end

return DropFXConfig
