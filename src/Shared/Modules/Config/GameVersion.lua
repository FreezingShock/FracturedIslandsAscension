--[[
	GameVersion (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The game version shown in the ViewMenu VERSION row. /fia-ship rewrites `version` to the commit's version number
	(the "3.xx.x" of the commit title) before it commits, so every shipped commit carries its own version.
--]]

return {
	version = "3.88.0",
	date = "2026-10-09", -- the commit's date
	commit = "Collection milestone rewards and attribute breakdown: stacked sources, paging, item icons", -- the commit title (short)
	-- what this commit added / changed / fixed: shown in chat when a player joins (ChatService.sendReleaseNotes)
	summary = {
		added = {
			"Attribute breakdowns page through every source: 28 per page, with Prev and Next",
			"Items in an attribute breakdown show their own icon",
			"Collection and skill sources stack: every tier of a collection and every level of a skill is one slot, marked x7",
			"Milestone reward slots show the attribute or statistic icon in its colour",
		},
		changed = {
			"Collection and skill sources in the breakdown read Collection and Skill, with capital letters in every title",
			"The amount under each breakdown slot is larger",
		},
		fixed = {
			"Milestone reward pages built with the wrong icons and colours, and stopped partway through",
			"Collection rewards now re-apply when you join, not only after a stat changes",
		},
	},
}
