--[[
	UIPlaceholderCleanup (LocalScript)
	Place inside: StarterPlayerScripts

	Studio-only layout panels that are left visible in StarterGui would show
	up on screen in a live game. They stay visible in the Studio editor (so UI
	editing is unchanged) and are hidden only at runtime here.

	  - ButtonHover.MainFrame  (prototype "Button #1" hover card)

	StarterGui.TooltipMenu.Template is NOT handled here: TooltipModule clones it
	into its own ScreenGui and disables the original itself.
--]]

local Players = game:GetService("Players")
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

task.spawn(function()
	local buttonHover = playerGui:WaitForChild("ButtonHover", 15)
	local mainFrame = buttonHover and buttonHover:FindFirstChild("MainFrame")
	if mainFrame and mainFrame:IsA("GuiObject") then
		mainFrame.Visible = false
	end
end)

print("UIPlaceholderCleanup: Ready ✓")
