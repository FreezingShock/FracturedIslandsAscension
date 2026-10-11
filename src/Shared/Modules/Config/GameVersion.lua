--[[
	GameVersion (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The game version shown in the ViewMenu VERSION row. /fia-ship rewrites `version` to the commit's version number
	(the "3.xx.x" of the commit title) before it commits, so every shipped commit carries its own version.
--]]

return {
	version = "3.93.0",
	date = "2026-10-10", -- the commit's date
	commit = "Intro loading screen: preload, locked cutscene, transparent menu", -- the commit title (short)
	-- what this commit added / changed / fixed: shown in chat when a player joins (ChatService.sendReleaseNotes)
	summary = {
		added = {
			"Loading screen on every join: a progress bar fills while the assets preload, and Play unlocks at 100%",
			"A camera tour of random spots around the map plays behind it; hold click to skip to the last shot",
			"Settings and controls panels open from the loading screen while it loads"
		},
		changed = {
			"While the loading screen is up, the camera, the cursor and game keys stand down until you press Play"
		},
		fixed = {},
	},
}
