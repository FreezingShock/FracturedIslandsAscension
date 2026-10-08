--[[
	DropTooltipConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	Everything DropTooltipController (client) does with the tags over dropped items. Every drop moves through three stages:
	  DOT       a rarity-coloured gem, far away          (stages.dot:    show / hide in studs, max count)
	  FOLDED    a small tag: gem + name + count          (stages.folded: show / hide, max count)
	  UNFOLDED  the full card, ONE at a time, only for the drop you aim at (stages.unfold)
	Distances are studs from the player's root part. Each stage hides a few studs after it shows (hysteresis), so
	nothing flickers on the edge. Pickup stays server-side (ItemDrops.PICKUP_RADIUS, 8 studs); unfold.range is kept 40 above it.

	LAYERS, each overriding the one before:
	  1. defaults                       the same for every drop
	  2. rarity[<0-6>]                  per rarity (0 Common ... 5 Mythic)
	  3. items[<itemId>]                per item id (an Items id, or the stat id of a stat drop)
	DropTooltipConfig.resolve(rarity, itemId) returns the merged table (cached). Nested tables merge field by field, so
	items.coal = { stages = { dot = { show = 30 } } } changes one number. The CAPS (stages.dot.max, stages.folded.max,
	stages.unfold.maxUnfolded) and the aim rules are read from `defaults` only, because they are about the whole screen.

	AIM: the aim point is the mouse cursor when it is free (T, menus, free camera), otherwise the screen centre. A drop is
	aimed when its anchor point is within unfold.aimRadius (a fraction of the viewport height) of the aim point, or the aim
	point is inside its folded tag (padded by unfold.aimPad pixels). With hoverFirst, a drop you point AT (aim point inside
	its tag, or within hoverRadius of its anchor) wins over drops that are only inside aimRadius; among equals the CLOSEST
	to you unfolds. It stays unfolded for unfold.hold seconds after the aim leaves; switching to another drop waits
	unfold.switchDelay.

	RECIPES
	  Show tags sooner / later:     defaults.stages.folded.show (and hide a few studs higher)
	  Dots further / nearer:        defaults.stages.dot.show / hide
	  More tags at once:            defaults.stages.folded.max (the overflow stays dots)
	  Unfold the nearest on its own when nothing is aimed at:   defaults.stages.unfold.idleNearest = true
	  Quiet a cheap item:           items.coal = { stages = { dot = { show = 25, hide = 28 }, folded = { show = 12, hide = 14 } } }
	  Hide an item's tag entirely:  items.coal = { disabled = true }
	  Slower unfold:                defaults.motion.unfold.time
	  Louder Legendary:             rarity[4] = { flash = true, sounds = { unfold = "rbxassetid://123" } }
	  Add a sound:                  sounds.<slot> = "rbxassetid://..."   ("" = silent)
	  Restyle a tag:                edit ReplicatedStorage.GUI.DropTag in Studio (keep the instance names), or rebuild it
	                                with tools/studio/build_drop_tag.luau (FORCE = true)
	  Test aiming without a mouse:  in Studio, workspace:SetAttribute("DropAimOverride", Vector2.new(x, y)) (viewport pixels);
	                                set it to nil to go back to the real aim point
]]

local DropTooltipConfig = {}

DropTooltipConfig.defaults = {
	disabled = false,
	scanEvery = 0.1, -- seconds between stage decisions; the aim test and all motion run every frame

	stages = {
		dot = {
			show = 70,
			hide = 74,
			max = 24, -- dots on screen at once, nearest first
			alwaysOnTop = true, -- the far dot is drawn over walls and props (the folded tag and card keep their own rules)
			nearAt = 28, -- the gem is full size at this distance ...
			farAt = 60, -- ... and shrinks to the far size here
			size = { near = 14, far = 10 }, -- gem size in pixels (the template gem is 14)
			opacity = { near = 1, far = 0.6 },
			fadeBand = 4, -- studs over which a dot fades in at show / out at hide
			haloTransparency = 0.62, -- ImageTransparency of the soft halo (1 = no halo)
		},
		folded = {
			show = 46,
			hide = 50,
			max = 10, -- folded tags at once, nearest first; the overflow stays dots
		},
		unfold = {
			range = 48, -- a tag can only unfold inside this distance
			aimRadius = 0.14, -- fraction of the viewport height
			hoverFirst = true, -- a drop you point AT (its tag or gem under the aim point) beats a closer drop merely inside aimRadius
			hoverRadius = 0.04, -- fraction of the viewport height around the anchor that counts as pointing AT it
			aimPad = 12, -- pixels around the folded tag that count as hovering it
			stick = 1.35, -- the unfolded drop keeps the aim until the aim point is this many radii away
			hold = 0.25, -- seconds the card stays open after the aim leaves
			switchDelay = 0.12, -- seconds before the card moves to another aimed drop
			maxUnfolded = 1,
			idleNearest = false, -- true: with nothing aimed at, the nearest folded tag inside idleNearestRadius unfolds by itself
			idleNearestRadius = 20,
			idleNearestModes = { free = true }, -- camera modes (player attribute CameraMode: see CameraController PHASES) that turn idleNearest on by themselves
		},
	},

	layout = {
		anchorLift = 1.1, -- studs above the drop's resting position where the tag is anchored (steady, not the bobbing mesh)
		dotLift = -32, -- pixels the bottom edge of each layer sits ABOVE the anchor (negative = below it)
		foldedLift = 6,
		cardLift = 6, -- same as the folded tag, so the card grows out of it
		cardAlwaysOnTop = true, -- the open card draws over other tags and nameplates, but only with a clear line of sight (never through walls)
		maxTags = 3, -- tag pills on the card (rarity first)
		descriptionLines = 2, -- the description is cut after this many lines
	},

	-- all motion. time in seconds; style / direction are Enum.EasingStyle / EasingDirection names.
	motion = {
		dotIn = { time = 0.25, style = "Quint", direction = "Out", scale = 0.4 }, -- scale: where the dot grows from
		dotOut = { time = 0.18, style = "Quad", direction = "In", scale = 0.4 }, -- ... and shrinks to
		foldedIn = { time = 0.25, style = "Quint", direction = "Out", scale = 0.85, rise = 6 }, -- rise: pixels it climbs
		foldedOut = { time = 0.18, style = "Quad", direction = "In", scale = 0.9, drop = 3 },
		unfold = {
			time = 0.3,
			style = "Quint",
			direction = "Out",
			fromFootprint = true, -- the card grows from the folded tag's width (UIScale = tagWidth / cardWidth)
			minFrom = 0.55, -- but never smaller than this
			ringTime = 0.25, -- ring colours neutral -> rarity
			detailsDelay = 0.08, -- the divider + description reveal starts this much later ...
			detailsTime = 0.22, -- ... and takes this long (height reveal, no pop-in)
			foldedOut = 0.15, -- the folded tag fades out this fast underneath
		},
		fold = { time = 0.2, style = "Quint", direction = "In", foldedInDelay = 0.05, detailsTime = 0.12 },
		pop = { time = 0.12, scale = 1.08 }, -- when the drop is picked up / expires: quick pop and fade
		exit = { time = 0.2, style = "Quad", direction = "In", scale = 0.9, drop = 4 }, -- leaving range
		stagger = 0.04, -- seconds between tags that appear in the same scan (nearest first)
		sizeSmoothing = 0.25, -- seconds a dot takes to follow its distance-based size / opacity
	},

	transparency = { dot = 0, folded = 0.1, card = 0 }, -- GroupTransparency of each layer when fully shown

	-- ring colours of a folded tag and an unfolded card before it is aimed at; the card ends on the rarity pair (dark / colour)
	neutralOuter = "#4B4B4B",
	neutralInner = "#AAAAAA",
	flash = false, -- one bright pulse of the card's ring when it unfolds
	flashTime = 0.25,

	-- "" = silent. Leave them empty until you have ids. useUiClick plays workspace.UISounds.Click as a placeholder on unfold.
	sounds = {
		dotAppear = "",
		foldedAppear = "",
		unfold = "rbxassetid://105736529842995", -- toast in: plays for the local player only, not positional
		fold = "rbxassetid://119958057244626", -- toast out
		pickup = "", -- the item pop for pickups is in DropFXConfig.sounds
		useUiClick = false,
		volume = 0.35,
	},

	debug = { aimAttribute = "DropAimOverride" }, -- Studio only
}

DropTooltipConfig.rarity = {
	[4] = { flash = true },
	[5] = { flash = true },
}

DropTooltipConfig.items = {
	-- example: coal = { stages = { dot = { show = 25, hide = 28 } } },
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
