# Ideation report .md contract (read by build_html.py)

```
---
type: fia-ideation
date: YYYY-MM-DD
based_on: <short sha>
ideas:
  - {id: <OUT>-1, name: ..., size: S|M|L}
---
# FI:A ideation - YYYY-MM-DD (nth batch)

## Summary
3 short lines. Use {green:..} {red:..} {gold:..} {yellow:..} {aqua:..} {lpurple:..} {blue:..} for the key facts:
the top pick and why, the biggest gaps found, and anything repeated/skipped.

Assumptions: one line (shown collapsed as "Run notes").

## What I noticed
- **Bold lead.** `file` cited sentence.   (3-5 bullets)

## Ideas
### 1. Name (S|M|L)
- **Pitch:** ...
- **Why now:** ...
- **Spec:** <goal> Files: `a`, `b`  Config: ... **Out of scope:** ... **Verification:** a; b; c **Placeholders needed:** ...
- **Keybind:** F (free)   |  none
- **Risk:** ...
(four ideas, ranked best first)

## Recommendation
3 sentences.

## Paste-ready prompt
```
/fia-feature ...
```
```
Notes: the title is `Weekday, Month Dth (nth)`; "(nth)" is the batch from the filename suffix (`-3` = 3rd, none = 1st). Verification items are split on `;`, Files items on `, ` before a backtick.
Inline: `code`, **bold** (gold), {color:text}. Colours: green red gold yellow aqua blue lpurple gray white.
