--[[
	DamageNumberController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Shows what a hit looks like, for every player's hits (the server broadcasts each one on the WeaponHit remote):
	  * a white flash (Highlight) on the target
	  * the weapon's `impact` slot sound at the hit point (CombatConfig; silent until an id is set)
	  * a floating damage number cloned from the hand-made template ReplicatedStorage.GUI.DamageNumber
	    (BillboardGui > Label + UIStroke; restyle it in Studio). Crits use CombatConfig.hit.crit colours and size.
	No UI is built here: the script only clones the template and sets its text, colours and motion.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local CombatFX = require(Modules:WaitForChild("CombatFX")) :: any

local WeaponHit = ReplicatedStorage:WaitForChild("WeaponHit")
local template = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("DamageNumber") :: BillboardGui

local HIT = CombatConfig.hit

local function withCommas(n: number): string
	local text = tostring(math.floor(n + 0.5))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

local function flash(model: Model)
	local highlight = model:FindFirstChild("HitFlash") :: Highlight?
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "HitFlash"
		highlight.OutlineTransparency = 1
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Adornee = model
		highlight.Parent = model
	end
	local flashHighlight = highlight :: Highlight
	flashHighlight.FillColor = HIT.flashColor
	flashHighlight.FillTransparency = 0.3
	local token = (flashHighlight:GetAttribute("Token") or 0) + 1
	flashHighlight:SetAttribute("Token", token)
	local tween = TweenService:Create(flashHighlight, TweenInfo.new(HIT.flashTime, Enum.EasingStyle.Quad), { FillTransparency = 1 })
	tween:Play()
	tween.Completed:Once(function()
		if flashHighlight.Parent and flashHighlight:GetAttribute("Token") == token then
			flashHighlight:Destroy()
		end
	end)
end

local function spawnNumber(position: Vector3, amount: number, isCrit: boolean)
	local style = isCrit and HIT.crit or HIT.normal
	local spread = HIT.numberSpread
	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumberAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position + Vector3.new((math.random() - 0.5) * 2 * spread, 0, (math.random() - 0.5) * 2 * spread)
	anchor.Parent = workspace.CurrentCamera

	local gui = template:Clone()
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(template.Size.X.Offset * style.scale, template.Size.Y.Offset * style.scale)
	local label = gui:FindFirstChild("Label") :: TextLabel
	local stroke = label and label:FindFirstChildOfClass("UIStroke")
	if label then
		label.Text = (style.prefix and (style.prefix .. " ") or "") .. withCommas(amount)
		label.TextColor3 = Color3.fromHex(style.color)
		label.TextSize = math.round(label.TextSize * style.scale)
		if stroke then
			stroke.Color = Color3.fromHex(style.stroke)
		end
	end
	-- crits show the hand-made CritBadge (template child) behind the number; normal hits hide it
	local badge = gui:FindFirstChild("CritBadge") :: ImageLabel?
	if badge then
		badge.Visible = style.badge ~= nil
		if style.badge then
			badge.ImageColor3 = Color3.fromHex(style.badge.color)
			badge.ImageTransparency = style.badge.transparency
			badge.Size = UDim2.fromOffset(badge.Size.X.Offset * style.scale, badge.Size.Y.Offset * style.scale)
		end
	end
	gui.Parent = anchor

	local life = HIT.numberTime
	TweenService:Create(anchor, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = anchor.Position + Vector3.new(0, HIT.numberRise, 0),
	}):Play()
	if label then
		local fade = TweenInfo.new(life * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.6)
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		end
		if badge and style.badge then
			TweenService:Create(badge, fade, { ImageTransparency = 1 }):Play()
		end
	end
	Debris:AddItem(anchor, life + 0.2)
end

WeaponHit.OnClientEvent:Connect(function(data)
	if type(data) ~= "table" or typeof(data.position) ~= "Vector3" or type(data.damage) ~= "number" then
		return
	end
	spawnNumber(data.position, data.damage, data.isCrit == true)
	if typeof(data.target) == "Instance" and data.target:IsA("Model") then
		flash(data.target)
	end
	CombatFX.impact(data.position, data.weaponType, data.weaponId)
end)
