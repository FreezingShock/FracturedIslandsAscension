--[[
	GlassHandler (Merged)
	Liquid Glass + Mosaic Glass in a single module.

	MODES:
	  "liquid"  — v1 approach: model-level Highlight (black fill, 0.9 FillT)
	              + Glass parts at Transparency 3. Adaptive 9-part grid
	              (Center/Edge/Corner) when UICorner present, single Center
	              when not. CaptureService suppression active.

	  "mosaic"  — distortion-only approach: NO model Highlight. CenterMosaic
	              template parts left untouched (Glass, 0.8 transparency,
	              Reflectance 1 baked in .rbxm). Always flat tiled grid with
	              configurable cols/rows. No CaptureService suppression.

	TAGS:
	  "LiquidGlass" → auto-creates liquid instance.
	  "MosaicGlass" → auto-creates mosaic instance.
	  Both tags on the same GuiObject → SKIPPED (mutual exclusion).

	SHARED OVERLAY FEATURES (independently toggleable per instance):
	  • Stroke                  — cursor-tracking specular UIStroke + UIGradient
	  • SeparatedBorderOutline  — hover-activated offset outline via BorderOffset

	API:
	  GlassHandler.apply(guiObject, { mode = "liquid", Stroke = {...}, ... })
	  GlassHandler.apply(guiObject, { mode = "mosaic", Mosaic = { Distortion = {...} } })
	  GlassHandler.new(guiObject)          — liquid (default), used by tag system
	  GlassHandler.newMosaic(guiObject)    — mosaic, used by tag system
	  GlassHandler.remove(guiObject)
	  GlassHandler.has(guiObject)
	  GlassHandler.get(guiObject)
	  GlassHandler.setEnabled(guiObject, state)
	  GlassHandler.removeAll()
	  GlassHandler.getActiveCount()
]]

local GlassHandler = {}

-- ── Services ──────────────────────────────────────────────────────────────────
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

-- ── Imports ───────────────────────────────────────────────────────────────────
local VisibilityChecker = require(script.VisibilityChecker)
local DefaultSettings = require(script.Settings)

-- ── Constants ─────────────────────────────────────────────────────────────────
local LIQUID_TAG = DefaultSettings.LiquidTag
local MOSAIC_TAG = DefaultSettings.MosaicTag
local templateContainer = script.Overlay
local rotationOffset = CFrame.Angles(0, math.rad(-90), 0)

-- ── World container ───────────────────────────────────────────────────────────
local parentFolder = Instance.new("Folder")
parentFolder.Name = "GlassObjects"
parentFolder.Parent = workspace

-- ── Active instance tracking ──────────────────────────────────────────────────
local activeInstances = {} -- [GuiObject] → { handle, mode, renderName }

-- ── Shallow merge helper ──────────────────────────────────────────────────────
local function shallowMerge(base, over)
	if not over then
		return base
	end
	local result = {}
	if base then
		for k, v in pairs(base) do
			result[k] = v
		end
	end
	for k, v in pairs(over) do
		result[k] = v
	end
	return result
end

-- ── Settings merge ────────────────────────────────────────────────────────────
local function mergeSettings(overrides)
	if not overrides then
		return {
			Padding = DefaultSettings.Padding,
			Depth = DefaultSettings.Depth,
			mode = "liquid",
			Liquid = {
				Highlight = shallowMerge(DefaultSettings.Liquid.Highlight, nil),
				Mesh = shallowMerge(DefaultSettings.Liquid.Mesh, nil),
				PartDepth = DefaultSettings.Liquid.PartDepth,
			},
			Mosaic = {
				Distortion = shallowMerge(DefaultSettings.Mosaic.Distortion, nil),
			},
			Stroke = shallowMerge(DefaultSettings.Stroke, nil),
			SeparatedBorderOutline = shallowMerge(DefaultSettings.SeparatedBorderOutline, nil),
		}
	end

	return {
		Padding = if overrides.Padding ~= nil then overrides.Padding else DefaultSettings.Padding,
		Depth = if overrides.Depth ~= nil then overrides.Depth else DefaultSettings.Depth,
		mode = overrides.mode or "liquid",

		Liquid = {
			Highlight = shallowMerge(DefaultSettings.Liquid.Highlight, overrides.Liquid and overrides.Liquid.Highlight),
			Mesh = shallowMerge(DefaultSettings.Liquid.Mesh, overrides.Liquid and overrides.Liquid.Mesh),
			PartDepth = if overrides.Liquid and overrides.Liquid.PartDepth ~= nil
				then overrides.Liquid.PartDepth
				else DefaultSettings.Liquid.PartDepth,
		},

		Mosaic = {
			Distortion = shallowMerge(
				DefaultSettings.Mosaic.Distortion,
				overrides.Mosaic and overrides.Mosaic.Distortion
			),
		},

		Stroke = shallowMerge(DefaultSettings.Stroke, overrides.Stroke),
		SeparatedBorderOutline = shallowMerge(DefaultSettings.SeparatedBorderOutline, overrides.SeparatedBorderOutline),
	}
end

-- ── Shortest-path angle lerp ──────────────────────────────────────────────────
local function lerpAngle(current: number, target: number, alpha: number): number
	local diff = ((target - current) + 180) % 360 - 180
	return current + diff * alpha
end

-- ══════════════════════════════════════════════════════════════════════════════
-- ██ CORE INSTANCE FACTORY
-- ══════════════════════════════════════════════════════════════════════════════

local function createGlassInstance(guiObject: GuiObject, overrides: { [string]: any }?)
	if not guiObject:IsDescendantOf(Players.LocalPlayer) then
		return nil
	end
	if activeInstances[guiObject] then
		return activeInstances[guiObject].handle
	end

	-- ── Mutual exclusion ──────────────────────────────────────────────────
	local hasLiquidTag = CollectionService:HasTag(guiObject, LIQUID_TAG)
	local hasMosaicTag = CollectionService:HasTag(guiObject, MOSAIC_TAG)
	if hasLiquidTag and hasMosaicTag then
		warn(
			"[GlassHandler] GuiObject has both LiquidGlass and MosaicGlass tags — skipping:",
			guiObject:GetFullName()
		)
		return nil
	end

	-- ── Resolve settings ──────────────────────────────────────────────────
	local settings = mergeSettings(overrides)
	local mode = settings.mode
	local isLiquid = (mode == "liquid")
	local isMosaic = (mode == "mosaic")
	local depth = settings.Depth
	local localPadding = settings.Padding

	local renderName = `Glass_{HttpService:GenerateGUID(false)}`

	-- ── 3D container ──────────────────────────────────────────────────────
	local container = Instance.new("Model")
	container.Name = renderName
	container.Parent = parentFolder

	-- ── Model-level Highlight (liquid only) ───────────────────────────────
	local highlight = nil
	if isLiquid then
		local hlCfg = settings.Liquid.Highlight
		highlight = Instance.new("Highlight")
		highlight.FillColor = hlCfg.FillColor
		highlight.OutlineTransparency = hlCfg.OutlineTransparency
		highlight.FillTransparency = hlCfg.FillTransparency
		highlight.Parent = container
	end
	-- Mosaic: NO model Highlight. Template parts handle their own appearance.

	-- ── Geometry state ────────────────────────────────────────────────────
	local pixels = {}
	local lastSize = Vector2.zero
	local lastRadius: number = -1
	local currentLayoutMode = "None"
	local enabled = true
	local destroyed = false
	local glassVisible = true -- false = 3D glass hidden, stroke/outline still active

	-- ── Corner radius (liquid only — mosaic always returns 0) ─────────────
	local function getCornerRadius(): number
		if isMosaic then
			return 0
		end
		local sz = guiObject.AbsoluteSize
		local uiCorner = guiObject:FindFirstChildWhichIsA("UICorner")
		local radius = uiCorner and (uiCorner.CornerRadius.Offset + uiCorner.CornerRadius.Scale * math.min(sz.X, sz.Y))
			or 0
		local maxR = math.min(sz.X, sz.Y) / 2
		return math.clamp(radius, 0, maxR)
	end

	-- ── Part creation ─────────────────────────────────────────────────────
	local function makePart(templateName: string)
		local template = templateContainer:FindFirstChild(templateName)
		if not template then
			warn("[GlassHandler] Missing overlay template:", templateName)
			return nil
		end
		local p = template:Clone()

		if isLiquid then
			-- Apply liquid mesh config over the cloned template
			local meshCfg = settings.Liquid.Mesh
			p.Material = meshCfg.Material
			p.Color = meshCfg.Color
			p.Transparency = meshCfg.Transparency
		end
		-- Mosaic: leave template properties untouched
		-- (Glass material, 0.8 transparency, Reflectance 1 — baked in .rbxm)

		p.Anchored = true
		p.CastShadow = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		pcall(function()
			p.AudioCanCollide = false
		end)
		p.Parent = container
		return p
	end

	-- ── Grid building ─────────────────────────────────────────────────────
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

		local targetMode = if radius <= 0 then "Flat" else "Rounded"
		local needsRebuild = (targetMode ~= currentLayoutMode)

		if needsRebuild then
			for _, data in ipairs(pixels) do
				data.Part:Destroy()
			end
			table.clear(pixels)
			currentLayoutMode = targetMode
		end

		local partIndex = 1
		local function addOrUpdate(templateName, relX, relY, relSizeX, relSizeY, localRot, swapAxes)
			localRot = localRot or CFrame.new()
			swapAxes = swapAxes or false
			if needsRebuild then
				local p = makePart(templateName)
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

		if isMosaic then
			-- ── Mosaic: always flat, tiled CenterMosaic grid ──────────
			local distCfg = settings.Mosaic.Distortion
			local cols = distCfg.gridCols
			local rows = distCfg.gridRows
			local cellW = 1 / cols
			local cellH = 1 / rows
			for row = 0, rows - 1 do
				for col = 0, cols - 1 do
					local relX = (col + 0.5) * cellW - 0.5
					local relY = (row + 0.5) * cellH - 0.5
					addOrUpdate("CenterMosaic", relX, relY, cellW, cellH)
				end
			end
		elseif radius <= 0 then
			-- ── Liquid flat (no UICorner) ─────────────────────────────
			addOrUpdate("Center", 0, 0, 1, 1)
		else
			-- ── Liquid 9-part rounded ─────────────────────────────────
			local relRadX = radius / currentSize.X
			local relRadY = radius / currentSize.Y
			local innerW = (currentSize.X - 2 * radius) / currentSize.X
			local innerH = (currentSize.Y - 2 * radius) / currentSize.Y
			local diamX = relRadX
			local diamY = relRadY

			addOrUpdate("Center", 0, 0, innerW, innerH)

			-- Top edge
			addOrUpdate("Edge", 0, -0.5 + (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, 0))
			-- Bottom edge
			addOrUpdate("Edge", 0, 0.5 - (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, math.rad(180)))
			-- Left edge
			addOrUpdate("Edge", -0.5 + (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(90)), true)
			-- Right edge
			addOrUpdate("Edge", 0.5 - (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(-90)), true)

			local halfDiamX = diamX / 2
			local halfDiamY = diamY / 2

			-- Top-left corner
			addOrUpdate(
				"Corner",
				-0.5 + halfDiamX,
				-0.5 + halfDiamY,
				diamX,
				diamY,
				CFrame.Angles(0, 0, math.rad(90)),
				true
			)
			-- Top-right corner
			addOrUpdate("Corner", 0.5 - halfDiamX, -0.5 + halfDiamY, diamX, diamY, CFrame.Angles(0, 0, 0))
			-- Bottom-left corner
			addOrUpdate("Corner", -0.5 + halfDiamX, 0.5 - halfDiamY, diamX, diamY, CFrame.Angles(0, 0, math.rad(180)))
			-- Bottom-right corner
			addOrUpdate(
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

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ SPECULAR STROKE (shared — independently toggleable)
	-- ══════════════════════════════════════════════════════════════════════

	local ss = settings.Stroke
	local stroke = nil
	local strokeGradient = nil
	local strokeHovering = false
	local strokeCurrentRot = ss.restingAngle
	local strokeHeartbeatConn = nil
	local cachedInset = GuiService:GetGuiInset()

	if ss.enabled then
		stroke = Instance.new("UIStroke")
		stroke.Name = "GlassStroke"
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

			local isVis, _ = VisibilityChecker.check(guiObject, false)
			if not isVis then
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

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ SEPARATED BORDER OUTLINE (shared — independently toggleable)
	-- ══════════════════════════════════════════════════════════════════════

	local sbo = settings.SeparatedBorderOutline
	local outlineStroke = nil
	local outlineTweenIn1 = nil
	local outlineTweenIn2 = nil
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

	if sbo.enabled then
		outlineStroke = Instance.new("UIStroke")
		outlineStroke.Name = "GlassOutline"
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

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ RENDERSTEP — 3D glass geometry
	-- ══════════════════════════════════════════════════════════════════════

	RunService:BindToRenderStep(renderName, Enum.RenderPriority.Camera.Value + 1, function()
		if not enabled then
			return
		end
		-- Glass-only toggle: hides 3D parts while stroke/outline remain active
		if not glassVisible then
			container.Parent = nil
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end

		-- Rebuild grid on size / corner-radius change
		if guiObject.AbsoluteSize ~= lastSize or getCornerRadius() ~= lastRadius then
			rebuildGrid()
		end

		-- Visibility (liquid suppresses during screenshot capture)
		local isVisible, absTransparency = VisibilityChecker.check(guiObject, isLiquid)
		container.Parent = if isVisible then parentFolder else nil
		if not isVisible then
			return
		end

		-- Clipped render bounds
		local visibleRect = VisibilityChecker.getTrueRenderBounds(guiObject)
		local visibleSize = Vector2.new(visibleRect.Width, visibleRect.Height)

		if visibleSize.X <= 0 or visibleSize.Y <= 0 then
			container.Parent = nil
			return
		else
			container.Parent = parentFolder
		end

		-- Screen → world projection
		local inset, _ = GuiService:GetGuiInset()
		local centerScreenPos = visibleRect.Min + (visibleSize / 2) + inset

		local camCF = camera:GetRenderCFrame()
		local camLookVec = camCF.LookVector
		local guiRotCF = CFrame.Angles(0, 0, math.rad(-guiObject.AbsoluteRotation))

		local function getPlanePos(pixelX, pixelY)
			local ray = camera:ViewportPointToRay(pixelX, pixelY)
			local dist = depth / ray.Direction:Dot(camLookVec)
			return ray.Origin + ray.Direction * dist
		end

		local centerWorldPos = getPlanePos(centerScreenPos.X, centerScreenPos.Y)
		local rightEdge = getPlanePos(centerScreenPos.X + (visibleSize.X / 2), centerScreenPos.Y)
		local leftEdge = getPlanePos(centerScreenPos.X - (visibleSize.X / 2), centerScreenPos.Y)
		local topEdge = getPlanePos(centerScreenPos.X, centerScreenPos.Y - (visibleSize.Y / 2))
		local bottomEdge = getPlanePos(centerScreenPos.X, centerScreenPos.Y + (visibleSize.Y / 2))

		local worldW = (rightEdge - leftEdge).Magnitude
		local worldH = (topEdge - bottomEdge).Magnitude

		-- ── Branch: liquid vs mosaic render ────────────────────────────

		if isLiquid then
			-- ▸ V1 EXACT RENDER LOGIC ◂
			-- Model Highlight transparency responds to CanvasGroup fade
			local hlCfg = settings.Liquid.Highlight
			local meshCfg = settings.Liquid.Mesh
			local partDepth = settings.Liquid.PartDepth

			highlight.FillTransparency = hlCfg.FillTransparency + (1 - hlCfg.FillTransparency) * absTransparency

			for _, data in ipairs(pixels) do
				local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
				local rotatedOffset = guiRotCF * localOffset
				local worldOffset = (camCF.RightVector * rotatedOffset.X) + (camCF.UpVector * rotatedOffset.Y)

				if data.SwapAxes then
					data.Part.Size = Vector3.new(
						partDepth,
						data.RelSizeX * worldW + localPadding,
						data.RelSizeY * worldH + localPadding
					)
				else
					data.Part.Size = Vector3.new(
						partDepth,
						data.RelSizeY * worldH + localPadding,
						data.RelSizeX * worldW + localPadding
					)
				end

				data.Part.Transparency = meshCfg.Transparency + (1 - meshCfg.Transparency) * absTransparency
				data.Part.CFrame = CFrame.new(centerWorldPos + worldOffset)
					* camCF.Rotation
					* guiRotCF
					* data.LocalRot
					* rotationOffset
			end
		else
			-- ▸ MOSAIC RENDER LOGIC (distortion-only) ◂
			-- No Highlight. Parts keep template transparency/reflectance.
			-- Size preserves OriginalDepth (template mesh depth).
			for _, data in ipairs(pixels) do
				local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
				local rotatedOffset = guiRotCF * localOffset
				local worldOffset = (camCF.RightVector * rotatedOffset.X) + (camCF.UpVector * rotatedOffset.Y)

				local tilePW = data.RelSizeX * worldW
				local tilePH = data.RelSizeY * worldH
				data.Part.Size = Vector3.new(data.OriginalDepth or 0.5, tilePH, tilePW)
				data.Part.CFrame = CFrame.new(centerWorldPos + worldOffset)
					* camCF.Rotation
					* guiRotCF
					* data.LocalRot
					* rotationOffset
			end
		end
	end)

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ CLEANUP
	-- ══════════════════════════════════════════════════════════════════════

	local function cleanup(): number
		if destroyed then
			return 0
		end
		destroyed = true
		activeInstances[guiObject] = nil
		RunService:UnbindFromRenderStep(renderName)
		container:Destroy()

		-- Specular stroke
		if strokeHeartbeatConn then
			strokeHeartbeatConn:Disconnect()
			strokeHeartbeatConn = nil
		end
		if stroke and stroke.Parent then
			stroke:Destroy()
		end
		stroke = nil
		strokeGradient = nil

		-- Separated outline
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

	-- Auto-cleanup on ancestry removal
	guiObject.AncestryChanged:Connect(function(_, newParent)
		if newParent then
			return
		end
		cleanup()
	end)

	-- Auto-cleanup on tag removal (for either tag)
	local function onTagRemoved(v)
		if v ~= guiObject then
			return
		end
		cleanup()
	end
	CollectionService:GetInstanceRemovedSignal(LIQUID_TAG):Connect(onTagRemoved)
	CollectionService:GetInstanceRemovedSignal(MOSAIC_TAG):Connect(onTagRemoved)

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ INSTANCE HANDLE
	-- ══════════════════════════════════════════════════════════════════════

	local handle = {}

	function handle.destroy(): number
		return cleanup()
	end

	function handle.setEnabled(state: boolean)
		enabled = state
		if not state then
			container.Parent = nil

			-- Specular stroke
			if stroke then
				stroke.Transparency = 1
			end
			strokeHovering = false

			-- Separated outline — snap to rest
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
			-- Outline stays at rest until next hover
		end
	end

	function handle.isEnabled(): boolean
		return enabled
	end

	function handle.getMode(): string
		return mode
	end

	--- Toggle only the 3D glass parts. Stroke and outline remain functional.
	function handle.setGlassVisible(state: boolean)
		glassVisible = state
		if not state then
			container.Parent = nil
		end
	end

	function handle.isGlassVisible(): boolean
		return glassVisible
	end

	-- ── Register ──────────────────────────────────────────────────────────
	activeInstances[guiObject] = {
		handle = handle,
		mode = mode,
		renderName = renderName,
	}

	return handle
end

-- ══════════════════════════════════════════════════════════════════════════════
-- ██ PUBLIC API
-- ══════════════════════════════════════════════════════════════════════════════

--- Create a liquid glass instance (default). Used by tag auto-application.
function GlassHandler.new(guiObject: GuiObject)
	return createGlassInstance(guiObject, { mode = "liquid" })
end

--- Create a mosaic glass instance. Used by tag auto-application.
function GlassHandler.newMosaic(guiObject: GuiObject)
	return createGlassInstance(guiObject, { mode = "mosaic" })
end

--- Create a glass instance with full config control.
--- overrides.mode = "liquid" (default) | "mosaic"
function GlassHandler.apply(guiObject: GuiObject, overrides: { [string]: any }?)
	return createGlassInstance(guiObject, overrides)
end

--- Remove the glass effect from a GuiObject.
function GlassHandler.remove(guiObject: GuiObject): boolean
	local instance = activeInstances[guiObject]
	if not instance then
		return false
	end
	instance.handle.destroy()
	return true
end

--- Check whether a GuiObject has an active glass instance.
function GlassHandler.has(guiObject: GuiObject): boolean
	return activeInstances[guiObject] ~= nil
end

--- Get the handle for an active glass instance (or nil).
function GlassHandler.get(guiObject: GuiObject)
	local instance = activeInstances[guiObject]
	return instance and instance.handle or nil
end

--- Toggle enabled state for an existing glass instance.
function GlassHandler.setEnabled(guiObject: GuiObject, state: boolean)
	local instance = activeInstances[guiObject]
	if not instance then
		return
	end
	instance.handle.setEnabled(state)
end

--- Toggle only the 3D glass rendering. Stroke and outline remain active.
function GlassHandler.setGlassVisible(guiObject: GuiObject, state: boolean)
	local instance = activeInstances[guiObject]
	if not instance then
		return
	end
	instance.handle.setGlassVisible(state)
end

--- Batch apply to multiple GuiObjects.
function GlassHandler.applyBatch(guiObjects: { GuiObject }, overrides: { [string]: any }?)
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
function GlassHandler.removeAll()
	local objects = {}
	for guiObject in pairs(activeInstances) do
		table.insert(objects, guiObject)
	end
	for _, guiObject in ipairs(objects) do
		GlassHandler.remove(guiObject)
	end
end

--- Count of active glass instances.
function GlassHandler.getActiveCount(): number
	local count = 0
	for _ in pairs(activeInstances) do
		count += 1
	end
	return count
end

-- ══════════════════════════════════════════════════════════════════════════════
-- ██ TAG AUTO-APPLICATION
-- ══════════════════════════════════════════════════════════════════════════════

-- LiquidGlass tag → liquid mode
CollectionService:GetInstanceAddedSignal(LIQUID_TAG):Connect(function(v)
	-- Guard: if it also has the mosaic tag, skip (mutual exclusion)
	if CollectionService:HasTag(v, MOSAIC_TAG) then
		warn("[GlassHandler] GuiObject has both LiquidGlass and MosaicGlass tags — skipping:", v:GetFullName())
		return
	end
	GlassHandler.new(v)
end)

-- MosaicGlass tag → mosaic mode
CollectionService:GetInstanceAddedSignal(MOSAIC_TAG):Connect(function(v)
	-- Guard: if it also has the liquid tag, skip (mutual exclusion)
	if CollectionService:HasTag(v, LIQUID_TAG) then
		warn("[GlassHandler] GuiObject has both LiquidGlass and MosaicGlass tags — skipping:", v:GetFullName())
		return
	end
	GlassHandler.newMosaic(v)
end)

-- Process already-tagged instances at startup
for _, v in ipairs(CollectionService:GetTagged(LIQUID_TAG)) do
	if not CollectionService:HasTag(v, MOSAIC_TAG) then
		GlassHandler.new(v)
	end
end
for _, v in ipairs(CollectionService:GetTagged(MOSAIC_TAG)) do
	if not CollectionService:HasTag(v, LIQUID_TAG) then
		GlassHandler.newMosaic(v)
	end
end

return GlassHandler
