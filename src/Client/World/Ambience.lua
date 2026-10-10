--[[
	Ambience (ModuleScript, Client)
	Place inside: StarterPlayerScripts

	The one place that plays ambience one-shots: 3D sounds from a character (footsteps, jump, landing) and 2D UI sounds (menus).
	Every id and volume comes from ReplicatedStorage.Modules.Config.AmbienceConfig, so nothing here names a sound.

	  Ambience.at(part, cue, pitch?)  one 3D sound at a part, heard by everyone nearby (skipped when far outside the camera)
	  Ambience.step(root, cfg, state) a footstep: a random variant from cfg.variants (never the one in state.lastId), random pitch
	  Ambience.pick(variants, last)   the variant pick on its own
	  Ambience.ui(cue)                a 2D sound only the local player hears
	  Ambience.cue(name)              a named cue from AmbienceConfig.cues (menuOpen / menuClose / jump / land)

	Nothing is sent to the server: these are cosmetic and only play on this client.
--]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AmbienceConfig = require(Modules:WaitForChild("Config"):WaitForChild("AmbienceConfig")) :: any

local CULL_PADDING = 20 -- studs past a sound's roll-off where it is not even created
local LIFETIME = 6 -- seconds before a one-shot is removed

local Ambience = {}

function Ambience.at(part: BasePart, cue: any, pitch: number?)
	if cue.id == nil or cue.id == "" then
		return -- an empty slot stays silent
	end
	local rollOff = cue.rollOff or 60
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - part.Position).Magnitude > rollOff + CULL_PADDING then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = cue.id
	sound.Volume = cue.volume or 0.5
	sound.RollOffMaxDistance = rollOff
	sound.PlaybackSpeed = pitch or 1
	sound.Parent = part
	sound:Play()
	Debris:AddItem(sound, LIFETIME)
end

--- A random variant id from a surface's list, never the one played last (state.lastId). Empty ids are skipped.
--- Returns nil when the list has no playable id.
function Ambience.pick(variants: { string }?, last: string?): string?
	local playable = {}
	for _, id in ipairs(variants or {}) do
		if id ~= "" then
			table.insert(playable, id)
		end
	end
	if #playable == 0 then
		return nil
	end
	if #playable == 1 then
		return playable[1]
	end
	local candidates = {}
	for _, id in ipairs(playable) do
		if id ~= last then
			table.insert(candidates, id)
		end
	end
	return candidates[math.random(#candidates)]
end

--- One footstep. state is the character's own table, so the no-repeat rule holds per character.
function Ambience.step(root: BasePart, cfg: any, state: { lastId: string? })
	local id = Ambience.pick(cfg.variants, state.lastId)
	if not id then
		return
	end
	state.lastId = id
	local pitch = 1 + (math.random() * 2 - 1) * (cfg.pitchRange or 0)
	Ambience.at(root, { id = id, volume = cfg.volume, rollOff = cfg.rollOff }, pitch)
end

function Ambience.ui(cue: any)
	if cue.id == nil or cue.id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = cue.id
	sound.Volume = cue.volume or 0.4
	sound.Parent = SoundService
	sound:Play()
	Debris:AddItem(sound, LIFETIME)
end

function Ambience.cue(name: string)
	local cue = AmbienceConfig.cues[name]
	if cue then
		Ambience.ui(cue)
	end
end

return Ambience
