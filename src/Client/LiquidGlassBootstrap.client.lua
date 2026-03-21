-- ============================================================
--  LiquidGlassBootstrap (LocalScript)
--  Place inside: StarterPlayerScripts
--
--  Activates the LiquidGlassHandler module so CollectionService
--  tag listeners fire. Without this, the ModuleScript never
--  executes and no glass instances are created.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local LiquidGlassHandler = require(Modules:WaitForChild("LiquidGlassHandler"))

print("LiquidGlassBootstrap: Active ✓ (" .. LiquidGlassHandler.getActiveCount() .. " tagged instances)")
