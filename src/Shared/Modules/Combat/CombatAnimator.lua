--[[
	CombatAnimator (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Plays combat animations on a character's Animator. What plays is decided by CombatConfig (library + weapon type +
	per-weapon overrides); this module only loads, caches and plays tracks. Entries without an id play nothing.
	Tracks played by the owning client replicate to everyone else, so only the local player's client calls this.

	  CombatAnimator.play(character, weaponType, stepIndex, attackSpeed, weaponId?) -> AnimationTrack?   combo step
	  CombatAnimator.playSlot(character, weaponType, slot, weaponId?, speed?)       -> AnimationTrack?   "equip", "idle", ...
	  CombatAnimator.stopSlot(character, slot)
	  CombatAnimator.stop(character)                 stops the combo step and every slot
	  CombatAnimator.preload(weaponType?)            loads the animation assets of one type (or all types) ahead of time
--]]

local ContentProvider = game:GetService("ContentProvider")

local CombatConfig = require(script.Parent:WaitForChild("CombatConfig")) :: any

local CombatAnimator = {}

-- [Animator] = { tracks = { [libraryKey] = AnimationTrack }, current = AnimationTrack?, slots = { [slot] = AnimationTrack } }
local state = setmetatable({}, { __mode = "k" })

local function getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator") or nil
end

local function getState(animator: Animator): any
	local mine = state[animator]
	if not mine then
		mine = { tracks = {}, slots = {} }
		state[animator] = mine
	end
	return mine
end

--- Track for a library entry, loaded once per Animator. nil when the entry has no id yet.
local function trackFor(animator: Animator, mine: any, key: string, entry: any): AnimationTrack?
	if not entry or not entry.id or entry.id == "" then
		return nil
	end
	local cached = mine.tracks[key]
	if cached and cached.Animation and cached.Animation.AnimationId == entry.id then
		return cached
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = entry.id
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority[entry.priority or "Action"] or Enum.AnimationPriority.Action
	track.Looped = entry.looped == true
	mine.tracks[key] = track
	return track
end

function CombatAnimator.play(character: Model, weaponType: string, stepIndex: number, attackSpeed: number?, weaponId: string?): AnimationTrack?
	local animator = getAnimator(character)
	if not animator then
		return nil
	end
	local mine = getState(animator)
	if mine.current then
		mine.current:Stop(0.08)
		mine.current = nil
	end
	local entry, key = CombatConfig.stepAnimation(weaponType, stepIndex, weaponId)
	local track = key and trackFor(animator, mine, key, entry)
	if not track then
		return nil
	end
	track:Play(entry.fade or 0.06, 1, math.max(0.5, attackSpeed or 1) * (entry.speed or 1))
	mine.current = track
	return track
end

function CombatAnimator.playSlot(character: Model, weaponType: string, slot: string, weaponId: string?, speed: number?): AnimationTrack?
	local animator = getAnimator(character)
	if not animator then
		return nil
	end
	local mine = getState(animator)
	local entry, key = CombatConfig.slotAnimation(weaponType, slot, weaponId)
	local previous = mine.slots[slot]
	local track = key and trackFor(animator, mine, key, entry)
	if previous and previous ~= track then
		previous:Stop(0.1)
		mine.slots[slot] = nil
	end
	if not track then
		return nil
	end
	if not (track.IsPlaying and track.Looped) then -- a running loop (idle) is left alone
		track:Play(entry.fade or 0.1, 1, speed or entry.speed or 1)
	end
	mine.slots[slot] = track
	return track
end

function CombatAnimator.stopSlot(character: Model, slot: string)
	local animator = getAnimator(character)
	local mine = animator and state[animator]
	local track = mine and mine.slots[slot]
	if track then
		track:Stop(0.1)
		mine.slots[slot] = nil
	end
end

function CombatAnimator.stop(character: Model)
	local animator = getAnimator(character)
	local mine = animator and state[animator]
	if not mine then
		return
	end
	if mine.current then
		mine.current:Stop(0.1)
		mine.current = nil
	end
	for slot, track in pairs(mine.slots) do
		track:Stop(0.1)
		mine.slots[slot] = nil
	end
end

--- Pull the animation assets into memory before the first swing so the first click does not stutter.
function CombatAnimator.preload(weaponType: string?)
	local types = weaponType and { weaponType } or CombatConfig.types()
	local assets, seen = {}, {}
	for _, t in ipairs(types) do
		for _, key in ipairs(CombatConfig.libraryKeysFor(t)) do
			local entry = CombatConfig.animations[key]
			if entry and entry.id and entry.id ~= "" and not seen[entry.id] then
				seen[entry.id] = true
				local animation = Instance.new("Animation")
				animation.AnimationId = entry.id
				table.insert(assets, animation)
			end
		end
	end
	if #assets > 0 then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
			for _, a in ipairs(assets) do
				a:Destroy()
			end
		end)
	end
end

return CombatAnimator
