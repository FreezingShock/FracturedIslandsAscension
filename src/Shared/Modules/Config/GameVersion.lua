--[[
	GameVersion (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The game version shown in the ViewMenu VERSION row. /fia-ship rewrites `version` to the commit's version number
	(the "3.xx.x" of the commit title) before it commits, so every shipped commit carries its own version.
--]]

return {
	version = "3.89.0",
	date = "2026-10-09", -- the commit's date
	commit = "Skill breakdown grid: title slot, snake of levels, page arrows; Nexus Star opens the menu", -- the commit title (short)
	-- what this commit added / changed / fixed: shown in chat when a player joins (ChatService.sendReleaseNotes)
	summary = {
		added = {
			"Skill breakdowns are a grid: the skill's title top-left, every level in the Hypixel snake, and page arrows for levels past the first page",
			"Hover a level for its rewards and status, or hover the title for XP, wisdom and the next reward",
			"Clicking the Nexus Star in the hotbar equips it and opens the Nexus menu",
		},
		changed = {
			"The old Skill page with the scrolling level strip is gone; Farming and Combat run to level 60 on three pages",
		},
		fixed = {},
	},
}
