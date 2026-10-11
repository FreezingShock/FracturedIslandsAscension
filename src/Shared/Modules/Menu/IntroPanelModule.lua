-- ============================================================
--  IntroPanelModule (ModuleScript)
--  Place inside: ReplicatedStorage.Modules (Shared > Modules > Menu)
--
--  The page renderer for the intro loading screen. One module serves every LoadingConfig.menus entry: the
--  entry's rows are cloned from the screen's Templates (Heading, Row, Option), so a new menu is data, not code.
--
--  API (IntroController calls these):
--    init(sharedRefs, panelFrame)   once. sharedRefs.templates = the Templates folder,
--                                   sharedRefs.closeMenu() closes whatever menu is open,
--                                   sharedRefs.getSetting(key) / sharedRefs.cycleSetting(key) back the option rows
--    open(arg)                      arg = { title = string, rows = { {kind, ...} } }
--                                   kinds: "heading" {text}, "text" {text}, "toggle" {key, label}, "cycle" {key, label, suffix}
--    close()                        animated: slides out and fades, then hides
--    reset()                        instant hide
--    isOpen()                       true while the panel is showing
--   Template shape: Row / Heading / Option = Frame > Inner (Frame) > Text | Label + Value
-- ============================================================

local TweenService = game:GetService("TweenService")

local SLIDE = 36 -- pixels the panel travels in and out
local OPEN_TIME = 0.42
local CLOSE_TIME = 0.24
local ROW_STAGGER = 0.025

local shared = nil
local panel: CanvasGroup? = nil
local basePosition = UDim2.new()
local titleLabel: TextLabel? = nil
local content: ScrollingFrame? = nil
local openState = false
local activeTween: Tween? = nil

local function cancelTween()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

local function clearContent()
	if not content then
		return
	end
	for _, child in ipairs(content:GetChildren()) do
		if not child:IsA("UIBase") then
			child:Destroy()
		end
	end
end

local function fromTemplate(name: string): Instance?
	local templates = shared and shared.templates
	local template = templates and templates:FindFirstChild(name)
	if not template then
		return nil
	end
	local clone = template:Clone()
	clone.Visible = true
	return clone
end

local function setOptionText(optionFrame: Instance, key: string, suffix: string?)
	local valueButton = optionFrame:FindFirstChild("Value", true)
	if valueButton and valueButton:IsA("TextButton") then
		local value = shared.getSetting(key)
		-- Minecraft codes: ON &a green, OFF &c red, numbers &e yellow (bright on top, the shade below)
		local top, bottom
		if typeof(value) == "boolean" then
			valueButton.Text = value and "ON" or "OFF"
			top, bottom = if value then Color3.fromHex("#55FF55") else Color3.fromHex("#FF5555"), if value then Color3.fromHex("#00AA00") else Color3.fromHex("#AA0000")
		else
			valueButton.Text = tostring(value) .. (suffix or "")
			top, bottom = Color3.fromHex("#FFFF55"), Color3.fromHex("#AAAA00")
		end
		valueButton.BackgroundColor3 = top
		local gradient = valueButton:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = ColorSequence.new(top, bottom)
		end
	end
end

-- fills the page from the rows; every row starts a little to the right and slides into place, staggered
local function buildRows(rows: { any })
	clearContent()
	if not content then
		return
	end
	local order = 0
	for _, row in ipairs(rows) do
		local item: Instance? = nil
		if row.kind == "heading" then
			item = fromTemplate("Heading")
			if item then
				local label = item:FindFirstChild("Text", true)
				if label and label:IsA("TextLabel") then
					label.Text = row.text
				end
			end
		elseif row.kind == "text" then
			item = fromTemplate("Row")
			if item then
				local label = item:FindFirstChild("Text", true)
				if label and label:IsA("TextLabel") then
					label.Text = row.text
				end
			end
		elseif row.kind == "toggle" or row.kind == "cycle" then
			item = fromTemplate("Option")
			if item then
				local label = item:FindFirstChild("Label", true)
				if label and label:IsA("TextLabel") then
					label.Text = row.label
				end
				setOptionText(item, row.key, row.suffix)
				local valueButton = item:FindFirstChild("Value", true)
				if valueButton and valueButton:IsA("GuiButton") then
					valueButton.Activated:Connect(function()
						shared.cycleSetting(row.key)
						setOptionText(item :: Instance, row.key, row.suffix)
					end)
				end
			end
		end
		if item then
			order += 1
			item.LayoutOrder = order
			item.Name = `Row{order}`
			item.Parent = content
			-- the layout owns the row's Position, so the slide moves its Inner frame (every template has one)
			local inner = item:FindFirstChild("Inner")
			if inner and inner:IsA("GuiObject") then
				local target = inner.Position
				inner.Position = target + UDim2.fromOffset(18, 0)
				task.delay((order - 1) * ROW_STAGGER, function()
					if inner.Parent then
						TweenService:Create(inner, TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = target }):Play()
					end
				end)
			end
		end
	end
end

local function init(sharedRefs, panelFrame)
	shared = sharedRefs
	panel = panelFrame :: CanvasGroup
	basePosition = panel.Position
	titleLabel = panel:FindFirstChild("Title", true) :: TextLabel?
	content = panel:FindFirstChild("Content", true) :: ScrollingFrame?
	local closeButton = panel:FindFirstChild("CloseButton", true)
	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.Activated:Connect(function()
			if shared and shared.closeMenu then
				shared.closeMenu()
			end
		end)
	end
	panel.Visible = false
end

local function open(arg)
	if not panel then
		return
	end
	arg = arg or {}
	cancelTween()
	if titleLabel then
		titleLabel.Text = tostring(arg.title or "")
	end
	buildRows(arg.rows or {})
	openState = true
	panel.Visible = true
	panel.GroupTransparency = 1
	panel.Position = basePosition + UDim2.fromOffset(SLIDE, 0)
	activeTween = TweenService:Create(panel, TweenInfo.new(OPEN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = basePosition,
		GroupTransparency = 0,
	})
	activeTween:Play()
end

local function reset()
	cancelTween()
	openState = false
	if panel then
		panel.Visible = false
		panel.Position = basePosition
		panel.GroupTransparency = 0
	end
end

local function close()
	if not panel or not openState then
		return
	end
	openState = false
	cancelTween()
	local tween = TweenService:Create(panel, TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In), {
		Position = basePosition + UDim2.fromOffset(SLIDE, 0),
		GroupTransparency = 1,
	})
	activeTween = tween
	tween.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and not openState then
			panel.Visible = false
		end
	end)
	tween:Play()
end

local function isOpen(): boolean
	return openState
end

return {
	init = init,
	open = open,
	close = close,
	reset = reset,
	isOpen = isOpen,
}
