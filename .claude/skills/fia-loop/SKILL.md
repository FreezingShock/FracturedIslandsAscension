---
name: fia-loop
description: Unattended maintenance loop for FIA and its memory vault. Runs static checks, refreshes stale vault cards, scans recent code for review-checklist issues, writes one idea note, and logs everything to the vault. Use only from the scheduled routine or when Nate says "run the loop".
---

# /fia-loop

You are an unattended agent. Nobody is watching and nobody can answer questions. Follow these steps in order. Do not skip steps. Do not add steps.

Two repos, both on `main`:
- **GAME** = the current working directory (`FracturedIslandsAscension`).
- **VAULT** = `$FIA_VAULT_PATH`, or `/home/user/fracturedislandsvault` if unset (`FreezingShock/FracturedIslandsVault`). This is the persistent memory. Everything the loop learns is written here.

## Hard rules
1. Commit and push to `main` only. Never create a branch or a pull request.
2. Never force-push, rewrite history, or delete files. To undo, use `git revert`.
3. Never edit `src/` in this loop. Static checks cannot verify Roblox changes, so game code waits for a human. Ideas go to the vault.
4. Never edit `CLAUDE.md`, `README.md`, `default.project.json`, `.claude/`, `plugins/`, or `tools/` except via the allowed fixes in P1. Put proposals in the vault instead.
5. In VAULT, only write to: `systems/`, `weapons/`, `ui/`, `blender/`, `roblox-studio/`, `gotchas/`, `decisions/`, `ideas/`, `sessions/`, `loop/`, and `Index.md`. Never read or write any other vault folder.
6. Never put tokens, passwords, emails, or account details into any file.
7. Max 3 GAME commits and max 10 VAULT commits per run.
8. If something is unclear, write it as an open question in the run log. Do not guess.

## Step 0: setup
1. GAME: `git fetch origin && git checkout main && git pull --ff-only origin main`. If this fails, stop.
2. If VAULT is missing, run `git clone https://github.com/FreezingShock/FracturedIslandsVault VAULT`. If the clone fails, set `VAULT_OK=false`. Skip every vault step and do the game-only parts (P1 and P4), then log why.
3. VAULT (if OK): `git pull --ff-only origin main`.
4. Read the last line of `VAULT/loop/scores.jsonl` if it exists. Note its `score`.
5. Baseline: `python3 tools/loop/checks.py --vault VAULT`. Record `before_fail` and `before_skip`.

## Passes
Run P1 to P5 in order. Never run more than 8 passes. Stop early if there's nothing left to do.

**P1. Fix failing checks.**
- `gen_project` fails: run `python3 tools/gen_project.py`, then re-check.
- `check_skills` fails: fix the named skill file's frontmatter or name, then re-check.
- `index_links` fails: fix the broken link in `VAULT/Index.md`.
- Any other failure: leave it. Note it in the run log.

**P2. Refresh stale cards** (VAULT_OK and `card_stale` failed). At most 3 per run.
- For each stale card, read the diffs: `git log -p -n 20 <verified_commit>..HEAD -- <code_paths>`.
- Update only the sections the diff changed. Keep the card short. No pasted code.
- Set `verified_commit` to the short hash of GAME `HEAD`.
- Commit in VAULT: `card: refresh <name> to <hash>`.

**P3. Find discrepancies** (VAULT_OK). At most 3 per run.
- Check each `[[link]]` in `Index.md`, and each claim in `North Star.md` ("Current focus", "Planned"), against the repo with `grep` or `ls`.
- If a card says something the code contradicts, fix the card. If the fix is unclear, write a gotcha in `gotchas/`.

**P4. Review scan** (findings go to the vault; no code edits).
- List recently changed source files: `git log --since=7.days --name-only --format= origin/main -- src/ | sort -u`.
- Check each file against this checklist (from CLAUDE.md):
  - a server handler trusts a client value (no type or range check on `OnServerEvent` input);
  - a RemoteEvent handler has no rate limit;
  - a tween `Completed` or async callback changes reused state without a generation or `PlaybackState` check;
  - a GUI object is built with `Instance.new` in a script (the project rule is templates made in Studio);
  - a hardcoded asset id or magic number sits outside `Config` modules;
  - two scripts in one realm share a name.
- Each real finding becomes a gotcha in VAULT (`file:line`, what, why). Only real findings. If there are none, log "none found". No speculation.

**P5. Easy additions and one idea** (VAULT_OK).
- Card: pick one system that has source files in `src/` but no card (check `Index.md`). Write it from `templates/system-card.md`: read the files, then write Purpose, Where it lives, Key functions, Config, Gotchas. Set `code_paths` and `verified_commit`. Add it to `Index.md` and link it from related cards. Commit: `card: add <name>`.
- Idea: write exactly one `VAULT/ideas/<YYYY-MM-DD>-<slug>.md` with these headings: `## Problem`, `## Grounded in` (`[[cards]]` it builds on), `## Smallest version`, `## Files to touch`, `## Verification` (what a desktop playtest must check), `## Risks`. The idea must be supported by a card or a finding. Don't invent systems the design doesn't mention. Commit: `idea: <slug>`.
- Improvements to this loop: if a step here was unclear or a check was skipped that could have run, write a proposal in `VAULT/loop/proposals.md` (append, one line, with the date). Do not edit this file.

## Versions
GAME commit titles follow `3.N.M - description`. Find the latest with `git log --format=%s -n 1 origin/main` and use the next `M`. Loop commits are patch-level.

## Finish
1. Re-run `python3 tools/loop/checks.py --vault VAULT`. Record `after_fail` and `after_pass`.
2. If `after_fail > before_fail`, `git revert` this run's GAME commits before pushing. Never push a state that fails more checks than the baseline.
3. Push GAME: `git push -u origin main`. If rejected, `git pull --rebase origin main`, then push once more. If it fails again, stop and log it.
4. Append a run entry to `VAULT/sessions/loop-log.md` (`append`, no heading):
   ```
   ### Loop run <YYYY-MM-DD HH:MM>
   - Passes: <n> of 8
   - Checks: before <before_fail> fail / <before_skip> skip; after <after_fail> fail
   - Cards: <refreshed or added names, or none>
   - Findings: <n> (gotchas: <names>)
   - Idea: [[ideas/<file>]] or none
   - Proposals: <n>
   - Open questions: <list or none>
   ```
5. Append one JSON line to `VAULT/loop/scores.jsonl`: `{"date", "passes", "before_fail", "after_fail", "skipped", "cards", "findings", "idea", "proposals", "score"}`. Set `score = 2*after_pass - 3*after_fail + cards + findings + (1 if an idea was written)`.
6. VAULT: `git add -A && git commit -m "loop: run <date>" && git push origin main` (same retry as step 3).
7. Final output: 3 lines. Date, checks after (pass/fail/skip), and what changed (cards, idea, proposals).
