-- Starts EnemyService (config-driven mobs on Workspace.EnemySpawns). Place inside: ServerScriptService
local ServerScriptService = game:GetService("ServerScriptService")
require(ServerScriptService:WaitForChild("DeathService")) -- takes over every death (glitch + burst), must be watching before mobs spawn
require(ServerScriptService:WaitForChild("EnemyService"))
