---
name: se-dev-mes
description: >-
  Use this skill when creating, editing, diagnosing, or troubleshooting Space Engineers
  Modular Encounters Systems (MES) and RivalAI encounters, spawn groups, behaviors,
  autopilot profiles, triggers, or SBC XML profiles. Authoritative guide covering MES
  Events vs RivalAI Grid Triggers, 1,861 source-extracted tags, boolean master gates,
  XML deserialization quirks, zero-stripping bugs, spawner setups, sandbox variable persistence,
  economy store grid sales, and verified engine workarounds.
license: MIT
allowed-tools: Read, run_command
---

# SE Dev MES & RivalAI Modding Guide

**Applies to Space Engineers version 1 with Modular Encounters Systems (MES) and RivalAI.** MES/RivalAI architecture, SBC pitfalls, and engineering standards for encounter designers and AI coding agents.

**Claim classification**:
- **[HARD]** = verified in the local MES C# source or enforced by the SE engine. Violations fail deterministically (crash, silent no-op, profile load failure).
- **[SOFT]** = field-tested on a live server, not pinned to a code path. An MES or SE update can invalidate it; re-validate if behavior changes.

---

## 1. Source of Truth & Reference Library

> [!IMPORTANT]
> **The MES C# source is the sole source of truth.** Online wikis and guides are often outdated or wrong. This skill (1,861 tags across 41 profile types, checked against that source) overrides generic MES overviews: never use Godimas101's `se-frameworks/references/mes.md`.

### A. Companion Skills
C# ModAPI, decompiled engine code, Torch and PB scripts: [CometWorks skills](https://github.com/CometWorks/skills) (`se-dev-game-code`, `se-dev-server-code`, `se-dev-mod`, `se-dev-torch`); `.mwm` models and TextSurfaceScripts: [Godimas101's se-claude-skill](https://github.com/Godimas101/se-claude-skill) (`se-assets`, `se-tss`; not its `mes.md`).

### B. Reference Library (Progressive Disclosure)
Detail lives in `references/`; open the file for the topic at hand. Keep this file a lean router: harnesses cap SKILL.md at **5,000 tokens** and silently truncate past it (`Update-MesSkill.ps1` checks).

| Reference Document | Key Topics Covered |
| :--- | :--- |
| [profiles_and_tags.md](references/profiles_and_tags.md) | Catalog of 30+ profile types, Registration Phases 1–5, tag types, token scope/rules, and the string-Tag broadcast system. |
| [spawning_and_conditions.md](references/spawning_and_conditions.md) | Spawners, environment gates, threat scoring, altitude formulas, and event spawners. |
| [behaviors_and_autopilot.md](references/behaviors_and_autopilot.md) | 11 Behavior subclasses, Role vs. CombatType state machines, autopilot profiles, command networks (parent/child, escort filters), `DespawnMES` triggers. |
| [dialogue_and_chat.md](references/dialogue_and_chat.md) | Dialogue banks, the shared bank chat profile, chance rolls, chat tokens and range, target-state trigger patterns for chatter. |
| [aircraft_behaviors_and_tuning.md](references/aircraft_behaviors_and_tuning.md) | Attack-run tuning, profile-swap triggers, fixed-gun gates, WeaponCore shoot mode (why MES fixed guns never fire), hover fighters, tuning method. |
| [manipulation_and_dereliction.md](references/manipulation_and_dereliction.md) | Block replacements, weapon randomizer (`<Public>true</Public>`), dereliction, AiEnabled bots, and ContainerTypes loot tables. |
| [events_and_zones.md](references/events_and_zones.md) | MES Events vs RivalAI Triggers, boolean master gates, zero-stripping bug, dynamic zones, Event Templates & TemplateGroups (lifecycle, limits, Missions), contract-block pairing. |
| [economy_and_stores.md](references/economy_and_stores.md) | Store grid sales (MES store items + `[MES Store]`), purchase spawn placement, icons, automated store refresh. |
| [third_party_integrations.md](references/third_party_integrations.md) | WeaponCore (800m clamp, range desync, lead prediction, NPC handicaps, flares, weapon setup matrix), Defense Shields, AiEnabled, Water Mod. |
| [diagnostics_and_troubleshooting.md](references/diagnostics_and_troubleshooting.md) | In-game admin commands, log error signatures, sim-speed optimization, anti-clang mitigations. |
| [testing_and_debugging.md](references/testing_and_debugging.md) | Writing in-game test procedures: spawning test NPCs by spawn type, visual checks, debug messages, log triage, instrumenting local MES. |
| [sbc_xml_editing_guide.md](references/sbc_xml_editing_guide.md) | IDE setup (`*.sbc -> xml`), `<Description>` protection, encoding rules, safe formatting. |

### C. Production-Tested Examples
Annotated `.sbc` implementations based on real workshop mods:
- [role_combattype_state_machine.sbc](examples/role_combattype_state_machine.sbc): Role + CombatType state machine.
- [courier_logistics_network.sbc](examples/courier_logistics_network.sbc): Parent-child courier logistics network.
- [planetary_convoy_escort.sbc](examples/planetary_convoy_escort.sbc): Planetary convoy with event spawning and escorts.
- [automated_economy_store.sbc](examples/automated_economy_store.sbc): Automated store inventory refresh loop.
- [merchant_safezone_station.sbc](examples/merchant_safezone_station.sbc): Safezone station (`[CreateSafeZone:true]`) + wandering merchant.

---

## 2. MES Architecture & Core Mental Models

- **Events vs. Triggers**: MES Events run globally via `EventManager` (server-authoritative, no physical grid needed); RivalAI Triggers run per-grid via Remote Control blocks. **They use different tag names** — see the Tag-Name Matrix in [`events_and_zones.md`](references/events_and_zones.md) §1.A (`[Spawner:]` vs `[SpawnData:]`, singular vs plural zone lists; both use `[ChatData:]`).
- **Action Debugging**: `[DebugMessage:]` (RivalAI), `[DebugChatMessage:]`/`[DebugHudMessage:]` (Events) are for development only; ship real `[RivalAI Chat]` profiles. → [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §1.
- **ContainerTypes & Loot**: bulk vs. selective assignment (paired list counts **must match 1:1** or MES silently drops all assignments), `[MES Loot]` profiles, runtime loot swapping. → [`manipulation_and_dereliction.md`](references/manipulation_and_dereliction.md) §6.

---

## 3. SBC XML Deserialization Quirks

> [!CAUTION]
> **Hard Rules (enforced by `audit_sbc.ps1`)**:
> 1. **One `<SubtypeId>` per `<Id>` block** — extra SubtypeIds are silently discarded; the profile fails to load.
> 2. **One `<Id>` per `<Prefab>` block** — duplicates register the prefab under the wrong Subtype.
> 3. **Never put XML comments inside `<Description>`** — `ReadElementString()` throws `XmlException` and aborts loading the entire mod. Use `[//Comment]` instead.
> 4. **UTF-8 encoding only** — UTF-16 or legacy-codepage saves fail the deserializer.
> 5. **No empty `.sbc` files** — a 0-byte or whitespace-only file throws `Root element is missing` and the whole world fails to load.

Full XML examples, formatting rules, and snippet tooling (`Format-MesSbc.ps1`, `Add-MesProfileSnippet.ps1`): [`sbc_xml_editing_guide.md`](references/sbc_xml_editing_guide.md).

---

## 4. Boolean Master Gates (Events and RivalAI Actions)

> [!CAUTION]
> **[HARD]** Both `[MES Event Action]` and `[RivalAI Action]` run a block of child parameters only when its boolean gate is `true`: `[ChangeCounters:true]` + `[SetCounters:]`, `[SpawnEncounter:true]` + `[SpawnData:]`/`[Spawner:]`, `[UseChatBroadcast:true]` + `[ChatData:]`, `[ChangeAutopilotProfile:true]` + `[AutopilotProfile:]`. A child without its gate is silently skipped. Triggers, conditions and spawns need `[UseTrigger:true]`/`[UseConditions:true]`/`[UseSpawn:true]`.

Event gate tables: [`events_and_zones.md`](references/events_and_zones.md) §2; RivalAI action tags: [`profiles_and_tags.md`](references/profiles_and_tags.md) §2C.

---

## 5. The Zero-Stripping Bug (`TagParse.cs`)

**[HARD]** MES integer-list parsers strip all `0` values unless called with `preserveZero: true`. `[CustomCountersTargets:0]` becomes an empty list → `Counter Names and Targets List Counts Don't Match`. Workaround: use `-1` with `[CounterCompareTypes:LessOrEqual]` / `[Greater]`. Full bugged-tag list: [`events_and_zones.md`](references/events_and_zones.md) §3.

---

## 6. Token Matrix & Scope (`IdsReplacer.cs`)

**[HARD]** `{Faction}`, `{SpawnGroupName}`, `{Position}`, custom string/counter tokens resolve **only in RivalAI Grid Triggers** (MES Events pass `npcData = null`). Event chat replaces only `{PlayerName}`/`{GPS}`; one exception: an Event `[SpawnEncounter:true]` replaces `{Faction}` in the `[SpawnGroups:]` of the spawner `[SpawnData:]` names, from `[SpawnFactionTags:]`. Tokens in profile SubtypeIds (`[Actions:]`, `[Triggers:]`, etc.) **never resolve**.

**[HARD]** A separate string-**Tag** broadcast system (`[Tags:Value]` + `[ManuallyActivatedTriggerTags:]`/`[EnableTriggerTags:]`/`[ToggleEventTags:]`/etc.) lets one Action act on every Trigger/Event declaring a matching tag. Trigger and Event tags are separate pools, and it reaches only Triggers on that grid's Behavior.

Full token table, rules, and Tag broadcast system: [`profiles_and_tags.md`](references/profiles_and_tags.md) §5-6.

---

## 7. Verified Engine Pitfalls & Workarounds

- **[HARD] Turret 800m Default Clamp**: ranges clamp to 800m on spawn; use `[SetWeaponsToMaxRange:true]`. → [`third_party_integrations.md`](references/third_party_integrations.md)
- **[HARD] Store grid sales**: an MES store sells prefabs from its store-items file (always quantity 1); `GridsForSale`/`Builder` is only for Keen-generated stations. → [`economy_and_stores.md`](references/economy_and_stores.md)
- **[HARD] `[Type:WaypointNear]`/`[Type:WaypointFar]` stall all NPC AI** off a CargoShip (unchecked waypoint index); use `[Type:BehaviorTriggerA]` or `[Type:Position]`. → [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §4.4
- **[HARD] `[Type:InsideZone]` vs `[Type:InsideActiveZone]`**: `InsideZone` is `true` even for deactivated zones — use the Active variant. → [`events_and_zones.md`](references/events_and_zones.md) §4
- **[HARD] Zones match by `[PublicName:]`**, never `[Name:]`; change types are `Set/Add/Subtract/Multiply/Divide`. Zone bool/counter actions and KPLs: MES 2.74.04+. → [`events_and_zones.md`](references/events_and_zones.md) §4
- **[HARD] Dereliction Percentage Gating**: percentages ignored without `[UseSeparatePercentages:true]`. → [`manipulation_and_dereliction.md`](references/manipulation_and_dereliction.md) §3
- **[HARD] Weapon Randomizer Public Definition**: non-public weapon definitions skipped unless `<Public>true</Public>`. → [`manipulation_and_dereliction.md`](references/manipulation_and_dereliction.md) §2
- **[HARD] Faction Resolution Drop**: non-existent or misspelled faction tag silently rejects spawn with 0% rate (`Could Not Get Valid NPC Faction`) → [`spawning_and_conditions.md`](references/spawning_and_conditions.md) §6
- **[HARD] Waypoints/Commands/Timers**: `RelativeRandom` follows the grid (use `EntityRandom`); random waypoints ignore water; replies beat `EnableTriggers`; `CommandFromParent` fixed in MES `0900b20`; cooldowns re-roll and persist. → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §5, §7, §8
- **[HARD] `MaxVelocityAngleForSpeedControl`**: default 5 overshoots moving waypoints; use 90. Above 90 is safe only on MES 2.75.00+ (before, the brake could fling a grid away from its waypoint). → [`aircraft_behaviors_and_tuning.md`](references/aircraft_behaviors_and_tuning.md) §1
- **[HARD] Target triggers (master after 2.75.01)**: `TargetFar` + `[AllowTargetFarWithoutTarget:true]` fires once the target is gone, and every `LostTarget`/`AcquiredTarget` trigger sees the edge; older builds: first trigger only, use a `NoTarget` timer. → [`aircraft_behaviors_and_tuning.md`](references/aircraft_behaviors_and_tuning.md) §2
- **[HARD] Escort slots**: one `[EscortOffsets:]` entry = one escort per behavior init, never freed while it lives; a refused request gets no reply; Escort Retreat is one-way. → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §3D
- **[HARD] WeaponCore fixed guns ignore MES on "Auto (AI Controlled)"**: save them on **Mouse Control** in the prefab (`scripts/wc_shootmode.py`); **[SOFT]** relax `[WeaponMaxAngleFromTarget]` to 8°–12°. → [`third_party_integrations.md`](references/third_party_integrations.md) §1C
- **[HARD] WC2 flares invisible to MES**: `[UseAntiSmartWeapons]` only sees WC1 `AntiSmart`. Use a self-tracking fixed flare with `LockedSmartOnly` off (status: GVK-Settings #695/#696). → [`third_party_integrations.md`](references/third_party_integrations.md) §1F
- **[HARD] Dialogue banks**: a bank's chat profile is ONE object shared by every grid on it (`MaxChats`, `MinTime`/`MaxTime`, first author name are server-wide), and the bank is chosen per behavior, never per `{Faction}`. → [`dialogue_and_chat.md`](references/dialogue_and_chat.md)
- **[HARD] `[Type:DespawnMES]` needs `[DespawnTypeFromSpawner:Any]`** (or an exact source string), else it never fires; a despawn action's delayed command is dropped. → [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §9
- **[HARD] `[ContractBlocks:]`/`[ContractBlockProfiles:]` pair by index** (stops at the shorter list); template event instances are never removed automatically. → [`events_and_zones.md`](references/events_and_zones.md) §5D-F
- **[HARD] Silent-ignore traps**: spawn groups need the `[Modular Encounters SpawnGroup]` header; `[RivalAI Target]` does nothing without `[UseCustomTargeting:true]`; dereliction needs `[UseGridDereliction:true]` + a `[Blocks:]` list; `[Type:HealthPercentage]` fires at or *above* the threshold; `[Type:Damage]` needs `[DamageTypes:Any]`; `[Triggers:A,B]` is one name (one tag per profile). → [`spawning_and_conditions.md`](references/spawning_and_conditions.md) §2, [`behaviors_and_autopilot.md`](references/behaviors_and_autopilot.md) §4
- **[SOFT] Anti-Clang Aircraft Force-Despawn**: force-despawn disabled aircraft to avoid falling-airframe Havok loops. → [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §5

---

## 8. Tooling & Diagnostics

### A. Skill Scripts
Run from the skill root: Python as `uv run scripts/<name>.py` (`pyproject.toml` ships; no venv), PowerShell as `powershell -ExecutionPolicy Bypass -File scripts/<name>.ps1` (audits take `-Path <mod Data dir>`). Inside a mod project use its `run-mes-audit.ps1 -Audit sbc|tags|refs|prefabs|unknown|wc` shim. The scripts live in the skill, so never search the mod directory for them.

**Before MES work, run `check_mes_sync.py`**: it compares `scripts/mes_tag_cache.json` with the installed MES source (`%AppData%\SpaceEngineers\Mods\Modular-Encounters-Systems`) and lists the MES commits since the cache. On drift, `Update-MesSkill.ps1` rebuilds the cache and re-runs the audits.

| Tool | Purpose (key arguments) |
| :--- | :--- |
| `query_mes_tags.py` | Tag, data-type and master-gate lookup (`--tag Zone`) |
| `check_mes_sync.py` | Tag cache vs. installed MES drift |
| `Update-MesSkill.ps1` | Maintainer sync: cache rebuild, audits of examples/scaffolds, global mirror, SKILL.md size gate |
| `audit_unknown_tags.py` | Tags, headers and trigger types MES does not parse (`<ModData>`) |
| `wc_shootmode.py` | WeaponCore shoot mode: `list`/`classify`/`audit` prefabs, set Mouse Control |
| `Format-MesSbc.ps1` | XML formatting that protects `<Description>` |
| `Add-MesProfileSnippet.ps1` | Safe `EntityComponent` injection (`-TargetFile`, `-SnippetFile`) |
| `audit_sbc.ps1` | Deserializer hazards (dup SubtypeIds, illegal comments, encoding, empty files) |
| `audit_mes_tags.ps1` | Semantic linter (master gates, zero-stripping, faction validation) |
| `audit_mes_references.ps1` | Cross-file profile references (`-WarnOrphans -SkipPrefabs`) |
| `audit_prefabs.ps1` | Prefab SubtypeId vs filename; stale `.sbcB5` purge (`-CleanStaleB5`) |
| `New-MesProfile.ps1` | Scaffolding (`-Pattern -ModPrefix -Name -Faction`): `DefendedWreck`, `ConvoyLeaderEscort`, `DynamicZoneLadder`, `StoreGrid`, `DynamicStateNpc`, `PlanetaryInstallation`, `CombatDrone`, `ReinforcementNetwork`, `BossEncounter` |

### B. In-Game Diagnostics & Agent Troubleshooting Protocol
**Write test procedures per [`testing_and_debugging.md`](references/testing_and_debugging.md)**: spawn the NPC with `/MES.Spawn.<Type>.<SpawnGroup>` (its conditions need that spawn type; never paste a blueprint), visual checks first (`/MES.Debug.DrawPaths`, `/MES.IGGB`, `/MES.Debug.ShowAllZones`), then `[DebugMessage:]`, then logs, and only last debug lines in the local MES copy. Only steps and checks a player can actually do and see.

When visual checks and debug messages don't explain it, have the user enable logging (`/MES.SpawnDebug.SpawnGroup.true` + `/MES.SpawnDebug.Spawning.true`; `/MES.BehaviorDebug.Trigger.true` + `.Condition.true` + `.Action.true`), copy each buffer with its type (`/MES.IGLSD.SpawnGroup`; `/MES.IGLBD.Trigger`, `.Condition`, `.Action`; the bare command fails), and for a grid's AI state `/MES.Info.GetGridBehavior` (`/MES.IGGB`). For intermittent issues append `.GameLog.true` and read `%AppData%\SpaceEngineers\SpaceEngineers*.log` directly. Full command list: [`diagnostics_and_troubleshooting.md`](references/diagnostics_and_troubleshooting.md) §2-3.
