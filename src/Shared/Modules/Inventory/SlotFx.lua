--[[
	SlotFx (ModuleScript)

	Shared hover / selected look for grid slots, so the Profile layers and the
	equipment slots feel the same. Works on any slot with BG.UIStroke (the
	standard StatSlot / equipment button shape).

	  SlotFx.bind(button) -> { Disconnect = fn }   hover grows the outline
	  SlotFx.setSelected(button, bool)             selected = permanently thicker outline
--]]

local TweenService = game:GetService("TweenService")

local SlotFx = {}

local HOVER_GROW = 1.5
local SELECT_GROW = 2
local INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function strokeOf(button: Instance): UIStroke?
	local bg = button:FindFirstChild("BG")
	return bg and bg:FindFirstChildOfClass("UIStroke") or nil
end

local function baseThickness(stroke: UIStroke): number
	local base = stroke:GetAttribute("BaseThickness")
	if not base then
		base = stroke.Thickness
		stroke:SetAttribute("BaseThickness", base)
	end
	return base
end

local function apply(button: Instance)
	local stroke = strokeOf(button)
	if not stroke then
		return
	end
	local grow = 0
	if button:GetAttribute("SlotFxSelected") then
		grow += SELECT_GROW
	end
	if button:GetAttribute("SlotFxHover") then
		grow += HOVER_GROW
	end
	TweenService:Create(stroke, INFO, { Thickness = baseThickness(stroke) + grow }):Play()
end

function SlotFx.setSelected(button: Instance, selected: boolean)
	button:SetAttribute("SlotFxSelected", selected or nil)
	apply(button)
end

function SlotFx.bind(button: GuiButton): { Disconnect: () -> () }
	local enter = button.MouseEnter:Connect(function()
		button:SetAttribute("SlotFxHover", true)
		apply(button)
	end)
	local leave = button.MouseLeave:Connect(function()
		button:SetAttribute("SlotFxHover", nil)
		apply(button)
	end)
	return {
		Disconnect = function()
			enter:Disconnect()
			leave:Disconnect()
		end,
	}
end

return SlotFx
