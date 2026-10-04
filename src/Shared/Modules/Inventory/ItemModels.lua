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

ItemModels.MODELS = {
	sword_basic = { template = "BasicSword", scale = 0.55 },
}

--- Grip applied to sprite Handles (unless the def's entry sets its own).
ItemModels.SPRITE_GRIP = { pos = Vector3.new(0, 0, 0) }

function ItemModels.get(def: any): any?
	if not def then
		return nil
	end
	local key = type(def.model) == "string" and def.model or def.id
	return ItemModels.MODELS[key]
end

return ItemModels
