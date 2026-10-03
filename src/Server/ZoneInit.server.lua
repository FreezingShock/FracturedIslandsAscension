-- ZoneManagerInit.server.lua (Script in ServerScriptService)
-- Initializes the zone detection system on server startup

print("[ZoneManagerInit] Starting...")

local ZoneManager = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("ZoneManager"))

print("[ZoneManagerInit] ZoneManager module loaded ✓")

ZoneManager.initialize()

print("[ZoneManagerInit] Zone detection initialized ✓")
