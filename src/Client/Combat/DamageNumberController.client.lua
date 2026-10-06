--[[
	DamageNumberController (LocalScript, Client)
	Place inside: StarterPlayer > StarterPlayerScripts

	Shows what a hit looks like, for every player's hits (the server broadcasts each one on the WeaponHit remote):
	  * a white flash (Highlight) on the target
	  * the weapon's `impact` slot sound at the hit point (CombatConfig; silent until an id is set)
	  * the enemy's hit / crit / death effects and sounds at the contact point (EnemyFX, styled by EnemyConfig)
	  * a floating damage number cloned from the hand-made template ReplicatedStorage.GUI.DamageNumber
	    (BillboardGui > Label + UIStroke; restyle it in Studio). Styles (normal / crit / crash / full / taken), sizes, pop-in and stacking are CombatConfig.hit.
	No UI is built here: the script only clones the template and sets its text, colours and motion.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CombatConfig = require(Modules:WaitForChild("CombatConfig")) :: any
local CombatFX = require(Modules:WaitForChild("CombatFX")) :: any
local EnemyFX = require(Modules:WaitForChild("EnemyFX")) :: any

local WeaponHit = ReplicatedStorage:WaitForChild("WeaponHit")
local template = ReplicatedStorage:WaitForChild("GUI"):WaitForChild("DamageNumber") :: BillboardGui

local HIT = CombatConfig.hit

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }

--- 1,234 stays whole below 10,000 (with commas); from there 12.3K, 1.2M ... so a big number never overflows its box.
local function formatAmount(n: number): string
	n = math.floor(n + 0.5)
	if n < 10000 then
		local formatted = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (formatted:gsub("^,", ""))
	end
	local index = math.min(math.floor(math.log(n, 1000)), #SUFFIXES)
	local scaled = n / 1000 ^ index
	local text = scaled < 100 and ("%.1f"):format(scaled) or ("%d"):format(scaled)
	return (text:gsub("%.0$", "")) .. SUFFIXES[index]
end

-- [target Instance] = { at = os.clock() of the last number, n = how many in the current burst }: numbers made on the same
-- target within HIT.stackWindow rise one HIT.stackOffset higher each, so they never sit on top of each other
local stacks: { [Instance]: { at: number, n: number } } = setmetatable({}, { __mode = "k" })

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

--- kind: "normal" | "crit" | "crash" | "full" | "taken"; flags: { full, aoe, target }
local function spawnNumber(position: Vector3, amount: number, kind: string, flags: any)
	local style = HIT[kind] or HIT.normal
	local scale = style.scale * (flags.aoe and HIT.aoeScale or 1)

	-- lift this number above the ones just made on the same target
	local lift = 0
	if flags.target then
		local stack = stacks[flags.target]
		local now = os.clock()
		if stack and now - stack.at < HIT.stackWindow then
			stack.n += 1
		else
			stack = { at = now, n = 0 }
			stacks[flags.target] = stack
		end
		stack.at = now
		lift = stack.n * HIT.stackOffset
	end

	local spread = HIT.numberSpread
	local anchor = Instance.new("Part")
	anchor.Name = "DamageNumberAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position + Vector3.new((math.random() - 0.5) * 2 * spread, lift, (math.random() - 0.5) * 2 * spread)
	anchor.Parent = workspace.CurrentCamera

	local gui = template:Clone()
	gui.Adornee = anchor
	gui.Size = UDim2.fromOffset(template.Size.X.Offset * scale, template.Size.Y.Offset * scale)
	local label = gui:FindFirstChild("Label") :: TextLabel
	local stroke = label and label:FindFirstChildOfClass("UIStroke")
	local finalTextSize = 0
	if label then
		-- the star marks a Full hit; a Full hit that is also a crit / crash keeps that style's colours and gains the star
		local star = flags.full and kind ~= "full" and (HIT.star .. " ") or ""
		label.Text = star .. (style.prefix and (style.prefix .. " ") or "") .. formatAmount(amount)
		label.TextColor3 = Color3.fromHex(style.color)
		finalTextSize = math.round(label.TextSize * scale)
		label.TextSize = math.max(1, math.round(finalTextSize * HIT.popFrom)) -- pops in to its size
		if stroke then
			stroke.Color = Color3.fromHex(style.stroke)
		end
	end
	-- crits and crashes show the hand-made CritBadge (template child) behind the number; the others hide it
	local badge = gui:FindFirstChild("CritBadge") :: ImageLabel?
	local badgeSize: UDim2? = nil
	if badge then
		badge.Visible = style.badge ~= nil
		if style.badge then
			badge.ImageColor3 = Color3.fromHex(style.badge.color)
			badge.ImageTransparency = style.badge.transparency
			badgeSize = UDim2.fromOffset(badge.Size.X.Offset * scale, badge.Size.Y.Offset * scale)
			badge.Size = UDim2.fromOffset(badgeSize.X.Offset * HIT.popFrom, badgeSize.Y.Offset * HIT.popFrom)
		end
	end
	gui.Parent = anchor

	local pop = TweenInfo.new(HIT.popTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if label then
		TweenService:Create(label, pop, { TextSize = finalTextSize }):Play()
	end
	if badge and badgeSize then
		TweenService:Create(badge, pop, { Size = badgeSize }):Play()
	end

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
	local target = typeof(data.target) == "Instance" and data.target or nil
	if data.taken == true then
		-- a player took damage: a red number over them, nothing else
		spawnNumber(data.position, data.damage, "taken", { target = target })
		return
	end
	-- the number's style: Crash beats Crit beats Full beats a normal hit (Full also adds a star to the other styles)
	local kind = data.crash == true and "crash" or data.isCrit == true and "crit" or data.full == true and "full" or "normal"
	spawnNumber(data.position, data.damage, kind, { full = data.full == true, aoe = data.aoe == true, target = target })
	if target and target:IsA("Model") then
		flash(target)
	end
	CombatFX.impact(data.position, data.weaponType, data.weaponId)
	-- the swing's attack sound: only when it hit, once per swing (the nearest target), crit variant on a crit
	if type(data.step) == "number" and data.first == true and type(data.weaponType) == "string" then
		CombatFX.hitSound(typeof(data.point) == "Vector3" and data.point or data.position, data.weaponType, data.step, data.weaponId, data.isCrit == true)
	end
	EnemyFX.hit(data)
end)
