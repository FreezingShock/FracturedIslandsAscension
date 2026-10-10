--[[
	LevelBadge (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Util

	The one place that paints a level badge: the "LV n" hexagon-ish pill the nameplate shows over every enemy and player,
	and the same pill the chat puts before each player's name. The badge itself is the hand-made template LevelBadge inside
	ReplicatedStorage.GUI.EnemyNameplate (restyle it in Studio: both places follow). This module only fills it in.

	  LevelBadge.text(level)              "LV 10"
	  LevelBadge.paint(badge, row, tween) gradient, stroke and text colour from a tint row ({ top, bottom, stroke, text })
	                                      tween(instance, property, value) is optional: the nameplate passes its tween helper
	                                      so the stroke and text colour ease; the gradient cannot be tweened, it is set at once.
--]]

local LevelBadge = {}

function LevelBadge.text(level: number): string
	return "LV " .. tostring(math.floor(level))
end

function LevelBadge.paint(badge: Instance, row: any, tween: ((Instance, string, any) -> ())?)
	local set = tween or function(instance: Instance, property: string, value: any)
		(instance :: any)[property] = value
	end
	local gradient = badge:FindFirstChild("BadgeGradient")
	if gradient and gradient:IsA("UIGradient") then
		gradient.Color = ColorSequence.new(Color3.fromHex(row.top), Color3.fromHex(row.bottom)) -- a ColorSequence cannot be tweened
	end
	local stroke = badge:FindFirstChild("BadgeStroke")
	if stroke and stroke:IsA("UIStroke") then
		set(stroke, "Color", Color3.fromHex(row.stroke))
	end
	local label = badge:FindFirstChild("LevelLabel")
	if label and label:IsA("TextLabel") then
		set(label, "TextColor3", Color3.fromHex(row.text))
	end
end

return LevelBadge
