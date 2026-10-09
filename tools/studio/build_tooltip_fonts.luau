-- build_tooltip_fonts.luau
-- Restyles the shared tooltip design StarterGui.TooltipMenu.Template (TooltipModule clones it at runtime, so EVERY tooltip in the game
-- follows): Silkscreen for titles, tags, stats, bars, the level bar, click pills and the footer; the description body stays Noto Sans but
-- bold and bigger; wider layout. Sizes = ReplicatedStorage.Modules.TooltipModule.Style.SIZE (change there AND rerun with FORCE = true).
-- Run through the Studio MCP (execute_luau, Edit datamodel, Play stopped). Keeps every instance name. Idempotent: skips when the Template
-- already carries the attribute FontsApplied == VERSION unless FORCE = true.
local FORCE = false
local VERSION = 1

local RS = game:GetService("ReplicatedStorage")
local Style = require(RS.Modules.TooltipModule.Style:Clone())
local SIZE = Style.SIZE

local template = game:GetService("StarterGui"):WaitForChild("TooltipMenu"):WaitForChild("Template")
if template:GetAttribute("FontsApplied") == VERSION and not FORCE then
	return "tooltip fonts already applied (set FORCE = true to reapply)"
end

local PIXEL = Font.new(Style.FONT_PIXEL, Enum.FontWeight.Regular, Enum.FontStyle.Normal)
local PIXEL_BOLD = Font.new(Style.FONT_PIXEL, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local BODY = Font.new(Style.FONT_BODY, Style.FONT_BODY_WEIGHT, Enum.FontStyle.Normal)
local changed = 0

local function label(inst, font, size)
	if inst and inst:IsA("TextLabel") then
		inst.FontFace = font
		inst.TextSize = size
		changed += 1
	end
end

-- title area
label(template.TitleFrame.TitleLabel, PIXEL, SIZE.title)
label(template.TitleFrame:FindFirstChild("StackLabel"), PIXEL, 20)
for _, tag in ipairs(template.TitleFrame.ItemTags:GetChildren()) do
	label(tag:FindFirstChild("TagLabel"), PIXEL, SIZE.tag)
end

-- description (the body font, bolder and bigger)
label(template.DescriptionLabel, BODY, SIZE.description)

-- bars
label(template.LevelBar:FindFirstChild("LevelLabel", true), PIXEL, SIZE.level)
label(template.ProgressBar:FindFirstChild("ProgressLabel", true), PIXEL, SIZE.progress)

-- stats rows (the prototype the module clones): ONLY the font weight changes (Silkscreen Bold, size = SIZE.stat = the original 20);
-- the row height, icon size and spacing stay exactly as designed in the Template (the dotted separator lives there)
for _, row in ipairs(template.Stats:GetChildren()) do
	if row:IsA("Frame") then
		label(row:FindFirstChild("NameLabel", true), PIXEL_BOLD, SIZE.stat)
		label(row:FindFirstChild("ValueLabel", true), PIXEL_BOLD, SIZE.stat)
	end
end

-- blocks / footer (prototypes inside Rewards): body text in the body font, titles + footer in the pixel font
for _, d in ipairs(template.Rewards:GetDescendants()) do
	if d:IsA("TextLabel") then
		if d.FontFace.Family == Style.FONT_BODY then
			label(d, BODY, SIZE.description)
		elseif d.Parent.Name == "Title" then
			label(d, PIXEL, SIZE.description)
		elseif d.Parent == template.Rewards then
			label(d, PIXEL, SIZE.footer) -- the footer prototype
		else
			label(d, PIXEL, SIZE.progress) -- cooldown / dynamic text
		end
	end
end

-- click pills + dividers
for _, pill in ipairs(template.ClickFrame:GetChildren()) do
	if pill:IsA("Frame") then
		label(pill:FindFirstChildWhichIsA("TextLabel"), PIXEL, SIZE.click)
	end
end
for _, name in ipairs({ "Divider1", "Divider2", "Divider3", "Divider4" }) do
	local divider = template:FindFirstChild(name)
	if divider then
		for _, d in ipairs(divider:GetDescendants()) do
			if d:IsA("TextLabel") and d.Text ~= "" then
				label(d, PIXEL, SIZE.progress)
			end
		end
	end
end

-- every other Noto Sans label of the Template (dividers, prototypes ...) is bold too: Noto Sans is never used in Regular weight
for _, d in ipairs(template:GetDescendants()) do
	if d:IsA("TextLabel") and d.FontFace.Family == Style.FONT_BODY and d.FontFace.Weight ~= Style.FONT_BODY_WEIGHT then
		d.FontFace = BODY
		changed += 1
	end
end

-- wider layout so the bigger text wraps later
local constraint = template:FindFirstChildOfClass("UISizeConstraint")
if constraint then
	constraint.MinSize = Vector2.new(340, 0)
	constraint.MaxSize = Vector2.new(520, math.huge)
end

template:SetAttribute("FontsApplied", VERSION)
return "tooltip template restyled: " .. changed .. " labels"
