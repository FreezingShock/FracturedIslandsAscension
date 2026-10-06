--[[
	CombatFX (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Swing trail, spark burst and swing / equip sounds for any weapon. Everything is read from CombatConfig (fx library,
	sounds library, steps[i].sound / .trail), so changing a look or a sound is a config edit. Nothing here is per weapon:
	the trail finds the blade by itself (longest axis of the Handle, tip = the end farthest from the hand), so every
	future sword gets it without setup.

	Runs locally on every client: the swinger's client calls it at once, and the other clients call it when the server
	broadcasts SwordSwing. (Animations replicate by themselves; trails and sounds do not.)

	  CombatFX.swing(character, weaponType, stepIndex, attackSpeed, weaponId?)   trail window + burst for one swing (its sound plays on a hit: hitSound)
	  CombatFX.equip(character, weaponType, weaponId?)                           equip sound
	  CombatFX.impact(position, weaponType, weaponId?)                           the weapon's `impact` slot sound at a hit
	CombatFX.playAt(position, entry)                                           any sound entry, 3D at a world position
	  CombatFX.stop(character)                                                   trail off (unequip, death)
	  CombatFX.preload()                                                         load every configured sound
--]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")

local CombatConfig = require(script.Parent:WaitForChild("CombatConfig")) :: any

local CombatFX = {}

-- [Tool] = { handle, fxKey, trail, emitter, ticket }
local rigs = setmetatable({}, { __mode = "k" })

local function toolOf(character: Model): Tool?
	return character and character:FindFirstChildOfClass("Tool") or nil
end

local function handOf(character: Model): Vector3
	local arm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand") or character:FindFirstChild("HumanoidRootPart")
	if arm and arm:IsA("BasePart") then
		return (arm.CFrame * CFrame.new(0, arm.Name == "Right Arm" and -0.9 or 0, 0)).Position
	end
	return Vector3.zero
end

--- Trail + burst objects on the tool's Handle, built once per tool (rebuilt when the fx key changes).
local function ensureRig(character: Model, tool: Tool, fx: any, fxKey: string): any?
	local handle = tool:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		return nil
	end
	local rig = rigs[tool]
	if rig and rig.fxKey == fxKey and rig.trail.Parent then
		return rig
	end
	if rig then
		rig.a0:Destroy() -- the emitter sits on a0 and goes with it
		rig.a1:Destroy()
		rig.trail:Destroy()
	end

	-- blade axis = longest side of the handle; the tip is the end farther from the hand
	local size = handle.Size
	local axis = Vector3.xAxis
	local length = size.X
	if size.Y > length then axis, length = Vector3.yAxis, size.Y end
	if size.Z > length then axis, length = Vector3.zAxis, size.Z end
	local half = axis * (length / 2)
	local hand = handOf(character)
	local plus = (handle.CFrame * CFrame.new(half)).Position
	local minus = (handle.CFrame * CFrame.new(-half)).Position
	local tipLocal, pommelLocal
	if (plus - hand).Magnitude >= (minus - hand).Magnitude then
		tipLocal, pommelLocal = half, -half
	else
		tipLocal, pommelLocal = -half, half
	end

	local t = fx.trail
	local a0 = Instance.new("Attachment") -- outer end of the ribbon (the tip)
	a0.Name = "TrailTip"
	a0.Position = tipLocal * 0.97
	a0.Parent = handle
	local a1 = Instance.new("Attachment") -- inner end of the ribbon
	a1.Name = "TrailBase"
	a1.Position = pommelLocal:Lerp(tipLocal, t and t.bladeFrom or 0.35)
	a1.Parent = handle

	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Enabled = false
	trail.FaceCamera = true
	if t then
		trail.Color = t.color or trail.Color
		trail.Lifetime = t.lifetime or 0.2
		trail.LightEmission = t.lightEmission or 0.8
		trail.MinLength = t.minLength or 0.02
		trail.Transparency = t.transparency or trail.Transparency
		trail.WidthScale = t.width or trail.WidthScale
	end
	trail.Parent = handle

	local b = fx.burst
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "SwingBurst"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Drag = 4
	emitter.LockedToPart = false
	if b then
		emitter.Color = b.color or emitter.Color
		emitter.Size = b.size or emitter.Size
		emitter.Lifetime = b.lifetime or emitter.Lifetime
		emitter.Speed = b.speed or emitter.Speed
		emitter.LightEmission = b.lightEmission or 1
	end
	emitter.Parent = a0

	rig = { handle = handle, fxKey = fxKey, trail = trail, emitter = emitter, a0 = a0, a1 = a1, ticket = 0 }
	rigs[tool] = rig
	return rig
end

local function playSound(parent: Instance, entry: any)
	if not (entry and entry.id and entry.id ~= "") then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = entry.id
	sound.Volume = entry.volume or 0.6
	local pitch = entry.pitch
	sound.PlaybackSpeed = pitch and (pitch[1] + (pitch[2] - pitch[1]) * math.random()) or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = entry.minDistance or 12
	sound.RollOffMaxDistance = entry.maxDistance or 80
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 4)
end

function CombatFX.swing(character: Model, weaponType: string, stepIndex: number, attackSpeed: number?, weaponId: string?)
	local cfg = CombatConfig.get(weaponType)
	local step = cfg and cfg.steps[stepIndex]
	local tool = character and toolOf(character)
	local handle = tool and tool:FindFirstChild("Handle")
	if not (step and tool and handle) then
		return
	end
	local speed = math.max(0.5, attackSpeed or 1)

	-- trail window + burst at the hit frame
	local fx, fxKey = CombatConfig.fxFor(weaponType, weaponId)
	local rig = fx and ensureRig(character, tool, fx, fxKey)
	if not rig then
		return
	end
	rig.ticket += 1
	local ticket = rig.ticket
	local window = step.trail
	if fx.trail and window then
		task.delay(window.from / speed, function()
			if rig.ticket == ticket then
				rig.trail.Enabled = true
			end
		end)
		task.delay(window.to / speed, function()
			if rig.ticket == ticket then
				rig.trail.Enabled = false
			end
		end)
	end
	if fx.burst then
		task.delay((step.hitFrame or 0) / speed, function()
			if rig.ticket == ticket and rig.emitter.Parent then
				rig.emitter:Emit(fx.burst.count or 6)
			end
		end)
	end
end

--- The swing's attack sound (steps[i].sound, or critSound on a crit), 3D at the point the blow landed. Played only for
--- a swing that hit something, from the WeaponHit broadcast, never on a miss.
function CombatFX.hitSound(position: Vector3, weaponType: string, stepIndex: number, weaponId: string?, isCrit: boolean)
	CombatFX.playAt(position, (CombatConfig.stepSound(weaponType, stepIndex, weaponId, isCrit)))
end

function CombatFX.equip(character: Model, weaponType: string, weaponId: string?)
	local tool = character and toolOf(character)
	local handle = tool and tool:FindFirstChild("Handle")
	if handle then
		playSound(handle, CombatConfig.slotSound(weaponType, "equip", weaponId))
	end
end

--- A 3D sound entry ({ id, volume, pitch, minDistance, maxDistance }) played at a world position; silent for an empty id.
function CombatFX.playAt(position: Vector3, entry: any)
	if not (entry and entry.id and entry.id ~= "") then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.Transparency, anchor.Size = true, false, false, 1, Vector3.one
	anchor.Position = position
	anchor.Parent = workspace
	playSound(anchor, entry)
	Debris:AddItem(anchor, 4)
end

function CombatFX.impact(position: Vector3, weaponType: string, weaponId: string?)
	CombatFX.playAt(position, CombatConfig.slotSound(weaponType, "impact", weaponId))
end

function CombatFX.stop(character: Model)
	local tool = character and toolOf(character)
	local rig = tool and rigs[tool]
	if rig then
		rig.ticket += 1
		rig.trail.Enabled = false
	end
end

function CombatFX.preload()
	local assets, seen = {}, {}
	local EnemyConfig = require(script.Parent:WaitForChild("EnemyConfig")) :: any
	for _, library in ipairs({ CombatConfig.sounds, EnemyConfig.sounds }) do
		for _, entry in pairs(library) do
			if entry.id and entry.id ~= "" and not seen[entry.id] then
				seen[entry.id] = true
				local sound = Instance.new("Sound")
				sound.SoundId = entry.id
				table.insert(assets, sound)
			end
		end
	end
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
		for _, s in ipairs(assets) do
			s:Destroy()
		end
	end)
end

return CombatFX
