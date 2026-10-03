--[[
	VisibilityChecker.lua — GlassHandler (Merged)

	Single-pass ancestor walk returning visibility + accumulated GroupTransparency.
	CaptureService suppression: when suppressOnCapture is true and a screenshot
	is in progress, check() returns false — used by liquid glass mode only.
]]

local VisibilityChecker = {}
local GuiService = game:GetService("GuiService")
local CaptureService = game:GetService("CaptureService")

-- ── CaptureService state ──────────────────────────────────────────────────────
local capturing = false
CaptureService.CaptureBegan:Connect(function()
	capturing = true
end)
CaptureService.CaptureEnded:Connect(function()
	capturing = false
end)

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function areAncestorsVisible(guiObject): boolean
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

local function computeAbsoluteTransparency(guiObject): number
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

-- ── PUBLIC: combined check ────────────────────────────────────────────────────
-- suppressOnCapture: when true, returns false during active screenshot capture.
-- Liquid glass passes true; mosaic glass passes false (or nil).
--
-- Returns (isVisible: boolean, absTransparency: number).
function VisibilityChecker.check(guiObject: GuiObject, suppressOnCapture: boolean?): (boolean, number)
	if not guiObject or not guiObject.Parent then
		return false, 1
	end
	if suppressOnCapture and capturing then
		return false, 1
	end
	if not areAncestorsVisible(guiObject) then
		return false, 1
	end
	local absT = computeAbsoluteTransparency(guiObject)
	if absT >= 0.999 then
		return false, 1
	end
	return true, absT
end

-- ── PUBLIC: legacy wrappers ───────────────────────────────────────────────────

function VisibilityChecker.isPotentiallyVisible(guiObject: GuiObject): boolean
	local visible, _ = VisibilityChecker.check(guiObject, false)
	return visible
end

function VisibilityChecker.getAbsoluteTransparency(guiObject: GuiObject): number
	return computeAbsoluteTransparency(guiObject)
end

-- ── PUBLIC: clipped render bounds ─────────────────────────────────────────────
-- Returns the actually-visible screen rect after walking ClipsDescendants ancestors.
-- Returns: { Min, Max, Width, Height, IsFullyClipped }
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
