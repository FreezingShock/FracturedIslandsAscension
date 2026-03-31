-- ============================================================
--  ChatBridge (ModuleScript)
--  Place inside: ReplicatedStorage > Modules
--
--  Follows the same pattern as MenuBridge — lets any LocalScript
--  communicate with ChatController without direct script references.
--
--  TWO USE CASES:
--
--  1. Local-only system message (no server round trip):
--     For cosmetic client events you already know happened
--     (e.g. an animation finishing, a UI button press echo).
--     Call ChatBridge.postLocal(templateKey, tokens).
--     ChatController renders it immediately, no server involved.
--
--  2. Trigger a server-authoritative system message:
--     For events that must be broadcast to all players or need
--     server validation. Fire the relevant RemoteEvent / call the
--     relevant RemoteFunction, and let ChatService.FireSystemMessage
--     handle it server-side — ChatController will receive it via
--     the SystemMessage RemoteEvent automatically.
--     (You don't need ChatBridge for this path at all.)
--
--  USAGE EXAMPLE:
--    -- In SkillsMenuHandler (LocalScript):
--    local ChatBridge = require(ReplicatedStorage.Modules.ChatBridge)
--    ChatBridge.postLocal("BUTTON_PRESS", { amount = 50, skill = "Mining" })
--
-- ============================================================

local ChatBridge = {}

-- ── Registered by ChatController ──────────────────────────────
-- ChatController calls ChatBridge.registerRenderer(fn) at startup.
-- fn signature: fn(payload)
--   payload = {
--       type        = "system",
--       templateKey = string | nil,
--       lines       = { string... },
--       colors      = { [lineIndex] = "RRGGBB" },
--       bold        = { [lineIndex] = true },
--       channel     = string,
--       hideFromAll = bool,
--       sound       = string | nil,
--       timestamp   = number,
--   }
ChatBridge._renderFn = nil

function ChatBridge.registerRenderer(fn)
	ChatBridge._renderFn = fn
end

-- ── Internal: build a payload from a template key + tokens ────
local function buildLocalPayload(templateKey, tokens)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ChatConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ChatConfig"))

	local template = ChatConfig.Templates[templateKey]
	if not template then
		warn("[ChatBridge] Unknown templateKey:", templateKey)
		return nil
	end

	-- Apply token substitution
	local resolvedLines = {}
	for i, line in ipairs(template.lines) do
		resolvedLines[i] = (
			line:gsub("{(%w+)}", function(key)
				local val = tokens and tokens[key]
				if val == nil then
					return "{" .. key .. "}"
				end
				return tostring(val)
			end)
		)
	end

	-- Serialize Color3 → hex
	local serializedColors = {}
	if template.colors then
		for idx, color in pairs(template.colors) do
			serializedColors[idx] = string.format(
				"%02X%02X%02X",
				math.floor(color.R * 255),
				math.floor(color.G * 255),
				math.floor(color.B * 255)
			)
		end
	end

	return {
		type = "system",
		templateKey = templateKey,
		lines = resolvedLines,
		colors = serializedColors,
		bold = template.bold or {},
		channel = template.channel,
		sound = template.sound,
		hideFromAll = template.hideFromAll or false,
		timestamp = os.time(),
		_local = true, -- flag: this was not server-authoritative
	}
end

-- ── Public API ────────────────────────────────────────────────

-- Post a system message locally (client-side only, not broadcast).
-- templateKey : string key from ChatConfig.Templates
-- tokens      : { skill="Mining", level=14, ... }
function ChatBridge.postLocal(templateKey, tokens)
	local payload = buildLocalPayload(templateKey, tokens)
	if not payload then
		return
	end
	if ChatBridge._renderFn then
		ChatBridge._renderFn(payload)
	else
		warn("[ChatBridge] postLocal called before ChatController registered renderer.")
	end
end

-- Post a raw local message (no template needed).
-- lines    : { "line 1", "line 2", ... }   "" = blank spacer
-- hexColors: { [lineIndex] = "RRGGBB" } or nil
-- boldMap  : { [lineIndex] = true } or nil
-- channel  : string channel key (default "game")
function ChatBridge.postRaw(lines, hexColors, boldMap, channel)
	local payload = {
		type = "system",
		lines = lines,
		colors = hexColors or {},
		bold = boldMap or {},
		channel = channel or "game",
		hideFromAll = false,
		timestamp = os.time(),
		_local = true,
	}
	if ChatBridge._renderFn then
		ChatBridge._renderFn(payload)
	else
		warn("[ChatBridge] postRaw called before ChatController registered renderer.")
	end
end

return ChatBridge
