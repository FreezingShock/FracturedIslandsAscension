--[[
	ResourceConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	One entry per rechargeable resource (Health, Mana, Stamina). The server (ResourceService) and the client
	(ResourceBarsController) both read this table, so adding a resource is: add an entry here and a display for it in
	StarterGui.FIAHUD (tools/studio/build_fiahud.luau): `display = "panel"` is a pixel panel FIAHUD.Root.Stats.<row>
	(Bar.Fill, Value, ValueShadow); `display = "strip"` is the segmented Stamina strip FIAHUD.Root.Strip.

	Each resource is published as two Player attributes, so anything (UI, abilities, other scripts) can read them:
	    player:GetAttribute(key)          current value      e.g. "Mana"
	    player:GetAttribute("Max" .. key) maximum            e.g. "MaxMana"

	Fields
	  key        attribute name and id
	  label      text shown in the bar's Label ("Health: 87/100")
	  row        name of the panel under FIAHUD.Root.Stats (display = "panel")
	  display    "panel" | "strip" (see above)
	  color      accent colour of the resource (the pixel HUD takes its fill colours from HudTheme)
	  max        function(stat) -> maximum. `stat("Defense")` returns that stat's final value from the stat chain.
	  source     "humanoid": current value IS Humanoid.Health / MaxHealth. Omit for a plain server-side value.
	  regen      nil = no regeneration, else { stat = <stat key> OR amount = <fixed number>, unit = "percentPerSecond" |
	             "perSecond", delay = seconds without taking damage / spending before regeneration starts }
	  startFull  true = starts (and respawns) full

	Formulas (change the numbers here, nowhere else):
	  Health  = Health stat + Defense x HEALTH_PER_DEFENSE
	  Mana    = 100 + Intelligence x MANA_PER_INTELLIGENCE
	  Stamina = 100 flat; Vitality sets its regeneration (+1 stamina per second per point)
--]]

local ResourceConfig = {}

local HEALTH_PER_DEFENSE = 1
local MANA_PER_INTELLIGENCE = 2

-- The level shown in the HUD badge is this Player attribute. The server publishes it (placeholder: no progression yet).
ResourceConfig.nexusLevelAttribute = "NexusLevel"
ResourceConfig.nexusLevelStart = 0
ResourceConfig.nexusXpAttribute = "NexusXp" -- 0..1 progress inside the level (NexusService publishes it; the badge's XpClip follows it)
ResourceConfig.TICK = 0.25 -- seconds between regeneration ticks (server); amounts scale with it

ResourceConfig.resources = {
	{
		key = "Health",
		label = "Health",
		row = "Health",
		display = "panel",
		color = Color3.fromRGB(255, 85, 85),
		source = "humanoid",
		startFull = true,
		max = function(stat)
			return stat("Health") + stat("Defense") * HEALTH_PER_DEFENSE
		end,
		-- HealthRegen is a percentage of max health per second (0 = none until items / skills grant it)
		regen = { stat = "HealthRegen", unit = "percentPerSecond", delay = 3 },
	},
	{
		key = "Mana",
		label = "Mana",
		row = "Mana",
		display = "panel",
		color = Color3.fromRGB(85, 255, 255),
		startFull = true,
		max = function(stat)
			return 100 + stat("Intelligence") * MANA_PER_INTELLIGENCE
		end,
		-- a fixed 2% of max per second, starting 3s after the last spend (ability cast)
		regen = { amount = 2, unit = "percentPerSecond", delay = 3 },
	},
	{
		key = "Stamina",
		label = "Stamina",
		row = "Stamina",
		display = "strip",
		color = Color3.fromRGB(255, 255, 85),
		startFull = true,
		max = function()
			return 100
		end,
		-- Vitality = stamina per second; regeneration starts 1s after the last spend (sprinting keeps spending)
		regen = { stat = "Vitality", unit = "perSecond", delay = 1 },
	},
}

--- key -> entry
ResourceConfig.byKey = {}
for _, entry in ipairs(ResourceConfig.resources) do
	ResourceConfig.byKey[entry.key] = entry
end

return ResourceConfig
