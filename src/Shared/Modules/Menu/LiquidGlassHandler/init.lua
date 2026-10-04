--[[
	GlassHandler (Merged)
	Liquid Glass + Mosaic Glass in a single module.

	MODES:
	  "liquid"  — model-level Highlight (black fill, 0.9 FillT) + Glass parts at Transparency 3.
	              Adaptive 9-part grid (Center/Edge/Corner) when UICorner present, single Center
	              when not. CaptureService suppression active.

	  "mosaic"  — distortion-only: NO model Highlight. CenterMosaic template parts left untouched
	              (Glass, 0.8 transparency, Reflectance 1 baked in .rbxm). Always flat tiled grid
	              with configurable cols/rows. No CaptureService suppression.

	TAGS:
	  "LiquidGlass" → auto-creates liquid instance.
	  "MosaicGlass" → auto-creates mosaic instance.
	  Both tags on the same GuiObject → SKIPPED (mutual exclusion).

	SHARED OVERLAY FEATURES (independently toggleable per instance):
	  • Stroke                  — cursor-tracking specular UIStroke + UIGradient
	  • SeparatedBorderOutline  — hover-activated offset outline via BorderOffset

	API (unchanged):
	  GlassHandler.apply(guiObject, { mode = "liquid", Stroke = {...}, ... })
	  GlassHandler.new(guiObject) / GlassHandler.newMosaic(guiObject)
	  GlassHandler.remove / has / get / setEnabled / setGlassVisible / applyBatch / removeAll / getActiveCount

	PERFORMANCE MODEL (rewritten):
	  * ONE shared RenderStep drives every instance (it used to be one BindToRenderStep + one Heartbeat
	    connection per instance: 40+ of them with the inventory slots).
	  * Per frame the camera/inset/mouse are read once, each instance walks its ancestors once, and the
	    3D parts are only touched when something that affects them changed (camera, rect, rotation,
	    fade, corner radius). A still camera + open menu costs almost nothing.
	  * Hidden glass is LAZY: an instance whose glass is hidden (setGlassVisible(false), e.g. the 27 grid
	    slots) never builds its parts, and an instance that isn't on screen does no geometry work.
	  * The stroke only animates while hovered or still easing back to its resting angle.
	  * Tag-removal handling is one global listener, not one connection per instance.
]]

local GlassHandler = {}

-- ── Services ──────────────────────────────────────────────────────────────────
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- ── Imports ───────────────────────────────────────────────────────────────────
local VisibilityChecker = require(script.VisibilityChecker)
local DefaultSettings = require(script.Settings)

-- ── Constants ─────────────────────────────────────────────────────────────────
local LIQUID_TAG = DefaultSettings.LiquidTag
local MOSAIC_TAG = DefaultSettings.MosaicTag
local templateContainer = script.Overlay
local rotationOffset = CFrame.Angles(0, math.rad(-90), 0)
local RENDER_NAME = "GlassHandler_Render"
local STROKE_FADE = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STROKE_REST_EPSILON = 0.05 -- degrees; below this the gradient is "at rest" and stops animating

-- ── World container ───────────────────────────────────────────────────────────
local parentFolder = Instance.new("Folder")
parentFolder.Name = "GlassObjects"
parentFolder.Parent = workspace

-- ── Active instance tracking ──────────────────────────────────────────────────
local activeInstances = {} -- [GuiObject] → inst
local instanceList = {} -- array of inst (iteration order for the shared render step)
local renderBound = false
local renderStep -- forward declaration

local function bindRender()
	if not renderBound then
		renderBound = true
		RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, renderStep)
	end
end

local function unbindRender()
	if renderBound then
		renderBound = false
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end
end

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
			GlassVisible = true,
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
		GlassVisible = overrides.GlassVisible ~= false,

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
	local existing = activeInstances[guiObject]
	if existing then
		return existing.handle
	end

	-- ── Mutual exclusion ──────────────────────────────────────────────────
	if CollectionService:HasTag(guiObject, LIQUID_TAG) and CollectionService:HasTag(guiObject, MOSAIC_TAG) then
		warn("[GlassHandler] GuiObject has both LiquidGlass and MosaicGlass tags — skipping:", guiObject:GetFullName())
		return nil
	end

	-- ── Resolve settings ──────────────────────────────────────────────────
	local settings = mergeSettings(overrides)
	local mode = settings.mode
	local isLiquid = (mode == "liquid")
	local isMosaic = (mode == "mosaic")
	local depth = settings.Depth
	local localPadding = settings.Padding

	-- ── State ─────────────────────────────────────────────────────────────
	local inst = {}
	inst.guiObject = guiObject
	inst.mode = mode

	local container: Model? = nil -- built lazily the first time the glass is actually drawn
	local highlight: Highlight? = nil
	local pixels = {}
	local lastSize = Vector2.zero
	local lastRadius: number = -1
	local currentLayoutMode = "None"
	local enabled = true
	local destroyed = false
	local glassVisible = settings.GlassVisible -- false = 3D glass hidden, stroke/outline still active
	local connections = {}

	-- last values that affect the 3D parts (skip the part updates when nothing changed)
	local lastCamCF: CFrame? = nil
	local lastCenter = Vector2.zero
	local lastVisSize = Vector2.zero
	local lastRotation = 0
	local lastAbsT = -1
	local lastViewport = Vector2.zero
	local geometryDirty = true

	local function setContainerParent(parent: Instance?)
		if container and container.Parent ~= parent then
			container.Parent = parent
		end
	end

	-- ── Corner radius (liquid only — mosaic always returns 0) ─────────────
	local uiCorner: UICorner? = guiObject:FindFirstChildWhichIsA("UICorner")
	local cornerDirty = true
	local cachedRadius = 0

	local function getCornerRadius(): number
		if isMosaic then
			return 0
		end
		if cornerDirty then
			cornerDirty = false
			local sz = guiObject.AbsoluteSize
			local radius = uiCorner
					and (uiCorner.CornerRadius.Offset + uiCorner.CornerRadius.Scale * math.min(sz.X, sz.Y))
				or 0
			cachedRadius = math.clamp(radius, 0, math.min(sz.X, sz.Y) / 2)
		end
		return cachedRadius
	end

	local function watchCorner(corner: UICorner?)
		if corner then
			table.insert(
				connections,
				corner:GetPropertyChangedSignal("CornerRadius"):Connect(function()
					cornerDirty = true
				end)
			)
		end
	end
	watchCorner(uiCorner)
	table.insert(
		connections,
		guiObject.ChildAdded:Connect(function(child)
			if child:IsA("UICorner") then
				uiCorner = child
				cornerDirty = true
				watchCorner(child)
			end
		end)
	)
	table.insert(
		connections,
		guiObject.ChildRemoved:Connect(function(child)
			if child == uiCorner then
				uiCorner = guiObject:FindFirstChildWhichIsA("UICorner")
				cornerDirty = true
			end
		end)
	)
	-- a size change changes the radius of percentage-based corners
	table.insert(
		connections,
		guiObject:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			cornerDirty = true
			geometryDirty = true
		end)
	)

	-- ── 3D container + Highlight (lazy) ───────────────────────────────────
	local function ensureContainer()
		if container then
			return
		end
		container = Instance.new("Model")
		container.Name = "Glass_" .. guiObject.Name
		if isLiquid then
			local hlCfg = settings.Liquid.Highlight
			highlight = Instance.new("Highlight")
			highlight.FillColor = hlCfg.FillColor
			highlight.OutlineTransparency = hlCfg.OutlineTransparency
			highlight.FillTransparency = hlCfg.FillTransparency
			highlight.Parent = container
		end
		-- Mosaic: NO model Highlight. Template parts handle their own appearance.
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
		if isMosaic then
			-- Template material/mesh stay; transparency + reflectance come from Settings.Mosaic.Distortion
			-- (the template's baked Reflectance 1 made the frosted panel sparkle like shattered glass)
			local distCfg = settings.Mosaic.Distortion
			p.Transparency = distCfg.strength
			p.Reflectance = distCfg.reflectance or 0
		end

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
		geometryDirty = true

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

			-- Top / bottom / left / right edges
			addOrUpdate("Edge", 0, -0.5 + (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, 0))
			addOrUpdate("Edge", 0, 0.5 - (relRadY / 2), innerW, relRadY, CFrame.Angles(0, 0, math.rad(180)))
			addOrUpdate("Edge", -0.5 + (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(90)), true)
			addOrUpdate("Edge", 0.5 - (relRadX / 2), 0, relRadX, innerH, CFrame.Angles(0, 0, math.rad(-90)), true)

			local halfDiamX = diamX / 2
			local halfDiamY = diamY / 2

			-- Corners: top-left, top-right, bottom-left, bottom-right
			addOrUpdate("Corner", -0.5 + halfDiamX, -0.5 + halfDiamY, diamX, diamY, CFrame.Angles(0, 0, math.rad(90)), true)
			addOrUpdate("Corner", 0.5 - halfDiamX, -0.5 + halfDiamY, diamX, diamY, CFrame.Angles(0, 0, 0))
			addOrUpdate("Corner", -0.5 + halfDiamX, 0.5 - halfDiamY, diamX, diamY, CFrame.Angles(0, 0, math.rad(180)))
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

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ SPECULAR STROKE (shared — independently toggleable)
	-- ══════════════════════════════════════════════════════════════════════

	local ss = settings.Stroke
	local stroke: UIStroke? = nil
	local strokeGradient: UIGradient? = nil
	local strokeHovering = false
	local strokeCurrentRot = ss.restingAngle
	local strokeSettled = true
	local strokeFade: Tween? = nil

	local function fadeStroke(target: number)
		if not stroke then
			return
		end
		if strokeFade then
			strokeFade:Cancel()
		end
		strokeFade = TweenService:Create(stroke, STROKE_FADE, { Transparency = target })
		strokeFade:Play()
	end

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

		table.insert(
			connections,
			guiObject.MouseEnter:Connect(function()
				if not enabled then
					return
				end
				strokeHovering = true
				strokeSettled = false
			end)
		)
		table.insert(
			connections,
			guiObject.MouseLeave:Connect(function()
				strokeHovering = false
				strokeSettled = false -- ease back to the resting angle
			end)
		)
	end

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ SEPARATED BORDER OUTLINE (shared — independently toggleable)
	-- ══════════════════════════════════════════════════════════════════════

	local sbo = settings.SeparatedBorderOutline
	local outlineStroke: UIStroke? = nil
	local outlineTweens = {}

	local function cancelOutlineTweens()
		for i = #outlineTweens, 1, -1 do
			outlineTweens[i]:Cancel()
			outlineTweens[i] = nil
		end
	end

	local function playOutline(info: TweenInfo, offset: number, transparency: number)
		cancelOutlineTweens()
		local a = TweenService:Create(outlineStroke, info, { BorderOffset = UDim.new(0, offset) })
		local b = TweenService:Create(outlineStroke, info, { Transparency = transparency })
		outlineTweens[1], outlineTweens[2] = a, b
		a:Play()
		b:Play()
	end

	local function outlineHoverIn()
		if not enabled or not outlineStroke then
			return
		end
		playOutline(TweenInfo.new(sbo.tweenInTime, sbo.easingIn, Enum.EasingDirection.Out), sbo.offset, sbo.hoverTransparency)
	end

	local function outlineHoverOut()
		if not outlineStroke then
			return
		end
		playOutline(TweenInfo.new(sbo.tweenOutTime, sbo.easingOut, Enum.EasingDirection.Out), 0, sbo.restTransparency)
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

		table.insert(connections, guiObject.MouseEnter:Connect(outlineHoverIn))
		table.insert(connections, guiObject.MouseLeave:Connect(outlineHoverOut))
	end

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ PER-FRAME UPDATE (called by the shared render step)
	-- ══════════════════════════════════════════════════════════════════════

	--- ctx = { camera, camCF, viewport, inset, mouse }
	function inst.update(ctx, dt: number)
		if destroyed then
			return
		end

		-- One visibility check per frame, shared by the stroke and the glass.
		local visible, absT = VisibilityChecker.check(guiObject, isLiquid and enabled and glassVisible)

		-- ── Stroke: only while hovered or still easing back to rest ──────
		if strokeGradient and not strokeSettled and visible then
			local targetRot = ss.restingAngle
			if strokeHovering then
				local absPos = guiObject.AbsolutePosition
				local absSize = guiObject.AbsoluteSize
				local dx = (ctx.mouse.X - ctx.inset.X) - (absPos.X + absSize.X * 0.5)
				local dy = (ctx.mouse.Y - ctx.inset.Y) - (absPos.Y + absSize.Y * 0.5)
				targetRot = 180 - math.deg(math.atan2(-dy, dx))
			end
			strokeCurrentRot = lerpAngle(strokeCurrentRot, targetRot, 1 - math.exp(-ss.lerpSpeed * dt))
			strokeGradient.Rotation = strokeCurrentRot
			if not strokeHovering and math.abs(((targetRot - strokeCurrentRot) + 180) % 360 - 180) < STROKE_REST_EPSILON then
				strokeCurrentRot = targetRot
				strokeGradient.Rotation = targetRot
				strokeSettled = true
			end
		end

		-- ── 3D glass ──────────────────────────────────────────────────────
		if not enabled or not glassVisible then
			setContainerParent(nil)
			return
		end
		if not visible then
			setContainerParent(nil)
			return
		end

		ensureContainer()
		rebuildGrid() -- cheap: returns immediately unless the size or corner radius changed
		if #pixels == 0 then
			return
		end

		-- Clipped render bounds
		local visibleRect = VisibilityChecker.getTrueRenderBounds(guiObject)
		if visibleRect.IsFullyClipped then
			setContainerParent(nil)
			return
		end
		local visibleSize = Vector2.new(visibleRect.Width, visibleRect.Height)
		local center = visibleRect.Min + (visibleSize / 2)
		local rotation = guiObject.AbsoluteRotation
		local camCF = ctx.camCF

		-- Nothing that affects the parts changed since last frame → leave them alone
		if
			not geometryDirty
			and camCF == lastCamCF
			and center == lastCenter
			and visibleSize == lastVisSize
			and rotation == lastRotation
			and absT == lastAbsT
			and ctx.viewport == lastViewport
		then
			setContainerParent(parentFolder)
			return
		end
		geometryDirty = false
		lastCamCF, lastCenter, lastVisSize, lastRotation, lastAbsT, lastViewport =
			camCF, center, visibleSize, rotation, absT, ctx.viewport
		setContainerParent(parentFolder)

		-- Screen → world projection (everything lives on a plane `depth` studs in front of the camera)
		local camera = ctx.camera
		local camLookVec = camCF.LookVector
		local guiRotCF = CFrame.Angles(0, 0, math.rad(-rotation))
		local centerScreenPos = center + ctx.inset

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

		local rightVec, upVec, camRot = camCF.RightVector, camCF.UpVector, camCF.Rotation

		if isLiquid then
			-- Model Highlight transparency responds to CanvasGroup fade
			local hlCfg = settings.Liquid.Highlight
			local meshCfg = settings.Liquid.Mesh
			local partDepth = settings.Liquid.PartDepth

			highlight.FillTransparency = hlCfg.FillTransparency + (1 - hlCfg.FillTransparency) * absT
			local partTransparency = meshCfg.Transparency + (1 - meshCfg.Transparency) * absT

			for _, data in ipairs(pixels) do
				local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
				local rotatedOffset = guiRotCF * localOffset
				local worldOffset = (rightVec * rotatedOffset.X) + (upVec * rotatedOffset.Y)

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

				data.Part.Transparency = partTransparency
				data.Part.CFrame = CFrame.new(centerWorldPos + worldOffset) * camRot * guiRotCF * data.LocalRot * rotationOffset
			end
		else
			-- Mosaic (distortion only): no Highlight; parts keep template transparency/reflectance
			for _, data in ipairs(pixels) do
				local localOffset = Vector3.new(data.RelX * worldW, -data.RelY * worldH, 0)
				local rotatedOffset = guiRotCF * localOffset
				local worldOffset = (rightVec * rotatedOffset.X) + (upVec * rotatedOffset.Y)

				data.Part.Size = Vector3.new(data.OriginalDepth or 0.5, data.RelSizeY * worldH, data.RelSizeX * worldW)
				data.Part.CFrame = CFrame.new(centerWorldPos + worldOffset) * camRot * guiRotCF * data.LocalRot * rotationOffset
			end
		end
	end

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ CLEANUP
	-- ══════════════════════════════════════════════════════════════════════

	local function cleanup(): number
		if destroyed then
			return 0
		end
		destroyed = true
		activeInstances[guiObject] = nil
		local index = table.find(instanceList, inst)
		if index then
			table.remove(instanceList, index)
		end
		if #instanceList == 0 then
			unbindRender()
		end

		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)

		if container then
			container:Destroy()
			container = nil
		end

		if strokeFade then
			strokeFade:Cancel()
		end
		if stroke and stroke.Parent then
			stroke:Destroy()
		end
		stroke, strokeGradient = nil, nil

		cancelOutlineTweens()
		if outlineStroke and outlineStroke.Parent then
			outlineStroke:Destroy()
		end
		outlineStroke = nil

		return 1
	end

	-- Auto-cleanup on ancestry removal
	table.insert(
		connections,
		guiObject.AncestryChanged:Connect(function(_, newParent)
			if not newParent then
				cleanup()
			end
		end)
	)

	-- ══════════════════════════════════════════════════════════════════════
	-- ██ INSTANCE HANDLE
	-- ══════════════════════════════════════════════════════════════════════

	local handle = {}

	function handle.destroy(): number
		return cleanup()
	end

	function handle.setEnabled(state: boolean)
		if enabled == state then
			return
		end
		enabled = state
		geometryDirty = true
		if not state then
			setContainerParent(nil)
			strokeHovering = false
			strokeSettled = true
			if stroke then
				fadeStroke(1) -- fade out instead of popping (the tooltip frame toggles this on every hover)
			end
			-- Separated outline — snap to rest
			if outlineStroke then
				cancelOutlineTweens()
				outlineStroke.Transparency = sbo.restTransparency
				outlineStroke.BorderOffset = UDim.new(0, 0)
			end
		else
			if stroke then
				fadeStroke(0)
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
		geometryDirty = true
		if not state then
			setContainerParent(nil)
		end
	end

	function handle.isGlassVisible(): boolean
		return glassVisible
	end

	-- ── Register ──────────────────────────────────────────────────────────
	inst.handle = handle
	activeInstances[guiObject] = inst
	table.insert(instanceList, inst)
	bindRender()

	return handle
end

-- ══════════════════════════════════════════════════════════════════════════════
-- ██ SHARED RENDER STEP
-- ══════════════════════════════════════════════════════════════════════════════

renderStep = function(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local ctx = {
		camera = camera,
		camCF = camera:GetRenderCFrame(),
		viewport = camera.ViewportSize,
		inset = GuiService:GetGuiInset(),
		mouse = UserInputService:GetMouseLocation(),
	}
	-- iterate a snapshot-safe way: instances may be removed (cleanup) while updating
	local i = 1
	while i <= #instanceList do
		local inst = instanceList[i]
		inst.update(ctx, dt)
		if instanceList[i] == inst then
			i += 1
		end
	end
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
--- overrides.mode = "liquid" (default) | "mosaic"; overrides.GlassVisible = false starts with the 3D glass
--- hidden (the stroke/outline still work and the glass parts are never built until it is shown).
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
	if instance then
		instance.handle.setEnabled(state)
	end
end

--- Toggle only the 3D glass rendering. Stroke and outline remain active.
function GlassHandler.setGlassVisible(guiObject: GuiObject, state: boolean)
	local instance = activeInstances[guiObject]
	if instance then
		instance.handle.setGlassVisible(state)
	end
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
	return #instanceList
end

-- ══════════════════════════════════════════════════════════════════════════════
-- ██ TAG AUTO-APPLICATION (one listener per tag, not one per instance)
-- ══════════════════════════════════════════════════════════════════════════════

local function tryApply(v: Instance, tag: string, otherTag: string, create: (GuiObject) -> any)
	if not v:IsA("GuiObject") then
		return
	end
	-- Guard: both tags on the same object → skip (mutual exclusion)
	if CollectionService:HasTag(v, otherTag) then
		warn("[GlassHandler] GuiObject has both LiquidGlass and MosaicGlass tags — skipping:", v:GetFullName())
		return
	end
	create(v :: GuiObject)
end

CollectionService:GetInstanceAddedSignal(LIQUID_TAG):Connect(function(v)
	tryApply(v, LIQUID_TAG, MOSAIC_TAG, GlassHandler.new)
end)
CollectionService:GetInstanceAddedSignal(MOSAIC_TAG):Connect(function(v)
	tryApply(v, MOSAIC_TAG, LIQUID_TAG, GlassHandler.newMosaic)
end)

-- Removing either tag removes the effect
local function onTagRemoved(v: Instance)
	if v:IsA("GuiObject") and activeInstances[v :: GuiObject] then
		GlassHandler.remove(v :: GuiObject)
	end
end
CollectionService:GetInstanceRemovedSignal(LIQUID_TAG):Connect(onTagRemoved)
CollectionService:GetInstanceRemovedSignal(MOSAIC_TAG):Connect(onTagRemoved)

-- Process already-tagged instances at startup
for _, v in ipairs(CollectionService:GetTagged(LIQUID_TAG)) do
	tryApply(v, LIQUID_TAG, MOSAIC_TAG, GlassHandler.new)
end
for _, v in ipairs(CollectionService:GetTagged(MOSAIC_TAG)) do
	tryApply(v, MOSAIC_TAG, LIQUID_TAG, GlassHandler.newMosaic)
end

return GlassHandler
