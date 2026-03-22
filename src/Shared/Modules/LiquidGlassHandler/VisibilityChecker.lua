--[[
	VisibilityChecker.lua — LiquidGlassHandler 2.1

	Improvements over 1.0:
	  • check() performs a single ancestor walk returning both visibility state
	    and accumulated GroupTransparency simultaneously. Eliminates the double
	    traversal (isPotentiallyVisible + getAbsoluteTransparency) that ran every
	    RenderStepped frame per instance.
	  • GroupTransparency early-exit: if a CanvasGroup has faded the element to
	    effectively zero opacity, we bail before any world-space math runs.
	  • Legacy public functions preserved for backward compatibility.
]]

local VisibilityChecker = {}
local GuiService = game:GetService("GuiService")

-- ── Internal: Visible / Enabled flag walk ────────────────────────────────────
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

-- ── Internal: GroupTransparency accumulation ──────────────────────────────────
-- Returns absTransparency in [0,1] where 1 = fully invisible.
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

-- ── PUBLIC: single-pass combined check ───────────────────────────────────────
-- Use this in RenderStepped.  Returns (isVisible: boolean, absTransparency: number).
--
-- Exit order:
--   1. nil / unparented → false, 1
--   2. Any ancestor Visible=false or ScreenGui Enabled=false → false, 1
--   3. Accumulated GroupTransparency ≥ 0.999 → false, 1  (skips all render work)
--   4. Otherwise → true, absTransparency
function VisibilityChecker.check(guiObject: GuiObject): (boolean, number)
	if not guiObject or not guiObject.Parent then
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

-- ── PUBLIC: legacy wrappers (backward compat) ─────────────────────────────────
function VisibilityChecker.isPotentiallyVisible(guiObject: GuiObject): boolean
	local visible, _ = VisibilityChecker.check(guiObject)
	return visible
end

function VisibilityChecker.getAbsoluteTransparency(guiObject: GuiObject): number
	return computeAbsoluteTransparency(guiObject)
end

-- ── PUBLIC: clipped render bounds ─────────────────────────────────────────────
-- Returns the actually-visible screen rect after walking ClipsDescendants ancestors.
-- Skips clip walk when the element has non-zero AbsoluteRotation (clip math is
-- non-trivial for rotated elements).
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
