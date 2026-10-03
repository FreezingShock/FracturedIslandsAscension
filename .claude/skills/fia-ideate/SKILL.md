---
name: fia-ideate
description: Turn a rough game idea or prompt into a concrete, buildable spec grounded in the existing systems. Use when the user brainstorms, has a vague feature idea, asks "what if", or wants to expand/refine an idea before building.
argument-hint: <rough idea>
---

# /fia-ideate $ARGUMENTS

Purpose: expand a rough idea into something `/fia-feature` can execute, without building anything.

1. **Ground it (cheap):** `obsidian_search` the idea's keywords (vault design notes, hub, idea board) and
   `Grep` the repo for the systems it touches. Cite only what is relevant; do not read whole notes.
2. **Expand:** give 3-5 concrete directions (not generic) that fit the game's pillars: button-pressing +
   passive income, stat/multiplier chains, config-driven content, Minecraft/SkyBlock feel, server-authoritative.
   For each: what the player does, what data it needs, which existing systems it reuses, rough cost (S/M/L).
3. **Pressure-test the favorite:** the strongest risk (balance/exponential growth, UI space, save-schema change,
   multiplayer/exploit surface) and how to mitigate it. Use `/obsidian-challenge` if the idea is large.
4. **Ask only what is the user's call** with `AskUserQuestion` (max 4, recommended option first).
5. **Output a spec** (<=12 lines): Goal - Player-facing behavior - Data/config shape - Files likely touched -
   Out of scope - Verification (what `/fia-verify` observes) - Open questions.
6. Offer to save it (`/obsidian-decide` for decisions, `/obsidian-graduate` for a project-sized idea) and to
   run `/fia-feature` on it. Do not create new vault files unless the user asks.
