--[[
	ItemRegistry (ModuleScript) — compatibility shim.

	The item system now lives in ReplicatedStorage.Modules.Items (see Items/init).
	This module just returns it so existing `require(Modules.ItemRegistry)`
	callers keep working. New code should require "Items".
--]]

return require(script.Parent:WaitForChild("Items"))
