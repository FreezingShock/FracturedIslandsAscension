--[[
	CollectionRewards (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Registry of collection reward TYPES. A reward in CollectionsConfig is { type = "statGain", ... }; this module knows
	how to show it (client + server) and the server module CollectionService adds how to apply it.

	  CollectionRewards.register(typeName, {
	      kind     = "derived" | "grant",
	      describe = function(reward, ctx) -> { short = "+5%", text = "<rich text line>", name = "plain", icon = "rbxassetid://...", color = "#55FF55" },
	      derive   = function(reward, ctx, acc)   SERVER, kind "derived": add to the accumulator, never touch saved data.
	      apply    = function(reward, ctx)        SERVER, kind "grant": runs ONCE when the tier is first reached.
	  })
	  register merges into an existing entry, so the server can add derive/apply to a type the client already describes.

	  "derived" rewards (permanent buffs) are rebuilt from the saved claimedTier every time they change, so they can
	  never double-count. "grant" rewards (items, recipes) are given exactly once because claimedTier is a high-water mark.

	  ctx for describe = { skill = <collected skill>, key = <collected stat>, tier = n }; the Skills system passes { skill = <skill>, level = n }.
	  New reward type = one register() call. The reward page and the tooltips only call describe(), so they need no change.

	  CollectionRewards.describe(reward, ctx) -> the table above (never nil)
	  CollectionRewards.get(typeName)         the registered spec or nil
--]]

local Config = require(script.Parent:WaitForChild("CollectionsConfig")) :: any
local Attributes = require(script.Parent:WaitForChild("Attributes")) :: any

local CollectionRewards = {}
local types: { [string]: any } = {}

function CollectionRewards.register(typeName: string, spec: any)
	local existing = types[typeName] or {}
	for field, value in pairs(spec) do
		existing[field] = value
	end
	types[typeName] = existing
end

function CollectionRewards.get(typeName: string)
	return types[typeName]
end

local FALLBACK =
	{ short = "?", text = '<font color="#AAAAAA">Unknown reward</font>', name = "Unknown", color = "#AAAAAA" }

function CollectionRewards.describe(reward: any, ctx: any)
	local spec = type(reward) == "table" and types[reward.type]
	if not (spec and spec.describe) then
		return FALLBACK
	end
	local ok, result = pcall(spec.describe, reward, ctx or {})
	return ok and result or FALLBACK
end

-- ===================== HELPERS =====================
local function statInfo(skill: string?, key: string?)
	local config = skill and key and Config.statConfigLookup[skill] and Config.statConfigLookup[skill][key]
	return config
end

local function gainDescription(reward: any, skill: string?, key: string?)
	local config = statInfo(skill, key)
	local name = config and config.name or tostring(key)
	local color = config and config.color or "#FFFFFF"
	return {
		short = string.format("+%d%%", reward.pct or 0),
		text = string.format(
			'<font color="#55FF55">+%d%%</font> <font color="%s">%s</font> gain',
			reward.pct or 0,
			color,
			name
		),
		name = name .. " gain",
		icon = config and config.icon or "",
		color = "#55FF55",
	}
end

-- ===================== BUILT-IN TYPES =====================
CollectionRewards.register("statGain", {
	kind = "derived",
	-- the collected statistic itself, unless the entry names another one
	target = function(reward, ctx)
		return reward.skill or ctx.skill, reward.key or ctx.key
	end,
	describe = function(reward, ctx)
		return gainDescription(reward, reward.skill or ctx.skill, reward.key or ctx.key)
	end,
})

CollectionRewards.register("crossStatGain", {
	kind = "derived",
	target = function(reward, ctx)
		return reward.skill, reward.key
	end,
	describe = function(reward, ctx)
		return gainDescription(reward, reward.skill, reward.key)
	end,
})

CollectionRewards.register("gameStat", {
	kind = "derived",
	describe = function(reward, ctx)
		local def = Attributes.get(reward.attr)
		local name = def and def.name or tostring(reward.attr)
		local color = def and def.color or "#FFFFFF"
		local amount = reward.flat and string.format("+%s", tostring(reward.flat))
			or string.format("+%s%%", tostring(reward.pct or 0))
		return {
			short = amount,
			text = string.format('<font color="#55FF55">%s</font> <font color="%s">%s</font>', amount, color, name),
			name = name,
			icon = def and def.icon or "",
			color = color,
		}
	end,
})

CollectionRewards.register("item", {
	kind = "grant",
	describe = function(reward, ctx)
		local count = reward.count or 1
		return {
			short = "x" .. count,
			text = string.format('<font color="#FFAA00">%dx %s</font>', count, tostring(reward.tool)),
			name = tostring(reward.tool),
			icon = reward.icon or "",
			color = "#FFAA00",
		}
	end,
})

CollectionRewards.register("recipe", {
	kind = "grant",
	describe = function(reward, ctx)
		return {
			short = "Recipe",
			text = string.format('<font color="#FF55FF">Recipe: %s</font>', tostring(reward.id)),
			name = "Recipe " .. tostring(reward.id),
			icon = reward.icon or "",
			color = "#FF55FF",
		}
	end,
})

CollectionRewards.register("statGrant", {
	kind = "grant",
	describe = function(reward, ctx)
		local config = statInfo(reward.skill, reward.key)
		local name = config and config.name or tostring(reward.key)
		local color = config and config.color or "#FFFFFF"
		local amount = tostring(reward.amount or 0)
		return {
			short = "+" .. amount,
			text = string.format('<font color="#55FF55">+%s</font> <font color="%s">%s</font>', amount, color, name),
			name = name,
			icon = config and config.icon or "",
			color = color,
		}
	end,
})

-- A feature or title the old UI promised: recorded in the profile (unlocks[id] = true), behaviour comes later.
CollectionRewards.register("unlock", {
	kind = "grant",
	describe = function(reward, ctx)
		local color = reward.color or "#FFD700"
		return {
			short = "Unlock",
			text = string.format('<font color="%s">%s</font>', color, tostring(reward.label or reward.id)),
			name = tostring(reward.label or reward.id),
			icon = reward.icon or "",
			color = color,
		}
	end,
})

return CollectionRewards
