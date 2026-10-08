---
name: figma-to-studio
description: Turn a Figma frame into a Roblox Studio GUI template. Use when the user shares a figma.com link or says "build this design in Studio".
argument-hint: <figma url>
---

# figma-to-studio $ARGUMENTS

1. Load the Figma tools via ToolSearch, then `get_design_context` (structure/tokens) and `get_screenshot` (reference only).
2. Map to Roblox: auto-layout -> `UIListLayout`/`UIGridLayout`, padding -> `UIPadding`, fills -> `BackgroundColor3`/`UIGradient`, strokes -> `UIStroke`, text -> TextLabel with the pixel font. Snap colors to the Minecraft palette unless the design is explicit; use Scale sizing plus `UIAspectRatioConstraint` for pixel art.
3. Export raster pieces with `download_assets`, then `upload_image` / `store_image`; unknown asset ids are placeholders.
4. Build with `/fia:studio-build` (inspect existing first, template not scripted UI, builder saved to `tools/studio/`).
5. Verify with `inspect_instance` text assertions plus one `screen_capture` beside the Figma screenshot.

Going the other way (Studio -> Figma) uses `use_figma`; load `/figma-use` first.
