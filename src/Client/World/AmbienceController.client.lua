--[[
	AmbienceController (LocalScript, Client)
	Place inside: StarterPlayerScripts

	The ambience driver: the rolling background music, and the footsteps / jump / hard landing of every character (yours and
	other players', 3D from each body). Menu sounds are fired by CentralizedMenuController through the Ambience module.

	  MUSIC       one Sound in SoundService. It waits a random gap (music.gapMin..gapMax), plays one random track with a fade in
	              and out, then waits another gap. The next start time is the attribute NextTrackAt on that Sound (os.clock based).
	  FOOTSTEPS   each stride (steps.stride studs) of real horizontal ground covered plays one step, so walking, sprinting and
	              dashing all step at their true rate. The sound is picked from the floor material via AmbienceConfig.stepFor.
	  PRELOAD     at launch every step variant, cue and music track is preloaded; SoundService.AmbienceLoaded / AmbienceTotal
	              report how many loaded.
	  JUMP / LAND a jump sound on the Jumping state; a landing sound on Landed after a fall of at least cues.land.minDrop studs.

	Everything reads humanoid state. Nothing is sent to the server.
--]]

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AmbienceConfig = require(Modules:WaitForChild("Config"):WaitForChild("AmbienceConfig")) :: any
local Ambience = require(script.Parent:WaitForChild("Ambience")) :: any

type Watch = {
	humanoid: Humanoid,
	root: BasePart,
	distance: number, -- studs of ground covered since the last step
	sinceStep: number, -- seconds since the last step (the minInterval floor)
	fallY: number?,
	lastId: string?, -- the footstep variant played last, so the next one differs
}
local watched: { [Model]: Watch } = {}

-- ===================== MUSIC =====================
local music = Instance.new("Sound")
music.Name = "AmbienceMusic"
music.Looped = false
music.Volume = 0
music.Parent = SoundService

local function fade(to: number, seconds: number)
	local tween = TweenService:Create(music, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = to })
	tween:Play()
	return tween
end

local function randomGap(): number
	return AmbienceConfig.music.gapMin + math.random() * (AmbienceConfig.music.gapMax - AmbienceConfig.music.gapMin)
end

task.spawn(function()
	local config = AmbienceConfig.music
	local lastIndex = nil
	while true do
		local gap = randomGap()
		music:SetAttribute("NextTrackAt", os.clock() + gap)
		task.wait(gap) -- the quiet gap before a track, including the first one

		local tracks = config.tracks
		if #tracks > 0 then
			local index = math.random(#tracks)
			if #tracks > 1 and index == lastIndex then
				index = index % #tracks + 1
			end
			lastIndex = index
			local track = tracks[index]
			music.SoundId = track.id
			local waited = 0
			while not music.IsLoaded and waited < 10 do
				task.wait(0.2)
				waited += 0.2
			end
			if music.IsLoaded then
				music.TimePosition = 0
				music.Volume = 0
				music:Play()
				fade(config.volume, config.fadeSeconds)
				local length = music.TimeLength
				task.wait(math.max(0, length - config.fadeSeconds))
				fade(0, config.fadeSeconds)
				task.wait(config.fadeSeconds)
				music:Stop()
			else
				warn("[AmbienceController] music track did not load: " .. track.name)
			end
		end
	end
end)

-- ===================== CHARACTERS =====================
local function watch(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not (humanoid and root) then
		return
	end
	local entry: Watch = { humanoid = humanoid, root = root, distance = 0, sinceStep = math.huge, fallY = nil }
	watched[character] = entry

	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			Ambience.at(root, AmbienceConfig.cues.jump)
		elseif new == Enum.HumanoidStateType.Freefall then
			entry.fallY = root.Position.Y
		elseif new == Enum.HumanoidStateType.Landed then
			local top = entry.fallY
			entry.fallY = nil
			if top and top - root.Position.Y >= AmbienceConfig.cues.land.minDrop then
				Ambience.at(root, AmbienceConfig.cues.land)
			end
		end
	end)
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			watched[character] = nil
		end
	end)
end

local function watchPlayer(player: Player)
	if player.Character then
		task.spawn(watch, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(watch, character)
	end)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end

-- footsteps: one shared loop over every watched character. Ground covered (real velocity, so dashes count too) is the
-- clock: every stride of ground plays one step. Standing still or airborne resets the distance, so a step never lags a stop.
RunService.Heartbeat:Connect(function(dt)
	for _, entry in pairs(watched) do
		local humanoid = entry.humanoid
		entry.sinceStep += dt
		local grounded = humanoid.Health > 0 and humanoid.FloorMaterial ~= Enum.Material.Air
		local velocity = entry.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		if grounded and speed >= AmbienceConfig.steps.minSpeed then
			entry.distance += speed * dt
			local cfg = AmbienceConfig.stepFor(humanoid.FloorMaterial)
			if entry.distance >= cfg.stride and entry.sinceStep >= cfg.minInterval then
				entry.distance -= cfg.stride
				entry.sinceStep = 0
				Ambience.step(entry.root, cfg, entry)
			end
		else
			entry.distance = 0
		end
	end
end)

-- preload: every step variant, cue and music track is fetched once at launch, so the first step is never late
task.spawn(function()
	local holder = Instance.new("Folder")
	holder.Name = "AmbiencePreload"
	holder.Parent = SoundService
	local seen, sounds = {}, {}
	local function add(id: string?)
		if id and id ~= "" and not seen[id] then
			seen[id] = true
			local sound = Instance.new("Sound")
			sound.SoundId = id
			sound.Parent = holder
			table.insert(sounds, sound)
		end
	end
	for _, surface in pairs(AmbienceConfig.surfaces) do
		for _, id in ipairs(surface.variants or {}) do
			add(id)
		end
	end
	for _, cue in pairs(AmbienceConfig.cues) do
		add(cue.id)
	end
	for _, track in ipairs(AmbienceConfig.music.tracks) do
		add(track.id)
	end
	pcall(function()
		ContentProvider:PreloadAsync(sounds)
	end)
	local loaded, missing = 0, {}
	for _, sound in ipairs(sounds) do
		if sound.IsLoaded then
			loaded += 1
		else
			table.insert(missing, sound.SoundId)
		end
	end
	SoundService:SetAttribute("AmbienceLoaded", loaded)
	SoundService:SetAttribute("AmbienceTotal", #sounds)
	if #missing > 0 then
		warn("[AmbienceController] not loaded: " .. table.concat(missing, ", "))
	end
end)
