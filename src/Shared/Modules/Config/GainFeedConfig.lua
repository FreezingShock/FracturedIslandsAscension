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
	fold = { time = 0.3, style = "Quint", direction = "Out" },
	sounds = { open = "rbxassetid://105736529842995", close = "rbxassetid://119958057244626", volume = 0.5 },
	fallbackColor = "#FFFFFF",
}

return GainFeedConfig
