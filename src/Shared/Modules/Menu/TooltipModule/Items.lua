--[[
	TooltipModule/Items (ModuleScript)

	Turns an inventory item into a tooltip config. This is the ONLY place
	that knows how an item definition (Modules/Items/Defs) maps onto the
	tooltip template, so adding a new item field means editing this file.

	  Items.fromTool(toolInfo)  -> config for TooltipModule.show()

	toolInfo is the table the server sends per inventory slot:
	  { name, displayName, count, rarity, description }

	Item definition fields understood (all optional):
	  description   string (rich text OK)
	  icon          "rbxassetid://..." item art for the icon box
	  typeTag       "Weapon" | "Armor" | "Resource" ...   -> TYPE badge
	  skillTag      "Combat" | "Farming" ...              -> SKILL badge (skill color)
	  showRarityTag false hides the rarity badge (shown when rarity > 0)
	  customTags    { { text|value|label, color }, ... }  -> extra badges
	  level         "LV. 5" or a number                   -> level bar
	  stats         { { icon, name, value, color }, ... } -> stat rows
	  showStatsSection false hides stats even if present
	  statsTitle    header text (default "STATS"); false = plain divider line
	  abilities     { { name, key, text, cooldown, color, align }, ... }
	  footer        small-caps note under the abilities
	  clickHint     string | { text, color, icon }  | array of those
	  slot          "Helmet" ... (adds a slot badge for armor / accessories)
--]]

local Style = require(script.Parent:WaitForChild("Style"))

local Items = {}

local function registry()
	local modules = script.Parent.Parent
	local reg = modules and modules:FindFirstChild("Items")
	if not reg then
		return nil
	end
	local ok, result = pcall(require, reg)
	return ok and result or nil
end

--- Icon box config: `color` tints the box strokes (rarity), `imageColor` tints the picture itself.
local function tooltipIcon(def: any, mainColor: string)
	local modules = script.Parent.Parent
	local iconsModule = modules and modules:FindFirstChild("ItemIcons")
	local ok, ItemIcons = pcall(function()
		return iconsModule and require(iconsModule)
	end)
	if not (ok and ItemIcons and def) then
		return { color = mainColor }
	end
	local spec = ItemIcons.resolve(def)
	return {
		image = spec.image,
		rectOffset = spec.rectOffset,
		rectSize = spec.rectSize,
		imageColor = spec.tint or Color3.new(1, 1, 1),
		color = mainColor,
	}
end

local function tagFrom(spec)
	return {
		text = spec.text or spec.value or spec.label or "?",
		color = spec.color or "#AAAAAA",
		dark = spec.strokeColor,
	}
end

function Items.fromTool(toolInfo: any)
	local reg = registry()
	local def = reg and reg.getByToolName(toolInfo.toolName or toolInfo.name) or nil

	local rarity = toolInfo.rarity or (def and def.rarity) or 0
	local rarityConf = reg and reg.getRarity(rarity) or nil
	local mainColor = (rarityConf and rarityConf.hexColor) or "#AAAAAA"

	local config: any = {
		title = toolInfo.displayName or toolInfo.name,
		titleColor = mainColor,
		stack = (toolInfo.count and toolInfo.count > 1) and toolInfo.count or nil,
		icon = tooltipIcon(def, mainColor),
		tags = {},
	}

	-- ── Tags ──
	if rarity > 0 and (not def or def.showRarityTag ~= false) then
		table.insert(config.tags, {
			text = rarityConf and rarityConf.name or "Rarity",
			color = mainColor,
		})
	end
	if def and def.typeTag then
		table.insert(config.tags, { text = def.typeTag, color = "#FFFFFF" })
	end
	if def and def.slot then
		local slotDef = reg and reg.Slots and reg.Slots.get(def.slot)
		table.insert(config.tags, { text = def.slot, color = slotDef and slotDef.color or "#FFFFFF" })
	end
	if def and def.skillTag then
		table.insert(config.tags, { text = def.skillTag, color = Style.SKILL_COLORS[def.skillTag] or "#FFFFFF" })
	end
	if def and def.customTags then
		for _, custom in ipairs(def.customTags) do
			table.insert(config.tags, tagFrom(custom))
		end
	end

	-- ── Description ──
	local description = (def and def.description) or toolInfo.description
	if description and description ~= "" then
		config.description = description
	end

	-- ── Level ──
	if def and def.level then
		config.level = type(def.level) == "number" and { text = "LV. " .. def.level } or { text = def.level }
	end

	-- ── Stats ──
	if def then
		local rows = reg and reg.Stats and reg.Stats.rows(def.stats) or {}
		for _, row in ipairs(def.displayStats or {}) do
			table.insert(rows, row)
		end
		if #rows > 0 then
			config.stats = rows
			config.statsTitle = def.statsTitle
		end
	end

	-- ── Abilities / footer ──
	if def and def.abilities and #def.abilities > 0 then
		config.blocks = def.abilities
	end
	if def and def.footer then
		config.footer = def.footer
	end

	-- ── Click hint ──
	if def and def.clickHint then
		config.click = def.clickHint
	else
		-- Right click equips / holds what can be worn or held; every item is moved by dragging (left click).
		config.click = {}
		if not def or def.equippable ~= false then
			table.insert(config.click, Style.CLICK_HINTS.equip)
		end
		table.insert(config.click, Style.CLICK_HINTS.drag)
	end

	return config
end

return Items
