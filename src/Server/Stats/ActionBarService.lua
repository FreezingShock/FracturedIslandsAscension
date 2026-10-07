--[[
	ActionBarService (ModuleScript, Server)
	Place inside: ServerScriptService

	Feeds the action bar (the centered line above the hotbar, ActionBarClient). Server-authoritative: the client only draws.
	Remote "ActionBar" (RemoteEvent, server -> client) carries one of:
	  { kind = "xp", skill, gain, pct, level, leveledUp }     skill XP (pct = 0-1 of the current level; level = the level now)
	  { kind = "text", text, hold?, color? }                  anything else (rich text allowed)

	  ActionBarService.xp(player, skill, gain, pct, level, leveledUp)   called by SkillsDataManager.AddXP; gains of one skill
	                                                                    that arrive within FLUSH seconds are summed into ONE message
	  ActionBarService.show(player, text, opts?)                        opts = { hold = seconds }; shown for 5s by default
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionBarService = {}

local FLUSH = 0.15
local MAX_TEXT = 200

local remote = ReplicatedStorage:FindFirstChild("ActionBar")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "ActionBar"
	remote.Parent = ReplicatedStorage
end

local pendingXp: { [Player]: { [string]: any } } = {}

function ActionBarService.xp(player: Player, skill: string, gain: number, pct: number, level: number, leveledUp: boolean)
	if typeof(player) ~= "Instance" or type(skill) ~= "string" or type(gain) ~= "number" or gain ~= gain or gain <= 0 then
		return
	end
	local bySkill = pendingXp[player]
	if not bySkill then
		bySkill = {}
		pendingXp[player] = bySkill
	end
	local entry = bySkill[skill]
	if not entry then
		entry = { kind = "xp", skill = skill, gain = 0, pct = 0, level = level, leveledUp = false }
		bySkill[skill] = entry
	end
	entry.gain += gain
	entry.pct = pct
	entry.level = level
	entry.leveledUp = entry.leveledUp or leveledUp == true
end

function ActionBarService.show(player: Player, text: string, opts: any?)
	if typeof(player) ~= "Instance" or type(text) ~= "string" or #text == 0 then
		return
	end
	remote:FireClient(player, {
		kind = "text",
		text = text:sub(1, MAX_TEXT),
		hold = opts and type(opts.hold) == "number" and opts.hold or nil,
	})
end

task.spawn(function()
	while true do
		task.wait(FLUSH)
		for player, bySkill in pairs(pendingXp) do
			pendingXp[player] = nil
			if player.Parent == Players then
				for _, entry in pairs(bySkill) do
					remote:FireClient(player, entry)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	pendingXp[player] = nil
end)

return ActionBarService
