-- Boots the data managers early so their PlayerAdded hooks are connected before players load.
-- (The legacy AdminToolManager remotes were removed: the Nexus admin panel talks to the AdminAction
--  RemoteFunction in InventoryTestCommands, which re-checks admin and validates every input.)
local ServerScriptService = game:GetService("ServerScriptService")

require(ServerScriptService:WaitForChild("SkillsDataManager"))
require(ServerScriptService:WaitForChild("StatisticsDataManager"))

print("[Main] Server boot ✓")
