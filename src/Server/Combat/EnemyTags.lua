--[[
	EnemyTags (ModuleScript, Server)
	Place inside: ServerScriptService

	The tag chips under an enemy's nameplate (element, debuffs, active effects; ids and looks are NameplateConfig.tags). The
	server owns them: each tag is one model attribute  Tag_<id> = "stacks|expiry"  (expiry = workspace:GetServerTimeNow() when
	it ends, 0 = permanent), so every client sees and times it the same and nothing is sent by a client.

	  EnemyTags.add(model, id, { duration = seconds (nil = permanent), stacks = 1 })   adds or refreshes a tag (keeps the longer end)
	  EnemyTags.remove(model, id)
	  EnemyTags.clear(model)                      removes every tag that is not permanent
	  EnemyTags.stamp(model, entry)               permanent tags from EnemyConfig.enemies.<key>.tags (called at spawn)

	An expired tag removes itself; the client also hides a chip whose time has run out.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NameplateConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("NameplateConfig")) :: any

local PREFIX = "Tag_"

local EnemyTags = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

function EnemyTags.add(model: Instance, id: string, options: { duration: number?, stacks: number? }?)
	if not (model and model.Parent) or not NameplateConfig.tags[id] then
		return
	end
	local duration = options and options.duration
	local stacks = math.max(1, math.floor(options and options.stacks or 1))
	local expiry = duration and (now() + duration) or 0
	local attribute = PREFIX .. id
	local existing = model:GetAttribute(attribute)
	if type(existing) == "string" then
		local _, oldExpiry = string.match(existing, "^(%d+)|([%d%.]+)$")
		oldExpiry = tonumber(oldExpiry)
		if oldExpiry == 0 or (oldExpiry and expiry ~= 0 and oldExpiry > expiry) then
			expiry = oldExpiry :: number
		end
	end
	model:SetAttribute(attribute, ("%d|%.2f"):format(stacks, expiry))
	if expiry > 0 then
		task.delay(expiry - now() + 0.05, function()
			local value = model.Parent and model:GetAttribute(attribute)
			if type(value) == "string" then
				local _, current = string.match(value, "^(%d+)|([%d%.]+)$")
				current = tonumber(current)
				if current and current > 0 and current <= now() then
					model:SetAttribute(attribute, nil)
				end
			end
		end)
	end
end

function EnemyTags.remove(model: Instance, id: string)
	if model then
		model:SetAttribute(PREFIX .. id, nil)
	end
end

function EnemyTags.clear(model: Instance)
	for name, value in pairs(model:GetAttributes()) do
		if string.sub(name, 1, #PREFIX) == PREFIX and type(value) == "string" and not string.find(value, "|0.00", 1, true) then
			model:SetAttribute(name, nil)
		end
	end
end

function EnemyTags.stamp(model: Instance, entry: any)
	for _, id in ipairs(entry and entry.tags or {}) do
		EnemyTags.add(model, id)
	end
end

return EnemyTags
