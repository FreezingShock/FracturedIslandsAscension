---
name: fia-ideate
description: Turn a rough game idea or prompt into a concrete, buildable spec grounded in the existing systems. Use when the user brainstorms, has a vague feature idea, asks "what if", or wants to expand/refine an idea before building.
argument-hint: <rough idea>
---

# /fia-ideate $ARGUMENTS

Purpose: expand a rough idea into something `/fia-feature` can execute, without building anything.
The user pastes the result straight into `/fia-feature`, so the last code block is the deliverable.

How the user uses this (keep doing what works): they give a topic list ("abilities and mana: the Q ability, mana
cost, hit shapes through DamageService, fx and sfx, aoe, dot"), answer 3-4 multiple-choice questions, then run the
prompt you hand back unchanged. They rarely need a long brainstorm; they need the right questions and a tight spec.

1. **Ground it (cheap, code first):** `Grep` the repo for the systems it touches (the existing module, config,
   remote, hook it will plug into; quote file:line). For design intent and registry rows, `Grep` the vault files
   directly (`C:\Users\natea\Documents\Obsidian\FracturedVault\8 - Claude\projects\fractured-islands.md`, it is an added
   working directory) instead of `obsidian_search`: it is cheaper and still works when the Obsidian MCP is
   disconnected. Cite only what is relevant; never read whole notes.
2. **Expand, only if the idea is vague:** 3-5 concrete directions (what the player does, data it needs, systems it
   reuses, cost S/M/L). If the user already listed the pieces, skip this and go straight to risks and questions.
3. **Pressure-test the favorite (short, 3-4 lines):** the strongest risk (exploit surface: what does the client send?;
   per-tick performance with many targets; balance/exponential growth; UI space; save-schema change) and how to
   mitigate it. Use `/obsidian-challenge` only for project-sized ideas.
4. **Ask only what is the user's call** with `AskUserQuestion` (max 4, recommended option first, concrete numbers in
   the options). Good questions are the ones the code cannot answer: trigger/keybind, formula or balance numbers,
   how much of the first set to ship, and **art/animation/sound: placeholder now or the user's own ids later**.
   Never ask what the code answers.
5. **Output a spec** (<=12 lines): Goal - Player-facing behavior - Data/config shape - Files likely touched -
   Out of scope - Verification (what the user or `/fia-verify` observes) - Open questions. Always cover:
   - **Config shape:** layered like `CombatConfig` / `AbilityConfig` (library -> type or item -> per-weapon override),
     so adding the next weapon / ability / enemy is data, not code ("modular, easy to change, for all future X").
   - **Server authority:** the client sends intent only (a key name, a click); the server derives targets, costs, ids.
   - **Others see it:** anything with sound or effects plays for nearby players (3D, sourced from the actor).
   - **GUI:** who builds it. Hand-made in Studio by the user, or a template I create through the Studio MCP and they
     restyle; never `Instance.new` UI in a script. Name the instances scripts will look up.
   - **Assets still missing:** animation ids, sound ids, icons: say which slots stay silent / placeholder.
6. **End with a ready-to-run prompt** in ONE code block (this exact shape has worked every time):
   ````
   /fia-feature <one-line title>
   SPEC: <the spec above as one paragraph, including out of scope and the verification step>
   ````
   Then one line offering `/obsidian-decide` (the user usually skips it; do not push). For a project-sized idea offer
   `/obsidian-graduate`. Do not create new vault files unless asked. Do not start building.
