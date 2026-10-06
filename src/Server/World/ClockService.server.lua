--[[
	ClockService (Script, ServerScriptService)
	The in-game calendar: writes workspace attributes Day (1-8), Month ("Early"|"Mid"|"Late"), Season ("Spring"...), Year, and (when
	ClockConfig.driveLighting) Lighting.ClockTime from the shared ClockConfig. The calendar is a pure function of the server clock,
	so nothing is saved and every server agrees. Clients read the attributes (and compute hh:mm themselves from ClockConfig.at).
--]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClockConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Config"):WaitForChild("ClockConfig")) :: any

local function tick()
	local now = ClockConfig.at(workspace:GetServerTimeNow())
	workspace:SetAttribute("Day", now.day)
	workspace:SetAttribute("Month", now.month)
	workspace:SetAttribute("Season", now.season)
	workspace:SetAttribute("Year", now.year)
	if ClockConfig.driveLighting then
		Lighting.ClockTime = now.hour
	end
end

while true do
	tick()
	task.wait(ClockConfig.lightingEvery)
end
