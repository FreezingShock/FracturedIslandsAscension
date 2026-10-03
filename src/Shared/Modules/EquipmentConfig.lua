--[[
	EquipmentConfig (ModuleScript) — compatibility shim.

	Slot definitions moved to Modules.Items.Slots; stat bonuses now come from the
	equipped ITEM (Items/Defs), not from the slot. EQUIPMENT_BOOSTS is gone.
--]]

local Slots = require(script.Parent:WaitForChild("Items"):WaitForChild("Slots"))

local EquipmentConfig = {}

EquipmentConfig.EQUIPPED_SLOTS = Slots.Defs
EquipmentConfig.slotLookup = Slots.Defs
EquipmentConfig.slotsByType = Slots.ByType
EquipmentConfig.slotOrder = Slots.Order

return EquipmentConfig
