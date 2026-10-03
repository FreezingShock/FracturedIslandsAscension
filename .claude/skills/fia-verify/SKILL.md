---
name: fia-verify
description: Playtest-verify a change in Roblox Studio with minimal tokens. Syncs, plays, returns ONLY deduped errors and pass/fail checks (never the full console). Use after any change to src/ or menu behavior, before committing, or when asked to test/verify/playtest.
---

# /fia-verify - closed-loop playtest (token-lean)

Goal: prove the change works and return **a short pass/fail report with evidence**. Never call
`get_console_output` (it dumps the whole log). Read errors with `LogService:GetLogHistory()` instead.

Run this **inline** in the main conversation: the error filter already keeps results tiny, so a subagent would cost more than it saves.

## Steps
1. **Studio id:** `list_roblox_studios` once, reuse the id.
2. **Static checks (no Studio):** `python tools/gen_project.py --check` and `rojo build default.project.json -o <temp>.rbxlx`
   (use a temp path on Linux/macOS). Stop and fix if either fails.
3. **Sync check (Edit datamodel, `execute_luau`):** script counts must equal
   `python tools/gen_project.py --counts`. If Modules is 0 or a count is doubled, the Rojo plugin is
   disconnected or stale folders exist: tell the user to press Connect, do not continue.
   ```lua
   local function n(i) local c=0 for _,d in ipairs(i:GetDescendants()) do if d:IsA("LuaSourceContainer") then c+=1 end end return c end
   return ("Modules=%d ServerScriptService=%d StarterPlayerScripts=%d"):format(n(game.ReplicatedStorage.Modules), n(game.ServerScriptService), n(game.StarterPlayer.StarterPlayerScripts))
   ```
4. **Play:** `start_stop_play(true)`, wait ~8 s (Rojo sync lag means an earlier play runs OLD code).
5. **Errors only (run once on `Server`, once on `Client`):**
   ```lua
   local noise = { "Lucide Icon Picker", "Yellow flower", "underwaterplant", "LoadUnownedAsset", "Infinite yield possible on 'ReplicatedStorage:WaitForChild(\"Config\")'", "tagged ClickableButton", "value of type Color3 cannot be converted to a number", "Requested module experienced an error while loading" }
   local seen, out = {}, {}
   for _, m in ipairs(game:GetService("LogService"):GetLogHistory()) do
     if m.messageType == Enum.MessageType.MessageError or m.messageType == Enum.MessageType.MessageWarning then
       local skip = false
       for _, p in ipairs(noise) do if m.message:find(p, 1, true) then skip = true break end end
       local key = m.message:sub(1, 140)
       if not skip and not seen[key] then seen[key] = true; table.insert(out, key) end
     end
   end
   return #out == 0 and "no new errors" or table.concat(out, "\n")
   ```
   The `noise` list is KNOWN pre-existing issues. When one is fixed, remove it; when a new harmless one
   appears, add it here (edit this file) rather than re-reading it every time.
6. **Feature checks (client):** open the menu (`user_keyboard_input` key `C`), drive the feature with
   `user_mouse_input` using `instance_path`s, then assert with **text/numbers** (`execute_luau` returning a label's
   `Text`, an attribute, an instance count), not images. Pooled-grid buffers are `...Menu.GridBufferA/B`.
7. **Screenshot only when the change is visual,** one `screen_capture`, and look at it yourself.
8. **Stop play** (`start_stop_play(false)`).

## Standing regressions (run when menu/grid code changed)
- Open each Statistics page, press Back quickly 3x: grid must not be blank.
- PlayerGui descendant count before vs after the cycle must match (leak check):
  `#game.Players.LocalPlayer.PlayerGui:GetDescendants()`.

## Report format (and nothing more)
```
VERIFY: PASS|FAIL
static: ok | <error>
sync: Modules=48 SSS=17 SPS=11 (expected same)
errors: none | <deduped lines>
checks: <one line per feature assertion with the observed value>
```
On FAIL: diagnose, fix, re-run only the failing step. After two failed fixes for the same symptom,
stop and ask the user (do not pile attempts into context).
