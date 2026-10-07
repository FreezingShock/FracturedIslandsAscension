--[[
	ItemModels (ModuleScript) — how an item looks as a held Tool / dropped item.

	Every item gets a Handle. Items listed in MODELS use a real model from
	ServerStorage.ItemModels (Studio-only, not in Rojo); everything else gets a flat
	sprite Handle (the ItemIcons image on both faces, SPRITE_PIXELS pixels thick).

	  MODELS[itemId] = {
	      template = "BasicSword",   -- ServerStorage.ItemModels.<template> (Model with a part named Handle)
	      scale    = 0.55,           -- optional Model:ScaleTo
	      grip     = { pos, forward, up, right },  -- optional Tool grip overrides (Vector3s)
	  }
	A def can also say `model = "OtherId"` to reuse another entry.
--]]

local ItemModels = {}

ItemModels.SPRITE_SIZE = 2 -- studs (width and height of a sprite item)
ItemModels.SPRITE_PIXELS = 16 -- sprite thickness = SPRITE_SIZE / SPRITE_PIXELS

-- The pixel swords (Blender, assets/blender/swords): the mesh origin is the grip, which sits 1.17 studs below the
-- Handle's centre (Roblox centres a mesh on its bounding box), so the grip offset moves the hand to the handle.
-- Templates live in ServerStorage.ItemModels (SwordWood / Stone / Iron / Gold / Diamond; Wood and Stone are ready
-- for items that do not exist yet).
-- The grip is also rolled 90 degrees about the blade, so the FLAT side of the blade faces left/right like a
-- Minecraft sword (seen from behind you see the thin edge).
local PIXEL_SWORD_GRIP = {
	pos = Vector3.new(0, -1.17, 0),
	forward = Vector3.new(-1, 0, 0),
	up = Vector3.new(0, 1, 0),
	right = Vector3.new(0, 0, -1),
}

ItemModels.MODELS = {
	sword_basic = { template = "SwordIron", grip = PIXEL_SWORD_GRIP }, -- Iron Sword (iron_sword icon)
	solar_blade = { template = "SwordGold", grip = PIXEL_SWORD_GRIP }, -- Solar Blade (golden_sword icon)
	sword_legendary = { template = "SwordDiamond", grip = PIXEL_SWORD_GRIP }, -- Excalibur (diamond_sword icon)
	blink_blade = { template = "SwordGold", grip = PIXEL_SWORD_GRIP }, -- golden_sword icon
	stormcaller = { template = "SwordDiamond", grip = PIXEL_SWORD_GRIP }, -- diamond_sword icon
	frostbrand = { template = "SwordIron", grip = PIXEL_SWORD_GRIP }, -- iron_sword icon
}

-- Any sword (item.weapon.weaponType == "sword") without its own MODELS entry still gets a 3D model, picked by rarity,
-- so a new sword is never a flat sprite. Add a MODELS entry to choose a specific template.
ItemModels.SWORD_BY_RARITY = { [0] = "SwordWood", "SwordStone", "SwordIron", "SwordGold", "SwordDiamond", "SwordDiamond" }

--- Grip applied to sprite Handles (unless the def's entry sets its own).
ItemModels.SPRITE_GRIP = { pos = Vector3.new(0, 0, 0) }

function ItemModels.get(def: any): any?
	if not def then
		return nil
	end
	local key = type(def.model) == "string" and def.model or def.id
	local entry = ItemModels.MODELS[key]
	if not entry and def.weapon and def.weapon.weaponType == "sword" then
		local template = ItemModels.SWORD_BY_RARITY[def.rarity or 0] or "SwordIron"
		entry = { template = template, grip = PIXEL_SWORD_GRIP }
		ItemModels.MODELS[key] = entry
	end
	return entry
end

return ItemModels
