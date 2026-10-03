--[[
	Items/Define (ModuleScript)

	Turns a short item spec (what you type in Items/Defs/*.lua) into the full
	normalized definition the rest of the game reads. Fills defaults and warns
	about mistakes (unknown stat, bad slot, bad rarity) instead of failing late.

	SPEC FIELDS (all optional except name):
	  name         string   display name (also the Tool name unless toolName given)
	  description  string   rich text OK
	  rarity       0-5
	  slot         "Helmet" ... (armor / accessory only; see Items/Slots)
	  stats        { Strength = 50, Defense = {flat=5, mult=0.1}, Damage = 250 }
	  weapon       { weaponType, attackSpeed, knockback, range }   (weapons)
	  abilities    { { name, key, text, cooldown, type }, ... }

	  -- tooltip template toggles (each section appears only when you set it) --
	  typeTag      badge text   (defaults from category: Weapon, Armor ...)
	  skillTag     badge text   (Combat, Farming ... uses skill color)
	  showRarityTag false hides rarity badge
	  customTags   { { text, color }, ... }
	  level        number | "LV. 5"
	  statsTitle   header text (default STATS)
	  displayStats extra display-only rows { { name, value, color, icon }, ... }
	  footer       small note under the abilities
	  clickHint    string | { text, color, icon }

	  icon         optional: icon key | "rbxassetid://" | { image, rectOffset, rectSize }; omit to use
	               ItemIcons (ALIASES[id] or the key equal to the id), see ItemIcons.lua
	  maxStack, toolName
--]]

local Slots = require(script.Parent:WaitForChild("Slots"))
local Stats = require(script.Parent:WaitForChild("Stats"))

local Define = {}

local CATEGORY_DEFAULTS = {
	weapon = { typeTag = "Weapon", maxStack = 1 },
	armor = { typeTag = "Armor", maxStack = 1 },
	accessory = { typeTag = "Accessory", maxStack = 1 },
	material = { typeTag = "Resource", maxStack = 999 },
	consumable = { typeTag = "Consumable", maxStack = 999 },
	misc = { maxStack = 999 },
}

local WEAPON_DEFAULTS = { weaponType = "sword", attackSpeed = 1, knockback = 10, range = 20 }

local function warnItem(id: string, message: string)
	warn(string.format("[Items] %s: %s", id, message))
end

--- Build the normalized definition. `category` is the fallback when the spec
--- doesn't name one (it comes from the Defs file the item lives in).
function Define.item(id: string, spec: any, category: string?): any
	local cat = spec.category or category or "misc"
	local defaults = CATEGORY_DEFAULTS[cat]
	if not defaults then
		warnItem(id, "unknown category '" .. tostring(cat) .. "', using misc")
		cat = "misc"
		defaults = CATEGORY_DEFAULTS.misc
	end

	local name = spec.name or spec.displayName
	if not name or name == "" then
		warnItem(id, "missing name, using id")
		name = id
	end

	local rarity = spec.rarity or 0
	if type(rarity) ~= "number" or rarity < 0 or rarity > 6 then
		warnItem(id, "rarity must be 0-6, got " .. tostring(rarity))
		rarity = 0
	end

	-- Slot only means something for armor / accessories.
	local slot = spec.slot
	if cat == "armor" or cat == "accessory" then
		local slotDef = slot and Slots.get(slot)
		if not slotDef then
			warnItem(id, "needs a valid `slot` (" .. table.concat(Slots.Order, ", ") .. ")")
			slot = nil
		elseif slotDef.type ~= cat then
			warnItem(id, string.format("slot %s is for %ss, not %ss", slot, slotDef.type, cat))
			slot = nil
		end
	elseif slot then
		warnItem(id, "slot is only valid on armor / accessory items; ignoring")
		slot = nil
	end

	local stats = spec.stats or {}
	for key in pairs(stats) do
		if not Stats.isKnown(key) then
			warnItem(id, "unknown stat '" .. tostring(key) .. "' (use a ProfileConfig attribute key or Damage)")
		end
	end

	local abilities = {}
	for _, ability in ipairs(spec.abilities or {}) do
		local entry = table.clone(ability)
		entry.type = entry.type or (entry.cooldown and "active" or "passive")
		table.insert(abilities, entry)
	end

	local weapon = nil
	if cat == "weapon" then
		weapon = table.clone(WEAPON_DEFAULTS)
		for k, v in pairs(spec.weapon or {}) do
			weapon[k] = v
		end
	end

	return {
		id = id,
		displayName = name,
		description = spec.description or "",
		rarity = rarity,
		category = cat,
		slot = slot,
		icon = spec.icon or "",
		maxStack = spec.maxStack or defaults.maxStack,
		toolName = spec.toolName or name,
		stats = stats,
		weapon = weapon,
		abilities = abilities,

		typeTag = spec.typeTag or defaults.typeTag,
		skillTag = spec.skillTag,
		showRarityTag = spec.showRarityTag,
		customTags = spec.customTags,
		level = spec.level,
		statsTitle = spec.statsTitle,
		displayStats = spec.displayStats,
		footer = spec.footer,
		clickHint = spec.clickHint,

		-- Legacy field kept so older readers don't nil-index.
		statBonuses = {},
	}
end

return Define
