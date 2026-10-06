-- ============================================================
--  MenuBridge (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Lightweight callback bridge between CentralizedMenuController
--  and InventoryController.  Both LocalScripts require this and
--  register/call functions through it.
-- ============================================================

local M = {}

-- ── Registered by CentralizedMenuController ──
M._openInventoryMode = nil -- function()  → open inventory-only
M._openFullMode = nil -- function()  → open grid + inventory
M._closeAll = nil -- function()  → close everything
M._isOpen = nil -- function() → bool
M._getMode = nil -- function() → nil | "inventory" | "full"

-- ── Registered by InventoryController ──
M._onStateChanged = nil -- function(mode)  → called when menu state changes
M._refreshInventory = nil -- function()      → force inventory slot refresh

-- ── Public API (called by InventoryController) ──
function M.openInventory()
	if M._openInventoryMode then
		M._openInventoryMode()
	end
end

function M.openFullMenu()
	if M._openFullMode then
		M._openFullMode()
	end
end

function M.closeAll()
	if M._closeAll then
		M._closeAll()
	end
end

function M.isOpen()
	if M._isOpen then
		return M._isOpen()
	end
	return false
end

function M.getMode()
	if M._getMode then
		return M._getMode()
	end
	return nil
end

-- ── Called by CentralizedMenuController when state changes ──
function M.notifyStateChanged(mode)
	if M._onStateChanged then
		M._onStateChanged(mode)
	end
	for _, listener in ipairs(M._stateListeners) do
		local ok, err = pcall(listener, mode)
		if not ok then
			warn("[MenuBridge] state listener error: " .. tostring(err))
		end
	end
end

-- Extra subscribers (ArmorAccessoriesController etc.). Use this instead of
-- overwriting notifyStateChanged / _onStateChanged, which have ONE owner each.
M._stateListeners = {}
function M.onStateChanged(listener)
	table.insert(M._stateListeners, listener)
end

-- ── Equipment drag support ──
-- Registered by ArmorAccessoriesController. While an inventory item is being
-- dragged, InventoryController calls this each move (and with nil to finish).
--   M.updateEquipDrag(screenPos | nil, itemSlotId | nil) -> slotId under the cursor | nil
M._updateEquipDrag = nil
function M.updateEquipDrag(screenPos, itemSlotId)
	if M._updateEquipDrag then
		return M._updateEquipDrag(screenPos, itemSlotId)
	end
	return nil
end

-- ── Called by CentralizedMenuController to force refresh ──
function M.requestInventoryRefresh()
	if M._refreshInventory then
		M._refreshInventory()
	end
end

return M
