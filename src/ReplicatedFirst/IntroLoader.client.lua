--[[
	IntroLoader (LocalScript)
	Place inside: ReplicatedFirst

	Runs before the world loads. It hides Roblox's default loading screen, clones the IntroScreen template into
	PlayerGui at once, and marks the player IntroActive so the camera, cursor and input controllers stand down.
	Everything else (preload, cutscene, menus, Play) is IntroController in StarterPlayerScripts > Client > Intro.
	The template (ReplicatedFirst.IntroScreen) is built by tools/studio/build_intro_screen.luau; the names are in LoadingConfig.
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
player:SetAttribute("IntroActive", true)

local playerGui = player:WaitForChild("PlayerGui")
local template = ReplicatedFirst:WaitForChild("IntroScreen", 10)
if template and template:IsA("ScreenGui") then
	local screen = template:Clone()
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 1000
	screen.Parent = playerGui
else
	warn("[IntroLoader] ReplicatedFirst.IntroScreen not found: run tools/studio/build_intro_screen.luau")
	player:SetAttribute("IntroActive", false)
end
