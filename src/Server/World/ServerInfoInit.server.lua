-- Publishes when this server started (workspace attribute ServerStart, in server time) so clients can show the uptime
-- (ViewMenu UP row) without any per-second server work. Place inside: ServerScriptService
workspace:SetAttribute("ServerStart", workspace:GetServerTimeNow())
