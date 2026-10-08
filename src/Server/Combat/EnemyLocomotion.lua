--[[
	EnemyLocomotion (ModuleScript, Server)
	Place inside: ServerScriptService   (required by EnemyService)

	An R6 rig built from a HumanoidDescription has no Animate script, so mobs slid around stiff. This plays idle / walk / run on the
	mob's Animator from Humanoid.Running, scaled by its speed. Ids: EnemyConfig.locomotion (Roblox's own R6 set) or the enemy's
	mob.locomotion = { idle, walk, run } for its own custom animations. The tracks sit at Movement priority, so an attack animation
	(Action) plays over them and the legs keep walking underneath.

	  EnemyLocomotion.attach(model, humanoid, override?)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnemyConfig")) :: any

local EnemyLocomotion = {}

function EnemyLocomotion.attach(model: Model, humanoid: Humanoid, override: any?)
	local cfg = table.clone(EnemyConfig.locomotion)
	for key, value in pairs(override or {}) do
		cfg[key] = value
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") :: Animator?
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function load(id: any, priority: Enum.AnimationPriority): AnimationTrack?
		if type(id) ~= "string" or id == "" then
			return nil
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if not ok then
			return nil
		end
		track.Looped = true
		track.Priority = priority
		return track
	end

	local idle = load(cfg.idle, Enum.AnimationPriority.Idle)
	local walk = load(cfg.walk, Enum.AnimationPriority.Movement)
	local run = (cfg.run == cfg.walk) and walk or load(cfg.run, Enum.AnimationPriority.Movement)
	local current: AnimationTrack? = nil

	local function play(track: AnimationTrack?, speed: number?)
		if track ~= current then
			if current then
				current:Stop(0.15)
			end
			current = track
			if track then
				track:Play(0.15)
			end
		end
		if track and speed then
			track:AdjustSpeed(speed)
		end
	end

	humanoid.Running:Connect(function(speed: number)
		if humanoid.Health <= 0 then
			return
		end
		if speed < 0.6 then
			play(idle, 1)
		elseif speed >= cfg.runAt and run then
			play(run, speed / cfg.speedScale)
		else
			play(walk, speed / cfg.speedScale)
		end
	end)
	humanoid.Died:Once(function()
		play(nil)
	end)
	play(idle, 1)
end

return EnemyLocomotion
