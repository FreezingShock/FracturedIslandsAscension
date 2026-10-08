---
name: report-style
description: Styles and organizes the .html version of an FIA report (ideation now, other routines later). Use ONLY when generating or redesigning a report's .html, never for markdown, game UI or other artifacts. Runs build_html.py on the .md.
argument-hint: <path to report .md, or a styling change>
---

# report-style

One source of truth for how every FIA report `.html` looks and is organized. The **`.md` is the content**, the HTML is always generated from it, never hand-written.

## Generate (routines and sessions)
```
python3 plugins/fia/skills/report-style/build_html.py reports/ideation/<name>.md
```
Writes `<name>.html` next to the md. Needs git history only for the commit subject in the header (falls back to the sha). Nothing else to fill in, no template.

## The md must follow `references/format.md`
Frontmatter (`date`, `based_on`), `# title`, `## Summary` (3 short lines with `{color:text}` highlights), `Assumptions:` line, `## What I noticed`, `## Ideas` (`### n. Name (S|M|L)` blocks), `## Recommendation`, `## Paste-ready prompt`. If the md breaks the contract the script fails loudly: fix the md, not the script.

## Look (do not restate in other prompts)
- **Fonts:** Merriweather = grand titles and block labels; Minecraft (regular, never bold) = values and data (sha, sizes, keys, numbers, code, prompt); Noto Sans = all body text.
- **Colour:** the 16 Minecraft colour codes on `#0b0b1a`, rounded cards, gradient strokes. Idea colour comes from size (S green, M gold, L light purple). Important words are coloured automatically: bold = gold, numbers/versions = yellow, keywords from `keywords.json`, plus explicit `{green:text}` in the md.
- **Order:** date headline -> based-on commit -> coloured summary -> stat tiles -> At a glance -> What I noticed -> Ideas -> Recommendation -> Paste-ready prompt (copy button). Run notes are collapsed.

## Updating the look (iterate here, everything else follows)
| Change | Edit |
|---|---|
| Colours, fonts, radius, spacing | `report.css` (tokens at the top of the file) |
| Which words get coloured | `keywords.json` (`"word": "aqua"`) |
| Section order, hero, new block, new stat tile | `build_html.py` |
| New md section | `references/format.md` first, then `build_html.py` |
After any change: rebuild one existing report, look at it (headless Chromium screenshot or the browser), then `python tools/build_plugin.py --check`.

## Rules
- Only used when producing the `.html`. Daily/weekly markdown reports and game UI never use it.
- Keep the page self-contained except the Google Fonts link for Merriweather/Noto Sans (the Minecraft font is embedded from `_font.css`; refresh it by re-running the script on a machine that has the `artifact-styling` skill).
- No emoji; use the symbol icons already in `build_html.py`.
