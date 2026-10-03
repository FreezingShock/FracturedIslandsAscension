--[[
	Settings.lua — GlassHandler (Merged)

	Two glass modes:
	  • Liquid  — model-level Highlight + Glass parts at Transparency 3.
	             Adaptive 9-part grid (Center/Edge/Corner) when UICorner present.
	  • Mosaic  — no Highlight; CenterMosaic template parts left untouched
	             (Glass, 0.8 transparency, Reflectance 1 baked in template).
	             Always flat tiled grid.

	Shared overlay features (independently toggleable per instance):
	  • Stroke                  — cursor-tracking specular UIStroke + UIGradient.
	  • SeparatedBorderOutline  — hover-activated offset outline via UIStroke.BorderOffset.
]]

return {

	-- ── Tags ──────────────────────────────────────────────────────────────
	LiquidTag = "LiquidGlass",
	MosaicTag = "MosaicGlass",

	-- ── Shared geometry ───────────────────────────────────────────────────
	Padding = 0.001,
	Depth = 2,

	-- ── Liquid glass mode ─────────────────────────────────────────────────
	-- Exact v1 approach: model-level Highlight (black fill) + Glass parts
	-- at Transparency 3 for the >1 distortion trick.
	Liquid = {
		Highlight = {
			FillColor = Color3.fromRGB(0, 0, 0),
			OutlineTransparency = 1,
			FillTransparency = 0.9,
		},
		Mesh = {
			Material = Enum.Material.Glass,
			Color = Color3.fromRGB(0, 0, 0),
			Transparency = 3,
		},
	},

	-- ── Mosaic glass mode ─────────────────────────────────────────────────
	-- Distortion-only approach: no model Highlight. CenterMosaic template
	-- properties (Glass, Transparency 0.8, Reflectance 1) are baked in the
	-- .rbxm and left untouched after cloning.
	-- `strength` is the Part.Transparency override — set to 0.8 to match
	-- the template default. Increase for heavier distortion if desired.
	Mosaic = {
		Distortion = {
			strength = 0.8,
			gridCols = 3,
			gridRows = 2,
		},
	},

	-- ── Dynamic specular stroke (shared, same defaults for both modes) ────
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

	-- ── Separated border outline (shared, same defaults for both modes) ───
	-- Off by default; enable per-instance via .apply() overrides.
	SeparatedBorderOutline = {
		enabled = false,
		offset = 7,
		thickness = 3,
		color = Color3.fromRGB(213, 229, 255),
		restTransparency = 1,
		hoverTransparency = 0.15,
		tweenInTime = 0.25,
		tweenOutTime = 0.2,
		easingIn = Enum.EasingStyle.Quint,
		easingOut = Enum.EasingStyle.Quint,
	},
}
