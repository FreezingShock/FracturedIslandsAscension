# Figma: FIA HUD Design System (the one master file)

All Figma UI design lives in ONE file: **FIA HUD Design System**, key `X4cTI05Lfoahh8sHQa3bB3`
(https://www.figma.com/design/X4cTI05Lfoahh8sHQa3bB3). **Roblox Studio stays the master**: the file is only for designing NEW
menus in line with the HUD bar / hotbar look before they are imported. Never start a second Figma file for a menu.

| Page | What is on it |
|---|---|
| Screen | `Gameplay Screen` component (1080p placeholder background + overlays: HUD Bar, Hotbar, Scoreboard, Recent Gains chip / list (removed from the game in 3.77.1, off by default), Enemy Nameplate, Notifications) with one BOOLEAN property per overlay, an instance, and the same screen as plain layers |
| Menus & HUD | One section per Studio GUI: `StarterGui.FIAHUD`, `ReplicatedStorage.GUI.EnemyNameplate`, `StarterGui.FIAScoreboard`, `StarterGui.FIANotifications`, Drop tooltips |
| Animations | Keyframe boards (notification slide, nameplate appear / hit / death, hotbar selector slide, bar fill steps) + timings from the code |
| Index | Pixel sheets of every game icon (items, stats, tags), HUD sprites, the Placeholders component library (slot, tag, card, menu panel, icon slots, pixel canvas) |
| Menus (placeholders) | Statistics, Skills, Inventory, View menu frames, ready to design |
| Styles | Paint styles (MC/*, HUD/*, Tooltip/*), text styles, effect styles, tooltip look, pixel-art rules |
| Components | Resource Bar, XP Segment, Resource Panel, Level Badge, Hotbar Slot, icons, drop tooltip sets |

New menu = a new frame in the master (Menus & HUD), built from the Styles page and the Placeholders, named after the Studio
instances the scripts look up. Source files (kept, do not edit): HUD `FYaO8Cagn5ECNdeios2eDh`, Enemy Nameplate
`bu0f6zkvcvSFMRYBlpPIid`, Scoreboard + Recent Gains `ltNBW0fgdnPS09JGKIqIx9`, Notifications `X8Df0yEXjx1sPPBmv1Mzj9`.

## Tools
- `gen_icon_pixels.py`: pixel dumps of assets/icons, assets/stat_icons (run `tools/fetch_stat_icons.py` first) and assets/tag_icons into `icon_pixels.json`; the Figma side turns each horizontal run into a rectangle.
- `ser.js` / `des.js`: a serializer / deserializer that copies a node tree between two Figma files through chat. Works, but is slow and error-prone for big pages (the `use_figma` return value is capped at 20,480 bytes and files share no storage or network), so bulk copies are done with a native copy-paste.
- Figma MCP gotchas: it cannot list files (needs the file key); `createImageAsync` is not allowed; one `setCurrentPageAsync` per call; pages must be `loadAsync()`ed before reading their children.
