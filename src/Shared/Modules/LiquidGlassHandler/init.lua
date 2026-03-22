--[[
	LiquidGlassHandler 3.1
	Copyright (c) 2026 @7eoeb, @UNIVERSECORNUCOPIA

	CHANGES FROM 3.0:

	① SEAM FIX — ForceFlat mode
	  Root cause: the 9-part rounded-corner grid (center + 4 edges + 4 corners)
	  creates visible line artifacts where parts meet:
	    a) Highlight.OutlineColor traces each disconnected part cluster separately,
	       drawing internal borders where parts have sub-pixel gaps.
	    b) Glass material refraction computes per-part — where two Glass parts
	       overlap, refraction stacks creating a darker band; where they gap,
	       the background bleeds through.
	    c) With two overlapping glass instances (e.g. inventory over Nexus menu),
	       the artifacts multiply: 4 layers × 9 parts = 36 potential seam sources.

	  Fix: Settings.ForceFlat = true (default). When active, buildLayerGrid()
	  always takes the single-Center-part path regardless of UICorner presence.
	  Result: 1 part per layer, 2 parts total, zero internal seams.

	  The frosted glass effect is subtle enough that the glass having square
	  corners while the GuiObject has rounded corners is unnoticeable.

	② ALL HIGHLIGHT OUTLINES DISABLED
	  Both layers now have outlineTransparency = 1 in Settings. The UIStroke
	  added in 3.0 provides the specular rim — the Highlight outline was
	  redundant and was the primary source of the nested-rectangle artifacts
	  visible when two glass instances overlap.
]]

local LiquidGlassHandler = {}
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local VisibilityChecker = require(script.VisibilityChecker)
local DefaultSettings = require(script.Settings)

local tag = DefaultSettings.Tag
local templateContainer = script.Overlay

local parentFolder = Instance.new("Folder")
parentFolder.Name = "LiquidGlassObjects"
parentFolder.Parent = workspace

local rotationOffset = CFrame.Angles(0, math.rad(-90), 0)

local activeInstances = {}

-- ── Settings merge ────────────────────────────────────────────────────────────
local function mergeSettings(overrides)
	if not overrides then
		return DefaultSettings
	end

	local merged = {
		Tag = DefaultSettings.Tag,
		Padding = if overrides.Padding ~= nil then overrides.Padding else DefaultSettings.Padding,
		Depth = if overrides.Depth ~= nil then overrides.Depth else (DefaultSettings.Depth or 2),
		ForceFlat = if overrides.ForceFlat ~= nil then overrides.ForceFlat else DefaultSettings.ForceFlat,
	}

	-- Highlight
	merged.Highlight = {}
	for k, v in pairs(DefaultSettings.Highlight) do
		merged.Highlight[k] = v
	end
	if overrides.Highlight then
		for k, v in pairs(overrides.Highlight) do
			merged.Highlight[k] = v
		end
	end

	-- Mesh
	merged.Mesh = {}
	for k, v in pairs(DefaultSettings.Mesh) do
		merged.Mesh[k] = v
	end
	if overrides.Mesh then
		for k, v in pairs(overrides.Mesh) do
			merged.Mesh[k] = v
		end
	end

	-- Layers
	merged.Layers = {}
	for i, layerDef in ipairs(DefaultSettings.Layers) do
		local ml = {}
		for k, v in pairs(layerDef) do
			ml[k] = v
		end
		if overrides.Layers and overrides.Layers[i] then
			for k, v in pairs(overrides.Layers[i]) do
				ml[k] = v
			end
		end
		merged.Layers[i] = ml
	end

	-- Rim
	merged.Rim = {}
	for k, v in pairs(DefaultSettings.Rim) do
		merged.Rim[k] = v
	end
	if overrides.Rim then
		for k, v in pairs(overrides.Rim) do
			merged.Rim[k] = v
		end
	end

	-- Stroke
	merged.Stroke = {}
	for k, v in pairs(DefaultSettings.Stroke) do
		merged.Stroke[k] = v
	end
	if overrides.Stroke then
		for k, v in pairs(overrides.Stroke) do
			merged.Stroke[k] = v
		end
	end

	return merged
end

-- ── Shortest-path angle lerp ──────────────────────────────────────────────────
local function lerpAngle(current: number, target: number, alpha: number): number
	local diff = ((target - current) + 180) % 360 - 180
	return current + diff * alpha
end

-- ── Core instance factory ─────────────────────────────────────────────────────
local function createGlassInstance(guiObject, overrides)
	if not guiObject:IsDescendantOf(Players.LocalPlayer) then
		return nil
	end
	if activeInstances[guiObject] then
		return activeInstances[guiObject].handle
	end

	local instanceSettings = mergeSettings(overrides)
	local forceFlat = instanceSettings.ForceFlat
	local renderName = `LiquidGlass_{HttpService:GenerateGUID(false)}`

	local masterFolder = Instance.new("Folder")
	masterFolder.Name = renderName
	masterFolder.Parent = parentFolder

	-- ── Layer containers ──────────────────────────────────────────────────
	local layerContainers = {}
	for i, layerDef in ipairs(instanceSettings.Layers) do
		local container = Instance.new("Model")
		container.Name = renderName .. "_L" .. i
		container.Parent = masterFolder

		local hl = Instance.new("Highlight")
		hl.FillColor = layerDef.fillColor
		hl.FillTransparency = layerDef.fillTransparency
		hl.OutlineColor = layerDef.outlineColor
		hl.OutlineTransparency = layerDef.outlineTransparency
		hl.Parent = container

		layerContainers[i] = {
			container = container,
			highlight = hl,
			pixels = {},
			depthOffset = layerDef.depthOffset,
			baseFillT = layerDef.fillTransparency,
			baseOutlineT = layerDef.outlineTransparency,
			baseMeshT = layerDef.meshTransparency,
			meshColor = layerDef.meshColor,
		}
	end

	-- ── Geometry state ────────────────────────────────────────────────────
	local lastSize = Vector2.zero
	local lastRadius = -1
	local currentLayoutMode = "None"
	local enabled = true
	local destroyed = false

	local function getCornerRadius(): number
		if forceFlat then
			return 0 -- skip UICorner detection entirely
		end
		local sz = guiObject.AbsoluteSize
		local uiCorner = guiObject:FindFirstChildWhichIsA("UICorner")
		if not uiCorner then
			return 0
		end
		local r = uiCorner.CornerRadius.Offset + uiCorner.CornerRadius.Scale * math.min(sz.X, sz.Y)
		return math.clamp(r, 0, math.min(sz.X, sz.Y) / 2)
	end

	local function makePart(lc, templateName: string)
		local template = templateContainer:FindFirstChild(templateName)
		if not template then
			warn("[LiquidGlass] Missing overlay template: " .. templateName)
			return nil
		end
		local p = template:Clone()
		p.Material = Enum.Material.Glass
		p.Color = lc.meshColor
		p.Transparency = lc.baseMeshT
		p.Anchored = true
		p.CastShadow = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		pcall(function()
			p.AudioCanCollide = false
		end)
		p.Parent = lc.container
		return p
	end

	local function buildLayerGrid(lc, currentSize, needsRebuild, radius)
		local pixels = lc.pixels
		local partIndex = 1

		local function addOrUpdate(name, relX, relY, relSizeX, relSizeY, localRot, swapAxes)
			localRot = localRot or CFrame.new()
			swapAxes = swapAxes or false
			if needsRebuild then
				local p = makePart(lc, name)
				if not p then
					return
				end
				table.insert(pixels, {
					Part = p,
					RelX = relX,
					RelY = relY,
					RelSizeX = relSizeX,
					RelSizeY = relSizeY,
					LocalRot = localRot,
					SwapAxes = swapAxes,
				})
			else
				local data = pixels[partIndex]
				if data then
					data.RelX = relX
					data.RelY = relY
					data.RelSizeX = relSizeX
					data.RelSizeY = relSizeY
					data.LocalRot = localRot
					data.SwapAxes = swapAxes
				end
			end
			partIndex += 1
		end

		-- ForceFlat path OR no UICorner: single Center part per layer.
		-- This eliminates ALL internal seams.
		if radius <= 0 then
			addOrUpdate("Center", 0, 0, 1, 1)
		else
			-- 9-part rounded-corner grid (only used when ForceFlat = false
			-- AND the GuiObject has a UICorner with radius > 0)
			local relRadX = radius / currentSize.X
			local relRadY = radius / currentSize.Y
			local innerW = (currentSize.X - 2 * radius) / currentSize.X
			local innerH = (currentSize.Y - 2 * radius) / currentSize.Y
			local diamX, diamY = relRadX, relRadY
			addOrUpdate("Center", 0, 0, innerW, innerH, CFrame.new())
			addOrUpdate("Edge", 0, -(0.5 - relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, 0))
			addOrUpdate("Edge", 0, 0.5 - relRadY / 2, innerW, relRadY, CFrame.Angles(0, 0, math.rad(180)))
			addOrUpdate("Edge", -(0.5 - relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(90)), true)
			addOrUpdate("Edge", 0.5 - relRadX / 2, 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(-90)), true)
			addOrUpdate(
				"Corner",
				-(0.5 - diamX / 2),
				-(0.5 - diamY / 2),
				diamX,
				diamY,
				CFrame.Angles(0, 0, math.rad(90)),
				true
			)
			addOrUpdate("Corner", 0.5 - diamX / 2, -(0.5 - diamY / 2), diamX, diamY, CFrame.Angles(0, 0, 0))
			addOrUpdate("Corner", -(0.5 - diamX / 2), 0.5 - diamY / 2, diamX, diamY, CFrame.Angles(0, 0, math.rad(180)))
			addOrUpdate(
				"Corner",
				0.5 - diamX / 2,
				0.5 - diamY / 2,
				diamX,
				diamY,
				CFrame.Angles(0, 0, math.rad(-90)),
				true
			)
		end
	end

	local function rebuildAllLayers()
		local currentSize = guiObject.AbsoluteSize
		if currentSize.X < 1 or currentSize.Y < 1 then
			return
		end
		local radius = getCornerRadius()
		if currentSize == lastSize and radius == lastRadius then
			return
		end
		local targetMode = if radius <= 0 then "Flat" else "Rounded"
		local needsRebuild = targetMode ~= currentLayoutMode
		if needsRebuild then
			for _, lc in ipairs(layerContainers) do
				for _, data in ipairs(lc.pixels) do
					data.Part:Destroy()
				end
				table.clear(lc.pixels)
			end
			currentLayoutMode = targetMode
		end
		lastSize = currentSize
		lastRadius = radius
		for _, lc in ipairs(layerContainers) do
			buildLayerGrid(lc, currentSize, needsRebuild, radius)
		end
	end

	rebuildAllLayers()

	-- ── Dynamic specular stroke ───────────────────────────────────────────

	local ss = instanceSettings.Stroke
	local stroke = nil
	local strokeGradient = nil
	local strokeHovering = false
	local strokeCurrentRot = ss and ss.restingAngle or 135
	local strokeHeartbeatConn = nil

	local cachedInset = GuiService:GetGuiInset()

	if ss and ss.enabled then
		stroke = Instance.new("UIStroke")
		stroke.Name = "LiquidGlassStroke"
		stroke.Color = ss.color
		stroke.Thickness = ss.thickness
		stroke.Transparency = 0
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = guiObject

		strokeGradient = Instance.new("UIGradient")
		strokeGradient.Transparency = ss.transparency
		strokeGradient.Color = ss.colorSequence
		strokeGradient.Rotation = ss.restingAngle
		strokeGradient.Parent = stroke

		guiObject.MouseEnter:Connect(function()
			if not enabled then
				return
			end
			strokeHovering = true
		end)

		guiObject.MouseLeave:Connect(function()
			strokeHovering = false
		end)

		strokeHeartbeatConn = RunService.Heartbeat:Connect(function(dt)
			if destroyed or not strokeGradient then
				return
			end

			local isVisible, _ = VisibilityChecker.check(guiObject)
			if not isVisible then
				return
			end

			local targetRot = ss.restingAngle

			if strokeHovering then
				local mouse = UserInputService:GetMouseLocation()
				local absPos = guiObject.AbsolutePosition
				local absSize = guiObject.AbsoluteSize
				local cx = absPos.X + absSize.X * 0.5
				local cy = absPos.Y + absSize.Y * 0.5
				local mx = mouse.X - cachedInset.X
				local my = mouse.Y - cachedInset.Y
				local dx = mx - cx
				local dy = my - cy
				local cursorAngle = math.deg(math.atan2(-dy, dx))
				targetRot = 180 - cursorAngle
			end

			local alpha = 1 - math.exp(-ss.lerpSpeed * dt)
			strokeCurrentRot = lerpAngle(strokeCurrentRot, targetRot, alpha)
			strokeGradient.Rotation = strokeCurrentRot
		end)
	end

	-- ── RenderStepped — 3D glass geometry ────────────────────────────────
	RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function()
		if not enabled then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		if guiObject.AbsoluteSize ~= lastSize or getCornerRadius() ~= lastRadius then
			rebuildAllLayers()
		end

		local isVisible, absTransparency = VisibilityChecker.check(guiObject)
		masterFolder.Parent = if isVisible then parentFolder else nil
		if not isVisible then
			return
		end

		local visibleRect = VisibilityChecker.getTrueRenderBounds(guiObject)
		if visibleRect.IsFullyClipped then
			masterFolder.Parent = nil
			return
		end

		local visibleSize = Vector2.new(visibleRect.Width, visibleRect.Height)
		local inset, _ = GuiService:GetGuiInset()
		local cx = visibleRect.Min.X + visibleSize.X * 0.5 + inset.X
		local cy = visibleRect.Min.Y + visibleSize.Y * 0.5 + inset.Y
		local hw = visibleSize.X * 0.5
		local hh = visibleSize.Y * 0.5

		local camCF = camera:GetRenderCFrame()
		local camLookVec = camCF.LookVector
		local guiRotCF = CFrame.Angles(0, 0, math.rad(-guiObject.AbsoluteRotation))
		local baseDepth = instanceSettings.Depth
		local localPadding = instanceSettings.Padding

		local rCenter = camera:ViewportPointToRay(cx, cy)
		local rRight = camera:ViewportPointToRay(cx + hw, cy)
		local rLeft = camera:ViewportPointToRay(cx - hw, cy)
		local rTop = camera:ViewportPointToRay(cx, cy - hh)
		local rBottom = camera:ViewportPointToRay(cx, cy + hh)

		local function worldAtDepth(ray, depth)
			return ray.Origin + ray.Direction * (depth / ray.Direction:Dot(camLookVec))
		end

		for _, lc in ipairs(layerContainers) do
			local depth = baseDepth + lc.depthOffset
			local pCen = worldAtDepth(rCenter, depth)
			local worldW = (worldAtDepth(rRight, depth) - worldAtDepth(rLeft, depth)).Magnitude
			local worldH = (worldAtDepth(rTop, depth) - worldAtDepth(rBottom, depth)).Magnitude

			lc.highlight.FillTransparency = lc.baseFillT + (1 - lc.baseFillT) * absTransparency
			lc.highlight.OutlineTransparency = lc.baseOutlineT + (1 - lc.baseOutlineT) * absTransparency

			for _, data in ipairs(lc.pixels) do
				local pw = data.RelSizeX * worldW + localPadding
				local ph = data.RelSizeY * worldH + localPadding
				if data.SwapAxes then
					data.Part.Size = Vector3.new(0.01, pw, ph)
				else
					data.Part.Size = Vector3.new(0.01, ph, pw)
				end
				data.Part.Transparency = lc.baseMeshT + (1 - lc.baseMeshT) * absTransparency

				local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
				local rotatedOffset = guiRotCF * localOffset
				local worldOffset = camCF.RightVector * rotatedOffset.X + camCF.UpVector * rotatedOffset.Y
				data.Part.CFrame = CFrame.new(pCen + worldOffset)
					* camCF.Rotation
					* guiRotCF
					* data.LocalRot
					* rotationOffset
			end
		end
	end)

	-- ── Cleanup ───────────────────────────────────────────────────────────
	local function cleanup(): number
		if destroyed then
			return 0
		end
		destroyed = true
		activeInstances[guiObject] = nil
		RunService:UnbindFromRenderStep(renderName)
		masterFolder:Destroy()
		if strokeHeartbeatConn then
			strokeHeartbeatConn:Disconnect()
			strokeHeartbeatConn = nil
		end
		if stroke and stroke.Parent then
			stroke:Destroy()
		end
		stroke = nil
		strokeGradient = nil
		return 1
	end

	guiObject.AncestryChanged:Connect(function(_, newParent)
		if newParent then
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

	-- ── Handle ────────────────────────────────────────────────────────────
	local handle = {}

	function handle.destroy(): number
		return cleanup()
	end

	function handle.setEnabled(state: boolean)
		enabled = state
		if not state then
			masterFolder.Parent = nil
			if stroke then
				stroke.Transparency = 1
			end
			strokeHovering = false
		else
			if stroke then
				stroke.Transparency = 0
			end
		end
	end

	function handle.isEnabled(): boolean
		return enabled
	end

	function handle.updateSettings(newOverrides)
		instanceSettings = mergeSettings(newOverrides)
		forceFlat = instanceSettings.ForceFlat

		for i, lc in ipairs(layerContainers) do
			local layerDef = instanceSettings.Layers[i]
			if not layerDef then
				continue
			end
			lc.depthOffset = layerDef.depthOffset
			lc.baseFillT = layerDef.fillTransparency
			lc.baseOutlineT = layerDef.outlineTransparency
			lc.baseMeshT = layerDef.meshTransparency
			lc.meshColor = layerDef.meshColor
			lc.highlight.FillColor = layerDef.fillColor
			lc.highlight.FillTransparency = layerDef.fillTransparency
			lc.highlight.OutlineColor = layerDef.outlineColor
			lc.highlight.OutlineTransparency = layerDef.outlineTransparency
			for _, data in ipairs(lc.pixels) do
				pcall(function()
					data.Part.Color = layerDef.meshColor
					data.Part.Transparency = layerDef.meshTransparency
				end)
			end
		end

		local nss = instanceSettings.Stroke
		if nss and stroke and strokeGradient then
			stroke.Color = nss.color
			stroke.Thickness = nss.thickness
			strokeGradient.Transparency = nss.transparency
			strokeGradient.Color = nss.colorSequence
			ss = nss
			strokeCurrentRot = nss.restingAngle
			if not nss.enabled then
				stroke.Transparency = 1
				strokeHovering = false
			else
				stroke.Transparency = 0
			end
		end

		currentLayoutMode = "None"
		lastSize = Vector2.zero
		lastRadius = -1
	end

	activeInstances[guiObject] = {
		handle = handle,
		masterFolder = masterFolder,
		renderName = renderName,
		settings = instanceSettings,
	}

	return handle
end

-- ── Public API ────────────────────────────────────────────────────────────────

function LiquidGlassHandler.new(guiObject: GuiObject)
	return createGlassInstance(guiObject, nil)
end

function LiquidGlassHandler.apply(guiObject: GuiObject, overrides: { [string]: any }?)
	return createGlassInstance(guiObject, overrides)
end

function LiquidGlassHandler.remove(guiObject: GuiObject): boolean
	local instance = activeInstances[guiObject]
	if not instance then
		return false
	end
	instance.handle.destroy()
	return true
end

function LiquidGlassHandler.setEnabled(guiObject: GuiObject, state: boolean)
	local instance = activeInstances[guiObject]
	if not instance then
		return
	end
	instance.handle.setEnabled(state)
end

function LiquidGlassHandler.has(guiObject: GuiObject): boolean
	return activeInstances[guiObject] ~= nil
end

function LiquidGlassHandler.get(guiObject: GuiObject)
	local instance = activeInstances[guiObject]
	return instance and instance.handle or nil
end

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

function LiquidGlassHandler.removeAll()
	local objects = {}
	for guiObject in pairs(activeInstances) do
		table.insert(objects, guiObject)
	end
	for _, guiObject in ipairs(objects) do
		LiquidGlassHandler.remove(guiObject)
	end
end

function LiquidGlassHandler.getActiveCount(): number
	local count = 0
	for _ in pairs(activeInstances) do
		count += 1
	end
	return count
end

CollectionService:GetInstanceAddedSignal(tag):Connect(LiquidGlassHandler.new)
for _, v in ipairs(CollectionService:GetTagged(tag)) do
	LiquidGlassHandler.new(v)
end

return LiquidGlassHandler
