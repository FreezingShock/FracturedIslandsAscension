--[[
	DropTooltipConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	Everything DropTooltipController (client) does with the cards over dropped items. LAYERS, each overriding the one before:
	  1. defaults                       the same for every drop
	  2. rarity[<0-6>]                  per rarity (0 Common ... 5 Mythic), e.g. a longer-lived flash for Legendary
	  3. items[<itemId>]                per item id (Items id, or the stat id of a stat drop)
	DropTooltipConfig.resolve(rarity, itemId) returns the merged table.

	Drops are found by the CollectionService tag "DropTooltip" (set by LootService and ItemDrops with the attributes
	DropKind, ItemId, Count, Rarity, DropName, DropColor, DropSkill). The client only reads them; it sends nothing.

	RECIPES
	  Show cards sooner / later:   defaults.showRadius (pickup is 5 studs; hide stays a little larger so cards never flicker)
	  More / fewer full cards:     defaults.maxCards (the rest collapse to chips; chips beyond maxChips are hidden)
	  Quiet a cheap item:          items.coal = { maxCards = 0 }   (chip only) or { disabled = true }
	  Louder Legendary:            rarity[4] = { flash = true, sounds = { appear = "rbxassetid://123" } }
	  Add a sound:                 sounds.appear / sounds.pickup = "rbxassetid://..."  ("" = silent)
	  Restyle a card:              edit ReplicatedStorage.GUI.DropCard / DropChip in Studio (keep instance names), or rebuild
	                               with tools/studio/build_drop_card.luau (FORCE = true)
]]

local DropTooltipConfig = {}

DropTooltipConfig.defaults = {
	disabled = false,

	-- studs from the player's root part to the drop
	showRadius = 8, -- a card appears at or inside this distance (pickup radius is 5)
	hideRadius = 10, -- and stays until the drop is farther than this (hysteresis)
	scanEvery = 0.1, -- seconds between show / hide / focus decisions; tweens run on their own

	maxCards = 5, -- full cards at once (nearest first, the nearest is "focused")
	maxChips = 8, -- collapsed name chips beyond maxCards
	maxTags = 3, -- tag pills per card (rarity first)
	descriptionOnFocus = true, -- the divider + description line only on the focused card

	-- BillboardGui placement (the card sits above the drop, bottom centre)
	offset = Vector3.new(0, 1.9, 0),
	chipOffset = Vector3.new(0, 1.5, 0),
	maxDistance = 12, -- BillboardGui.MaxDistance (camera distance)

	-- motion (seconds). Group transparency is the CanvasGroup's, so 0 = fully visible
	enter = { time = 0.3, style = "Quint", direction = "Out", scale = 0.85, rise = 8, stagger = 0.04 },
	exit = { time = 0.2, style = "Quint", direction = "In", scale = 0.9, drop = 4 },
	pop = { time = 0.12, scale = 1.08 }, -- on pickup / despawn: quick pop then fade, removed immediately
	focus = { time = 0.18, style = "Quad", direction = "Out" },
	chipFade = 0.2,
	flash = false, -- one bright pulse of the ring on enter (Legendary and above by rarity layer)
	flashTime = 0.25,

	transparency = { focused = 0, unfocused = 0.3, chip = 0.15 },

	-- ring colours of an unfocused card; the focused card uses the rarity pair (outer = dark, inner = colour)
	neutralOuter = "#4B4B4B",
	neutralInner = "#AAAAAA",

	sounds = {
		appear = "", -- "" = silent. Leave empty until you have ids.
		pickup = "",
		useUiClick = true, -- placeholder: play workspace.UISounds.Click when the focused drop changes
		volume = 0.35,
	},
}

DropTooltipConfig.rarity = {
	[4] = { flash = true },
	[5] = { flash = true },
}

DropTooltipConfig.items = {
	-- example: coal = { maxCards = 0 },
}

local function merge(into: any, from: any)
	for key, value in pairs(from) do
		if type(value) == "table" and type(into[key]) == "table" and getmetatable(value) == nil and #value == 0 then
			merge(into[key], value)
		else
			into[key] = value
		end
	end
end

local function deepCopy(value: any)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = deepCopy(inner)
	end
	return copy
end

local cache: { [string]: any } = {}

function DropTooltipConfig.resolve(rarity: number?, itemId: string?)
	local cacheKey = tostring(rarity) .. "|" .. tostring(itemId)
	local hit = cache[cacheKey]
	if hit then
		return hit
	end
	local out = deepCopy(DropTooltipConfig.defaults)
	local byRarity = DropTooltipConfig.rarity[rarity or 0]
	if byRarity then
		merge(out, byRarity)
	end
	local byItem = itemId and DropTooltipConfig.items[itemId]
	if byItem then
		merge(out, byItem)
	end
	cache[cacheKey] = out
	return out
end

return DropTooltipConfig
