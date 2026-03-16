# Fractured Islands: Ascension (FIA)

> A Roblox incremental/progression game blending the deep skill and stat ecosystem of Hypixel SkyBlock with the satisfying exponential loop of idle/incremental mechanics. Players ascend from a nobody gathering basic resources to a stat-stacked demigod with specialized skill trees, rare gear multipliers, and a character sheet that tells the story of hundreds of hours of play.

---

## Description

Fractured Islands: Ascension is a **passive, Minecraft-themed incremental game** built in Roblox Studio, authored entirely by a solo developer. Resources generate automatically, skills level through accumulation and XP gain — no clicking required.

### Core Fantasy
Progress must always be **visible**, **satisfying**, and **multi-layered**. Every system is designed so the player can see exactly how far they've come and how far they have left to go.

### Design Pillars
- **Six Skills** — Farming, Foraging, Fishing, Mining, Combat, Carpentry — each with 50 levels and milestone rewards at levels 5, 10, 15, 25, 30, 40, and 50
- **Dual-layer stat formula** — `Final = (Base + Flat) × (1 + ΣMultipliers)` — flat bonuses and percentage multipliers tracked separately and combined
- **Item rarity tiers** — Common → Uncommon → Rare → Epic → Legendary → Mythic
- **Gear slots** — Helmet, Chest, Legs, Boots, Weapon, Tool, Accessories (×5)
- **Skill Tokens (ST)** — milestone rewards spendable cross-skill at 2× cost
- **Carpentry** — economy accelerator providing passive Coins/sec, funding the seventh General Skills tree
- **Aetheric Nexus** — master leveling system (up to 200 levels) fed by skill progression across all six skills
- **Currency chain** — Bronze → Silver → Gold → Platinum → Diamond → Emerald → Obsidian → Crystallized → Exotic → Celestial → Void Coins

### Stats
| Category | Stats |
|---|---|
| Combat | Health, Defense, Strength, Crit Chance, Crit Damage, Speed, Attack Speed |
| Gathering | Farming Fortune, Foraging Fortune, Fishing Speed, Mining Speed, Mining Fortune |
| Economy | Magic Find, Coins/sec |

### Architecture
| Layer | Technology |
|---|---|
| Client UI & Input | `LocalScript` |
| Shared Logic | `ModuleScript` in `ReplicatedStorage.Modules` |
| Server Data & Computation | `ModuleScript` in `ServerScriptService` |
| Client ↔ Server | `RemoteEvent` |
| Data Persistence | `ProfileService` |
| Script Editing | VSCode + Rojo |

All stat computation is server-authoritative. Client never computes final values.

---

## Completed Systems

### UI Framework
- **`CentralizedMenuController`** (LocalScript, `StarterPlayerScripts`) — orchestrates all menus via a `sharedRefs`/`sharedModules` pattern; owns open/close/navigate lifecycle
- **`GridMenuModule`** — config-driven grid registration, tooltip/click wiring, stack-based navigation with crossfade transitions; `fadeInGrid` / `fadeOutGrid` using `CanvasGroup.GroupTransparency`
- **Sidebar** — spam-safe tween with `Back` easing, blur tween on menu open/close (`Quint`, 0.35s, Size 18)

### Page Modules
- **`SkillsPageModule`** — skill card display, level box hover tooltips, XP progress bars, Roman numeral toggle, skill average display, search filter, scroll-idle shadow system, live XP updates via `SkillUpdated` RemoteEvent
- **`ProfilePageModule`** — player profile display
- **`SettingsPageModule`** — five settings sub-pages (Personal, Communication, Gameplay, Notifications, Controls, Audio)
- **`StatisticsPageModule`** with `StatisticsConfig` — 9-column × 6-row grid; per-skill color theming via `applyStatColor` / `revertStatColor`; `SelectedSkill` slot mirrors source button visual properties

### Tooltip System (`TooltipModule`)
- Cursor-following via `RenderStepped`; source-keyed ownership model prevents clobber between page modules
- Divider visibility logic: `TT_Divider1.Visible = TT_Desc.Visible and TT_Click.Visible`
- `showRaw` path for full manual control (skill cards, level boxes)
- Progress fill tween (`tweenProgressFill`) for XP bar animation

### Navigation
- Return button with hold-to-confirm (0.5s threshold), animated progress bar, cancellable `task.delay` appear guard
- Token-based animation cancellation (`restoreToken`, `pageAnimToken`, `bdAnimToken`)
- `navigateBack()` — handles page depth ≥ 2, page depth = 1 (returns to grid), and grid depth > 0
- Stack-based grid-to-grid traversal via `GridMenuModule`

### Helpers & Patterns
- **Typewriter system** — silent (`typewrite`) and sound (`typewriteSound`) variants; `typewriteSuffix` for label suffix animation; `titlesLocked` race-condition guard
- **`applyGridLayout`** — config-driven blank slot generation from a `BlankSlot` template in `TemporaryMenus`
- **`MoneyLib`** — suffix-based large number formatting (`k`, `M`, `B` … up to `10e123`)

### Collections Grid
- Farming, Foraging, Fishing, Mining, Combat entries registered and wired; back/close navigation functional

### Server
- **`SkillsDataManager`** (ServerScriptService) — ProfileService saving, XP threshold tables, level-up logic, fires `SkillUpdated` to clients

### Tooling
- Rojo + VSCode workflow fully operational
- `.luaurc` (`"languageMode": "nonstrict"`), `selene.toml` (`global_usage = "allow"`, `unused_variable = "allow"`), `sourcemap` configured
- Luau LSP, Selene, StyLua active
- GUI Interface Tools 2 plugin + Material Icons (filled style) for UI construction

---

## Planned / In Progress

Items are listed in rough implementation priority.

| # | System | Notes |
|---|---|---|
| 1 | **Inventory & Equipment Panel** | Gear slots, drag-and-drop, rarity borders, stat diff preview on hover |
| 2 | **Click Handler** | 6 skill-themed button types, combo tracking, crit click logic |
| 3 | **Animated Resource Popups** | Floating `+XP` / `+Gold` text on resource gain |
| 4 | **ItemManager ModuleScript** | Item definitions, drop tables, stat computation |
| 5 | **Milestone Tracker GUI** | Scrollable list per skill, lock/unlock animations, Skill Token rewards |
| 6 | **Aetheric Nexus UI** | Hook into existing `SkillUpdated` events → Nexus XP module → stat multiplier injection → accessory resonance schema → area gating |
| 7 | **General Skills Tree** | Seventh tree, unlocks after any skill hits Level 25 |
| 8 | **Recipe Menu** | Complex — full crafting recipe browser |
| 9 | **Crafting Menu** | Hard — full crafting workflow UI |
| 10 | **"Next Reward at Level X" Preview** | Inline preview in skill tooltips |
| 11 | **Total Cumulative XP Tracking** | Overflow XP past Level 50 |
| 12 | **Leaderboard Panel** | Per-skill and global leaderboard display |
| 13 | **Reforge Anvil UI** | Item reforge workflow |
| 14 | **Boost Events System** | Time-limited multiplier events |
| 15 | **Pet System** | Required before Mythic Weave node 8 is reachable |
| 16 | **Prestige / Rebirth System** | Design after core loop is fully stable |

---

## Project Structure

```
FracturedIslandsAscension/
├── src/
│   ├── client/                         # StarterPlayerScripts
│   │   └── CentralizedMenuController.client.lua
│   ├── server/                         # ServerScriptService
│   │   └── SkillsDataManager.lua
│   └── Shared/
│       └── Modules/                    # ReplicatedStorage/Modules
│           ├── GridMenuModule.lua
│           ├── TooltipModule.lua
│           ├── SkillsPageModule.lua
│           ├── ProfilePageModule.lua
│           ├── SettingsPageModule.lua
│           ├── StatisticsPageModule.lua
│           └── MoneyLib.lua
├── default.project.json
├── selene.toml
├── .luaurc
└── README.md
```

> **Note:** GUI layout (Frames, Buttons, Labels) is authored in Roblox Studio. Scripts are managed exclusively via Rojo/VSCode. Never edit scripts in Studio while Rojo is syncing — Rojo will overwrite Studio edits.

---

## Git Setup & Workflow

### First-time setup (new machine)

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/fractured-islands-ascension.git
cd fractured-islands-ascension

# Verify Rojo is installed (requires Aftman or manual install)
rojo --version

# Start Rojo sync (run this before opening Studio)
rojo serve default.project.json
```

### Daily workflow

```bash
# Pull latest before starting work
git pull origin main

# Start Rojo sync session
rojo serve default.project.json

# Stage all changes
git add .

# Commit with a descriptive message
git commit -m "feat: add StatisticsPageModule skill color theming"

# Push to remote
git push origin main
```

### Branching (for larger features)

```bash
# Create and switch to a new feature branch
git checkout -b feat/inventory-panel

# Work, commit as normal, then push the branch
git push origin feat/inventory-panel

# Merge back to main when ready
git checkout main
git merge feat/inventory-panel
git push origin main

# Clean up the branch
git branch -d feat/inventory-panel
git push origin --delete feat/inventory-panel
```

### Useful utility commands

```bash
# Check what's changed and unstaged
git status

# View recent commit history (one line per commit)
git log --oneline -20

# Discard all unstaged changes (use with caution)
git checkout -- .

# Undo the last commit but keep the changes staged
git reset --soft HEAD~1

# View the diff of staged changes before committing
git diff --staged

# Tag a stable build milestone
git tag -a v0.1.0 -m "Skills + Statistics UI complete"
git push origin v0.1.0
```

### Recommended `.gitignore`

```gitignore
# Rojo sourcemap (auto-generated, not needed in repo)
sourcemap.json

# Roblox Studio local files
*.rbxl
*.rbxlx

# OS files
.DS_Store
Thumbs.db

# VSCode local settings (keep .vscode/settings.json if shared)
.vscode/launch.json
```

---

## Key Engineering Notes

- **Declaration order is critical in Luau** — `local` variables only exist from their declaration line downward. Functions defined before their dependencies silently capture `nil`.
- **Always use `playerGui`, never `game.StarterGui`** — StarterGui is the template, not the live instance.
- **Wire connections once at startup** — never inside render loops or repeated function calls. Prevents connection stacking.
- **Per-entry tween tracking** — use cancellable per-entry tweens, not global boolean locks, for responsive UI.
- **`GroupTransparency` only works on `CanvasGroup`** — not `Frame`. Use instant visibility swaps or convert to CanvasGroup for fade effects.
- **`ProfileService` must live in `ServerScriptService`** — not `ReplicatedStorage` (security boundary).
- **`WaitForChild` with no timeout blocks indefinitely** — use `FindFirstChild` with diagnostic warn loops for GUI children.

---

## Design References

| Reference | What We Borrow |
|---|---|
| **Hypixel SkyBlock** | Skill trees, dual-layer stat formula, item modifiers, milestone reward structure |
| **Untitled Button Simulator** | Incremental loop, exponential scaling, button upgrade trees |
| **Cookie Clicker** | Passive income structure, prestige loop shape |
