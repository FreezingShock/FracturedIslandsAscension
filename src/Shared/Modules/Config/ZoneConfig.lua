-- ZoneConfig.lua (ModuleScript in ReplicatedStorage.Config)
-- Single source of truth for all zone definitions and animation settings

local ZoneConfig = {}

-- ANIMATION SETTINGS (applied globally to all zone notifications)
ZoneConfig.ANIMATION = {
	ENTER_DURATION = 0.4, -- slide in time
	EXIT_DURATION = 0.3, -- slide out time
	EASING = Enum.EasingStyle.Back,
	EASING_DIRECTION = Enum.EasingDirection.Out,
}

-- SKILLS INDEX: Define all skill properties once, reference by name in zones
-- Each skill has: color (Color3), spriteCoord (x, y for 320x320 grid on spritesheet), and colorScheme (dark/light hex)
-- Spritesheet is 3 columns × 2 rows (320×320 px per cell)
ZoneConfig.SKILLS = {
	["Fishing"] = {
		color = Color3.fromHex("#55FFFF"),
		spriteCoord = { x = 2, y = 2 }, -- Top-left
		colorDark = "00AA00", -- Dark green
		colorLight = "55FF55", -- Light green
	},
	["Mining"] = {
		color = Color3.fromHex("#FF8800"),
		spriteCoord = { x = 2, y = 1 }, -- Top-center
		colorDark = "FFAA00", -- Dark orange
		colorLight = "FFFF55", -- Light yellow
	},
	["Farming"] = {
		color = Color3.fromHex("#00DD00"),
		spriteCoord = { x = 3, y = 1 }, -- Top-right
		colorDark = "228B22", -- Forest green
		colorLight = "90EE90", -- Light green
	},
	["Foraging"] = {
		color = Color3.fromHex("#8B4513"),
		spriteCoord = { x = 1, y = 2 }, -- Bottom-left
		colorDark = "654321", -- Dark brown
		colorLight = "CD853F", -- Peru
	},
	["Combat"] = {
		color = Color3.fromHex("#FF0000"),
		spriteCoord = { x = 1, y = 1 }, -- Bottom-center
		colorDark = "8B0000", -- Dark red
		colorLight = "FF6666", -- Light red
	},
	["Carpentry"] = {
		color = Color3.fromHex("#D2691E"),
		spriteCoord = { x = 3, y = 2 }, -- Bottom-right
		colorDark = "8B4513", -- Saddle brown
		colorLight = "DEB887", -- Burlywood
	},
	["General"] = {
		color = Color3.fromHex("#AAAAAA"),
		spriteCoord = { x = 1, y = 1 }, -- Default to Fishing position
		colorDark = "808080", -- Dark gray
		colorLight = "D3D3D3", -- Light gray
	},
}

-- SPRITESHEET SETTINGS
ZoneConfig.SPRITESHEET = {
	assetId = "rbxassetid://122923092565587", -- Your spritesheet asset ID
	cellSize = 320, -- 320×320 px per cell
	columns = 3, -- 3 columns
	rows = 2, -- 2 rows
}

-- ZONE DEFINITIONS
-- Structure:
--   enabled: bool — whether this zone is active
--   displayName: string — shown in notification
--   skill: string — skill name (references ZoneConfig.SKILLS index)
--   showSkillTab: bool — whether to display the skill tab at all
--   levelRange: string — "10-50" format, shown in level badge
--   detectionMethod: "radius" or "part" — how to detect player entry
--   radiusSize: number — only used if detectionMethod == "radius" (default 100)
--   colorDark: string (hex, optional) — dark color for ZoneFrame, ZoneNameLabel, Underline stroke. Falls back to skill's colorDark if not set.
--   colorLight: string (hex, optional) — light color for ZoneNameLabel text, Underline bg, Icon. Falls back to skill's colorLight if not set.

ZoneConfig.ZONES = {

}

-- NOTIFICATION GUI SETTINGS
ZoneConfig.GUI = {
	-- Path to the LocationNotif template GUI in ReplicatedStorage
	-- Expected structure:
	-- LocationNotif (ScreenGui or Frame)
	--   └─ BoundingBox (Frame)
	--      ├─ ZoneFrame (Frame)
	--      │  ├─ ZoneName (Frame)
	--      │  │  ├─ ZoneNameLabel (TextLabel)
	--      │  │  └─ Underline (Frame)
	--      ├─ Tabs (Frame)
	--      │  ├─ LevelTabBB (Frame)
	--      │  │  └─ LevelTab (Frame)
	--      │  └─ SkillTabBB (Frame)
	--      │     └─ SkillTab (Frame)
	TEMPLATE_PATH = "ReplicatedStorage/GUI/LocationNotif",
}

-- Helper function to convert hex string to Color3
function ZoneConfig.hexToColor3(hex)
	local r = tonumber(string.sub(hex, 1, 2), 16) / 255
	local g = tonumber(string.sub(hex, 3, 4), 16) / 255
	local b = tonumber(string.sub(hex, 5, 6), 16) / 255
	return Color3.new(r, g, b)
end

-- Helper function to get skill data by skill name
-- Returns the skill table from ZoneConfig.SKILLS
function ZoneConfig.getSkillData(skillName)
	if not skillName then
		warn("[ZoneConfig] No skill name provided to getSkillData")
		return ZoneConfig.SKILLS["General"] -- Fallback to General
	end

	local skillData = ZoneConfig.SKILLS[skillName]
	if not skillData then
		warn("[ZoneConfig] Skill not found in SKILLS index: " .. skillName .. ". Using General.")
		return ZoneConfig.SKILLS["General"] -- Fallback to General
	end

	return skillData
end

-- Helper function to get zone colors with skill fallback
-- If zone specifies colorDark/colorLight, use those; otherwise use skill's colors
function ZoneConfig.getZoneColors(zoneName)
	local zoneConfig = ZoneConfig.ZONES[zoneName]
	if not zoneConfig then
		warn("[ZoneConfig] Zone not found: " .. zoneName .. ". Using General skill colors.")
		local skillData = ZoneConfig.SKILLS["General"]
		return { colorDark = skillData.colorDark, colorLight = skillData.colorLight }
	end

	local skillData = ZoneConfig.getSkillData(zoneConfig.skill)

	-- Use zone's explicit colors if set, otherwise fall back to skill's colors
	local colorDark = zoneConfig.colorDark or skillData.colorDark
	local colorLight = zoneConfig.colorLight or skillData.colorLight

	return { colorDark = colorDark, colorLight = colorLight }
end

-- Helper function to compute ImageRect for a sprite coordinate
-- Returns Rect2D for use with ImageLabel.ImageRect
function ZoneConfig.getImageRectFromSprite(spriteCoord)
	if not spriteCoord or not spriteCoord.x or not spriteCoord.y then
		warn("[ZoneConfig] Invalid sprite coordinate provided to getImageRectFromSprite")
		return Rect.new(0, 0, ZoneConfig.SPRITESHEET.cellSize, ZoneConfig.SPRITESHEET.cellSize)
	end

	local cellSize = ZoneConfig.SPRITESHEET.cellSize
	-- Convert 1-indexed grid position to pixel offset
	-- x=1 → 0px, x=2 → 320px, x=3 → 640px, etc.
	local offsetX = (spriteCoord.x - 1) * cellSize
	local offsetY = (spriteCoord.y - 1) * cellSize

	return Rect.new(offsetX, offsetY, offsetX + cellSize, offsetY + cellSize)
end

return ZoneConfig
