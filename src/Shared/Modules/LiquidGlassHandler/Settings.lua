--[[
	LiquidGlass Settings

	TUNING GUIDE:
	─────────────────────────────────────────────────────────
	Mesh.Transparency   = THE main blur knob
	                      0.0  = fully opaque glass (blocks view)
	                      0.5  = heavy frost (strong blur, still see shapes)
	                      0.7  = medium frost (clear blur, readable background)
	                      1.0  = light frost (subtle distortion)
	                      3.0  = nearly invisible (original default — minimal effect)

	Mesh.Color          = Glass tint
	                      (255,255,255) = bright/white frost (iOS style)
	                      (200,200,210) = cool neutral frost
	                      (0,0,0)       = dark smoked glass

	Highlight.FillTransparency = Overlay darkness
	                      0.7  = noticeable tint
	                      0.85 = subtle tint
	                      0.95 = barely visible
	                      1.0  = no tint at all

	Highlight.FillColor = Overlay tint color
	                      White = bright frost glow
	                      Black = darkened frost
	                      Match your UI accent = themed frost

	Depth               = Camera distance (studs)
	                      0.1  = very close (large glass, strong effect)
	                      0.5  = moderate
	                      2.0  = far (subtle, original default)
	─────────────────────────────────────────────────────────
]]

return {
	Highlight = {
		FillColor = Color3.fromRGB(20, 20, 30), -- dark cool tint for depth
		OutlineTransparency = 1, -- no outline
		FillTransparency = 0.82, -- visible but not overpowering
	},
	Mesh = {
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(180, 180, 195), -- cool neutral glass tint
		Transparency = 3, -- heavy frost, strong blur
		Anchored = true,
		CastShadow = false,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		AudioCanCollide = false,
	},
	Tag = "LiquidGlass",
	Padding = 0.001,
	Depth = 2,
}

--[[
	PRESET REFERENCE (copy-paste to swap):

	── MAXIMUM FROST (near-opaque, very blurry) ──
	Mesh.Transparency    = 0.35
	Mesh.Color           = Color3.fromRGB(200, 200, 210)
	Highlight.FillTransparency = 0.75
	Highlight.FillColor  = Color3.fromRGB(30, 30, 40)

	── BALANCED FROST (readable background, clear blur) ──
	Mesh.Transparency    = 0.55
	Mesh.Color           = Color3.fromRGB(180, 180, 195)
	Highlight.FillTransparency = 0.82
	Highlight.FillColor  = Color3.fromRGB(20, 20, 30)

	── LIGHT FROST (subtle distortion, mostly transparent) ──
	Mesh.Transparency    = 0.8
	Mesh.Color           = Color3.fromRGB(220, 220, 230)
	Highlight.FillTransparency = 0.92
	Highlight.FillColor  = Color3.fromRGB(10, 10, 15)

	── DARK SMOKED GLASS ──
	Mesh.Transparency    = 0.45
	Mesh.Color           = Color3.fromRGB(15, 15, 20)
	Highlight.FillTransparency = 0.7
	Highlight.FillColor  = Color3.fromRGB(0, 0, 0)
]]
