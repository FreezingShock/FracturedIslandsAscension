--[[
	GameVersion (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The game version shown in the ViewMenu VERSION row. /fia-ship rewrites `version` to the commit's version number
	(the "3.xx.x" of the commit title) before it commits, so every shipped commit carries its own version.
--]]

return {
	version = "3.91.0",
	date = "2026-10-10", -- the commit's date
	commit = "Ambience: rolling music, footsteps by floor material with stride steps, jump and landing, menu sounds", -- the commit title (short)
	-- what this commit added / changed / fixed: shown in chat when a player joins (ChatService.sendReleaseNotes)
	summary = {
		added = {
			"Background music rolls through a playlist with quiet gaps between tracks",
			"Footsteps depend on the ground you walk on: grass, stone, sand, wood, snow, gravel and glass each have their own steps",
			"Jumping and landing from a fall make a sound",
			"Opening and closing the menu makes a sound",
		},
		changed = {
			"A footstep plays for every stride you cover, so sprinting and dashing step as fast as you move",
		},
		fixed = {
			"Footsteps no longer lag behind your movement",
		},
	},
}
