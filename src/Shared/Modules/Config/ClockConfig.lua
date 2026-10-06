--[[
	ClockConfig (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules > Config

	The in-game calendar and clock, a pure function of the SERVER clock (workspace:GetServerTimeNow()), so every server and every
	client agrees with no saving and no replication traffic:
	  1 in-game day  = dayRealSeconds real seconds (default 20 minutes)
	  1 month        = daysPerMonth days (8), 1 season = monthsPerSeason months (3: Early / Mid / Late), 4 seasons per year
	ClockService (server) writes workspace attributes Day (1-8), Month ("Early"|"Mid"|"Late"), Season ("Spring"..."Winter"), Year
	and, when driveLighting is true, Lighting.ClockTime. The scoreboard reads the attributes for the date and ClockConfig.at() for
	the smooth hh:mm.

	RECIPES
	  Longer days:           dayRealSeconds = 1800
	  Keep my own lighting:  driveLighting = false
	  Start the world in autumn: epochOffsetDays = 48   (days to skip from the epoch)
]]

local ClockConfig = {
	dayRealSeconds = 1200,
	daysPerMonth = 8,
	monthsPerSeason = 3,
	months = { "Early", "Mid", "Late" }, -- one name per month of a season
	seasons = { "Spring", "Summer", "Autumn", "Winter" },
	epochOffsetDays = 72, -- the world starts in Early Winter
	startHour = 6, -- the in-game hour at server time 0 (the cycle length is dayRealSeconds)
	driveLighting = true,
	lightingEvery = 1, -- seconds between Lighting.ClockTime writes
}

--- The calendar at a server time: { day, month, monthIndex, season, seasonIndex, year, hour (0-24 float), minute, hour12, ampm }.
function ClockConfig.at(serverTime: number)
	local totalHours = serverTime / ClockConfig.dayRealSeconds * 24 + ClockConfig.startHour + ClockConfig.epochOffsetDays * 24
	local dayIndex = math.floor(totalHours / 24)
	local hour = totalHours % 24
	local perMonth, perSeason = ClockConfig.daysPerMonth, ClockConfig.daysPerMonth * ClockConfig.monthsPerSeason
	local perYear = perSeason * #ClockConfig.seasons
	local inYear = dayIndex % perYear
	local seasonIndex = math.floor(inYear / perSeason) + 1
	local monthIndex = math.floor((inYear % perSeason) / perMonth) + 1
	local minute = math.floor((hour % 1) * 60)
	local h24 = math.floor(hour)
	local h12 = h24 % 12
	if h12 == 0 then
		h12 = 12
	end
	return {
		day = inYear % perMonth + 1,
		month = ClockConfig.months[monthIndex],
		monthIndex = monthIndex,
		season = ClockConfig.seasons[seasonIndex],
		seasonIndex = seasonIndex,
		year = math.floor(dayIndex / perYear) + 1,
		hour = hour,
		minute = minute,
		hour12 = h12,
		ampm = h24 < 12 and "am" or "pm",
		isNight = h24 >= 19 or h24 < 5,
	}
end

--- 1 -> "1st", 2 -> "2nd", 3 -> "3rd", 4 -> "4th", 11 -> "11th"
function ClockConfig.ordinal(n: number): string
	local last, teen = n % 10, n % 100
	local suffix = "th"
	if teen < 11 or teen > 13 then
		suffix = (last == 1 and "st") or (last == 2 and "nd") or (last == 3 and "rd") or "th"
	end
	return n .. suffix
end

return ClockConfig
