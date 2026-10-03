-- ============================================================
--  ButtonRegistry (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Single source of truth for every clickable button in the game.
--  Mirrors ItemRegistry's pattern: one config table, lookup API.
--
--  Adding a new button = adding one entry to Buttons table.
--  The world ButtonPart references its config via the "ButtonId"
--  attribute, which must match the table key.
--
--  API:
--    ButtonRegistry.get(buttonId)         → config table or nil
--    ButtonRegistry.exists(buttonId)      → bool
--    ButtonRegistry.getBySkill(skillName) → array of configs for that skill
--    ButtonRegistry.Buttons               → full table (read-only use)
-- ============================================================

local ButtonRegistry = {}

-- ===================== DEFAULTS =====================
-- Pulled when a button entry omits these fields.
ButtonRegistry.Defaults = {
	visibilityDistance = 30, -- studs; tween-in radius
	tweenInTime = 0.35,
	tweenOutTime = 0.25,
	cost = {}, -- { itemId = amount } required to click
	reward = {}, -- { itemId = amount } given on click
	resetsOnRebirth = true, -- drives "NO RESET" tag
	skill = "General",
}

-- ===================== SKILL THEME LOOKUP =====================
-- Per-skill colors for the SkillTag and reward text accents.
-- Keep in sync with SkillsDataManager skill colors.
ButtonRegistry.SkillThemes = {
	Farming = { color = Color3.fromHex("#F2C94C"), display = "FARMING" },
	Foraging = { color = Color3.fromHex("#27AE60"), display = "FORAGING" },
	Fishing = { color = Color3.fromHex("#56CCF2"), display = "FISHING" },
	Mining = { color = Color3.fromHex("#BDBDBD"), display = "MINING" },
	Combat = { color = Color3.fromHex("#EB5757"), display = "COMBAT" },
	Carpentry = { color = Color3.fromHex("#BB6BD9"), display = "CARPENTRY" },
	General = { color = Color3.fromHex("#FFFFFF"), display = "GENERAL" },
}

-- ===================== BUTTON DEFINITIONS =====================
-- Fields per entry:
--   id                 : string — must match table key
--   displayName        : string — shown in NameReward.Name
--   tier               : number — Roman numeral tier (1, 2, 3...)
--   skill              : string — matches SkillThemes key
--   cost               : table  — { itemId = amount } consumed per click
--   reward             : table  — { itemId = amount } awarded per click
--   resetsOnRebirth    : bool   — false → shows "NO RESET" tag
--   visibilityDistance : number — override Defaults.visibilityDistance
--
-- The world part's "ButtonId" attribute must equal the table key.

ButtonRegistry.Buttons = {

	-- ── Foraging ──
	foraging_wood_1 = {
		id = "foraging_wood_1",
		displayName = "Wood Button",
		tier = 1,
		skill = "Foraging",
		cost = { sticks = 100 },
		reward = { wood = 100 },
		resetsOnRebirth = false,
		visibilityDistance = 30,
	},

	foraging_wood_2 = {
		id = "foraging_wood_2",
		displayName = "Wood Button",
		tier = 2,
		skill = "Foraging",
		cost = { wood = 500 },
		reward = { plank = 100 },
		resetsOnRebirth = false,
	},

	-- ── Farming ──
	farming_sticks_1 = {
		id = "farming_sticks_1",
		displayName = "Stick Button",
		tier = 1,
		skill = "Farming",
		cost = {},
		reward = { sticks = 1 },
		resetsOnRebirth = false,
	},

	-- Add more here. One entry per tier per skill.
}

-- ===================== HELPERS =====================

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }
function ButtonRegistry.toRoman(n: number): string
	return ROMAN[n] or tostring(n)
end

-- ===================== API =====================

--- Get a full button config by id, with defaults merged in.
function ButtonRegistry.get(buttonId: string)
	local raw = ButtonRegistry.Buttons[buttonId]
	if not raw then
		return nil
	end

	-- Merge defaults (shallow) without mutating original
	local merged = {}
	for k, v in pairs(ButtonRegistry.Defaults) do
		merged[k] = v
	end
	for k, v in pairs(raw) do
		merged[k] = v
	end
	return merged
end

function ButtonRegistry.exists(buttonId: string): boolean
	return ButtonRegistry.Buttons[buttonId] ~= nil
end

function ButtonRegistry.getTheme(skill: string)
	return ButtonRegistry.SkillThemes[skill] or ButtonRegistry.SkillThemes.General
end

--- Get every button config belonging to a skill.
function ButtonRegistry.getBySkill(skillName: string)
	local out = {}
	for id, _ in pairs(ButtonRegistry.Buttons) do
		local cfg = ButtonRegistry.get(id)
		if cfg.skill == skillName then
			table.insert(out, cfg)
		end
	end
	table.sort(out, function(a, b)
		return (a.tier or 0) < (b.tier or 0)
	end)
	return out
end

print("ButtonRegistry: Loaded ✓")
return ButtonRegistry
