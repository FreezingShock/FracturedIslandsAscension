local VisibilityChecker = {}
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")

local function areAncestorsVisible(guiObject)
	local current = guiObject
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("ScreenGui") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

function VisibilityChecker.isPotentiallyVisible(guiObject)
	if not guiObject or not guiObject.Parent then
		return false
	end
	return areAncestorsVisible(guiObject)
end

function VisibilityChecker.getAbsoluteTransparency(guiObject)
	local current = guiObject
	local combinedOpacity = 1
	while current do
		if current:IsA("CanvasGroup") then
			combinedOpacity = combinedOpacity * (1 - current.GroupTransparency)
		end
		current = current.Parent
	end
	return math.round((1 - combinedOpacity) * 1000) / 1000
end

function VisibilityChecker.getTrueRenderBounds(guiObject: GuiObject)
	local absPos = guiObject.AbsolutePosition
	local absSize = guiObject.AbsoluteSize
	local absRot = guiObject.AbsoluteRotation

	local minX, minY = absPos.X, absPos.Y
	local maxX, maxY = absPos.X + absSize.X, absPos.Y + absSize.Y

	if absRot == 0 then
		local current = guiObject.Parent
		while current and current:IsA("GuiObject") do
			if current.AbsoluteRotation ~= 0 then
				break
			end
			if current.ClipsDescendants then
				local cPos = current.AbsolutePosition
				local cSize = current.AbsoluteSize
				minX = math.max(minX, cPos.X)
				minY = math.max(minY, cPos.Y)
				maxX = math.min(maxX, cPos.X + cSize.X)
				maxY = math.min(maxY, cPos.Y + cSize.Y)
			end
			current = current.Parent
		end
	end

	local width = math.max(0, maxX - minX)
	local height = math.max(0, maxY - minY)

	return {
		Min = Vector2.new(minX, minY),
		Max = Vector2.new(maxX, maxY),
		Width = width,
		Height = height,
		IsFullyClipped = (width <= 0 or height <= 0),
	}
end

return VisibilityChecker
