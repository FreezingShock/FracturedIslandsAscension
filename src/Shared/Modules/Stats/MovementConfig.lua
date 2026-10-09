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
	  animations       { ground = {f=,fr=,r=,br=,b=,bl=,l=,fl=}, air = {...} } asset ids of the 8 directional clips (Blender: tools/blender/gen_dodge_roll_r6.py)
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
	requireGround = false, -- true = no rolling in the air (false: the air clips play)
	statDistance = "DodgeDistance",
	sound = "", -- whoosh: silent until you set an id
	-- the 8 roll clips, picked by the angle between the roll direction and where the character faces (f = forward, fr, r, br, b, bl, l, fl);
	-- `air` plays when the roller is not standing on anything. A type may override any of it (dodge.types.heavy.animations = {...}).
	animations = {
		ground = {
			f = "rbxassetid://109782061774123",
			fr = "rbxassetid://139065912490102",
			r = "rbxassetid://89731343433947",
			br = "rbxassetid://100039428146587",
			b = "rbxassetid://121367520278861",
			bl = "rbxassetid://115604823499926",
			l = "rbxassetid://129952270481506",
			fl = "rbxassetid://74166854028412",
		},
		air = {
			f = "rbxassetid://107315233101713",
			fr = "rbxassetid://122827429084307",
			r = "rbxassetid://72581392122109",
			br = "rbxassetid://119210140360871",
			b = "rbxassetid://120476070242479",
			bl = "rbxassetid://86967347179960",
			l = "rbxassetid://74242401533663",
			fl = "rbxassetid://125374623391694",
		},
	},
	animationDashStart = 2 / 30, -- seconds into the clip where the dash must start (clips are authored with the crouch first)
	animationDuration = 0.28, -- the dash time the clips were authored for; other durations play the clip at animationDuration / duration
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
