-- ============================================================
--  GridMenuModule (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Reusable system that wires any hand-built 8×6 grid frame
--  with tooltips, click navigation, and stack-based grid-to-grid
--  traversal.  Every grid is registered once via registerGrid(),
--  and the module handles visibility, in-place swapping, and
--  delegation back to the controller for page/close actions.
--
--  API:
--    init(sharedRefs, callbacks)
--    registerGrid(gridKey, gridFrame, buttonConfigs, options)
--    showRoot(gridKey, animated)
--    navigateToGrid(gridKey)
--    navigateBack()  → true if handled, false if at root
--    reset()
--    getActiveGridKey()
--    getGridDepth()
--    getActiveGridFrame()
--    getActiveGridConfig()
-- ============================================================

local TweenService = game:GetService("TweenService")

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")

-- ===================== STATE =====================
local grids = {} -- gridKey → { frame, buttons, title, buttonConfigs }
local gridStack = {} -- stack of gridKeys (parent grids)
local activeGrid = nil -- currently visible gridKey

-- ===================== EXTERNAL REFS =====================
local shared = nil
local TooltipModule = nil

-- Callbacks provided by the controller:
--   onNavigateToPage(gridKey, buttonKey, buttonConfig)
--   onCloseMenu()
local callbacks: { [string]: any } = {}

-- ===================== TRANSITION CONFIG =====================
-- In-place swap: brief crossfade.  Adjust to taste.
local FADE_OUT_TIME = 0.4
local FADE_IN_TIME = 0.6
local fadeTweenOut = TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local fadeTweenIn = TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- ===================== HELPERS =====================

--- Fade out a grid frame, then hide it.
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
		frame.GroupTransparency = 0 -- reset for next show
	end)
end

--- Show a grid frame with a quick fade in.
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

-- ===================== MODULE =====================
local M = {}

--- Call once from CentralizedMenuController after requiring.
--- sharedRefs = the same table you pass to page modules.
--- cbs = { onNavigateToPage = fn, onCloseMenu = fn }
function M.init(sharedRefs, cbs)
	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule
	callbacks = cbs or {}
end

-- ===================== REGISTER GRID =====================
--- Register a hand-built grid frame so the module wires all its buttons.
---
--- gridKey       : unique string identifier (e.g. "NexusMenu", "CraftingGrid")
--- gridFrame     : the Frame instance inside menuFrame
--- buttonConfigs : table mapping child button Name → config
--- options       : { title = string }
---
--- buttonConfig fields:
---   tooltipData   : { title, desc, click, stats? }  — hover tooltip
---   action        : "page" | "grid" | "close" | "callback" | nil
---   -- For action == "page":
---     module      : the page module reference
---     menuTitle   : string shown in top bar
---     menuChild   : string name of the page frame inside menuFrame
---     topBarSetup : optional function(sharedRefs) for page-specific UI
---   -- For action == "grid":
---     targetGrid  : gridKey string of the destination grid
---   -- For action == "callback":
---     callback    : function()
---   -- For action == nil / missing:
---     Treated as "coming soon" — click plays sound, does nothing.

function M.registerGrid(gridKey, gridFrame, buttonConfigs, options)
	options = options or {}

	local gridData = {
		frame = gridFrame,
		buttonConfigs = buttonConfigs,
		title = options.title or gridKey,
		buttons = {}, -- btnKey → GuiButton instance
	}

	-- Wire every GuiButton child that has a matching config entry.
	for _, child in ipairs(gridFrame:GetChildren()) do
		if not child:IsA("GuiButton") then
			continue
		end

		local btnKey = child.Name
		local btnConfig = buttonConfigs[btnKey]
		if not btnConfig then
			continue
		end -- BlankSlot or unmapped button

		gridData.buttons[btnKey] = child

		-- ── Click ──
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
				-- No action defined → "coming soon" click
				UIClick:Play()
			end
		end)

		-- ── Tooltip ──
		if btnConfig.tooltipData then
			child.MouseEnter:Connect(function()
				UIClick3:Play()
				TooltipModule.show(btnConfig.tooltipData)
			end)
			child.MouseLeave:Connect(function()
				TooltipModule.hide()
			end)
		end
	end

	grids[gridKey] = gridData

	-- Start hidden; showRoot() makes the root visible.
	gridFrame.Visible = false
end

-- ===================== SHOW ROOT =====================
--- Reset the grid stack and display the root grid.
--- Called on menu open and on hold-to-return.
function M.showRoot(gridKey, animated)
	-- Hide all grids
	for _, data in pairs(grids) do
		data.frame.Visible = false
		data.frame.GroupTransparency = 0
	end

	gridStack = {}
	activeGrid = gridKey

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

-- ===================== NAVIGATE TO GRID =====================
--- Push the current grid onto the stack and swap to a new grid in-place.
function M.navigateToGrid(gridKey)
	local data = grids[gridKey]
	if not data then
		warn("GridMenuModule: Unknown grid '" .. tostring(gridKey) .. "'")
		return
	end

	-- Push current onto stack
	if activeGrid then
		table.insert(gridStack, activeGrid)
	end

	-- Swap
	local oldData = grids[activeGrid]
	activeGrid = gridKey

	if oldData then
		fadeOutGrid(oldData.frame, false)
	end
	fadeInGrid(data.frame, false)

	-- Update title + return button
	shared.typewriteTitle(data.title)
	if #gridStack > 0 then
		shared.showReturnButton()
	end

	-- Hide page-specific top bar elements when on a sub-grid
	shared.hideSkillAverage()
	shared.hideRomanToggle()

	UIClick:Play()
end

-- ===================== NAVIGATE BACK =====================
--- Pop one grid level.  Returns true if it handled the back,
--- false if we're already at root (caller should close or no-op).
function M.navigateBack()
	if #gridStack == 0 then
		return false
	end

	local oldData = grids[activeGrid]

	-- Pop
	activeGrid = table.remove(gridStack)
	local newData = grids[activeGrid]

	-- Swap
	if oldData then
		fadeOutGrid(oldData.frame, false)
	end
	if newData then
		fadeInGrid(newData.frame, false)
		shared.typewriteTitle(newData.title)
	end

	-- Hide return button if back at root
	if #gridStack == 0 then
		shared.hideReturnButton()
	end

	UIClick:Play()
	return true
end

-- ===================== HIDE ACTIVE GRID =====================
--- Hides the currently active grid (used when navigating to a page).
--- Does NOT modify the stack — the grid stays as the "parent" context.
function M.hideActiveGrid(animated)
	if not activeGrid then
		return
	end
	local data = grids[activeGrid]
	if not data then
		return
	end
	fadeOutGrid(data.frame, not animated)
end

-- ===================== SHOW ACTIVE GRID =====================
--- Re-shows the currently active grid (used when returning from a page).
function M.showActiveGrid(animated)
	if not activeGrid then
		return
	end
	local data = grids[activeGrid]
	if not data then
		return
	end
	if animated then
		fadeInGrid(data.frame, false)
	else
		data.frame.Visible = true
		data.frame.GroupTransparency = 0
	end
end

-- ===================== RESET =====================
--- Instant hard-reset.  Hide everything, clear stack.
function M.reset()
	gridStack = {}
	activeGrid = nil
	for _, data in pairs(grids) do
		data.frame.Visible = false
		data.frame.GroupTransparency = 0
	end
end

-- ===================== QUERIES =====================
function M.getActiveGridKey()
	return activeGrid
end

function M.getGridDepth()
	return #gridStack
end

function M.getActiveGridFrame()
	if activeGrid and grids[activeGrid] then
		return grids[activeGrid].frame
	end
	return nil
end

function M.getActiveGridConfig()
	if activeGrid and grids[activeGrid] then
		return grids[activeGrid].buttonConfigs
	end
	return nil
end

--- Get the title of a registered grid.
function M.getGridTitle(gridKey)
	local data = grids[gridKey]
	return data and data.title or gridKey
end

--- Check if a grid key has been registered.
function M.hasGrid(gridKey)
	return grids[gridKey] ~= nil
end

print("GridMenuModule: Loaded ✓")
return M
