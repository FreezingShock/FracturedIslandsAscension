--[[
	DamageService (ModuleScript, Server)
	Place inside: ServerScriptService

	Server-authoritative melee hits. WeaponManager calls DamageService.swing at each combo step's hit frame (only for a
	swing it accepted, and only if the same weapon is still held). Clients never send targets or positions: the server
	finds the targets from the swinger's own position and facing.

	A target is any Model tagged "Damageable" (DamageService.TAG) with a living Humanoid: training dummies now, PvP / mobs
	later by just adding the tag. Hit rules (numbers come from CombatConfig, per combo step):
	  * inside `reach` studs in front of the swinger, measured to the target's edge, within `arc` degrees of the facing
	  * not more than `verticalTolerance` studs above / below
	  * nothing solid in between (line of sight) when `damage.lineOfSight`
	  * nearest `maxTargets` only; one hit per target per swing

	Damage = (weapon Damage x rarity scaling + flatBase) x (1 + Strength x strengthScale) x step.damageMult, then a crit roll
	(see CombatConfig.damage). Strength / CritChance / CritIncrease = the player's stat chain value + the held weapon's own
	stat of that name (weapon stats are not applied to the chain yet).

	Each hit is broadcast on the WeaponHit remote so every client can show the impact (flash, number, effects, sound):
	{ target, full (charge bar full), tierMult, aoe (splash), taken (a player was hurt), crash (landing-swing Crash hit, primary or AoE), step (combo step, swings only), first (nearest target), position (number spot), point (contact on the body), dir (spray direction), enemyType, damage, isCrit,
	killed, attacker, weaponType, weaponId }. EnemyType is a model attribute (EnemyConfig key).

	  DamageService.swing(player, stepIndex, weaponId, weaponStats, crash?)  a combo step (cone from CombatConfig)
	  DamageService.strike(player, ability, weaponId, weaponStats) -> n    an ability hit (circle / cone / line, AbilityConfig)
	  DamageService.query(character, origin, facing, shape) -> hits        the shared target query
	  DamageService.strikeHits(player, hits, hitInfo, weaponId, weaponStats, from) -> n   hit a ready list (chain jumps, burn ticks)
	  DamageService.hitFor(model, from) -> hit      a query-style hit entry for one Damageable model (nil when dead / not a target)
	  DamageService.compute(player, weaponStats, weaponId, step, forceCrit?, crash?, tier?) -> amount, isCrit
	  DamageService.hurtPlayer(player, amount, source?) -> damage dealt     an enemy hits a player (Defense applies)
	  DamageService.TAG
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local Items = require(Modules:WaitForChild("Items")) :: any
local AttributeStatManager = require(ServerScriptService:WaitForChild("AttributeStatManager")) :: any
local DamageTracker = require(ServerScriptService:WaitForChild("DamageTracker")) :: any

local DamageService = {}
DamageService.TAG = "Damageable"

local WeaponHitEvent = ReplicatedStorage:FindFirstChild("WeaponHit")
if not WeaponHitEvent then
	WeaponHitEvent = Instance.new("RemoteEvent")
	WeaponHitEvent.Name = "WeaponHit"
	WeaponHitEvent.Parent = ReplicatedStorage
end

local DAMAGE = CombatConfig.damage

--- The weapon item's own value of a stat (a plain number, or the flat part of { flat, mult }).
local function weaponStat(weaponId: string, key: string): number
	local def = Items.get(weaponId)
	local value = def and def.stats and def.stats[key]
	if type(value) == "table" then
		return tonumber(value.flat) or 0
	end
	return tonumber(value) or 0
end

local function stat(player: Player, weaponId: string, key: string): number
	return (tonumber(AttributeStatManager.GetFinalValue(player, key)) or 0) + weaponStat(weaponId, key)
end

function DamageService.compute(player: Player, weaponStats: any, weaponId: string, step: any, forceCrit: boolean?, crash: boolean?, tier: any?): (number, boolean)
	local base = ((weaponStats.baseDamage or 0) + DAMAGE.flatBase)
		* (1 + stat(player, weaponId, "Strength") * DAMAGE.strengthScale)
		* (step.damageMult or 1)
		* (tier and tier.mult or 1) -- the swing-timing tier: the only place the timing multiplier applies

	local critChance = math.clamp(stat(player, weaponId, "CritChance"), 0, DAMAGE.critChanceCap)
	local isCrit
	if forceCrit ~= nil then
		isCrit = forceCrit
	else
		isCrit = math.random() * 100 < critChance
	end
	if isCrit then
		base *= 1 + (DAMAGE.critBase + stat(player, weaponId, "CritIncrease")) * DAMAGE.critScale
	end
	if crash then
		base *= CombatConfig.crash.damageMult -- after the crit multiplier: a crash crit is the strongest hit
	end
	return math.max(1, math.floor(base + 0.5)), isCrit
end

--- Horizontal radius of a target (half its widest footprint side), so a big target is hit by its edge.
local function radiusOf(model: Model): number
	local size = model:GetExtentsSize()
	return math.max(size.X, size.Z) / 2
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function blocked(fromPosition: Vector3, targetPosition: Vector3, ignore: { Instance }): boolean
	-- dropped items and other targets (a dying one stays frozen in place for its death animation) never block a hit
	local filter = table.clone(ignore)
	local drops = workspace:FindFirstChild("ItemDrops")
	if drops then
		table.insert(filter, drops)
	end
	for _, other in ipairs(CollectionService:GetTagged(DamageService.TAG)) do
		table.insert(filter, other)
	end
	for _, other in ipairs(CollectionService:GetTagged("Enemy")) do
		table.insert(filter, other)
	end
	rayParams.FilterDescendantsInstances = filter
	return workspace:Raycast(fromPosition, targetPosition - fromPosition, rayParams) ~= nil
end

--- Everything Damageable inside a shape, nearest first. The shape is measured from `origin` (horizontal distance, to the
--- target's edge) along `facing` (a flat unit vector):
---   { kind = "cone", reach, arc }   { kind = "circle", radius }   { kind = "line", length, width }
--- optional: vertical (studs up / down), lineOfSight (false = walls do not block).
--- Returns a list of { model, humanoid, root, distance, flat }.
function DamageService.query(character: Model?, origin: Vector3, facing: Vector3, shape: any): { any }
	local vertical = shape.vertical or DAMAGE.verticalTolerance
	local needSight = shape.lineOfSight
	if needSight == nil then
		needSight = DAMAGE.lineOfSight
	end
	local kind = shape.kind or "cone"
	local halfArc = math.rad((shape.arc or 360) / 2)

	local hits = {}
	for _, model in ipairs(CollectionService:GetTagged(DamageService.TAG)) do
		local targetHumanoid = model:IsA("Model") and model:FindFirstChildOfClass("Humanoid")
		local targetRoot = targetHumanoid and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) :: BasePart?
		if model ~= character and targetHumanoid and targetRoot and targetHumanoid.Health > 0 then
			local delta = targetRoot.Position - origin
			local flat = Vector3.new(delta.X, 0, delta.Z)
			local distance = flat.Magnitude
			local radius = radiusOf(model)
			local inside = false
			if math.abs(delta.Y) <= vertical then
				if kind == "circle" then
					inside = distance - radius <= shape.radius
				elseif kind == "line" then
					local along = flat:Dot(facing)
					local across = (flat - facing * along).Magnitude
					inside = along >= -radius and along - radius <= shape.length and across - radius <= (shape.width or 4) / 2
				elseif distance - radius <= shape.reach then -- cone
					inside = distance <= radius + 0.25
					if not inside then
						local angle = math.acos(math.clamp(facing:Dot(flat.Unit), -1, 1))
						inside = angle <= halfArc + math.atan2(radius, distance) -- a wide target is hit by its edge
					end
				end
			end
			if inside and not (needSight and blocked(origin + Vector3.new(0, 1, 0), targetRoot.Position, { character, model })) then
				table.insert(hits, { model = model, humanoid = targetHumanoid, root = targetRoot, distance = distance, flat = flat })
			end
		end
	end
	table.sort(hits, function(a, b)
		return a.distance < b.distance
	end)
	return hits
end

--- The caster's flat origin / facing, or nil when dead or gone.
local function casterFrame(player: Player): (Model?, Vector3?, Vector3?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if facing.Magnitude < 1e-3 then
		return nil, nil, nil
	end
	return character, root.Position, facing.Unit
end

local contactParams = RaycastParams.new()
contactParams.FilterType = Enum.RaycastFilterType.Include

--- Where the hit lands on the target's body: a ray from the attacker's side toward a random spot on the torso (so
--- repeated hits do not stack on one pixel) stops on the nearest surface. Returns that point and the direction the
--- effect should spray (back toward the attacker, leaning on the surface normal).
local function contactOf(from: Vector3, hit: any): (Vector3, Vector3)
	local center = hit.root.Position
	local toward = from - center
	local dir = toward.Magnitude > 0.05 and toward.Unit or Vector3.yAxis
	local aim = center + Vector3.new((math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.2)
	contactParams.FilterDescendantsInstances = { hit.model }
	local result = workspace:Raycast(aim + dir * 8, -dir * 16, contactParams)
	if result then
		return result.Position, (dir * 0.65 + result.Normal * 0.35).Unit
	end
	return aim + dir * (radiusOf(hit.model) * 0.8), dir
end

--- Damage, knock back and broadcast every target of `hits` (from query). `hitInfo` = { damageMult, knockback, maxTargets }.
--- `from` = where the blow comes from (the swinger, or an ability's fixed origin): effects spray back toward it.
local function applyHits(player: Player, hits: { any }, hitInfo: any, facing: Vector3, weaponId: string, weaponStats: any, from: Vector3, stepIndex: number?, crash: boolean?, tier: any?, aoe: boolean?): number
	local count = math.min(#hits, hitInfo.maxTargets or 1)
	for i = 1, count do
		local hit = hits[i]
		local amount, isCrit = DamageService.compute(player, weaponStats, weaponId, hitInfo, nil, crash, tier)
		local taken = hit.model:GetAttribute("DamageTakenMult") -- a blocking enemy (EnemyAttacks parry) takes a share of the blow
		if type(taken) == "number" then
			amount *= taken
		end
		hit.humanoid:TakeDamage(amount)
		DamageTracker.record(player, amount)
		hit.model:SetAttribute("LastHit", os.clock())
		hit.model:SetAttribute("LastAttacker", player.UserId)

		-- push the target away from the attacker
		local direction = hit.distance > 0.05 and hit.flat.Unit or facing
		local push = hitInfo.knockback or 0
		if push > 0 then
			hit.root:ApplyImpulse((direction * push + Vector3.new(0, push * 0.25, 0)) * hit.root.AssemblyMass)
		end

		local head = hit.model:FindFirstChild("Head") :: BasePart?
		local point, dir = contactOf(from, hit)
		WeaponHitEvent:FireAllClients({
			target = hit.model,
			position = (head and head.Position or hit.root.Position) + Vector3.new(0, 1, 0), -- the damage number
			point = point, -- where the blow landed on the body (impact effects)
			dir = dir, -- unit vector the effects spray along
			step = stepIndex, -- combo step for a swing (the client plays that step's attack sound once, on the first target)
			first = i == 1,
			full = tier ~= nil and tier.full == true, -- the swing-timing bar was full (independent of crit / crash)
			tierMult = tier and tier.mult or 1,
			aoe = aoe == true, -- a splash hit (drawn smaller)
			crash = crash == true, -- a falling-swing Crash hit (red style; damage already x CombatConfig.crash.damageMult)
			enemyType = hit.model:GetAttribute("EnemyType"), -- EnemyConfig key (nil = default)
			damage = amount,
			isCrit = isCrit,
			killed = hit.humanoid.Health <= 0,
			attacker = player.UserId,
			weaponType = weaponStats.weaponType,
			weaponId = weaponId,
		})
	end
	return count
end

--- An enemy hurting a player: `amount` is the base damage, reduced by the player's Defense (amount x 100 / (100 + Defense)),
--- applied through the Humanoid and broadcast as a red number over the player. Returns the damage dealt.
function DamageService.hurtPlayer(player: Player, amount: number, source: Instance?): number
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (humanoid and root) or humanoid.Health <= 0 then
		return 0
	end
	-- dodge roll i-frames (MovementService writes DodgeUntil in server time): the hit deals nothing
	local dodgeUntil = player:GetAttribute("DodgeUntil")
	if type(dodgeUntil) == "number" and workspace:GetServerTimeNow() < dodgeUntil then
		return 0
	end
	local defense = math.max(tonumber(AttributeStatManager.GetFinalValue(player, "Defense")) or 0, 0)
	local dealt = math.max(1, math.floor(amount * 100 / (100 + defense) + 0.5))
	humanoid:TakeDamage(dealt)
	local head = character:FindFirstChild("Head") :: BasePart?
	WeaponHitEvent:FireAllClients({
		taken = true, -- a player took this: only a red number, no impact effects
		target = character,
		position = (head and head.Position or root.Position) + Vector3.new(0, 1, 0),
		damage = dealt,
		source = source,
	})
	return dealt
end

--- Hit a ready list of query hits (from query, or hitFor) with `hitInfo` = { damageMult, knockback, maxTargets }.
function DamageService.strikeHits(player: Player, hits: { any }, hitInfo: any, weaponId: string, weaponStats: any, from: Vector3): number
	local _, _, facing = casterFrame(player)
	return applyHits(player, hits, hitInfo, facing or Vector3.zAxis, weaponId, weaponStats, from)
end

--- One Damageable model as a query hit measured from `from` (nil when it is dead or not a target).
function DamageService.hitFor(model: Model, from: Vector3): any?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not (humanoid and root) or humanoid.Health <= 0 or not CollectionService:HasTag(model, DamageService.TAG) then
		return nil
	end
	local flat = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
	return { model = model, humanoid = humanoid, root = root, distance = flat.Magnitude, flat = flat }
end

function DamageService.swing(player: Player, stepIndex: number, weaponId: string, weaponStats: any, crash: boolean?, tier: any?)
	local typeConfig = CombatConfig.get(weaponStats and weaponStats.weaponType)
	local step = typeConfig and typeConfig.steps[stepIndex]
	local character, origin, facing = casterFrame(player)
	if not (character and origin and facing and step and step.reach) then
		return
	end
	local hits = DamageService.query(character, origin, facing, { kind = "cone", reach = step.reach, arc = step.arc })
	if not crash then
		applyHits(player, hits, step, facing, weaponId, weaponStats, origin, stepIndex, nil, tier)
		return
	end

	-- Crash hit: the nearest enemy in the cone takes the full hit (x damageMult), everything else within aoeRadius of it
	-- takes the AoE share. With nothing in the cone there is no hit and no AoE.
	local primary = hits[1]
	if not primary then
		return
	end
	local config = CombatConfig.crash
	applyHits(player, { primary }, step, facing, weaponId, weaponStats, origin, stepIndex, true, tier)
	local center = primary.root.Position
	local around = {}
	for _, other in ipairs(DamageService.query(character, center, facing, { kind = "circle", radius = config.aoeRadius, lineOfSight = false })) do
		if other.model ~= primary.model then
			table.insert(around, other)
		end
	end
	if #around > 0 then
		local aoeInfo = {
			damageMult = (step.damageMult or 1) * DAMAGE.aoeMult,
			knockback = (step.knockback or 0) * config.aoeKnockbackMult,
			maxTargets = config.aoeMaxTargets,
		}
		applyHits(player, around, aoeInfo, facing, weaponId, weaponStats, center, nil, true, tier, true) -- no step: no second attack sound
	end
end

--- An ability's hit: everything inside `ability.shape` around `fixedOrigin` (default: the caster's position). The shape
--- is aimed along the caster's facing. `ability` supplies damageMult / knockback / maxTargets (AbilityConfig).
--- Returns how many targets were hit.
function DamageService.strike(player: Player, ability: any, weaponId: string, weaponStats: any, fixedOrigin: Vector3?): number
	local character, origin, facing = casterFrame(player)
	if not (character and origin and facing and ability.shape) then
		return 0
	end
	local hits = DamageService.query(character, fixedOrigin or origin, facing, ability.shape)
	return applyHits(player, hits, ability, facing, weaponId, weaponStats, fixedOrigin or origin)
end

return DamageService
