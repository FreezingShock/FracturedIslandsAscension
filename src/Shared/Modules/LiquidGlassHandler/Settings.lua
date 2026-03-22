--[[
	Settings.lua — LiquidGlassHandler 3.1

	Two Glass layers (Back + Front) — frosted body.
	Dynamic UIStroke + UIGradient — cursor-tracking specular highlight.

	CHANGES FROM 3.0:
	  ① ALL Highlight outlineTransparency set to 1 (disabled).
	    The UIStroke now provides the specular rim. Highlight outlines on
	    individual Glass parts caused visible line artifacts where parts
	    met, especially with overlapping glass instances.
	  ② ForceFlat = true added. Uses 1 Center part per layer regardless of
	    UICorner presence, eliminating ALL internal seams from the 9-part
	    rounded-corner grid. The frosted glass effect is subtle enough that
	    square-cornered glass on a rounded frame is unnoticeable.
	  ③ Padding reduced to 0.001 (single-part mode has no seams to close;
	    this is just a minor safety margin).

	meshTransparency must stay 0.30–0.65 for Glass refraction to be active.
]]

return {

	-- ── Legacy keys (mirror Layer 1) ─────────────────────────────────────
	Highlight = {
		FillColor = Color3.fromRGB(190, 210, 235),
		OutlineColor = Color3.fromRGB(255, 255, 255),
		OutlineTransparency = 1, -- DISABLED: UIStroke handles rim
		FillTransparency = 0.55,
	},
	Mesh = {
		Material = Enum.Material.Glass,
		Color = Color3.fromRGB(175, 192, 215),
		Transparency = 0.40,
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

	-- When true, always use a single Center part per layer regardless of
	-- whether the GuiObject has a UICorner. Eliminates ALL internal seams
	-- from the 9-part rounded-corner grid. The frosted glass effect is
	-- subtle enough that the glass not following rounded corners exactly
	-- is unnoticeable in practice.
	ForceFlat = true,

	-- ── Two-layer glass stack ─────────────────────────────────────────────
	Layers = {
		{ -- Back: frosted body anchor
			depthOffset = 0.22,
			fillColor = Color3.fromRGB(190, 210, 235),
			fillTransparency = 0.55,
			outlineColor = Color3.fromRGB(255, 255, 255),
			outlineTransparency = 1, -- DISABLED: was causing nested-rectangle artifacts
			meshColor = Color3.fromRGB(175, 192, 215),
			meshTransparency = 0.40,
		},
		{ -- Front: glass face (specular rim now via UIStroke, not Highlight)
			depthOffset = -0.08,
			fillColor = Color3.fromRGB(228, 236, 252),
			fillTransparency = 0.72,
			outlineColor = Color3.fromRGB(255, 255, 255),
			outlineTransparency = 1, -- DISABLED: was 0.18, primary cause of line artifacts
			meshColor = Color3.fromRGB(192, 206, 228),
			meshTransparency = 0.54,
		},
	},

	Rim = { enabled = true },

	-- ── Dynamic specular stroke ───────────────────────────────────────────
	Stroke = {
		enabled = true,
		thickness = 4,
		color = Color3.fromRGB(255, 255, 255),
		restingAngle = 135,
		lerpSpeed = 8,

		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.0),
			NumberSequenceKeypoint.new(0.08, 0.35),
			NumberSequenceKeypoint.new(0.2, 0.88),
			NumberSequenceKeypoint.new(0.4, 0.97),
			NumberSequenceKeypoint.new(0.6, 0.97),
			NumberSequenceKeypoint.new(0.8, 0.88),
			NumberSequenceKeypoint.new(0.92, 0.35),
			NumberSequenceKeypoint.new(1, 0.15),
		}),

		colorSequence = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(230, 240, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(195, 212, 238)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 232, 252)),
		}),
	},
}
