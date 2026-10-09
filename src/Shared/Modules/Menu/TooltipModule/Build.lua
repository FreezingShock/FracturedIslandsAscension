--[[
	TooltipModule/Build (ModuleScript)

	Helpers that turn game data into tooltip config pieces, so callers stop hand-writing rich-text markup:

	  Build.stat(attribute, amount, opts?)   -> a Stats row { name, value, color, icon }  (name / colour / icon from Style.statInfo)
	  Build.rewardList(rewards)               -> Stats rows of { { stat = "Health", amount = 5 }, ... }  (value "+5" in the stat's colour)
	  Build.progress(pct, label, opts?)       -> the progress bar spec { pct, label, color, animate }
	  Build.tag(text, color)                  -> a tag badge { text, color }
	  Build.row(name, value, color, icon?)    -> a plain Stats row (a label that is not a game attribute)

	  Tooltip.show({ title = "Level 7", stats = Build.rewardList(rewards), progress = Build.progress(0.69, "69 / 100 XP") }, "source", anchor)
]]

local Style = require(script.Parent:WaitForChild("Style"))

local Build = {}

function Build.stat(attribute: string, amount: number, opts: any?)
	local info = Style.statInfo(attribute)
	local sign = amount >= 0 and "+" or ""
	local o = opts or {}
	return {
		name = o.name or info.name,
		value = (o.prefix or sign) .. tostring(amount) .. (o.suffix or ""),
		color = o.color or info.color,
		valueColor = o.valueColor,
		icon = o.icon or info.icon,
	}
end

function Build.rewardList(rewards: { any }): { any }
	local rows = {}
	for _, reward in ipairs(rewards) do
		table.insert(rows, Build.stat(reward.stat, reward.amount))
	end
	return rows
end

function Build.row(name: string, value: any, color: string?, icon: any?)
	return { name = name, value = tostring(value), color = color or "#FFFFFF", icon = icon }
end

function Build.progress(pct: number, label: string, opts: any?)
	local o = opts or {}
	return { pct = math.clamp(pct or 0, 0, 1), label = label, color = o.color, animate = o.animate ~= false }
end

function Build.tag(text: string, color: string?)
	return { text = text, color = color or "#FFFFFF" }
end

return Build
