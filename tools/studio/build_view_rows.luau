-- build_view_rows.luau
-- Prepares StarterGui.ViewMenu for the info rows (ViewMenuController):
--   * ReplicatedStorage.GUI.ViewRow: a copy of the hand-made View.Cursor label (font, 22 px, rich text, right-anchored,
--     auto-size, UIStroke), emptied: the template the controller clones for a row that has no label yet
--   * StarterGui.ViewMenu.View.<RowId>: one placeholder label per row of ViewMenuConfig.order, copies of Cursor with the
--     row's coloured word and a sample value, stacked upward above Cursor (24 px pitch) so the layout is visible in
--     Studio; View grows to hold them and Cursor / POV are anchored to its bottom
--   * StarterGui.ViewMenu.View.Scale: a UIScale the controller sets from the viewport
-- Restyle the labels in Studio (or ViewRow) and the info rows follow. Run on the Edit datamodel with the Studio MCP.
-- Skips what exists unless FORCE = true (FORCE rebuilds the placeholder labels).
local FORCE = false

local RS = game.ReplicatedStorage
local C = require(RS.Modules.Config.ViewMenuConfig:Clone())
local view = game.StarterGui:FindFirstChild("ViewMenu") and game.StarterGui.ViewMenu:FindFirstChild("View")
assert(view, "StarterGui.ViewMenu.View is missing")
local cursor = view:FindFirstChild("Cursor")
assert(cursor, "StarterGui.ViewMenu.View.Cursor is missing")
local folder = RS:FindFirstChild("GUI")
assert(folder, "ReplicatedStorage.GUI is missing")

local out = {}
local existing = folder:FindFirstChild("ViewRow")
if existing and not FORCE then
	table.insert(out, "ViewRow: already exists (FORCE to rebuild)")
else
	if existing then
		existing:Destroy()
	end
	local row = cursor:Clone()
	row.Name = "ViewRow"
	row.Text = ""
	row.TextTransparency = 0
	row.Position = UDim2.new(1, 0, 1, -46)
	local stroke = row:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	row.Parent = folder
	table.insert(out, "ViewRow: built from Cursor")
end

if view:FindFirstChildOfClass("UIScale") then
	table.insert(out, "View.Scale: already exists")
else
	local scale = Instance.new("UIScale")
	scale.Name = "Scale"
	scale.Parent = view
	table.insert(out, "View.Scale: added")
end
-- placeholder labels, stacked upward above Cursor
cursor.Position = UDim2.new(1, 0, 1, -C.baseHeight)
local pov = view:FindFirstChild("POV")
if pov then
	pov.Position = UDim2.new(1, 0, 1, -(C.baseHeight - C.rowHeight))
end
local made = 0
for index, id in ipairs(C.order) do
	local def = C.get(id)
	local label = view:FindFirstChild(id)
	if not label or FORCE then
		if label then
			label:Destroy()
		end
		label = (folder:FindFirstChild("ViewRow") or cursor):Clone()
		label.Name = id
		label.RichText = true
		label.TextTransparency = 0
		label.Text = string.format(
			'<font color="%s">%s</font> (<font color="%s">%s</font>)',
			def.wordColor,
			def.word,
			def.valueColor or "#FFFF55",
			def.sample or ""
		)
		label.Parent = view
		made += 1
	end
	label.Position = UDim2.new(1, 0, 1, -(C.baseHeight + index * C.rowHeight))
	label.LayoutOrder = index
end
view.Size = UDim2.fromOffset(C.minWidth, C.baseHeight + #C.order * C.rowHeight)
table.insert(out, string.format("placeholder labels: %d new of %d, View.Size=%s", made, #C.order, tostring(view.Size)))
return table.concat(out, "; ")
