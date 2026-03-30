--[[
	LiquidGlassHandler 3.2
	Copyright (c) 2026 @7eoeb, @UNIVERSECORNUCOPIA

	CHANGES FROM 3.1:

	① SEPARATED BORDER OUTLINE
	  New per-instance toggle: SeparatedBorderOutline.enabled
	  Creates a third UIStroke on the GuiObject using the new BorderOffset
	  property. On hover, BorderOffset tweens outward from (0,0) to the
	  configured offset while Transparency tweens from invisible to the
	  target. On leave, both reverse (shrink + fade). Cancel-safe tweens.

	② SPECULAR STROKE TOGGLE
	  Stroke.enabled is now respected per-instance — if false, no specular
	  UIStroke or Heartbeat connection is created. (Was already partially
	  implemented; now fully gated.)

	PRIOR CHANGES (3.1):
	  • ForceFlat mode — single Center part per layer, zero internal seams
	  • All Highlight outlines disabled — UIStroke provides specular rim
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

	-- Layers (support overrides adding layers beyond the default count)
	merged.Layers = {}
	local layerCount = #DefaultSettings.Layers
	if overrides.Layers and #overrides.Layers > layerCount then
		layerCount = #overrides.Layers
	end
	for i = 1, layerCount do
		local base = DefaultSettings.Layers[i]
		local over = overrides.Layers and overrides.Layers[i]
		local ml = {}
		if base then
			for k, v in pairs(base) do
				ml[k] = v
			end
		end
		if over then
			for k, v in pairs(over) do
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

	-- SeparatedBorderOutline
	merged.SeparatedBorderOutline = {}
	for k, v in pairs(DefaultSettings.SeparatedBorderOutline) do
		merged.SeparatedBorderOutline[k] = v
	end
	if overrides.SeparatedBorderOutline then
		for k, v in pairs(overrides.SeparatedBorderOutline) do
			merged.SeparatedBorderOutline[k] = v
		end
	end

	-- Distortion
	merged.Distortion = {}
	for k, v in pairs(DefaultSettings.Distortion) do
		merged.Distortion[k] = v
	end
	if overrides.Distortion then
		for k, v in pairs(overrides.Distortion) do
			merged.Distortion[k] = v
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
	local distortionCfg = instanceSettings.Distortion
	local useDistortion = distortionCfg and distortionCfg.enabled
	local distortionStrength = useDistortion and distortionCfg.strength or 0
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

		local hl = nil
		if not useDistortion then
			-- Legacy mode: Model-level Highlight provides frosted tint.
			hl = Instance.new("Highlight")
			hl.FillColor = layerDef.fillColor
			hl.OutlineColor = layerDef.outlineColor
			hl.FillTransparency = layerDef.fillTransparency
			hl.OutlineTransparency = layerDef.outlineTransparency
			hl.Parent = container
		end
		-- Distortion mode: NO Model-level Highlight.
		-- Per-Part Highlights (created in makePart) handle keep-alive.
		-- Multiple competing Highlights kill the distortion effect.

		layerContainers[i] = {
			container = container,
			highlight = hl, -- nil in distortion mode
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

		if not useDistortion then
			-- Legacy mode: override with config values
			p.Material = Enum.Material.Glass
			p.Color = lc.meshColor
			p.Transparency = lc.baseMeshT
		end
		-- Distortion mode: template already has Glass material,
		-- Transparency >5, and child Highlight. Don't touch them.

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
					OriginalDepth = p.Size.X,
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
			if useDistortion then
				local cols = distortionCfg.gridCols or 3
				local rows = distortionCfg.gridRows or 2
				local cellW = 1 / cols
				local cellH = 1 / rows
				for row = 0, rows - 1 do
					for col = 0, cols - 1 do
						local relX = (col + 0.5) * cellW - 0.5
						local relY = (row + 0.5) * cellH - 0.5
						addOrUpdate("Center", relX, relY, cellW, cellH)
					end
				end
			else
				addOrUpdate("Center", 0, 0, 1, 1)
			end
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

	-- ── Separated border outline ──────────────────────────────────────────
	-- A third UIStroke using BorderOffset to create a hover-activated
	-- separated outline effect (Fortnite item shop style).

	local sbo = instanceSettings.SeparatedBorderOutline
	local outlineStroke = nil
	local outlineTweenIn1 = nil -- BorderOffset tween
	local outlineTweenIn2 = nil -- Transparency tween
	local outlineTweenOut1 = nil
	local outlineTweenOut2 = nil
	local outlineHoverEnterConn = nil
	local outlineHoverLeaveConn = nil

	local function cancelOutlineTweens()
		if outlineTweenIn1 then
			outlineTweenIn1:Cancel()
			outlineTweenIn1 = nil
		end
		if outlineTweenIn2 then
			outlineTweenIn2:Cancel()
			outlineTweenIn2 = nil
		end
		if outlineTweenOut1 then
			outlineTweenOut1:Cancel()
			outlineTweenOut1 = nil
		end
		if outlineTweenOut2 then
			outlineTweenOut2:Cancel()
			outlineTweenOut2 = nil
		end
	end

	local function outlineHoverIn()
		if not enabled or not outlineStroke then
			return
		end
		cancelOutlineTweens()

		local tweenInfoIn = TweenInfo.new(sbo.tweenInTime, sbo.easingIn, Enum.EasingDirection.Out)

		outlineTweenIn1 = TweenService:Create(outlineStroke, tweenInfoIn, {
			BorderOffset = UDim.new(0, sbo.offset),
		})
		outlineTweenIn2 = TweenService:Create(outlineStroke, tweenInfoIn, {
			Transparency = sbo.hoverTransparency,
		})

		outlineTweenIn1:Play()
		outlineTweenIn2:Play()
	end

	local function outlineHoverOut()
		if not outlineStroke then
			return
		end
		cancelOutlineTweens()

		local tweenInfoOut = TweenInfo.new(sbo.tweenOutTime, sbo.easingOut, Enum.EasingDirection.Out)

		outlineTweenOut1 = TweenService:Create(outlineStroke, tweenInfoOut, {
			BorderOffset = UDim.new(0, 0),
		})
		outlineTweenOut2 = TweenService:Create(outlineStroke, tweenInfoOut, {
			Transparency = sbo.restTransparency,
		})

		outlineTweenOut1:Play()
		outlineTweenOut2:Play()
	end

	if sbo and sbo.enabled then
		outlineStroke = Instance.new("UIStroke")
		outlineStroke.Name = "LiquidGlassOutline"
		outlineStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		outlineStroke.LineJoinMode = Enum.LineJoinMode.Round
		outlineStroke.Thickness = sbo.thickness
		outlineStroke.Color = sbo.color
		outlineStroke.Transparency = sbo.restTransparency
		outlineStroke.BorderOffset = UDim.new(0, 0)
		outlineStroke.Parent = guiObject

		outlineHoverEnterConn = guiObject.MouseEnter:Connect(function()
			outlineHoverIn()
		end)

		outlineHoverLeaveConn = guiObject.MouseLeave:Connect(function()
			outlineHoverOut()
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

			if lc.highlight then
				lc.highlight.FillTransparency = lc.baseFillT + (1 - lc.baseFillT) * absTransparency
				lc.highlight.OutlineTransparency = lc.baseOutlineT + (1 - lc.baseOutlineT) * absTransparency
			end

			for _, data in ipairs(lc.pixels) do
				local pw = data.RelSizeX * worldW + localPadding
				local ph = data.RelSizeY * worldH + localPadding

				local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
				local rotatedOffset = guiRotCF * localOffset
				local worldOffset = camCF.RightVector * rotatedOffset.X + camCF.UpVector * rotatedOffset.Y

				if useDistortion then
					-- Clone's X depth is 0.025 (baked). rotationOffset aligns
					-- thin X with camera look → camera sees through 0.025 studs.
					-- Only scale Y (height) and Z (width) to match tile.
					local tilePW = data.RelSizeX * worldW
					local tilePH = data.RelSizeY * worldH
					data.Part.Size = Vector3.new(data.OriginalDepth or 0.5, tilePH, tilePW)
					data.Part.CFrame = CFrame.new(pCen + worldOffset)
						* camCF.Rotation
						* guiRotCF
						* data.LocalRot
						* rotationOffset
				else
					if data.SwapAxes then
						data.Part.Size = Vector3.new(0.01, pw, ph)
					else
						data.Part.Size = Vector3.new(0.01, ph, pw)
					end
					data.Part.Transparency = lc.baseMeshT + (1 - lc.baseMeshT) * absTransparency
					data.Part.CFrame = CFrame.new(pCen + worldOffset)
						* camCF.Rotation
						* guiRotCF
						* data.LocalRot
						* rotationOffset
				end
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

		-- Specular stroke cleanup
		if strokeHeartbeatConn then
			strokeHeartbeatConn:Disconnect()
			strokeHeartbeatConn = nil
		end
		if stroke and stroke.Parent then
			stroke:Destroy()
		end
		stroke = nil
		strokeGradient = nil

		-- Separated outline cleanup
		cancelOutlineTweens()
		if outlineHoverEnterConn then
			outlineHoverEnterConn:Disconnect()
			outlineHoverEnterConn = nil
		end
		if outlineHoverLeaveConn then
			outlineHoverLeaveConn:Disconnect()
			outlineHoverLeaveConn = nil
		end
		if outlineStroke and outlineStroke.Parent then
			outlineStroke:Destroy()
		end
		outlineStroke = nil

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

			-- Specular stroke
			if stroke then
				stroke.Transparency = 1
			end
			strokeHovering = false

			-- Separated outline — snap to rest state
			if outlineStroke then
				cancelOutlineTweens()
				outlineStroke.Transparency = sbo.restTransparency
				outlineStroke.BorderOffset = UDim.new(0, 0)
			end
		else
			-- Specular stroke
			if stroke then
				stroke.Transparency = 0
			end

			-- Outline stays at rest until next hover — no action needed
		end
	end

	function handle.isEnabled(): boolean
		return enabled
	end

	function handle.updateSettings(newOverrides)
		instanceSettings = mergeSettings(newOverrides)
		forceFlat = instanceSettings.ForceFlat

		-- Update glass layers
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
			if lc.highlight then
				lc.highlight.FillColor = layerDef.fillColor
				lc.highlight.FillTransparency = layerDef.fillTransparency
				lc.highlight.OutlineColor = layerDef.outlineColor
				lc.highlight.OutlineTransparency = layerDef.outlineTransparency
			end
			for _, data in ipairs(lc.pixels) do
				pcall(function()
					data.Part.Color = layerDef.meshColor
					data.Part.Transparency = layerDef.meshTransparency
				end)
			end
		end

		-- Update specular stroke
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

		-- Update separated outline
		local nsbo = instanceSettings.SeparatedBorderOutline
		if nsbo and outlineStroke then
			outlineStroke.Color = nsbo.color
			outlineStroke.Thickness = nsbo.thickness
			sbo = nsbo

			if not nsbo.enabled then
				cancelOutlineTweens()
				outlineStroke.Transparency = 1
				outlineStroke.BorderOffset = UDim.new(0, 0)
			end
		end

		-- Update distortion
		distortionCfg = instanceSettings.Distortion
		useDistortion = distortionCfg and distortionCfg.enabled
		distortionStrength = useDistortion and distortionCfg.strength or 0

		for i, lc in ipairs(layerContainers) do
			local layerDef = instanceSettings.Layers[i]
			if layerDef and lc.highlight then
				lc.highlight.FillTransparency = layerDef.fillTransparency
				lc.highlight.OutlineTransparency = layerDef.outlineTransparency
			end
			for _, data in ipairs(lc.pixels) do
				pcall(function()
					data.Part.Transparency = if useDistortion then distortionStrength else lc.baseMeshT
				end)
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
