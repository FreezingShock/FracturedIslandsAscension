---
name: fia-feature
description: End-to-end pipeline for building a game feature - spec, branch, implement, verify, review, commit. Manual only. Invoke as /fia-feature <short idea>.
disable-model-invocation: true
argument-hint: <feature idea>
---

# /fia-feature $ARGUMENTS

Run these phases in order. Keep each phase's output short. If scope is a one-sentence diff, skip phases 1-2.

## 1. Spec (skip if /fia-ideate already produced one)
- Read only what is needed: the registry rows for the touched systems (`Grep` the vault note
  `8 - Claude/projects/fractured-islands.md`, do not read it whole) and the files you will edit.
- Use `AskUserQuestion` for decisions that are the user's (design, naming, balance). Max 4 questions, offer a
  recommended option. Do not ask what the code answers.
- Write a spec of 6-10 lines: goal, files touched, config shape, **out of scope**, and an explicit
  **verification step** (what `/fia-verify` must observe). Save it to the vault via `/obsidian-decide` or
  append to the feature note; do not create new vault files unless the user asks.

## 2. Branch
`git checkout -b feature/<kebab-name>` from the current branch (never commit to `main`).

## 3. Implement
- Follow the repo's conventions (see CLAUDE.md): tabs, config-driven data, server-authoritative, GUI by name.
- Prefer extending existing config tables (items, stat chains, attributes) over new code.
- New or moved script: the `post_edit` hook regenerates `default.project.json`; if it says so, ask the user to
  restart `rojo serve` and press Connect before verifying.
- Use `Grep`/partial `Read`. Delegate wide exploration to the `lua-explorer` subagent.

## 4. Verify
Run `/fia-verify`. Fix until PASS (two-attempt rule applies).

## 5. Review
Run the `fia-reviewer` subagent on the diff against the spec. Apply only findings that affect correctness
or the stated requirements; ignore style.

## 6. Commit
Run `/fia-ship` (commit, vault log, push). Finish by telling the user: what changed, what was verified (with
the evidence line), anything Studio-only they must save (Ctrl+S), and the next suggested step.
