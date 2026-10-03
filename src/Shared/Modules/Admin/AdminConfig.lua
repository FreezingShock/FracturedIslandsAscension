--[[
	AdminConfig (ModuleScript)
	Place inside: ReplicatedStorage > Modules

	The ONE place that decides who is an admin. Server scripts re-check this on
	every admin request; the client only uses it to decide whether to show the
	button, so hiding the UI is never the security.

	  AdminConfig.isAdmin(player)    true for listed ids (and any player in Studio)
	  AdminConfig.isAdminId(userId)  strict id check, ignores the Studio bypass
--]]

local RunService = game:GetService("RunService")

local AdminConfig = {}

AdminConfig.ADMIN_IDS = { 288851273 } -- Nate

-- In Studio every test player counts as an admin (test players have fake ids).
-- Flip to false to test the non-admin path.
AdminConfig.studioBypass = true

-- Limits the admin panel enforces on the server.
AdminConfig.MAX_GIVE = 9999
AdminConfig.MAX_STAT = 1e9
AdminConfig.MAX_BONUS_DURATION = 3600 -- seconds
AdminConfig.MAX_BONUS_AMOUNT = 1e6

function AdminConfig.isAdminId(userId: number): boolean
	return table.find(AdminConfig.ADMIN_IDS, userId) ~= nil
end

function AdminConfig.isAdmin(player: Player): boolean
	if AdminConfig.studioBypass and RunService:IsStudio() then
		return true
	end
	return AdminConfig.isAdminId(player.UserId)
end

return AdminConfig
