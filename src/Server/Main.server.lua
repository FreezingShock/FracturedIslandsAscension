local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local SkillsDataManager = require(ServerScriptService:WaitForChild("SkillsDataManager")) :: any
-- ServerScriptService > StatisticsLoader (Script)
local StatisticsDataManager =
	require(game:GetService("ServerScriptService"):WaitForChild("StatisticsDataManager")) :: any
-- StatManager removed — not needed
