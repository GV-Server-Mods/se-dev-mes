# se-dev-mes: Space Engineers MES & RivalAI Developer Skill & Tooling Suite

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Space Engineers](https://img.shields.io/badge/Space%20Engineers-v1-blue.svg)](https://www.spaceengineersgame.com/)
[![Modular Encounters Systems](https://img.shields.io/badge/MES-v2.x-orange.svg)](https://steamcommunity.com/sharedfiles/filedetails/?id=1521905890)

A comprehensive, production-grade developer skill, reference library, and automated diagnostics suite for modding **Modular Encounters Systems (MES)** and **RivalAI** in Space Engineers.

Equips AI coding assistants (Antigravity, Claude Code, Cursor, Cline) and encounter modders with source-verified engine constraints, syntax rules, pitfall detection, safe XML tooling, and automated scaffolding.

---

## Background & Development

This skill was created by **Mike Dude**, born out of years of real-world server operation, encounter design, and combat balancing on the **GV: Deserts of Kharak (GVK)** rover-PvPvE server.

To ensure complete accuracy and eliminate the guesswork that often plagues Space Engineers modding, it was developed in close pair-programming collaboration with **Google DeepMind's Gemini (Antigravity)**. Every tag, master gate, parsing behavior, and execution pathway was systematically audited and cross-referenced directly against the local **Modular Encounters Systems (MES)** and **RivalAI** C# source code.

---

## What `se-dev-mes` Gives You

1. **Code-Verified Accuracy, Not Guesswork**:
   - Online wikis and guides can be outdated, incomplete, or describe legacy workarounds. Nothing takes precedence over the MES C# codebase itself.
   - Every rule is classified as **`[HARD]`** (code-verified against local C# source and Keen binaries) or **`[SOFT]`** (field-tested operational heuristic), so you always know how much to trust it.
   - Known engine bugs are documented down to the exact source line (e.g. `TriggerChecks.cs:77` `CargoShipWaypoints` out-of-bounds crash).
2. **Automated Staleness Detection**:
   - `check_mes_sync.py` compares the skill's offline tag cache against your local MES install, so you know right away if the skill's knowledge has drifted from the version you're actually running.
3. **Token Optimization & Progressive Disclosure for AI Agents**:
   - Lean root `SKILL.md` keeps AI agent token usage minimal while providing high-density mental models.
   - 9 dedicated reference documents in `references/` are loaded on-demand only when relevant.
4. **Safe XML Tooling (Eliminating Deserializer Crashes)**:
   - Standard XML comments (`<!-- ... -->`) inside `<Description>` tags crash Keen's deserializer: `ReadElementString()` throws `System.Xml.XmlException`, causing the game to skip loading the mod entirely (`MOD_CRITICAL_ERROR`).
   - `Format-MesSbc.ps1` and `Add-MesProfileSnippet.ps1` protect `<Description>` tags and auto-convert comments to RivalAI's `[//Comment]` syntax.
5. **Real-World Production Architectures**:
   - Incorporates real-world patterns from Enenra's `mes-shared-behaviors` (Role vs. CombatType state machines), `GFA - MES Utilities` (courier logistics networks), Mike Dude's `GVK_Derelicts` (planetary convoys & store automation), and `Trade Operators Coalition` (safezone stations).
6. **9 Production Scaffolding Patterns**:
   - `New-MesProfile.ps1` generates full boilerplate encounters, from defended wrecks and convoy escorts to boss encounters, combat drones, and reinforcement networks.
7. **Automated Auditing for Silent-Failure Bugs**:
   - Catches missing master gates, mismatched tag-list counts, dangling profile references, and deserializer traps before they ship to your server - the kind of bugs MES fails on silently, with no error logged.

---

## Repository Structure

```
se-dev-mes/
├── SKILL.md                                # Root AI skill definition (lean, progressive disclosure)
├── README.md                               # Project documentation
├── references/                             # Deep-dive reference library (on-demand loading)
│   ├── profiles_and_tags.md                # 30+ profile types, registration phases, tag types
│   ├── spawning_and_conditions.md          # Spawners, environment gates, threat scoring
│   ├── behaviors_and_autopilot.md          # 11 behavior subclasses, Role vs. CombatType, autopilot
│   ├── aircraft_behaviors_and_tuning.md    # Attack runs, profile-swap triggers, fixed-gun gates, WC shoot mode, hover fighters
│   ├── manipulation_and_dereliction.md     # Block replacement, weapon randomizer, dereliction
│   ├── events_and_zones.md                 # MES Events vs Triggers, master gates, zero-stripping
│   ├── economy_and_stores.md               # 3-part store grid sales, 124m clearance, store refresh
│   ├── third_party_integrations.md         # WeaponCore (800m clamp), Shields, AiEnabled, Water Mod
│   ├── diagnostics_and_troubleshooting.md  # Admin commands, error signatures, sim-speed, anti-clang
│   └── sbc_xml_editing_guide.md            # IDE setup (*.sbc -> xml), <Description> rules, formatting
├── examples/                               # Production-tested workshop implementations
│   ├── role_combattype_state_machine.sbc   # Enenra MSB Role + CombatType state machine
│   ├── courier_logistics_network.sbc       # Enenra GFA parent-child courier logistics network
│   ├── planetary_convoy_escort.sbc         # Mike Dude GVK convoy with event-based spawning & escorts
│   ├── automated_economy_store.sbc         # Mike Dude GVK automated store inventory refresh loop
│   └── merchant_safezone_station.sbc       # TOC safezone station ([CreateSafeZone:true]) + merchant
└── scripts/                                # Automation, diagnostics, and scaffolding suite
    ├── mes_tag_cache.json                  # Offline database of 1,847 tags across 41 profile types + trigger Type values
    ├── query_mes_tags.py                   # Tag inspector CLI (search local MES source or cache)
    ├── audit_unknown_tags.py               # Finds tags MES silently ignores and values its parsers reject (e.g. true on a Yes/No tag)
    ├── wc_shootmode.py                     # List/set/audit the WeaponCore shoot mode in prefabs; classify turrets, fixed guns and flares
    ├── PB_TurnTest.cs                      # Programmable Block script: flight-path turn vs nose turn
    ├── check_mes_sync.py                   # Automated staleness & version drift detector
    ├── Update-MesSkill.ps1                 # Maintainer-only: 1-step release updater (rebuilds cache, runs tests, syncs global)
    ├── Format-MesSbc.ps1                   # Safe XML formatter protecting <Description> & comments
    ├── Add-MesProfileSnippet.ps1           # Safe profile snippet injector for SBC files
    ├── audit_sbc.ps1                       # SBC XML deserialization auditor
    ├── audit_mes_tags.ps1                  # Semantic tag linter (master gates, zero-stripping)
    ├── audit_mes_references.ps1            # Cross-file reference validator (-SkipPrefabs support)
    └── New-MesProfile.ps1                  # Boilerplate generator (9 encounter patterns)
```

---

## Installation

### 1. Antigravity / Gemini CLI
Clone directly into your global skills directory:
```bash
git clone https://github.com/GV-Server-Mods/se-dev-mes.git ~/.gemini/config/skills/se-dev-mes
```

### 2. Claude Code
Clone directly into your Claude skills directory:
```bash
git clone https://github.com/GV-Server-Mods/se-dev-mes.git ~/.claude/skills/se-dev-mes
```

### 3. Per-Project / Workspace (Cursor, Cline, VS Code)
Clone into your workspace's `.skills/` directory:
```bash
git clone https://github.com/GV-Server-Mods/se-dev-mes.git .skills/se-dev-mes
```

---

## Tooling & Automation Guide

All scripts reside in the `scripts/` directory:

### 1. Tag Inspector CLI (`query_mes_tags.py`)
Queries tag definitions, data types, and parent profiles from the local MES C# source code or offline cache:
```bash
# Query any tag containing 'Zone'
python scripts/query_mes_tags.py --tag Zone

# Search specifically within RivalAI Action profiles
python scripts/query_mes_tags.py --profile "RivalAI Action" --tag Spawner

# Output structured JSON
python scripts/query_mes_tags.py --tag Weapon --json
```

### 2. Staleness & Version Drift Detector (`check_mes_sync.py`)
Compares the offline tag cache against the local MES source code to detect updates:
```bash
python scripts/check_mes_sync.py
```

### 3. Safe XML Formatter (`Format-MesSbc.ps1`)
Formats XML while protecting `<Description>` tags from illegal line-wrapping and converting `<!-- -->` comments into `[//]`:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/Format-MesSbc.ps1 -Path ".\Content\Data"
```

### 4. Profile Snippet Injector (`Add-MesProfileSnippet.ps1`)
Safely injects new `EntityComponent` profiles into existing `.sbc` files without regex corruption:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/Add-MesProfileSnippet.ps1 -TargetFile ".\Data\Triggers.sbc" -SnippetFile ".\snippets\action.xml"
```

### 5. SBC XML Deserialization Auditor (`audit_sbc.ps1`)
Checks all `.sbc` files for fatal Keen deserializer traps:
- Duplicate `<SubtypeId>` within `<Id>` blocks.
- Duplicate `<Id>` attributes inside `<Prefab>`.
- XML comments inside `<Description>` tags.
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_sbc.ps1 -Path ".\Content\Data"
```

### 6. MES Tag & Master-Gate Linter (`audit_mes_tags.ps1`)
Detects runtime pitfalls:
- Zero-stripping bug in `CustomCountersTargets` / `CustomSandboxCountersTargets`.
- Fatal `WaypointNear` / `WaypointFar` index crashes.
- RivalAI zone custom bool/counter actions: missing gates, misaligned lists, and `[KnownPlayerAreaTimer:]` <= 0 (no KPL created).
- Omission of required boolean master gates (`[ChangeCounters:true]`, `[SpawnEncounter:true]`).
- Tag list count mismatches (`SetCounters` vs `SetCountersAmount`).
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_mes_tags.ps1 -Path ".\Content\Data"
```

### 7. Cross-Reference Validator (`audit_mes_references.ps1`)
Validates that every referenced trigger, action, condition, spawner, spawn group, and prefab exists across the mod files, and that every `[ZoneName:]`/`[ZoneNames:]` matches a zone's `[PublicName:]`:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/audit_mes_references.ps1 -Path ".\Content\Data" -WarnOrphans -SkipPrefabs
```

### 8. Prefab & Binary Cache Auditor (`audit_prefabs.ps1`)
Audits `Data/Prefabs/*.sbc` for silent spawn failure modes:
- **SubtypeId vs. File Name Mismatch**: Warns if the internal `<Prefab><Id><SubtypeId>` diverges from the file name (SpawnGroups match by internal SubtypeId, not file name).
- **Stale `.sbcB5` Binary Caches**: Detects cached binary files that override XML edits. Pass `-CleanStaleB5` to automatically purge them.
- **Remote Control Block Check**: Verifies that prefabs contain an operational Remote Control block required for RivalAI behaviors.
```powershell
# Audit prefabs and purge stale .sbcB5 binary caches
powershell -ExecutionPolicy Bypass -File scripts/audit_prefabs.ps1 -Path ".\Data\Prefabs" -CleanStaleB5
```

### 9. Profile Scaffolding Generator (`New-MesProfile.ps1`)
Generates production-ready `.sbc` files for 9 standard encounter patterns:
```powershell
# 1. Defended Wreck
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern DefendedWreck -ModPrefix MYMOD -Name ScrapWreck -Faction SPRT

# 2. Convoy Leader + Escort
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern ConvoyLeaderEscort -ModPrefix MYMOD -Name CargoFreighter -Faction SPRT

# 3. Dynamic Zone Ladder
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern DynamicZoneLadder -ModPrefix MYMOD -Name ContestedTerritory

# 4. Economy Store Grid
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern StoreGrid -ModPrefix MYMOD -Name OutpostTrader -Faction TRAD

# 5. Dynamic State NPC (Dynamic Behavior Subclass & Autopilot Switching)
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern DynamicStateNpc -ModPrefix MYMOD -Name PatrolDrone -Faction SPRT

# 6. Planetary Installation
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern PlanetaryInstallation -ModPrefix MYMOD -Name OutpostAlpha -Faction SPRT

# 7. Combat Drone (Fighter/Strike)
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern CombatDrone -ModPrefix MYMOD -Name HunterKiller -Faction SPRT

# 8. Reinforcement Network
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern ReinforcementNetwork -ModPrefix MYMOD -Name StrikeNet -Faction SPRT

# 9. Boss Encounter (Multi-phase)
powershell -ExecutionPolicy Bypass -File scripts/New-MesProfile.ps1 -Pattern BossEncounter -ModPrefix MYMOD -Name OverlordCarrier -Faction SPRT
```

---

## Known MES & SE Engine Pitfalls Documented in Skill

- **Zero-Stripping Bug**: `TagParse.cs` strips `0` values from integer lists unless called with `preserveZero: true`. Using `[CustomCountersTargets:0]` produces an empty list and breaks conditions.
- **Turret 800m Clamp**: On spawn, MES clamps all automated weapon ranges to 800m unless an action executes `[SetWeaponsToMaxRange:true]`.
- **Zone names**: `[ZoneName:]` / `[ZoneNames:]` match a zone's `[PublicName:]`, never its `[Name:]`; zone change types are `Set/Add/Subtract/Multiply/Divide` (`Increase`/`Decrease` silently fail).
- **`WaypointNear` / `WaypointFar`**: Unchecked index on `CargoShipWaypoints[0]` crashes the trigger loop if waypoints are empty.
- **`InsideZone` vs `InsideActiveZone`**: `[Type:InsideZone]` evaluates `true` even when the target zone is deactivated.
- **Economy Store Grids**: Purchased grids only spawn if registered under a `<FactionType>` with subtype `Builder` in `FactionTypes_Economy.sbc`.

---

## Recommended Tooling & Space Engineers AI Skills Ecosystem

When developing Space Engineers mods, encounter packs, and plugins, no single skill covers every domain. We recommend pairing **`se-dev-mes`** with the following companion skills and tools:

### 1. C# Modding, Decompiled Code & Plugins: Viktor Ferenczi's CometWorks Skills
For C# ModAPI scripting, reading decompiled Space Engineers source code, or writing Torch/Pulsar plugins, install **[Viktor Ferenczi's CometWorks Skills](https://github.com/CometWorks/skills)**:
- **`se-dev-game-code`**: Enables AI agents to search Keen Software House's decompiled client C# codebase—indispensable when investigating vanilla spawning mechanics, grid serialization, or ModAPI interfaces.
- **`se-dev-server-code`**: Decompiled dedicated server C# codebase search.
- **`se-dev-mod`**: ModAPI C# scripting guide and patterns.
- **`se-dev-torch`**: Torch plugin development and server administration.
- **`se-dev-script`**: In-game Programmable Block (PB) script development.

```bash
git clone https://github.com/CometWorks/skills.git ~/.gemini/config/skills/cometworks-skills
```

### 2. C# Script Modding & PB Development: MDK2 (Malware's Development Kit 2)
For writing and compiling C# script mods and PB scripts in an IDE (Visual Studio / Rider), use **[MDK2 (Malware's Development Kit 2)](https://github.com/malware-dev/MDK-SE)**:
- Full IDE IntelliSense and syntax highlighting against the latest Space Engineers binaries.
- Automated script minification, packing, and deployment into your local Space Engineers mods folder.
- Type-checking and static analysis preventing illegal namespace usage in PB scripts.

### 3. 3D Assets, Models & Non-MES Frameworks: Godimas101's Skills
For non-MES domains such as 3D modeling, audio, and LCD scripting, reference select modules from **[Godimas101's se-claude-skill](https://github.com/Godimas101/se-claude-skill)**:
- **`se-assets`**: Guide for 3D modeling (`.mwm`), Havok collision models, and audio conversions (`.xwm`)—ideal when designing custom hulls or blocks for your MES prefabs.
- **`se-tss`**: Guide for TextSurfaceScripts (drawing custom UI on LCD screens via ModAPI).
- **`se-frameworks` (non-MES)**: Reference guides for *Animation Engine*, *Mod Adjuster*, *Scope Framework*, and *Tank Tracks*.

---

## Versioning & Release Policy

This project strictly adheres to **Semantic Versioning (`MAJOR.MINOR.PATCH`)**. For full details on when releases qualify for Patch, Minor, or Major bumps, see [VERSIONING.md](VERSIONING.md).

If you're maintaining your own fork or cutting a release, `scripts/Update-MesSkill.ps1` runs the full pre-flight workflow (rebuilds the tag cache, runs the audit suite against `examples/`, and syncs the repo to your global skill directory) - see `VERSIONING.md` for the full release checklist. It's not something you need to run as a skill user.

---

## Contributing

Contributions, bug reports, and newly discovered engine quirks are welcome! Please open an issue or pull request.

---

## License

This project is licensed under the [MIT License](LICENSE).
