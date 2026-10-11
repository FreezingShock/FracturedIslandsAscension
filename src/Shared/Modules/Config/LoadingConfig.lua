--[[
	LoadingConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The intro loading screen, shown on every join. IntroLoader (ReplicatedFirst) clones the screen in at once;
	IntroController (Client > Intro) runs the cutscene tour, the preload and the menus from these numbers. The server
	side of the join (the damage shield) is IntroService (ServerScriptService).

	GUI: ReplicatedFirst.IntroScreen, built by tools/studio/build_intro_screen.luau. Names the scripts look up
	(restyle freely, do not rename):
	  IntroScreen (ScreenGui)
	    LetterTop, LetterBottom        black bars that slide in for the tour and out on Play
	    Vignette (Frame)               soft dark edges (gradient), always on
	    Fade (Frame, black)            transitions between shots, and the fade into the game
	    SkipSurface (Frame)            press and HOLD anywhere on the empty screen to skip the tour (never the preload)
	    SkipRing (Frame) > Fill        shows the hold-to-skip progress
	    Title (Frame) > Main, Sub      the game title, animated in
	    Caption (Frame) > Name, Index  location name of the current shot (LoadingConfig.locations)
	    Tip (TextLabel)                rotating tips (LoadingConfig.tips)
	    StatusLabel (TextLabel)        "Loading 42%" / "Ready"
	    ProgressBar (Frame) > Fill     preload progress, shimmer runs on Fill
	    PlayButton (TextButton)        locked (Active off) until the preload reaches 100%
	    MenuBar (Frame) > (UIListLayout)  one MenuButton per LoadingConfig.menus entry, cloned from Templates
	    MenuPanel (CanvasGroup, hidden)   Title (TextLabel), Content (ScrollingFrame), CloseButton
	    Templates (Folder)             MenuButton, Row (text), Option (toggle or cycle), Heading: cloned, never shown

	Layers (the same idea as CombatConfig: library -> per-scene override -> per-menu entry):
	  shot .......... library: defaults for every cutscene shot
	  scenes ........ fixed shots that always play first, each with its own name and overrides
	  shots ......... how many random shots follow, and where random spots may go
	  menus ......... one entry per menu button; rows = the page content (data only)

	Recipes:
	  New menu ............ add { key, label, icon, rows = { {kind="heading"|"text", text=...}, ... } } to menus.
	                        rows may also be "settings" (the settings list below) or "changelog" (GameVersion notes).
	  New option .......... add { key, label, kind="toggle" } or { key, label, kind="cycle", values = {...} } to settings.
	  New fixed scene ..... add { name = "Spawn", spot = Vector3.new(...), overrides = { duration = 12 } } to scenes.
	  New location name ... add a string to locations (random shots cycle through them).
	  New preload asset ... combat animations and sounds are picked up automatically; add extra ids to preload.extraIds.
	  Music, clicks, hovers ... rbxassetid:// strings in sounds ("" = silent). Placeholders until the user's ids arrive.
]]

local LoadingConfig = {}

-- The map box random shots may use (world studs). Spots are raycast down onto real ground inside it.
LoadingConfig.area = {
	min = Vector3.new(-1200, 0, -1950),
	max = Vector3.new(80, 0, 680),
}

-- Cutscene shot defaults (library). Overridden per scene; the tour speed setting divides every duration.
LoadingConfig.shot = {
	points = 4, -- camera path points, joined with a smooth curve
	radius = 64, -- how far the path circles around the spot
	sweep = math.rad(120), -- how far around the spot the path turns during the shot
	heightMin = 20, -- camera height above the spot, picked at random per shot
	heightMax = 34,
	lookHeight = 5, -- the camera aims this far above the ground
	duration = 10, -- seconds the camera travels along the path (at tour speed 1)
	fade = 0.9, -- seconds to fade out, and to fade back in on the next shot
	easing = Enum.EasingStyle.Sine,
	fov = 62,
}

-- Shots that always play first, in order. Leave empty for random shots only.
-- Two ways to write one:
--   Circling a spot:   { name = "Spawn", spot = Vector3.new(-951, 282, -808), overrides = { duration = 12 } }
--   Exact cameras:     { name = "Harbour", cameras = {
--                          { pos = Vector3.new(-900, 320, -700), look = Vector3.new(-950, 280, -800) },
--                          { pos = Vector3.new(-600, 300, -900), look = Vector3.new(-550, 260, -980) },
--                        }, overrides = { duration = 14 } }
--                      The camera flies through the positions in order, turning from each look to the next.
--                      Set shots = { min = 0, max = 0 } to play only your hand-placed scenes.
LoadingConfig.scenes = {
	{ name = "Starting Grounds", cameras = {
		{ pos = Vector3.new(-1130.7, 357.0, -836.3), look = Vector3.new(-1031.1, 349.4, -831.5) },
		{ pos = Vector3.new(-1027.1, 325.9, -678.4), look = Vector3.new(-952.5, 343.2, -742.7) },
	} },
	{ name = "Lake", cameras = {
		{ pos = Vector3.new(-1529.609, 201.219, -473.04), look = Vector3.new(-1527.673, 201.41, -472.575) },
		{ pos = Vector3.new(-1320.168, 283.81, -459.969), look = Vector3.new(-1318.197, 284.12, -460.096) },
	} },
	{ name = "Spawn", cameras = {
		{ pos = Vector3.new(-976.555, 299.517, -881.723), look = Vector3.new(-975.794, 299.569, -879.874) },
		{ pos = Vector3.new(-933.7, 306.799, -721.551), look = Vector3.new(-932.09, 306.96, -720.375) },
	} },
	{ name = "Main Island", cameras = {
		{ pos = Vector3.new(-993.447, 319.86, 204.872), look = Vector3.new(-993.251, 319.992, 202.886) },
		{ pos = Vector3.new(-640.884, 294.532, -224.413), look = Vector3.new(-641.988, 294.694, -226.073) },
	} },
}

-- Captions: random shots take these names in order (wrapping around). Scenes can set their own name.
LoadingConfig.locations = {
	"Hub Island",
	"Crystal Shore",
	"Ember Ridge",
	"Verdant Hollow",
	"Stormpeak Road",
	"Ruined Ascent",
	"Sky Harbor",
}

-- How many random shots follow the fixed scenes: a random count between min and max.
LoadingConfig.shots = {
	min = 0, -- set to 5 and 7 again for random scenes after yours
	max = 0,
	minGroundY = 4, -- a spot must sit above this height (keeps shots out of the water)
	tries = 80, -- raycasts tried per random spot before giving up on it
}

LoadingConfig.timings = {
	minLoadTime = 2.5, -- seconds the bar takes at least, even when everything is already cached
	stallTimeout = 25, -- after this long the preload gives up, Play unlocks, and a warning is printed
	streamTimeout = 6, -- seconds a shot waits for its surroundings to stream in before it plays anyway
	skipHold = 0.9, -- seconds to hold on SkipSurface before the tour jumps to its last shot
	letterbox = 0.9, -- seconds the black bars take to slide in and out
	enterFade = 0.6, -- seconds to fade to black when Play is pressed, before the camera handover
	handover = 2.4, -- seconds the camera glides from where the tour left it to your character's eyes
	tipEvery = 6, -- seconds per tip
}

LoadingConfig.tips = {
	"Hold click anywhere on the screen to skip the tour",
	"Q drops an item, F dodges",
	"R cycles the camera: first person, over the shoulder, free",
	"T frees the cursor",
	"Your progress saves automatically",
}

-- Asset ids the loader warms up before Play unlocks. Combat animations and sounds come from CombatConfig automatically.
LoadingConfig.preload = {
	extraIds = {
		-- "rbxassetid://...", -- icons, UI sounds, decals: add the ids here as they are made
	},
}

-- Sounds: an id plays on its event; "" = silent. The world's own sounds are muted until Play (see the handover).
LoadingConfig.sounds = {
	music = "", -- looping tour music ("" = silent)
	hover = "", -- a menu button under the cursor
	click = "", -- a menu button pressed, or Play
	play = "", -- the handover sting when Play is pressed
}

-- Options shown on the Settings page. Values live for this session (they are not saved).
LoadingConfig.settings = {
	{ key = "speed", label = "Tour speed", kind = "cycle", values = { 0.5, 1, 1.5 }, default = 1, suffix = "x" },
	{ key = "captions", label = "Location captions", kind = "toggle", default = true },
	{ key = "reduceMotion", label = "Reduce motion", kind = "toggle", default = false },
}

-- Menu buttons on the intro screen. module = a ModuleScript in ReplicatedStorage.Modules with init/open/close/reset.
-- rows = the page: heading / text lines, "settings" (the list above) or "changelog" (the notes in GameVersion).
LoadingConfig.menus = {
	{
		key = "Settings",
		label = "Settings",
		color = "aqua", -- a Minecraft code colour name: aqua, green, gold, red, purple, blue, yellow, gray
		module = "IntroPanelModule",
		rows = "settings",
		title = "Settings",
	},
	{
		key = "Controls",
		label = "Controls",
		color = "green",
		module = "IntroPanelModule",
		title = "Controls",
		rows = {
			{ kind = "heading", text = "Keys" },
			{ kind = "text", text = "Q  drop an item" },
			{ kind = "text", text = "F  dodge roll" },
			{ kind = "text", text = "E  open the menu" },
			{ kind = "text", text = "R  cycle the camera" },
			{ kind = "text", text = "T  free the cursor" },
			{ kind = "heading", text = "Mouse" },
			{ kind = "text", text = "Left click  attack" },
			{ kind = "text", text = "Hold click (intro)  skip the tour" },
		},
	},
	{
		key = "Changelog",
		label = "What's new",
		color = "purple",
		module = "IntroPanelModule",
		rows = "changelog",
		title = "What's new",
	},
}

return LoadingConfig
