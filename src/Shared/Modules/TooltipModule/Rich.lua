--[[
	TooltipModule/Rich (ModuleScript)

	Tiny helpers for building the rich-text strings tooltips use, so callers
	don't hand-write <font> tags. Everything returns a plain string.

	  Rich.color("text", "#FF5555")      colored text
	  Rich.value("75 Damage", "#FF5555") highlighted value in the pixel font
	  Rich.damage(75)  Rich.studs(50)    common ability highlights
	  Rich.key("LMB")                    yellow key / button name
	  Rich.sc("Cooldown: 10s")           small caps
	  Rich.strip(text)                   remove all tags
	  Rich.firstColor(text)              first color="#RRGGBB" found, or nil
--]]

local Style = require(script.Parent:WaitForChild("Style"))

local Rich = {}

function Rich.color(text: any, hex: string): string
	return string.format('<font color="%s">%s</font>', Style.hex(hex), tostring(text))
end

function Rich.value(text: any, hex: string?): string
	return string.format('<font color="%s" family="%s">%s</font>', Style.hex(hex or "#FFFFFF"), Style.FONT_PIXEL, tostring(text))
end

function Rich.bold(text: any): string
	return "<b>" .. tostring(text) .. "</b>"
end

function Rich.sc(text: any): string
	return "<sc>" .. tostring(text) .. "</sc>"
end

function Rich.key(text: any): string
	return Rich.color(text, "#FFFF55")
end

function Rich.dash(): string
	return Rich.color("-", "#AAAAAA")
end

function Rich.damage(amount: any): string
	return Rich.value(tostring(amount) .. " Damage", "#FF5555")
end

function Rich.studs(amount: any): string
	return Rich.value(tostring(amount) .. " studs", "#55FF55")
end

--- Minecraft color codes -> rich text.  "&7Base &f10 &a+5"  (&r resets, &l bold)
--- Both "&" and "§" work. Unknown codes are left as-is.
function Rich.mc(text: any): string
	local input = tostring(text):gsub("§", "&")
	local out = {}
	local openColor, openBold = false, false
	local function closeAll()
		if openBold then
			table.insert(out, "</b>")
			openBold = false
		end
		if openColor then
			table.insert(out, "</font>")
			openColor = false
		end
	end
	local i = 1
	while i <= #input do
		local ch = input:sub(i, i)
		local code = input:sub(i + 1, i + 1):lower()
		if ch == "&" and (Style.MC_CODES[code] or code == "r" or code == "l") then
			if code == "l" then
				if not openBold then
					table.insert(out, "<b>")
					openBold = true
				end
			elseif code == "r" then
				closeAll()
			else
				if openBold then
					table.insert(out, "</b>")
					openBold = false
				end
				if openColor then
					table.insert(out, "</font>")
				end
				table.insert(out, string.format('<font color="%s">', Style.MC_CODES[code]))
				openColor = true
			end
			i += 2
		else
			table.insert(out, ch)
			i += 1
		end
	end
	closeAll()
	return table.concat(out)
end

function Rich.strip(text: string): string
	return (tostring(text):gsub("<[^>]+>", ""))
end

function Rich.firstColor(text: string): string?
	local hex = tostring(text):match('color="(#?%x%x%x%x%x%x)"')
	if hex then
		return Style.hex(hex)
	end
	return nil
end

return Rich
