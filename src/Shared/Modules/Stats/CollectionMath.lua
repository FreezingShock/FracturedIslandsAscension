--[[
	CollectionMath (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	The tier arithmetic of Collections, shared by the server (CollectionService decides what is granted) and the
	client (CollectionsPageModule shows it), so both always agree.

	  highestTier(lifetime)        0..TIER_COUNT, the highest tier whose threshold the lifetime reached
	  nextTier(lifetime)           the next { level, threshold }, or nil when all tiers are done
	  status(tier, highest)        "completed" | "inProgress" | "locked"
	  progress(lifetime)           0..1 toward the next tier (from the previous threshold)
	  rewardColumns(count)         the grid columns (0-based) for `count` rewards on the reward row
--]]

local Config = require(script.Parent:WaitForChild("CollectionsConfig")) :: any

local CollectionMath = {}

local TIER_COUNT = Config.TIER_COUNT

function CollectionMath.highestTier(lifetime: any): number
	if type(lifetime) ~= "number" or lifetime ~= lifetime or lifetime < Config.threshold(1) then
		return 0
	end
	-- log10 can land a hair under an exact power of ten, so start from the estimate and correct it
	local tier = math.clamp(math.floor(math.log10(lifetime)) - 1, 0, TIER_COUNT)
	while tier < TIER_COUNT and lifetime >= Config.threshold(tier + 1) do
		tier += 1
	end
	while tier > 0 and lifetime < Config.threshold(tier) do
		tier -= 1
	end
	return tier
end

function CollectionMath.nextTier(lifetime: any)
	local highest = CollectionMath.highestTier(lifetime)
	return Config.COLLECTION_TIERS[highest + 1]
end

function CollectionMath.status(tier: number, highest: number): string
	if tier <= highest then
		return "completed"
	elseif tier == highest + 1 then
		return "inProgress"
	end
	return "locked"
end

function CollectionMath.progress(lifetime: any): number
	local highest = CollectionMath.highestTier(lifetime)
	local nextTier = Config.COLLECTION_TIERS[highest + 1]
	if not nextTier then
		return 1
	end
	local previous = highest > 0 and Config.threshold(highest) or 0
	return math.clamp((lifetime - previous) / (nextTier.threshold - previous), 0, 1)
end

--- Where `count` rewards sit on the 9-cell reward row (0-based columns), centred and evenly spaced:
--- 1-4 rewards every second cell (4 / 3,5 / 2,4,6 / 1,3,5,7), 5 and 7 side by side, 6 with the middle cell skipped.
function CollectionMath.rewardColumns(count: number): { number }
	local columns = Config.LAYOUT.columns
	local middle = math.floor(columns / 2)
	count = math.clamp(count, 0, Config.LAYOUT.maxRewards)
	local out = {}
	if count <= 4 then
		for i = 0, count - 1 do
			out[#out + 1] = middle - (count - 1) + i * 2
		end
	elseif count % 2 == 1 then
		for i = 0, count - 1 do
			out[#out + 1] = middle - (count - 1) // 2 + i
		end
	else
		local half = count // 2
		for i = 1, half do
			out[#out + 1] = middle - i
			out[#out + 1] = middle + i
		end
		table.sort(out)
	end
	return out
end

return CollectionMath
