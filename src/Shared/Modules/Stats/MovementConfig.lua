--[[
	MovementConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Movement tuning shared by the server (MovementService) and the client (SprintController, CameraController).

	sprint
	  keys             hold any of these to sprint
	  resource         the ResourceConfig resource sprinting spends (Stamina)
	  drainPerSecond   resource spent per second while sprinting AND moving
	  minToStart       resource needed to start / resume a sprint (stops flicker at ~0)
	  speedStat        the stat chain attribute sprint boosts: a +speedBonus flat boost is added to it while sprinting, so the
	                   Speed attribute really reads 16 -> 32 (shown as "Sprint" in its breakdown; never saved)
	  speedBonus       the flat Speed added
	  fovBonus         degrees the camera field of view widens while sprinting (first and third person)
	  fovSpeed         how fast the field of view eases (higher = snappier; about 3 / seconds)
--]]

local MovementConfig = {}

MovementConfig.sprint = {
	keys = { Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift },
	resource = "Stamina",
	drainPerSecond = 5,
	minToStart = 5,
	speedStat = "Speed",
	speedBonus = 16,
	fovBonus = 20,
	fovSpeed = 10,
}

return MovementConfig
