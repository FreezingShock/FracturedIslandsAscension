--[[
	NexusBadgeView (ModuleScript, Shared)
	Place inside: ReplicatedStorage > Modules

	Drives a Nexus Level badge (the HUD's FIAHUD.Root.Badge and the big copy on the Nexus Level page share this): a Frame that holds
	  XpClip   Frame, ClipsDescendants, anchored to the bottom; its HEIGHT is the xp progress (the hex inside it never moves or resizes,
	           so the fill is clipped to the badge shape while the clip grows)
	  Level    TextLabel, the level number (tinted by NexusConfig.tiers)
	built by tools/studio/build_nexus_badge.luau. Looks (tween, hex size) are HudTheme.badge.xp; the numbers come from the Player
	attributes NexusService publishes (NexusConfig.attributes), the client only reads.

	  NexusBadgeView.bind(badge, player)   -> { set(level, progress, instant?), destroy() }  (also follows the player's attributes)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = Modules:WaitForChild("Config")
local HudTheme = require(Config:WaitForChild("HudTheme")) :: any
local NexusConfig = require(Config:WaitForChild("NexusConfig")) :: any
local ResourceConfig = require(Modules:WaitForChild("ResourceConfig")) :: any

local XP = HudTheme.badge.xp

local NexusBadgeView = {}

function NexusBadgeView.bind(badge: Instance, player: Player?)
	local clip = badge:FindFirstChild("XpClip") :: Frame?
	local label = badge:FindFirstChild("Level") :: TextLabel?
	if not clip then
		warn("[NexusBadgeView] " .. badge:GetFullName() .. ".XpClip is missing (run tools/studio/build_nexus_badge.luau)")
	end

	local view = {}
	local tween: Tween? = nil
	local connections: { RBXScriptConnection } = {}
	local lastLevel, lastProgress = nil, nil

	function view.set(level: number, progress: number, instant: boolean?)
		level = math.floor(tonumber(level) or 0)
		progress = math.clamp(tonumber(progress) or 0, 0, 1)
		if label and level ~= lastLevel then
			label.Text = tostring(level)
			label.TextColor3 = Color3.fromHex((NexusConfig.colorFor(level):gsub("#", "")))
		end
		if clip and progress ~= lastProgress then
			local goal = UDim2.fromOffset(XP.hexSize.X, math.floor(XP.hexSize.Y * progress + 0.5))
			if tween then
				tween:Cancel()
				tween = nil
			end
			-- a level-up drops the progress back near 0: fill/empty with the tween either way (instant on the first read)
			if instant or lastProgress == nil then
				clip.Size = goal
			else
				local info = TweenInfo.new(XP.tween.time, XP.tween.style, XP.tween.direction)
				tween = TweenService:Create(clip, info, { Size = goal })
				tween:Play()
			end
		end
		lastLevel, lastProgress = level, progress
	end

	if player then
		local attributes = NexusConfig.attributes
		local function read(instant: boolean?)
			view.set(
				player:GetAttribute(attributes.level) or ResourceConfig.nexusLevelStart,
				player:GetAttribute(attributes.progress) or 0,
				instant
			)
		end
		table.insert(connections, player:GetAttributeChangedSignal(attributes.level):Connect(read))
		table.insert(connections, player:GetAttributeChangedSignal(attributes.progress):Connect(read))
		read(true)
	end

	function view.destroy()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(connections)
		if tween then
			tween:Cancel()
		end
	end

	return view
end

return NexusBadgeView
