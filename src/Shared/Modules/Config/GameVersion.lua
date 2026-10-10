--[[
	GameVersion (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The game version shown in the ViewMenu VERSION row. /fia-ship rewrites `version` to the commit's version number
	(the "3.xx.x" of the commit title) before it commits, so every shipped commit carries its own version.
--]]

return {
	version = "3.90.0",
	date = "2026-10-09", -- the commit's date
	commit = "Player and self nameplates, chat level badge, taller chat with top fade and scroll polish", -- the commit title (short)
	-- what this commit added / changed / fixed: shown in chat when a player joins (ChatService.sendReleaseNotes)
	summary = {
		added = {
			"Other players have the same overhead plate as enemies: name, Nexus level badge, tag row and health bar",
			"Your own plate shows in third-person free camera and hides in first person",
			"Each player's chat line starts with their Nexus level badge, matching the nameplate",
			"Players die with the same shard dissolve as enemies",
		},
		changed = {
			"The chat panel is taller (450px) and its top fades out over the older lines",
			"The chat scrollbar stays visible and the mouse wheel moves further per notch",
		},
		fixed = {
			"Player plates no longer show Roblox's own name and health tag on top of ours",
		},
	},
}
