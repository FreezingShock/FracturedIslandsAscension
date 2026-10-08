---
name: fia-feature
description: End-to-end pipeline for building a game feature - spec, implement, verify, review, commit to main. Manual only. Invoke as /fia-feature <short idea>.
disable-model-invocation: true
argument-hint: <feature idea>
---

# /fia-feature $ARGUMENTS

How the user runs this (the loop that has worked): they paste the prompt from `/fia-ideate`, I build, I restart Rojo
and ask them to press Connect, they reply "connected, verify it" (or they test it themselves and report), they ask
for small follow-ups ("one more small change"). **Shipping is automatic:** once the change is verified (my
`/fia-verify` PASS, or they say it works) I commit, push and write the vault log without being asked (decided
2026-10-04). Never ship before that point or on a FAIL: code they have not seen working does not go to git.

## 0. Size check (decides how much process to use)
- **Small / follow-up** (fits in one sentence, 1-3 files, no saved-data or Remote changes): skip the spec, skip review.
  Implement, run the static checks, tell them what to look at.
- **Large** (new system, 4+ files, touches saved data, RemoteEvents/Functions, or the menu/grid engine): run every phase.
- If `$ARGUMENTS` already contains a spec (pasted from `/fia-ideate`), skip phase 1 and start at phase 2.

Run the phases in order. Keep each phase's output short; send a one-line status if a step takes long.

## 1. Spec (skip if /fia-ideate already produced one)
- Read only what is needed: `Grep` the registry rows in the vault file
  `C:\Users\natea\Documents\Obsidian\FracturedVault\8 - Claude\projects\fractured-islands.md` (do not read it whole),
  and the files you will edit.
- `AskUserQuestion` only for the user's calls (design, naming, balance); max 4, recommended first.
- Spec of 6-10 lines: goal, files, config shape, **out of scope**, **verification step**.

## 2. Branch
None. Work and commit directly on `main` (no feature branches, no PRs). Make sure you are on `main` first.

## 3. Implement
- Follow CLAUDE.md: tabs, config-driven data, server-authoritative (client sends intent only, rate limited and
  type-checked), GUI bound by name. Existing GUI first: inspect it with the Studio MCP before inventing any.
- **Modular by default.** New content goes in a config with the same layering as `CombatConfig` / `AbilityConfig`
  (library -> type or item -> per-weapon override); behavior reads the config, nothing hardcoded. Document the recipes
  ("new ability: add an entry here") in the config file header. Reuse an existing pipeline when one exists (icons:
  `tools/fetch_icons.py` -> upload -> `gen_icon_data`; stat icons: ProfileConfig spritesheet cells).
- **Missing art is a placeholder, not a blocker.** Animation / sound / icon slots with no id stay silent or reuse an
  existing one; say which slots are waiting for the user's ids.
- **UI:** never `Instance.new` GUI in scripts. Create a template in Studio via the Studio MCP (`execute_luau`, Edit
  datamodel, pixel font `rbxassetid://12187371840`, Minecraft color codes) so the user can restyle it; scripts clone it
  and fill text / colors. Rebind on `PlayerGui.ChildAdded` (ResetOnSpawn). **Save the builder Luau to `tools/studio/build_<name>.luau` in the same turn** (idempotent, refuses to overwrite unless `FORCE`) and add it to `tools/studio/README.md`; the same goes for anything else Claude generates (Blender scripts to `tools/blender/`, icon fetchers, etc.): the generating script is committed, not just the output.
- Studio MCP: Edit-datamodel calls fail while Play is running. `start_stop_play(false)` first.
- New or moved script: the `post_edit` hook regenerates `default.project.json`. Then do the Rojo hand-off yourself:
  `python tools/gen_project.py --check`, `rojo build default.project.json -o "$TEMP/x.rbxlx"`, run `python tools/restart_rojo.py`
  (kills the old rojo by PID, restarts it, waits for the port), and ask the user to press **Connect**. Do not verify before they confirm.
- Use `Grep`/partial `Read`. Delegate wide exploration to the `lua-explorer` subagent.

## 4. Verify
When the user says "connected, verify it", run `/fia-verify` (static, sync, errors, text assertions of the spec's
verification step; real input beats command-bar `require`, which makes duplicate module instances). If the user says
they tested it themselves and it works, skip this. Fix until PASS (two-attempt rule applies). Say honestly what was
not verified (two-player replication, real mouse drags, long timed runs).

## 5. Review (large features only)
Check the diff yourself against the spec and the CLAUDE.md review checklist (server never trusts client values, new
remotes type-check inputs, async callbacks re-check state, script names unique). Small and medium features: the inline check is enough. Large features: run the `fia-reviewer` subagent (read-only, haiku, low effort) on the diff first. If the change touches combat, inventory, death or saved data (or the reviewer finds something serious), recommend `/code-review high` and wait: **never run `/code-review` without his explicit permission.**
Apply only findings that affect correctness or the stated requirements.

## 6. Ship automatically, then report
Run `/fia-ship` (it is model-invocable now), which does:
version `3.N.0` for a feature, `3.N.M` for a fix or small follow-up (check `git log -1`), `python tools/gen_project.py
--check`, `git add -A`, commit, `git push origin main`. Then the vault: append the session entry (do NOT read the whole
the month log `8 - Claude/agents/game-dev-log-YYYY-MM.md`, ~30k chars: `obsidian_update_note`, `append`, no heading) and update the touched Registry
rows with `obsidian_replace_text`; the pre-existing wikilink warnings are not new. If the Obsidian MCP is disconnected,
commit and push anyway and say the vault log is pending. A tiny follow-up (a color, a keybind) is one patch commit and
a one-line vault note appended to the same session entry, not a new entry.
Finish with: commit hash and title, what changed, what was verified (evidence) and what was not, generated Studio items (and the
`tools/studio/*.luau` builders saved for them), and the next suggested step. Never ask the user to Ctrl+S: Team Create autosaves.
