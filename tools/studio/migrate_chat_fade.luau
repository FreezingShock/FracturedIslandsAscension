-- migrate_chat_fade.luau
-- Brings an existing ReplicatedStorage.GUI.FIAChatGui up to the taller, fading chat WITHOUT rebuilding it (a rebuild would
-- throw away any restyling made in Studio). The same structure is built fresh by build_chat_gui.luau; this file only adds what is missing:
--   * Panel is 480 x 450 (was 300 high)
--   * Body > FadeGroup (CanvasGroup, UIGradient "FadeGradient": 1 at the top -> 0 by 30%) wraps LogFrame
--   * LogFrame scrollbar: 6px and fully visible
--   * Templates > Row (horizontal UIListLayout) for player lines, and a UIFlexItem "Flex" on Line so the name fills the row
-- Idempotent: every step checks first, so running it again changes nothing. Run on the Edit datamodel (stop Play first).
local FADE_TOP = 0.3 -- = ChatConfig.Visual.FadeTopFraction

local GUI = game:GetService("ReplicatedStorage"):FindFirstChild("GUI")
assert(GUI, "ReplicatedStorage.GUI is missing")
local gui = GUI:FindFirstChild("FIAChatGui")
assert(gui, "FIAChatGui is missing: run build_chat_gui.luau first")

local function new(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do
		i[k] = v
	end
	i.Parent = parent
	return i
end

local done = {}
local panel = gui:FindFirstChild("Panel") :: Frame
local body = panel:FindFirstChild("Body") :: Frame
local log = body:FindFirstChild("LogFrame", true) :: ScrollingFrame
local templates = gui:FindFirstChild("Templates") :: Folder

if panel.Size.Y.Offset ~= 450 then
	panel.Size = UDim2.fromOffset(480, 450)
	table.insert(done, "panel 450")
end

if not body:FindFirstChild("FadeGroup") then
	local fade = new("CanvasGroup", {
		Name = "FadeGroup",
		Size = log.Size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		GroupTransparency = 0,
	}, body)
	log.Parent = fade
	log.Size = UDim2.fromScale(1, 1)
	new("UIGradient", {
		Name = "FadeGradient",
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(FADE_TOP, 0),
			NumberSequenceKeypoint.new(1, 0),
		}),
	}, fade)
	table.insert(done, "FadeGroup")
end
if log.ScrollBarThickness ~= 6 or log.ScrollBarImageTransparency ~= 0 then
	log.ScrollBarThickness = 6
	log.ScrollBarImageTransparency = 0
	table.insert(done, "scrollbar")
end

if not templates:FindFirstChild("Row") then
	local row = new("Frame", { Name = "Row", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0 }, templates)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Top, Padding = UDim.new(0, 6) }, row)
	table.insert(done, "Row")
end
local line = templates:FindFirstChild("Line") :: TextLabel
if line and not line:FindFirstChild("Flex") then
	new("UIFlexItem", { Name = "Flex", FlexMode = Enum.UIFlexMode.Fill }, line)
	table.insert(done, "Line Flex")
end

return #done == 0 and "FIAChatGui already migrated (nothing changed)" or ("migrated FIAChatGui: " .. table.concat(done, ", "))
