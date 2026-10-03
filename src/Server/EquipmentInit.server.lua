-- Starts the server item systems (Tool factory + equipment). Runs once at boot.
local ServerScriptService = game:GetService("ServerScriptService")

require(ServerScriptService:WaitForChild("ItemTools")).ensureAll()
require(ServerScriptService:WaitForChild("EquipmentService"))
