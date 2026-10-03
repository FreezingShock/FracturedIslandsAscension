---
name: fia-skill
description: Create, change, or retire a skill, hook, subagent, permission, or standing rule for this project. Use when the user has a new workflow idea, wants a new restriction ("always/never do X"), says "make a skill for...", or a repeated task should be automated.
argument-hint: <workflow idea or restriction>
---

# /fia-skill $ARGUMENTS

Turn an idea or restriction into the **right kind** of automation, in the repo (so it syncs everywhere), validated and committed.

## 1. Pick the mechanism (do not default to a skill)
| The user wants... | Use | Where |
|---|---|---|
| "Always/never do X, no exceptions" (must happen) | **Hook** (deterministic) | `.claude/hooks/*.py` + `.claude/settings.json` |
| A repeatable multi-step workflow | **Skill** | `.claude/skills/<name>/SKILL.md` |
| Heavy/noisy work whose details shouldn't fill the chat (testing, wide search, review) | **Subagent** | `.claude/agents/<name>.md` |
| A preference/convention Claude should usually follow | **One line in CLAUDE.md** | `CLAUDE.md` (keep it short) |
| Stop being asked / block a dangerous command | **Permission rule** | `.claude/settings.json` allow/deny |
| Knowledge only needed sometimes (formats, recipes) | **Skill with references** | `.claude/skills/<name>/references/` |
Rule of thumb: if removing it wouldn't change behavior, don't add it. Prefer hook over CLAUDE.md for hard rules.

## 2. Interview (<=4 questions, only what you cannot infer)
Trigger (when should it run?), inputs, what "done" looks like, side effects (should it be manual-only?),
what it must never do. If it is a restriction, ask the exception cases.

## 3. Build
- Skill: copy `.claude/templates/skill-template.md`. `name` = folder name (kebab-case, prefix `fia-` for game-specific).
  `description` = WHAT + WHEN to use (this is what triggers it; keep <=300 chars, concrete trigger phrases).
  Body: numbered steps, token-lean (use Grep/partial reads, return short reports). Side effects ->
  `disable-model-invocation: true`. Put long reference material in `references/` and link it.
- Hook: small stdlib-only Python (cross-platform), read JSON from stdin, exit 2 + stderr to block, silent
  on success (every printed line costs tokens). Register in `.claude/settings.json`. Test it by piping sample JSON.
- Subagent: `name`, `description`, `tools` (omit to inherit MCP tools), `model` (haiku for search/verify,
  sonnet for review/design). Only if it saves main-context tokens.
- Allowlist: add the narrowest pattern (e.g. `Bash(python tools/*)`), never blanket `Bash(*)`.

## 4. Validate and ship
1. `python tools/check_skills.py` must pass (frontmatter, name matches folder, description length).
2. Dry-run the new thing once (pipe sample hook input / run the skill on a tiny case).
3. Commit as `3.xx.x - skill: <name>` on a feature branch; mention how to invoke it.
4. If it is useful outside this repo: `python tools/install_skills.py` copies skills to `~/.claude/skills`
   (all projects); `python tools/package_skills.py` makes zips for claude.ai upload.
5. Record durable rules in the vault memory (capture every correction) if the user stated a preference.

## Retiring / changing
Edit in place; delete obsolete skills rather than leaving them (stale skills waste tokens in the skill list).
