--[[
	CombatConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Everything animation- and combo-related for weapons lives here. Three layers, from "what plays" to "when":

	1. LIBRARY  CombatConfig.animations[key] = { id, priority, fade, looped, speed }
	   The ONLY place an animation id is written. `id = ""` means "not published yet": the slot plays nothing and the
	   rest of the combat loop still runs. priority: "Action" (default), "Movement", "Idle", "Core".

	2. TYPE     CombatConfig.<weaponType> = { combo numbers, steps = {...}, slots = {...} }
	   Every item whose item.weapon.weaponType matches uses it, so all five swords share CombatConfig.sword.
	     steps[i].animation   library key played on combo step i (+ duration / hitFrame / recovery timing)
	     slots[name]          library key played for a situation: "equip", "idle", or any name you invent
	                          (code plays a slot with CombatAnimator.playSlot(character, weaponType, name, weaponId))

	3. OVERRIDES  CombatConfig.overrides[weaponId] = { steps = { [stepIndex] = key }, slots = { [name] = key } }
	   One weapon gets its own animation for a step or situation; everything else falls back to the type.

	Recipes
	  Change an animation for ALL swords ..... edit its `id` in the library (one line).
	  Change which animation a step uses ..... edit steps[i].animation (or add a library entry and point at it).
	  New situation (sprint, block, hurt) .... add library entry, add slots.sprint = "<key>", call playSlot(..., "sprint").
	  One weapon with its own swing .......... overrides.sword_legendary = { steps = { [4] = "legendary_finisher" } }.
	  New weapon type (spear, bow, ...) ...... copy CombatConfig.sword, change weaponType, steps and slots.
	  Longer / shorter combo ................. add or remove entries in steps (the loop uses #steps).

	FX AND SOUND (same layering: library -> type -> per-weapon override)
	  CombatConfig.sounds[key] = { id, volume, pitch = {min, max} }   id "" = silent; ids can be rbxassetid:// or rbxasset://
	  CombatConfig.fx[key]     = { trail = {...}, burst = {...} }      the swing trail ribbon and the spark burst
	  steps[i].sound / soundAt        sound key played soundAt seconds into the swing (at attack speed 1; scales with it)
	                                  the attack sounds are ~0.09s accents, so soundAt sits just before hitFrame
	  steps[i].trail = { from, to }   seconds (at attack speed 1) the trail ribbon is visible
	  type.fx                          fx key every weapon of the type uses
	  type.slotSounds[name]            sound key for a situation ("equip", later "impact", ...)
	  overrides[weaponId].fx / .stepSounds[i] / .slotSounds[name]   one weapon with its own look or sound
	  The trail attaches itself to ANY weapon's Handle (blade axis and tip are detected), so future swords need no setup.

	API
	  CombatConfig.get(weaponType)                          -> type config or nil
	  CombatConfig.swingTime(step, attackSpeed)             -> seconds a swing locks the player for
	  CombatConfig.stepAnimation(type, stepIndex, weaponId) -> library entry or nil (override first, then type)
	  CombatConfig.slotAnimation(type, slot, weaponId)      -> library entry or nil
	  CombatConfig.stepSound(type, stepIndex, weaponId)     -> sound entry or nil
	  CombatConfig.slotSound(type, slot, weaponId)          -> sound entry or nil
	  CombatConfig.fxFor(type, weaponId)                    -> fx entry (and its key) or nil
	  CombatConfig.types()                                  -> list of weaponType strings that have a config
	  CombatConfig.libraryKeysFor(type)                     -> every library key a type can use (for preloading)

	Type fields
	  comboWindow               seconds after a swing ends in which the next click continues the combo (else step 1)
	  moveSpeedFactor           WalkSpeed multiplier while swinging
	  finisherMoveSpeedFactor   same for the last step of the combo
	  bufferTime                a click this close to the end of a swing is remembered and fires when it ends
	  steps[i].duration         animation length in seconds at attack speed 1
	  steps[i].hitFrame         seconds into the swing where damage will be applied (hook: WeaponManager.onSwingHit)
	  steps[i].recovery         extra seconds after the animation before the next swing may start
	The real swing time is (duration + recovery) / attackSpeed, attackSpeed coming from the weapon's definition.
--]]

local CombatConfig = {}

-- ===================== 1. LIBRARY =====================
-- Paste the published animation ids here as "rbxassetid://123". Keys are free-form; steps and slots refer to them.
CombatConfig.animations = {
	-- sword combo (authored in Blender, R6; see assets/blender/combat/)
	sword_combo1 = { id = "rbxassetid://94936991830299", priority = "Action", fade = 0.06 }, -- slash down-left
	sword_combo2 = { id = "rbxassetid://121132140735511", priority = "Action", fade = 0.06 }, -- slash down-right
	sword_combo3 = { id = "rbxassetid://107854592014324", priority = "Action", fade = 0.06 }, -- fence jab
	sword_combo4 = { id = "rbxassetid://92264070348960", priority = "Action", fade = 0.06 }, -- overhead slash

	-- situations (no animation yet; fill in an id and it plays)
	sword_equip = { id = "", priority = "Action", fade = 0.1 },
	sword_idle = { id = "", priority = "Idle", fade = 0.2, looped = true },
}

-- Sounds. Defaults are Roblox's own bundled sword sounds (free, nothing to upload). To use your own audio, upload it
-- to Creator Hub and put "rbxassetid://<id>" here. Please keep to audio you own or that is licensed for games.
CombatConfig.sounds = {
	-- one attack sound per combo step. They are 3D sounds on the sword: minDistance = full volume within that many
	-- studs, silent beyond maxDistance, so anyone nearby hears them from the blade.
	sword_atk1 = { id = "rbxassetid://87733479853952", volume = 0.8, pitch = { 0.97, 1.03 }, minDistance = 12, maxDistance = 90 },
	sword_atk2 = { id = "rbxassetid://83101665211645", volume = 0.8, pitch = { 0.97, 1.03 }, minDistance = 12, maxDistance = 90 },
	sword_atk3 = { id = "rbxassetid://109876336137523", volume = 0.8, pitch = { 0.97, 1.03 }, minDistance = 12, maxDistance = 90 },
	sword_atk4 = { id = "rbxassetid://120264723935510", volume = 0.9, pitch = { 0.97, 1.03 }, minDistance = 14, maxDistance = 100 },
	sword_equip = { id = "rbxasset://sounds/unsheath.wav", volume = 0.45, pitch = { 0.95, 1.05 } },
	sword_impact = { id = "", volume = 0.7, pitch = { 0.9, 1.1 } }, -- reserved for the damage system
}

-- Visual FX. trail = ribbon behind the blade; burst = sparks thrown off the tip at the hit frame.
CombatConfig.fx = {
	sword_default = {
		trail = {
			color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 235, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 170, 255)),
			}),
			lifetime = 0.22, -- seconds a point of the ribbon lives
			lightEmission = 0.85,
			minLength = 0.02,
			bladeFrom = 0.35, -- ribbon spans the blade from this fraction (0 = pommel, 1 = tip) out to the tip
			transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }),
			width = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) }),
		},
		burst = {
			count = 7,
			color = ColorSequence.new(Color3.fromRGB(210, 245, 255), Color3.fromRGB(110, 190, 255)),
			size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) }),
			lifetime = NumberRange.new(0.25, 0.45),
			speed = NumberRange.new(6, 14),
			lightEmission = 1,
		},
	},
}

-- ===================== 2. WEAPON TYPES =====================
CombatConfig.sword = {
	weaponType = "sword",
	comboWindow = 0.7,
	moveSpeedFactor = 0.6,
	finisherMoveSpeedFactor = 0.4,
	bufferTime = 0.35,
	steps = {
		{ name = "SlashDownLeft", animation = "sword_combo1", duration = 0.50, hitFrame = 0.20, recovery = 0.05,
			sound = "sword_atk1", soundAt = 0.17, trail = { from = 0.10, to = 0.36 } },
		{ name = "SlashDownRight", animation = "sword_combo2", duration = 0.50, hitFrame = 0.20, recovery = 0.05,
			sound = "sword_atk2", soundAt = 0.17, trail = { from = 0.10, to = 0.36 } },
		{ name = "Jab", animation = "sword_combo3", duration = 0.47, hitFrame = 0.17, recovery = 0.05,
			sound = "sword_atk3", soundAt = 0.14, trail = { from = 0.12, to = 0.30 } },
		{ name = "OverheadSlash", animation = "sword_combo4", duration = 0.70, hitFrame = 0.32, recovery = 0.30,
			sound = "sword_atk4", soundAt = 0.29, trail = { from = 0.18, to = 0.46 } },
	},
	slots = {
		equip = "sword_equip",
		idle = "sword_idle",
	},
	fx = "sword_default",
	slotSounds = {
		equip = "sword_equip",
		impact = "sword_impact",
	},
}

-- ===================== 3. PER-WEAPON OVERRIDES =====================
-- [weaponId] = { steps = { [stepIndex] = "libraryKey" }, slots = { [slotName] = "libraryKey" } }
-- Extra per-weapon keys: fx = "<fx key>", stepSounds = { [stepIndex] = "<sound key>" }, slotSounds = { [name] = "<sound key>" }
CombatConfig.overrides = {}

-- ===================== LOOKUPS =====================
function CombatConfig.get(weaponType: string?): any?
	if not weaponType then
		return nil
	end
	local cfg = (CombatConfig :: any)[weaponType]
	if type(cfg) == "table" and cfg.steps then
		return cfg
	end
	return nil
end

function CombatConfig.types(): { string }
	local out = {}
	for key, value in pairs(CombatConfig :: any) do
		if type(value) == "table" and value.steps and value.weaponType == key then
			table.insert(out, key)
		end
	end
	return out
end

--- Seconds a swing locks the player for (animation + recovery, scaled by attack speed).
function CombatConfig.swingTime(step: any, attackSpeed: number?): number
	return (step.duration + step.recovery) / math.max(0.5, attackSpeed or 1)
end

local function entryOf(key: string?): any?
	if not key or key == "" then
		return nil
	end
	return CombatConfig.animations[key]
end

function CombatConfig.stepAnimation(weaponType: string?, stepIndex: number, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.steps and override.steps[stepIndex]
	if not key then
		local cfg = CombatConfig.get(weaponType)
		local step = cfg and cfg.steps[stepIndex]
		key = step and step.animation
	end
	return entryOf(key), key
end

function CombatConfig.slotAnimation(weaponType: string?, slot: string, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.slots and override.slots[slot]
	if not key then
		local cfg = CombatConfig.get(weaponType)
		key = cfg and cfg.slots and cfg.slots[slot]
	end
	return entryOf(key), key
end

local function soundEntry(key: string?): any?
	if not key or key == "" then
		return nil
	end
	local entry = CombatConfig.sounds[key]
	if entry and entry.id and entry.id ~= "" then
		return entry
	end
	return nil
end

function CombatConfig.stepSound(weaponType: string?, stepIndex: number, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.stepSounds and override.stepSounds[stepIndex]
	if not key then
		local cfg = CombatConfig.get(weaponType)
		local step = cfg and cfg.steps[stepIndex]
		key = step and step.sound
	end
	return soundEntry(key), key
end

function CombatConfig.slotSound(weaponType: string?, slot: string, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.slotSounds and override.slotSounds[slot]
	if not key then
		local cfg = CombatConfig.get(weaponType)
		key = cfg and cfg.slotSounds and cfg.slotSounds[slot]
	end
	return soundEntry(key), key
end

function CombatConfig.fxFor(weaponType: string?, weaponId: string?): any?
	local override = weaponId and CombatConfig.overrides[weaponId]
	local key = override and override.fx
	if not key then
		local cfg = CombatConfig.get(weaponType)
		key = cfg and cfg.fx
	end
	return key and CombatConfig.fx[key], key
end

function CombatConfig.libraryKeysFor(weaponType: string): { string }
	local cfg = CombatConfig.get(weaponType)
	local seen, out = {}, {}
	local function add(key)
		if key and key ~= "" and not seen[key] then
			seen[key] = true
			table.insert(out, key)
		end
	end
	if cfg then
		for _, step in ipairs(cfg.steps) do
			add(step.animation)
		end
		for _, key in pairs(cfg.slots or {}) do
			add(key)
		end
	end
	for _, override in pairs(CombatConfig.overrides) do
		for _, key in pairs(override.steps or {}) do
			add(key)
		end
		for _, key in pairs(override.slots or {}) do
			add(key)
		end
	end
	return out
end

return CombatConfig
