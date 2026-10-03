<div align="center">

# ✦ Fractured Islands: Ascension ✦

### A Minecraft-flavoured incremental RPG for Roblox — stand on pads, stack stats, ascend.

![Roblox](https://img.shields.io/badge/ROBLOX-STUDIO-55FFFF?style=for-the-badge&labelColor=0b0b1a)
![Luau](https://img.shields.io/badge/LUAU-NONSTRICT-FFAA00?style=for-the-badge&labelColor=0b0b1a)
![Rojo](https://img.shields.io/badge/ROJO-7.7.0-FF5555?style=for-the-badge&labelColor=0b0b1a)
![Status](https://img.shields.io/badge/STATUS-IN_DEVELOPMENT-55FF55?style=for-the-badge&labelColor=0b0b1a)

**🟦 [Tooling](#-tooling-and-workflow)**  ·  **🟩 [Systems](#-systems)**  ·  **🟪 [Project structure](#%EF%B8%8F-project-structure)**  ·  **🟨 [Run it locally](#-run-it-locally)**

</div>

---

## ✧ What is this?

**Fractured Islands: Ascension** (FIA) is a solo-built Roblox game that blends the deep skill-and-stat ecosystem of **Hypixel SkyBlock** with the satisfying exponential loop of an idle/incremental. You start on a floating island with a trickle of Bronze Coins, step on pads to convert one resource into the next, and climb a web of statistics whose owned amounts multiply each other.

> [!NOTE]
> FIA is in active development. The core loop, menus, items and statistics are playable; combat, crafting and more world content are still being built.

### The loop

```
passive Bronze income ─► stand on a pad (auto-buys every 0.2 s) ─► server validates, deducts, pays
        ▲                                                                   │
        └──── owned stats boost the stats below them (multiplier chain) ◄───┘
```

Every statistic you own multiplies the stats it rewards, so progress is always **visible**, **satisfying** and **multi-layered**.

---

## 🎮 Systems

| | System | What it does |
|:-:|:--|:--|
| 🪙 | **Statistics** | 75 statistics across 6 skills (Farming, Foraging, Fishing, Mining, Combat, General). Costs, rewards and multipliers are plain data in `StatisticsConfig`. Menu is read-only: stats are earned from world buttons or passively. |
| 🔘 | **World buttons** | Pads defined in `ButtonConfig` (`Button.{Key}.{Tier}` models). Server-authoritative auto-buy, sparkle FX, floating `+gain`, purchase log popups. |
| 🧭 | **Ascension menu** | One centralized menu: Profile, Skills, Statistics, Collections, Settings. A pooled double-buffer grid keeps rapid navigation smooth and leak-free. |
| 🛡️ | **Items & equipment** | Modular item definitions (24 items): rarities, 4 armor + 4 accessory slots, server-authoritative equip/unequip/swap, stats applied as attribute sources. |
| 📊 | **Attributes** | 30+ attributes from one config. Profile → skill attributes → per-attribute source breakdown (base, equipment, admin, more to come). |
| 💬 | **Tooltips** | One data-driven tooltip with collapsible sections (hold **SHIFT**), centered pixel font and Minecraft colour codes (`&a`, `&6` …). |
| 💾 | **Persistence** | ProfileService stores for skills/inventory, statistics and attributes. Reconcile backfills new fields, so saves survive updates. |
| 🌫️ | **World** | Floating starter island, cloud system, zone detection scaffolding. |
| ⚔️ | **Combat** | Weapon registry and ability scaffolding (not the current focus). |
| 🛠️ | **Admin tools** | Slash commands for testing: `/give /item /set /add /reset /stats /equip /unequip /items /clear /cap /help`. |

### Currency chain

`Bronze → Silver → Gold → Platinum → Diamond → Emerald → Obsidian → Crystallized → Exotic → Celestial → Void`

Each coin tier is bought with the one below it, and owning higher tiers multiplies the tiers beneath.

---

## 🎨 Design language

**Look & feel**
- Minecraft colour-code palette on dark glass
- Pixel font (Silkscreen) for dynamic text
- Liquid-glass menu panels
- `Quint`/`Out` tweens, 0.3–0.5 s
- Item and statistic icons from Minecraft item sprites

**The palette**

| Token | Colour |
| :-- | :-- |
| `aqua` | ![#55FFFF](https://img.shields.io/badge/-55FFFF-55FFFF?style=flat-square) |
| `green` | ![#55FF55](https://img.shields.io/badge/-55FF55-55FF55?style=flat-square) |
| `yellow` | ![#FFFF55](https://img.shields.io/badge/-FFFF55-FFFF55?style=flat-square) |
| `gold` | ![#FFAA00](https://img.shields.io/badge/-FFAA00-FFAA00?style=flat-square) |
| `red` | ![#FF5555](https://img.shields.io/badge/-FF5555-FF5555?style=flat-square) |
| `light-purple` | ![#FF55FF](https://img.shields.io/badge/-FF55FF-FF55FF?style=flat-square) |
| `gray` | ![#AAAAAA](https://img.shields.io/badge/-AAAAAA-AAAAAA?style=flat-square) |

---

## 🧱 Tech stack

| Layer | Tools |
| :-- | :-- |
| **Engine / language** | Roblox Studio, Luau (non-strict) |
| **Editing** | VS Code + [Rojo](https://rojo.space) 7.7 (`src/` → Studio, one-way) |
| **Persistence** | [ProfileService](https://madstudioroblox.github.io/ProfileService/) |
| **Lint** | Selene (`selene.toml`), `.luaurc` |
| **AI-assisted workflow** | Claude Code + Roblox Studio MCP + an Obsidian vault as memory |

**Architecture rules**
- Server-authoritative: clients render, servers decide.
- Final stat formula: `Final = (Base + Flat) × (1 + ΣMultipliers)`.
- GUI lives in the Studio place; scripts reach it by name with `WaitForChild`.

---

## 🧭 Tooling and workflow

1. **Spec** the feature (design notes live in the vault).
2. **Commit to `main`** — no feature branches or PRs; commits titled `3.xx.x - description`.
3. **Implement** in `src/`; Rojo syncs to Studio.
4. **Verify** in Studio: wait for sync → play → check console → drive the UI → screenshot.
5. **Commit and log** — update the systems registry and session log.

---

## 🚀 Run it locally

```bash
git clone https://github.com/FreezingShock/FracturedIslandsAscension.git
cd FracturedIslandsAscension
rojo serve            # then press Connect in the Rojo plugin inside Studio
```

| Command | Does |
| :-- | :-- |
| `rojo serve` | Live-sync `src/` into the open Studio place |
| `python tools/gen_project.py` | Regenerate `default.project.json` after adding, moving or removing a script |
| `python tools/gen_project.py --check` | Fail if `default.project.json` is out of date |
| `rojo sourcemap default.project.json -o sourcemap.json` | Refresh the sourcemap used by Luau tooling |

> [!IMPORTANT]
> Scripts are organised into **system folders on disk** but appear **flat in Studio** (`ReplicatedStorage.Modules.X`, `ServerScriptService.X`), because the game finds modules by name. `tools/gen_project.py` maps every script individually to make that work. After moving or adding files, run it and restart `rojo serve`.

The GUI (ScreenGuis, templates) is **not** in Rojo — it lives in the place file, so save the place (Ctrl+S) after UI changes.

---

## 🗂️ Project structure

```
├── src/
│   ├── Server/        # → ServerScriptService
│   │   ├── Data/          # ProfileService, skills, inventory, attributes, statistics
│   │   ├── Inventory/     # item tools, equipment service
│   │   ├── Buttons/       # world-button purchase loop
│   │   ├── Combat/ World/ Chat/ Admin/
│   │   └── Main.server.lua
│   ├── Shared/Modules/    # → ReplicatedStorage.Modules
│   │   ├── Menu/          # grid engine, bridge, TooltipModule/, LiquidGlassHandler/, Pages/
│   │   ├── Inventory/     # Items/ definitions, registries, equipment controller, slot FX
│   │   ├── Stats/         # Attributes, Sources, Profile/Statistics/Collections configs, stat log
│   │   ├── Buttons/       # ButtonConfig, ButtonFX, ButtonRegistry
│   │   ├── Config/        # chat, cloud and zone configs
│   │   └── Combat/ World/ Chat/ Admin/ Util/
│   └── Client/        # → StarterPlayerScripts
│       ├── Menu/ Inventory/ Buttons/ HUD/ Combat/ World/ Chat/ Admin/
├── tools/             # gen_project.py — regenerates default.project.json
├── docs/archive/      # retired notes
├── assets/blender/    # Blender source files
├── legacy/            # backups of replaced modules
├── default.project.json   # generated — do not edit by hand
└── CLAUDE.md          # instructions for Claude Code in this repo
```

---

<div align="center">

**Built by [Nate](https://github.com/FreezingShock)**  ·  [nateanderson.dev](https://nateanderson.dev/)

✦ made with too much rainbow ✦

</div>
