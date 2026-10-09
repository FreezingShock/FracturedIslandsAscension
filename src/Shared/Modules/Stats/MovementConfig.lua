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

	dodge   (the dodge roll: press `key`, the server spends Stamina and grants i-frames, the client rolls)
	  key              the keybind (F; no weapon ability uses it)
	  staminaCost      Stamina spent per roll
	  distance         studs the roll travels
	  duration         seconds the roll lasts
	  iframes          seconds after the roll starts during which enemy hits deal 0 damage (Player attribute DodgeUntil, server time)
	  cooldown         seconds between rolls (measured from the start of the previous one)
	  requireGround    true = no rolling in the air
	  statDistance     a stat-chain attribute whose value is ADDED to the distance (DodgeDistance: a boot enchant later; 0 when nobody has it)
	  sound / animation  asset ids ("" = silent / no animation until you have them): sound plays 3D at the roller for everybody
	  type / types     LAYERS: dodge (library) < dodge.types[<type>] < the Player attribute `DodgeType` (set by the server, e.g. for armor
	                   weight later; default = dodge.type). MovementConfig.dodgeFor(typeName) returns them merged.
	  New dodge type:  dodge.types.heavy = { staminaCost = 35, distance = 10, iframes = 0.18 }, then the server sets Player attribute DodgeType = "heavy"
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

MovementConfig.dodge = {
	key = Enum.KeyCode.F,
	staminaCost = 25,
	distance = 14,
	duration = 0.28,
	iframes = 0.22,
	cooldown = 0.9,
	requireGround = true,
	statDistance = "DodgeDistance",
	sound = "", -- whoosh: silent until you set an id
	animation = "", -- roll animation: none until you set an id
	type = "light",
	types = {
		light = {},
		heavy = { staminaCost = 35, distance = 10, duration = 0.34, iframes = 0.18, cooldown = 1.2 },
	},
}

--- The dodge numbers for a type ("light" | "heavy" | ...): the library values overridden by dodge.types[typeName].
function MovementConfig.dodgeFor(typeName: string?): any
	local base = MovementConfig.dodge
	local out = {}
	for k, v in pairs(base) do
		if k ~= "types" then
			out[k] = v
		end
	end
	for k, v in pairs(base.types[typeName or base.type] or base.types[base.type] or {}) do
		out[k] = v
	end
	return out
end

return MovementConfig
