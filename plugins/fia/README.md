# fia: Fractured Islands Ascension dev plugin

One toolkit for every FIA session (desktop or MacBook): Roblox Studio + Rojo, Blender, Figma, and the Obsidian vault as memory.

## Install

```
/plugin marketplace add FreezingShock/FracturedIslandsAscension
/plugin install fia@fia-marketplace
```

Local checkout: `/plugin marketplace add <path to repo>`.

## Skills (invoke as `/fia:<name>`)

| Skill | Use |
|---|---|
| `connect` | "connect and load": pull main, regenerate project, restart Rojo, find Studio, check vault |
| `recall` | pull registry rows, lessons and past decisions for a system before working on it |
| `handoff` | end-of-session vault log, registry rows, "where I stopped" (also for machine switches) |
| `lesson` | capture a correction or pitfall into auto-memory and the vault |
| `studio-build` | create GUI/templates/markers via the Studio MCP and save the builder script |
| `gui-audit` | verify every GUI name the scripts look up exists in the live place |
| `blender-asset` | Blender MCP model/animation to Roblox, generator saved in `tools/blender/` |
| `figma-to-studio` | Figma frame to Studio GUI template |
| `reports` | import the cloud routines' daily/weekly/ideation reports from `claude/fia-reports` into the vault |
| `report-style` | styles and organizes the .html of FIA reports (routines call `build_html.py` on the report .md); edit `report.css` / `keywords.json` to restyle |
| `content` | add items/abilities/enemies as config data using the layered recipes |
| `fia-ideate`, `fia-feature`, `fia-verify`, `fia-ship`, `fia-skill` | the feature pipeline (copied from `.claude/skills`) |

Agent: `lua-explorer` (read-only code search).

## MCP servers (`.mcp.json`)

`Roblox_Studio` (Windows `mcp.bat` launcher; the macOS Studio MCP path is not bundled, set it in user config) and `blender` (`uvx blender-mcp`). The Obsidian vault server comes from the `obsidian-second-brain` plugin; Figma is a connector.

## Maintaining

The `fia-*` skills and the agent are edited in `.claude/` and copied here. After changing them: `python tools/build_plugin.py` (copies, then validates). New plugin skills are authored directly in `plugins/fia/skills/<name>/SKILL.md`. Project hooks stay in `.claude/settings.json` (they need the repo's `tools/`), so the plugin ships none, to avoid running them twice.

Inside this repo the project-level `.claude/` skills already load, so the plugin matters for other checkouts and projects.

## Cloud routines

Three claude.ai routines (Anthropic cloud, repo-only, no connectors) write markdown to branch `claude/fia-reports`:

| Routine | When (Pacific, PDT) | Output |
|---|---|---|
| Daily review (rolling 7 days, per day) | every day ~6am | `reports/daily/<date>.md` |
| Ideation | Mon-Sat ~7am | `reports/ideation/<date>.md` |
| Weekly summary | Sunday ~6pm | `reports/weekly/<year>-W<week>.md` |

Crons are fixed UTC, so the Pacific time shifts one hour when daylight saving ends (Nov 1). Obsidian Sync cannot be mounted in the cloud, so `/fia:reports` pulls the branch and files the reports into the vault (`Claude outputs/FIA reports/`), which Sync then carries to every device. Manage the routines at https://claude.ai/code/routines.
