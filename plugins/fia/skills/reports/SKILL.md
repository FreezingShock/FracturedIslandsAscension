---
name: reports
description: Import the cloud routines' daily review, weekly summary and ideation reports from the claude/fia-reports branch into the Obsidian vault. Use when he says "check my reports", "what did the routines find", "import reports", or at session start.
---

# reports

The scheduled cloud routines (daily review, weekly summary, ideation) cannot reach the vault. They push markdown to branch `claude/fia-reports` under `reports/{daily,weekly,ideation}/`. This skill brings it home. Obsidian Sync then carries the notes to the other machine.

1. `git fetch origin claude/fia-reports`. Branch missing: say the routines have not run yet and stop. List files with `git ls-tree -r --name-only origin/claude/fia-reports reports/`. Read a file with `git show origin/claude/fia-reports:<path>`. Do not check the branch out and do not merge it into `main`; this skill never pushes.
2. **Find what is new.** A report is imported when the vault note `Claude outputs/FIA reports/<kind>/<filename>` exists (`obsidian_read_note`, small `limit`). MCP down: the vault is a plain folder, check with Glob. Skip imported ones. Cap the first run at the newest 3 per kind.
3. **Import each new report** with `obsidian_save_note` to `Claude outputs/FIA reports/<kind>/<filename>`: keep the report's frontmatter, add `tags: [fia, fia-report, <kind>]` and `source: claude/fia-reports`. Wikilinks never end in `.md`. Create no other vault files.
4. **Weekly reports only:** also append the report's `## Vault import` block verbatim to the current month log `8 - Claude/agents/game-dev-log-YYYY-MM.md` with `obsidian_update_note` (`append`, no heading, never read the log first, newest at the bottom). Do it once per weekly report (skip when step 2 found the note already imported).
5. **Summarize in <= 12 lines:** daily = headline plus Watch-list items (file:line); weekly = TL;DR and the 3 next-week suggestions; ideation = the 4 idea names with sizes, the recommendation, and the latest report's paste-ready `/fia-feature` block verbatim in a fenced code block.
6. Watch-list items are findings from git history alone, not verified in Studio. Do not fix anything unprompted: offer `/fia-feature` for the ones he picks.
7. Never delete the branch or its files; the cloud routines keep appending to it.

If the branch exists but `git fetch` is denied, the repo is private and this machine is not signed in to GitHub: say so.
