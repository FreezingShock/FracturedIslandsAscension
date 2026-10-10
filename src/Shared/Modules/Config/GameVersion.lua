--[[
	GameVersion (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The game version shown in the ViewMenu VERSION row. /fia-ship rewrites `version` to the commit's version number
	(the "3.xx.x" of the commit title) before it commits, so every shipped commit carries its own version.
--]]

return {
	version = "3.92.0",
	date = "2026-10-10", -- the commit's date
	commit = "Chat speech bubble above the sender's nameplate, styled to match it", -- the commit title (short)
	-- what this commit added / changed / fixed: shown in chat when a player joins (ChatService.sendReleaseNotes)
	summary = {
		added = {
			"Chat messages show as a speech bubble above the sender's nameplate, in the nameplate's style",
			"Each player shows up to three bubbles at once, and they fade out after six seconds",
			"Your own bubble shows in third-person free camera",
		},
		changed = {
			"The bubble rises and falls with the nameplate's health bar and tags",
		},
		fixed = {
			"Roblox's own chat bubbles are turned off, so only the new bubble shows",
		},
	},
}
