--[[
	AmbienceConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	Every sound the ambience layer plays, in one place. AmbienceController (music, footsteps, jump, landing) and
	CentralizedMenuController (menu open / close) read it, so changing a sound or a number here changes it everywhere.

	Layering: shared steps  ->  default surface  ->  surface override (footsteps, by floor material)
	          cue override (jump / land / menus).
	A surface's variants list REPLACES the default's, so a surface with no variants falls back to the default's sounds.
	All ids are Roblox audio ids (rbxassetid://<id>). An empty id = that slot stays silent.

	RECIPES
	  Add a variant to a surface:  append "rbxassetid://<id>" to that surface's variants (one line; picks never repeat in a row)
	  Replace a surface's sounds:  edit its variants list
	  New surface (e.g. Mud):      add surfaces.Mud = { variants = { ... } }, then map its Enum.Material names in materialSurface
	  Add a music track:           append { id = "rbxassetid://...", name = "..." } to music.tracks (one plays at random)
	  Retune a cue:                edit cues.<jump | land | menuOpen | menuClose> (id, volume; land also minDrop in studs)
	  Music volume / gap:          music.volume, music.gapMin / gapMax (seconds of quiet between tracks)

	STEP VARIANTS (the user's own .ogg recordings, uploaded to Roblox; the number is the file name, e.g. stone3.ogg)
	  Grass  1-5: 86981853124973, 124989623679753, 115255788229551, 82212014938471, 97082124029132 (grass6 pending, see above)
	  Stone  1-6: 84891863105315, 132039494371144, 131313967933551, 92209997988823, 106459926971896, 85892221698378
	           (replaces the old Rock clip, 82357128779870 was 4.3 s long and overlapped the next step)
	  Sand   1-5: 91771331694324, 119411568555825, 118920101432941, 112849912654169, 89093163751436
	  Wood   1-6: 128141721692705, 109813609620243, 106018515434216, 130408204569851, 117535029122071, 133790597118129
	  Snow   1-3: 123076505087905, 75379936225835, 130858123795926 (snow4 pending, see above)
	  Gravel 1-4: 132191112480711, 74709784160241, 81320991345999, 100030547620233
	  Glass  1-4: 134120663736003, 97985555310875, 80881092186265, 93290716631926
	  default:    82357128779870 "Audio/Dirt_step_run_06" (ra1nsl1_4): the neutral step for anything unmapped
	  Ladder and cloth are not wired yet (the files exist; add surfaces when you want them).

	CHOSEN CUES (Creator Store, all free)
	  jump      106990833241950 "Roblox Old Jumping Sound" (Metability Gaming Utilities): the classic Roblox jump feel
	  land      9116488211      "Meaty Thud 7 (SFX)" (ProSoundEffects): a heavy thud for a hard landing
	  menuOpen  97861038165143  "ui-simple-menu-open" (AmbientSorcery): a short, soft open chime
	  menuClose 110059957735733 "ui-simple-menu-close" (AmbientSorcery): the matching close
	  music     102696255971003 "Piano Dreams", 81083173835517 "Voyage", 120398838451788 "Haven", 80849508346318 "Room No. 2"
	            (all DistrokidOfficial): calm, low-key tracks that sit under play rather than over it
--]]

local AmbienceConfig = {}

-- ===================== MUSIC (rolling playlist, Minecraft style) =====================
AmbienceConfig.music = {
	volume = 0.25, -- the loudest the music gets (0..1), reached after the fade in
	fadeSeconds = 3, -- fade in at the start of a track, fade out at its end
	gapMin = 60, -- seconds of quiet after a track ends, random between gapMin and gapMax
	gapMax = 180,
	tracks = {
		{ id = "rbxassetid://102696255971003", name = "Piano Dreams" },
		{ id = "rbxassetid://81083173835517", name = "Voyage" },
		{ id = "rbxassetid://120398838451788", name = "Haven" },
		{ id = "rbxassetid://80849508346318", name = "Room No. 2" },
	},
}

-- ===================== FOOTSTEPS (by the floor under the foot) =====================
-- shared settings for every step (a surface may override any of them)
-- A step is one stride of ground covered: the character's real horizontal velocity is integrated, so walking, sprinting
-- and dashing all step at the rate they actually move (no timer, no MoveDirection). Tune stride to match the foot plants.
AmbienceConfig.steps = {
	volume = 0.5,
	rollOff = 60, -- studs: a step is heard within this distance, 3D, from the character's body
	pitchRange = 0.08, -- +/- random pitch so repeated steps do not sound identical
	stride = 4.5, -- studs of ground covered per footstep (smaller = more steps per metre)
	minInterval = 0.12, -- seconds: the fastest steps can come (keeps a fast dash from stacking sounds)
	minSpeed = 1, -- studs/s of horizontal speed below which the character counts as standing still
}

local function ids(list: { string }): { string }
	local out = {}
	for _, number in ipairs(list) do
		table.insert(out, "rbxassetid://" .. number)
	end
	return out
end

-- every surface: variants = the sounds one step is picked from. "default" is the fallback surface.
AmbienceConfig.surfaces = {
	default = { variants = ids({ "82357128779870" }) },
	-- grass6 (86215967656787) and snow4 (138833963891272) did not load in Studio (checked 3 times, 2026-10-10):
	-- check their upload / permissions, then add them back to the list. Left out so no step plays silent.
	Grass = {
		variants = ids({ "86981853124973", "124989623679753", "115255788229551", "82212014938471", "97082124029132" }),
	},
	Stone = {
		variants = ids({ "84891863105315", "132039494371144", "131313967933551", "92209997988823", "106459926971896", "85892221698378" }),
	},
	Sand = {
		variants = ids({ "91771331694324", "119411568555825", "118920101432941", "112849912654169", "89093163751436" }),
	},
	Wood = {
		variants = ids({ "128141721692705", "109813609620243", "106018515434216", "130408204569851", "117535029122071", "133790597118129" }),
	},
	Snow = {
		variants = ids({ "123076505087905", "75379936225835", "130858123795926" }),
	},
	Gravel = {
		variants = ids({ "132191112480711", "74709784160241", "81320991345999", "100030547620233" }),
	},
	Glass = {
		variants = ids({ "134120663736003", "97985555310875", "80881092186265", "93290716631926" }),
	},
}

-- Enum.Material name -> surface above. Anything not listed uses "default".
AmbienceConfig.materialSurface = {
	Grass = "Grass",
	LeafyGrass = "Grass",
	Ground = "Grass",
	Rock = "Stone",
	Slate = "Stone",
	Basalt = "Stone",
	Concrete = "Stone",
	Sand = "Sand",
	Sandstone = "Sand",
	Wood = "Wood",
	WoodPlanks = "Wood",
	Snow = "Snow",
	Ice = "Snow",
	Pebble = "Gravel",
	Glass = "Glass",
}

-- ===================== CUES (jump, landing, menus) =====================
-- one-shot sounds. jump / land are 3D from the character; menuOpen / menuClose are 2D (you hear them, nobody else does)
AmbienceConfig.cues = {
	jump = { id = "rbxassetid://106990833241950", volume = 0.4, rollOff = 60 },
	land = { id = "rbxassetid://9116488211", volume = 0.6, rollOff = 60, minDrop = 8 }, -- minDrop: studs fallen before a landing sounds
	menuOpen = { id = "rbxassetid://97861038165143", volume = 0.35 },
	menuClose = { id = "rbxassetid://110059957735733", volume = 0.3 },
}

--- The footstep settings for a floor material: shared steps, then the default surface, then the surface override.
--- variants come from the surface (or the default when the surface has none).
function AmbienceConfig.stepFor(material: Enum.Material): any
	local surfaceName = AmbienceConfig.materialSurface[material.Name] or "default"
	local out = {}
	for key, value in pairs(AmbienceConfig.steps) do
		out[key] = value
	end
	for key, value in pairs(AmbienceConfig.surfaces.default) do
		out[key] = value
	end
	local override = AmbienceConfig.surfaces[surfaceName]
	if override then
		for key, value in pairs(override) do
			out[key] = value
		end
	end
	if not out.variants or #out.variants == 0 then
		out.variants = AmbienceConfig.surfaces.default.variants
	end
	return out
end

return AmbienceConfig
