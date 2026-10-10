--[[
	GameVersion (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The game version shown in the ViewMenu VERSION row. /fia-ship rewrites `version` to the commit's version number
	(the "3.xx.x" of the commit title) before it commits, so every shipped commit carries its own version.
--]]

return {
	version = "3.87.0",
	date = "2026-10-09", -- the commit's date
	commit = "Camera feel: lean and roll into strafes, trailing blink, shake tiers; layered ability FX", -- the commit title (short)
	-- what this commit added / changed / fixed: shown in chat when a player joins (ChatService.sendReleaseNotes)
	summary = {
		added = {
			"Camera feel: the body leans and the camera rolls into strafing (first person too), with a lagged over-the-shoulder drift",
			"Camera shake tiers from sword hits, abilities and deaths, falling off with distance",
			"Sword swings kick the view, and the blink dash whips the view toward its direction with a short FOV punch",
			"Layered ability effects: every ability has its own stacked visuals (see docs/FX_GUIDE.md)",
			"Wood and stone swords, and icons for every sword",
		},
		changed = {
			"The blink dash is trailed by the camera, so it slides after you instead of snapping",
			"Earthshatter's slam is the strongest ability shake",
		},
		fixed = {
			"The camera froze for a moment whenever a shake ran",
		},
	},
}
