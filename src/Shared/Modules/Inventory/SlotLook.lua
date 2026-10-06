--[[
	SlotLook (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Paints the pixel item slot (ReplicatedStorage.SlotTemplate, built by tools/studio/build_fiahud.luau) so the inventory
	code never writes colours into the slot directly. A slot is a root Frame holding:
	  Outline / Face   two "bands" (child frames H and V) that make a rectangle with one-pixel notched corners
	  Highlight, Shade thin strips on the face
	  Rarity           Bar + CL + CR (bottom bar with two corner pixels), coloured by the item's rarity
	  ItemImage, StackNum, SlotNum, ToolName, Select, Swap (unchanged names)

	  SlotLook.paint(slot, rarityConf?, { hovered, selected, blank })   face colour + rarity bar
	  SlotLook.setOutline(slot, color) / SlotLook.getOutline(slot)       drag highlight
	  SlotLook.dim(slot, transparency)                                    dims the face while the slot is dragged
--]]

local Modules = script.Parent -- flat in Studio: ReplicatedStorage.Modules
local HudTheme = require(Modules:WaitForChild("Config"):WaitForChild("HudTheme")) :: any

local C = HudTheme.colors
local WHITE = Color3.new(1, 1, 1)

local SlotLook = {}

local function bands(holder: any, color: Color3)
	holder.H.BackgroundColor3 = color
	holder.V.BackgroundColor3 = color
end

function SlotLook.paint(slot: any, rarityConf: any?, opts: any?)
	opts = opts or {}
	local fill = opts.selected and C.slotSelectedFill or C.slotFill
	if opts.hovered and not opts.blank then
		fill = fill:Lerp(WHITE, HudTheme.slot.hoverLighten)
	end
	bands(slot.Face, fill)

	local rarity = slot.Rarity
	local show = rarityConf ~= nil and not opts.blank
	rarity.Visible = show
	if show then
		rarity.Bar.BackgroundColor3 = rarityConf.color
		rarity.CL.BackgroundColor3 = rarityConf.color
		rarity.CR.BackgroundColor3 = rarityConf.color
	end
end

function SlotLook.setOutline(slot: any, color: Color3)
	bands(slot.Outline, color)
end

function SlotLook.getOutline(slot: any): Color3
	return slot.Outline.H.BackgroundColor3
end

--- Transparency of the face only (the dragged source slot dims, its icon and text stay).
function SlotLook.dim(slot: any, transparency: number)
	slot.Face.H.BackgroundTransparency = transparency
	slot.Face.V.BackgroundTransparency = transparency
end

--- The outline colour a slot starts with.
function SlotLook.defaultOutline(): Color3
	return C.slotBorder
end

return SlotLook
