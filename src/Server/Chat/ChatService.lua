-- ============================================================
--  ChatService (Script — server)
--  Place inside: ServerScriptService
--
--  WHY THIS IS SIMPLER THAN BEFORE:
--    Player chat text is now sent via TextChannel:SendAsync() on
--    the client. Roblox's TextChatService pipeline handles all
--    filtering automatically on the backend — GetChatForUserAsync
--    was deprecated in May 2025 and now returns empty strings.
--    This service no longer touches player text at all.
--
--  What this file still handles:
--    - System message broadcasting (level up, day change, etc.)
--    - FireSystemMessage() API for other server scripts
--    - BroadcastRaw() for one-off messages
--    - Player join/leave announcements
--
--  Wiring player messages to our custom GUI is handled entirely
--  on the client in ChatController via TextChatService.MessageReceived.
--
--  RemoteEvents in ReplicatedStorage:
--    "SystemMessage"  (server → client)  system blocks only
--    "SendChat" and "ReceiveChat" are NO LONGER USED and can be
--    deleted from ReplicatedStorage.
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ChatConfig = require(Modules:WaitForChild("ChatConfig"))

local ChatService = {}

-- ===================== REMOTE SETUP =====================
local function ensureRemote(class, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local r = Instance.new(class)
	r.Name = name
	r.Parent = ReplicatedStorage
	return r
end

-- Only SystemMessage is needed now
local SystemMsg = ensureRemote("RemoteEvent", "SystemMessage")

-- ===================== HELPERS =====================

local function toHex(color)
	return string.format(
		"%02X%02X%02X",
		math.floor(color.R * 255),
		math.floor(color.G * 255),
		math.floor(color.B * 255)
	)
end

local function applyTokens(str, tokens)
	if not tokens then
		return str
	end
	return (
		str:gsub("{(%w+)}", function(key)
			local val = tokens[key]
			if val == nil then
				return "{" .. key .. "}"
			end
			return tostring(val)
		end)
	)
end

-- ===================== PUBLIC API =====================

-- Fire a templated system message.
-- target = Player | nil (nil = broadcast to all)
--
-- Usage from another server Script:
--   local ChatService = require(ServerScriptService:WaitForChild("ChatService"))
--   ChatService.FireSystemMessage("LEVEL_UP", {
--       skill = "Mining", level = 14, romanLevel = "XIV"
--   }, player)
--
function ChatService.FireSystemMessage(templateKey, tokens, target)
	local template = ChatConfig.Templates[templateKey]
	if not template then
		warn("[ChatService] Unknown template key:", templateKey)
		return
	end

	local resolvedLines = {}
	for i, line in ipairs(template.lines) do
		resolvedLines[i] = applyTokens(line, tokens)
	end

	-- Color3 is not safely serialized over RemoteEvents — use hex strings
	local serializedColors = {}
	if template.colors then
		for idx, color in pairs(template.colors) do
			serializedColors[idx] = toHex(color)
		end
	end

	local payload = {
		type = "system",
		templateKey = templateKey,
		lines = resolvedLines,
		colors = serializedColors,
		bold = template.bold or {},
		channel = template.channel,
		sound = template.sound,
		hideFromAll = template.hideFromAll or false,
		timestamp = os.time(),
	}

	if target then
		SystemMsg:FireClient(target, payload)
	else
		SystemMsg:FireAllClients(payload)
	end
end

-- One-off raw system message with no template.
function ChatService.BroadcastRaw(lines, hexColors, boldMap, channel, target)
	local payload = {
		type = "system",
		lines = lines,
		colors = hexColors or {},
		bold = boldMap or {},
		channel = channel or "all",
		hideFromAll = false,
		timestamp = os.time(),
	}
	if target then
		SystemMsg:FireClient(target, payload)
	else
		SystemMsg:FireAllClients(payload)
	end
end

-- ===================== PLAYER LIFECYCLE =====================
Players.PlayerAdded:Connect(function(player)
	-- Add the player to the RBXGeneral TextChannel so SendAsync works.
	-- This is required — players won't be able to send messages without it.
	task.delay(1, function()
		if not player or not player.Parent then
			return
		end

		local channels = TextChatService:FindFirstChild("TextChannels")
		if channels then
			local general = channels:FindFirstChild("RBXGeneral")
			if general then
				-- AddUserAsync is only needed if you manually manage channel membership.
				-- With CreateDefaultTextChannels = true, Roblox does this automatically.
				-- This block is here as a safety net.
				local ok, err = pcall(function()
					general:AddUserAsync(player.UserId)
				end)
				if not ok then
					-- Non-fatal — player may already be in channel
					warn("[ChatService] AddUserAsync warn (non-fatal):", err)
				end
			end
		end

		-- Join announcement via our system message panel
		if ChatConfig.Behaviour.ShowJoinLeave then
			ChatService.FireSystemMessage("PLAYER_JOIN", { player = player.DisplayName })
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	if ChatConfig.Behaviour.ShowJoinLeave then
		ChatService.FireSystemMessage("PLAYER_LEAVE", { player = player.DisplayName })
	end
end)

print("[ChatService] Loaded ✓")

return ChatService
