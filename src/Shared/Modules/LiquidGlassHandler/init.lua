--[[
	LiquidGlassHandler 1.0
	Copyright (c) 2026 @7eoeb, @UNIVERSECORNUCOPIA

	All rights reserved.

	This code and its associated assets are the intellectual property of @7eoeb
	and @UNIVERSECORNUCOPIA. Unauthorized copying, modification, distribution,
	or use of this code, in whole or in part, without explicit permission is
	strictly prohibited.

	Created: 2026

	Extended with programmatic API for per-instance application,
	setting overrides, enable/disable toggling, and batch operations.
]]

local LiquidGlassHandler = {}
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")

if not RunService:IsStudio() then
	print(require(script.Version))
end

local VisibilityChecker = require(script.VisibilityChecker)
local DefaultSettings = require(script.Settings)

local tag = DefaultSettings.Tag
local templateContainer = script.Overlay

local parentFolder = Instance.new("Folder")
parentFolder.Name = "LiquidGlassObjects"
parentFolder.Parent = workspace

local rotationOffset = CFrame.Angles(0, math.rad(-90), 0)

-- ===================== INSTANCE REGISTRY =====================
-- guiObject → { handle, container, renderName, settings }
local activeInstances = {}

-- ===================== SETTINGS MERGE =====================

--- Deep-merge overrides into a copy of DefaultSettings.
--- Only merges Highlight, Mesh, Padding, and Depth — Tag is always global.
local function mergeSettings(overrides)
	if not overrides then
		return DefaultSettings
	end

	local merged = {
		Tag = DefaultSettings.Tag,
		Padding = if overrides.Padding ~= nil then overrides.Padding else DefaultSettings.Padding,
		Depth = if overrides.Depth ~= nil then overrides.Depth else (DefaultSettings.Depth or 2),
	}

	-- Deep-merge Highlight
	merged.Highlight = {}
	for k, v in pairs(DefaultSettings.Highlight) do
		merged.Highlight[k] = v
	end
	if overrides.Highlight then
		for k, v in pairs(overrides.Highlight) do
			merged.Highlight[k] = v
		end
	end

	-- Deep-merge Mesh
	merged.Mesh = {}
	for k, v in pairs(DefaultSettings.Mesh) do
		merged.Mesh[k] = v
	end
	if overrides.Mesh then
		for k, v in pairs(overrides.Mesh) do
			merged.Mesh[k] = v
		end
	end

	return merged
end

-- ===================== HIGHLIGHT FACTORY =====================

local function createHighlight(instanceSettings)
	local h = Instance.new("Highlight")
	for k, v in pairs(instanceSettings.Highlight) do
		h[k] = v
	end
	return h
end

-- ===================== CORE INSTANCE CREATION =====================

local function createGlassInstance(guiObject, overrides)
	if not guiObject:IsDescendantOf(Players.LocalPlayer) then
		return nil
	end

	-- Prevent duplicates — return existing handle
	if activeInstances[guiObject] then
		return activeInstances[guiObject].handle
	end

	local instanceSettings = mergeSettings(overrides)
	local renderName = `LiquidGlass_{HttpService:GenerateGUID(false)}`

	local container = Instance.new("Model")
	container.Name = renderName
	container.Parent = parentFolder

	local highlight = createHighlight(instanceSettings)
	highlight.Parent = container

	local pixels = {}
	local lastSize = Vector2.zero
	local lastRadius = -1
	local currentLayoutMode = "None"
	local depth = instanceSettings.Depth or 2
	local localPadding = instanceSettings.Padding
	local enabled = true
	local destroyed = false

	local function getCornerRadius()
		local currentSize = guiObject.AbsoluteSize
		local uiCorner = guiObject:FindFirstChildWhichIsA("UICorner")
		local radius = uiCorner
				and (uiCorner.CornerRadius.Offset + (uiCorner.CornerRadius.Scale * math.min(
					currentSize.X,
					currentSize.Y
				)))
			or 0
		local maxPossibleRadius = math.min(currentSize.X, currentSize.Y) / 2
		radius = math.clamp(radius, 0, maxPossibleRadius)
		return radius
	end

	local function rebuildGrid()
		local currentSize = guiObject.AbsoluteSize
		if currentSize.X < 1 or currentSize.Y < 1 then
			return
		end

		local radius = getCornerRadius()

		if currentSize == lastSize and radius == lastRadius then
			return
		end
		lastSize = currentSize
		lastRadius = radius

		local targetMode = (radius <= 0) and "Flat" or "Rounded"
		local needsRebuild = (targetMode ~= currentLayoutMode)

		if needsRebuild then
			for _, data in pairs(pixels) do
				data.Part:Destroy()
			end
			table.clear(pixels)
			currentLayoutMode = targetMode
		end

		local partIndex = 1
		local function updateOrAddPart(templateName, relX, relY, relSizeX, relSizeY, localRot, swapAxes)
			if needsRebuild then
				local template = templateContainer:FindFirstChild(templateName)
				if not template then
					warn("[LiquidGlass] Missing overlay template: " .. templateName)
					return
				end
				local p = template:Clone()
				p.Parent = container
				table.insert(pixels, {
					Part = p,
					RelX = relX,
					RelY = relY,
					RelSizeX = relSizeX,
					RelSizeY = relSizeY,
					LocalRot = localRot or CFrame.new(),
					SwapAxes = swapAxes or false,
				})
			else
				local data = pixels[partIndex]
				data.RelX = relX
				data.RelY = relY
				data.RelSizeX = relSizeX
				data.RelSizeY = relSizeY
				data.LocalRot = localRot or CFrame.new()
				data.SwapAxes = swapAxes or false
			end
			partIndex += 1
		end

		if radius <= 0 then
			updateOrAddPart("Center", 0, 0, 1, 1)
		else
			local relRadX = radius / currentSize.X
			local relRadY = radius / currentSize.Y
			local innerW = (currentSize.X - 2 * radius) / currentSize.X
			local innerH = (currentSize.Y - 2 * radius) / currentSize.Y
			local diamX = relRadX
			local diamY = relRadY

			updateOrAddPart("Center", 0, 0, innerW, innerH)

			updateOrAddPart("Edge", 0, -0.5 + (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, 0))
			updateOrAddPart("Edge", 0, 0.5 - (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, math.rad(180)))

			updateOrAddPart("Edge", -0.5 + (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(90)), true)
			updateOrAddPart("Edge", 0.5 - (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(-90)), true)

			local halfDiamX = diamX / 2
			local halfDiamY = diamY / 2

			updateOrAddPart(
				"Corner",
				-0.5 + halfDiamX,
				-0.5 + halfDiamY,
				diamX,
				diamY,
				CFrame.Angles(0, 0, math.rad(90)),
				true
			)
			updateOrAddPart("Corner", 0.5 - halfDiamX, -0.5 + halfDiamY, diamX, diamY, CFrame.Angles(0, 0, 0))
			updateOrAddPart(
				"Corner",
				-0.5 + halfDiamX,
				0.5 - halfDiamY,
				diamX,
				diamY,
				CFrame.Angles(0, 0, math.rad(180))
			)
			updateOrAddPart(
				"Corner",
				0.5 - halfDiamX,
				0.5 - halfDiamY,
				diamX,
				diamY,
				CFrame.Angles(0, 0, math.rad(-90)),
				true
			)
		end
	end

	rebuildGrid()

	RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function()
		if not enabled then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		if guiObject.AbsoluteSize ~= lastSize or getCornerRadius() ~= lastRadius then
			rebuildGrid()
		end

		local isVisible = VisibilityChecker.isPotentiallyVisible(guiObject)
		container.Parent = isVisible and parentFolder or nil
		if not isVisible then
			return
		end

		local visibleRect = VisibilityChecker.getTrueRenderBounds(guiObject)
		local visibleSize = Vector2.new(visibleRect.Width, visibleRect.Height)

		if visibleSize.X <= 0 or visibleSize.Y <= 0 then
			container.Parent = nil
			return
		else
			container.Parent = parentFolder
		end

		local inset, _ = GuiService:GetGuiInset()
		local centerScreenPos = visibleRect.Min + (visibleSize / 2) + inset

		local function getPlanePos(pixelX, pixelY)
			local ray = camera:ViewportPointToRay(pixelX, pixelY)
			local dist = depth / ray.Direction:Dot(camera:GetRenderCFrame().LookVector)
			return ray.Origin + ray.Direction * dist
		end

		local centerWorldPos = getPlanePos(centerScreenPos.X, centerScreenPos.Y)
		local rightEdge = getPlanePos(centerScreenPos.X + (visibleSize.X / 2), centerScreenPos.Y)
		local leftEdge = getPlanePos(centerScreenPos.X - (visibleSize.X / 2), centerScreenPos.Y)
		local topEdge = getPlanePos(centerScreenPos.X, centerScreenPos.Y - (visibleSize.Y / 2))
		local bottomEdge = getPlanePos(centerScreenPos.X, centerScreenPos.Y + (visibleSize.Y / 2))

		local worldW = (rightEdge - leftEdge).Magnitude
		local worldH = (topEdge - bottomEdge).Magnitude

		local camCF = camera:GetRenderCFrame()
		local guiRotCF = CFrame.Angles(0, 0, math.rad(-guiObject.AbsoluteRotation))

		local absTransparency = VisibilityChecker.getAbsoluteTransparency(guiObject)

		local baseFillT = instanceSettings.Highlight.FillTransparency
		local baseMeshT = instanceSettings.Mesh.Transparency

		for _, data in ipairs(pixels) do
			local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
			local rotatedOffset = guiRotCF * localOffset

			local worldOffset = (camCF.RightVector * rotatedOffset.X) + (camCF.UpVector * rotatedOffset.Y)

			if data.SwapAxes then
				data.Part.Size =
					Vector3.new(0.01, data.RelSizeX * worldW + localPadding, data.RelSizeY * worldH + localPadding)
			else
				data.Part.Size =
					Vector3.new(0.01, data.RelSizeY * worldH + localPadding, data.RelSizeX * worldW + localPadding)
			end

			highlight.FillTransparency = baseFillT + (1 - baseFillT) * absTransparency
			data.Part.Transparency = baseMeshT + (1 - baseMeshT) * absTransparency

			data.Part.CFrame = CFrame.new(centerWorldPos + worldOffset)
				* camCF.Rotation
				* guiRotCF
				* data.LocalRot
				* rotationOffset
		end
	end)

	-- ── Cleanup ──

	local function cleanup()
		if destroyed then
			return 0
		end
		destroyed = true
		activeInstances[guiObject] = nil
		container:Destroy()
		RunService:UnbindFromRenderStep(renderName)
		return 1
	end

	guiObject.AncestryChanged:Connect(function(_, n)
		if n then
			return
		end
		cleanup()
	end)

	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
		if v ~= guiObject then
			return
		end
		cleanup()
	end)

	-- ── Handle (returned to caller) ──

	local handle = {}

	--- Destroy this glass instance permanently.
	function handle.destroy()
		return cleanup()
	end

	--- Toggle rendering on/off without destroying. Useful for menu open/close.
	function handle.setEnabled(state: boolean)
		enabled = state
		if not state then
			container.Parent = nil
		end
	end

	--- Check if this instance is currently enabled.
	function handle.isEnabled(): boolean
		return enabled
	end

	--- Hot-swap settings on this instance (merged with defaults).
	--- Forces a grid rebuild on the next frame.
	function handle.updateSettings(newOverrides)
		instanceSettings = mergeSettings(newOverrides)
		localPadding = instanceSettings.Padding
		depth = instanceSettings.Depth or 2

		-- Update highlight properties immediately
		for k, v in pairs(instanceSettings.Highlight) do
			pcall(function()
				highlight[k] = v
			end)
		end

		-- Invalidate cached size/radius to force rebuild
		lastSize = Vector2.zero
		lastRadius = -1
	end

	-- ── Register ──

	activeInstances[guiObject] = {
		handle = handle,
		container = container,
		renderName = renderName,
		settings = instanceSettings,
	}

	return handle
end

-- =====================================================================
--  PUBLIC API
-- =====================================================================

--- Original constructor — kept for backward compat with CollectionService.
function LiquidGlassHandler.new(guiObject: GuiObject)
	return createGlassInstance(guiObject, nil)
end

--- Apply glass to a GuiObject programmatically.
--- @param guiObject  The GUI element to frost.
--- @param overrides  Optional table matching Settings shape for per-instance tuning.
---                   Example: { Depth = 3, Mesh = { Transparency = 2.5 }, Highlight = { FillTransparency = 0.85 } }
--- @return handle    Table with :destroy(), :setEnabled(bool), :isEnabled(), :updateSettings(overrides)
---                   Returns existing handle if already applied (no duplicate).
function LiquidGlassHandler.apply(guiObject: GuiObject, overrides: { [string]: any }?)
	return createGlassInstance(guiObject, overrides)
end

--- Remove glass from a specific GuiObject. Returns true if found and removed.
function LiquidGlassHandler.remove(guiObject: GuiObject): boolean
	local instance = activeInstances[guiObject]
	if not instance then
		return false
	end
	instance.handle.destroy()
	return true
end

--- Toggle glass rendering without destroying. No-op if not applied.
function LiquidGlassHandler.setEnabled(guiObject: GuiObject, state: boolean)
	local instance = activeInstances[guiObject]
	if not instance then
		return
	end
	instance.handle.setEnabled(state)
end

--- Check if a GuiObject currently has glass applied.
function LiquidGlassHandler.has(guiObject: GuiObject): boolean
	return activeInstances[guiObject] ~= nil
end

--- Get the handle for a specific GuiObject (nil if not applied).
function LiquidGlassHandler.get(guiObject: GuiObject)
	local instance = activeInstances[guiObject]
	return instance and instance.handle or nil
end

--- Apply glass to multiple GuiObjects at once. Returns array of handles.
function LiquidGlassHandler.applyBatch(guiObjects: { GuiObject }, overrides: { [string]: any }?)
	local handles = {}
	for _, obj in ipairs(guiObjects) do
		local h = createGlassInstance(obj, overrides)
		if h then
			table.insert(handles, h)
		end
	end
	return handles
end

--- Remove all active glass instances.
function LiquidGlassHandler.removeAll()
	-- Snapshot keys to avoid mutation-during-iteration
	local objects = {}
	for guiObject in pairs(activeInstances) do
		table.insert(objects, guiObject)
	end
	for _, guiObject in ipairs(objects) do
		LiquidGlassHandler.remove(guiObject)
	end
end

--- Get count of active glass instances.
function LiquidGlassHandler.getActiveCount(): number
	local count = 0
	for _ in pairs(activeInstances) do
		count += 1
	end
	return count
end

-- ===================== COLLECTION SERVICE AUTO-APPLY =====================
CollectionService:GetInstanceAddedSignal(tag):Connect(LiquidGlassHandler.new)
for _, v in ipairs(CollectionService:GetTagged(tag)) do
	LiquidGlassHandler.new(v)
end

return LiquidGlassHandler
