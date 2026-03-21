-- ============================================================
--  SkillsPageModule (ModuleScript)
--  Place inside: TemporaryMenus
--
--  Refactored: No more skill cards or ScrollingFrame.
--  Each SkillsGrid button opens directly to the skill breakdown.
--  Called by CentralizedMenuController via:
--    init(sharedRefs, skillsMenuFrame)
--    open(statKey) — shows breakdown for that skill immediately
--    close()       — called when navigating away (animated)
--    reset()       — called on menu hard-close (instant)
--    toggleRomanNumerals() — returns new useRomanNumerals state
-- ============================================================

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- ===================== AUDIO =====================
local UIClick = workspace:WaitForChild("UISounds"):WaitForChild("Click")
local UIClick3 = workspace:WaitForChild("UISounds"):WaitForChild("Click3")

-- ===================== MODULE STATE =====================
local initialized = false
local isOpen = false

local shared = nil
local TooltipModule = nil

-- Frame references (set by init)
local skillsMenuFrame = nil
local skillDescFrame = nil

-- ===================== ROMAN NUMERAL TABLE =====================
local ROMAN_DISPLAY = {
	[1] = "I",
	[2] = "II",
	[3] = "III",
	[4] = "IV",
	[5] = "V",
	[6] = "VI",
	[7] = "VII",
	[8] = "VIII",
	[9] = "IX",
	[10] = "X",
	[11] = "XI",
	[12] = "XII",
	[13] = "XIII",
	[14] = "XIV",
	[15] = "XV",
	[16] = "XVI",
	[17] = "XVII",
	[18] = "XVIII",
	[19] = "XIX",
	[20] = "XX",
	[21] = "XXI",
	[22] = "XXII",
	[23] = "XXIII",
	[24] = "XXIV",
	[25] = "XXV",
	[26] = "XXVI",
	[27] = "XXVII",
	[28] = "XXVIII",
	[29] = "XXIX",
	[30] = "XXX",
	[31] = "XXXI",
	[32] = "XXXII",
	[33] = "XXXIII",
	[34] = "XXXIV",
	[35] = "XXXV",
	[36] = "XXXVI",
	[37] = "XXXVII",
	[38] = "XXXVIII",
	[39] = "XXXIX",
	[40] = "XL",
	[41] = "XLI",
	[42] = "XLII",
	[43] = "XLIII",
	[44] = "XLIV",
	[45] = "XLV",
	[46] = "XLVI",
	[47] = "XLVII",
	[48] = "XLVIII",
	[49] = "XLIX",
	[50] = "L",
}

local function toRoman(n)
	return ROMAN_DISPLAY[math.clamp(n, 1, 50)] or tostring(n)
end

-- ===================== STATE =====================
local useRomanNumerals = true
local activeStatKey = nil
local currentLevelPage = 1
local latestSkillData = nil
local activeTooltipSlot = nil

-- ===================== ROMAN / NUMBER TOGGLE HELPERS =====================
local function displayLevel(n)
	if useRomanNumerals then
		return ROMAN_DISPLAY[math.clamp(n, 1, 50)] or tostring(n)
	else
		return tostring(n)
	end
end

local function displayLevelAlt(n)
	if useRomanNumerals then
		return tostring(n)
	else
		return ROMAN_DISPLAY[math.clamp(n, 1, 50)] or tostring(n)
	end
end

local function fmtLevelTitle(colorHex, skillName, level)
	local primary = displayLevel(level)
	local secondary = displayLevelAlt(level)
	return string.format(
		"<font color='%s'><b>%s</b> <b>%s</b></font>"
			.. "<font family='rbxasset://11598121416' weight='400' color='#555555'> (%s)</font>",
		colorHex,
		skillName,
		primary,
		secondary
	)
end

-- ===================== SKILL CONFIG (static data) =====================
local SKILL_CONFIG = {
	Farming = {
		stat = "Farming",
		description = "Farming skill increases your multipliers among all Farming buttons.",
		color = Color3.fromHex("#FFAA00"),
		hex = "#FFAA00",
	},
	Foraging = {
		stat = "Foraging",
		description = "Foraging skill increases your multipliers among all Foraging buttons.",
		color = Color3.fromHex("#00AA00"),
		hex = "#00AA00",
	},
	Fishing = {
		stat = "Fishing",
		description = "Fishing skill increases your multipliers among all Fishing buttons.",
		color = Color3.fromHex("#00AAAA"),
		hex = "#00AAAA",
	},
	Mining = {
		stat = "Mining",
		description = "Mining skill increases your multipliers among all Mining buttons.",
		color = Color3.fromHex("#5555FF"),
		hex = "#5555FF",
	},
	Combat = {
		stat = "Combat",
		description = "Combat skill increases your multipliers among all Combat buttons.",
		color = Color3.fromHex("#FF5555"),
		hex = "#FF5555",
	},
	Carpentry = {
		stat = "Carpentry",
		description = "Carpentry skill increases your multipliers when crafting Accessories, Armor, or other trinkets.",
		color = Color3.fromHex("#55FF55"),
		hex = "#55FF55",
	},
}

-- Ordered list for skill average calculation
local SKILL_ORDER = { "Farming", "Foraging", "Fishing", "Mining", "Combat", "Carpentry" }

-- ===================== SKILL DATA =====================
local DEFAULT_SKILL_DATA = {
	Farming = { level = 1, xp = 0, xpNeeded = 50, roman = "I", pct = 0 },
	Foraging = { level = 1, xp = 0, xpNeeded = 50, roman = "I", pct = 0 },
	Fishing = { level = 1, xp = 0, xpNeeded = 50, roman = "I", pct = 0 },
	Mining = { level = 1, xp = 0, xpNeeded = 50, roman = "I", pct = 0 },
	Combat = { level = 1, xp = 0, xpNeeded = 50, roman = "I", pct = 0 },
	Carpentry = { level = 1, xp = 0, xpNeeded = 50, roman = "I", pct = 0 },
}

local function getSkillEntry(statKey)
	if latestSkillData then
		local entry = latestSkillData[statKey]
		if entry and type(entry) == "table" then
			return entry
		end
	end
	return DEFAULT_SKILL_DATA[statKey] or { level = 1, xp = 0, xpNeeded = 50, roman = "I", pct = 0 }
end

-- ===================== SHORTHAND FORMATTER =====================
local function shorthand(n)
	if n >= 1000000 then
		local v = n / 1000000
		return (v == math.floor(v)) and (math.floor(v) .. "m") or (string.format("%.1f", v) .. "m")
	elseif n >= 1000 then
		local v = n / 1000
		return (v == math.floor(v)) and (math.floor(v) .. "k") or (string.format("%.1f", v) .. "k")
	end
	return tostring(n)
end

-- ===================== REWARD SYSTEM =====================
local GENERAL_REWARDS = {
	Farming = {
		{
			name = "Farmhand",
			color = "#FFFF55",
			stat = "♣ Farming Fortune",
			statColor = "#FFAA00",
			base = 4,
			desc = "\n		increases your chance for multiple crop \n		stats.",
		},
		{ label = { { text = "2 ", color = "#55FF55" }, { text = "♥ Health", color = "#FF5555" } } },
		{ label = { { text = "200 ", color = "#FFAA00" }, { text = "Coins", color = "#AAAAAA" } } },
		{ label = { { text = "5 ", color = "#FF55FF" }, { text = "Aetheric Nexus XP", color = "#FF55FF" } } },
	},
	Foraging = {
		{
			name = "Forager",
			color = "#FFFF55",
			stat = "♣ Foraging Fortune",
			statColor = "#FFAA00",
			base = 4,
			desc = "\n		increases your chance for multiple \n		wood stats.",
		},
		{ label = { { text = "0.25 ", color = "#55FF55" }, { text = "☯ Critical Chance", color = "#5555FF" } } },
		{ label = { { text = "200 ", color = "#FFAA00" }, { text = "Coins", color = "#AAAAAA" } } },
		{ label = { { text = "5 ", color = "#FF55FF" }, { text = "Aetheric Nexus XP", color = "#FF55FF" } } },
	},
	Fishing = {
		{
			name = "Fisher",
			color = "#FFFF55",
			stat = "♣ Fishing Fortune",
			statColor = "#FFAA00",
			base = 4,
			desc = "\n		increases your chance for multiple fish \n		stats.",
		},
		{ label = { { text = "0.01s ", color = "#FFFFFF" }, { text = "Reel Speed", color = "#00AAAA" } } },
		{ label = { { text = "200 ", color = "#FFAA00" }, { text = "Coins", color = "#AAAAAA" } } },
		{ label = { { text = "5 ", color = "#FF55FF" }, { text = "Aetheric Nexus XP", color = "#FF55FF" } } },
	},
	Mining = {
		{
			name = "Spelunker",
			color = "#FFFF55",
			stat = "♣ Mining Fortune",
			statColor = "#FFAA00",
			base = 4,
			desc = "\n		increases your chance for multiple ore \n		stats.",
		},
		{ label = { { text = "0.01s ", color = "#FFFFFF" }, { text = "Mine Speed", color = "#5555FF" } } },
		{ label = { { text = "200 ", color = "#FFAA00" }, { text = "Coins", color = "#AAAAAA" } } },
		{ label = { { text = "5 ", color = "#FF55FF" }, { text = "Aetheric Nexus XP", color = "#FF55FF" } } },
	},
	Combat = {
		{
			name = "Warrior",
			color = "#FFFF55",
			stat = "☀ Combat Defense",
			statColor = "#55FF55",
			base = 1,
			desc = "\n		which defends against combat button \n		attacks.",
		},
		{ label = { { text = "1 ", color = "#FFFFFF" }, { text = "Defense", color = "#55FF55" } } },
		{ label = { { text = "200 ", color = "#FFAA00" }, { text = "Coins", color = "#AAAAAA" } } },
		{ label = { { text = "5 ", color = "#FF55FF" }, { text = "Aetheric Nexus XP", color = "#FF55FF" } } },
	},
	Carpentry = {
		{
			name = "Artisan",
			color = "#FFFF55",
			stat = "Crafting Quality",
			statColor = "#FFAA00",
			base = 4,
			desc = "\n		increases your quality of crafted items.",
		},
		{ label = { { text = "0.01 ", color = "#FFFFFF" }, { text = "Build Quality", color = "#55FF55" } } },
		{ label = { { text = "200 ", color = "#FFAA00" }, { text = "Coins", color = "#AAAAAA" } } },
		{ label = { { text = "5 ", color = "#FF55FF" }, { text = "Aetheric Nexus XP", color = "#FF55FF" } } },
	},
}

local SPECIFIC_REWARDS = {
	Farming = {
		[5] = { { label = "Crop Storage +10", color = "#55FFFF", special = true } },
		[10] = {
			{ label = "Farming Buttons 2 Unlocked", color = "#FFAA00", special = true },
			{ label = "+5% Crop Yield (Milestone)", color = "#55FF55", special = false },
		},
		[15] = { { label = "Auto-Harvest Ability Unlocked", color = "#FF55FF", special = true } },
		[20] = {
			{ label = "Farming Buttons 3 Unlocked", color = "#FFAA00", special = true },
			{ label = "+10% Harvest Speed (Milestone)", color = "#FFAA00", special = false },
		},
		[25] = {
			{ label = "Master Farmer Title", color = "#FFD700", special = true },
			{ label = "Rare Seed Drop Chance +2%", color = "#FF55FF", special = false },
		},
		[30] = { { label = "Farming Buttons 4 Unlocked", color = "#FFAA00", special = true } },
		[40] = {
			{ label = "Farming Buttons 5 Unlocked", color = "#FFAA00", special = true },
			{ label = "Legendary Seed Access", color = "#FFD700", special = true },
		},
		[50] = {
			{ label = "MAX LEVEL — Grandmaster Farmer", color = "#FFD700", special = true },
			{ label = "Exclusive Farm Pet Unlocked", color = "#FF55FF", special = true },
			{ label = "+25% All Farming Stats", color = "#55FF55", special = false },
		},
	},
	Foraging = {
		[5] = { { label = "Forage Bag Slot +5", color = "#55FFFF", special = true } },
		[10] = {
			{ label = "Foraging Area 2 Unlocked", color = "#00AA00", special = true },
			{ label = "+5% Rare Find Chance", color = "#55FF55", special = false },
		},
		[15] = { { label = "Night Foraging Unlocked", color = "#FF55FF", special = true } },
		[20] = { { label = "Foraging Area 3 Unlocked", color = "#00AA00", special = true } },
		[25] = {
			{ label = "Master Forager Title", color = "#FFD700", special = true },
			{ label = "Legendary Herb Chance +1%", color = "#FF55FF", special = false },
		},
		[50] = {
			{ label = "MAX LEVEL — Grandmaster Forager", color = "#FFD700", special = true },
			{ label = "+25% All Foraging Stats", color = "#55FF55", special = false },
		},
	},
	Fishing = {
		[5] = { { label = "Fishing Rod Upgrade Slot", color = "#55FFFF", special = true } },
		[10] = {
			{ label = "Deep Sea Fishing Unlocked", color = "#00AAAA", special = true },
			{ label = "+5% Rare Fish Chance", color = "#55FF55", special = false },
		},
		[15] = { { label = "Night Fishing Unlocked", color = "#FF55FF", special = true } },
		[20] = { { label = "Fishing Spot 3 Unlocked", color = "#00AAAA", special = true } },
		[25] = {
			{ label = "Master Angler Title", color = "#FFD700", special = true },
			{ label = "Legendary Fish Chance +1%", color = "#FF55FF", special = false },
		},
		[50] = {
			{ label = "MAX LEVEL — Grandmaster Angler", color = "#FFD700", special = true },
			{ label = "+25% All Fishing Stats", color = "#55FF55", special = false },
		},
	},
	Mining = {
		[5] = { { label = "Ore Bag Slot +5", color = "#55FFFF", special = true } },
		[10] = {
			{ label = "Deep Mine Access Unlocked", color = "#5555FF", special = true },
			{ label = "+5% Gem Find Chance", color = "#55FF55", special = false },
		},
		[15] = { { label = "Dynamite Ability Unlocked", color = "#FF5555", special = true } },
		[20] = {
			{ label = "Mine Level 3 Unlocked", color = "#5555FF", special = true },
			{ label = "+10% Ore Yield (Milestone)", color = "#FFAA00", special = false },
		},
		[25] = {
			{ label = "Master Miner Title", color = "#FFD700", special = true },
			{ label = "Legendary Ore Chance +1%", color = "#FF55FF", special = false },
		},
		[50] = {
			{ label = "MAX LEVEL — Grandmaster Miner", color = "#FFD700", special = true },
			{ label = "Exclusive Mining Pet Unlocked", color = "#FF55FF", special = true },
			{ label = "+25% All Mining Stats", color = "#55FF55", special = false },
		},
	},
	Combat = {
		[5] = { { label = "Combo Multiplier Unlocked", color = "#55FFFF", special = true } },
		[10] = {
			{ label = "Dual Wield Unlocked", color = "#FF5555", special = true },
			{ label = "+5% Critical Damage", color = "#55FF55", special = false },
		},
		[15] = { { label = "Parry Ability Unlocked", color = "#FF55FF", special = true } },
		[20] = {
			{ label = "Combat Arena 3 Unlocked", color = "#FF5555", special = true },
			{ label = "+10% All Damage (Milestone)", color = "#FFAA00", special = false },
		},
		[25] = {
			{ label = "Master Combatant Title", color = "#FFD700", special = true },
			{ label = "Berserker Passive Unlocked", color = "#FF55FF", special = false },
		},
		[50] = {
			{ label = "MAX LEVEL — Grandmaster Warrior", color = "#FFD700", special = true },
			{ label = "Exclusive Combat Pet Unlocked", color = "#FF55FF", special = true },
			{ label = "+25% All Combat Stats", color = "#55FF55", special = false },
		},
	},
	Carpentry = {
		[5] = { { label = "Blueprint Slot +1", color = "#55FFFF", special = true } },
		[10] = {
			{ label = "Advanced Crafting Unlocked", color = "#55FF55", special = true },
			{ label = "+5% Material Efficiency", color = "#55FF55", special = false },
		},
		[15] = { { label = "Auto-Craft Ability Unlocked", color = "#FF55FF", special = true } },
		[20] = {
			{ label = "Master Workbench Unlocked", color = "#55FF55", special = true },
			{ label = "+10% Craft Speed (Milestone)", color = "#FFAA00", special = false },
		},
		[25] = {
			{ label = "Master Carpenter Title", color = "#FFD700", special = true },
			{ label = "Legendary Blueprint Access", color = "#FF55FF", special = false },
		},
		[50] = {
			{ label = "MAX LEVEL — Grandmaster Crafter", color = "#FFD700", special = true },
			{ label = "Exclusive Carpentry Pet", color = "#FF55FF", special = true },
			{ label = "+25% All Carpentry Stats", color = "#55FF55", special = false },
		},
	},
}

local function fmtVal(base, level)
	local v = base * level
	if v == math.floor(v) then
		return tostring(math.floor(v))
	end
	return string.format("%.2f", v)
end

local function renderLabel(r)
	local prefix = "<font color='#555555'>\t+</font>"
	if type(r.label) == "table" then
		local parts = {}
		for _, seg in ipairs(r.label) do
			table.insert(parts, "<font color='" .. seg.color .. "'>" .. seg.text .. "</font>")
		end
		return prefix .. table.concat(parts)
	else
		return prefix .. "<font color='" .. r.color .. "'>" .. r.label .. "</font>"
	end
end

local function buildRewardText(skillName, level)
	local lines = {}
	local general = GENERAL_REWARDS[skillName]
	if general then
		for _, r in ipairs(general) do
			if r.name then
				table.insert(
					lines,
					"	<font color='" .. r.color .. "'><b>" .. r.name .. " " .. displayLevel(level) .. "</b></font>"
				)
				local currVal = "+" .. fmtVal(r.base, level)
				local valStr
				if level <= 1 then
					valStr = "<font color='#55FF55'><b>" .. currVal .. "</b></font>"
				else
					local prevVal = "+" .. fmtVal(r.base, level - 1)
					valStr = "<font color='#777777'>"
						.. prevVal
						.. "</font>"
						.. "<font color='#555555'>→</font>"
						.. "<font color='#55FF55'><b>"
						.. currVal
						.. "</b></font>"
				end
				local statPart = "<font color='" .. r.statColor .. "'><b>" .. r.stat .. "</b></font>"
				local descPart = (r.desc and r.desc ~= "") and "<font color='#FFFFFF'>, " .. r.desc .. "</font>" or ""
				table.insert(lines, "		<font color='#FFFFFF'>Grants </font>" .. valStr .. " " .. statPart .. descPart)
			else
				table.insert(lines, renderLabel(r))
			end
		end
	end
	local specific = SPECIFIC_REWARDS[skillName] and SPECIFIC_REWARDS[skillName][level]
	if specific and #specific > 0 then
		if #lines > 0 then
			table.insert(lines, "")
		end
		for _, r in ipairs(specific) do
			local prefix = r.special and "<font color='#FFD700'>★ </font>" or "<font color='#555555'>‣ </font>"
			table.insert(lines, prefix .. "<font color='" .. r.color .. "'>" .. r.label .. "</font>")
		end
	end
	if #lines == 0 then
		return "<font color='#555555'>No rewards defined for this level.</font>"
	end
	return table.concat(lines, "\n")
end

-- ===================== DESC FRAME REFERENCES (set in init) =====================
local statNameLabel = nil
local statUIStroke = nil
local statUnderline = nil
local descLabel = nil
local line = nil
local statValueLabel = nil
local skillLevelsFrame = nil
local levelScrollFrame = nil
local pageToggleButton = nil
local levelGradient = nil

local DEFAULT_SKILLLEVELS_BG = nil
local DEFAULT_SKILLLEVELS_STROKE = nil

-- ===================== LEVEL BOX CONSTANTS =====================
local SLOT_NAMES = {
	"I",
	"II",
	"III",
	"IV",
	"V",
	"VI",
	"VII",
	"VIII",
	"IX",
	"X",
	"XI",
	"XII",
	"XIII",
	"XIV",
	"XV",
	"XVI",
	"XVII",
	"XVIII",
	"XIX",
	"XX",
	"XXI",
	"XXII",
	"XXIII",
	"XXIV",
	"XXV",
}
local COLOR_COMPLETE = Color3.fromHex("55FF55")
local COLOR_CURRENT = Color3.fromHex("FFFF55")
local COLOR_LOCKED = Color3.fromHex("FF5555")

-- ===================== SHADOW SYSTEM =====================
local SHADOW_DELAY = 0.5
local CANVAS_MAX_X = 251
local BUFFER_PX = 35
local shadowTimer = 0
local shadowActive = false
local shadowTween = nil
local lastCanvasX = 0

local GRAD_RIGHT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.75, 1),
	NumberSequenceKeypoint.new(1, 0),
})
local GRAD_LEFT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 1),
	NumberSequenceKeypoint.new(1, 1),
})
local GRAD_BOTH = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.25, 1),
	NumberSequenceKeypoint.new(0.75, 1),
	NumberSequenceKeypoint.new(1, 0),
})

local function getTargetGradient(canvasX)
	if canvasX <= BUFFER_PX then
		return GRAD_RIGHT
	elseif canvasX >= CANVAS_MAX_X - BUFFER_PX then
		return GRAD_LEFT
	else
		return GRAD_BOTH
	end
end

local function showShadow(canvasX)
	if shadowActive then
		return
	end
	shadowActive = true
	levelGradient.Transparency = getTargetGradient(canvasX)
	if shadowTween then
		shadowTween:Cancel()
	end
	shadowTween = TweenService:Create(
		levelScrollFrame,
		TweenInfo.new(2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.5 }
	)
	shadowTween:Play()
end

local function hideShadow()
	if not shadowActive then
		return
	end
	shadowActive = false
	shadowTimer = 0
	if shadowTween then
		shadowTween:Cancel()
	end
	shadowTween = TweenService:Create(
		levelScrollFrame,
		TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	shadowTween:Play()
end

-- ===================== TYPEWRITER =====================
local typewriterThreads = {}

local function typewriteCore(label, text, speed, sound)
	speed = speed or 0.03
	if typewriterThreads[label] then
		typewriterThreads[label] = false
	end
	local token = {}
	typewriterThreads[label] = token
	label.Text = text
	label.MaxVisibleGraphemes = 0
	local length = utf8.len(text) or #text
	task.spawn(function()
		for i = 1, length do
			if typewriterThreads[label] ~= token then
				return
			end
			label.MaxVisibleGraphemes = i
			if sound then
				UIClick3:Play()
			end
			task.wait(speed)
		end
		label.MaxVisibleGraphemes = -1
		if typewriterThreads[label] == token then
			typewriterThreads[label] = nil
		end
	end)
end

local function typewrite(label, text, speed)
	typewriteCore(label, text, speed, false)
end

-- ===================== TWEEN HELPER =====================
local uiTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local function _tween(object, properties)
	TweenService:Create(object, uiTweenInfo, properties):Play()
end

-- ===================== UPDATE SKILL LEVEL BOXES =====================
local function updateSkillLevelBoxes(statKey)
	if not statKey then
		return
	end
	local skillData = getSkillEntry(statKey)
	local playerLevel = skillData.level or 1
	local pageOffset = (currentLevelPage - 1) * 25

	for slotIndex, slotName in ipairs(SLOT_NAMES) do
		local button = levelScrollFrame:FindFirstChild(slotName)
		if not button then
			continue
		end
		local label = button:FindFirstChild("Label")
		local uiStroke = button:FindFirstChildOfClass("UIStroke")
		local realLevel = pageOffset + slotIndex
		local colour
		if realLevel <= playerLevel then
			colour = COLOR_COMPLETE
		elseif realLevel == playerLevel + 1 then
			colour = COLOR_CURRENT
		else
			colour = COLOR_LOCKED
		end
		button.BackgroundColor3 = colour
		if uiStroke then
			uiStroke.Color = colour
		end
		if label then
			label.TextColor3 = colour
			label.Text = displayLevel(realLevel)
		end
	end

	local toggleLabel = pageToggleButton:FindFirstChild("Label")
	if toggleLabel then
		toggleLabel.Text = currentLevelPage == 1
				and displayLevel(26) .. " – " .. displayLevel(50) .. " <font color='#FFFF55'>▶</font>"
			or "<font color='#FFFF55'>◀</font> " .. displayLevel(1) .. " – " .. displayLevel(25)
	end
end

-- ===================== STAT COLOR =====================
local function applyStatColor(color)
	statNameLabel.TextColor3 = color
	statUIStroke.Color = color
	statUnderline.BackgroundColor3 = color
	line.BackgroundColor3 = color
	line.UIStroke.Color = color
	skillDescFrame.StatNameVal.StatValue.Underline.BackgroundColor3 = color
	skillLevelsFrame.BackgroundColor3 = color
	skillLevelsFrame.UIStroke.Color = color
end

local function revertStatColor()
	skillLevelsFrame.BackgroundColor3 = DEFAULT_SKILLLEVELS_BG
	skillLevelsFrame.UIStroke.Color = DEFAULT_SKILLLEVELS_STROKE
end

-- ===================== TOOLTIP: LEVEL BOXES =====================
local tooltipFromLevels = false

local function showLevelTooltip(slotIndex)
	if not activeStatKey then
		return
	end
	local config = SKILL_CONFIG[activeStatKey]
	if not config then
		return
	end

	activeTooltipSlot = slotIndex

	local realLevel = (currentLevelPage - 1) * 25 + slotIndex
	local skillData = getSkillEntry(activeStatKey)
	local playerLevel = skillData.level or 1

	local statusHex
	if realLevel <= playerLevel then
		statusHex = "#55FF55"
	elseif realLevel == playerLevel + 1 then
		statusHex = "#FFFF55"
	else
		statusHex = "#FF5555"
	end

	local tt = TooltipModule.refs
	tt.Title.Text = fmtLevelTitle(statusHex, config.stat, realLevel)

	tt.Desc.Visible = false
	tt.Rewards.Text = "<font color='#AAAAAA'>Rewards:</font>\n" .. buildRewardText(config.stat, realLevel)
	tt.Rewards.Visible = true
	tt.Stats.Visible = false
	tt.Click.Visible = false
	tt.Divider1.Visible = false
	UIClick3:Play()

	local isCurrentGoal = (realLevel == playerLevel + 1)
	tt.Divider2.Visible = isCurrentGoal
	tt.ProgressOuter.Visible = isCurrentGoal
	tt.ProgressLabel.Visible = isCurrentGoal

	if isCurrentGoal then
		local pct = skillData.pct or 0
		local xp = skillData.xp or 0
		local xpNeeded = skillData.xpNeeded or 50
		tt.ProgressLabel.Text = "Progress: <font color='#FFFF55'>" .. math.floor(pct * 100) .. "%</font>"
		tt.ProgressBL.Text = shorthand(xp) .. "<font color='#FFAA00'>/</font>" .. shorthand(xpNeeded)
		TooltipModule.tweenProgressFill(pct)
	end

	tt.Rewards.LayoutOrder = 4
	tt.ProgressLabel.LayoutOrder = 7
	tt.ProgressOuter.LayoutOrder = 8

	tooltipFromLevels = true
	TooltipModule.showRaw("skillLevels")
end

local function hideLevelTooltip()
	if not tooltipFromLevels then
		return
	end
	TooltipModule.hide("skillLevels")
	tooltipFromLevels = false
	activeTooltipSlot = nil
end

-- ===================== GRID-LEVEL SKILL TOOLTIPS =====================
local gridTooltipActive = false
local gridTooltipStatKey = nil

local function showGridSkillTooltip(statKey, silent)
	if not initialized then
		return
	end
	local config = SKILL_CONFIG[statKey]
	if not config then
		return
	end

	local skillData = getSkillEntry(statKey)
	local level = skillData.level or 1
	local isMax = level >= 50

	local tt = TooltipModule.refs
	tt.Title.Text = fmtLevelTitle(config.hex, config.stat, level)

	tt.Stats.Visible = false
	tt.Desc.Visible = true
	tt.Divider1.Visible = true
	tt.Divider3.Visible = true
	tt.Desc.Text = "<font color='#AAAAAA'>" .. config.description .. "</font>"
	tt.Click.Text = "Click to view!"
	tt.Click.Visible = true
	if not silent then
		UIClick3:Play()
	end

	if isMax then
		tt.Rewards.Text =
			"<font color='#AAAAAA'>This skill has reached </font><font color='#FFD700'><b>MAX LEVEL</b></font><font color='#AAAAAA'>.</font>"
		tt.Rewards.Visible = true
		tt.Divider2.Visible = false
		tt.ProgressOuter.Visible = false
		tt.ProgressLabel.Visible = false
	else
		local nextLevel = level + 1
		local pct = skillData.pct or 0
		local xp = skillData.xp or 0
		local xpNeeded = skillData.xpNeeded or 50

		tt.ProgressLabel.Text = "Progress to Level "
			.. displayLevel(nextLevel)
			.. ": <font color='#FFFF55'>"
			.. math.floor(pct * 100)
			.. "%</font>"
		tt.ProgressBL.Text = shorthand(xp) .. "<font color='#FFAA00'>/</font>" .. shorthand(xpNeeded)
		TooltipModule.tweenProgressFill(pct)
		tt.ProgressOuter.Visible = true
		tt.ProgressLabel.Visible = true
		tt.Divider2.Visible = true

		tt.Rewards.Text = "<font color='#AAAAAA'>Level "
			.. displayLevel(nextLevel)
			.. " Rewards:</font>\n"
			.. buildRewardText(config.stat, nextLevel)
		tt.Rewards.Visible = true
	end

	tt.Rewards.LayoutOrder = 4
	tt.ProgressLabel.LayoutOrder = 7
	tt.ProgressOuter.LayoutOrder = 8

	gridTooltipActive = true
	gridTooltipStatKey = statKey
	TooltipModule.showRaw("skillGrid")
end

local function hideGridSkillTooltip()
	if not gridTooltipActive then
		return
	end
	TooltipModule.hide("skillGrid")
	gridTooltipActive = false
	gridTooltipStatKey = nil
end

local function refreshGridSkillTooltip(statKey)
	if not gridTooltipActive then
		return
	end
	if gridTooltipStatKey ~= statKey then
		return
	end
	showGridSkillTooltip(statKey, true)
end

-- ===================== MODULE API =====================
local M = {}

function M.init(sharedRefs, frame)
	if initialized then
		return
	end
	initialized = true

	shared = sharedRefs
	TooltipModule = sharedRefs.TooltipModule
	skillsMenuFrame = frame

	skillDescFrame = skillsMenuFrame:WaitForChild("SkillDescFrame")

	statNameLabel = skillDescFrame.StatNameVal.StatName
	statUIStroke = statNameLabel.UIStroke
	statUnderline = statNameLabel.Underline
	descLabel = skillDescFrame.Desc.DescLabel
	line = skillDescFrame.StatNameVal.LineDivider.Line
	statValueLabel = skillDescFrame.StatNameVal.StatValue

	skillLevelsFrame = skillDescFrame.SkillLevels
	levelScrollFrame = skillLevelsFrame:WaitForChild("ScrollingFrame")
	pageToggleButton = skillLevelsFrame:WaitForChild("PageToggle")
	levelGradient = levelScrollFrame:WaitForChild("UIGradient")

	DEFAULT_SKILLLEVELS_BG = skillLevelsFrame.BackgroundColor3
	DEFAULT_SKILLLEVELS_STROKE = skillLevelsFrame.UIStroke.Color

	-- Position: breakdown is the only view now
	skillDescFrame.Position = UDim2.new(0, 0, 0, 0)

	-- ===================== WIRE LEVEL BOX TOOLTIPS (ONCE) =====================
	for slotIndex, slotName in ipairs(SLOT_NAMES) do
		local button = levelScrollFrame:WaitForChild(slotName)
		local capturedIndex = slotIndex
		button.MouseEnter:Connect(function()
			showLevelTooltip(capturedIndex)
		end)
		button.MouseLeave:Connect(function()
			hideLevelTooltip()
		end)
	end

	-- ===================== PAGE TOGGLE BUTTON =====================
	pageToggleButton.MouseButton1Click:Connect(function()
		currentLevelPage = (currentLevelPage == 1) and 2 or 1
		UIClick:Play()
		updateSkillLevelBoxes(activeStatKey)
	end)

	-- ===================== SHADOW SYSTEM: CANVAS SCROLL =====================
	levelScrollFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local newX = levelScrollFrame.CanvasPosition.X
		if math.abs(newX - lastCanvasX) > 0.5 then
			lastCanvasX = newX
			shadowTimer = 0
			hideShadow()
		end
	end)

	-- ===================== HEARTBEAT: STAT VALUE + SHADOW =====================
	local lastDisplayedLevel = nil
	local lastDisplayedKey = nil

	RunService.Heartbeat:Connect(function(dt)
		if isOpen and activeStatKey then
			local skillData = getSkillEntry(activeStatKey)
			local level = skillData.level or 1
			if level ~= lastDisplayedLevel or activeStatKey ~= lastDisplayedKey then
				lastDisplayedLevel = level
				lastDisplayedKey = activeStatKey
				statValueLabel.Text = displayLevel(level)
			end
		end

		if not isOpen or not activeStatKey then
			if shadowActive then
				hideShadow()
			end
			shadowTimer = 0
			return
		end
		shadowTimer = shadowTimer + dt
		if shadowTimer >= SHADOW_DELAY and not shadowActive then
			showShadow(levelScrollFrame.CanvasPosition.X)
		end
	end)

	-- ===================== SERVER SKILL SYNC =====================
	local SkillUpdated = ReplicatedStorage:WaitForChild("SkillUpdated", 10)

	local function sanitizeSkillData(data)
		if type(data) ~= "table" then
			return
		end
		for _, skillData in pairs(data) do
			if type(skillData) == "table" then
				skillData.level = tonumber(skillData.level) or 1
				skillData.xp = tonumber(skillData.xp) or 0
				skillData.xpNeeded = tonumber(skillData.xpNeeded) or 50
				skillData.roman = tostring(skillData.roman or "I")
				skillData.pct = tonumber(skillData.pct) or 0
			end
		end
	end

	if SkillUpdated then
		SkillUpdated.OnClientEvent:Connect(function(data)
			sanitizeSkillData(data)
			latestSkillData = data
			if activeStatKey then
				updateSkillLevelBoxes(activeStatKey)
			end
			for statKey in pairs(data) do
				refreshGridSkillTooltip(statKey)
			end
		end)
	end

	print("SkillsPageModule: Initialized ✓")
end

--- Called when user clicks a skill on the SkillsGrid.
--- statKey is passed via buttonConfig.openArg from the controller.
function M.open(statKey)
	isOpen = true
	activeStatKey = statKey
	currentLevelPage = 1

	local config = SKILL_CONFIG[statKey]
	if not config then
		warn("[SkillsPageModule] Unknown statKey: " .. tostring(statKey))
		return
	end

	skillDescFrame.Position = UDim2.new(0, 0, 0, 0)
	applyStatColor(config.color)
	updateSkillLevelBoxes(statKey)
	statNameLabel.Text = config.stat
	descLabel.Text = ""
	descLabel.MaxVisibleGraphemes = -1

	local skillData = getSkillEntry(statKey)
	statValueLabel.Text = displayLevel(skillData.level or 1)

	task.delay(0.25, function()
		if activeStatKey == statKey then
			typewrite(descLabel, config.description, 0.025)
		end
	end)
end

function M.close()
	isOpen = false
	hideLevelTooltip()
	revertStatColor()
	activeStatKey = nil
	currentLevelPage = 1
end

function M.reset()
	isOpen = false
	hideLevelTooltip()
	revertStatColor()
	activeStatKey = nil
	currentLevelPage = 1
	descLabel.Text = ""
	descLabel.MaxVisibleGraphemes = -1
	skillDescFrame.Position = UDim2.new(0, 0, 0, 0)
end

function M.navigateBack()
	-- No internal navigation — controller handles grid return
end

M.showGridSkillTooltip = showGridSkillTooltip
M.hideGridSkillTooltip = hideGridSkillTooltip

return M
