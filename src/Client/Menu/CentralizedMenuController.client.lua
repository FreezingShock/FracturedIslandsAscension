-- ============================================================
--  CentralizedMenuController (LocalScript)
--  StarterPlayerScripts
-- ============================================================

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local LiquidGlassHandler = require(Modules:WaitForChild("LiquidGlassHandler")) :: any

-- ===================== AUDIO =====================
local UIClick, UIClick3, UIIn, UIOut
do
	local success, err = pcall(function()
		UIClick = workspace:WaitForChild("UISounds", 3):WaitForChild("Click")
		UIClick3 = workspace:WaitForChild("UISounds", 3):WaitForChild("Click3")
		UIIn = workspace:WaitForChild("UISounds", 3):WaitForChild("In")
		UIOut = workspace:WaitForChild("UISounds", 3):WaitForChild("Out")
	end)
	if not success then
		UIClick = Instance.new("Sound")
		UIClick3 = Instance.new("Sound")
		UIIn = Instance.new("Sound")
		UIOut = Instance.new("Sound")
	end
end

-- ===================== GUI REFERENCES =====================
local CentralizedMenu = playerGui:WaitForChild("CentralizedAscensionMenu", 5)
if not CentralizedMenu then
	error("[CentralizedMenuController] CentralizedAscensionMenu not found in PlayerGui")
end

local BoundingBox = CentralizedMenu:WaitForChild("BoundingBox", 3)
if not BoundingBox then
	error("[CentralizedMenuController] BoundingBox not found in CentralizedAscensionMenu")
end
local outerFrame = BoundingBox:WaitForChild("outerFrame")
local innerFrame = outerFrame:WaitForChild("innerFrame")
local menuClip = innerFrame:WaitForChild("MenuClip")
local menuFrame = menuClip:WaitForChild("Menu")
local gridBufferA = menuFrame:WaitForChild("GridBufferA")
local gridBufferB = menuFrame:WaitForChild("GridBufferB")
local topBarFrame = innerFrame:WaitForChild("topBarFrame")
local menuTitleLabel = topBarFrame:WaitForChild("MenuTitleLabel")
local inventoryPanel = innerFrame:WaitForChild("Inventory")
local inventoryFrame = inventoryPanel:WaitForChild("InventoryFrame")
local inventoryGridLayout = inventoryFrame:WaitForChild("UIGridLayout")

local TemporaryMenus = CentralizedMenu:WaitForChild("TemporaryMenus")
local GridTemplates = ReplicatedStorage:WaitForChild("GridTemplates")
local Sidebar = playerGui:WaitForChild("Sidebar")
local SidebarBB = Sidebar:WaitForChild("SidebarBB")
local NexusBtn = SidebarBB:WaitForChild("Nexus")

-- ===================== ARMOR ACCESSORIES CLIP =====================
local ArmorAccessoriesClip = innerFrame:WaitForChild("ArmorAccessoriesClip")

-- ===================== MODULES =====================
local function safeRequire(moduleName, critical)
	critical = critical ~= false
	local success, result = pcall(function()
		return require(Modules:WaitForChild(moduleName, 5))
	end)
	if success then
		return result
	else
		local msg = "[CentralizedMenuController] " .. moduleName .. " failed to load: " .. tostring(result)
		if critical then
			error(msg)
		else
			warn(msg)
			return nil
		end
	end
end

local TooltipModule = safeRequire("TooltipModule", true)
local GridMenuModule = safeRequire("GridMenuModule", true)
local SkillsPageModule = safeRequire("SkillsPageModule", true)
local ProfilePageModule = safeRequire("ProfilePageModule", true)
local ProfileConfig = safeRequire("ProfileConfig", true)
local SettingsPageModule = safeRequire("SettingsPageModule", true)
local StatisticsPageModule = safeRequire("StatisticsPageModule", true)
local CollectionsPageModule = safeRequire("CollectionsPageModule", true)
local AdminPageModule = safeRequire("AdminPageModule", false)
local NexusLevelPageModule = safeRequire("NexusLevelPageModule", false)
local MenuBridge = safeRequire("MenuBridge", true)

-- Register MenuBridge callbacks IMMEDIATELY (before InventoryController tries to use them)
MenuBridge._openInventoryMode = function() end
MenuBridge._openFullMode = function() end
MenuBridge._closeAll = function() end
MenuBridge._isOpen = function() return false end
MenuBridge._getMode = function() return nil end

local ArmorAccessoriesController = safeRequire("ArmorAccessoriesController", true)

local Lighting = game:GetService("Lighting")

-- ===================== TWEEN CONFIG =====================
local TWEEN_TIME = 0.5
local TWEEN_STYLE = Enum.EasingStyle.Quint
local TWEEN_DIR = Enum.EasingDirection.Out
local tweenInfo = TweenInfo.new(TWEEN_TIME, TWEEN_STYLE, TWEEN_DIR)

local SLIDE_ON = UDim2.new(0, 0, 0, 0)
local SLIDE_LEFT = UDim2.fromScale(-1.1, 0)
local SLIDE_RIGHT = UDim2.fromScale(1.1, 0)

local SIDEBAR_VISIBLE = UDim2.new(0, 10, 0.5, 0)
local SIDEBAR_HIDDEN = UDim2.new(0, -70, 0.5, 0)
local sidebarTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local sidebarHideTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local MENU_OPEN = UDim2.fromScale(0.5, 0.5)
local MENU_CLOSED = UDim2.fromScale(0.5, -0.5)
local menuTweenInfo = TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Back, TWEEN_DIR)

-- Menu panel slide (Position on menuFrame inside MenuClip)
local MENU_PANEL_HIDDEN = UDim2.fromScale(0, -1)
local MENU_PANEL_SHOWN = UDim2.new(0, 0, 0, 0)
local menuPanelTweenIn = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local menuPanelTweenOut = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local menuPanelTween = nil

-- InventoryFrame size tween (shrinks when nexus grid is visible)
local INVFRAME_SIZE_DEFAULT = UDim2.new(1, 0, 0, 205)
local INVFRAME_SIZE_NEXUS = UDim2.new(1, 0, 0, 140)
local invFrameTweenInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- Armor/Accessories clip tween
local ARMOR_CLIP_OPEN = UDim2.fromScale(0.5, 0.5)
local ARMOR_CLIP_CLOSED = UDim2.fromScale(0, 0)
local armorClipTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local armorClipActiveTween = nil

-- ===================== STATE =====================
local menuOpen = false
local lastActivity = 0 -- os.clock() of the last thing that can move the blank-slot gradients
local openMode: "full" | "inventory" | nil = nil
local navStack = {}
local sidebarVisible = true
local sidebarActiveTween = nil

-- ===================== ROOT GRID KEY =====================
local ROOT_GRID = "NexusMenu"

-- ===================== TWEEN HELPERS =====================
local function tweenObject(object, targetProps, info)
	local tw = TweenService:Create(object, info or tweenInfo, targetProps)
	tw:Play()
	return tw
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

-- ===================== ARMOR CLIP TWEEN HELPERS =====================
local function tweenArmorClip(visible)
	if armorClipActiveTween then
		armorClipActiveTween:Cancel()
	end

	local targetSize = visible and ARMOR_CLIP_OPEN or ARMOR_CLIP_CLOSED
	ArmorAccessoriesClip.Visible = true

	armorClipActiveTween = TweenService:Create(ArmorAccessoriesClip, armorClipTweenInfo, { Size = targetSize })
	armorClipActiveTween:Play()

	armorClipActiveTween.Completed:Once(function()
		if not visible then
			ArmorAccessoriesClip.Visible = false
		end
		armorClipActiveTween = nil
	end)
end

-- ===================== MENU PANEL TWEEN HELPERS =====================
-- MenuAnimationContainer tweens Size.Y from 0 to 280px (not scale, use offset pixels)

-- ===================== MENU PANEL TWEEN HELPERS =====================
-- Match armor accessories pattern: tween MenuClip size + Menu position simultaneously
-- Menu slides up from below screen while clip expands to show it

local menuSlideTween = nil -- Track both tweens separately

local function _openMenuPanel()
	if menuPanelTween then
		menuPanelTween:Cancel()
	end
	if menuSlideTween then
		menuSlideTween:Cancel()
	end

	menuClip.Visible = true
	menuFrame.Visible = true

	-- Menu starts off-screen below (NOT visible yet)
	menuFrame.Position = UDim2.new(0, 0, 0, -1)

	-- Disable AutomaticSize so we can tween the size (like armor)
	menuClip.AutomaticSize = Enum.AutomaticSize.None
	menuClip.Size = UDim2.new(0, 0, 0, 0) -- Start at Y=0

	-- TWEEN 1: MenuClip expands from Y=0 to Y=365 (actual needed height)
	menuPanelTween = TweenService:Create(menuClip, menuPanelTweenIn, { Size = UDim2.new(0, 0, 0, 365) })
	menuPanelTween:Play()

	-- TWEEN 2: Menu slides from below (-1 scale) to visible (0,0) simultaneously
	menuSlideTween = TweenService:Create(menuFrame, menuPanelTweenIn, { Position = UDim2.new(0, 0, 0, 0) })
	menuSlideTween:Play()

	-- Wait for BOTH tweens to complete
	menuPanelTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			menuClip.AutomaticSize = Enum.AutomaticSize.Y
		end
		menuPanelTween = nil
	end)

	menuSlideTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			-- Grid is now fully visible
		end
		menuSlideTween = nil
	end)
end

local function _closeMenuPanel()
	if menuPanelTween then
		menuPanelTween:Cancel()
	end
	if menuSlideTween then
		menuSlideTween:Cancel()
	end

	-- Disable AutomaticSize for close tween
	menuClip.AutomaticSize = Enum.AutomaticSize.None

	-- TWEEN 1: MenuClip shrinks from Y=365 to Y=0
	menuPanelTween = TweenService:Create(menuClip, menuPanelTweenOut, { Size = UDim2.new(0, 0, 0, 0) })
	menuPanelTween:Play()

	-- TWEEN 2: Menu slides down off-screen to 1.2 scale (further below) so it's fully gone
	menuSlideTween = TweenService:Create(menuFrame, menuPanelTweenOut, { Position = UDim2.new(0, 0, 0, 1.2) })
	menuSlideTween:Play()

	-- Wait for BOTH tweens to complete before hiding
	menuPanelTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			menuClip.Size = UDim2.new(0, 0, 0, 0)
			menuClip.Visible = false
			menuClip.AutomaticSize = Enum.AutomaticSize.Y
		end
		menuPanelTween = nil
	end)

	menuSlideTween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed then
			menuFrame.Position = UDim2.new(0, 0, 0, 1.2) -- Ensure it stays off-screen
			menuFrame.Visible = false -- Only hide AFTER tween completes
		end
		menuSlideTween = nil
	end)
end

-- ===================== TYPEWRITER (title label) =====================
local titleTypewriteToken = nil

local function typewriteTitle(text, speed)
	speed = speed or 0.03
	local token = {}
	titleTypewriteToken = token
	menuTitleLabel.RichText = true
	menuTitleLabel.Text = text
	menuTitleLabel.MaxVisibleGraphemes = 0
	local length = utf8.len(menuTitleLabel.ContentText) or #menuTitleLabel.ContentText
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
	menuTitleLabel.RichText = true
	menuTitleLabel.Text = text
	menuTitleLabel.MaxVisibleGraphemes = -1
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

local closeNexusPanel

-- ===================== BUTTON CONFIGS =====================
-- ===================== NEXUS LEVEL PAGE =====================
local function openNexusLevel()
	if GridMenuModule.hasGrid("NexusLevelMenu") then
		GridMenuModule.navigateToGrid("NexusLevelMenu") -- onPopulate fills it (and refills on Back)
	end
end

-- The Nexus buttons' tooltip (home middle slot + Profile): one table that TooltipModule reads when it shows, kept current from the Player attributes.
local NEXUS_TOOLTIP = {
	title = '<font color="#FF55FF"><b>Aetheric Nexus Level</b></font>',
	desc = '<font color="#AAAAAA">Your account level, earned from skill level-ups and collections.</font>',
	click = '<font color="#FFFF55">Click to view!</font>',
}
if NexusLevelPageModule then
	local NexusConfig = require(Modules:WaitForChild("Config"):WaitForChild("NexusConfig")) :: any
	local function refreshNexusTooltip()
		local config = NexusLevelPageModule.tooltipText()
		for key in pairs(NEXUS_TOOLTIP) do
			NEXUS_TOOLTIP[key] = nil
		end
		for key, value in pairs(config) do
			NEXUS_TOOLTIP[key] = value
		end
	end
	refreshNexusTooltip()
	for _, attribute in ipairs({ NexusConfig.attributes.level, NexusConfig.attributes.progress, NexusConfig.attributes.total }) do
		player:GetAttributeChangedSignal(attribute):Connect(refreshNexusTooltip)
	end
end

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
		action = "grid",
		targetGrid = "ProfileGrid",
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
	-- The middle slot: the Aetheric Nexus Level page (same grid as the Profile menu's AethericNexus button)
	AethericNexus = {
		tooltipData = NEXUS_TOOLTIP,
		action = "callback",
		callback = function()
			openNexusLevel()
		end,
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
			title = '<font color="#FF5555"><b>Close Nexus Menu</b></font>',
			desc = '<font color="#AAAAAA">Click to close Nexus Menu, Inventory menu remains open.</font>',
			click = '<font color="#FFFF55">Click to close!</font>',
		},
		action = "callback",
		callback = function()
			closeNexusPanel()
		end,
	},
	AdminPanel = {
		tooltipData = {
			title = '<font color="#FF55FF"><b>Admin Panel</b></font>',
			desc = '<font color="#AAAAAA">See every item, give yourself items and statistics, and add temporary attribute bonuses.</font>',
			click = '<font color="#FFFF55">Click to open!</font>',
		},
		-- Not a template button: AdminPageModule.addNexusButton builds it for admins only.
		callback = function()
			GridMenuModule.navigateToGrid("AdminGrid")
		end,
	},
}

-- Collections: ONE hub button per skill (tooltip is dynamic, see the grid's onWireTooltips). Every page's Go back is
-- CollectionsPageModule.back(): the engine rebuilds the page we return to from the module's state.
local COLLECTION_SKILLS = { "Farming", "Foraging", "Fishing", "Mining", "Combat", "General" }

local COLLECTION_BACK_TOOLTIP = {
	title = '<font color="#55FF55"><b>Go back</b></font>',
	desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
	click = "",
}
local COLLECTION_CLOSE_TOOLTIP = {
	title = '<font color="#FF5555"><b>Close Menu</b></font>',
	desc = "",
	click = "",
}

local function collectionFooter()
	return {
		BackButton = {
			tooltipData = COLLECTION_BACK_TOOLTIP,
			action = "callback",
			callback = function()
				CollectionsPageModule.back()
			end,
		},
		CloseSlot = { tooltipData = COLLECTION_CLOSE_TOOLTIP, action = "close" },
	}
end

local COLLECTION_BUTTONS = {
	BackButton = {
		tooltipData = COLLECTION_BACK_TOOLTIP,
		action = "callback",
		callback = function()
			GridMenuModule.navigateBack()
		end,
	},
	CloseSlot = { tooltipData = COLLECTION_CLOSE_TOOLTIP, action = "close" },
}
for _, skillName in ipairs(COLLECTION_SKILLS) do
	COLLECTION_BUTTONS[skillName .. "Collections"] = {
		action = "callback",
		callback = function()
			CollectionsPageModule.openSkill(skillName)
		end,
	}
end

local COLLECTION_MENU2_BUTTONS = collectionFooter()
local COLLECTION_MENU3_BUTTONS = collectionFooter()
local COLLECTION_MENU4_BUTTONS = collectionFooter()

-- ===================== STATISTICS ROUTING =====================
-- Hub (StatisticsGrid): one button per skill, tooltip is dynamic (see the grid's
-- onWireTooltips). Page (StatisticsMenu2): built by StatisticsPageModule.populate.
-- Statistics are READ-ONLY here - they are earned from world buttons.
local STATISTICS_SKILLS = { "Farming", "Foraging", "Fishing", "Mining", "General", "Combat" }

local function openStatistics(skillName)
	StatisticsPageModule.setPendingSkill(skillName)
	GridMenuModule.setGridTitle("StatisticsMenu2", StatisticsPageModule.titleFor(skillName))
	GridMenuModule.navigateToGrid("StatisticsMenu2") -- onPopulate builds the page
end

local STATISTICS_BUTTONS = {
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
for _, skillName in ipairs(STATISTICS_SKILLS) do
	STATISTICS_BUTTONS[skillName .. "Statistics"] = {
		action = "callback",
		callback = function()
			openStatistics(skillName)
		end,
	}
end

local STATS_MENU2_BUTTONS = {
	BackButton = {
		tooltipData = {
			title = '<font color="#55FF55"><b>Go back</b></font>',
			desc = '<font color="#AAAAAA">Return to the previous menu.</font>',
			click = "",
		},
		action = "callback",
		callback = function()
			GridMenuModule.navigateBack() -- onDepopulate clears the page + tooltip
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

local ADMIN_BUTTONS = {
	BackButton = STATS_MENU2_BUTTONS.BackButton,
	CloseSlot = STATS_MENU2_BUTTONS.CloseSlot,
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
	},
	ForagingSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Foraging Skill",
		menuChild = "SkillsMenu",
		openArg = "Foraging",
	},
	FishingSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Fishing Skill",
		menuChild = "SkillsMenu",
		openArg = "Fishing",
	},
	MiningSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Mining Skill",
		menuChild = "SkillsMenu",
		openArg = "Mining",
	},
	CombatSkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Combat Skill",
		menuChild = "SkillsMenu",
		openArg = "Combat",
	},
	CarpentrySkills = {
		action = "page",
		module = SkillsPageModule,
		menuTitle = "Carpentry Skill",
		menuChild = "SkillsMenu",
		openArg = "Carpentry",
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

-- ===================== PROFILE MENU 2 — SKILL ROUTING =====================
-- Tracks which skill the player clicked so onPopulate knows what to show.
local pendingProfileSkill = nil

local function openProfileMenu2(skillName)
	ProfilePageModule.setPendingSkill(skillName)
	local color = ProfileConfig.SKILL_COLORS[skillName] or "#FFFFFF"
	GridMenuModule.setGridTitle("ProfileMenu2", string.format('<font color="%s">%s</font> Attributes', color, skillName))
	GridMenuModule.navigateToGrid("ProfileMenu2") -- onPopulate fills it (and refills on Back)
end

-- Layer 3: one attribute's sources (clicked from ProfileMenu2).
local function openProfileMenu3(skillName, attrConfig)
	ProfilePageModule.setPendingAttribute(skillName, attrConfig)
	local color = attrConfig.color or "#FFFFFF"
	GridMenuModule.setGridTitle(
		"ProfileMenu3",
		string.format('<font color="%s">%s</font> Breakdown', color, attrConfig.name or "Attribute")
	)
	GridMenuModule.navigateToGrid("ProfileMenu3")
end

local NEXUS_LEVEL_BUTTONS = {
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
		tooltipData = { title = '<font color="#FF5555"><b>Close Menu</b></font>', desc = "", click = "" },
		action = "close",
	},
}

-- ===================== PROFILE GRID BUTTON CONFIGS =====================
local PROFILE_BUTTONS = {
	MyProfile = {
		action = nil,
	},
	-- Helmet..Belt (equipment slots) are driven by ArmorAccessoriesController.
	-- The Aetheric Nexus Level page. The tooltip is rewritten from the Player attributes (see NEXUS_TOOLTIP below).
	AethericNexus = {
		tooltipData = NEXUS_TOOLTIP,
		action = "callback",
		callback = function()
			openNexusLevel()
		end,
	},
	FarmingAttributes = {
		action = "callback",
		callback = function()
			openProfileMenu2("Farming")
		end,
	},
	ForagingAttributes = {
		action = "callback",
		callback = function()
			openProfileMenu2("Foraging")
		end,
	},
	MiningAttributes = {
		action = "callback",
		callback = function()
			openProfileMenu2("Mining")
		end,
	},
	MiscAttributes = {
		action = "callback",
		callback = function()
			openProfileMenu2("Misc")
		end,
	},
	FishingAttributes = {
		action = "callback",
		callback = function()
			openProfileMenu2("Fishing")
		end,
	},
	GeneralAttributes = {
		action = "callback",
		callback = function()
			openProfileMenu2("General")
		end,
	},
	Milestones = {
		tooltipData = {
			title = '<font color="#AA00AA"><b>Milestones</b></font>',
			desc = '<font color="#AAAAAA">View your completed milestones and achievements.</font>',
			click = '<font color="#555555">Coming Soon</font>',
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

local PROFILE_MENU2_BUTTONS = {
	Category = {
		tooltipData = {
			title = '<font color="#FFFFFF"><b>Attribute Category</b></font>',
			desc = '<font color="#AAAAAA">Currently viewing this skill\'s attributes.</font>',
			click = "",
		},
		action = nil,
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

local PROFILE_MENU3_BUTTONS = {
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
-- REPLACE WITH:
local NEXUS_BLANK_GROUPS = {
	{ layoutOrder = -2, count = 8 },
	{ layoutOrder = -1, count = 1 }, -- top-right: the admin button replaces this for admins
	{ layoutOrder = 1, count = 4 },
	{ layoutOrder = 3, count = 5 },
	{ layoutOrder = 11, count = 4 },
	{ layoutOrder = 15, count = 12 }, -- (the retired hotbar-toggle button has no cell any more) the blanks up to the bottom row
	{ layoutOrder = 17, count = 2 }, -- bottom row: 2 blanks, then WarpMap, Close, Settings, BoosterOil
	{ layoutOrder = 22, count = 3 },
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
	WarpMap = 18,
	CloseSlot = 19,
	Settings = 20,
	BoosterOil = 21,
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
-- Same arrangement as the Collections hub: five skills in a row, the sixth centred below, Back / Close in the footer.
local SKILL_BLANK_GROUPS = {
	{ layoutOrder = 0, count = 20 },
	{ layoutOrder = 6, count = 6 },
	{ layoutOrder = 8, count = 16 },
	{ layoutOrder = 11, count = 4 },
}
local SKILL_ITEM_ORDERS = { CarpentrySkills = 7, BackButton = 9, CloseSlot = 10 }
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
	TooltipModule.forceHide()
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
	GridMenuModule.showRoot(ROOT_GRID, animated)
	if animated then
		typewriteTitle("Your Nexus Menu")
	else
		setTitleInstant("Your Nexus Menu")
	end
	navStack = {}
end

-- ===================== NAVIGATE TO PAGE =====================
local function navigateToPage(gridKey, buttonKey, buttonConfig, animated)
	if not buttonConfig.menuChild then
		return
	end
	local frame = menuChildFrames[buttonConfig.menuChild]
	if not frame then
		return
	end

	TooltipModule.forceHide() -- the page slides in: the button's tooltip must not stay on screen

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

	if buttonConfig.module then
		buttonConfig.module.open(buttonConfig.openArg)
	end
end

-- ===================== NAVIGATE BACK =====================
local function navigateBack()
	local depth = navDepth()
	TooltipModule.forceHide()

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
	table.insert(navStack, { key = key, config = nav.config, depth = nav.depth + 1 })
end

-- ===================== OPEN / CLOSE ENTIRE MENU =====================
local function openMenu(mode)
	mode = mode or "full"

	if menuOpen then
		if openMode == "inventory" and mode == "full" then
			openMode = "full"
			inventoryPanel.Visible = true
			navigateToRoot(true)
			MenuBridge.notifyStateChanged("full")
			tweenObject(inventoryFrame, { Size = INVFRAME_SIZE_NEXUS }, invFrameTweenInfo)
			task.delay(0.15, function()
				if menuOpen and openMode == "full" then
					_openMenuPanel()
				end
			end)
		end
		return
	end

	menuOpen = true
	openMode = mode
	CentralizedMenu.Enabled = true
	hideSidebar()
	lastActivity = os.clock() -- wakes the blank-slot gradient loop (bottom of this file)

	if mode == "full" then
		inventoryPanel.Visible = true
		navigateToRoot(true)
		tweenObject(inventoryFrame, { Size = INVFRAME_SIZE_NEXUS }, invFrameTweenInfo)
		task.delay(0.5, function()
			if menuOpen and openMode == "full" then
				_openMenuPanel()
			end
		end)
	elseif mode == "inventory" then
		inventoryFrame.Active = true
		menuClip.Visible = false
		menuFrame.Visible = false
		menuFrame.Position = MENU_PANEL_HIDDEN
		inventoryPanel.Visible = true
		GridMenuModule.reset()
		CollectionsPageModule.reset()
		setTitleInstant("Your Inventory")
		inventoryFrame.Size = INVFRAME_SIZE_DEFAULT
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
	showSidebar()
	local nav = currentNav()
	if nav and nav.config and nav.config.module then
		nav.config.module.reset()
	end
	TooltipModule.forceHide()
	UIOut:Play()

	_closeMenuPanel()
	local tw = TweenService:Create(BoundingBox, menuTweenInfo, { Position = MENU_CLOSED })
	tw:Play()
	tw.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and not menuOpen then
			inventoryFrame.Size = INVFRAME_SIZE_DEFAULT
			CentralizedMenu.Enabled = false
			inventoryPanel.Visible = false
			inventoryFrame.Active = false
			for _, frame in pairs(menuChildFrames) do
				frame.Position = SLIDE_RIGHT
				frame.Visible = false
			end
			GridMenuModule.showRoot(ROOT_GRID, false)
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

-- ===================== CLOSE NEXUS PANEL ONLY =====================
closeNexusPanel = function()
	if not menuOpen or openMode ~= "full" then
		return
	end

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

	_closeMenuPanel()

	task.delay(0.3, function()
		if openMode == "inventory" then
			GridMenuModule.reset()
		end
	end)

	task.delay(0.45, function()
		if openMode == "inventory" then
			tweenObject(inventoryFrame, { Size = INVFRAME_SIZE_DEFAULT }, invFrameTweenInfo)
		end
	end)

	navStack = {}
	openMode = "inventory"
	typewriteTitle("Your Inventory")

	TooltipModule.forceHide()
	MenuBridge.notifyStateChanged("inventory")
	UIOut:Play()
end

-- ===================== SHARED REFS =====================
local sharedRefs = {
	menuFrame = menuFrame,
	topBarFrame = topBarFrame,
	menuTitleLabel = menuTitleLabel,
	TooltipModule = TooltipModule,
	pushSubPage = pushSubPage,
	typewriteTitle = typewriteTitle,
	setTitleInstant = setTitleInstant,
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

-- ===================== REGISTER MENUBRIDGE CALLBACKS (IMPLEMENTATION) =====================
MenuBridge._openInventoryMode = function()
	if menuOpen and openMode == "inventory" then
		closeMenu()
	else
		openMenu("inventory")
	end
end

MenuBridge._openFullMode = function()
	if menuOpen and openMode == "full" then
		closeNexusPanel()
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

-- ===================== INITIALIZE DOUBLE-BUFFER SYSTEM =====================
GridMenuModule.initBuffers(
	menuFrame:WaitForChild("GridBufferA"),
	menuFrame:WaitForChild("GridBufferB"),
	blankSlotTemplate
)

-- ===================== REGISTER NexusMenu AS POOLED ROOT GRID =====================
GridMenuModule.registerPooledGrid(ROOT_GRID, GridTemplates:WaitForChild("NexusMenu"), NEXUS_BUTTONS, {
	title = "Your Nexus Menu",
	blankGroups = NEXUS_BLANK_GROUPS,
	itemOrders = NEXUS_ITEM_ORDERS,
	onWireTooltips = function(clonedButtons)
		-- Dynamic Profile tooltip (moved from manual wiring section below)
		local conns = {}
		local hovers = {} -- what each button's MouseEnter shows (lets the pointer be re-read after a page change)
		local profileBtn = clonedButtons["Profile"]
		if profileBtn then
			hovers.Profile = function()
				ProfilePageModule.showProfileSummaryTooltip()
			end
			table.insert(
				conns,
				profileBtn.MouseEnter:Connect(function()
					UIClick3:Play()
					ProfilePageModule.showProfileSummaryTooltip()
				end)
			)
			table.insert(
				conns,
				profileBtn.MouseLeave:Connect(function()
					ProfilePageModule.hideProfileSummaryTooltip()
				end)
			)
		end
		-- Admin button (top-right). Non-admins keep the blank slot.
		if AdminPageModule then
			local settingsBtn = clonedButtons["Settings"]
			for _, conn in ipairs(AdminPageModule.addNexusButton(settingsBtn and settingsBtn.Parent, settingsBtn, NEXUS_BUTTONS.AdminPanel)) do
				table.insert(conns, conn)
			end
		end
		return conns, hovers
	end,
})

-- ===================== REGISTER ALL POOLED GRIDS =====================

-- ── Level-1 static grids ──
GridMenuModule.registerPooledGrid(
	"CollectionsGrid",
	GridTemplates:WaitForChild("CollectionsMenu1"),
	COLLECTION_BUTTONS,
	{
		title = "Collections",
		blankGroups = COLLECTION_BLANK_GROUPS,
		itemOrders = {},
		onWireTooltips = function(clonedButtons)
			local conns = {}
			local hovers = {}
			for _, skillName in ipairs(COLLECTION_SKILLS) do
				local btn = clonedButtons[skillName .. "Collections"]
				if btn then
					hovers[skillName .. "Collections"] = function()
						CollectionsPageModule.showSkillTooltip(skillName, btn)
					end
					table.insert(
						conns,
						btn.MouseEnter:Connect(function()
							CollectionsPageModule.showSkillTooltip(skillName, btn)
						end)
					)
					table.insert(
						conns,
						btn.MouseLeave:Connect(function()
							CollectionsPageModule.hideSkillTooltip()
						end)
					)
				end
			end
			return conns, hovers
		end,
	}
)

GridMenuModule.registerPooledGrid("StatisticsGrid", GridTemplates:WaitForChild("StatisticsMenu1"), STATISTICS_BUTTONS, {
	title = "Statistics",
	blankGroups = STATISTICS_BLANK_GROUPS,
	itemOrders = {},
	onWireTooltips = function(clonedButtons)
		local conns = {}
		local hovers = {}
		for _, skillName in ipairs(STATISTICS_SKILLS) do
			local btn = clonedButtons[skillName .. "Statistics"]
			if btn then
				hovers[skillName .. "Statistics"] = function()
					StatisticsPageModule.showSkillTooltip(skillName, btn)
				end
				table.insert(
					conns,
					btn.MouseEnter:Connect(function()
						StatisticsPageModule.showSkillTooltip(skillName, btn)
					end)
				)
				table.insert(
					conns,
					btn.MouseLeave:Connect(function()
						StatisticsPageModule.hideSkillTooltip()
					end)
				)
			end
		end
		return conns, hovers
	end,
})

GridMenuModule.registerPooledGrid("SettingsGrid", GridTemplates:WaitForChild("SettingsMenu1"), SETTINGS_BUTTONS, {
	title = "Settings",
	blankGroups = SETTINGS_BLANK_GROUPS,
	itemOrders = {},
})

GridMenuModule.registerPooledGrid("SkillsGrid", GridTemplates:WaitForChild("SkillsMenu1"), SKILLS_BUTTONS, {
	title = "Skills",
	blankGroups = SKILL_BLANK_GROUPS,
	itemOrders = SKILL_ITEM_ORDERS,
	onWireTooltips = function(clonedButtons)
		local conns = {}
		local hovers = {}
		local SKILLGRID_STAT_MAP = {
			FarmingSkills = "Farming",
			ForagingSkills = "Foraging",
			FishingSkills = "Fishing",
			MiningSkills = "Mining",
			CombatSkills = "Combat",
			CarpentrySkills = "Carpentry",
		}
		for buttonName, statKey in pairs(SKILLGRID_STAT_MAP) do
			local btn = clonedButtons[buttonName]
			if btn then
				hovers[buttonName] = function()
					SkillsPageModule.showGridSkillTooltip(statKey)
				end
				table.insert(
					conns,
					btn.MouseEnter:Connect(function()
						SkillsPageModule.showGridSkillTooltip(statKey)
					end)
				)
				table.insert(
					conns,
					btn.MouseLeave:Connect(function()
						SkillsPageModule.hideGridSkillTooltip()
					end)
				)
			end
		end
		return conns, hovers
	end,
})

GridMenuModule.registerPooledGrid("ProfileGrid", GridTemplates:WaitForChild("ProfileMenu1"), PROFILE_BUTTONS, {
	title = "Your Profile",
	blankGroups = ProfileConfig.PROFILE_BLANK_GROUPS,
	itemOrders = ProfileConfig.PROFILE_ITEM_ORDERS,
	onWireTooltips = function(clonedButtons)
		local conns = {}
		local hovers = {}
		-- Skill attribute dynamic tooltips
		for skillName, buttonName in pairs(ProfileConfig.SKILL_BUTTON_MAP) do
			local btn = clonedButtons[buttonName]
			if btn then
				local capturedSkill = skillName
				hovers[buttonName] = function()
					ProfilePageModule.showSkillAttributeTooltip(capturedSkill)
				end
				table.insert(
					conns,
					btn.MouseEnter:Connect(function()
						UIClick3:Play()
						ProfilePageModule.showSkillAttributeTooltip(capturedSkill)
					end)
				)
				table.insert(
					conns,
					btn.MouseLeave:Connect(function()
						ProfilePageModule.hideSkillAttributeTooltip()
					end)
				)
			end
		end
		-- Armor + accessory slots: show / equip / unequip (same logic as the inventory clip)
		local equipButtons = {}
		for _, slotId in ipairs(ProfileConfig.EQUIPMENT_BUTTONS) do
			equipButtons[slotId] = clonedButtons[slotId]
		end
		local unbindEquipment = ArmorAccessoriesController.bindExternal(equipButtons)
		table.insert(conns, {
			Disconnect = function()
			unbindEquipment()
			end,
		})
		-- MyProfile full tooltip
		local myProfileBtn = clonedButtons["MyProfile"]
		if myProfileBtn then
			hovers.MyProfile = function()
				ProfilePageModule.showFullProfileTooltip()
			end
			table.insert(
				conns,
				myProfileBtn.MouseEnter:Connect(function()
					UIClick3:Play()
					ProfilePageModule.showFullProfileTooltip()
				end)
			)
			table.insert(
				conns,
				myProfileBtn.MouseLeave:Connect(function()
					ProfilePageModule.hideFullProfileTooltip()
				end)
			)
		end
		return conns, hovers
	end,
})

-- ── Level-2/3 dynamic grids (page modules handle content cloning) ──
-- Template folders contain only base icons (SelectedSkill, BackButton, CloseSlot).
-- No blankGroups/itemOrders — page modules handle all dynamic layout.

local StatisticsMenu2Template = GridTemplates:FindFirstChild("StatisticsMenu2")
if StatisticsMenu2Template then
	GridMenuModule.registerPooledGrid("StatisticsMenu2", StatisticsMenu2Template, STATS_MENU2_BUTTONS, {
		title = "Statistics",
		onPopulate = function(frame)
			StatisticsPageModule.populate(frame)
		end,
		onDepopulate = function()
			StatisticsPageModule.depopulate()
		end,
	})
else
	warn("[CMC] GridTemplates/StatisticsMenu2 not found — skipping registration (still legacy?)")
end

-- Aetheric Nexus Level page (NexusLevelPageModule): the badge, the xp and where it came from. Opened from the Profile grid's AethericNexus button.
local NexusLevelTemplate = GridTemplates:FindFirstChild("NexusLevelMenu")
if NexusLevelPageModule and NexusLevelTemplate then
	GridMenuModule.registerPooledGrid("NexusLevelMenu", NexusLevelTemplate, NEXUS_LEVEL_BUTTONS, {
		title = "Aetheric Nexus Level",
		onPopulate = function(frame)
			NexusLevelPageModule.populate(frame)
		end,
		onDepopulate = function()
			NexusLevelPageModule.depopulate()
		end,
	})
else
	warn("[CMC] GridTemplates/NexusLevelMenu or NexusLevelPageModule missing: run tools/studio/build_nexus_page.luau")
end

-- Admin panel (built in code, see AdminPageModule). Only reachable from the admin-only Nexus button.
if AdminPageModule then
	AdminPageModule.init(sharedRefs) -- builds the template folder the grid needs
end
if AdminPageModule and AdminPageModule.getTemplateFolder() then
	GridMenuModule.registerPooledGrid("AdminGrid", AdminPageModule.getTemplateFolder(), ADMIN_BUTTONS, {
		title = "Admin Panel",
		onPopulate = function(frame)
			AdminPageModule.populate(frame)
		end,
		onDepopulate = function()
			AdminPageModule.depopulate()
		end,
	})
end

-- Collections drill-down: each page is rebuilt from CollectionsPageModule's state whenever its grid is populated,
-- so Back (which re-populates the grid we return to) never shows an empty grid.
local function registerCollectionGrid(gridKey, buttons, title, populate)
	local template = GridTemplates:FindFirstChild(gridKey)
	if not template then
		warn("[CMC] GridTemplates/" .. gridKey .. " not found - skipping registration")
		return
	end
	GridMenuModule.registerPooledGrid(gridKey, template, buttons, {
		title = title,
		onPopulate = function(frame)
			populate(frame)
		end,
	})
end
registerCollectionGrid("CollectionsMenu2", COLLECTION_MENU2_BUTTONS, "Collections", function(frame)
	CollectionsPageModule.populateSkill(frame)
end)
registerCollectionGrid("CollectionsMenu3", COLLECTION_MENU3_BUTTONS, "Collection", function(frame)
	CollectionsPageModule.populateStat(frame)
end)
registerCollectionGrid("CollectionsMenu4", COLLECTION_MENU4_BUTTONS, "Collection Rewards", function(frame)
	CollectionsPageModule.populateTier(frame)
end)

GridMenuModule.registerPooledGrid("ProfileMenu2", GridTemplates:WaitForChild("ProfileMenu2"), PROFILE_MENU2_BUTTONS, {
	title = "Attributes",
	blankGroups = ProfileConfig.PROFILE_MENU2_BLANK_GROUPS,
	itemOrders = ProfileConfig.PROFILE_MENU2_ITEM_ORDERS,
	onPopulate = function(frame)
		ProfilePageModule.populateAttributeGrid(frame)
	end,
	onDepopulate = function()
		ProfilePageModule.closeAttributeGrid()
	end,
})

local ProfileMenu3Template = GridTemplates:FindFirstChild("ProfileMenu3")
if ProfileMenu3Template then
	GridMenuModule.registerPooledGrid("ProfileMenu3", ProfileMenu3Template, PROFILE_MENU3_BUTTONS, {
		title = "Attribute Breakdown",
		blankGroups = ProfileConfig.PROFILE_MENU3_BLANK_GROUPS,
		itemOrders = ProfileConfig.PROFILE_MENU3_ITEM_ORDERS,
		onPopulate = function(frame)
			ProfilePageModule.openAttributeDetail(frame)
		end,
		onDepopulate = function()
			ProfilePageModule.closeAttributeDetail()
		end,
	})
else
	warn("[CMC] ReplicatedStorage.GridTemplates.ProfileMenu3 not found - attribute breakdown layer disabled")
end

-- ===================== INITIALIZE PAGE MODULES =====================
SkillsPageModule.init(sharedRefs, menuChildFrames["SkillsMenu"])
ProfilePageModule.init(sharedRefs)
ProfilePageModule.setAttributeClickHandler(function(skillName, attrConfig)
	if GridMenuModule.hasGrid("ProfileMenu3") then
		openProfileMenu3(skillName, attrConfig)
	end
end)
SettingsPageModule.init(sharedRefs, menuChildFrames["SettingsMenu"])
StatisticsPageModule.init(sharedRefs)
CollectionsPageModule.init(sharedRefs)
if NexusLevelPageModule then
	NexusLevelPageModule.init(sharedRefs)
end
ArmorAccessoriesController.init()

sharedRefs.SkillsPageModule = SkillsPageModule
sharedRefs.ProfilePageModule = ProfilePageModule
sharedRefs.ArmorAccessoriesController = ArmorAccessoriesController

-- ===================== WIRE UpdateEquipped REMOTE EVENT =====================
local UpdateEquippedEvent = ReplicatedStorage:FindFirstChild("UpdateEquipped")
if UpdateEquippedEvent then
	UpdateEquippedEvent.OnClientEvent:Connect(function(equippedSlots)
		ArmorAccessoriesController.loadEquipped(equippedSlots)
	end)
else
	warn("[CentralizedMenuController] UpdateEquipped event not found")
end

-- ===================== INITIAL STATE =====================
CentralizedMenu.Enabled = false
menuFrame.Visible = false
menuFrame.Position = UDim2.new(0, 0, 0, -1) -- Off-screen below
menuClip.Visible = false
menuClip.Size = UDim2.new(0, 0, 0, 0) -- Y offset 0, not visible
inventoryPanel.Visible = false
inventoryFrame.Active = false
inventoryFrame.Size = INVFRAME_SIZE_DEFAULT
menuClip.Visible = false
ArmorAccessoriesClip.Size = UDim2.fromScale(0, 0)
ArmorAccessoriesClip.Visible = false
BoundingBox.Position = MENU_CLOSED
menuTitleLabel.Text = "Your Nexus Menu"
SidebarBB.Position = SIDEBAR_VISIBLE

for _, frame in pairs(menuChildFrames) do
	frame.Position = SLIDE_RIGHT
	frame.Visible = false
end

-- ===================== TOP BAR CLOSE BUTTON =====================
local closeButton = topBarFrame:WaitForChild("Close")
closeButton.MouseButton1Click:Connect(function()
	if not menuOpen then
		return
	end
	if openMode == "full" then
		closeNexusPanel()
	else
		closeMenu()
	end
end)

closeButton.MouseEnter:Connect(function()
	if not menuOpen then
		return
	end
	local data
	if openMode == "full" then
		data = {
			title = '<font color="#FF5555"><b>Close Nexus Menu</b></font>',
			desc = '<font color="#AAAAAA">Click to close Nexus Menu, Inventory menu remains open.</font>',
			click = '<font color="#FFFF55">Click to close!</font>',
		}
	else
		data = {
			title = '<font color="#FF5555"><b>Close Inventory</b></font>',
			desc = "",
			click = '<font color="#FFFF55">Click to close!</font>',
		}
	end
	UIClick3:Play()
	TooltipModule.show(data)
end)

closeButton.MouseLeave:Connect(function()
	TooltipModule.hide()
end)

-- ===================== E KEY TOGGLE =====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.E then
		if gameProcessed then
			return -- typing in a TextBox (chat, admin panel...): E is a letter, not a hotkey
		end
		if menuOpen then
			if openMode == "full" then
				closeNexusPanel()
			else
				closeMenu()
			end
		else
			openMenu("inventory")
		end
	end
end)

-- ===================== SIDEBAR INVENTORY BUTTON =====================
-- The hand-made Sidebar.SidebarBB.Nexus button (BG / UIStroke / Icon). Only existing instances are animated;
-- restyle them in Studio and the hover/press feedback follows. Click = the E key (open / close the inventory).
local SIDEBAR_TIP_SOURCE = "sidebar"
local SIDEBAR_GREEN = Color3.fromHex("#55FF55")
local sidebarBG = NexusBtn:WaitForChild("BG")
local sidebarStroke = sidebarBG:FindFirstChildOfClass("UIStroke")
local sidebarIcon = NexusBtn:WaitForChild("Icon")
local SIDEBAR_STROKE_BASE = sidebarStroke and sidebarStroke.Thickness or 2
local SIDEBAR_STROKE_COLOR = sidebarStroke and sidebarStroke.Color or Color3.new(1, 1, 1)
local SIDEBAR_ICON_SIZE = sidebarIcon.Size
local SIDEBAR_ICON_HOVER = UDim2.new(SIDEBAR_ICON_SIZE.X.Scale, SIDEBAR_ICON_SIZE.X.Offset + 6, SIDEBAR_ICON_SIZE.Y.Scale, SIDEBAR_ICON_SIZE.Y.Offset + 6)
local SIDEBAR_ICON_PRESS = UDim2.new(SIDEBAR_ICON_SIZE.X.Scale, SIDEBAR_ICON_SIZE.X.Offset - 6, SIDEBAR_ICON_SIZE.Y.Scale, SIDEBAR_ICON_SIZE.Y.Offset - 6)
local sidebarHoverInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local sidebarHovered = false

local function tweenSidebarLook(iconSize, strokeThickness, strokeColor)
	TweenService:Create(sidebarIcon, sidebarHoverInfo, { Size = iconSize }):Play()
	if sidebarStroke then
		TweenService:Create(sidebarStroke, sidebarHoverInfo, { Thickness = strokeThickness, Color = strokeColor }):Play()
	end
end

--- Explains what the button opens (the sidebar slides away while a menu is open, so it only ever says OPEN).
local function sidebarTooltip()
	return {
		title = '<font color="#55FF55"><b>Inventory</b></font>',
		description = '<font color="#AAAAAA">Opens your inventory: the hotbar, your backpack pages, and the armor and accessory slots. Drag items to move them, right click gear to equip it, and use the trash slot to delete what you no longer need.</font>\n\n'
			.. '<font color="#00AA00">Key:</font> <font color="#55FF55"><b>E</b></font>',
		click = { { text = "TO OPEN INVENTORY", color = "#55FF55", icon = "lmb" } },
	}
end

local function showSidebarTooltip()
	TooltipModule.show(sidebarTooltip(), SIDEBAR_TIP_SOURCE)
end

NexusBtn.MouseEnter:Connect(function()
	sidebarHovered = true
	UIClick3:Play()
	tweenSidebarLook(SIDEBAR_ICON_HOVER, SIDEBAR_STROKE_BASE + 1, SIDEBAR_GREEN)
	showSidebarTooltip()
end)

NexusBtn.MouseLeave:Connect(function()
	sidebarHovered = false
	tweenSidebarLook(SIDEBAR_ICON_SIZE, SIDEBAR_STROKE_BASE, SIDEBAR_STROKE_COLOR)
	TooltipModule.hide(SIDEBAR_TIP_SOURCE)
end)

NexusBtn.MouseButton1Down:Connect(function()
	tweenSidebarLook(SIDEBAR_ICON_PRESS, SIDEBAR_STROKE_BASE + 1, SIDEBAR_GREEN)
end)

NexusBtn.MouseButton1Up:Connect(function()
	tweenSidebarLook(sidebarHovered and SIDEBAR_ICON_HOVER or SIDEBAR_ICON_SIZE, SIDEBAR_STROKE_BASE + (sidebarHovered and 1 or 0), sidebarHovered and SIDEBAR_GREEN or SIDEBAR_STROKE_COLOR)
end)

NexusBtn.MouseButton1Click:Connect(function()
	UIClick:Play()
	if menuOpen then
		closeMenu()
	else
		openMenu("inventory")
	end
	-- the sidebar slides away: drop the tooltip and the hover look now (MouseLeave only fires when the mouse moves)
	sidebarHovered = false
	TooltipModule.hide(SIDEBAR_TIP_SOURCE)
	tweenSidebarLook(SIDEBAR_ICON_SIZE, SIDEBAR_STROKE_BASE, SIDEBAR_STROKE_COLOR)
end)
TooltipModule.registerHover(NexusBtn, showSidebarTooltip)

-- (Armor clip tweening subscribes through MenuBridge.onStateChanged inside
--  ArmorAccessoriesController; nothing to wrap here.)
LiquidGlassHandler.apply(outerFrame, {
	mode = "mosaic",
})

-- ===================== BLANKSLOT GRADIENT ROTATION =====================
-- Each BlankSlot's BG gradient turns toward the cursor. This used to walk both grid buffers every
-- Heartbeat (allocating a table, ~100x FindFirstChild x2, atan2 each, plus a never-cleaned angle table).
-- Now: the blank list is cached (rebuilt only when a buffer's children change), the work only runs while
-- something can actually change (cursor moved / menu just opened or slid / page changed), and angles
-- live on the cached entries so nothing leaks.

local GRADIENT_LERP_SPEED = 12 -- higher = snappier; tune freely
local ACTIVE_WINDOW = 1.0 -- seconds of updates after any activity (covers the slide/fade tweens)

local blankEntries = {} -- { { buffer, bg, gradient, angle } }
local blanksDirty = true

local function wake()
	lastActivity = os.clock()
end

local latestCursorPos = Vector2.new(0, 0)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		latestCursorPos = Vector2.new(input.Position.X, input.Position.Y)
		wake()
	end
end)

for _, buffer in ipairs({ gridBufferA, gridBufferB }) do
	local function dirty()
		blanksDirty = true
		wake()
	end
	buffer.ChildAdded:Connect(dirty)
	buffer.ChildRemoved:Connect(dirty)
	buffer:GetPropertyChangedSignal("Visible"):Connect(wake)
end

local function rebuildBlankEntries()
	blanksDirty = false
	local angles = {}
	for _, entry in ipairs(blankEntries) do
		angles[entry.bg] = entry.angle
	end
	table.clear(blankEntries)
	for _, buffer in ipairs({ gridBufferA, gridBufferB }) do
		for _, child in ipairs(buffer:GetChildren()) do
			if child.Name == "BlankSlot" then
				local bg = child:FindFirstChild("BG")
				local gradient = bg and bg:FindFirstChildOfClass("UIGradient")
				if gradient then
					table.insert(blankEntries, { buffer = buffer, bg = bg, gradient = gradient, angle = angles[bg] })
				end
			end
		end
	end
end

local function shortestArcDelta(from, to)
	-- signed delta in [-180, 180] to go from `from` to `to`
	local delta = (to - from) % 360
	if delta > 180 then
		delta = delta - 360
	end
	return delta
end

RunService.Heartbeat:Connect(function(dt)
	if not menuOpen or os.clock() - lastActivity > ACTIVE_WINDOW then
		return
	end
	if blanksDirty then
		rebuildBlankEntries()
	end

	local alpha = math.min(dt * GRADIENT_LERP_SPEED, 1)
	for _, entry in ipairs(blankEntries) do
		if not entry.buffer.Visible or not entry.gradient.Parent then
			continue
		end
		local bg = entry.bg
		local slotPos = bg.AbsolutePosition
		local slotSize = bg.AbsoluteSize
		local cx = slotPos.X + slotSize.X * 0.5
		local cy = slotPos.Y + slotSize.Y * 0.5
		local target = (math.deg(math.atan2(cx - latestCursorPos.X, latestCursorPos.Y - cy)) - 90) % 360

		local current = entry.angle or target
		local nextAngle = (current + shortestArcDelta(current, target) * alpha) % 360
		entry.angle = nextAngle
		entry.gradient.Rotation = nextAngle
	end
end)
