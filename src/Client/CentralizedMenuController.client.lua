-- ============================================================
--  CentralizedMenuController (LocalScript)
--  StarterPlayerScripts
--
--  UPDATED: Now uses GridMenuModule for all grid wiring and
--  stack-based grid-to-grid navigation.  NexusMenu is registered
--  as the root grid.  Sub-grids swap in-place; page modules
--  still slide left/right as before.
-- ============================================================

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- ← CHANGED: added

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")
local UIIn = workspace:WaitForChild("UISounds"):WaitForChild("In")
local UIOut = workspace:WaitForChild("UISounds"):WaitForChild("Out")

-- ===================== GUI REFERENCES =====================
local CentralizedMenu = playerGui:WaitForChild("CentralizedAscensionMenu")
local BoundingBox = CentralizedMenu:WaitForChild("BoundingBox") -- ← CHANGED: was script.Parent
local outerFrame = BoundingBox:WaitForChild("outerFrame")
local innerFrame = outerFrame:WaitForChild("innerFrame")
local menuFrame = innerFrame:WaitForChild("Menu")
local NexusMenu = menuFrame:WaitForChild("NexusMenu")
local topBarFrame = innerFrame:WaitForChild("topBarFrame")
local menuTitleLabel = topBarFrame:WaitForChild("MenuTitleLabel")
local returnBox = topBarFrame:WaitForChild("returnBox")
local returnButton = returnBox:WaitForChild("returnButton")
local romantonumButton = topBarFrame:WaitForChild("romantonumButton")
local skillAverageFrame = topBarFrame:WaitForChild("skillAverageFrame")
local searchBoxOuter = topBarFrame:WaitForChild("searchBoxOuter")

local TemporaryMenus = CentralizedMenu:WaitForChild("TemporaryMenus") -- stays: BlankSlot lives here
local Sidebar = playerGui:WaitForChild("Sidebar")
local SidebarBB = Sidebar:WaitForChild("SidebarBB")
local NexusBtn = SidebarBB:WaitForChild("Nexus")

-- ===================== MODULES =====================
local Modules = ReplicatedStorage:WaitForChild("Modules") -- ← CHANGED: added

local TooltipModule = require(Modules:WaitForChild("TooltipModule")) :: any -- ←  CHANGED
local GridMenuModule = require(Modules:WaitForChild("GridMenuModule")) :: any -- ← CHANGED
local SkillsPageModule = require(Modules:WaitForChild("SkillsPageModule")) :: any -- ← CHANGED
local ProfilePageModule = require(Modules:WaitForChild("ProfilePageModule")) :: any -- ← CHANGED
local SettingsPageModule = require(Modules:WaitForChild("SettingsPageModule")) :: any -- ← CHANGED
local StatisticsPageModule = require(Modules:WaitForChild("StatisticsPageModule")) :: any
local CollectionsPageModule = require(Modules:WaitForChild("CollectionsPageModule")) :: any
local MenuBridge = require(Modules:WaitForChild("MenuBridge")) :: any

local Lighting = game:GetService("Lighting")
local TraceRouteService = game:GetService("TraceRouteService")

-- ===================== TWEEN CONFIG =====================
local TWEEN_TIME = 0.5
local TWEEN_STYLE = Enum.EasingStyle.Quint
local TWEEN_DIR = Enum.EasingDirection.Out
local tweenInfo = TweenInfo.new(TWEEN_TIME, TWEEN_STYLE, TWEEN_DIR)

local SLIDE_ON = UDim2.new(0, 0, 0, 0)
local SLIDE_LEFT = UDim2.fromScale(-1.1, 0)
local SLIDE_RIGHT = UDim2.fromScale(1.1, 0)

local RETURN_HIDDEN = UDim2.new(1, -205, -1, 4)
local RETURN_VISIBLE = UDim2.new(1, -205, 0, 4)

local SKILLAVG_VISIBLE = UDim2.new(1, -205, 0, 4)
local SKILLAVG_HIDDEN = UDim2.new(1, -205, -1, 4)

local SEARCH_VISIBLE = UDim2.new(1, -205, 0, 4)
local SEARCH_HIDDEN = UDim2.new(1, -205, -1, 4)

local PROGRESS_EMPTY = UDim2.fromScale(0, 1)
local PROGRESS_FULL = UDim2.fromScale(1, 1)

local SIDEBAR_VISIBLE = UDim2.new(0, 10, 0.5, 0)
local SIDEBAR_HIDDEN = UDim2.new(0, -70, 0.5, 0)
local sidebarTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local sidebarHideTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local MENU_OPEN = UDim2.fromScale(0.5, 0.5)
local MENU_CLOSED = UDim2.fromScale(0.5, -0.5)
local menuTweenInfo = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, TWEEN_DIR)

-- ===================== INVENTORY PANEL REF =====================
local inventoryPanel = innerFrame:WaitForChild("Inventory")

-- ===================== STATE =====================
local menuOpen = false
local openMode = nil -- nil | "inventory" | "full"
local navStack = {}
local activeTween = nil
local returnHoldProgress = 0
local progressTween = nil
local sidebarVisible = true
local sidebarActiveTween = nil

-- ===================== BLUR =====================
local blur = Lighting:FindFirstChildOfClass("BlurEffect")
if not blur then
	blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting
end
blur.Size = 0

local blurTween = nil
local BLUR_SIZE = 18
local blurTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local function tweenBlur(targetSize)
	if blurTween then
		blurTween:Cancel()
		blurTween = nil
	end
	blurTween = TweenService:Create(blur, blurTweenInfo, { Size = targetSize })
	blurTween:Play()
end

-- ===================== RETURN BUTTON HOLD =====================
local HOLD_THRESHOLD = 0.5
local returnPressTime = nil
local returnHeld = false
local returnDebounce = false
local RETURN_DEBOUNCE_TIME = 1

-- ===================== ROOT GRID KEY =====================
local ROOT_GRID = "NexusMenu"

-- ===================== TWEEN HELPERS =====================
local function tweenObject(object, targetProps, info)
	local tw = TweenService:Create(object, info or tweenInfo, targetProps)
	tw:Play()
	return tw
end

local function _snapPosition(object, pos)
	object.Position = pos
end

local function cancelSidebarTween()
	if sidebarActiveTween then
		sidebarActiveTween:Cancel()
		sidebarActiveTween = nil
	end
end

local function showSidebar()
	cancelSidebarTween()
	sidebarVisible = true
	sidebarActiveTween = TweenService:Create(SidebarBB, sidebarTweenInfo, { Position = SIDEBAR_VISIBLE })
	sidebarActiveTween:Play()
end

local function hideSidebar()
	cancelSidebarTween()
	sidebarVisible = false
	sidebarActiveTween = TweenService:Create(SidebarBB, sidebarHideTweenInfo, { Position = SIDEBAR_HIDDEN })
	sidebarActiveTween:Play()
end

-- ===================== TYPEWRITER (title label) =====================
local titleTypewriteToken = nil

local function typewriteTitle(text, speed)
	speed = speed or 0.03
	local token = {}
	titleTypewriteToken = token
	menuTitleLabel.Text = text
	menuTitleLabel.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		for i = 1, length do
			if titleTypewriteToken ~= token then
				return
			end
			menuTitleLabel.MaxVisibleGraphemes = i
			task.wait(speed)
		end
		menuTitleLabel.MaxVisibleGraphemes = -1
		if titleTypewriteToken == token then
			titleTypewriteToken = nil
		end
	end)
end

local function setTitleInstant(text)
	titleTypewriteToken = nil
	menuTitleLabel.Text = text
	menuTitleLabel.MaxVisibleGraphemes = -1
end

-- ===================== TOP BAR ELEMENT HELPERS =====================
local function showReturnButton()
	tweenObject(returnBox, { Position = RETURN_VISIBLE })
end

local function hideReturnButton()
	tweenObject(returnBox, { Position = RETURN_HIDDEN })
end

local function showSkillAverage()
	tweenObject(skillAverageFrame, { Position = SKILLAVG_VISIBLE })
end

local function hideSkillAverage()
	tweenObject(skillAverageFrame, { Position = SKILLAVG_HIDDEN })
end

local function showRomanToggle()
	romantonumButton.Visible = true
end

local function hideRomanToggle()
	romantonumButton.Visible = false
end

local function showSearchBox()
	tweenObject(searchBoxOuter, { Position = SEARCH_VISIBLE })
end

local function hideSearchBox()
	tweenObject(searchBoxOuter, { Position = SEARCH_HIDDEN })
end

-- ===================== TEMPORARY MENU FRAMES =====================
local menuChildFrames = {}

-- ===================== NAVIGATION HELPERS =====================
local function currentNav()
	return navStack[#navStack]
end

local function navDepth()
	return #navStack
end

-- ===================== BUTTON CONFIGS =====================
local NEXUS_BUTTONS = {
	Skills = {
		tooltipData = {
			title = '<font color="#FFFF55"><b>Your Skills</b></font>',
			desc = '<font color="#AAAAAA">View your Skill progression and rewards.</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "grid",
		targetGrid = "SkillsGrid",
		menuTitle = "Your Skills",
		menuChild = "SkillsMenu",
	},
	Profile = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Your Profile</b></font>',
			desc = '<font color="#AAAAAA">View your equipment, playtime, and other stats.</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "page",
		module = ProfilePageModule,
		menuTitle = "Your Profile",
		menuChild = "ProfileMenu",
		topBarSetup = function()
			hideSkillAverage()
			hideRomanToggle()
			showSearchBox()
		end,
	},
	Settings = {
		tooltipData = {
			title = '<font color="#FFFFFF"><b>Settings</b></font>',
			desc = '<font color="#AAAAAA">View and edit your settings.</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "grid",
		targetGrid = "SettingsGrid",
		menuTitle = "Settings",
		menuChild = "SettingsMenu",
	},
	AethericNexus = {
		tooltipData = {
			title = '<font color="#FF55FF"><b>Aetheric Nexus</b></font>',
			desc = '<font color="#AAAAAA">Access your aetheric core and view your stats, playtime, and more.</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = nil,
	},
	Bank = {
		tooltipData = {
			title = '<font color="#00AA00"><b>Bank</b></font>',
			desc = '<font color="#AAAAAA">Store and manage your coins and valuables.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	BoosterOil = {
		tooltipData = {
			title = '<font color="#FFAA00"><b>Booster Oil</b></font>',
			desc = '<font color="#AAAAAA">Apply booster oils to enhance your stats temporarily.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	CalendarEvents = {
		tooltipData = {
			title = '<font color="#00AAAA"><b>Calendar Events</b></font>',
			desc = '<font color="#AAAAAA">View upcoming and active events.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	Collections = {
		tooltipData = {
			title = '<font color="#55FFFF"><b>Collections</b></font>',
			desc = '<font color="#AAAAAA">Track your collected items and achievements.</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "grid",
		targetGrid = "CollectionsGrid",
	},
	CraftingMenu = {
		tooltipData = {
			title = '<font color="#FFAA00"><b>Crafting Menu</b></font>',
			desc = '<font color="#AAAAAA">Craft gear, accessories, and tools.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	Milestones = {
		tooltipData = {
			title = '<font color="#AA00AA"><b>Milestones</b></font>',
			desc = '<font color="#AAAAAA">View your milestone progress and rewards.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	Statistics = {
		tooltipData = {
			title = '<font color="#AA0000"><b>Statistics</b></font>',
			desc = '<font color="#AAAAAA">View detailed gameplay statistics.</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "grid",
		targetGrid = "StatisticsGrid",
	},
	QuestLog = {
		tooltipData = {
			title = '<font color="#FFFF55"><b>Quest Log</b></font>',
			desc = '<font color="#AAAAAA">Track active and completed quests.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	RecipeBook = {
		tooltipData = {
			title = '<font color="#5555FF"><b>Recipe Book</b></font>',
			desc = '<font color="#AAAAAA">Browse crafting recipes you have discovered.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	WarpMap = {
		tooltipData = {
			title = '<font color="#5555FF"><b>Warp Map</b></font>',
			desc = '<font color="#AAAAAA">Teleport to discovered locations.</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
		action = nil,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = '<font color="#AAAAAA">Click to return to the game.</font>',
			click = '<font color="#FFFF55">Click to close!</font>',
		},
		action = "close",
	},
}

local COLLECTION_BUTTONS = {
	FarmingCollections = {
		tooltipData = {
			title = '<font color="#FFAA00"><b>Farming</b></font><font color="#55FF55"> Collections</font>',
			desc = '<font color="#AAAAAA">View your Farming collections!</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "callback",
		callback = function()
			CollectionsPageModule.openSkill("Farming")
			GridMenuModule.navigateToGrid("CollectionsMenu2")
			typewriteTitle("Farming Collections")
		end,
	},
	ForagingCollections = {
		tooltipData = {
			title = '<font color="#00AA00"><b>Foraging</b></font><font color="#55FF55"> Collections</font>',
			desc = '<font color="#AAAAAA">View your Foraging collections!</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "callback",
		callback = function()
			CollectionsPageModule.openSkill("Foraging")
			GridMenuModule.navigateToGrid("CollectionsMenu2")
			typewriteTitle("Foraging Collections")
		end,
	},
	FishingCollections = {
		tooltipData = {
			title = '<font color="#00AAAA"><b>Fishing</b></font><font color="#55FF55"> Collections</font>',
			desc = '<font color="#AAAAAA">View your Fishing collections!</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
	},
	MiningCollections = {
		tooltipData = {
			title = '<font color="#5555FF"><b>Mining</b></font><font color="#55FF55"> Collections</font>',
			desc = '<font color="#AAAAAA">View your Mining collections!</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
	},
	CombatCollections = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Combat</b></font><font color="#55FF55"> Collections</font>',
			desc = '<font color="#AAAAAA">View your Combat collections!</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
	},
	GeneralCollections = {
		tooltipData = {
			title = '<font color="#FFFF55"><b>General</b></font><font color="#55FF55"> Collections</font>',
			desc = '<font color="#AAAAAA">View your General collections!</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "callback",
		callback = function()
			CollectionsPageModule.openSkill("General")
			GridMenuModule.navigateToGrid("CollectionsMenu2")
			typewriteTitle("General Collections")
		end,
	},
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = "",
			click = "",
		},
		action = "close",
	},
}

local COLLECTION_MENU2_BUTTONS = {
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			CollectionsPageModule.closeMenu2()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = "",
			click = "",
		},
		action = "close",
	},
}

local COLLECTION_MENU3_BUTTONS = {
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			CollectionsPageModule.closeMenu3()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = "",
			click = "",
		},
		action = "close",
	},
}

local STATISTICS_BUTTONS = {
	FarmingStatistics = {
		tooltipData = {
			title = '<font color="#FFAA00"><b>Farming</b></font><font color="#FFFF55"> Statistics</font>',
			desc = '<font color="#AAAAAA">View your Farming statistics!</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "callback",
		callback = function()
			StatisticsPageModule.openSkill("Farming")
			GridMenuModule.navigateToGrid("StatisticsMenu2")
			typewriteTitle("Farming Statistics")
		end,
	},
	ForagingStatistics = {
		tooltipData = {
			title = '<font color="#00AA00"><b>Foraging</b></font><font color="#FFFF55"> Statistics</font>',
			desc = '<font color="#AAAAAA">View your Foraging statistics!</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "callback",
		callback = function()
			StatisticsPageModule.openSkill("Foraging")
			GridMenuModule.navigateToGrid("StatisticsMenu2")
			typewriteTitle("Foraging Statistics")
		end,
	},
	FishingStatistics = {
		tooltipData = {
			title = '<font color="#00AAAA"><b>Fishing</b></font><font color="#FFFF55"> Statistics</font>',
			desc = '<font color="#AAAAAA">View your Fishing statistics!</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
	},
	MiningStatistics = {
		tooltipData = {
			title = '<font color="#5555FF"><b>Mining</b></font><font color="#FFFF55"> Statistics</font>',
			desc = '<font color="#AAAAAA">View your Mining statistics!</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
	},
	GeneralStatistics = {
		tooltipData = {
			title = '<font color="#FFFF55"><b>General</b></font><font color="#FFFF55"> Statistics</font>',
			desc = '<font color="#AAAAAA">View your currency and general statistics!</font>',
			click = '<font color="#FFFF55">Click to view!</font>',
		},
		action = "callback",
		callback = function()
			StatisticsPageModule.openSkill("General")
			GridMenuModule.navigateToGrid("StatisticsMenu2")
			typewriteTitle("General Statistics")
		end,
	},
	CombatStatistics = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Combat</b></font><font color="#FFFF55"> Statistics</font>',
			desc = '<font color="#AAAAAA">View your Combat statistics!</font>',
			click = '<font color="#555555">Coming Soon</font>',
		},
	},
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = "",
			click = "",
		},
		action = "close",
	},
}

local STATS_MENU2_BUTTONS = {
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			StatisticsPageModule.close()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = "",
			click = "",
		},
		action = "close",
	},
}

local SETTINGS_BUTTONS = {
	PersonalSettings = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Personal</b></font><font color="#FFFFFF"> Settings</font>',
			desc = '<font color="#AAAAAA">General settings related to your experience.</font>',
			click = '<font color="#FFFF55">Click for settings!</font>',
		},
		action = "page",
		module = SettingsPageModule,
		menuTitle = "Personal Settings",
		menuChild = "SettingsMenu",
		openArg = "Personal",
	},
	CommSettings = {
		tooltipData = {
			title = '<font color="#FFFF55"><b>Communication</b></font><font color="#FFFFFF"> Settings</font>',
			desc = '<font color="#AAAAAA">Tweak notifications and invites from other players.</font>',
			click = '<font color="#FFFF55">Click for settings!</font>',
		},
		action = "page",
		module = SettingsPageModule,
		menuTitle = "Communication Settings",
		menuChild = "SettingsMenu",
		openArg = "Comms",
	},
	GameplaySettings = {
		tooltipData = {
			title = '<font color="#5555FF"><b>Gameplay</b></font><font color="#FFFFFF"> Settings</font>',
			desc = '<font color="#AAAAAA">Customize gameplay options and preferred units.</font>',
			click = '<font color="#FFFF55">Click for settings!</font>',
		},
		action = "page",
		module = SettingsPageModule,
		menuTitle = "Gameplay Settings",
		menuChild = "SettingsMenu",
		openArg = "Gameplay",
	},
	NotificationSettings = {
		tooltipData = {
			title = '<font color="#FFAA00"><b>Notification</b></font><font color="#FFFFFF"> Settings</font>',
			desc = '<font color="#AAAAAA">Customize level up notifications and other on-screen logs.</font>',
			click = '<font color="#FFFF55">Click for settings!</font>',
		},
		action = "page",
		module = SettingsPageModule,
		menuTitle = "Notification Settings",
		menuChild = "SettingsMenu",
		openArg = "Notifications",
	},
	ControlSettings = {
		tooltipData = {
			title = '<font color="#00AAAA"><b>Control</b></font><font color="#FFFFFF"> Settings</font>',
			desc = '<font color="#AAAAAA">Change keybinds and custom controllers.</font>',
			click = '<font color="#FFFF55">Click for settings!</font>',
		},
		action = "page",
		module = SettingsPageModule,
		menuTitle = "Control Settings",
		menuChild = "SettingsMenu",
		openArg = "Controls",
	},
	AudioSettings = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Audio</b></font><font color="#FFFFFF"> Settings</font>',
			desc = '<font color="#AAAAAA">Tweak audio and music settings.</font>',
			click = '<font color="#FFFF55">Click for settings!</font>',
		},
		action = "page",
		module = SettingsPageModule,
		menuTitle = "Audio Settings",
		menuChild = "SettingsMenu",
		openArg = "Audio",
	},
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = "",
			click = "",
		},
		action = "close",
	},
}

local SKILLS_BUTTONS = {
	FarmingSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Farming Skill",
		menuChild = "SkillsMenu",
		openArg = "Farming",
		topBarSetup = function()
			showSkillAverage()
			showRomanToggle()
			hideSearchBox()
		end,
	},
	ForagingSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Foraging Skill",
		menuChild = "SkillsMenu",
		openArg = "Foraging",
		topBarSetup = function()
			showSkillAverage()
			showRomanToggle()
			hideSearchBox()
		end,
	},
	FishingSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Fishing Skill",
		menuChild = "SkillsMenu",
		openArg = "Fishing",
		topBarSetup = function()
			showSkillAverage()
			showRomanToggle()
			hideSearchBox()
		end,
	},
	MiningSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Mining Skill",
		menuChild = "SkillsMenu",
		openArg = "Mining",
		topBarSetup = function()
			showSkillAverage()
			showRomanToggle()
			hideSearchBox()
		end,
	},
	CombatSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Combat Skill",
		menuChild = "SkillsMenu",
		openArg = "Combat",
		topBarSetup = function()
			showSkillAverage()
			showRomanToggle()
			hideSearchBox()
		end,
	},
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = {
		tooltipData = {
			title = '<font color="#FF5555"><b>Close Menu</b></font>',
			desc = "",
			click = "",
		},
		action = "close",
	},
}

-- ===================== NEXUS GRID LAYOUT CONFIG =====================
local NEXUS_BLANK_GROUPS = {
	{ layoutOrder = 1, count = 13 },
	{ layoutOrder = 3, count = 5 },
	{ layoutOrder = 11, count = 4 },
	{ layoutOrder = 15, count = 15 },
	{ layoutOrder = 20, count = 2 },
}

local NEXUS_ITEM_ORDERS = {
	Profile = 2,
	Skills = 4,
	Collections = 5,
	Statistics = 6,
	AethericNexus = 7,
	QuestLog = 8,
	CalendarEvents = 9,
	Milestones = 10,
	RecipeBook = 12,
	CraftingMenu = 13,
	Bank = 14,
	WarpMap = 16,
	CloseSlot = 17,
	Settings = 18,
	BoosterOil = 19,
}

local COLLECTION_BLANK_GROUPS = {
	{ layoutOrder = 0, count = 20 },
	{ layoutOrder = 6, count = 6 },
	{ layoutOrder = 8, count = 16 },
	{ layoutOrder = 11, count = 4 },
}
local STATISTICS_BLANK_GROUPS = {
	{ layoutOrder = 0, count = 20 },
	{ layoutOrder = 6, count = 6 },
	{ layoutOrder = 8, count = 16 },
	{ layoutOrder = 11, count = 4 },
}
local SKILL_BLANK_GROUPS = {
	{ layoutOrder = 0, count = 20 },
	{ layoutOrder = 6, count = 23 },
	{ layoutOrder = 10, count = 4 },
}
local SETTINGS_BLANK_GROUPS = {
	{ layoutOrder = 0, count = 10 },
	{ layoutOrder = 2, count = 1 },
	{ layoutOrder = 4, count = 1 },
	{ layoutOrder = 6, count = 1 },
	{ layoutOrder = 8, count = 11 },
	{ layoutOrder = 10, count = 1 },
	{ layoutOrder = 12, count = 1 },
	{ layoutOrder = 14, count = 1 },
	{ layoutOrder = 16, count = 13 },
	{ layoutOrder = 19, count = 4 },
}

-- ===================== GRID BLANK SLOT BUILDER =====================
local blankSlotTemplate = TemporaryMenus:FindFirstChild("BlankSlot")
if not blankSlotTemplate then
	warn("[GridLayout] BlankSlot template NOT FOUND in TemporaryMenus — listing children:")
	for _, child in ipairs(TemporaryMenus:GetChildren()) do
		warn("  →", child.Name, child.ClassName)
	end
end

local function applyGridLayout(gridFrame, blankGroups, itemOrders)
	if not blankSlotTemplate then
		warn("[GridLayout] No BlankSlot template — skipping layout for " .. gridFrame.Name)
		return
	end
	for itemName, order in pairs(itemOrders) do
		local item = gridFrame:FindFirstChild(itemName)
		if item then
			item.LayoutOrder = order
		else
			warn("[GridLayout] Missing child: " .. itemName .. " in " .. gridFrame.Name)
		end
	end
	for _, group in ipairs(blankGroups) do
		for _ = 1, group.count do
			local blank = blankSlotTemplate:Clone()
			blank.LayoutOrder = group.layoutOrder
			blank.Visible = true
			blank.Parent = gridFrame
		end
	end
	print("[GridLayout] Applied " .. gridFrame.Name .. ": spawned blanks ✓")
end

-- ===================== BUILD menuChildFrames =====================
local allMenuChildNames = {}
for _, config in pairs(NEXUS_BUTTONS) do
	if config.menuChild then
		allMenuChildNames[config.menuChild] = true
	end
end
for _, config in pairs(SKILLS_BUTTONS) do
	if config.menuChild then
		allMenuChildNames[config.menuChild] = true
	end
end
for _, config in pairs(SETTINGS_BUTTONS) do
	if config.menuChild then
		allMenuChildNames[config.menuChild] = true
	end
end
for _, config in pairs(STATISTICS_BUTTONS) do
	if config.menuChild then
		allMenuChildNames[config.menuChild] = true
	end
end
for childName in pairs(allMenuChildNames) do
	local frame = menuFrame:FindFirstChild(childName)
	if frame then
		menuChildFrames[childName] = frame
	end
end

-- ===================== NAVIGATE TO ROOT =====================
local function navigateToRoot(animated)
	local nav = currentNav()
	if nav and nav.config and nav.config.module then
		nav.config.module.close()
	end
	for _, frame in pairs(menuChildFrames) do
		if frame.Visible then
			if animated then
				tweenObject(frame, { Position = SLIDE_RIGHT })
				task.delay(TWEEN_TIME, function()
					frame.Visible = false
				end)
			else
				frame.Position = SLIDE_RIGHT
				frame.Visible = false
			end
		end
	end
	menuFrame.Visible = true
	inventoryPanel.Visible = true
	GridMenuModule.showRoot(ROOT_GRID, animated)
	hideReturnButton()
	hideSkillAverage()
	hideRomanToggle()
	hideSearchBox()
	if animated then
		typewriteTitle("Your Nexus Menu")
	else
		setTitleInstant("Your Nexus Menu")
	end
	navStack = {}
end

-- ===================== NAVIGATE TO PAGE =====================
local function navigateToPage(gridKey, buttonKey, buttonConfig, animated)
	returnDebounce = true
	task.delay(RETURN_DEBOUNCE_TIME, function()
		returnDebounce = false
	end)

	if not buttonConfig.menuChild then
		return
	end
	local frame = menuChildFrames[buttonConfig.menuChild]
	if not frame then
		return
	end

	if navDepth() > 0 then
		local oldNav = currentNav()
		if oldNav and oldNav.config and oldNav.config.module then
			oldNav.config.module.close()
		end
		local oldFrame = menuChildFrames[oldNav and oldNav.config and oldNav.config.menuChild]
		if oldFrame then
			oldFrame.Position = SLIDE_RIGHT
			oldFrame.Visible = false
		end
		navStack = {}
	end

	local gridFrame = GridMenuModule.getActiveGridFrame()

	if animated then
		if gridFrame then
			tweenObject(gridFrame, { Position = SLIDE_LEFT })
			task.delay(TWEEN_TIME, function()
				if not gridFrame.Visible then
					return
				end
				gridFrame.Visible = false
			end)
		end
		frame.Visible = true
		frame.Position = SLIDE_RIGHT
		tweenObject(frame, { Position = SLIDE_ON })
		UIClick:Play()
		typewriteTitle(buttonConfig.menuTitle or buttonKey)
	else
		if gridFrame then
			gridFrame.Position = SLIDE_LEFT
			gridFrame.Visible = false
		end
		frame.Position = SLIDE_ON
		frame.Visible = true
		setTitleInstant(buttonConfig.menuTitle or buttonKey)
	end

	navStack = { { key = buttonKey, config = buttonConfig, depth = 1 } }
	showReturnButton()

	if buttonConfig.topBarSetup then
		buttonConfig.topBarSetup()
	else
		hideSkillAverage()
		hideRomanToggle()
		hideSearchBox()
	end

	if buttonConfig.module then
		buttonConfig.module.open(buttonConfig.openArg)
	end
end

-- ===================== NAVIGATE BACK =====================
local function navigateBack()
	local depth = navDepth()

	if depth >= 2 then
		local nav = currentNav()
		if nav.config.module and nav.config.module.navigateBack then
			nav.config.module.navigateBack()
		end
		table.remove(navStack)
	elseif depth == 1 then
		local nav = currentNav()
		if nav.config.module then
			nav.config.module.close()
		end
		local frame = menuChildFrames[nav.config.menuChild]
		if frame then
			tweenObject(frame, { Position = SLIDE_RIGHT })
			task.delay(TWEEN_TIME, function()
				frame.Visible = false
			end)
		end
		local gridFrame = GridMenuModule.getActiveGridFrame()
		if gridFrame then
			gridFrame.Position = SLIDE_LEFT
			gridFrame.Visible = true
			gridFrame.GroupTransparency = 0
			tweenObject(gridFrame, { Position = SLIDE_ON })
		end
		local activeKey = GridMenuModule.getActiveGridKey()
		typewriteTitle(GridMenuModule.getGridTitle(activeKey))
		UIClick:Play()
		navStack = {}

		if GridMenuModule.getGridDepth() > 0 then
			showReturnButton()
		else
			hideReturnButton()
		end

		hideSkillAverage()
		hideRomanToggle()
		hideSearchBox()
	elseif GridMenuModule.getGridDepth() > 0 then
		GridMenuModule.navigateBack()
	end
end

-- ===================== PUSH SUB-PAGE =====================
local function pushSubPage(key)
	local nav = currentNav()
	if not nav then
		return
	end
	table.insert(navStack, {
		key = key,
		config = nav.config,
		depth = nav.depth + 1,
	})
end

-- ===================== OPEN / CLOSE ENTIRE MENU =====================
local function openMenu(mode)
	mode = mode or "full"

	-- Already open — check for mode upgrade
	if menuOpen then
		if openMode == "inventory" and mode == "full" then
			-- Upgrade: show the grid area
			openMode = "full"
			menuFrame.Visible = true
			inventoryPanel.Visible = true
			navigateToRoot(true)
			MenuBridge.notifyStateChanged("full")
		end
		return
	end

	menuOpen = true
	openMode = mode
	tweenBlur(BLUR_SIZE)
	CentralizedMenu.Enabled = true
	hideSidebar()

	if mode == "full" then
		menuFrame.Visible = true
		inventoryPanel.Visible = true
		navigateToRoot(false)
	elseif mode == "inventory" then
		menuFrame.Visible = false
		inventoryPanel.Visible = true
		GridMenuModule.reset()
		hideReturnButton()
		hideSkillAverage()
		hideRomanToggle()
		hideSearchBox()
		setTitleInstant("Your Inventory")
	end

	BoundingBox.Position = MENU_CLOSED
	tweenObject(BoundingBox, { Position = MENU_OPEN }, menuTweenInfo)
	UIClick:Play()
	UIIn:Play()
	navStack = {}
	MenuBridge.notifyStateChanged(mode)
end

local function closeMenu()
	if not menuOpen then
		return
	end
	menuOpen = false
	openMode = nil
	tweenBlur(0)
	showSidebar()
	local nav = currentNav()
	if nav and nav.config and nav.config.module then
		nav.config.module.reset()
	end
	TooltipModule.forceHide()
	UIOut:Play()
	local tw = TweenService:Create(BoundingBox, menuTweenInfo, { Position = MENU_CLOSED })
	tw:Play()
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and not menuOpen then
			CentralizedMenu.Enabled = false
			for _, frame in pairs(menuChildFrames) do
				frame.Position = SLIDE_RIGHT
				frame.Visible = false
			end
			GridMenuModule.showRoot(ROOT_GRID, false)
			menuFrame.Visible = false
			inventoryPanel.Visible = false
		end
	end)
	navStack = {}
	MenuBridge.notifyStateChanged(nil)
end

local function toggleMenu()
	if menuOpen then
		closeMenu()
	else
		openMenu("full")
	end
end

-- ===================== SHARED REFS =====================
local sharedRefs = {
	menuFrame = menuFrame,
	topBarFrame = topBarFrame,
	menuTitleLabel = menuTitleLabel,
	returnBox = returnBox,
	returnButton = returnButton,
	romantonumButton = romantonumButton,
	skillAverageFrame = skillAverageFrame,
	TooltipModule = TooltipModule,
	pushSubPage = pushSubPage,
	typewriteTitle = typewriteTitle,
	setTitleInstant = setTitleInstant,
	showReturnButton = showReturnButton,
	hideReturnButton = hideReturnButton,
	showSkillAverage = showSkillAverage,
	hideSkillAverage = hideSkillAverage,
	showRomanToggle = showRomanToggle,
	hideRomanToggle = hideRomanToggle,
	showSearchBox = showSearchBox,
	hideSearchBox = hideSearchBox,
	GridMenuModule = GridMenuModule,
}

-- ===================== INITIALIZE GridMenuModule =====================
GridMenuModule.init(sharedRefs, {
	onNavigateToPage = function(gridKey, buttonKey, buttonConfig)
		navigateToPage(gridKey, buttonKey, buttonConfig, true)
	end,
	onCloseMenu = function()
		closeMenu()
	end,
})

-- ===================== REGISTER MENUBRIDGE CALLBACKS =====================
MenuBridge._openInventoryMode = function()
	if menuOpen then
		closeMenu()
	else
		openMenu("inventory")
	end
end

MenuBridge._openFullMode = function()
	if menuOpen and openMode == "full" then
		closeMenu()
	else
		openMenu("full")
	end
end

MenuBridge._closeAll = function()
	closeMenu()
end

MenuBridge._isOpen = function()
	return menuOpen
end

MenuBridge._getMode = function()
	return openMode
end

-- ===================== REGISTER NexusMenu AS ROOT GRID =====================
GridMenuModule.registerGrid(ROOT_GRID, NexusMenu, NEXUS_BUTTONS, {
	title = "Your Nexus Menu",
})

local CollectionsGrid = menuFrame:WaitForChild("CollectionsMenu1")
local StatisticsGrid = menuFrame:WaitForChild("StatisticsMenu1")
local SettingsGrid = menuFrame:WaitForChild("SettingsMenu1")
local SkillsGrid = menuFrame:WaitForChild("SkillsMenu1")
local StatisticsMenu2 = menuFrame:WaitForChild("StatisticsMenu2")
local CollectionsMenu2 = menuFrame:WaitForChild("CollectionsMenu2")
local CollectionsMenu3 = menuFrame:WaitForChild("CollectionsMenu3")

applyGridLayout(NexusMenu, NEXUS_BLANK_GROUPS, NEXUS_ITEM_ORDERS)
applyGridLayout(CollectionsGrid, COLLECTION_BLANK_GROUPS, {})
applyGridLayout(SettingsGrid, SETTINGS_BLANK_GROUPS, {})
applyGridLayout(SkillsGrid, SKILL_BLANK_GROUPS, {})
applyGridLayout(StatisticsGrid, STATISTICS_BLANK_GROUPS, {})

GridMenuModule.registerGrid("CollectionsGrid", CollectionsGrid, COLLECTION_BUTTONS, { title = "Collections" })
GridMenuModule.registerGrid("StatisticsGrid", StatisticsGrid, STATISTICS_BUTTONS, { title = "Statistics" })
GridMenuModule.registerGrid("SettingsGrid", SettingsGrid, SETTINGS_BUTTONS, { title = "Settings" })
GridMenuModule.registerGrid("SkillsGrid", SkillsGrid, SKILLS_BUTTONS, { title = "Skills" })
GridMenuModule.registerGrid("StatisticsMenu2", StatisticsMenu2, STATS_MENU2_BUTTONS, { title = "Statistics" })
GridMenuModule.registerGrid("CollectionsMenu2", CollectionsMenu2, COLLECTION_MENU2_BUTTONS, { title = "Collections" })
GridMenuModule.registerGrid("CollectionsMenu3", CollectionsMenu3, COLLECTION_MENU3_BUTTONS, { title = "Collection" })

-- ===================== WIRE DYNAMIC SKILL GRID TOOLTIPS =====================
local SKILLGRID_STAT_MAP = {
	FarmingSkills = "Farming",
	ForagingSkills = "Foraging",
	FishingSkills = "Fishing",
	MiningSkills = "Mining",
	CombatSkills = "Combat",
}

for buttonName, statKey in pairs(SKILLGRID_STAT_MAP) do
	local btn = SkillsGrid:FindFirstChild(buttonName)
	if btn then
		btn.MouseEnter:Connect(function()
			SkillsPageModule.showGridSkillTooltip(statKey)
		end)
		btn.MouseLeave:Connect(function()
			SkillsPageModule.hideGridSkillTooltip()
		end)
	else
		warn("[SkillGridTooltips] Missing button: " .. buttonName)
	end
end

-- ===================== INITIALIZE PAGE MODULES =====================
SkillsPageModule.init(sharedRefs, menuChildFrames["SkillsMenu"])
ProfilePageModule.init(sharedRefs, menuChildFrames["ProfileMenu"])
SettingsPageModule.init(sharedRefs, menuChildFrames["SettingsMenu"])
StatisticsPageModule.init(sharedRefs, StatisticsMenu2)
CollectionsPageModule.init(sharedRefs, CollectionsMenu2, CollectionsMenu3)
sharedRefs.SkillsPageModule = SkillsPageModule

-- ===================== INITIAL STATE =====================
CentralizedMenu.Enabled = false
menuFrame.Visible = false
inventoryPanel.Visible = false
BoundingBox.Position = MENU_CLOSED
returnBox.Position = RETURN_HIDDEN
skillAverageFrame.Position = SKILLAVG_HIDDEN
searchBoxOuter.Position = SEARCH_HIDDEN
romantonumButton.Visible = false
menuTitleLabel.Text = "Your Nexus Menu"
SidebarBB.Position = SIDEBAR_VISIBLE

for _, frame in pairs(menuChildFrames) do
	frame.Position = SLIDE_RIGHT
	frame.Visible = false
end


-- ===================== NEXUS SIDEBAR BUTTON =====================
NexusBtn.MouseButton1Click:Connect(function()
	toggleMenu()
end)

-- ===================== RETURN BUTTON — HOLD / TAP =====================
local progressBar = returnBox:WaitForChild("Progress")
progressBar.Size = PROGRESS_EMPTY
progressBar.Visible = false
local holdCompleted = false

local HOLD_APPEAR_DELAY = 0.15
local holdAppearThread = nil

returnButton.MouseButton1Down:Connect(function()
	returnPressTime = tick()
	holdCompleted = false

	if progressTween then
		progressTween:Cancel()
	end
	progressBar.Size = PROGRESS_EMPTY
	progressBar.Visible = false

	if holdAppearThread then
		task.cancel(holdAppearThread)
		holdAppearThread = nil
	end

	holdAppearThread = task.delay(HOLD_APPEAR_DELAY, function()
		holdAppearThread = nil
		progressBar.Visible = true

		local current = progressBar.Size.X.Scale
		local remaining = HOLD_THRESHOLD * (1 - current)
		progressTween = TweenService:Create(
			progressBar,
			TweenInfo.new(remaining, Enum.EasingStyle.Linear),
			{ Size = PROGRESS_FULL }
		)
		progressTween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				holdCompleted = true
				if progressTween then
					progressTween:Cancel()
				end
				progressBar.Size = PROGRESS_EMPTY
				progressBar.Visible = false

				local nav = currentNav()
				if nav and nav.config and nav.config.module then
					nav.config.module.reset()
				end

				for _, frame in pairs(menuChildFrames) do
					if frame.Visible then
						frame.Position = SLIDE_RIGHT
						frame.Visible = false
					end
				end

				navStack = {}
				navigateToRoot(true)
				UIClick:Play()
				returnPressTime = nil
			end
		end)
		progressTween:Play()
	end)
end)

returnButton.MouseButton1Up:Connect(function()
	if holdAppearThread then
		task.cancel(holdAppearThread)
		holdAppearThread = nil
	end

	if not returnPressTime then
		return
	end
	if holdCompleted then
		return
	end

	if returnDebounce then
		returnPressTime = nil
		if progressTween then
			progressTween:Cancel()
		end
		local current = progressBar.Size.X.Scale
		progressBar.Visible = current > 0
		progressTween = TweenService:Create(
			progressBar,
			TweenInfo.new(current * HOLD_THRESHOLD, Enum.EasingStyle.Linear),
			{ Size = PROGRESS_EMPTY }
		)
		progressTween.Completed:Connect(function()
			progressBar.Visible = false
		end)
		progressTween:Play()
		return
	end

	returnPressTime = nil
	if progressTween then
		progressTween:Cancel()
	end
	local current = progressBar.Size.X.Scale
	if current > 0 then
		progressBar.Visible = true
		progressTween = TweenService:Create(
			progressBar,
			TweenInfo.new(current * HOLD_THRESHOLD, Enum.EasingStyle.Linear),
			{ Size = PROGRESS_EMPTY }
		)
		progressTween.Completed:Connect(function()
			progressBar.Visible = false
		end)
		progressTween:Play()
	end
	navigateBack()
end)

-- ===================== ROMAN / NUMBER TOGGLE =====================
romantonumButton.button.Text = "I"

romantonumButton.button.MouseButton1Click:Connect(function()
	UIClick:Play()
	if SkillsPageModule.toggleRomanNumerals then
		local newMode = SkillsPageModule.toggleRomanNumerals()
		romantonumButton.button.Text = newMode and "I" or "1"
	end
end)

print("CentralizedMenuController: Ready ✓")
