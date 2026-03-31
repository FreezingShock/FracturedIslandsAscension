-- ============================================================
--  GridMenuModule (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Reusable system for 9×6 icon grids with tooltips, click
--  navigation, and stack-based grid-to-grid traversal.
--
--  Supports TWO grid types:
--
--    LEGACY  – hand-built CanvasGroup frames registered via
--              registerGrid().  Visibility toggled directly.
--              (Existing behavior, unchanged.)
--
--    POOLED  – template folders registered via registerPooledGrid().
--              Content is cloned into a double-buffered pair of
--              CanvasGroups at navigation time, enabling crossfade
--              transitions while reusing a single grid area.
--
--  Both types coexist: legacy grids keep their own frames, pooled
--  grids share the buffer pair.  Hybrid transitions (legacy↔pooled)
--  are handled automatically.
--
--  API:
--    init(sharedRefs, callbacks)
--    initBuffers(bufferA, bufferB, blankSlotTemplate)
--    registerGrid(gridKey, gridFrame, buttonConfigs, options)
--    registerPooledGrid(gridKey, templateFolder, buttonConfigs, options)
--    showRoot(gridKey, animated)
--    navigateToGrid(gridKey)
--    navigateBack()  → true if handled, false if at root
--    hideActiveGrid(animated)
--    showActiveGrid(animated)
--    reset()
--    getActiveGridKey()
--    getGridDepth()
--    getActiveGridFrame()
--    getActiveGridConfig()
--    getGridTitle(gridKey)
--    hasGrid(gridKey)
-- ============================================================

local TweenService = game:GetService("TweenService")

-- ===================== MODULE TABLE (forward-declared) =====================
-- Declared early so local helper functions can reference M.navigateToGrid
-- etc. inside connection callbacks.  Methods are attached further down.
local M = {}

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")

-- ===================== LEGACY GRID STATE =====================
local grids = {} -- gridKey → { frame, buttons, title, buttonConfigs }
local gridStack = {} -- stack of gridKey strings (navigation history)
local activeGrid = nil -- currently visible gridKey (legacy OR pooled)

-- ===================== POOLED GRID STATE =====================
local pooledGrids = {} -- gridKey → { templateFolder, buttonConfigs, blankGroups, itemOrders, title, hooks }

local bufferData = {
	A = { frame = nil, connections = {}, gridKey = nil },
	B = { frame = nil, connections = {}, gridKey = nil },
}
local activeBuffer = "A" -- label of the buffer currently showing pooled content
local blankTemplate = nil -- BlankSlot template for pooled grids
local buffersReady = false

-- ===================== EXTERNAL REFS =====================
local shared = nil
local TooltipModule = nil

-- Callbacks provided by the controller:
--   onNavigateToPage(gridKey, buttonKey, buttonConfig)
--   onCloseMenu()
local callbacks: { [string]: any } = {}

-- ===================== TRANSITION CONFIG =====================
local FADE_OUT_TIME = 0.4
local FADE_IN_TIME = 0.6
local fadeTweenOut = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local fadeTweenIn = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Per-buffer tween tracking (cancel before reuse to avoid races)
local bufferTweens = { A = nil, B = nil }

-- ===================== LEGACY FADE HELPERS =====================

--- Fade out a legacy grid frame, then hide it.
local function fadeOutGrid(frame, instant)
	if instant then
		frame.Visible = false
		frame.GroupTransparency = 0
		return
	end
	local tw = TweenService:Create(frame, fadeTweenOut, { GroupTransparency = 1 })
	tw:Play()
	tw.Completed:Once(function()
		frame.Visible = false
		frame.GroupTransparency = 0
	end)
end

--- Show a legacy grid frame with a quick fade in.
local function fadeInGrid(frame, instant)
	if instant then
		frame.GroupTransparency = 0
		frame.Visible = true
		return
	end
	frame.GroupTransparency = 1
	frame.Visible = true
	TweenService:Create(frame, fadeTweenIn, { GroupTransparency = 0 }):Play()
end

-- ===================== BUFFER HELPERS =====================

local function isPooled(gridKey)
	return pooledGrids[gridKey] ~= nil
end

local function getStandbyLabel()
	return activeBuffer == "A" and "B" or "A"
end

local function cancelBufferTween(label)
	if bufferTweens[label] then
		bufferTweens[label]:Cancel()
		bufferTweens[label] = nil
	end
end

--- Destroy all children of a buffer frame except layout objects.
local function clearBufferChildren(frame)
	local n = 0
	for _, child in ipairs(frame:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
			n += 1
		end
	end
	return n
end

--- Find which buffer label currently holds a given gridKey.
--- Returns "A", "B", or nil.
local function findBufferForGrid(gridKey)
	if bufferData.A.gridKey == gridKey then
		return "A"
	end
	if bufferData.B.gridKey == gridKey then
		return "B"
	end
	return nil
end

-- ===================== DEPOPULATE BUFFER =====================

--- Disconnect connections, call hooks, destroy cloned children.
--- Safe to call on an already-empty buffer (no-op).
local function depopulateBuffer(label)
	local bd = bufferData[label]
	if not bd.gridKey then
		return
	end

	-- Hook: onDepopulate
	local pooled = pooledGrids[bd.gridKey]
	if pooled and pooled.hooks and pooled.hooks.onDepopulate then
		pooled.hooks.onDepopulate()
	end

	-- Disconnect all tracked connections
	local connCount = #bd.connections
	for _, conn in ipairs(bd.connections) do
		conn:Disconnect()
	end
	table.clear(bd.connections)

	-- Destroy cloned children
	local destroyed = clearBufferChildren(bd.frame)

	local oldKey = bd.gridKey
	bd.gridKey = nil

	print(
		"[GridPool] Depopulated "
			.. oldKey
			.. " from buffer "
			.. label
			.. ": "
			.. connCount
			.. " conns, "
			.. destroyed
			.. " instances"
	)
end

-- ===================== POPULATE BUFFER =====================

--- Clone icons from a pooled grid's template folder into a buffer,
--- apply layout orders, fill blank slots, wire all connections.
local function populateBuffer(label, gridKey)
	local bd = bufferData[label]
	local pooled = pooledGrids[gridKey]
	if not pooled then
		warn("[GridPool] populateBuffer: unknown pooled grid '" .. tostring(gridKey) .. "'")
		return
	end

	-- Safety: if this buffer has leftover content, clean it first
	cancelBufferTween(label)
	if bd.gridKey then
		depopulateBuffer(label)
	end
	bd.frame.Visible = false
	bd.frame.GroupTransparency = 0

	-- 1. Clone icons from template folder → parent to buffer
	local clonedButtons = {} -- btnName → GuiButton instance
	for _, template in ipairs(pooled.templateFolder:GetChildren()) do
		local clone = template:Clone()
		clone.Visible = true
		clone.Parent = bd.frame
		if clone:IsA("GuiButton") then
			clonedButtons[clone.Name] = clone
		end
	end

	-- 2. Apply LayoutOrders from itemOrders config
	if pooled.itemOrders then
		for itemName, order in pairs(pooled.itemOrders) do
			local item = bd.frame:FindFirstChild(itemName)
			if item then
				item.LayoutOrder = order
			end
		end
	end

	-- 3. Clone BlankSlots from blankGroups config
	if pooled.blankGroups and blankTemplate then
		for _, group in ipairs(pooled.blankGroups) do
			for _ = 1, group.count do
				local blank = blankTemplate:Clone()
				blank.LayoutOrder = group.layoutOrder
				blank.Visible = true
				blank.Parent = bd.frame
			end
		end
	end

	-- 4. Wire click connections for every mapped button
	for btnKey, btn in pairs(clonedButtons) do
		local cfg = pooled.buttonConfigs[btnKey]
		if not cfg then
			continue
		end

		-- Click handler
		table.insert(
			bd.connections,
			btn.MouseButton1Click:Connect(function()
				local action = cfg.action

				if action == "grid" then
					M.navigateToGrid(cfg.targetGrid)
				elseif action == "page" then
					if callbacks.onNavigateToPage then
						callbacks.onNavigateToPage(gridKey, btnKey, cfg)
					end
				elseif action == "close" then
					if callbacks.onCloseMenu then
						callbacks.onCloseMenu()
					end
				elseif action == "callback" then
					UIClick:Play()
					if cfg.callback then
						cfg.callback()
					end
				else
					-- No action → "coming soon" click
					UIClick:Play()
				end
			end)
		)

		-- Static tooltip
		if cfg.tooltipData then
			table.insert(
				bd.connections,
				btn.MouseEnter:Connect(function()
					UIClick3:Play()
					TooltipModule.show(cfg.tooltipData)
				end)
			)
			table.insert(
				bd.connections,
				btn.MouseLeave:Connect(function()
					TooltipModule.hide("generic")
				end)
			)
		end
	end

	-- 5. Hook: dynamic tooltip wiring (returns extra connections)
	if pooled.hooks and pooled.hooks.onWireTooltips then
		local extraConns = pooled.hooks.onWireTooltips(clonedButtons)
		if extraConns then
			for _, conn in ipairs(extraConns) do
				table.insert(bd.connections, conn)
			end
		end
	end

	-- 6. Hook: post-populate (for page modules that add dynamic content)
	if pooled.hooks and pooled.hooks.onPopulate then
		pooled.hooks.onPopulate(bd.frame)
	end

	bd.gridKey = gridKey

	print("[GridPool] Populated " .. gridKey .. " → buffer " .. label .. ": " .. #bd.connections .. " connections")
end

-- ===================== TRANSITION ENGINE =====================

--- Perform the visual transition between two grids (animated or instant).
--- Handles all four hybrid cases: pooled↔pooled, pooled↔legacy, etc.
--- Does NOT modify gridStack or activeGrid — caller handles that.
local function performTransition(sourceKey, targetKey, animated)
	local srcPooled = sourceKey and isPooled(sourceKey)
	local tgtPooled = isPooled(targetKey)

	-- ── INSTANT (non-animated) ──
	if not animated then
		-- Hide source
		if srcPooled and sourceKey then
			local srcLabel = findBufferForGrid(sourceKey)
			if srcLabel then
				cancelBufferTween(srcLabel)
				bufferData[srcLabel].frame.Visible = false
				bufferData[srcLabel].frame.GroupTransparency = 0
				depopulateBuffer(srcLabel)
			end
		elseif sourceKey and grids[sourceKey] then
			grids[sourceKey].frame.Visible = false
			grids[sourceKey].frame.GroupTransparency = 0
		end

		-- Show target
		if tgtPooled then
			local label = getStandbyLabel()
			populateBuffer(label, targetKey)
			bufferData[label].frame.GroupTransparency = 0
			bufferData[label].frame.Visible = true
			activeBuffer = label
		elseif grids[targetKey] then
			grids[targetKey].frame.GroupTransparency = 0
			grids[targetKey].frame.Visible = true
		end
		return
	end

	-- ── ANIMATED ──

	if srcPooled and tgtPooled then
		-- ▸ POOLED → POOLED: crossfade between buffers
		local oldLabel = findBufferForGrid(sourceKey) or activeBuffer
		local newLabel = (oldLabel == "A") and "B" or "A"

		populateBuffer(newLabel, targetKey)

		local oldFrame = bufferData[oldLabel].frame
		local newFrame = bufferData[newLabel].frame

		cancelBufferTween(oldLabel)
		cancelBufferTween(newLabel)

		-- Start crossfade
		newFrame.GroupTransparency = 1
		newFrame.Visible = true

		local twOut = TweenService:Create(oldFrame, fadeTweenOut, { GroupTransparency = 1 })
		bufferTweens[oldLabel] = twOut
		twOut:Play()
		twOut.Completed:Once(function()
			oldFrame.Visible = false
			oldFrame.GroupTransparency = 0
			bufferTweens[oldLabel] = nil
			depopulateBuffer(oldLabel) -- safe: no-op if already depopulated
		end)

		local twIn = TweenService:Create(newFrame, fadeTweenIn, { GroupTransparency = 0 })
		bufferTweens[newLabel] = twIn
		twIn:Play()
		twIn.Completed:Once(function()
			bufferTweens[newLabel] = nil
		end)

		activeBuffer = newLabel
	elseif srcPooled and not tgtPooled then
		-- ▸ POOLED → LEGACY: fade out buffer, fade in legacy frame
		local oldLabel = findBufferForGrid(sourceKey) or activeBuffer
		local oldFrame = bufferData[oldLabel].frame

		cancelBufferTween(oldLabel)

		local twOut = TweenService:Create(oldFrame, fadeTweenOut, { GroupTransparency = 1 })
		bufferTweens[oldLabel] = twOut
		twOut:Play()
		twOut.Completed:Once(function()
			oldFrame.Visible = false
			oldFrame.GroupTransparency = 0
			bufferTweens[oldLabel] = nil
			depopulateBuffer(oldLabel)
		end)

		if grids[targetKey] then
			fadeInGrid(grids[targetKey].frame, false)
		end
	elseif not srcPooled and tgtPooled then
		-- ▸ LEGACY → POOLED: fade out legacy frame, populate & fade in buffer
		local newLabel = getStandbyLabel()
		populateBuffer(newLabel, targetKey)

		local newFrame = bufferData[newLabel].frame
		cancelBufferTween(newLabel)

		-- Fade out legacy
		if sourceKey and grids[sourceKey] then
			fadeOutGrid(grids[sourceKey].frame, false)
		end

		-- Fade in buffer
		newFrame.GroupTransparency = 1
		newFrame.Visible = true
		local twIn = TweenService:Create(newFrame, fadeTweenIn, { GroupTransparency = 0 })
		bufferTweens[newLabel] = twIn
		twIn:Play()
		twIn.Completed:Once(function()
			bufferTweens[newLabel] = nil
		end)

		activeBuffer = newLabel
	else
		-- ▸ LEGACY → LEGACY: existing behavior (unchanged)
		if sourceKey and grids[sourceKey] then
			fadeOutGrid(grids[sourceKey].frame, false)
		end
		if grids[targetKey] then
			fadeInGrid(grids[targetKey].frame, false)
		end
	end
end

-- ===================== MODULE: INIT =====================

--- Call once from CentralizedMenuController after requiring.
--- sharedRefs = the same table you pass to page modules.
--- cbs = { onNavigateToPage = fn, onCloseMenu = fn }
function M.init(sharedRefs, cbs)
	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule
	callbacks = cbs or {}
end

--- Call once after init() to set up the double-buffer system.
--- bufferA, bufferB = CanvasGroup instances under menuFrame.
--- blankSlot = BlankSlot template from TemporaryMenus.
function M.initBuffers(bA, bB, blankSlot)
	bufferData.A.frame = bA
	bufferData.B.frame = bB
	blankTemplate = blankSlot
	buffersReady = true
	bA.Visible = false
	bB.Visible = false
	print("[GridPool] Buffers initialized ✓")
end

-- ===================== MODULE: REGISTER GRID (LEGACY) =====================

--- Register a hand-built CanvasGroup grid frame.
--- Wires click/tooltip connections permanently at registration time.
--- (Unchanged from original — all legacy grids use this path.)
function M.registerGrid(gridKey, gridFrame, buttonConfigs, options)
	options = options or {}

	local gridData = {
		frame = gridFrame,
		buttonConfigs = buttonConfigs,
		title = options.title or gridKey,
		buttons = {},
	}

	for _, child in ipairs(gridFrame:GetChildren()) do
		if not child:IsA("GuiButton") then
			continue
		end

		local btnKey = child.Name
		local btnConfig = buttonConfigs[btnKey]
		if not btnConfig then
			continue
		end

		gridData.buttons[btnKey] = child

		-- Click
		child.MouseButton1Click:Connect(function()
			local action = btnConfig.action

			if action == "grid" then
				M.navigateToGrid(btnConfig.targetGrid)
			elseif action == "page" then
				if callbacks.onNavigateToPage then
					callbacks.onNavigateToPage(gridKey, btnKey, btnConfig)
				end
			elseif action == "close" then
				if callbacks.onCloseMenu then
					callbacks.onCloseMenu()
				end
			elseif action == "callback" then
				UIClick:Play()
				if btnConfig.callback then
					btnConfig.callback()
				end
			else
				UIClick:Play()
			end
		end)

		-- Tooltip
		if btnConfig.tooltipData then
			child.MouseEnter:Connect(function()
				UIClick3:Play()
				TooltipModule.show(btnConfig.tooltipData)
			end)
			child.MouseLeave:Connect(function()
				TooltipModule.hide("generic")
			end)
		end
	end

	grids[gridKey] = gridData
	gridFrame.Visible = false
end

-- ===================== MODULE: REGISTER POOLED GRID =====================

--- Register a pooled grid backed by a template folder.
--- No connections are wired at registration — they are created
--- dynamically each time the grid is populated into a buffer.
---
--- options fields:
---   title         : string — top bar title
---   blankGroups   : {{ layoutOrder = n, count = n }, ...}
---   itemOrders    : { [childName] = layoutOrder, ... }
---   onPopulate    : function(bufferFrame)  — called after populate
---   onDepopulate  : function()             — called before depopulate
---   onWireTooltips: function(clonedButtons) → RBXScriptConnection[]
function M.registerPooledGrid(gridKey, templateFolder, buttonConfigs, options)
	options = options or {}
	pooledGrids[gridKey] = {
		templateFolder = templateFolder,
		buttonConfigs = buttonConfigs,
		blankGroups = options.blankGroups,
		itemOrders = options.itemOrders,
		title = options.title or gridKey,
		hooks = {
			onPopulate = options.onPopulate,
			onDepopulate = options.onDepopulate,
			onWireTooltips = options.onWireTooltips,
		},
	}
	print("[GridPool] Registered pooled grid: " .. gridKey .. " ✓")
end

-- ===================== MODULE: SHOW ROOT =====================

--- Reset the grid stack and display the root grid.
--- Handles both legacy and pooled root grids.
function M.showRoot(gridKey, animated)
	-- Hide all legacy grids
	for _, data in pairs(grids) do
		data.frame.Visible = false
		data.frame.GroupTransparency = 0
	end

	-- Clean up both buffers
	if buffersReady then
		cancelBufferTween("A")
		cancelBufferTween("B")
		depopulateBuffer("A")
		depopulateBuffer("B")
		bufferData.A.frame.Visible = false
		bufferData.A.frame.GroupTransparency = 0
		bufferData.B.frame.Visible = false
		bufferData.B.frame.GroupTransparency = 0
	end

	gridStack = {}
	activeGrid = gridKey

	if isPooled(gridKey) then
		-- Pooled root: populate buffer A and show
		activeBuffer = "A"
		populateBuffer("A", gridKey)
		if animated then
			fadeInGrid(bufferData.A.frame, false)
		else
			bufferData.A.frame.GroupTransparency = 0
			bufferData.A.frame.Visible = true
		end
	else
		-- Legacy root
		local data = grids[gridKey]
		if not data then
			warn("GridMenuModule: Unknown root grid '" .. tostring(gridKey) .. "'")
			return
		end
		if animated then
			fadeInGrid(data.frame, false)
		else
			data.frame.Visible = true
			data.frame.GroupTransparency = 0
		end
	end
end

-- ===================== MODULE: NAVIGATE TO GRID =====================

--- Push the current grid onto the stack and transition to a new grid.
--- Handles all four hybrid cases automatically.
function M.navigateToGrid(gridKey)
	-- Validate target
	local tgtPooled = isPooled(gridKey)
	local tgtLegacy = grids[gridKey] ~= nil
	if not tgtPooled and not tgtLegacy then
		warn("GridMenuModule: Unknown grid '" .. tostring(gridKey) .. "'")
		return
	end

	TooltipModule.forceHide()

	-- Push current onto stack
	if activeGrid then
		table.insert(gridStack, activeGrid)
	end

	local sourceKey = activeGrid
	activeGrid = gridKey

	-- Perform visual transition
	performTransition(sourceKey, gridKey, true)

	-- Update title
	local title = tgtPooled and pooledGrids[gridKey].title or grids[gridKey].title
	shared.typewriteTitle(title)
	UIClick:Play()
end

-- ===================== MODULE: NAVIGATE BACK =====================

--- Pop one grid level.  Returns true if handled, false if at root.
function M.navigateBack()
	if #gridStack == 0 then
		return false
	end

	TooltipModule.forceHide()

	local sourceKey = activeGrid

	-- Pop
	activeGrid = table.remove(gridStack)

	-- Perform visual transition
	performTransition(sourceKey, activeGrid, true)

	-- Update title
	local title
	if isPooled(activeGrid) then
		title = pooledGrids[activeGrid].title
	elseif grids[activeGrid] then
		title = grids[activeGrid].title
	else
		title = activeGrid
	end
	shared.typewriteTitle(title)
	UIClick:Play()
	return true
end

-- ===================== MODULE: HIDE / SHOW ACTIVE GRID =====================

--- Hide the currently active grid (used when navigating to a page).
--- Does NOT modify the stack.
function M.hideActiveGrid(animated)
	if not activeGrid then
		return
	end
	if isPooled(activeGrid) then
		local label = findBufferForGrid(activeGrid)
		if label then
			if animated then
				fadeOutGrid(bufferData[label].frame, false)
			else
				bufferData[label].frame.Visible = false
				bufferData[label].frame.GroupTransparency = 0
			end
		end
	else
		local data = grids[activeGrid]
		if data then
			fadeOutGrid(data.frame, not animated)
		end
	end
end

--- Re-show the currently active grid (used when returning from a page).
function M.showActiveGrid(animated)
	if not activeGrid then
		return
	end
	if isPooled(activeGrid) then
		local label = findBufferForGrid(activeGrid)
		if label then
			if animated then
				fadeInGrid(bufferData[label].frame, false)
			else
				bufferData[label].frame.Visible = true
				bufferData[label].frame.GroupTransparency = 0
			end
		end
	else
		local data = grids[activeGrid]
		if data then
			if animated then
				fadeInGrid(data.frame, false)
			else
				data.frame.Visible = true
				data.frame.GroupTransparency = 0
			end
		end
	end
end

-- ===================== MODULE: RESET =====================

--- Instant hard-reset.  Hide everything, clear stack, depopulate buffers.
function M.reset()
	gridStack = {}
	activeGrid = nil

	for _, data in pairs(grids) do
		data.frame.Visible = false
		data.frame.GroupTransparency = 0
	end

	if buffersReady then
		cancelBufferTween("A")
		cancelBufferTween("B")
		depopulateBuffer("A")
		depopulateBuffer("B")
		bufferData.A.frame.Visible = false
		bufferData.A.frame.GroupTransparency = 0
		bufferData.B.frame.Visible = false
		bufferData.B.frame.GroupTransparency = 0
		activeBuffer = "A"
	end
end

-- ===================== MODULE: QUERIES =====================

function M.getActiveGridKey()
	return activeGrid
end

function M.getGridDepth()
	return #gridStack
end

--- Returns the frame instance of the currently active grid.
--- For pooled grids, returns the buffer CanvasGroup holding its content.
--- For legacy grids, returns the registered CanvasGroup frame.
function M.getActiveGridFrame()
	if not activeGrid then
		return nil
	end
	if isPooled(activeGrid) then
		local label = findBufferForGrid(activeGrid)
		return label and bufferData[label].frame or nil
	end
	local data = grids[activeGrid]
	return data and data.frame or nil
end

function M.getActiveGridConfig()
	if not activeGrid then
		return nil
	end
	if isPooled(activeGrid) then
		return pooledGrids[activeGrid].buttonConfigs
	end
	local data = grids[activeGrid]
	return data and data.buttonConfigs or nil
end

--- Get the title of a registered grid (legacy or pooled).
function M.getGridTitle(gridKey)
	if isPooled(gridKey) then
		return pooledGrids[gridKey].title
	end
	local data = grids[gridKey]
	return data and data.title or gridKey
end

--- Check if a grid key has been registered (legacy or pooled).
function M.hasGrid(gridKey)
	return grids[gridKey] ~= nil or pooledGrids[gridKey] ~= nil
end

--- Dynamically update a grid's title before navigating to it.
--- Works for both legacy and pooled grids.
--- Call this BEFORE navigateToGrid() when the title depends on
--- context (e.g. which skill was clicked to open ProfileMenu2).
function M.setGridTitle(gridKey, title)
	if pooledGrids[gridKey] then
		pooledGrids[gridKey].title = title
	elseif grids[gridKey] then
		grids[gridKey].title = title
	end
end

print("GridMenuModule: Loaded ✓")
return M
