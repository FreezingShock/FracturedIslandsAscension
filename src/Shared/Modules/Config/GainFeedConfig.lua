--[[
	GainFeedConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The J "Recently gained" foldable under the scoreboard (GainFeedController). The server (GainFeedService) says what was gained;
	the client groups it per key, sums it and shows the last `window` seconds.

	  key           the key that toggles the foldable (J). Free in the codebase; change it here.
	  window        seconds a gain stays in the list
	  fadeLast      the row fades from full to `minOpacity` over its last `fadeLast` seconds
	  maxRows       rows shown at once (newest first); older ones wait their turn
	  holdOpen      true = the foldable starts unfolded and stays open (the key still folds it)
	  chip          the folded chip: shows "x{N}" for gains you have not seen yet (since it was last unfolded)
	  look          transparencies and text sizes of the chip / card / rows
	  fold          Quint Out tween of the open / close
	  sounds        local only (not positional). "" = silent
	  rows          the stat / skill / item colour is sent by the server; `fallbackColor` is used when a gain has none

	RECIPES
	  Longer memory:     window = 60
	  Always open:       holdOpen = true
	  Other key:         key = "K"   (an Enum.KeyCode name)
	  Quieter:           sounds.volume = 0.2
]]

local GainFeedConfig = {
	key = "J",
	window = 30,
	fadeLast = 12,
	minOpacity = 0.35,
	maxRows = 8,
	holdOpen = false,
	-- the look of the foldable (the chip and the open card): more opaque than the scoreboard so it reads on any background
	look = {
		bodyTransparency = 0.08, -- 0 = solid
		borderTransparency = 0.2,
		chipSize = 20, -- chip text
		headerSize = 22, -- "Recently gained"
		rowSize = 20, -- gain rows
		ageSize = 16, -- the age on the right and the "30s" in the header
		emptySize = 16,
		ageWidth = 52,
	},
	fold = { time = 0.3, style = "Quint", direction = "Out" },
	sounds = { open = "rbxassetid://105736529842995", close = "rbxassetid://119958057244626", volume = 0.5 },
	fallbackColor = "#FFFFFF",
}

return GainFeedConfig
