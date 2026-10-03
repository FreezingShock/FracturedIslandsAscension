-- ============================================================
--  SettingsPageModule (ModuleScript)
--  Place inside: TemporaryMenus
--
--  Refactored: No more settings pages list. Each SettingsGrid
--  button opens directly to the breakdown folder.
--
--  API:
--    init(sharedRefs, settingsMenuFrame)
--    open(pageKey)    — shows breakdown for that settings category
--    close()          — animated navigation away
--    reset()          — instant hard-close
--    navigateBack()   — no-op (controller handles grid return)
-- ============================================================

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")

-- ===================== MODULE STATE =====================
local initialized = false
local isOpen = false

local shared = nil

-- Frame references (set by init)
local settingsMenuFrame = nil
local settingsBreakdown = nil

-- ===================== SETTINGS CONFIG =====================
-- Maps openArg keys to the folder name inside SettingsBreakdown.
-- If a key maps to nil, that category has no breakdown yet.
local SETTINGS_CONFIG = {
	Personal = { label = "Personal", folder = "Personal" },
	Comms = { label = "Communication", folder = "Comms" },
	Gameplay = { label = "Gameplay", folder = "Gameplay" },
	Notifications = { label = "Notifications", folder = "Notifications" },
	Controls = { label = "Controls", folder = "Controls" },
	Audio = { label = "Audio", folder = "Audio" },
}

-- ===================== STATE =====================
local activePageKey = nil
local activeFolder = nil
local bdAnimToken = nil

-- ===================== TWEEN CONFIG =====================
local BD_ENTRANCE_STAGGER = 0.15
local BD_ENTRANCE_DURATION = 0.6
local BD_ENTRANCE_DELAY = 0

local BD_EXIT_STAGGER = 0.1
local BD_EXIT_DURATION = 0.25

local bdEntranceTweenInfo = TweenInfo.new(BD_ENTRANCE_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local bdExitTweenInfo = TweenInfo.new(BD_EXIT_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

-- ===================== POSITION CONSTANTS =====================
local ON_SCREEN = UDim2.fromScale(0, 0)
local OFF_RIGHT = UDim2.fromScale(1.5, 0)

-- ===================== HELPERS =====================
local function getBreakdownFrames(folder)
	if not folder then
		return {}
	end
	local frames = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(frames, child)
		end
	end
	table.sort(frames, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	return frames
end

-- ===================== BREAKDOWN ENTRANCE ANIMATION =====================
local function playBreakdownEntrance(folder)
	if not folder then
		return
	end
	local token = {}
	bdAnimToken = token
	local frames = getBreakdownFrames(folder)

	for _, frame in ipairs(frames) do
		local otb = frame:FindFirstChild("OuterTopBar")
		if otb then
			frame.Visible = true
			otb.Position = OFF_RIGHT
			otb.Visible = true
		end
	end

	for i, frame in ipairs(frames) do
		local otb = frame:FindFirstChild("OuterTopBar")
		if not otb then
			continue
		end
		task.delay(BD_ENTRANCE_DELAY + (i - 1) * BD_ENTRANCE_STAGGER, function()
			if bdAnimToken ~= token then
				return
			end
			TweenService:Create(otb, bdEntranceTweenInfo, { Position = ON_SCREEN }):Play()
		end)
	end
end

-- ===================== SNAP FOLDER HIDDEN =====================
local function snapFolderHidden(folder)
	if not folder then
		return
	end
	for _, frame in ipairs(getBreakdownFrames(folder)) do
		local otb = frame:FindFirstChild("OuterTopBar")
		if otb then
			otb.Position = OFF_RIGHT
			otb.Visible = false
		end
		frame.Visible = false
	end
end

-- ===================== SNAP ALL BREAKDOWNS HIDDEN =====================
local function snapAllHidden()
	bdAnimToken = nil
	if not settingsBreakdown then
		return
	end
	for _, child in ipairs(settingsBreakdown:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Frame") then
			snapFolderHidden(child)
		end
	end
end

-- ===================== MODULE API =====================
local M = {}

function M.init(sharedRefs, frame)
	if initialized then
		return
	end
	initialized = true

	shared = sharedRefs
	settingsMenuFrame = frame

	settingsBreakdown = settingsMenuFrame:WaitForChild("SettingsBreakdown")

	snapAllHidden()

	print("SettingsPageModule: Initialized ✓")
end

function M.open(pageKey)
	isOpen = true
	activePageKey = pageKey
	bdAnimToken = nil

	local config = SETTINGS_CONFIG[pageKey]
	if not config then
		warn("[SettingsPageModule] Unknown pageKey: " .. tostring(pageKey))
		return
	end

	-- Snap everything hidden first (in case a previous breakdown is still visible)
	snapAllHidden()

	-- Resolve the breakdown folder
	local folder = settingsBreakdown:FindFirstChild(config.folder)
	activeFolder = folder

	if not folder then
		warn("[SettingsPageModule] No breakdown folder for: " .. config.folder)
		return
	end

	playBreakdownEntrance(folder)
end

function M.close()
	isOpen = false
	activePageKey = nil
	bdAnimToken = nil

	snapAllHidden()
	activeFolder = nil
end

function M.reset()
	isOpen = false
	activePageKey = nil
	bdAnimToken = nil

	snapAllHidden()
	activeFolder = nil
end

function M.navigateBack()
	-- No internal navigation — controller handles grid return
end

return M
